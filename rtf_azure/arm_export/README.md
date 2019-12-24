# Instructions

This directory contains the scripts used to provision Runtime Fabric on your Azure subscription.
Navigate to [Install Runtime Fabric on Azure](https://docs.mulesoft.com/anypoint-runtime-fabric/v/latest/install-azure) documentation for instructions.

# Contents
* *ARM-template-dev.template* - an Azure Resource Manager Template for generating a development configuration of Runtime Fabric. It includes 1 controller VM (2 cores, 8 GiB memory), and 2 worker VMs (2 cores, 16 GiB memory).
* *ARM-template-prod.template* - an Azure Resource Manager Template for generating a production configuration of Runtime Fabric. It includes 3 controller VMs (2 cores, 8 GiB memory), and 3 worker VMs (2 cores, 16 GiB memory).
* *generate-templates.sh* - a script to embed the Mule License digest into the startup script which runs after each VM is provisioned. This script outputs the complete versions of the `dev` and `prod` ARM templates as JSON files.

## Deploying a cluster on Azure

* Run `generate-templates.sh` first with the `RTF_MULE_LICENSE` environment variable set.
* On the Azure portal: type in the search bar `Deploy a custom template`
* Hit `Build your own template in the editor`
* Hit `Load file` and select the generated template (eg `ARM-template-dev.json`)
* Click `Save`
* Specify the required parameters, and hit `Purchase`

### Required parameters

* `publicKey`: Your public key to SSH into the nodes
* `anypointActivationData`: Runtime Fabric activation data (eg `NzdlMzU1YTktMzAxMC00OGE0LWJlMGQtMDd...`)
