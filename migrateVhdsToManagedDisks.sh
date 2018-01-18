#!/bin/bash

#TODO: create named args
SOURCE_VHD_PATHS=$1
DESTINATION_RESOURCEGROUP=$2
OUTPUT_FILE_PATH=$3

echo "SOURCE_VHD_PATHS: $SOURCE_VHD_PATHS"
echo "DESTINATION_RESOURCEGROUP: $DESTINATION_RESOURCEGROUP"
echo "OUTPUT_FILE_PATH: $OUTPUT_FILE_PATH"

# Check that 'az' is configured
SUBSCRIPTION_NAME=`az account show --query name`
if [ $? == "0" ]; then
  echo "Running in $SUBSCRIPTION_NAME"
else
  echo "'az' does not have a subscription set. Do you need to run 'az login'?"
  exit 1 
fi

# Check that destination RG exists
DESTINATION_RESOURCEGROUP_REGION=`az group show -n $DESTINATION_RESOURCEGROUP --query location -o tsv`
if [ ! $DESTINATION_RESOURCEGROUP_REGION ]; then
  echo "Destination resource group ($DESTINATION_RESOURCEGROUP) not found"
  exit 1
fi

# Make sure user gets a snapshot warning & wants to proceed
echo -e "\nWARNING!\nThis script will take a snapshot of your VHDs before creating managed disks. All writes received after the snapshot is taken will remain in the VHD but will not be present in the managed disk. We recommend stopping writes, or if not possible, syncing data from the VHD to the managed disk after it has been mounted (via sftp, rsync, etc)\n"
echo -e "\nWARNING!\nIf your VHDs are in a storage account with a different region than your destination resource group, this script will copy them across a regions. This operation will incur outbound data charges\n"
read -r -p "Are you sure? [y/N] " response
if ! [[ $response =~ ^[yY]$ ]]; then
  echo "VHD migration canceled"
  exit 0
fi

# Create blob snapshot of VHDs
VHD_REGEX='https://(.*).blob.core.windows.net/(.*)/(.*)'

