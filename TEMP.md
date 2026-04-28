# Temporary Notes

Kubernetes `PersistentVolume.spec.hostPath.path` is immutable after the PV is created. After moving the host folders and
applying these manifest path changes, the affected PV/PVC pairs may need to be deleted and recreated so the cluster uses
the new host paths under `/mnt/userdata-clusterfiles/k3s-volumes` and `/mnt/twindrives-clusterfiles/k3s-volumes`.

## Storage Path Change

The repo manifests have been updated so persistent storage points at these roots:

- `/mnt/userdata-clusterfiles/k3s-volumes`: normal app/user data
- `/mnt/twindrives-clusterfiles/k3s-volumes`: `storage-media`, `transmission`, and `monero`

The corrected hostPath values are:

- `chat-data`: `/mnt/userdata-clusterfiles/k3s-volumes/chat`
- `gitlab-gitaly-default`: `/mnt/userdata-clusterfiles/k3s-volumes/storage-code/gitlab`
- `gitlab-minio-data`: `/mnt/userdata-clusterfiles/k3s-volumes/gitlab-minio`
- `gitlab-redis-data`: `/mnt/userdata-clusterfiles/k3s-volumes/gitlab-redis`
- `jellyfin-config`: `/mnt/userdata-clusterfiles/k3s-volumes/jellyfin-config`
- `jellyfin-media`: `/mnt/twindrives-clusterfiles/k3s-volumes/storage-media/media`
- `monero-data`: `/mnt/twindrives-clusterfiles/k3s-volumes/monero`
- `observability-grafana-data`: `/mnt/userdata-clusterfiles/k3s-volumes/observability-grafana`
- `observability-loki-data`: `/mnt/userdata-clusterfiles/k3s-volumes/observability-loki`
- `postgres-data`: `/mnt/userdata-clusterfiles/k3s-volumes/postgres`
- `transmission-data`: `/mnt/twindrives-clusterfiles/k3s-volumes/transmission`
- `transmission-incoming`: `/mnt/twindrives-clusterfiles/k3s-volumes/storage-media/media/incoming`

## What Was Done

- Local repo commits were made for the storage path move, including a follow-up commit restoring the `k3s-volumes`
  path segment after the real mounted paths were confirmed.
- The local branch is ahead of `origin/main` by 2 commits. Push failed from this environment because GitHub DNS/network
  resolution was unavailable here.
- Live PV/PVC objects were recreated so the cluster uses the corrected hostPath values above.
- The last successful live check showed all relevant PVCs were `Bound` to the corrected PVs.
- Flux Kustomizations and the GitLab/Grafana/Loki HelmReleases were suspended while live PVs were repaired, to prevent
  old Git state from reconciling the immutable PV paths back.
- `postgres`, `jellyfin`, `transmission`, `loki`, and `gitlab-minio` were brought back up in the live cluster.

## Still To Do

- Push the 2 local commits to `origin/main` before resuming Flux. Do not resume Flux while the cluster can still see the
  old Git revision, or it may fight the live PV changes.
- Recreate or align the missing Postgres roles/databases for `chat` and `grafana` from their Kubernetes secrets, then
  restart those deployments.
- Diagnose and fix the remaining GitLab `redis` and `gitaly` pods. The last logs showed Redis could not open/create its
  AOF `appendonlydir`; Gitaly was crash-looping without a clear fatal message in the log tail.
- After GitLab Redis and Gitaly are healthy, scale GitLab web-facing/background deployments back up if they are still at
  zero replicas: `gitlab-webservice-default`, `gitlab-sidekiq-all-in-1-v2`, and `gitlab-gitlab-shell`.
- Once the pushed Git revision contains these path changes and the live cluster is stable, resume Flux and the suspended
  HelmReleases.
