# Casefile

Source: `git@github.com:sam-bee/casefile.git`, pinned by the full commit in
`deployment.yaml`. The upstream Dockerfile builds the browser assets and Go
binary. Casefile runs as UID 1000/GID 1984 with a read-only root filesystem.

The web service is `http://casefile.casefile.svc.cluster.local` inside k3s and
`http://127.0.0.1:8090` on containernode. The Tailscale Serve mapping publishes
that loopback listener as HTTPS service `svc:casefile`. Create/approve that
service and its service host in Tailscale; its tailnet DNS name is assigned by
Tailscale. The application has no login, so the tailnet service ACL is its
access boundary. It is not exposed through a public Ingress.

## Database and search

Casefile uses its own `casefile` database and login role on the existing shared
PostgreSQL 18 instance at `postgres18.postgres.svc.cluster.local:5432`. The
SOPS-encrypted `casefile-db.secret.sops.yaml` contains `DATABASE_URL`, including
`sslmode=require`. The application installs its schema when it starts; the
role owns only this database and has no administrative privileges.

The role and database must exist before the first deployment. To restore them
on a replacement PostgreSQL instance, use an administrative `psql` session in
`deployment/postgres18` in namespace `postgres` and a private random password:

```sql
CREATE ROLE casefile LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
  PASSWORD :'casefile_password';
CREATE DATABASE casefile OWNER casefile;
REVOKE ALL ON DATABASE casefile FROM PUBLIC;
```

Set the same password in the encrypted Secret's URL, encrypt with the root
`.sops.yaml` rule, and restart Casefile after credential changes. Back up the
`casefile` database using the existing PostgreSQL backup procedure. PostgreSQL
is the canonical store; do not copy data from a different environment unless
that migration is explicitly intended.

Elasticsearch 9.5.5 runs in namespace `elasticsearch`, with a retained 20 GiB
hostPath PV on `/mnt/userdata-clusterfiles/k3s-volumes/elasticsearch`. Like
other hostPath PVs here, the declared capacity is not a filesystem quota.
Its only Service is ClusterIP:
`http://elasticsearch.elasticsearch.svc.cluster.local:9200`. NetworkPolicy
allows port 9200 only from pods labelled `app: casefile` in namespace
`casefile`. Add explicit rules before allowing another consumer. k3s network
policy enforcement must remain enabled.

Elasticsearch authentication is disabled to match the upstream client. It has
no hostPort, NodePort, public Ingress, or Tailscale mapping. Its heap is 512 MiB
and its container memory limit is 2 GiB; machine learning is disabled. This
small single-node index disables mmap to avoid host sysctl changes, following
[Elastic's documented configuration](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/virtual-memory).
For a larger workload, size the node and tune virtual memory before enabling
mmap. Casefile recreates and repopulates the index from PostgreSQL if it is
lost. Recreate strategy prevents concurrent Elasticsearch processes opening
the same data directory.

## Build and update

This single-node deployment imports the application image directly into k3s
containerd. It requires no registry credentials. The image is node-local and
uses `imagePullPolicy: Never`; retain/rebuild it when replacing the node or
clearing the container image store. Flux applies manifests; it does not build
or import the image.

1. Clone/fetch Casefile and check out the desired commit in a clean checkout.
2. Change `deployment.yaml` to `localhost/casefile:<full-commit>`.
3. Build and import **before** committing that image change:

   ```sh
   export KUBECONFIG="$HOME/.kube/containernode.yaml"
   infrastructure/containernode/casefile/build-and-load.sh /path/to/casefile
   ```

   The helper builds `linux/amd64` in Docker, creates a temporary root pod with
   the node's bundled containerd CLI and containerd socket, streams the image into
   containerd, and removes the helper pod on exit. It needs cluster-admin
   access. If interrupted before cleanup, delete its `casefile-image-import-*`
   pod from `kube-system`.

4. Commit/push the infrastructure change for Flux and wait for readiness:

   ```sh
   flux reconcile kustomization infrastructure --with-source
   kubectl rollout status -n elasticsearch deployment/elasticsearch
   kubectl rollout status -n casefile deployment/casefile
   ```

For rollback, restore the previous manifest image and rebuild/import that
revision if it is no longer cached. Check upstream schema compatibility before
rolling back across application schema changes.

## Verify

Kubernetes readiness uses `POST /api/health` with JSON, which checks both
PostgreSQL and the Elasticsearch index. Startup and liveness check the web
listener without restarting Casefile during a dependency outage.

On containernode (or through `kubectl port-forward -n casefile svc/casefile
8090:80`), run:

```sh
curl -fsS http://127.0.0.1:8090/ >/dev/null
curl -fsS http://127.0.0.1:8090/api/health \
  -H 'Content-Type: application/json' -d '{}'
curl -fsS http://127.0.0.1:8090/api/projects/list \
  -H 'Content-Type: application/json' -d '{}'
curl -fsS http://127.0.0.1:8090/api/casenotes/search \
  -H 'Content-Type: application/json' \
  -d '{"project":"packagist-local","query":"","limit":20}'
```

Use the Tailscale HTTPS hostname as the base URL for browser/API consumers.
The Go SDK/CLI accept `CASEFILE_API_URL=https://<service-hostname>/api`.
Upstream's optional OMP tool currently restricts requests to loopback HTTP;
using that adapter remotely requires a separate upstream configuration change.
