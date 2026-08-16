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

Command authorization is deliberately enforced twice: the agent has an OpenClaw `exec` allowlist policy, and the
paired node has a host-side approval file. Initially only `/usr/bin/uname` is pre-approved for `grok-number1`.
Expand that list narrowly as research tasks are introduced; do not allowlist a general shell or interpreter.
