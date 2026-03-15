# AGENTS.md

This repository is the source of truth for `containernode`, a small self-hosted k3s control-plane node.

It manages two layers:

- Kubernetes state, reconciled by Flux
- host-level Tailscale Serve routing

## Key paths

- `clusters/containernode/`: Flux bootstrap and cluster reconciliation objects. `infrastructure.yaml` points Flux at
  `./infrastructure/containernode`.
- `infrastructure/containernode/`: Kubernetes manifests for workloads and platform components on this node.
- `tailscale/`: Tailscale Serve config and the server-side deployment script.
- `.github/workflows/`: automation, including Tailscale Serve deployment.
- `docs/`: small operational runbooks.

## Environment

- Kubernetes API server: `containernode.[TAILNET_NAME].ts.net:6443`
- k3s runs on the `containernode` host.
- Traefik is the default k3s ingress controller.
- Tailscale is used for admin access and for exposing selected internal services.

(If you need the tailnet name, just ask.)

## Editing guidance

- Prefer declarative manifest changes over ad hoc scripts.
- Keep solutions simple for a single-node, single-operator environment.
- Keep Kubernetes config under `infrastructure/` and host-level Tailscale config under `tailscale/`.
- Avoid editing generated Flux files under `clusters/containernode/flux-system` unless you are intentionally
  regenerating them.
- Treat the repository as live infrastructure and favor small, clear, reversible changes.

## Privacy and Security

Please do not put the tailnet name or any credentials in version control. a `.sops.yaml` file is available for secrets
management.
