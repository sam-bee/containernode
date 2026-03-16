#!/bin/sh
set -eu

config_path="${WG_CONFIG_PATH:-/vpn-secret/wg0.conf}"
pod_iface="${POD_IFACE:-eth0}"

endpoint="$(awk -F' = ' '/^Endpoint[[:space:]]*=/{print $2; exit}' "$config_path")"
if [ -z "$endpoint" ]; then
  echo "missing Endpoint in ${config_path}" >&2
  exit 1
fi

endpoint_host="${endpoint%:*}"
endpoint_port="${endpoint##*:}"
endpoint_host="${endpoint_host#[}"
endpoint_host="${endpoint_host%]}"

iptables -F OUTPUT
iptables -P OUTPUT DROP
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

if printf '%s' "$endpoint_host" | grep -q ':'; then
  ip6tables -F OUTPUT
  ip6tables -P OUTPUT DROP
  ip6tables -A OUTPUT -o lo -j ACCEPT
  ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A OUTPUT -o "$pod_iface" -p udp -d "$endpoint_host" --dport "$endpoint_port" -j ACCEPT
else
  iptables -A OUTPUT -o "$pod_iface" -p udp -d "$endpoint_host" --dport "$endpoint_port" -j ACCEPT

  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -F OUTPUT
    ip6tables -P OUTPUT DROP
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  fi
fi
