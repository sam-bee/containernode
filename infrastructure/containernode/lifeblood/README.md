# Lifeblood

Source and API documentation: https://github.com/sam-bee/lifeblood

One public Echo REST API at https://lifeblood.personalinfra.co.uk/oura with one
bearer token. No browser interface, SSO, Eufy implementation or Redis.

The dedicated lifeblood database lives on postgres18; lifeblood_app has only
runtime privileges and lifeblood_migrate owns this isolated database. Migration
credentials are injected only into the init container. All application and GHCR
credentials are SOPS encrypted. API and token-encryption keys were generated
randomly. Oura registration is pending; the service reports not_connected until
client credentials are configured and the operator runs /lifeblood link once.

GitHub Actions publishes private ghcr.io/sam-bee/lifeblood:latest. Flux resolves
the digest and updates both init and runtime images using casefile-flux-write.
The only public ingress path is /oura; probes stay internal. TLS is issued by
letsencrypt-production-dns01-cloudflare. NetworkPolicy permits Traefik ingress,
DNS, PostgreSQL 18 and public HTTPS egress for fixed Oura destinations.

Edit the encrypted config with sops and restart the Deployment after Flux applies
credential changes. Keep the encryption key with the database backup. This
initial deployment has no health records. The existing Postgres server certificate
does not cover postgres18's DNS name; database connections currently use the
same encrypted sslmode=require convention as Casefile.
