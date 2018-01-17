
# Export k8s resources

in: kubectl + kubeconfig configured
out: folder of yaml files

* kubectl export?

## Get volume info from k8s

in: kubectl + kubeconfig configured
out: list of VHD paths

* Get Pods (and/or Deployments/ReplicationControllers/etc)
* Get PersistentVolumeClaims
* Get PersistentVolumes
* Get VHD paths

## Create new ACS/AKS cluster

in: az configured
out: new cluster created, RG name for new cluster (dynamically created for RPv2 & AKS)

* Create RG for target cluster
* az acs/aks create

## Convert VHD to managed disks

in: az configured, list of VHDs, target RG
out: managed disks created in target RG

* Warning: Stop disk writes OR sync later
* Create blob snapshot of VHDs
* Detect region move (based on VHD storage acct and target RG name)
  * Create dynamically named storage account to copy blob (if moving regions)
  * Copy snapshot to new blob (if moving regions)
  * Copy blob to another region (if moving regions)
* Create managed disks from snapshot (or copied blob if moving regions) in new RG
* Cleanup temp files (copied blob if moving regions, remove snapshots)

## Deploy k8s to new cluster

in: kubectl + kubeconfig for new cluster, yaml folder path
out: apps running on new cluster, next steps

* Modify YAML to use managed disks
  * Create PV for managed disk (if needed)
  * Add label to PVs
  * Add selector to PVCs
* kubectl apply yaml files
* Show info for next steps:
  * Sync data from VHD (only if writes were not stopped)
  * Point traffic to new cluster
  * Cleanup steps (snapshots, old vhd's, etc)