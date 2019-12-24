provider "azurerm" {
    subscription_id = var.subscription_id
    client_id       = var.client_id
    client_secret   = var.client_secret
    tenant_id       = var.tenant_id
    version         = "=1.39.0"
}

resource "azurerm_resource_group" "cka-lab" {
  name     = var.resource_group
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.virtual_network_name
  location            = azurerm_resource_group.cka-lab.location
  address_space       = [var.address_space]
  resource_group_name = azurerm_resource_group.cka-lab.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.cka-lab.name
  address_prefix       = var.subnet_prefix
}

resource "azurerm_network_security_group" "cka-lab-sg" {
  name                = "${var.prefix}-sg"
  location            = var.location
  resource_group_name = azurerm_resource_group.cka-lab.name

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

resource "azurerm_network_interface" "cka-lab-nic-master" {
  count                     = var.cluster_size.masters
  name                      = "${var.prefix}-nic-master-${count.index}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.cka-lab.name
  network_security_group_id = azurerm_network_security_group.cka-lab-sg.id

  ip_configuration {
    name                          = "${var.prefix}-ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.cka-lab-pip-master[count.index].id
  }
}

resource "azurerm_public_ip" "cka-lab-pip-master" {
  count               = var.cluster_size.masters
  name                = "${var.prefix}-master-pip-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.cka-lab.name
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.prefix}-master-${count.index}"
}

resource "azurerm_network_interface" "cka-lab-nic-worker" {
  count                     = var.cluster_size.workers
  name                      = "${var.prefix}-nic-worker-${count.index}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.cka-lab.name
  network_security_group_id = azurerm_network_security_group.cka-lab-sg.id

  ip_configuration {
    name                          = "${var.prefix}-ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.cka-lab-pip-worker[count.index].id
  }
}

resource "azurerm_public_ip" "cka-lab-pip-worker" {
  count               = var.cluster_size.workers
  name                = "${var.prefix}-worker-pip-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.cka-lab.name
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.prefix}-worker-${count.index}"
}

resource "azurerm_virtual_machine" "master" {
  count               = var.cluster_size.masters
  name                = "${var.prefix}-master-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.cka-lab.name
  vm_size             = var.vm_size

  network_interface_ids         = [azurerm_network_interface.cka-lab-nic-master[count.index].id]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  storage_os_disk {
    name              = "${var.prefix}-master-${count.index}-osdisk"
    managed_disk_type = "StandardSSD_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = "${var.prefix}-master-${count.index}"
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
    source      = "files/node-install.sh"
    destination = "/home/${var.admin_username}/setup.sh"
    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa")
      host     = azurerm_public_ip.cka-lab-pip-master[count.index].fqdn
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${var.admin_username}/setup.sh",
      "sudo /home/${var.admin_username}/setup.sh",
      "sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --token ${var.kubeadm_token}",
      "mkdir -p ~/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config",
      "sudo chmod a+r ~/.kube/config",
      "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
    ]

    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa")
      host     = azurerm_public_ip.cka-lab-pip-master[count.index].fqdn
    }
  }
}

resource "azurerm_virtual_machine" "worker" {
  count               = var.cluster_size.workers
  name                = "${var.prefix}-worker-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.cka-lab.name
  vm_size             = var.vm_size

  network_interface_ids         = [azurerm_network_interface.cka-lab-nic-worker[count.index].id]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  storage_os_disk {
    name              = "${var.prefix}-worker-${count.index}-osdisk"
    managed_disk_type = "StandardSSD_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
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
    source      = "files/node-install.sh"
    destination = "/home/${var.admin_username}/setup.sh"
    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa")
      host     = azurerm_public_ip.cka-lab-pip-worker[count.index].fqdn
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${var.admin_username}/setup.sh",
      "sudo /home/${var.admin_username}/setup.sh",
      "sudo kubeadm join ${azurerm_network_interface.cka-lab-nic-master[0].ip_configuration[0].private_ip_address}:6443 --token ${var.kubeadm_token} --discovery-token-unsafe-skip-ca-verification"
    ]

    connection {
      type     = "ssh"
      user     = var.admin_username
      private_key = file("~/.ssh/id_rsa")
      host     = azurerm_public_ip.cka-lab-pip-worker[count.index].fqdn
    }
  }
}