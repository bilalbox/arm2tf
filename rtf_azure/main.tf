provider "azurerm" {
    subscription_id = var.subscription_id
    client_id       = var.client_id
    client_secret   = var.client_secret
    tenant_id       = var.tenant_id
    version         = "=1.39.0"
}

resource "azurerm_resource_group" "rtf" {
  name     = var.resource_group
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.virtual_network_name
  location            = azurerm_resource_group.rtf.location
  address_space       = [var.virtualNetworkCIDR]
  resource_group_name = azurerm_resource_group.rtf.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.rtf.name
  address_prefix       = var.virtualNetworkSubnet
}

resource "azurerm_network_security_group" "rtf-sg" {
  name                = "${var.prefix}-sg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rtf.name

  security_rule {
    name                       = "HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = var.source_network
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.source_network
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "rtf-nic-controller" {
  count                     = var.cluster_size.controllers
  name                      = "${var.prefix}-nic-controller-${count.index}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rtf.name
  network_security_group_id = azurerm_network_security_group.rtf-sg.id

  ip_configuration {
    name                          = "${var.prefix}-ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.virtualNetworkSubnet, 7)
    public_ip_address_id          = azurerm_public_ip.rtf-pip-controller[count.index].id
  }
}

resource "azurerm_public_ip" "rtf-pip-controller" {
  count               = var.cluster_size.controllers
  name                = "${var.prefix}-controller-pip-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rtf.name
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.prefix}-controller-${count.index}"
}

resource "azurerm_network_interface" "rtf-nic-worker" {
  count                     = var.cluster_size.workers
  name                      = "${var.prefix}-nic-worker-${count.index}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rtf.name
  network_security_group_id = azurerm_network_security_group.rtf-sg.id

  ip_configuration {
    name                          = "${var.prefix}-ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.virtualNetworkSubnet, 8 + count.index)
    public_ip_address_id          = azurerm_public_ip.rtf-pip-worker[count.index].id
  }
}

resource "azurerm_public_ip" "rtf-pip-worker" {
  count               = var.cluster_size.workers
  name                = "${var.prefix}-worker-pip-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rtf.name
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.prefix}-worker-${count.index}"
}

resource "azurerm_virtual_machine" "controller" {
  count               = var.cluster_size.controllers
  name                = "${var.prefix}-controller-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rtf.name
  vm_size             = var.controller_vm_size

  network_interface_ids         = [azurerm_network_interface.rtf-nic-controller[count.index].id]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  storage_os_disk {
    name              = "${var.prefix}-controller-${count.index}-os"
    managed_disk_type = "Premium_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    disk_size_gb      = "128"
  }

  storage_data_disk {
    name              = "${var.prefix}-controller-${count.index}-etcd"
    managed_disk_type = "Premium_LRS"
    caching           = "ReadWrite"
    create_option     = "Empty"
    lun               = "0"
    disk_size_gb      = "1024"
  }

  storage_data_disk {
    name              = "${var.prefix}-controller-${count.index}-docker"
    managed_disk_type = "Premium_LRS"
    caching           = "ReadWrite"
    create_option     = "Empty"
    lun               = "1"
    disk_size_gb      = "256"
  }

  os_profile {
    computer_name  = "${var.prefix}-controller-${count.index}"
    admin_username = var.admin_username
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
        path = "/home/${var.admin_username}/.ssh/authorized_keys"
        key_data = var.ssh_key 
        }
  }
  
  provisioner "file" {
    source      = "scripts/init.sh"
    destination = "/home/${var.admin_username}/init.sh"
    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa")
      host     = azurerm_public_ip.rtf-pip-controller[count.index].fqdn
    }
  }

  provisioner "remote-exec" {
    inline = [
      <<EOT
      sudo mkdir -p /opt/anypoint/runtimefabric && sudo cat > /opt/anypoint/runtimefabric/env <<EOF 
      RTF_PRIVATE_IP='${azurerm_network_interface.rtf-nic-controller[0].ip_configuration[0].private_ip_address}'
      RTF_NODE_ROLE=controller_node 
      RTF_INSTALL_ROLE=leader 
      RTF_ETCD_DEVICE=/dev/disk/azure/scsi1/lun0
      RTF_DOCKER_DEVICE=/dev/disk/azure/scsi1/lun1
      RTF_TOKEN='${var.cluster_token}' 
      RTF_NAME='runtime-fabric' 
      RTF_ACTIVATION_DATA='${var.activation_data}' 
      RTF_MULE_LICENSE='${var.mule_license}' 
      POD_NETWORK_CIDR='${var.podCIDR}' 
      SERVICE_CIDR='${var.serviceCIDR}' 
      EOF
      EOT
      ,
      "chmod +x /home/${var.admin_username}/init.sh",
      "sudo /home/${var.admin_username}/init.sh",
  ]

    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa")
      host     = azurerm_public_ip.rtf-pip-controller[count.index].fqdn
    }
  }
}

resource "azurerm_virtual_machine" "worker" {
  count               = var.cluster_size.workers
  name                = "${var.prefix}-worker-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rtf.name
  vm_size             = var.worker_vm_size

  network_interface_ids         = [azurerm_network_interface.rtf-nic-worker[count.index].id]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  storage_os_disk {
    name              = "${var.prefix}-worker-${count.index}-os"
    managed_disk_type = "Premium_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    disk_size_gb      = "128"
  }

  storage_data_disk {
    name              = "${var.prefix}-worker-${count.index}-docker"
    managed_disk_type = "Premium_LRS"
    caching           = "ReadWrite"
    create_option     = "Empty"
    lun               = "1"
    disk_size_gb      = "256"
  }

  os_profile {
    computer_name  = "${var.prefix}-worker-${count.index}"
    admin_username = var.admin_username
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
        path = "/home/${var.admin_username}/.ssh/authorized_keys"
        key_data = var.ssh_key 
        }
  }

  provisioner "file" {
    source      = "scripts/init.sh"
    destination = "/home/${var.admin_username}/init.sh"
    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa")
      host     = azurerm_public_ip.rtf-pip-worker[count.index].fqdn
    }
  }

  provisioner "remote-exec" {
    inline = [
      <<EOT
      sudo mkdir -p /opt/anypoint/runtimefabric && sudo cat > /opt/anypoint/runtimefabric/env <<EOF 
      RTF_PRIVATE_IP='${azurerm_network_interface.rtf-nic-worker[count.index].ip_configuration[0].private_ip_address}'
      RTF_NODE_ROLE=worker_node 
      RTF_INSTALL_ROLE=joiner 
      RTF_DOCKER_DEVICE=/dev/disk/azure/scsi1/lun1
      RTF_TOKEN='${var.cluster_token}' 
      RTF_INSTALLER_IP='${azurerm_network_interface.rtf-nic-controller[0].ip_configuration[0].private_ip_address}'
      EOF
      EOT
      ,
      "chmod +x /home/${var.admin_username}/init.sh",
      "sudo /home/${var.admin_username}/init.sh"
  ]

    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa")
      host     = azurerm_public_ip.rtf-pip-worker[count.index].fqdn
    }
  }
}