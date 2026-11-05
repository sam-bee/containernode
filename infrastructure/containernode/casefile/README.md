# Casefile

Source: `git@github.com:sam-bee/casefile.git`. The upstream Dockerfile builds the browser assets and Go
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
role owns only this database and has no administrative privileges. The current
application uses `local-research` when API requests omit a project; existing
projects and their records remain available by explicitly selecting them.

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

Push Casefile changes to GitHub `master`. GitHub Actions tests and builds the image,
then publishes `ghcr.io/sam-bee/nightwatch-casefile:latest` to the private registry.
Flux checks for a new digest every five minutes, commits the deployment update to
`containernode/main`, and reconciles it into the cluster. The digest identifies the
actual image while the `latest` tag keeps releases automatic. New pushes can take
several minutes to reach the cluster. No host-side build or image import is needed.

Before editing this repository, fetch `origin` and fast-forward a clean `main`: Flux
can create commits automatically. If the checkout has local changes or divergent
commits, preserve them and reconcile deliberately rather than resetting them.

Both the `casefile` and `flux-system` namespaces need the `casefile-ghcr` pull
Secret. Their SOPS-encrypted manifests use a GitHub token with `read:packages`.
Rotate both secrets together before the token expires, and check `flux get images all -A`
and the Casefile rollout afterward. The separate `casefile-flux-write` GitHub deploy key has write access to this
infrastructure repository so image automation can commit digest updates; Flux's
original source key remains read-only.

Check automation and the current rollout with:

```sh
flux get images all -A
flux get kustomizations -A
kubectl rollout status -n casefile deployment/casefile
```

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
