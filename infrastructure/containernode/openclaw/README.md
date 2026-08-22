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
| `personal` | `@personal:matrix` | `personal` | built-in OpenClaw prompt |
| `3-8` | `@3-8:matrix` | `personal-diary` | `agents/3-8/AGENTS.md` |

Edit agent content on the `master` branch of the agents repository. An agents commit changes the generated ConfigMap
hash, which rolls out OpenClaw; the init container then copies each prompt into its isolated workspace. GitHub is the
Flux deployment source and GitLab is maintained as a mirror.

Agent skills live at `agents/<agent-id>/skills/<skill-name>/SKILL.md`. The deployment copies packaged skills into the
matching OpenClaw workspace under `skills/`, where OpenClaw discovers them automatically; agent prompts do not need to
name the skill path.

The `grok-number1` model credential is created interactively with xAI OAuth and retained in the OpenClaw home PVC;
it is not stored in Git. Matrix and gateway tokens are SOPS-encrypted in this directory.

The `personal` agent uses `deepseek/deepseek-v4-pro` with no host or web tools. Its Matrix token is SOPS-encrypted,
but its DeepSeek API key is intentionally not pre-provisioned. Add the key interactively when it is available; the
resulting per-agent auth profile is retained in the OpenClaw home PVC:

```sh
kubectl exec -it -n openclaw deploy/openclaw -- \
  openclaw models auth --agent personal paste-api-key \
  --provider deepseek --profile-id deepseek:personal
```

The `3-8` agent uses the private OpenAI-compatible Qwen endpoint configured by the SOPS-encrypted
`THREE_EIGHT_BASE_URL` value. It has an isolated Markdown-configured workspace and no host or web tools.

## Research node

The `research` node runs as the `sierra` user through `openclaw-node.service`. Useful checks on that host are:

```sh
systemctl --user status openclaw-node.service
journalctl --user -u openclaw-node.service
```

Research agents are allowed arbitrary commands on this node so they can edit code and use Git, but the node service
runs inside a host-enforced systemd write boundary. It can modify OpenClaw's own state and
`/mnt/workfiles/synced/tech-projects/security-research/01-packagist`; the rest of the host filesystem is read-only.
Raw SSH keys, personal Docker client state, and the desktop/user systemd session are inaccessible from the service.
The existing rootful Docker socket is deliberately available to the research agent. This is root-equivalent host
authority and means the filesystem boundary is not a security boundary against malicious Docker operations.

The Packagist Compose services retain their existing `1000:1984` PHP/Node identity so bind-mounted dependencies remain
owned by `sierra:shareddata`. OpenClaw uses an isolated Docker client directory at
`~/.openclaw/docker-config`; it does not use or expose the operator's personal `~/.docker` state.

Git authentication is provided through a dedicated SSH-agent socket. The node can ask that agent to sign Git SSH
connections but cannot read the underlying private-key file. Both GitHub and GitLab access should be tested after
changing the service sandbox.

These controls are host-local rather than Kubernetes configuration:

- `~/.config/systemd/user/openclaw-node.service.d/20-security-research-sandbox.conf` defines the write boundary.
- `~/.config/systemd/user/openclaw-node.service.d/30-research-tool-storage.conf` routes npm, XDG, and Playwright state
  into OpenClaw's existing writable directory rather than making the whole home directory writable.
- `~/.openclaw/npm-global` holds the pinned Playwright CLI. Its node-wide config selects `/usr/bin/chromium` and sends
  generated output to `~/.openclaw/playwright-output`, keeping npm and Playwright setup files out of research repos.
- `~/.local/bin/playwright-cli` exposes that node-wide CLI through the paired node's sanitized command path.
- `~/.config/systemd/user/openclaw-ssh-agent.service` owns the dedicated credential-agent socket.
- `~/.openclaw/openclaw.json` explicitly requests `tools.exec.security=full` and `tools.exec.ask=off` for the node
  runtime. Keep these values explicit: OpenClaw 2026.7.1 otherwise enforces its `allowlist`/`on-miss` node-host
  fallbacks even when the gateway and per-agent host approval both request unrestricted execution.
- `~/.openclaw/exec-approvals.json` supplies the host-side OpenClaw execution policy.

The gateway must route `exec`, the node-local requested policy must permit it, and the host approval file must grant it
explicitly for each research agent. The host default is deny, so setting the node-local requested policy to `full` does
not authorize the non-research `default` agent. Add each future research agent to the gateway and host approval layers
rather than relaxing the host default.

## Research media bridge

Files created by `exec` exist on the paired `research` node, not in the OpenClaw gateway pod. Syncthing replicates the
Packagist `.playwright-mcp` directory to the same host path on `containernode`; the deployment mounts only that directory
read-only at `workspace-grok-number1/research-playwright-media`. This lets OpenClaw resolve node-generated screenshots
as workspace media without exposing the rest of the synced research tree to the gateway.

An init container also creates the research node's absolute `.playwright-mcp` path as a symlink to that workspace mount.
This compatibility mapping makes old sessions and imperfect model replies deterministic: a `MEDIA:` directive that uses
the research-side absolute path canonicalizes to the already-approved workspace path. It does not grant the agent the
general `read` tool or add the research checkout to OpenClaw's local-media allowlist.

The two sides of the bridge are:

- research-node output: `/mnt/workfiles/synced/tech-projects/security-research/01-packagist/.playwright-mcp/outbound/<file>`
- reply media path: `MEDIA:./research-playwright-media/outbound/<file>`

The preferred reply path is workspace-relative. The absolute research-node path is supported as a compatibility
fallback and exposes the same narrow read-only directory, not the surrounding research checkout.

Keep the source directory mounted with `hostPath.type: Directory`. A missing Syncthing directory should prevent the
gateway rollout instead of silently creating an empty path that turns attachments into `Media failed` warnings.

## Grok web search

`grok-number1` has the OpenClaw `web_search` tool, backed by the `grok` provider. The xAI plugin reuses the agent's
existing xAI OAuth profile, so no separate Brave or xAI API key is stored in Kubernetes. Both the per-agent and Matrix
room tool allowlists must include `web_search`; the non-research Codex account remains unable to use it.

This enables cited, read-only public-web research. It does not enable `web_fetch`, browser automation on public sites,
xAI code execution, or `x_search`; the latter remains explicitly disabled. Research agents may use search to locate
public documentation and background material, but the rules against testing or probing live targets still apply.
