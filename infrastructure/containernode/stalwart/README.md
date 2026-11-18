# Stalwart and Email MCP

Stalwart hosts `nightwatch-research.co.uk` at
`mail.nightwatch-research.co.uk`. The initial mailbox is
`agents@nightwatch-research.co.uk`, with `postmaster@nightwatch-research.co.uk`
as an alias. The domain's `catchAllAddress` points to the agent mailbox
so mail to unassigned addresses at this domain goes there too.

| Cloudflare record | Name | Target | Priority |
| --- | --- | --- | --- |
| A (DNS only) | `mail` | `51.75.167.127` | |
| MX | `@` | `mail.nightwatch-research.co.uk` | 10 |

Allow public TCP 25 to containernode. Stalwart renews its STARTTLS certificate
through HTTP-01 on Traefik's existing TCP 80 listener. The Ingress serves only
the challenge path on the mail hostname. JMAP stays on the internal Service at
`http://stalwart-jmap.stalwart.svc.cluster.local:8080/.well-known/jmap`, with pod
access limited to Email MCP. The JMAP session advertises the same internal hostname for API requests.
Administrators can port-forward the JMAP Service and call the API directly.

```sh
kubectl -n stalwart port-forward svc/stalwart-jmap 8080:8080
```

In a second terminal, request the domain configuration. Curl prompts for the
administrator password.

```sh
curl -fsS --user admin@nightwatch-research.co.uk \
  -H 'Content-Type: application/json' http://127.0.0.1:8080/jmap \
  -d '{"using":["urn:ietf:params:jmap:core","urn:stalwart:jmap"],"methodCalls":[["x:Domain/get",{},"domains"]]}'
```

The Stalwart namespace has separate SOPS-managed Secrets named
`stalwart-admin` and `stalwart-agents` with `username` and `password` keys. The application stores both its registry
and mailbox data on the `stalwart-data` claim. Preserve both
`/var/lib/stalwart/config.json` and `/var/lib/stalwart/db` when backing up or
restoring the volume. Bootstrap uses a temporary operator tunnel to port 18080.

Email MCP is a separate service. Pushes to `sam-bee/email-mcp` on `master`
publish a private GHCR image. Flux tracks the digest of `latest` and rolls out
updates from the containernode repository. Its `email-mcp-ghcr` Secrets use the
same package reader as Lifeblood and Casefile. Rotate the copies together.

The Tailscale Services entry is `svc:email-mcp` on `tcp:443`. Once its host is
approved, use the service's MagicDNS hostname with the path `/mcp`. The
service uses the official Go MCP SDK and exposes two read-only tools.
`list_recent_messages` lists the last hour of messages across the agent
mailbox. `get_message_body` retrieves text and HTML body parts by JMAP ID.

The deployment reads a Stalwart API key from the SOPS-managed
`email-mcp-jmap` Secret. The key belongs to the agent mailbox and grants only
`authenticate`, `jmapEmailQuery` and `jmapEmailGet`. To rotate it, create a
replacement with the same permissions, update the Secret, restart the
deployment and revoke the old key.

## Thunderbird

Approve the `containernode` host for `svc:nightwatch-imap` on `tcp:993`
in Tailscale Services. In Thunderbird's manual account configuration, set
the incoming protocol to IMAP, use the service's MagicDNS hostname and port
993, choose SSL/TLS and Normal password, and sign in as
`agents@nightwatch-research.co.uk`. On the incoming-server screen, use
**Advanced Configuration** to save the account for reading mail.

Retrieve the IMAP password in a private terminal with the cluster context.

```sh
kubectl -n stalwart get secret stalwart-agents -o jsonpath='{.data.password}' | base64 -d
printf '\n'
```

Tailscale Serve terminates TLS and forwards from the node to the fixed
ClusterIP of `stalwart-imap`. The Stalwart registry has an `imap-serve`
listener on port 1143 with TLS off for this private hop. Its Imap singleton
allows password authentication on that hop. The ingress policy grants IMAP
access to node-local traffic only.

## Outgoing SMTP

Define `nightwatch-smtp` with endpoint `tcp:465` in Tailscale Services and
approve its `containernode` host. In Thunderbird's Outgoing Server (SMTP)
settings, enter that service's MagicDNS hostname, port 465, SSL/TLS, Normal
password and username `agents@nightwatch-research.co.uk`. Use the same
mailbox password as IMAP. Assign the server to the Nightwatch account.

Tailscale Serve terminates TLS and forwards from the node to
`stalwart-submission`. The Stalwart registry has a `submission-serve` listener
on port 1587. The `MtaStageAuth` policy advertises PLAIN and LOGIN on that
listener, requires authentication for submission, and checks the envelope
sender against the authenticated account.

Stalwart sends directly from `51.75.167.127` over TCP 25. With this as the
domain's only sender, publish the following Cloudflare records.

| Type | Name | Value |
| --- | --- | --- |
| TXT | `@` | `v=spf1 ip4:51.75.167.127 -all` |
| TXT | `mail` | `v=spf1 ip4:51.75.167.127 -all` |
| TXT | `_dmarc` | `v=DMARC1; p=none` |
| TXT | RSA selector under `_domainkey` | Public key from the domain's `dnsZoneFile` field |

Set the sending IP's PTR at the IP provider to
`mail.nightwatch-research.co.uk`.
