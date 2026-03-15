# Tailscale Files

`tailscale serve` is acting as a reverse proxy, for web applications only available on the tailnet.

`tailscale/serve-config.json` is the main config file that controls this.

`tailscale/serve-config.template.json` is a template without certain sensitive data in it, and is in version control.


## Role of Github Actions - templating

A Github Action can run something similar to this command:

```
envsubst < tailscale/serve-config.template.json > tailscale/serve-config.json
```

This runs on the Gihub Action runner, and results in a file with secrets injected.

## Role of Github Actions - using config

The Github Action can also do something like this:

```
tailscale serve set-config serve-config.json --all
```

This has the effect of loading the latest config changes.

`tailscale/`
