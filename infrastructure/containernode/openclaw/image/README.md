# Optional pinned OpenClaw image

This image installs the exact official npm packages `openclaw@2026.10.7` and
`@openclaw/codex@2026.10.7` over the immutable linux/amd64 image published for OpenClaw 2026.10.7. The
matching Codex plugin preserves the existing default agent without relying on OpenClaw's mutable `@beta` auto-repair.
The committed `package-lock.json` pins the packages and all transitive npm dependencies, including npm integrity
hashes. The Dockerfile verifies the installed OpenClaw package version during the build. The Kubernetes deployment uses
the official GHCR image directly because it already contains OpenClaw 2026.10.7, Node 24.22.1, and the matching Codex
extension; this overlay remains available only for an offline/custom-image delivery.

Build it from the repository root:

```bash
docker build \
  --platform linux/amd64 \
  --provenance=false \
  --tag localhost/openclaw:2026.10.7-npm.4 \
  infrastructure/containernode/openclaw/image
```

The Kubernetes manifest uses `ghcr.io/openclaw/openclaw:2026.10.7` pinned to its verified OCI index digest with
`imagePullPolicy: IfNotPresent`; no local image build or host-side image import is required for normal delivery.
