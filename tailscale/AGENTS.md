# Tailscale Files

Tailscale Serve deployment is orchestrated by `tailscale/update-serve-config.sh`.

The actual `tailscale serve` service mappings live in `tailscale/run-tailscale-serve.sh`.

Deployment is handled by:

- `.github/workflows/deploy-tailscale-serve.yml`
- `tailscale/update-serve-config.sh`

The workflow connects to `containernode` over Tailscale SSH and runs the server-side script. That script resets the
remote checkout to `origin/main`, then invokes `run-tailscale-serve.sh` from the checked-out repo so service-line
changes are applied from the current revision instead of the previously deployed copy.

When editing this directory:

- update `run-tailscale-serve.sh` when you are changing service mappings
- update `update-serve-config.sh` only when you are changing the deployment/update mechanics
- keep upstream ports aligned with the service actually listening on the host
- prefer host-local upstreams such as `127.0.0.1:PORT`
