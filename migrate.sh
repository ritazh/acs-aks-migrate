#!/bin/bash
#
echo $(date +"%F %T%z") "- Starting script migrate.sh"

# Get values for this script
echo "AZURE_SUBSCRIPTION_ID: $AZURE_SUBSCRIPTION_ID"
echo "AZURE_TENANT_ID: $AZURE_TENANT_ID"
echo "AZURE_CLIENT_ID: $AZURE_CLIENT_ID"
echo "AZURE_CLIENT_SECRET: $AZURE_CLIENT_SECRET"
echo "DESTINATION_CLUSTERNAME: $DESTINATION_CLUSTERNAME"
echo "DESTINATION_ACS_AKS_RESOURCEGROUP: $DESTINATION_ACS_AKS_RESOURCEGROUP"
echo "DESTINATION_CLUSTERTYPE: $DESTINATION_CLUSTERTYPE"

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

if [ -z "$DESTINATION_ACS_AKS_RESOURCEGROUP" ]; then
  echo "Error: Missing env var for DESTINATION_ACS_AKS_RESOURCEGROUP"
  exit 0
fi

if [ -z "$DESTINATION_CLUSTERTYPE" ]; then
  echo "Error: Missing env var for DESTINATION_CLUSTERTYPE"
  exit 0
fi

if [ -z "$SOURCEKUBECONFIGPATH" ]; then
  echo "Error: Missing env var for SOURCEKUBECONFIGPATH"
  exit 0
fi

if [ -f $SSHKEY_FILEPATH ]; then
  echo "ssh key $SSHKEY_FILEPATH for migration already exists...skip creating ssh key"
else
  echo "Generating new ssh key $SSHKEY_FILEPATH"
  ssh-keygen -t rsa -b 4096 -C "acs@migrate.com" -f $SSHKEY_FILEPATH
fi

DESTINATION_RESOURCEGROUP_REGION=`az group show -n $DESTINATION_ACS_AKS_RESOURCEGROUP --query location -o tsv`
if [ ! $DESTINATION_RESOURCEGROUP_REGION ]; then
  echo "Destination resource group ($DESTINATION_ACS_AKS_RESOURCEGROUP) not found"
  exit 1
fi

if [ $DESTINATION_CLUSTERTYPE == "acs" ]; then
  EXIST=$(az acs list -g $DESTINATION_ACS_AKS_RESOURCEGROUP | grep $DESTINATION_CLUSTERNAME)
  if [ -z "$EXIST" ]; then
    echo "Creating new destination cluster $DESTINATION_CLUSTERNAME with premium managed disks "
    az acs create -g $DESTINATION_ACS_AKS_RESOURCEGROUP -n $DESTINATION_CLUSTERNAME --orchestrator-type Kubernetes --agent-count 2 --agent-osdisk-size 100 --agent-vm-size Standard_DS2_v2 --agent-storage-profile ManagedDisks --master-storage-profile ManagedDisks --ssh-key-value $SSHKEY_FILEPATH --dns-prefix azure-$DESTINATION_CLUSTERNAME --location $DESTINATION_RESOURCEGROUP_REGION --service-principal $AZURE_CLIENT_ID --client-secret $AZURE_CLIENT_SECRET
  else
    echo "Cluster $DESTINATION_CLUSTERNAME already exists"
  fi
  DESTINATION_RESOURCEGROUP=${DESTINATION_ACS_AKS_RESOURCEGROUP}_${DESTINATION_CLUSTERNAME}_${DESTINATION_RESOURCEGROUP_REGION}
else
  if [ $DESTINATION_CLUSTERTYPE == "aks" ]; then
    EXIST=$(az aks list -g $DESTINATION_ACS_AKS_RESOURCEGROUP | grep $DESTINATION_CLUSTERNAME)
    if [ -z "$EXIST" ]; then
      echo "Creating new destination cluster $DESTINATION_CLUSTERNAME with premium managed disks "
      az aks create -g $DESTINATION_ACS_AKS_RESOURCEGROUP -n $DESTINATION_CLUSTERNAME -l $DESTINATION_RESOURCEGROUP_REGION --node-osdisk-size 100 --node-vm-size Standard_DS2_v2 --ssh-key-value $SSHKEY_FILEPATH --service-principal $AZURE_CLIENT_ID --client-secret $AZURE_CLIENT_SECRET
    else
      echo "Cluster $DESTINATION_CLUSTERNAME already exists"
    fi
    DESTINATION_RESOURCEGROUP=MC_${DESTINATION_ACS_AKS_RESOURCEGROUP}_${DESTINATION_CLUSTERNAME}_${DESTINATION_RESOURCEGROUP_REGION}
  else
    echo "Cluster type $DESTINATION_CLUSTERTYPE is not valid. "
    exit 0
  fi
fi

export KUBECONFIG=$SOURCEKUBECONFIGPATH

echo "DESTINATION_RESOURCEGROUP: $DESTINATION_RESOURCEGROUP"

DISK_URIS=$(kubectl get pv -o json | jq -r '.items[].spec.azureDisk.diskURI' | grep http)

bash migrateVhdsToManagedDisks.sh "$DISK_URIS" $DESTINATION_RESOURCEGROUP "output.log"

echo $(date +"%F %T%z") " - Script complete"
