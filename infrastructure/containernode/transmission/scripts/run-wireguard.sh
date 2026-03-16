#!/bin/sh
set -eu

config_path="${WG_CONFIG_PATH:-/vpn-secret/wg0.conf}"
runtime_config="${WG_RUNTIME_CONFIG:-/run/wireguard/wg0.conf}"
pod_iface="${POD_IFACE:-eth0}"

cleanup() {
  wg-quick down "$runtime_config" >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

sed '/^[[:space:]]*DNS[[:space:]]*=.*/d' "$config_path" > "$runtime_config"
chmod 600 "$runtime_config"

wg-quick up "$runtime_config"

iptables -C OUTPUT -o wg0 -j ACCEPT 2>/dev/null || iptables -A OUTPUT -o wg0 -j ACCEPT
for cidr in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10; do
  iptables -C OUTPUT -o "$pod_iface" -d "$cidr" -j ACCEPT 2>/dev/null || \
    iptables -A OUTPUT -o "$pod_iface" -d "$cidr" -j ACCEPT
done

if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -C OUTPUT -o wg0 -j ACCEPT 2>/dev/null || ip6tables -A OUTPUT -o wg0 -j ACCEPT
  for cidr in fc00::/7 fe80::/10; do
    ip6tables -C OUTPUT -o "$pod_iface" -d "$cidr" -j ACCEPT 2>/dev/null || \
      ip6tables -A OUTPUT -o "$pod_iface" -d "$cidr" -j ACCEPT
  done
fi

while true; do
  sleep 3600
done
