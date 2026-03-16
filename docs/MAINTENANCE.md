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

Transmission now runs a torrent-done hook that copies completed files into `/mnt/helsinki1-media/media/incoming` on
`containernode`. The workload reaches that path through the `transmission-incoming` hostPath PV/PVC.

That hostPath is intentionally declared with `type: Directory`, not `DirectoryOrCreate`, so the pod will fail to start
if the NFS mount is missing and the node only has an empty local path. Keep the mount present before restarting or
redeploying the Transmission workload.


## Transmission storage path and size changes

Transmission's main data PV is rooted at `/mnt/erithc-clusterfiles/k3s-volumes/transmission`.

Be careful changing either the `hostPath` or the requested PV/PVC size after the objects already exist:

- the PV source path is immutable once created
- the PVC size cannot be reduced after creation

For this workload, those changes are effectively a delete-and-recreate operation, not a normal in-place Flux update.

Safe operator sequence:

```bash
kubectl scale deployment/transmission -n transmission --replicas=0
kubectl delete pod -n transmission -l app=transmission --force --grace-period=0 --wait=false
kubectl delete pvc transmission-data -n transmission
kubectl delete pv transmission-data
flux reconcile kustomization infrastructure -n flux-system --with-source
```

If the storage path itself is moving on disk, move the host directory first while Transmission is scaled down, then let
Flux recreate the PV/PVC against the new path.


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
