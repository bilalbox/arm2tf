# arm2tf
ARM to Terraform template conversions. Tested with **terraform v0.12**

Make sure to set the following ENV VARs to authenticate with Azure:
```bash
export TF_VAR_subscription_id=""
export TF_VAR_client_id="" 
export TF_VAR_client_secret="" 
export TF_VAR_tenant_id=""
export TF_VAR_kubeadm_token=""
export TF_VAR_ssh_key=""
```



In general, always run a `terraform plan` before `terraform apply`...and don't forget to clean up with a `terraform destroy`!
