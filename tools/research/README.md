# Research server Kubernetes CLIs

These scripts install the Kubernetes operator CLIs used from the research server. They are pinned to versions that
match the `containernode` cluster, verify upstream release checksums, install into `/usr/local/bin`, and retain the
previous local binary as a timestamped backup.

Run them on the research server from the repository root:

```bash
sudo tools/research/upgrade-kubectl.sh
sudo tools/research/upgrade-flux.sh
```

Then refresh the shell command cache and verify cluster access:

```bash
rehash
kubectl version
flux check
```
