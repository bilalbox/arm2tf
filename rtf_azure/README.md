# arm2tf
ARM to Terraform template conversions. Tested with **terraform v0.12**

For details on Runtime Fabric installation being automated with this template, please see: https://docs.mulesoft.com/runtime-fabric/latest/install-manual

Make sure to set the following ENV VARs to authenticate with Azure, AnyPoint Platform, etc.:
```bash
export TF_VAR_subscription_id=""
export TF_VAR_client_id="" 
export TF_VAR_client_secret="" 
export TF_VAR_tenant_id=""
export TF_VAR_kubeadm_token=""
export TF_VAR_ssh_key=""
export TF_VAR_controller_ips=""
export TF_VAR_worker_ips=""
export TF_VAR_activation_data=""
export TF_VAR_mule_license=""
```

- For details on Azure authentication, please see: https://www.terraform.io/docs/providers/azurerm/guides/service_principal_client_secret.html

- For details on activation data and mule license, please see: https://docs.mulesoft.com/runtime-fabric/latest/install-manual


In general, always run a `terraform plan` before `terraform apply`...and don't forget to clean up with a `terraform destroy`!
