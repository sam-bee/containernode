# GitLab PostgreSQL 17 to 18.6 migration

Completed on 25 October 2026. The stable `postgres` Service now selects
`postgres-gitlab18`, which runs PostgreSQL 18.6 and owns the existing
`127.0.0.1:5432` host port. All three cutover patches below are active in the
final Kustomization. The original PostgreSQL 17 Deployment is at zero replicas;
its original PV/PVC remain retained. GitLab writers are restored, temporary
Flux suspensions are cleared, and Rails migrations, background migrations,
transactional write-path checks and public HTTPS validation passed. The
procedure below records the completed migration phases; do not rerun its
initial restore steps against the live target.

This runbook is for the GitLab-only PostgreSQL instance in the `postgres`
namespace.  The existing `postgres18` Deployment, Service, PV, PVC, and data
directory are a separate database service for Chat, Grafana, and Synapse and
are not part of this procedure.

The migration uses a new PostgreSQL 18.6 data directory and a direct logical
transfer from the quiesced PostgreSQL 17 server.  PostgreSQL major versions
cannot share a data directory.  The existing PostgreSQL 17 Deployment, PV,
and PVC remain in the repository and are retained for rollback.

## Current inventory and acceptance targets

The observed source state before this change is:

- PostgreSQL 17.11, data directory `/var/lib/postgresql/data/pgdata`.
- GitLab database `gitlabhq_production`, approximately 206 MiB according to
  `pg_database_size`, with approximately 311 MiB used in the PostgreSQL 17
  data directory.
- Database owner `gitlab`; database locale and collation `en_US.utf8`, libc
  provider, with current collation version `2.41`.
- Required extensions present: `btree_gist`, `pg_trgm`, and `plpgsql`.
  `amcheck` is available in the PostgreSQL 18.6 image but was absent from the
  source database, so the target procedure creates it explicitly.
- GitLab schema migration status was `3749 up, 0 down`; background migration
  entries were finished or finalized at inspection time.

The target must satisfy all of the following before the stable Service is
switched:

1. PostgreSQL reports 18.6, and `data_directory` is
   `/var/lib/postgresql/18/docker` on the new PVC.
2. `gitlabhq_production` has owner `gitlab`, the source locale/collation and
   libc provider, and a compatible current collation version.
3. The source roles and memberships needed by the GitLab database are present;
   at minimum the `gitlab` role exists with the expected login capability and
   `postgres` remains a superuser.  Preserve the other PostgreSQL 17 roles
   during the global-role transfer because they are part of the existing
   authentication state.
4. `amcheck`, `btree_gist`, `pg_trgm`, and `plpgsql` are installed in
   `gitlabhq_production`.
5. Object counts, relation sizes, schema ownership, and representative GitLab
   reads match the source.  The direct transfer must exit successfully with
   `pg_restore --exit-on-error`.
6. After the application is resumed, Rails migration and background migration
   checks are clean, all GitLab workloads are Ready, and public HTTPS remains
   healthy with the existing Rails secrets and TLS secret.

The workstation has limited free space.  The commands below stream the
current database from the source Service into the target pod and do not write a
new dump artifact on the workstation.  The first transfer uses a temporary
`gitlabhq_production_validation` database for isolated checks; the final
quiesced transfer creates the real `gitlabhq_production` database.

## Files and declarative phases

The base target resources are now in this directory and are included by the
Kustomization:

- `postgres-gitlab18-persistentvolume.yaml` uses the new retained host path
  `/mnt/userdata-clusterfiles/k3s-volumes/postgres-gitlab18`.
- `postgres-gitlab18-persistentvolumeclaim.yaml` binds that PV as
  `postgres-gitlab18-data`.
- `postgres-gitlab18-deployment.yaml` runs one PostgreSQL 18.6 pod without a
  host port, so it can be initialized and validated while PostgreSQL 17 still
  owns `127.0.0.1:5432`.
- `postgres-gitlab18-service.yaml` exposes only the target pod internally as
  `postgres-gitlab18.postgres.svc`.
- `postgres-gitlab18-required-extensions.sql` is applied after the database
  restore.

The following files are deliberately not referenced by the base Kustomization
until the coordinated cutover:

