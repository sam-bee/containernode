# Maintenance Runbooks


## Local kubectl access

Some environments already have a default kubeconfig context set up for `containernode`. If `kubectl` falls back to
`localhost:8080` or otherwise cannot find the cluster, it may be necessary to point it at the local copy of the
`containernode` kubeconfig:

```bash
export KUBECONFIG="$HOME/.kube/containernode.yaml"
```

For one-off commands, prefix the command instead:

```bash
KUBECONFIG="$HOME/.kube/containernode.yaml" kubectl get nodes
```


## Fixing Tailscale CI Authentication

GitHub Actions now connects to Tailscale through the `tailscale/github-action@v4` OAuth client flow, not a stored auth
key. If the workflow fails with a Tailscale authentication error, rotate or recreate the OAuth client credentials and
update the GitHub Actions secrets.

### 1. Create or recreate the OAuth client

Open [Tailscale OAuth clients](https://login.tailscale.com/admin/settings/oauth).

Create a client that can provision CI runners with:

* the `auth_keys` scope required by the GitHub Action (shown in the admin UI as Auth Keys write)
* `tag:ci` in the allowed tags list

Copy the generated:

* **Client ID**
* **Client Secret**

### 2. Update GitHub secrets

Open [GitHub Actions secrets config](https://github.com/sam-bee/containernode/settings/secrets/actions).

Update:

```text
TS_OAUTH_CLIENT_ID
TS_OAUTH_SECRET
```

Unlike the old auth-key flow, there is no scheduled 90-day key rotation here. Only rotate these values if the OAuth
client is revoked, replaced, or the workflow starts failing authentication.

### 3. Re-run the workflow

Re-run the failed workflow.

If authentication succeeds, a temporary machine named like `gha-tailscale-serve-*` should briefly appear in the
[Tailscale machines view](https://login.tailscale.com/admin/machines) with the `tag:ci` tag.

See the GitHub token note below.


## Expired GitHub token on server

SSH into `containernode` server, and locate token in `/opt/containernode-github-repo`. Update.

The token needs read permissions on this repository only, and no other privileges.


## Upgrade k3s

The manually applied k3s target for `containernode` is pinned in `host/containernode/k3s-version`. The upgrade helper
is specific to this single-node amd64 server and its SQLite datastore. It does not float on a release channel.

The current target is `v1.37.1+k3s1`, installed on 24 October 2026 from the healthy `v1.36.5+k3s1` installation.
The matching pre-upgrade backup is `/var/backups/k3s/pre-upgrade-v1.36.5+k3s1-20261024T191159Z` on the host.
GitLab is on `19.5.1`, satisfying its published minimum of 19.5 for Kubernetes 1.37.
The operator explicitly accepted running cert-manager `1.21.3` outside its published Kubernetes support range on
24 October 2026. Its supported/tested range currently stops at 1.36; this is an accepted compatibility risk, not a
claim of upstream support. The chart allows 1.37 and renders the same resources as for 1.36; verify runtime behavior
after each upgrade. See the [GitLab Kubernetes support table](https://docs.gitlab.com/charts/installation/cloud/)
and [cert-manager support table](https://cert-manager.io/docs/releases/).

cert-manager is pinned to `v1.21.3`, including its CRDs, through the Flux HelmRelease. The k3s helper requires that
version to be ready. This patch includes certificate issuance and security fixes but does not extend the published
Kubernetes support range; see the [1.21.3 release notes](https://github.com/cert-manager/cert-manager/releases/tag/v1.21.3).

For future target changes, review Flux and add-on compatibility and record any accepted support exceptions.
If updating Flux, regenerate `clusters/containernode/flux-system/gotk-components.yaml` with the matching Flux CLI.
Kubernetes control planes must not skip minor versions. Review the
[Kubernetes 1.37 urgent upgrade notes](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.37.md#urgent-upgrade-notes).
The current cluster has no enabled `scheduling.k8s.io/v1alpha2` API and uses `eventRecordQPS: 50`. The host helper
refuses SELinux-enabled hosts pending review of the 1.37 volume-labeling change.

GitLab's public certificate was renewed successfully through Cloudflare DNS-01 before preparing this target. It now
expires on 22 January 2027. An encrypted recovery copy of the renewed certificate and private key is stored off-node.
The helper requires GitLab `19.5.1` and a Ready certificate with no renewal in progress and at least 30 days of validity.

From an up-to-date repository checkout on `containernode`, run the preparation check first:

```bash
sudo host/containernode/upgrade-k3s.sh --check
```

This checks workload and Flux readiness, refuses suspended reconciliations, verifies the SQLite datastore and server
token exist, confirms the running k3s process has that SQLite database open, checks the local-storage skip marker and
service files, verifies the GitLab version and public certificate, and downloads and verifies the required release
binaries. It does not stop k3s, take a backup, install a binary, or print credentials. Check available space and mounted
application storage on the host as well. Ensure application backups and a protected off-node recovery copy are available;
the helper's Kubernetes datastore backup does not back up application volumes.

The existence of `server/db/etcd/` alone does not mean etcd is initialized. The helper rejects an initialized etcd WAL
directory or member database and verifies the live SQLite file instead. Do not remove datastore directories to bypass
the check. See [k3s's initialization check](https://github.com/k3s-io/k3s/blob/v1.36.3%2Bk3s1/pkg/etcd/etcd.go).

When using a Proxmox VM backup as the recovery copy, wait for it to complete successfully and verify its included disks
cover the application data under `/mnt/userdata-clusterfiles`, `/mnt/twindrives-clusterfiles`, and `/mnt/workfiles`.
Data outside the included virtual disks needs a separate backup. For a live backup, confirm the guest-agent filesystem
freeze/thaw succeeds; a live VM backup is not equivalent to an application-native database backup.

GitLab's web ingress remains intentionally disabled while its security upgrade is validated. Preserve that isolation
during k3s maintenance. The published minimum for Kubernetes 1.37 is GitLab 19.5.

During the agreed maintenance window, run:

```bash
sudo host/containernode/upgrade-k3s.sh
```

The helper refuses to start unless Flux and every running workload are healthy. It downloads and verifies each pinned
k3s binary before making changes, creates an offline SQLite and server-token backup under `/var/backups/k3s`, then
restarts k3s once per required version step. Workload containers remain running during the brief API-server outages.
This follows the [manual k3s binary upgrade procedure](https://docs.k3s.io/upgrades/manual#upgrade-k3s-using-the-binary).
The helper waits for workload readiness, Flux reconciliation and GitLab certificate readiness after each version step.

Verify the final state:

```bash
k3s --version
kubectl get nodes
kubectl get pods --all-namespaces
flux check
kubectl -n cert-manager get deployments
kubectl -n gitlab get certificate gitlab-web-tls
```

Verify cert-manager webhook admission and fresh certificate issuance after the 1.37 upgrade; the existing GitLab
certificate staying Ready alone does not prove that new issuance or renewal works on the new Kubernetes version.

Post-upgrade verification on 24 October 2026 passed on `v1.37.1+k3s1` with cert-manager `v1.21.3`: all 35 active pods
and Flux reconciliations were healthy, all 23 PVs and PVCs were Bound, and GitLab's internal health and full readiness
checks returned HTTP 200. A temporary Let's Encrypt staging Certificate successfully completed Cloudflare DNS-01
issuance and forced renewal with private-key rotation; certificate/key matching and webhook validation also passed.
All temporary test resources and account keys were removed. GitLab's production certificate was unchanged by these
tests, web ingress remains disabled, and Jellyfin remains Tailscale only. These checks validate this deployment and
do not extend cert-manager's upstream support matrix.

Do not roll back by replacing only the binary after a minor-version upgrade. Use the matching pre-upgrade database,
token, configuration, service unit, and binary from `/var/backups/k3s` and follow the upstream k3s rollback procedure.


## Maintain the Flux-owned local-path provisioner

The bundled K3s `local-storage` AddOn is intentionally skipped so Flux can manage a newer local-path provisioner from
`infrastructure/containernode/local-path-provisioner`. K3s rewrites packaged manifests at startup, so the skip file must
be present on `containernode` before restarting or upgrading K3s.

On `containernode`, create the host-local skip marker once. Its contents do not matter:

```bash
sudo install -D -m 0644 /dev/null \
  /var/lib/rancher/k3s/server/manifests/local-storage.yaml.skip
```

The matching repository file at `host/containernode/manifests/local-storage.yaml.skip` records this manually applied
host state for reproducibility.

The skip file does not delete or modify the existing resources. Flux adopts the same ServiceAccount, RBAC, Deployment,
StorageClass, and ConfigMap names and preserves the K3s storage root at `/var/lib/rancher/k3s/storage`.

Verify the Flux-managed rollout with:

```bash
kubectl rollout status deployment/local-path-provisioner -n kube-system
kubectl get deployment/local-path-provisioner -n kube-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```


## Grafana admin access

Grafana runs in the `observability` namespace and is exposed via the Tailscale Serve service `svc:grafana`.

The Grafana chart generates the initial admin password inside the cluster. Retrieve it with:

```bash
kubectl get secret grafana -n observability -o jsonpath='{.data.admin-password}' | base64 -d && echo
```


## GitLab security maintenance

GitLab is pinned to chart `10.5.1` / GitLab `19.5.1`, the latest stable release verified on 24 October 2026. This includes
the critical CVE-2026-110264 fix. Recheck the [GitLab patch release notes](https://docs.gitlab.com/releases/patches/)
and [chart version mappings](https://docs.gitlab.com/charts/installation/version_mappings/) before future upgrades.

Web access remains intentionally disabled with `global.ingress.enabled: false` and `global.gatewayApi.enabled: false`.
The registry and KAS are also disabled. The application components and Git-over-SSH service still run; this is web
ingress isolation, not a shutdown of the namespace. Keep these settings when changing the chart version.

GitLab still requires a publicly trusted Let's Encrypt certificate. `gitlab/certificate.sops.yaml` manages
`gitlab-web-tls` explicitly using the Cloudflare DNS-01 ClusterIssuer, so cert-manager can renew it while web ingress
is disabled. Keep certificate ownership in this manifest and leave the ingress issuer annotation unset when restoring
web access. Jellyfin currently uses Tailscale Serve HTTPS and has no cert-manager Certificate resource.

Before an upgrade, create a native backup from the Toolbox pod with `backup-utility`, verify the resulting archive in
the configured backup bucket, and save the Kubernetes secrets in a separate encrypted recovery copy. The native backup
does not contain the Rails encryption secrets. Follow GitLab's required upgrade stops and ensure background migrations
are finished or finalized before advancing to the next stop. The October 2026 upgrade used `19.2.2 -> 19.2.9 -> 19.5.1`.

## PostgreSQL 17 and 18 service split

Two PostgreSQL Deployments intentionally run side by side while application support catches up:

- `postgres.postgres.svc.cluster.local` runs PostgreSQL 17 and currently contains only GitLab's
  `gitlabhq_production` database. GitLab 19.x with Helm chart 10.x supports PostgreSQL 17.x, but not PostgreSQL 18.
  Keep this instance, its `postgres-data` PVC/PV, and its service until GitLab officially supports PostgreSQL 18 and
  its database has been migrated and verified. See the
  [GitLab PostgreSQL requirements](https://docs.gitlab.com/install/requirements/#postgresql).
- `postgres18.postgres.svc.cluster.local` runs PostgreSQL 18 and contains the Chat, Grafana, and Matrix Synapse
  databases. New supported consumers should use this service.

The two instances have separate data directories and retained PVs. PostgreSQL major versions cannot share a data
directory, so retiring PostgreSQL 17 requires an explicit GitLab database migration followed by application and
backup verification; changing the image or service selector is not sufficient.

The host-local port `127.0.0.1:5432` and Tailscale Serve service `svc:postgres` currently reach PostgreSQL 17. The
PostgreSQL 18 service is cluster-internal only.


## Maintain Grafana Postgres settings

Grafana already reads its database settings from the Secret
`infrastructure/containernode/observability/grafana-postgres-auth.secret.sops.yaml` and connects to PostgreSQL 18.

If the Secret needs to be recreated, first create or rotate the Grafana database role in the PostgreSQL 18 pod:

```bash
export GRAFANA_DB_PASSWORD="$(openssl rand -hex 24)"

kubectl exec -i -n postgres deploy/postgres18 -- \
  env GRAFANA_DB_PASSWORD="$GRAFANA_DB_PASSWORD" \
  sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -v grafana_password="$GRAFANA_DB_PASSWORD"' <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana') THEN
    CREATE ROLE grafana LOGIN;
  END IF;
END
$$;

ALTER ROLE grafana WITH PASSWORD :'grafana_password';

SELECT 'CREATE DATABASE grafana OWNER grafana'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'grafana')\gexec

ALTER DATABASE grafana OWNER TO grafana;
SQL
```

Then overwrite the encrypted Secret manifest:

```bash
kubectl create secret generic grafana-postgres-auth \
  --namespace observability \
  --from-literal=GF_DATABASE_TYPE=postgres \
  --from-literal=GF_DATABASE_HOST=postgres18.postgres.svc.cluster.local:5432 \
  --from-literal=GF_DATABASE_NAME=grafana \
  --from-literal=GF_DATABASE_USER=grafana \
  --from-literal=GF_DATABASE_PASSWORD="$GRAFANA_DB_PASSWORD" \
  --from-literal=GF_DATABASE_SSL_MODE=disable \
  --dry-run=client -o yaml \
  | sops -e \
      --filename-override infrastructure/containernode/observability/grafana-postgres-auth.secret.sops.yaml \
      --input-type yaml --output-type yaml /dev/stdin \
  > infrastructure/containernode/observability/grafana-postgres-auth.secret.sops.yaml
```

After Flux applies the encrypted Secret, restart Grafana so the environment variables are picked up:

```bash
kubectl rollout restart deployment/grafana -n observability
```


## Rotate ProtonVPN WireGuard config for Transmission

Generate a fresh ProtonVPN WireGuard config and place it at the repository root as `wireguard-protonvpn.conf`.

Rebuild the encrypted Kubernetes Secret:

```bash
kubectl create secret generic transmission-proton-wireguard \
  --namespace transmission \
  --from-file=wg0.conf=wireguard-protonvpn.conf \
  --dry-run=client -o yaml \
  | sops -e \
      --filename-override infrastructure/containernode/transmission/proton-wireguard.secret.sops.yaml \
      --input-type yaml --output-type yaml /dev/stdin \
  > infrastructure/containernode/transmission/proton-wireguard.secret.sops.yaml
```

Commit the updated `infrastructure/containernode/transmission/proton-wireguard.secret.sops.yaml` file, but do not
commit the plaintext `wireguard-protonvpn.conf`.

Delete the plaintext file before committing:

```bash
rm -f wireguard-protonvpn.conf
```

The pod DNS is pinned to Proton's current internal resolver `10.2.0.1`; if Proton changes that value in a future
config, update `infrastructure/containernode/transmission/deployment.yaml` at the same time.

After Flux applies the change, restart the Transmission deployment if you want the tunnel and forwarded port to rotate
immediately:

```bash
kubectl rollout restart deployment/transmission -n transmission
```


## Transmission completed-download copy destination

Transmission now runs a torrent-done hook that copies completed files into
`/mnt/twindrives-clusterfiles/k3s-volumes/storage-media/media/incoming` on `containernode`. The workload reaches that
path through the `transmission-incoming` hostPath PV/PVC.

That hostPath is intentionally declared with `type: Directory`, not `DirectoryOrCreate`, so the pod will fail to start
if the NFS mount is missing and the node only has an empty local path. Keep the mount present before restarting or
redeploying the Transmission workload.


## Transmission storage path and size changes

Transmission's writable PVs are rooted at:

- `/mnt/twindrives-clusterfiles/k3s-volumes/transmission`
- `/mnt/twindrives-clusterfiles/k3s-volumes/storage-media/media/incoming`

Be careful changing either the `hostPath` or the requested PV/PVC size after the objects already exist:

- the PV source path is immutable once created
- the PVC size cannot be reduced after creation

For this workload, those changes are effectively a delete-and-recreate operation, not a normal in-place Flux update.

Safe operator sequence when either Transmission host path is moving:

```bash
kubectl scale deployment/transmission -n transmission --replicas=0
kubectl delete pod -n transmission -l app=transmission --force --grace-period=0 --wait=false
kubectl delete pvc transmission-data -n transmission
kubectl delete pv transmission-data
kubectl delete pvc transmission-incoming -n transmission
kubectl delete pv transmission-incoming
flux reconcile kustomization infrastructure -n flux-system --with-source
```

If only one of those host paths is moving, delete and recreate only that PV/PVC pair. Move the host directory first
while Transmission is scaled down, then let Flux recreate the PV/PVC against the new path.

If Flux reconciliation was suspended during a storage move, resume it after the host paths and PV/PVC objects are ready:

```bash
flux resume kustomization infrastructure -n flux-system
flux reconcile kustomization infrastructure -n flux-system --with-source
flux get kustomization infrastructure -n flux-system
```


## Syncthing tailnet-only setup

Syncthing runs in the `syncthing` namespace. Its config is stored at
`/mnt/userdata-clusterfiles/k3s-volumes/syncthing-config` and the shared data folder is mounted from
`/mnt/workfiles/synced`.

The pod binds its GUI and sync listener to localhost on `containernode`:

- GUI: `127.0.0.1:8384`
- Sync TCP: `127.0.0.1:22000`

Tailscale Serve exposes those localhost listeners to the tailnet as:

- `svc:syncthing-gui`
- `svc:syncthing-sync`

The deployment rewrites the generated Syncthing config before startup so it uses only a TCP listener and disables
global discovery, local discovery, relays, NAT traversal, STUN, and crash reporting.

After first deploy, open the Syncthing GUI over Tailscale and finish manual peering:

- set a GUI username and password
- add `/data` as the synced folder path
- add peer devices by Device ID
- set peer addresses to Tailscale endpoints, for example `tcp://device-name:22000`


## Matrix Synapse tailnet-only setup

Synapse runs in the `matrix` namespace and is exposed through Tailscale Serve as `svc:matrix`. Element Web also runs
in the `matrix` namespace and is exposed as `svc:element`.

The Synapse `server_name` is set to `matrix`, so local Matrix user IDs look like `@user:matrix`. Treat that value as
effectively permanent after the homeserver first starts.

Element Web generates its homeserver URL from the Tailscale service hostname at request time. When accessed as
`element.[TAILNET_NAME].ts.net`, it points at `matrix.[TAILNET_NAME].ts.net` without storing the tailnet name in this
repository.

Registration is disabled by default. After Synapse is running, create the first user from inside the pod:

```bash
kubectl exec -it -n matrix deploy/synapse -- \
  register_new_matrix_user -c /run/synapse/homeserver.yaml http://localhost:8008
```


## OpenClaw tailnet-only setup

OpenClaw runs in the `openclaw` namespace and is exposed through Tailscale Serve as `svc:openclaw`. The gateway binds
to `127.0.0.1:18789` on `containernode`; it is not exposed through Traefik or a public ingress.

OpenClaw keeps its config, workspace, session data, credentials, and SQLite state under `/home/node/.openclaw`. That
directory is backed by the retained hostPath volume at `/mnt/userdata-clusterfiles/k3s-volumes/openclaw`. It does not
use the cluster Postgres service.

### Edit agent instructions

Model-facing instructions are maintained in the private `sam-bee/agents` repository, not in this infrastructure
repository. Edit files below `agents/<agent-id>/` on its `master` branch and push the same commit to its GitHub and
GitLab remotes. Flux reads the GitHub copy through the `openclaw-agents` source, includes those files in the dedicated
OpenClaw artifact, and rolls out the gateway when the generated ConfigMap hash changes.

The encrypted read-only Git credential is
`infrastructure/containernode/openclaw-agents-git-auth.secret.sops.yaml`. Its public key must be registered as a
read-only deploy key on the GitHub agents repository. Do not give this key write access.

### Create or rotate the gateway token

Generate a new token with `openssl rand -hex 32`, store it in the password manager, then paste it into the silent prompt
below. The command creates only the encrypted manifest; it does not apply a plaintext Secret to the cluster. The Docker
invocation is used because `sops` is not otherwise required to be installed on the workstation.

```bash
printf 'OpenClaw gateway token: '
IFS= read -r -s OPENCLAW_GATEWAY_TOKEN
printf '\n'

kubectl create secret generic openclaw-secrets \
  --namespace openclaw \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  --dry-run=client -o yaml \
  | docker run --rm -i \
      -v "$PWD:/work" \
      -w /work \
      ghcr.io/getsops/sops:v3.13.3 \
      --encrypt \
      --filename-override infrastructure/containernode/openclaw/openclaw-secrets.secret.sops.yaml \
      --input-type yaml --output-type yaml /dev/stdin \
  > infrastructure/containernode/openclaw/openclaw-secrets.secret.sops.yaml

unset OPENCLAW_GATEWAY_TOKEN
```

Commit only `openclaw-secrets.secret.sops.yaml`. After Flux applies a rotated token, restart the gateway so its process
environment is refreshed:

```bash
kubectl rollout restart deployment/openclaw -n openclaw
```

### Configure the Tailscale Service

Before pushing the initial OpenClaw manifests, define `svc:openclaw` in the Tailscale admin console with endpoint
`tcp:443` and grant only the intended tailnet identities access to it. After the Tailscale Serve workflow advertises
`containernode` as a host, approve that pending service host in the admin console.

Verify the deployment and host-local listener before testing the Control UI over Tailscale:

```bash
kubectl get pods,pvc -n openclaw
kubectl logs -n openclaw deploy/openclaw
curl --fail --silent --show-error http://127.0.0.1:18789/readyz
```

Open the `svc:openclaw` MagicDNS HTTPS address and enter the gateway token in the Control UI. Provider API keys and
local model endpoints are intentionally not part of the initial deployment. Add them later through SOPS-encrypted
Secrets and environment-backed OpenClaw configuration; do not commit them to the ConfigMap or workspace.


## Allow Transmission's WireGuard sysctl on k3s

The Transmission pod sets `net.ipv4.conf.all.src_valid_mark=1` so the WireGuard policy-routing path can start cleanly.
On this node, kubelet must explicitly allowlist that unsafe sysctl or the pod will be rejected with
`SysctlForbidden`.

The tracked drop-in file is:

`host/containernode/etc/rancher/k3s/config.yaml.d/90-kubelet-unsafe-sysctls.yaml`

Apply it on `containernode` and restart k3s:

```bash
sudo install -D -m 0644 \
  /opt/containernode-github-repo/containernode/host/containernode/etc/rancher/k3s/config.yaml.d/90-kubelet-unsafe-sysctls.yaml \
  /etc/rancher/k3s/config.yaml.d/90-kubelet-unsafe-sysctls.yaml

sudo systemctl restart k3s
```

Verify the node and workload recover:

```bash
kubectl get nodes
kubectl get pods -n transmission -w
```
