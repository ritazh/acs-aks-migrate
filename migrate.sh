#!/bin/bash
#
echo $(date +"%F %T%z") "- Starting script migrate.sh"

# Get values for this script
echo "AZURE_SUBSCRIPTION_ID: $AZURE_SUBSCRIPTION_ID"
echo "AZURE_TENANT_ID: $AZURE_TENANT_ID"
echo "AZURE_CLIENT_ID: $AZURE_CLIENT_ID"
echo "AZURE_CLIENT_SECRET: $AZURE_CLIENT_SECRET"
echo "DESTINATION_CLUSTERNAME: $DESTINATION_CLUSTERNAME"
echo "DESTINATION_RESOURCEGROUP: $DESTINATION_RESOURCEGROUP"
echo "DESTINATION_STORAGEACCOUNT: $DESTINATION_STORAGEACCOUNT"
echo "DESTINATION_STORAGEACCOUNT_CONTAINER: $DESTINATION_STORAGEACCOUNT_CONTAINER"
echo "DESTINATION_MANAGED_DISK: $DESTINATION_MANAGED_DISK"
echo "SOURCE_BLOB: $SOURCE_BLOB"
echo "SOURCE_STORAGEACCOUNT_CONTAINER: $SOURCE_STORAGEACCOUNT_CONTAINER"
#echo "SOURCE_SNAPSHOT: $SOURCE_SNAPSHOT"
echo "SOURCE_STORAGEACCOUNT: $SOURCE_STORAGEACCOUNT"
echo "SOURCE_STORAGEACCOUNT_KEY: $SOURCE_STORAGEACCOUNT_KEY"

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

if [ -z "$DESTINATION_RESOURCEGROUP" ]; then
  echo "Error: Missing env var for DESTINATION_RESOURCEGROUP"
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

echo "Generating new ssh key"
ssh-keygen -t rsa -b 4096 -C "acs@migrate.com" -f ~/.ssh/acsmigrate

echo "Creating new destination cluster $DESTINATION_CLUSTERNAME with premium managed disks "
az acs create -g $z -n $DESTINATION_CLUSTERNAME --orchestrator-type Kubernetes --agent-count 2 --agent-osdisk-size 100 --agent-vm-size Standard_DS2_v2 --agent-storage-profile ManagedDisks --master-storage-profile ManagedDisks --ssh-key-value ~/.ssh/acsmigrate --dns-prefix azure-$DESTINATION_CLUSTERNAME --location westus2 --service-principal $AZURE_CLIENT_ID --client-secret $AZURE_CLIENT_SECRET

echo "Creating storage account $DESTINATION_STORAGEACCOUNT"
az storage account create -n $DESTINATION_STORAGEACCOUNT -g '$DESTINATION_RESOURCEGROUP_$DESTINATION_RESOURCEGROUP' -l westus2 --sku Standard_LRS
DESTINATION_STORAGEACCOUNT_KEY=$(az storage account keys list -g '$DESTINATION_RESOURCEGROUP_$DESTINATION_RESOURCEGROUP' -n $DESTINATION_STORAGEACCOUNT | jq -r '.[0].value')
echo "Storage account key: $DESTINATION_STORAGEACCOUNT_KEY"

echo "Creating container $DESTINATION_STORAGEACCOUNT_CONTAINER"
az storage container create --name $DESTINATION_STORAGEACCOUNT_CONTAINER --account-key $DESTINATION_STORAGEACCOUNT_KEY --account-name $DESTINATION_STORAGEACCOUNT

echo "Creating snapshot for vhd $SOURCE_BLOB"
SOURCE_SNAPSHOT=$(az storage blob snapshot -c $SOURCE_STORAGEACCOUNT_CONTAINER -n $SOURCE_BLOB --account-name $SOURCE_STORAGEACCOUNT --account-key $SOURCE_STORAGEACCOUNT_KEY | jq -r '.snapshot')

echo "Copying vhd snapshot $SOURCE_BLOB $SOURCE_SNAPSHOT"
az storage blob copy start --source-blob $SOURCE_BLOB --source-container $SOURCE_STORAGEACCOUNT_CONTAINER --source-snapshot $SOURCE_SNAPSHOT -b $SOURCE_BLOB -c $DESTINATION_STORAGEACCOUNT_CONTAINER --source-account-name $SOURCE_STORAGEACCOUNT --source-account-key $SOURCE_STORAGEACCOUNT_KEY --account-name $DESTINATION_STORAGEACCOUNT --account-key $DESTINATION_STORAGEACCOUNT_KEY 

echo "Creating Managed Disk from vhd $SOURCE_BLOB"
az disk create -n $DESTINATION_MANAGED_DISK -g '$DESTINATION_RESOURCEGROUP_$DESTINATION_RESOURCEGROUP' --source http://$DESTINATION_STORAGEACCOUNT.blob.core.windows.net/$DESTINATION_STORAGEACCOUNT_CONTAINER/$SOURCE_BLOB

echo $(date +"%F %T%z") " - Script complete"
