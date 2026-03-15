#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="/opt/containernode-github-repo/containernode"
TAILSCALE_DIR="$REPO_DIR/tailscale"
TEMPLATE_FILE="$TAILSCALE_DIR/serve-config.template.json"
RENDERED_FILE="$TAILSCALE_DIR/serve-config.json"

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

: "${TAILNET_NAME:?TAILNET_NAME is not set}"
export TAILNET_NAME

log "Rendering serve config from template"
envsubst '${TAILNET_NAME}' < "$TEMPLATE_FILE" > "$RENDERED_FILE"

log "Rendered config file: $RENDERED_FILE"
test -f "$RENDERED_FILE"

log "Applying Tailscale Serve config"
tailscale serve set-config "$RENDERED_FILE" --all

log "Tailscale Serve config applied successfully"
dump_tailscale_debug
