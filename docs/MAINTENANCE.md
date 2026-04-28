# Maintenance Runbooks


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


## Grafana admin access

Grafana runs in the `observability` namespace and is exposed via the Tailscale Serve service `svc:grafana`.

The Grafana chart generates the initial admin password inside the cluster. Retrieve it with:

```bash
kubectl get secret grafana -n observability -o jsonpath='{.data.admin-password}' | base64 -d && echo
```


## Switch Grafana to Postgres

Grafana is configured to read its database settings from the Secret
`infrastructure/containernode/observability/grafana-postgres-auth.secret.sops.yaml`.

Create the Grafana database and role from the existing Postgres pod:

```bash
export GRAFANA_DB_PASSWORD="$(openssl rand -hex 24)"

kubectl exec -n postgres deploy/postgres -- \
  env GRAFANA_DB_PASSWORD="$GRAFANA_DB_PASSWORD" \
  sh -ec '
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<SQL
    CREATE ROLE grafana LOGIN PASSWORD '"'$GRAFANA_DB_PASSWORD'"';
    CREATE DATABASE grafana OWNER grafana;
SQL
  '
```

Then overwrite the placeholder Secret manifest with an encrypted one:

```bash
kubectl create secret generic grafana-postgres-auth \
  --namespace observability \
  --from-literal=GF_DATABASE_TYPE=postgres \
  --from-literal=GF_DATABASE_HOST=postgres.postgres.svc.cluster.local:5432 \
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

After Flux applies the encrypted Secret, restart Grafana so the new environment variables are picked up:

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
