#!/usr/bin/env bash
set -Eeuo pipefail

tailscale serve --service=svc:jellyfin --https=443 http://127.0.0.1:8096
tailscale serve --service=svc:postgres --tcp=5432 tcp://127.0.0.1:5432
tailscale serve --service=svc:transmission --https=443 http://127.0.0.1:9091
