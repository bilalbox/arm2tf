
output "controller_connection_details" {
  description = "Connect to controller(s) by using SSH"
  value = [
      for fqdn in azurerm_public_ip.rtf-pip-controller[*].fqdn :
      "ssh cka-admin@${fqdn}"
  ]
}

output "controller_private_ips" {
  description = "Private IP address of controller(s)"
  value = [
      for ip in azurerm_network_interface.rtf-nic-controller[*].ip_configuration[0].private_ip_address :
      "${ip}"
  ]
}

output "worker_connection_details" {
  description = "Connect to worker(s) by using SSH"
  value = [
      for fqdn in azurerm_public_ip.rtf-pip-worker[*].fqdn :
      "ssh cka-admin@${fqdn}"
  ]
}

output "worker_private_ips" {
  description = "Private IP address of worker(s)"
  value = [
      for ip in azurerm_network_interface.rtf-nic-worker[*].ip_configuration[0].private_ip_address :
      "${ip}"
  ]
}
