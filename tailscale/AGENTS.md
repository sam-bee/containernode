# Tailscale Files

`tailscale/serve-config.json` is the active Tailscale Serve config tracked in this repository.

Deployment is handled by:

- `.github/workflows/deploy-tailscale-serve.yml`
- `tailscale/update-serve-config.sh`

The workflow connects to `containernode` over Tailscale SSH and runs the server-side script. That script resets the
remote checkout to `origin/main` and applies `tailscale/serve-config.json` with `tailscale serve set-config`.

When editing this directory:

- update `serve-config.json`
- keep upstream ports aligned with the service actually listening on the host
- prefer host-local upstreams such as `127.0.0.1:PORT`
