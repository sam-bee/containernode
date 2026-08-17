# Pinned OpenClaw image

This image installs the exact official npm package `openclaw@2026.8.1-beta.2` over the immutable linux/amd64 image
that previously ran on `containernode`. The committed `package-lock.json` pins the package and all transitive npm
dependencies, including npm integrity hashes. The Dockerfile verifies the installed package version during the build.

Build it from the repository root:

```bash
docker build \
  --platform linux/amd64 \
  --tag localhost/openclaw:2026.8.1-beta.2-npm.1 \
  infrastructure/containernode/openclaw/image
```

The Kubernetes manifest uses the built OCI digest as well as the versioned local tag. The image must be imported into
the single k3s node's containerd image store before reconciliation; the workload uses `imagePullPolicy: Never` so an
unavailable local image fails closed rather than falling back to an untrusted or moving registry tag.
