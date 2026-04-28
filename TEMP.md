# Temporary Notes

Kubernetes `PersistentVolume.spec.hostPath.path` is immutable after the PV is created. After moving the host folders and
applying these manifest path changes, the affected PV/PVC pairs may need to be deleted and recreated so the cluster uses
the new host paths under `/mnt/userdata-clusterfiles/k3s-volumes` and `/mnt/twindrives-clusterfiles/k3s-volumes`.
