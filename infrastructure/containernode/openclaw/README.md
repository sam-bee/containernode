# OpenClaw

OpenClaw runs on `containernode` and connects private Matrix accounts to isolated agents. Commands that need the
research host are sent over OpenClaw's paired-node protocol to the node named `research`; the gateway does not SSH
into the host and Matrix credentials do not need to be installed there.

## Agents

| Agent | Matrix account | Room | Prompt |
| --- | --- | --- | --- |
| `default` | `@codex:matrix` | `outside-agents` | `prompts/codex/AGENTS.md` |
| `grok-number1` | `@grok-number1:matrix` | `security-research` | `prompts/grok-number1/AGENTS.md` |

Edit an agent's `AGENTS.md` file to maintain its durable role instructions. Kustomize generates ConfigMaps from
those files and the init container copies each prompt into its isolated workspace on rollout.

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
