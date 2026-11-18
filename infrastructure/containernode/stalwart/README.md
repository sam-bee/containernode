# Stalwart and Email MCP

Stalwart hosts `nightwatch-research.co.uk` at
`mail.nightwatch-research.co.uk`. The initial mailbox is
`agents@nightwatch-research.co.uk`, with `postmaster@nightwatch-research.co.uk`
as an alias.

| Cloudflare record | Name | Target | Priority |
| --- | --- | --- | --- |
| A (DNS only) | `mail` | `51.75.167.127` | |
| MX | `@` | `mail.nightwatch-research.co.uk` | 10 |

Allow public TCP 25 to containernode. Stalwart renews its STARTTLS certificate
through HTTP-01 on Traefik's existing TCP 80 listener. The Ingress serves only
the challenge path on the mail hostname. JMAP stays on the internal Service at
`http://stalwart-jmap.stalwart.svc.cluster.local:8080/.well-known/jmap`, with pod
access limited to Email MCP. Administrators can use Kubernetes port forwarding.

```sh
kubectl -n stalwart port-forward svc/stalwart-jmap 8080:8080
```

Open `http://127.0.0.1:8080/admin` over that tunnel. The Stalwart namespace has
separate SOPS-managed Secrets named `stalwart-admin` and `stalwart-agents`
with `username` and `password` keys. The application stores both its registry
and mailbox data on the `stalwart-data` claim. Preserve both
`/var/lib/stalwart/config.json` and `/var/lib/stalwart/db` when backing up or
restoring the volume. Bootstrap uses a temporary operator tunnel to port 18080.

Email MCP is a separate service. Pushes to `sam-bee/email-mcp` on `master`
publish a private GHCR image. Flux tracks the digest of `latest` and rolls out
updates from the containernode repository. Its `email-mcp-ghcr` Secrets use the
same package reader as Lifeblood and Casefile. Rotate the copies together.

The Tailscale Services entry is `svc:email-mcp` on `tcp:443`. Once its host is
approved, use the service's MagicDNS hostname with the path `/mcp`. The
placeholder exposes zero tools and has no mailbox credentials mounted.