- `postgres-pg17-retire-patch.yaml` sets only the old `postgres` Deployment
  replicas to zero.  It does not delete or alter `postgres-data` PV/PVC.
- `postgres-gitlab18-hostport-patch.yaml` adds `hostIP: 127.0.0.1` and
  `hostPort: 5432` to the target after the old pod has terminated.
- `postgres-stable-service-gitlab18-patch.yaml` changes only the existing
  stable `postgres` Service selector from `app: postgres` to
  `app: postgres-gitlab18`.

Use separate reviewed commits or equivalent reconciliations for these phases:

1. **Prepare:** reconcile the four target resources.  Do not change the old
   Deployment, the stable `postgres` Service, or the existing PostgreSQL 18
   resources.
2. **Retire source:** after the final direct transfer and writer quiescence,
   add `postgres-pg17-retire-patch.yaml` and wait for the old pod to be gone.
   Keep the old PV/PVC and its Deployment manifest retained.
3. **Claim host port:** add `postgres-gitlab18-hostport-patch.yaml`, wait for
   the target rollout and readiness, then verify the node-local listener and
   the Tailscale `svc:postgres` route.
4. **Switch stable endpoint:** add
   `postgres-stable-service-gitlab18-patch.yaml`.  The GitLab `gitlab-db`
   secret continues to point at `postgres.postgres.svc.cluster.local`; no
   application secret or Rails configuration needs to change.

The cutover patches can be represented in `kustomization.yaml` as:

```yaml
patches:
  - path: postgres-pg17-retire-patch.yaml
  - path: postgres-gitlab18-hostport-patch.yaml
  - path: postgres-stable-service-gitlab18-patch.yaml
```

Do not add those patches until the corresponding phase.  Flux suspension and
resumption, if needed to make the phases atomic, is coordinated by the parent
task.  Any temporary GitLab HelmRelease or Kustomization suspension must be
removed at the end of the cutover.

## Preparation and isolated target validation

Use the repository kubeconfig and context for every command:

```sh
export KUBECONFIG=/home/sierra/.kube/containernode.yaml
export KUBE_CONTEXT=default
kubectl --context="$KUBE_CONTEXT" --request-timeout=20s ...
```

After the target Deployment is running, set `PG18_POD` to its Ready pod name.
Do not print secret values.  The target pod receives the existing
`postgres-auth` and `postgres-tls` Secrets, and its temporary Service is
`postgres-gitlab18`.

First verify that the target is truly new and empty except for its bootstrap
database.  Abort if either the validation or final GitLab database already
exists; never reuse a partially restored target.

```sh
PG18_POD="$(kubectl --context="$KUBE_CONTEXT" -n postgres \
  get pod -l app=postgres-gitlab18 \
  -o jsonpath='{.items[0].metadata.name}')"

kubectl --context="$KUBE_CONTEXT" -n postgres exec "$PG18_POD" -- \
  sh -ec '
    set -eu
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
      -Atqc "SELECT current_setting('\''server_version'\''), current_setting('\''data_directory'\'');"
    if test -n "$(psql -U "$POSTGRES_USER" -d postgres -Atqc \
      "SELECT datname FROM pg_database WHERE datname IN ('\''gitlabhq_production'\'', '\''gitlabhq_production_validation'\'')")"; then
      echo "target already contains a GitLab migration database; aborting" >&2
      exit 1
    fi
  '
```

Check locale availability on the target before creating the database.  The
source uses libc `en_US.utf8`, so a missing target locale is a hard blocker;
do not silently create the database with `C`.

```sh
kubectl --context="$KUBE_CONTEXT" -n postgres exec "$PG18_POD" -- \
  sh -ec 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c \
    "SELECT collname, collprovider, collversion FROM pg_collation \
     WHERE collname = '\''en_US.utf8'\'';"'
```

### Transfer global roles

Keep PostgreSQL 17 serving the stable `postgres` Service.  From the target
pod, stream the source global-role definitions directly into the target.  The
bootstrap `postgres` role is deliberately not recreated or altered because it
is initialized from the existing `postgres-auth` Secret; all other source
roles and memberships are transferred.

