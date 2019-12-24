
output "MASTER" {
  description = "Connect to master(s) by using SSH"
  value = [
      for fqdn in azurerm_public_ip.cka-lab-pip-master[*].fqdn :
      "ssh cka-admin@${fqdn}"
  ]
}

output "WORKER" {
  description = "Connect to worker(s) by using SSH"
  value = [
      for fqdn in azurerm_public_ip.cka-lab-pip-worker[*].fqdn :
      "ssh cka-admin@${fqdn}"
  ]
}

