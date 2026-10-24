#!/usr/bin/env bash

set -Eeuo pipefail

umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TARGET_VERSION="$(tr -d '\r\n' < "${SCRIPT_DIR}/k3s-version")"
readonly TARGET_VERSION
readonly KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
readonly K3S_BINARY="/usr/local/bin/k3s"
readonly K3S_DATA_DIR="/var/lib/rancher/k3s"
readonly BACKUP_ROOT="/var/backups/k3s"
readonly REQUIRED_FLUX_VERSION="v2.9.4"
readonly REQUIRED_CERT_MANAGER_VERSION="v1.21.3"
readonly REQUIRED_GITLAB_VERSION="v19.5.1"
readonly -a UPGRADE_VERSIONS=(
  "v1.34.10+k3s1"
  "v1.35.7+k3s1"
  "v1.36.3+k3s1"
  "v1.36.5+k3s1"
  "v1.37.1+k3s1"
)
declare -Ar K3S_SHA256=(
  ["v1.34.10+k3s1"]="e63a3511b2603fd1436a1ea8d228348a3b47334b45024801d41a8c0e2d22e8c4"
  ["v1.35.7+k3s1"]="5fc25309c53031e0cf03f7ee85f6f60969381ff3649039ffda19e30f5c26947a"
  ["v1.36.3+k3s1"]="2f98a9f8fe5782479ee2d54e70a1b10a7f6fd4cae8d38ed3098452dc6eed76b5"
  ["v1.36.5+k3s1"]="d73847bcd3c5fccef0115b372e2f9a91f3032dc84bbf71518a4617565294d313"
  ["v1.37.1+k3s1"]="92b94582eb7b34a8cf532e6006842b9ed215a6783cf56a3dd6271fd35243b2c0"
)
TEMP_DIR=""

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

kube() {
  KUBECONFIG="${KUBECONFIG_PATH}" "${K3S_BINARY}" kubectl "$@"
}

installed_version() {
  "${K3S_BINARY}" --version | awk 'NR == 1 { print $3 }'
}

version_is_older() {
  local first

  [[ "$1" != "$2" ]] || return 1
  first="$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)"
  [[ "${first}" == "$1" ]]
}

node_version() {
  kube get node "$1" -o jsonpath='{.status.nodeInfo.kubeletVersion}'
}

wait_for_cluster() {
  local expected_version="$1"
  local node_name="$2"

  for _ in $(seq 1 150); do
    if systemctl is-active --quiet k3s \
      && kube get --raw=/readyz >/dev/null 2>&1 \
      && [[ "$(node_version "${node_name}" 2>/dev/null)" == "${expected_version}" ]]; then
      return 0
    fi
    sleep 2
  done

  return 1
}

not_ready_pod_count() {
  kube get pods --all-namespaces -o json | jq '[
    .items[]
    | select(.status.phase != "Succeeded")
    | (.status.containerStatuses // []) as $statuses
    | select(
        .status.phase != "Running"
        or ($statuses | length) == 0
        or ([$statuses[].ready] | all) == false
      )
  ] | length'
}

not_ready_reconciliation_count() {
  kube get kustomizations,gitrepositories,helmreleases --all-namespaces -o json | jq '[
    .items[]
    | select(
        .spec.suspend == true
        or .status.observedGeneration != .metadata.generation
        or ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) == 0
      )
  ] | length'
}

