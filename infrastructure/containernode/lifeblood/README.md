# Lifeblood

Source and API documentation: https://github.com/sam-bee/lifeblood

Lifeblood is available only through the Tailscale Service `svc:lifeblood` on
HTTPS port 443. Tailscale Serve proxies to the pod's host-local listener at
`127.0.0.1:8091`; there is no public ingress. The API also requires its bearer
token. The node's Tailscale Service configuration is in
`tailscale/run-tailscale-serve.sh`.

The dedicated database lives on postgres18 with separate runtime and migration
roles. Credentials and the callback origin are SOPS encrypted. With public
webhooks disabled, Oura data is reconciled periodically instead of arriving via
webhook. Relinking requires registering the tailnet callback URL with Oura and
opening the authorization link from a device on the tailnet.

GitHub Actions publishes the private image; Flux updates both deployment images.
NetworkPolicy permits host-origin traffic, DNS, PostgreSQL, and outbound public
HTTPS. Keep the encryption key with database backups. The database connection
uses the cluster's existing encrypted `sslmode=require` convention.
