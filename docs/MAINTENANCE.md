# Maintenance Runbooks


## Expired Tailscale Auth Key

Go to the [Tailscale Auth Key](https://login.tailscale.com/admin/settings/keys) page and get a new one.

The token needs to be `Single-use`, `Ephemeral`, and should have the `ci` tag.

Go to [Github Action secrets config](https://github.com/sam-bee/containernode/settings/secrets/actions) and put the new
key.

Needs doing every 90 days.

See Github tokens below


## Expired Github token on server

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
