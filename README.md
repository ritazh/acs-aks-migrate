# acs-aks-migrate

⚒ Script to migrate from ACS Kubernetes clusters to ACS (RP v2 [regions](https://github.com/Azure/ACS/blob/master/acs_regional_avilability)) or AKS cluster

__USE IT AT YOUR OWN RISK - DO NOT USE IN PRODUCTION__

### Usage

Set the following environment variables:

```bash
AZURE_SUBSCRIPTION_ID=
AZURE_TENANT_ID=
AZURE_CLIENT_ID=
AZURE_CLIENT_SECRET=
SOURCEKUBECONFIGPATH=
DESTINATION_CLUSTERNAME=
DESTINATION_ACS_AKS_RESOURCEGROUP=
DESTINATION_CLUSTERTYPE=acs
```
Run script

```bash
bash migrate.sh
```

You should have an `output.log` file generated in the same directory you ran migration.sh. 
Example output:

```bash
https://<SOURCE_STORAGE>.blob.core.windows.net/<SOURCE_CONTAINER>/<SOURCE_BLOB>/subscriptions/<SUBSCRIPTION>/resourceGroups/<DESTINATION_RESOURCEGROUP>/providers/Microsoft.Compute/disks/<DESTINATION_BLOB>
...

```

Update your app Helm Chart to include `enablemigration`
You can also take a look at the [sample Helm chart in this repo](https://github.com/ritazh/acs-aks-migrate/tree/master/charts) to see how to update your own app.

1. Update your deployment.yaml to conditionally mount disks depending on the `enablemigration` field in the `values.yaml` to mount the new managed disk created by the previous step OR to use the PVC to create a disk dynamically.

```yaml
      volumes:
      - name: mydisk
      {{- if .Values.enablemigration }}
        azureDisk:
          cachingMode: ReadWrite
          diskName: {{ .Values.disk.name }}
          diskURI: {{ .Values.disk.uri }}
          fsType: ext4
          kind: Managed
          readOnly: false
      {{- else }}
        persistentVolumeClaim:
          claimName: myclaim
      {{- end }}
```

2. Update your pvc.yaml to conditionally deploy only when the `enablemigration` field in the `values.yaml` is false.

```yaml
{{- if not .Values.enablemigration }}
...

{{- end }}
```

3. Update your values.yaml to set `enablemigration` to `true` to use migrated disk and set to `false` to use PVC to dynamically create disk. Set `disk` fields to the value of the new managed disk created from the previous step. You can also look in `output.log` file for the new diskURI.

```yaml
...

enablemigration: true
disk:
  name: <DESTINATION_BLOB>
  uri: https://<SOURCE_STORAGE>.blob.core.windows.net/<SOURCE_CONTAINER>/<SOURCE_BLOB>/subscriptions/<SUBSCRIPTION>/resourceGroups/<DESTINATION_RESOURCEGROUP>/providers/Microsoft.Compute/disks/<DESTINATION_BLOB>

```

### Current Features

* zero-downtime migration
* disk migration
* vhd to managed disk
* cross-region support
* snapshot support
* automate ACS, AKS cluster creation
* ssh key generation
* Support kubernetes version 1.6+

### Current Limitations

* Azure only
* manual cleanup
* PVs only, pod level disk support coming


