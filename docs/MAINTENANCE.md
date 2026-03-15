# Maintenance Runbooks


## Expired Tailscale Auth Key

Go to the [Tailscale Auth Key](https://login.tailscale.com/admin/settings/keys) page and get a new one.

The token needs to be `Single-use`, `Ephemeral`, and should have the `ci` tag.

Go to [Github Action secrets config](https://github.com/sam-bee/containernode/settings/secrets/actions) and put the new key.

Needs doing every 90 days.

See Github tokens below


## Expired Github token on server

SSH into `containernode` server, and locate token in `/opt/containernode-github-repo`. Update.

The token needs read permissions on this repository only, and no other privileges.
