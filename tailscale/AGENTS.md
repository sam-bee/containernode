# Tailscale Files

Tailscale Serve state is deployed from `tailscale/update-serve-config.sh`.

Deployment is handled by:

- `.github/workflows/deploy-tailscale-serve.yml`
- `tailscale/update-serve-config.sh`

The workflow connects to `containernode` over Tailscale SSH and runs the server-side script. That script resets the
remote checkout to `origin/main` and applies the current `tailscale serve` service mappings directly.

When editing this directory:

- update `update-serve-config.sh`
- keep upstream ports aligned with the service actually listening on the host
- prefer host-local upstreams such as `127.0.0.1:PORT`
