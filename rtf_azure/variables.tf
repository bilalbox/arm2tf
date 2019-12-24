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

variable "activation_data" {
  default = ""
}

variable "mule_license" {
  default = ""
}

variable "cluster_token" {
  default = "my-cluster-token"
}

variable "resource_group" {
  description = "The name of your Azure Resource Group."
  default     = "rtf-rg"
}

variable "prefix" {
  description = "This prefix will be included in the name of some resources."
  default     = "rtf"
}

variable "cluster_size" {
  description = "Virtual machine hostname. Used for local hostname, DNS, and storage-related names."
  default     = {
    controllers = 1,
    workers = 2
  }
}

variable "location" {
  description = "The region where the virtual network is created."
  default     = "eastasia"
}

variable "virtual_network_name" {
  description = "The name for your virtual network."
  default     = "vnet"
}

variable "virtualNetworkCIDR" {
  description = "Specifies the network address space to allocate when creating the virtual network, in CIDR notation."
  default     = "172.31.0.0/16"
}

variable "virtualNetworkSubnet" {
  description = "Specifies the subnet to create when assigning private IP addresses to the virtual network, in CIDR notation."
  default     = "172.31.3.0/28"
}

variable "serviceCIDR" {
  description = "CIDR range Kubernetes will be allocating service IPs from."
  default     = "10.100.0.0/16"
}

variable "podCIDR" {
  description = "CIDR range Kubernetes will be allocating pod IPs from."
  default     = "10.244.0.0/16"
}

variable "storage_account_tier" {
  description = "Defines the storage tier. Valid options are Standard and Premium."
  default     = "Premium"
}

variable "storage_replication_type" {
  description = "Defines the replication type to use for this storage account. Valid options include LRS, GRS etc."
  default     = "LRS"
}

variable "controller_vm_size" {
  description = "Specifies the size of the virtual machine."
  default     = "Standard_D2s_v3"
}

variable "worker_vm_size" {
  description = "Specifies the size of the virtual machine."
  default     = "Standard_E2s_v3"
}

variable "image_publisher" {
  description = "Name of the publisher of the image (az vm image list)"
  default     = "RedHat"
}

variable "image_offer" {
  description = "Name of the offer (az vm image list)"
  default     = "RHEL"
}

variable "image_sku" {
  description = "Image SKU to apply (az vm image list)"
  default     = "7-RAW"
}

variable "image_version" {
  description = "Version of the image to apply (az vm image list)"
  default     = "7.7.2019090418"
}

variable "admin_username" {
  description = "Administrator user name"
  default     = "rtf-user"
}

variable "ssh_key" {
  description = "SSH Public Key Data"
  default     = ""
}

variable "source_network" {
  description = "Allow access from this network prefix. Defaults to '*'."
  default     = "*"
}

