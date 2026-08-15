#!/usr/bin/env bash

set -Eeuo pipefail

readonly FLUX_VERSION="2.9.4"
readonly ARCHIVE_SHA256="c2c397a52930f52d2005c01d276116b059d062de379386d58e98115380a766a2"
readonly INSTALL_PATH="/usr/local/bin/flux"
readonly ARCHIVE_NAME="flux_${FLUX_VERSION}_linux_amd64.tar.gz"
readonly DOWNLOAD_URL="https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/${ARCHIVE_NAME}"

if (( EUID != 0 )); then
  echo "Run this script with sudo: sudo $0" >&2
  exit 1
fi

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "This pinned installer supports Linux x86_64 only." >&2
  exit 1
fi

for command_name in curl install mktemp mv sha256sum tar; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 1
  fi
done

current_path="$(command -v flux 2>/dev/null || true)"
if [[ -n "$current_path" ]]; then
  echo "Current Flux CLI: $current_path"
  "$current_path" --version
else
  echo "No Flux CLI currently resolves through PATH."
fi

temporary_directory="$(mktemp -d /tmp/flux-upgrade.XXXXXX)"
archive_path="${temporary_directory}/${ARCHIVE_NAME}"
extracted_path="${temporary_directory}/flux"
staging_path=""

cleanup() {
  if [[ -n "$staging_path" ]]; then
    rm -f -- "$staging_path"
  fi
  rm -f -- "$extracted_path" "$archive_path"
  rmdir -- "$temporary_directory" 2>/dev/null || true
}
trap cleanup EXIT

echo "Downloading Flux CLI ${FLUX_VERSION} from the official GitHub release ..."
curl \
  --fail \
  --location \
  --proto '=https' \
  --silent \
  --show-error \
  --tlsv1.2 \
  --output "$archive_path" \
  "$DOWNLOAD_URL"

actual_sha256="$(sha256sum "$archive_path")"
actual_sha256="${actual_sha256%% *}"
if [[ "$actual_sha256" != "$ARCHIVE_SHA256" ]]; then
  echo "Checksum verification failed." >&2
  echo "Expected: $ARCHIVE_SHA256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi

tar \
  --extract \
  --gzip \
  --file "$archive_path" \
  --directory "$temporary_directory" \
  --no-same-owner \
  --no-same-permissions \
  flux

chmod 0755 "$extracted_path"
echo "Downloaded binary reports:"
"$extracted_path" --version

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -e "$INSTALL_PATH" ]]; then
  backup_path="${INSTALL_PATH}.backup.${timestamp}"
  echo "Backing up existing $INSTALL_PATH to $backup_path"
  cp --archive -- "$INSTALL_PATH" "$backup_path"
fi

staging_path="${INSTALL_PATH}.new.$$"
install -o root -g root -m 0755 "$extracted_path" "$staging_path"
mv -f -- "$staging_path" "$INSTALL_PATH"
staging_path=""
hash -r

echo
echo "Installed Flux CLI at $INSTALL_PATH"
"$INSTALL_PATH" --version

resolved_path="$(command -v flux 2>/dev/null || true)"
if [[ "$resolved_path" != "$INSTALL_PATH" ]]; then
  echo >&2
  echo "Warning: flux currently resolves to '${resolved_path:-nothing}', not $INSTALL_PATH." >&2
  echo "Ensure /usr/local/bin is in PATH, then run: hash -r" >&2
  exit 1
fi

echo
echo "Upgrade complete. Run 'flux check' without sudo to verify cluster access."
