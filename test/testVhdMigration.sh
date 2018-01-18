# RG for ACS RPv1 cluster
az group create -n hack-acs-rpv1 -l eastus
az acs create -n rpv1 -g hack-acs-rpv1 -t Kubernetes --no-wait

# RG for ACS RPv2 cluster
az group create -n hack-acs-rpv2 -l westus2
az acs create -n rpv2 -g hack-acs-rpv2 -t Kubernetes --agent-osdisk-size 100 --master-storage-profile ManagedDisks --agent-storage-profile ManagedDisks --no-wait

./migrateVhdsToManagedDisks.sh "$DISK_URIS" hack-acs-rpv2_rpv2_westus2 out.txt