```sh
kubectl --context="$KUBE_CONTEXT" -n postgres exec "$PG18_POD" -- \
  bash -euo pipefail -c '
    PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall --globals-only \
      -h postgres.postgres.svc.cluster.local -p 5432 -U "$POSTGRES_USER" |
    sed \
      -e "/^CREATE ROLE postgres;$/d" \
      -e "/^ALTER ROLE postgres /d" |
    PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 \
      -U "$POSTGRES_USER" -d postgres
  '
```

If this command reports a role conflict other than the expected bootstrap
`postgres` role, stop and inspect it.  Do not force role ownership or reset a
password by hand.

### Create and restore the isolated validation database

Confirm that `gitlab` exists, that `en_US.utf8` is available, and that the
database does not exist.  Then create it from `template0` with the source
owner and locale:

```sh
kubectl --context="$KUBE_CONTEXT" -n postgres exec "$PG18_POD" -- \
  sh -ec '
    set -eu
    test "$(psql -U "$POSTGRES_USER" -d postgres -Atqc \
      "SELECT 1 FROM pg_roles WHERE rolname = '\''gitlab'\''")" = 1
    test -z "$(psql -U "$POSTGRES_USER" -d postgres -Atqc \
      "SELECT 1 FROM pg_database WHERE datname = '\''gitlabhq_production_validation'\''")"
    createdb -U "$POSTGRES_USER" -O gitlab -T template0 \
      --locale-provider=libc --lc-collate=en_US.utf8 --lc-ctype=en_US.utf8 \
      gitlabhq_production_validation
  '
```

Stream the current source database through the PostgreSQL 18.6 client into the
new target database.  This is the migration transfer itself; it is not a
second persistent backup artifact.

```sh
kubectl --context="$KUBE_CONTEXT" -n postgres exec "$PG18_POD" -- \
  bash -euo pipefail -c '
    PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -Fc \
      -h postgres.postgres.svc.cluster.local -p 5432 -U "$POSTGRES_USER" \
      -d gitlabhq_production |
    PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --verbose --exit-on-error \
      -U "$POSTGRES_USER" -d gitlabhq_production_validation
  '
```

Install the required target extensions after the restore.  This command reads
the repository SQL file but does not store credentials or dump data:

```sh
kubectl --context="$KUBE_CONTEXT" -n postgres exec -i "$PG18_POD" -- \
  sh -ec 'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" \
    -d gitlabhq_production_validation' \
  < infrastructure/containernode/postgres/postgres-gitlab18-required-extensions.sql
```

Run isolated validation while the stable Service still points to PostgreSQL
17.  Execute the following checks against the target by using `psql` in the
target pod:

```sql
SELECT current_setting('server_version'), current_setting('data_directory');
SELECT datname, pg_get_userbyid(datdba), datlocprovider, datcollate, datctype,
       datcollversion
  FROM pg_database WHERE datname = 'gitlabhq_production_validation';
SELECT extname, extversion FROM pg_extension ORDER BY extname;
SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin
  FROM pg_roles
 WHERE rolname IN ('postgres', 'gitlab', 'chat', 'grafana', 'synapse')
 ORDER BY rolname;
SELECT count(*) AS relations
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f');
SELECT pg_size_pretty(pg_database_size('gitlabhq_production_validation'));
```

The extension result must include `amcheck`, `btree_gist`, `pg_trgm`, and
`plpgsql`.  Compare the relation count, database size, and key table counts to
the source before proceeding.  Use a read-only GitLab Toolbox connection or
the target pod for representative reads; do not point GitLab writers at the
target yet.

## Final quiesced transfer

The validation database is only an isolated test copy.  Do not point GitLab at
it.  During the coordinated writer pause, create a fresh
`gitlabhq_production` database and stream the current PostgreSQL 17 database
into it.  The temporary validation database stays available until the final
copy has passed the target checks, so a failed final restore can be diagnosed
without touching the source.

