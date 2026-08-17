# Pinned OpenClaw image

This image installs the exact official npm packages `openclaw@2026.8.1-beta.2` and
`@openclaw/codex@2026.8.1-beta.2` over the immutable linux/amd64 image that previously ran on `containernode`. The
matching Codex plugin preserves the existing default agent without relying on OpenClaw's mutable `@beta` auto-repair.
The committed `package-lock.json` pins the packages and all transitive npm dependencies, including npm integrity
hashes. The Dockerfile verifies the installed OpenClaw package version during the build.

Build it from the repository root:

```bash
docker build \
  --platform linux/amd64 \
  --provenance=false \
  --tag localhost/openclaw:2026.8.1-beta.2-npm.2 \
  infrastructure/containernode/openclaw/image
```

The Kubernetes manifest uses the built OCI digest as well as the versioned local tag. The image must be imported into
the single k3s node's containerd image store before reconciliation; the workload uses `imagePullPolicy: Never` so an
unavailable local image fails closed rather than falling back to an untrusted or moving registry tag.