DISKS=($SOURCE_VHD_PATHS)
for (( i=0; i<${#DISKS[@]}; i++))
do
  VHD=${DISKS[$i]}
  if [[ $VHD =~ $VHD_REGEX ]]; then
    SOURCE_STORAGEACCOUNT=${BASH_REMATCH[1]}
    SOURCE_STORAGEACCOUNT_CONTAINER=${BASH_REMATCH[2]}
    SOURCE_BLOB=${BASH_REMATCH[3]]}
  else
    echo "Could not parse storage account information for $VHD"
    continue
  fi

  SOURCE_STORAGEACCOUNT_GROUP=$(az storage account list --query "[?name=='$SOURCE_STORAGEACCOUNT'].resourceGroup" -o tsv)
  SOURCE_STORAGEACCOUNT_KEY=$(az storage account keys list -n $SOURCE_STORAGEACCOUNT -g $SOURCE_STORAGEACCOUNT_GROUP --query '[0].value' -o tsv)
  SOURCE_STORAGEACCOUNT_REGION=$(az storage account show -n $SOURCE_STORAGEACCOUNT -g $SOURCE_STORAGEACCOUNT_GROUP --query location -o tsv)

  echo "Creating snapshot for vhd $SOURCE_BLOB"
  SOURCE_SNAPSHOT=$(az storage blob snapshot -c $SOURCE_STORAGEACCOUNT_CONTAINER -n $SOURCE_BLOB --account-name $SOURCE_STORAGEACCOUNT --account-key $SOURCE_STORAGEACCOUNT_KEY --query snapshot -o tsv)

  # Detect region move (based on VHD storage acct and target RG name)
  if [[ $SOURCE_STORAGEACCOUNT_REGION != $DESTINATION_RESOURCEGROUP_REGION ]]; then 
    MIGRATE_REGIONS=true
  fi

  # When moving between regions, we need to copy the snapshot to a storage account in the destination region
  if [ "$MIGRATE_REGIONS" = true ]; then
    echo "Migrating from $SOURCE_STORAGEACCOUNT_REGION to $DESTINATION_RESOURCEGROUP_REGION"
    
    if [ "$DESTINATION_STORAGE_ACCOUNT_CREATED" = true ]; then
      echo "Destination storage account $DESTINATION_STORAGEACCOUNT already created"
    else
      # Create dynamically named storage account to copy blob
      #TODO: allow specifying temp storage acct
      echo "Creating storage account $DESTINATION_STORAGEACCOUNT"
      DESTINATION_STORAGEACCOUNT="vhdmigration$(cat /proc/sys/kernel/random/uuid | cut -d '-' -f5)"
      az storage account create -n $DESTINATION_STORAGEACCOUNT -g $DESTINATION_RESOURCEGROUP -l $DESTINATION_RESOURCEGROUP_REGION --sku Standard_LRS
      DESTINATION_STORAGE_ACCOUNT_CREATED=true
      DESTINATION_STORAGEACCOUNT_KEY=$(az storage account keys list -g $DESTINATION_RESOURCEGROUP -n $DESTINATION_STORAGEACCOUNT --query '[0].value' -o tsv)

      DESTINATION_STORAGEACCOUNT_CONTAINER=temp
      az storage container create --name $DESTINATION_STORAGEACCOUNT_CONTAINER --account-key $DESTINATION_STORAGEACCOUNT_KEY --account-name $DESTINATION_STORAGEACCOUNT
    fi

    # Copy snapshot to new blob (if moving regions)
    echo "Copying vhd snapshot $SOURCE_BLOB $SOURCE_SNAPSHOT"
    az storage blob copy start \
      --source-account-name $SOURCE_STORAGEACCOUNT \
      --source-account-key $SOURCE_STORAGEACCOUNT_KEY \
      --source-blob $SOURCE_BLOB \
      --source-container $SOURCE_STORAGEACCOUNT_CONTAINER \
      --source-snapshot $SOURCE_SNAPSHOT \
      -b $SOURCE_BLOB \
      --account-name $DESTINATION_STORAGEACCOUNT \
      --account-key $DESTINATION_STORAGEACCOUNT_KEY \
      -c $DESTINATION_STORAGEACCOUNT_CONTAINER
    
    DESTINATION_MANAGED_DISK_SOURCE="https://$DESTINATION_STORAGEACCOUNT.blob.core.windows.net/$DESTINATION_STORAGEACCOUNT_CONTAINER/$SOURCE_BLOB"

    # Wait for blob copy to finish
    BLOB_COPY_STATUS=$(az storage blob show --account-name $DESTINATION_STORAGEACCOUNT --account-key $DESTINATION_STORAGEACCOUNT_KEY -c $DESTINATION_STORAGEACCOUNT_CONTAINER -n $SOURCE_BLOB --query 'properties.copy.status' -o tsv)
    while [ "$BLOB_COPY_STATUS" != "success" ]; do
      echo "$(date +"%F %T%z") Waiting for $SOURCE_BLOB to copy. Current status is $BLOB_COPY_STATUS"
      sleep 5
      BLOB_COPY_STATUS=$(az storage blob show --account-name $DESTINATION_STORAGEACCOUNT --account-key $DESTINATION_STORAGEACCOUNT_KEY -c $DESTINATION_STORAGEACCOUNT_CONTAINER -n $SOURCE_BLOB --query 'properties.copy.status' -o tsv)
    done
  else
    DESTINATION_MANAGED_DISK_SOURCE="https://$SOURCE_STORAGEACCOUNT.blob.core.windows.net/$SOURCE_STORAGEACCOUNT_CONTAINER/$SOURCE_BLOB?snapshot=$SOURCE_SNAPSHOT"
  fi

  # TODO: Handle disks that already exist (but possibly from an older snapshot)
  # Create managed disks from snapshot (or copied blob if moving regions) in new RG
  echo "Creating Managed Disk from vhd $SOURCE_BLOB"
  DESTINATION_MANAGED_DISK=$SOURCE_BLOB     # Name the managed disk the same as the source blob
  DESTINATION_MANAGED_DISK_ID=$(az disk create -n $DESTINATION_MANAGED_DISK -g $DESTINATION_RESOURCEGROUP --source $DESTINATION_MANAGED_DISK_SOURCE --query 'id' -o tsv)

  # Write map of VHD->managed disk to OUTPUT_FILE_PATH
  echo "$VHD:$DESTINATION_MANAGED_DISK_ID" >> $OUTPUT_FILE_PATH
done

# Cleanup temp files (copied blob if moving regions, remove snapshots)
echo "ATTENTION!\nFor safety, this script doesn't delete anything. You'll need to do some cleanup to remove the temporary resources that were created. This includes blob snapshots in the source storage account(s) and temporary vhdmigration* storage accounts"
