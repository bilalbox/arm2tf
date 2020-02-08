variable "subscription_id" {
  default = ""
}
variable "client_id" { 
  default = "" 
}

variable "client_secret" { 
  default = "" 
}

variable "tenant_id" { 
  default = "" 
}

variable "kubeadm_token" {
  default = ""
}

variable "resource_group" {
  description = "The name of your Azure Resource Group."
  default = "cka-lab-rg"
}

variable "aset_name" {
  description = "The name of the virtual machine availability set"
  default = "aset_cka_lab_controllers"
}

variable "prefix" {
  description = "This prefix will be included in the name of some resources."
  default = "cka-lab"
}

variable "cluster_size" {
  description = "Virtual machine hostname. Used for local hostname, DNS, and storage-related names."
  default = {
    masters = 1,
    workers = 2
  }
}

variable "location" {
  description = "The region where the virtual network is created."
  default = "eastasia"
}

variable "virtual_network_name" {
  description = "The name for your virtual network."
  default = "vnet"
}

variable "address_space" {
  description = "The address space that is used by the virtual network. You can supply more than one address space. Changing this forces a new resource to be created."
  default = "10.0.0.0/16"
}

variable "subnet_prefix" {
  description = "The address prefix to use for the subnet."
  default = "10.0.10.0/24"
}

variable "storage_account_tier" {
  description = "Defines the storage tier. Valid options are Standard and Premium."
  default = "Standard"
}

variable "storage_replication_type" {
  description = "Defines the replication type to use for this storage account. Valid options include LRS, GRS etc."
  default = "LRS"
}

variable "vm_size" {
  description = "Specifies the size of the virtual machine."
  default = "Standard_B2s"
}

variable "image_publisher" {
  description = "Name of the publisher of the image (az vm image list)"
  default = "Canonical"
}

variable "image_offer" {
  description = "Name of the offer (az vm image list)"
  default = "UbuntuServer"
}

variable "image_sku" {
  description = "Image SKU to apply (az vm image list)"
  default = "16.04-LTS"
}

variable "image_version" {
  description = "Version of the image to apply (az vm image list)"
  default = "latest"
}

variable "admin_username" {
  description = "Administrator user name"
  default = "cka-admin"
}

variable "ssh_key" {
  description = "SSH Public Key Data"
  default = ""
}

variable "source_network" {
  description = "Allow access from this network prefix. Defaults to '*'."
  default = "*"
}

