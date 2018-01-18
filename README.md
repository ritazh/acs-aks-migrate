# acs-aks-migrate
⚒ Script to migrate from ACS Kubernetes clusters to ACS (RP v2 [regions](https://github.com/Azure/ACS/blob/master/acs_regional_avilability) ) or AKS cluster

__USE IT AT YOUR OWN RISK - DO NOT USE IN PRODUCTION__

* Set the following environment variables

```bash
AZURE_SUBSCRIPTION_ID=
AZURE_TENANT_ID=
AZURE_CLIENT_ID=
AZURE_CLIENT_SECRET=
KUBECONFIGPATH=
DESTINATION_CLUSTERNAME=
DESTINATION_ACS_RESOURCEGROUP=
```
* Run script

```bash
bash migrate.sh
```
