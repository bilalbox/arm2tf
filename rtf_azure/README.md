# arm2tf
ARM to Terraform template conversions. Tested with **terraform v0.12**

For details on Runtime Fabric installation being automated with this template, please see: https://docs.mulesoft.com/runtime-fabric/latest/install-manual

Make sure to set the following ENV VARs to authenticate with Azure:
```bash
export TF_VAR_subscription_id=""
export TF_VAR_client_id="" 
export TF_VAR_client_secret="" 
export TF_VAR_tenant_id=""
```
- For details on where to derive these values for Azure authentication, please see: https://www.terraform.io/docs/providers/azurerm/guides/service_principal_client_secret.html


Also set the following environment variables for connectivity, authentication, and licensing for the RTF cluster nodes:

```bash
export TF_VAR_ssh_key=""    # your public key data, e.g. the one stored at ~/.ssh/id_rsa.pub
export TF_VAR_controller_ips="172.31.3.7"
export TF_VAR_worker_ips="172.31.3.8 172.31.3.9"
export TF_VAR_activation_data=""
export TF_VAR_mule_license=""
```

- For details on RTF activation data and licenses, please see: https://docs.mulesoft.com/runtime-fabric/latest/install-manual


In general, always run a `terraform plan` before `terraform apply`...and don't forget to clean up with a `terraform destroy`!
