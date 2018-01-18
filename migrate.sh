#!/bin/bash
#
echo $(date +"%F %T%z") "- Starting script migrate.sh"

# Get values for this script
echo "AZURE_SUBSCRIPTION_ID: $AZURE_SUBSCRIPTION_ID"
echo "AZURE_TENANT_ID: $AZURE_TENANT_ID"
echo "AZURE_CLIENT_ID: $AZURE_CLIENT_ID"
echo "AZURE_CLIENT_SECRET: $AZURE_CLIENT_SECRET"
echo "DESTINATION_CLUSTERNAME: $DESTINATION_CLUSTERNAME"
echo "DESTINATION_ACS_RESOURCEGROUP: $DESTINATION_ACS_RESOURCEGROUP"
echo "DESTINATION_STORAGEACCOUNT: $DESTINATION_STORAGEACCOUNT"
echo "DESTINATION_STORAGEACCOUNT_CONTAINER: $DESTINATION_STORAGEACCOUNT_CONTAINER"
echo "DESTINATION_MANAGED_DISK: $DESTINATION_MANAGED_DISK"
echo "SOURCE_BLOB: $SOURCE_BLOB"
echo "SOURCE_STORAGEACCOUNT_CONTAINER: $SOURCE_STORAGEACCOUNT_CONTAINER"
#echo "SOURCE_SNAPSHOT: $SOURCE_SNAPSHOT"
echo "SOURCE_STORAGEACCOUNT: $SOURCE_STORAGEACCOUNT"
echo "SOURCE_STORAGEACCOUNT_KEY: $SOURCE_STORAGEACCOUNT_KEY"

SSHKEY_FILEPATH=~/.ssh/acsmigrate

if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
  echo "Error: Missing env var for AZURE_SUBSCRIPTION_ID"
  exit 0
fi

if [ -z "$AZURE_TENANT_ID" ]; then
  echo "Error: Missing env var for AZURE_TENANT_ID"
  exit 0
fi

if [ -z "$AZURE_CLIENT_ID" ]; then
  echo "Error: Missing env var for AZURE_CLIENT_ID"
  exit 0
fi

if [ -z "$AZURE_CLIENT_SECRET" ]; then
  echo "Error: Missing env var for AZURE_CLIENT_SECRET"
  exit 0
fi

if [ -z "$DESTINATION_CLUSTERNAME" ]; then
  echo "Error: Missing env var for DESTINATION_CLUSTERNAME"
  exit 0
fi

if [ -z "$DESTINATION_ACS_RESOURCEGROUP" ]; then
  echo "Error: Missing env var for DESTINATION_ACS_RESOURCEGROUP"
  exit 0
fi

if [ -z "$DESTINATION_STORAGEACCOUNT" ]; then
  echo "Error: Missing env var for DESTINATION_STORAGEACCOUNT"
  exit 0
fi

if [ -z "$DESTINATION_STORAGEACCOUNT_CONTAINER" ]; then
  echo "Error: Missing env var for DESTINATION_STORAGEACCOUNT_CONTAINER"
  exit 0
fi

if [ -z "$DESTINATION_MANAGED_DISK" ]; then
  echo "Error: Missing env var for DESTINATION_MANAGED_DISK"
  exit 0
fi

if [ -z "$SOURCE_BLOB" ]; then
  echo "Error: Missing env var for SOURCE_BLOB"
  exit 0
fi

if [ -z "$SOURCE_STORAGEACCOUNT_CONTAINER" ]; then
  echo "Error: Missing env var for SOURCE_STORAGEACCOUNT_CONTAINER"
  exit 0
fi

# if [ -z "$SOURCE_SNAPSHOT" ]; then
#   echo "Error: Missing env var for SOURCE_SNAPSHOT"
#   exit 0
# fi

if [ -z "$SOURCE_STORAGEACCOUNT" ]; then
  echo "Error: Missing env var for SOURCE_STORAGEACCOUNT"
  exit 0
fi

if [ -z "$SOURCE_STORAGEACCOUNT_KEY" ]; then
  echo "Error: Missing env var for SOURCE_STORAGEACCOUNT_KEY"
  exit 0
fi

if [ -f $SSHKEY_FILEPATH ]; then
  echo "ssh key $SSHKEY_FILEPATH for migration already exists...skip creating ssh key"
else
  echo "Generating new ssh key $SSHKEY_FILEPATH"
  ssh-keygen -t rsa -b 4096 -C "acs@migrate.com" -f $SSHKEY_FILEPATH
fi

EXIST=$(az acs list -g $DESTINATION_ACS_RESOURCEGROUP | grep $DESTINATION_CLUSTERNAME)
if [ -z $EXIST ]; then
  echo "Creating new destination cluster $DESTINATION_CLUSTERNAME with premium managed disks "
  az acs create -g $DESTINATION_ACS_RESOURCEGROUP -n $DESTINATION_CLUSTERNAME --orchestrator-type Kubernetes --agent-count 2 --agent-osdisk-size 100 --agent-vm-size Standard_DS2_v2 --agent-storage-profile ManagedDisks --master-storage-profile ManagedDisks --ssh-key-value $SSHKEY_FILEPATH --dns-prefix azure-$DESTINATION_CLUSTERNAME --location $DESTINATION_CLUSTERNAME_LOCATION --service-principal $AZURE_CLIENT_ID --client-secret $AZURE_CLIENT_SECRET
else
  echo "Cluster $DESTINATION_CLUSTERNAME already exists"
fi

DESTINATION_RESOURCEGROUP='$DESTINATION_ACS_RESOURCEGROUP_$DESTINATION_CLUSTERNAME_$DESTINATION_CLUSTERNAME_LOCATION'
# Assuming KUBECONFIG is set to source cluster
DISK_URIS=$(kubectl get pv -o json | jq -r '.items[].spec.azureDisk.diskURI' | grep http)

bash migrateVhdsToManagedDisks.sh "$DISK_URIS" $DESTINATION_RESOURCEGROUP "output.log"

echo $(date +"%F %T%z") " - Script complete"
