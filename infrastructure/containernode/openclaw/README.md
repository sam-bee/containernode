# OpenClaw

OpenClaw runs on `containernode` and connects private Matrix accounts to isolated agents. Commands that need the
research host are sent over OpenClaw's paired-node protocol to the node named `research`; the gateway does not SSH
into the host and Matrix credentials do not need to be installed there.

## Configuration ownership

This directory owns OpenClaw's Kubernetes resources, runtime configuration, storage, secret references, Matrix
routing, and enforceable tool policy. Model-facing instructions are owned by the separate private `sam-bee/agents`
repository and do not live in this infrastructure repository.

Flux fetches that repository as `openclaw-agents` and includes its `agents/` directory at `agent-content/` in the
`containernode-openclaw` source artifact. The `agent-content/` path therefore exists only in the reconciled artifact,
not in a normal `containernode` checkout. The dedicated `openclaw` Flux Kustomization builds this directory from that
composite artifact.

## Agents

| Agent | Matrix account | Room | Prompt |
| --- | --- | --- | --- |
| `default` | `@codex:matrix` | `outside-agents` | `agents/codex/AGENTS.md` |
| `grok-number1` | `@grok-number1:matrix` | `security-research` | `agents/grok-number1/AGENTS.md` |

Edit agent content on the `master` branch of the agents repository. An agents commit changes the generated ConfigMap
hash, which rolls out OpenClaw; the init container then copies each prompt into its isolated workspace. GitHub is the
Flux deployment source and GitLab is maintained as a mirror.

The `grok-number1` model credential is created interactively with xAI OAuth and retained in the OpenClaw home PVC;
it is not stored in Git. Matrix and gateway tokens are SOPS-encrypted in this directory.

## Research node

The `research` node runs as the `sierra` user through `openclaw-node.service`. Useful checks on that host are:

```sh
systemctl --user status openclaw-node.service
journalctl --user -u openclaw-node.service
```

Research agents are allowed arbitrary commands on this node so they can edit code and use Git, but the node service
runs inside a host-enforced systemd write boundary. It can modify OpenClaw's own state and
`/mnt/workfiles/synced/tech-projects/security-research/01-packagist`; the rest of the host filesystem is read-only.
Raw SSH keys, the Docker control socket, and the desktop/user systemd session are inaccessible from the service.

Git authentication is provided through a dedicated SSH-agent socket. The node can ask that agent to sign Git SSH
connections but cannot read the underlying private-key file. Both GitHub and GitLab access should be tested after
changing the service sandbox.

These controls are host-local rather than Kubernetes configuration:

- `~/.config/systemd/user/openclaw-node.service.d/20-security-research-sandbox.conf` defines the write boundary.
- `~/.config/systemd/user/openclaw-ssh-agent.service` owns the dedicated credential-agent socket.
- `~/.openclaw/exec-approvals.json` supplies the host-side OpenClaw execution policy.

The gateway and host approval file must both grant and route `exec` explicitly for each research agent. The host default
is deny, and the non-research `default` agent remains without `exec` access. Add each future research agent to both
layers rather than relaxing the host default.