```sh
kubectl --context="$KUBE_CONTEXT" -n postgres exec "$PG18_POD" -- \
  bash -euo pipefail -c '
    test -z "$(psql -U "$POSTGRES_USER" -d postgres -Atqc \
      "SELECT 1 FROM pg_database WHERE datname = '\''gitlabhq_production'\''")"
    createdb -U "$POSTGRES_USER" -O gitlab -T template0 \
      --locale-provider=libc --lc-collate=en_US.utf8 --lc-ctype=en_US.utf8 \
      gitlabhq_production
  '

kubectl --context="$KUBE_CONTEXT" -n postgres exec "$PG18_POD" -- \
  bash -euo pipefail -c '
    PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -Fc \
      -h postgres.postgres.svc.cluster.local -p 5432 -U "$POSTGRES_USER" \
      -d gitlabhq_production |
    PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --verbose --exit-on-error \
      -U "$POSTGRES_USER" -d gitlabhq_production
  '

kubectl --context="$KUBE_CONTEXT" -n postgres exec -i "$PG18_POD" -- \
  sh -ec 'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" \
    -d gitlabhq_production' \
  < infrastructure/containernode/postgres/postgres-gitlab18-required-extensions.sql
```

Repeat the version, locale/collation, role, extension, relation-count, size,
and representative-read checks against `gitlabhq_production`.  Confirm that
the GitLab role and memberships still match the source; no role recreation is
needed when they were unchanged during preparation.  Only after those checks
pass may the temporary validation database be removed:

```sh
kubectl --context="$KUBE_CONTEXT" -n postgres exec "$PG18_POD" -- \
  sh -ec 'dropdb -U "$POSTGRES_USER" --if-exists \
    gitlabhq_production_validation'
```

## Coordinated cutover

The parent task owns the deployment slot and writer coordination.  The
following order is required:

1. Confirm no schema or background migrations are pending and that the
   isolated target checks above pass.
2. Temporarily stop ingress writes by scaling or pausing GitLab webservice and
   Sidekiq.  Coordinate toolbox maintenance/migration jobs and any
   Gitaly-related jobs that could write GitLab metadata.  Keep Gitaly itself
   healthy unless the parent determines a specific job must be stopped.
   Verify no GitLab application sessions remain writing in `pg_stat_activity`.
3. While PostgreSQL 17 still serves `postgres.postgres.svc`, run the **Final
   quiesced transfer** above from the freshly quiesced source, then rerun
   extension and target validation.  This closes the write window without
   introducing another persistent dump.
4. Apply only `postgres-pg17-retire-patch.yaml`; wait for the old
   `postgres` pod to terminate and verify the old `postgres-data` PV/PVC remain
   Bound/retained.
5. Apply `postgres-gitlab18-hostport-patch.yaml`; wait for the target rollout
   and readiness.  Verify the node-local `127.0.0.1:5432` listener and the
   existing Tailscale `svc:postgres` TCP route.
6. Apply `postgres-stable-service-gitlab18-patch.yaml`.  Verify that
   `postgres` Endpoints now contain only the `postgres-gitlab18` pod and that
   a connection through `postgres.postgres.svc.cluster.local` returns
   PostgreSQL 18.6 and the GitLab database.
7. Resume GitLab Helm reconciliation and the paused writers.  Remove any
   temporary suspension or migration setting used for the cutover.  Do not
   make a permanent GitLab URL, Rails secret, TLS secret, or database Service
   name change.
8. Verify Rails and background migration status, webservice/Sidekiq/Gitaly
   readiness, GitLab shell access, a read and write through the application,
   and the public HTTPS endpoint/certificate.  A native GitLab backup is not a
   migration exit criterion for this run.

During steps 2 through 6, watch the target pod, Service endpoints, and
application logs.  If any target validation or readiness check fails, keep
writers stopped and roll back before resuming them.

## Rollback

Rollback is safest before GitLab writers resume:

1. Keep webservice, Sidekiq, and coordinated writer jobs stopped.
2. Remove the stable-Service target patch and restore the stable selector to
   `app: postgres`.
3. Remove the target host-port patch, wait for the target pod to stop using
   `127.0.0.1:5432`, then set the old `postgres` Deployment replicas back to
   one.  Never start the old pod while the target still claims host port
   5432.
4. Wait for PostgreSQL 17 readiness and verify the old PV/PVC/data directory
   are unchanged.  The target PV/PVC and target data remain retained for
   diagnosis; do not attach the PostgreSQL 17 directory to PostgreSQL 18.
5. Resume the stable Service and GitLab writers only after source checks pass.

If writers have already resumed against PostgreSQL 18, do not blindly switch
back: first quiesce them and assess writes made after cutover.  The old data
directory cannot contain those writes, so any post-cutover rollback requires a
separately reviewed data reconciliation decision.
