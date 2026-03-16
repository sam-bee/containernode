#!/usr/bin/env python3
import json
import os
import socket
import struct
import sys
import time
import urllib.error
import urllib.request


WG_CONFIG_PATH = os.environ.get("WG_CONFIG_PATH", "/vpn-secret/wg0.conf")
TRANSMISSION_RPC_URL = os.environ.get(
    "TRANSMISSION_RPC_URL", "http://127.0.0.1:9091/transmission/rpc"
)
PROTON_NATPMP_GATEWAY = os.environ.get("PROTON_NATPMP_GATEWAY")
LEASE_SECONDS = int(os.environ.get("PROTON_NATPMP_LEASE_SECONDS", "60"))
RENEW_SECONDS = int(os.environ.get("PROTON_NATPMP_RENEW_SECONDS", "45"))
RETRY_SECONDS = int(os.environ.get("PROTON_NATPMP_RETRY_SECONDS", "5"))
SOCKET_TIMEOUT_SECONDS = float(os.environ.get("PROTON_NATPMP_TIMEOUT_SECONDS", "5"))


def log(message: str) -> None:
    print(f"[proton-port-forward] {message}", flush=True)


def parse_natpmp_gateway(config_path: str) -> str:
    with open(config_path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line.startswith("DNS = "):
                continue

            for value in line.split("=", 1)[1].split(","):
                candidate = value.strip()
                if "." in candidate:
                    return candidate

    raise RuntimeError(f"no IPv4 Proton gateway found in {config_path}")


def natpmp_request(gateway: str, opcode: int, private_port: int, public_port: int) -> int:
    payload = struct.pack("!BBHHHI", 0, opcode, 0, private_port, public_port, LEASE_SECONDS)

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(SOCKET_TIMEOUT_SECONDS)
        sock.sendto(payload, (gateway, 5351))
        response, _ = sock.recvfrom(16)

    if len(response) != 16:
        raise RuntimeError(f"unexpected NAT-PMP response length {len(response)}")

    version, returned_opcode, result_code, _epoch, _private, mapped_public, _lifetime = struct.unpack(
        "!BBHIHHI", response
    )
    if version != 0 or returned_opcode != opcode + 128:
        raise RuntimeError("unexpected NAT-PMP response header")
    if result_code != 0:
        raise RuntimeError(f"NAT-PMP request failed with result code {result_code}")

    return mapped_public


def proton_forwarded_port(gateway: str) -> int:
    udp_port = natpmp_request(gateway, 1, 1, 0)
    tcp_port = natpmp_request(gateway, 2, 1, udp_port)
    return tcp_port


def transmission_rpc(method: str, arguments: dict) -> dict:
    session_id = None
    payload = json.dumps({"method": method, "arguments": arguments}).encode("utf-8")

    while True:
        request = urllib.request.Request(
            TRANSMISSION_RPC_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        if session_id:
            request.add_header("X-Transmission-Session-Id", session_id)

        try:
            with urllib.request.urlopen(request, timeout=SOCKET_TIMEOUT_SECONDS) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code != 409:
                raise
            session_id = error.headers.get("X-Transmission-Session-Id")
            if not session_id:
                raise RuntimeError("Transmission RPC did not return a session id") from error


def wait_for_transmission() -> None:
    while True:
        try:
            transmission_rpc("session-get", {})
            return
        except Exception as exc:  # noqa: BLE001
            log(f"waiting for Transmission RPC: {exc}")
            time.sleep(RETRY_SECONDS)


def apply_base_settings() -> None:
    transmission_rpc(
        "session-set",
        {
            "download-dir": "/downloads/complete",
            "incomplete-dir": "/downloads/incomplete",
            "incomplete-dir-enabled": True,
            "peer-port-random-on-start": False,
            "port-forwarding-enabled": False,
            "rpc-host-whitelist-enabled": False,
            "rpc-whitelist-enabled": False,
            "script-torrent-done-enabled": True,
            "script-torrent-done-filename": "/custom-scripts/transmission-done-copy.sh",
        },
    )


def apply_peer_port(port: int) -> None:
    transmission_rpc("session-set", {"peer-port": port, "peer-port-random-on-start": False})


def main() -> int:
    gateway = PROTON_NATPMP_GATEWAY or parse_natpmp_gateway(WG_CONFIG_PATH)
    current_port = None

    log(f"using Proton NAT-PMP gateway {gateway}")
    wait_for_transmission()
    apply_base_settings()

    while True:
        try:
            forwarded_port = proton_forwarded_port(gateway)
            if forwarded_port != current_port:
                apply_peer_port(forwarded_port)
                current_port = forwarded_port
                log(f"updated Transmission peer port to {forwarded_port}")
            else:
                log(f"renewed Proton forwarded port {forwarded_port}")
            time.sleep(RENEW_SECONDS)
        except Exception as exc:  # noqa: BLE001
            log(f"port-forward renewal failed: {exc}")
            time.sleep(RETRY_SECONDS)

    return 0


if __name__ == "__main__":
    sys.exit(main())
