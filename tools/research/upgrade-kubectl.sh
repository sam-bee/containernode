#!/usr/bin/env bash

set -Eeuo pipefail

readonly KUBECTL_VERSION="v1.36.3"
readonly KUBECTL_SHA256="ebbd080e7c2e275093b55915722043257eb24004363e20acb3c4d71919f88336"
readonly INSTALL_PATH="/usr/local/bin/kubectl"
readonly DOWNLOAD_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

if (( EUID != 0 )); then
  echo "Run this script with sudo: sudo $0" >&2
  exit 1
fi

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "This pinned installer supports Linux x86_64 only." >&2
  exit 1
fi

for command_name in curl install mktemp mv sha256sum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 1
  fi
done

current_path="$(command -v kubectl 2>/dev/null || true)"
if [[ -n "$current_path" ]]; then
  echo "Current kubectl: $current_path"
  "$current_path" version --client
else
  echo "No kubectl currently resolves through PATH."
fi

temporary_directory="$(mktemp -d /tmp/kubectl-upgrade.XXXXXX)"
download_path="${temporary_directory}/kubectl"
staging_path=""

cleanup() {
  if [[ -n "$staging_path" ]]; then
    rm -f -- "$staging_path"
  fi
  rm -f -- "$download_path"
  rmdir -- "$temporary_directory" 2>/dev/null || true
}
trap cleanup EXIT

echo "Downloading kubectl ${KUBECTL_VERSION} from dl.k8s.io ..."
curl \
  --fail \
  --location \
  --proto '=https' \
  --silent \
  --show-error \
  --tlsv1.2 \
  --output "$download_path" \
  "$DOWNLOAD_URL"

actual_sha256="$(sha256sum "$download_path")"
actual_sha256="${actual_sha256%% *}"
if [[ "$actual_sha256" != "$KUBECTL_SHA256" ]]; then
  echo "Checksum verification failed." >&2
  echo "Expected: $KUBECTL_SHA256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi

chmod 0755 "$download_path"
echo "Downloaded binary reports:"
"$download_path" version --client

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -e "$INSTALL_PATH" ]]; then
  backup_path="${INSTALL_PATH}.backup.${timestamp}"
  echo "Backing up existing $INSTALL_PATH to $backup_path"
  cp --archive -- "$INSTALL_PATH" "$backup_path"
fi

staging_path="${INSTALL_PATH}.new.$$"
install -o root -g root -m 0755 "$download_path" "$staging_path"
mv -f -- "$staging_path" "$INSTALL_PATH"
staging_path=""
hash -r

echo
echo "Installed kubectl at $INSTALL_PATH"
"$INSTALL_PATH" version --client

resolved_path="$(command -v kubectl 2>/dev/null || true)"
if [[ "$resolved_path" != "$INSTALL_PATH" ]]; then
  echo >&2
  echo "Warning: kubectl currently resolves to '${resolved_path:-nothing}', not $INSTALL_PATH." >&2
  echo "Ensure /usr/local/bin precedes /usr/bin in PATH, then run: hash -r" >&2
  exit 1
fi

echo
echo "Upgrade complete. The apt-managed /usr/bin/kubectl was left unchanged as a fallback."
echo "Run 'kubectl version' without sudo to confirm both client and server versions."
