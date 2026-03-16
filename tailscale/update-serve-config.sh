#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVE_SCRIPT="$SCRIPT_DIR/run-tailscale-serve.sh"

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

log "Applying Tailscale Serve config with $SERVE_SCRIPT"
"$SERVE_SCRIPT"

log "Tailscale Serve config applied successfully"
dump_tailscale_debug
