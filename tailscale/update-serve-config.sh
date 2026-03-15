#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="/opt/containernode-github-repo/containernode"
TAILSCALE_DIR="$REPO_DIR/tailscale"
SERVE_CONFIG_FILE="$TAILSCALE_DIR/serve-config.json"

log() {
  printf '[update-serve-config] %s\n' "$*" >&2
}

dump_tailscale_debug() {
  log "tailscale status:"
  tailscale status || true

  log "tailscale serve status:"
  tailscale serve status || true
}

on_error() {
  rc=$?
  log "ERROR: update failed with exit code $rc"
  dump_tailscale_debug
  exit "$rc"
}

trap on_error ERR

log "Updating local clone in $REPO_DIR"
cd "$REPO_DIR"

git reset --hard HEAD;
git fetch --all;
git switch --detach origin/main;

log "Applying Tailscale Serve config"
tailscale serve set-config --all "$SERVE_CONFIG_FILE"

log "Tailscale Serve config applied successfully"
dump_tailscale_debug