require_active_sqlite() {
  local process_id
  local database_path
  local descriptor
  local opened_path

  [[ -f "${K3S_DATA_DIR}/server/db/state.db" ]] \
    || die "expected the single-node SQLite datastore at ${K3S_DATA_DIR}/server/db/state.db"
  # K3s itself uses the WAL directory to identify initialized embedded etcd.
  # The parent etcd directory may exist even when the cluster uses SQLite.
  [[ ! -d "${K3S_DATA_DIR}/server/db/etcd/member/wal" \
    && ! -f "${K3S_DATA_DIR}/server/db/etcd/member/snap/db" ]] \
    || die "initialized embedded etcd was found; this helper supports SQLite only"

  process_id="$(systemctl show k3s --property=MainPID --value)" \
    || die "could not identify the running k3s process"
  [[ "${process_id}" =~ ^[1-9][0-9]*$ && -d "/proc/${process_id}/fd" ]] \
    || die "could not inspect the running k3s process"
  database_path="$(readlink -f "${K3S_DATA_DIR}/server/db/state.db")" \
    || die "could not resolve the SQLite database path"
  for descriptor in /proc/"${process_id}"/fd/*; do
    opened_path="$(readlink "${descriptor}" 2>/dev/null)" || continue
    [[ "${opened_path}" == "${database_path}" ]] && return 0
  done
  die "the running k3s process does not have the expected SQLite database open; verify its datastore configuration"
}

wait_for_workloads() {
  for _ in $(seq 1 180); do
    if [[ "$(not_ready_pod_count 2>/dev/null)" == "0" ]] \
      && [[ "$(not_ready_reconciliation_count 2>/dev/null)" == "0" ]] \
      && [[ "$(kube get certificate gitlab-web-tls -n gitlab \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == "True" ]]; then
      return 0
    fi
    sleep 2
  done

  return 1
}

download_release() {
  local version="$1"
  local destination="$2"
  local encoded_version="${version/+/%2B}"
  local expected_sha256="${K3S_SHA256[${version}]}"
  local downloaded_version

  printf 'Downloading %s...\n' "${version}"
  curl \
    --fail \
    --location \
    --retry 3 \
    --show-error \
    --silent \
    --output "${destination}" \
    "https://github.com/k3s-io/k3s/releases/download/${encoded_version}/k3s"

  printf '%s  %s\n' "${expected_sha256}" "${destination}" | sha256sum --check --status \
    || die "checksum verification failed for ${version}"
  chmod 0755 "${destination}"
  downloaded_version="$("${destination}" --version | awk 'NR == 1 { print $3 }')"
  [[ "${downloaded_version}" == "${version}" ]] \
    || die "downloaded binary reports ${downloaded_version}, expected ${version}"
}

create_backup() {
  local current_version="$1"
  local node_name="$2"
  local timestamp
  local backup_dir

  timestamp="$(date --utc +%Y%m%dT%H%M%SZ)"
  backup_dir="${BACKUP_ROOT}/pre-upgrade-${current_version}-${timestamp}"
  install -d -m 0700 "${backup_dir}" || die "failed to create the backup directory"

  cp --archive "${K3S_BINARY}" "${backup_dir}/k3s" \
    || die "failed to back up the k3s binary"
  cp --archive /etc/rancher/k3s "${backup_dir}/etc-rancher-k3s" \
    || die "failed to back up the k3s configuration"
  cp --archive /etc/systemd/system/k3s.service "${backup_dir}/k3s.service" \
    || die "failed to back up the k3s service unit"
  cp --archive /etc/systemd/system/k3s.service.env "${backup_dir}/k3s.service.env" \
    || die "failed to back up the k3s service environment"

  [[ -f "${K3S_DATA_DIR}/server/db/state.db" ]] \
    || die "expected the single-node SQLite datastore at ${K3S_DATA_DIR}/server/db/state.db"
  [[ -f "${K3S_DATA_DIR}/server/token" ]] \
    || die "server token not found at ${K3S_DATA_DIR}/server/token"

  printf 'Stopping k3s for a consistent SQLite backup...\n' >&2
  systemctl stop k3s || die "could not stop k3s for a consistent backup"
  if ! cp --archive "${K3S_DATA_DIR}/server/db" "${backup_dir}/db" \
    || ! cp --archive "${K3S_DATA_DIR}/server/token" "${backup_dir}/token"; then
    systemctl start k3s || true
    die "datastore backup failed"
  fi
  systemctl start k3s || die "could not restart k3s after the backup"

  wait_for_cluster "${current_version}" "${node_name}" \
    || die "k3s did not recover after the backup; inspect: journalctl -u k3s"

  (
    cd "${backup_dir}"
    find . -type f -print0 \
      | sort -z \
      | xargs -0 sha256sum
  ) > "${TEMP_DIR}/SHA256SUMS" || die "failed to checksum the backup"
  install -m 0600 "${TEMP_DIR}/SHA256SUMS" "${backup_dir}/SHA256SUMS" \
    || die "failed to save the backup checksums"

  printf '%s\n' "${backup_dir}"
}

upgrade_to() {
  local version="$1"
  local candidate="$2"
  local node_name="$3"

  printf 'Installing %s...\n' "${version}"
  install -o root -g root -m 0755 "${candidate}" "${K3S_BINARY}"
  systemctl restart k3s

  wait_for_cluster "${version}" "${node_name}" \
    || die "k3s ${version} did not become ready; inspect: journalctl -u k3s"
  wait_for_workloads \
    || die "workloads, Flux or the GitLab certificate did not recover after installing ${version}"

  printf 'Cluster is healthy on %s.\n' "${version}"
}

main() {
  local check_only=false
  local current_version
  local node_name
  local flux_version
  local cert_manager_version
  local cert_manager_ready
  local gitlab_version
  local certificate_ready
  local certificate_issuing
  local certificate_expiry
  local certificate_expiry_epoch
  local backup_dir
  local version
  local -a nodes

  case "${1:-}" in
    --check)
      [[ "$#" -eq 1 ]] || die "usage: $0 [--check]"
      check_only=true
      ;;
    --help|-h)
      printf 'Usage: %s [--check]\n\n' "$0"
      printf '  --check  Validate prerequisites and release downloads without stopping or upgrading k3s.\n'
      return 0
      ;;
    "") [[ "$#" -eq 0 ]] || die "usage: $0 [--check]" ;;
    *) die "usage: $0 [--check]" ;;
  esac

  [[ "${EUID}" -eq 0 ]] || die "run this script with sudo"
  [[ "$(uname -m)" == "x86_64" ]] || die "only the containernode amd64 host is supported"
  [[ "${TARGET_VERSION}" == "${UPGRADE_VERSIONS[-1]}" ]] \
    || die "k3s-version is not represented by the validated upgrade path"

  for command in awk chmod cp curl date find head install jq mktemp readlink seq sha256sum sort systemctl xargs; do
    require_command "${command}"
  done
  [[ -x "${K3S_BINARY}" ]] || die "k3s binary not found at ${K3S_BINARY}"
  [[ -r "${KUBECONFIG_PATH}" ]] || die "kubeconfig not found at ${KUBECONFIG_PATH}"
  systemctl is-active --quiet k3s || die "k3s service is not active"

  current_version="$(installed_version)"
  case "${current_version}" in
    v1.34.*+k3s*|v1.35.*+k3s*|v1.36.*+k3s*|v1.37.*+k3s*) ;;
    *) die "unsupported starting version: ${current_version}" ;;
  esac

  if [[ "${current_version}" == "${TARGET_VERSION}" && "${check_only}" == false ]]; then
    printf 'k3s is already at %s.\n' "${TARGET_VERSION}"
    exit 0
  fi
  version_is_older "${TARGET_VERSION}" "${current_version}" \
    && die "refusing to downgrade from ${current_version} to ${TARGET_VERSION}"

  [[ ! -e /sys/fs/selinux/enforce ]] \
    || die "SELinux is enabled; review Kubernetes 1.37 volume-labeling changes before using this helper"

  mapfile -t nodes < <(kube get nodes -o name)
  [[ "${#nodes[@]}" -eq 1 ]] || die "expected exactly one Kubernetes node"
  node_name="${nodes[0]#node/}"
  [[ "$(node_version "${node_name}")" == "${current_version}" ]] \
    || die "the k3s binary and node kubelet versions do not match"

  for controller in source-controller kustomize-controller helm-controller notification-controller; do
    flux_version="$(
      kube get deployment "${controller}" -n flux-system \
        -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}'
    )"
    [[ "${flux_version}" == "${REQUIRED_FLUX_VERSION}" ]] \
      || die "${controller} must be upgraded to Flux ${REQUIRED_FLUX_VERSION} first"
  done

  cert_manager_version="$(
    kube get helmrelease cert-manager -n cert-manager \
      -o jsonpath='{.spec.chart.spec.version}'
  )"
  cert_manager_ready="$(
    kube get helmrelease cert-manager -n cert-manager \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  )"
  [[ "${cert_manager_version}" == "${REQUIRED_CERT_MANAGER_VERSION}" \
    && "${cert_manager_ready}" == "True" ]] \
    || die "cert-manager ${REQUIRED_CERT_MANAGER_VERSION} must be ready before the upgrade"

  gitlab_version="$(
    kube get helmrelease gitlab -n gitlab -o jsonpath='{.status.history[0].appVersion}'
  )"
  [[ "${gitlab_version}" == "${REQUIRED_GITLAB_VERSION}" ]] \
    || die "GitLab ${REQUIRED_GITLAB_VERSION} must be installed before the Kubernetes 1.37 upgrade"

  certificate_ready="$(
    kube get certificate gitlab-web-tls -n gitlab \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  )"
  certificate_issuing="$(
    kube get certificate gitlab-web-tls -n gitlab \
      -o jsonpath='{.status.conditions[?(@.type=="Issuing")].status}'
  )"
  certificate_expiry="$(
    kube get certificate gitlab-web-tls -n gitlab -o jsonpath='{.status.notAfter}'
  )"
  [[ "${certificate_ready}" == "True" && "${certificate_issuing}" != "True" ]] \
    || die "the GitLab public certificate must be ready and its renewal complete before the upgrade"
  certificate_expiry_epoch="$(date --date="${certificate_expiry}" +%s)" \
    || die "could not parse the GitLab certificate expiry"
  [[ -n "${certificate_expiry}" && "${certificate_expiry_epoch}" -gt "$(($(date +%s) + 30 * 86400))" ]] \
    || die "renew the GitLab public certificate first; at least 30 days of validity are required"

  [[ "$(not_ready_pod_count)" == "0" ]] \
    || die "one or more pods are not ready before the upgrade"
  [[ "$(not_ready_reconciliation_count)" == "0" ]] \
    || die "one or more Flux reconciliations are suspended or not ready"

  require_active_sqlite
  [[ -s "${K3S_DATA_DIR}/server/token" ]] || die "k3s server token is missing or empty"
  [[ -f "${K3S_DATA_DIR}/server/manifests/local-storage.yaml.skip" ]] \
    || die "install the local-storage.yaml.skip marker before restarting k3s; see docs/MAINTENANCE.md"
  [[ -r /etc/systemd/system/k3s.service && -r /etc/systemd/system/k3s.service.env ]] \
    || die "the k3s service unit or environment file is missing"

  printf 'Preflight passed: %s -> %s; workloads and Flux are healthy; SQLite, token and skip marker exist.\n' \
    "${current_version}" "${TARGET_VERSION}"
  printf 'GitLab %s is installed; its public certificate is valid through %s.\n' \
    "${gitlab_version}" "${certificate_expiry}"

  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf -- "${TEMP_DIR}"' EXIT

  for version in "${UPGRADE_VERSIONS[@]}"; do
    if version_is_older "${current_version}" "${version}"; then
      download_release "${version}" "${TEMP_DIR}/k3s-${version}"
    fi
  done

  if [[ "${check_only}" == true ]]; then
    printf 'Release downloads verified. No backup, service restart or upgrade was performed.\n'
    return 0
  fi

  backup_dir="$(create_backup "${current_version}" "${node_name}")"
  printf 'Backup written to %s.\n' "${backup_dir}"

  for version in "${UPGRADE_VERSIONS[@]}"; do
    if version_is_older "${current_version}" "${version}"; then
      upgrade_to "${version}" "${TEMP_DIR}/k3s-${version}" "${node_name}"
      current_version="${version}"
    fi
  done

  [[ "$(installed_version)" == "${TARGET_VERSION}" ]] \
    || die "final k3s version does not match ${TARGET_VERSION}"
  printf 'k3s upgrade complete: %s\n' "${TARGET_VERSION}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
