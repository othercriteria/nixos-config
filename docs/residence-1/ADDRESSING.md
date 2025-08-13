# residence-1: Addressing and DNS

This document describes LAN addressing and name resolution for
`residence-1`, the home network where `skaia`, `meteor-*`, and other
hosts reside.

## Addressing

- LAN: 192.168.0.0/24
- DHCP pool (router-managed): 192.168.0.100–192.168.0.219
- Static DHCP reservations:
  - `skaia` → 192.168.0.160 (MAC F0-2F-74-CA-3E-AA)
  - `meteor-1` → 192.168.0.121 (MAC 58-47-CA-7F-20-99)
  - `meteor-2` → 192.168.0.122
  - `meteor-3` → 192.168.0.123
  - (Add MAC↔IP mapping here for auditability)
- MetalLB address pool (reserved, not in DHCP): 192.168.0.220–192.168.0.239

## DNS

- Private zone: `veil.home.arpa`
  - Router may not support static A records. Interim: use `sslip.io` or
    `nip.io` (e.g., `app.192-168-0-220.sslip.io`).
  - Future plan: move LAN DNS to `skaia` (e.g., `unbound`, `dnsmasq`, or
    `coredns`) and manage `veil.home.arpa` there with static A records for
    MetalLB VIPs (e.g., `grafana.veil.home.arpa` → 192.168.0.220).
- mDNS (`*.local`): optional for direct host discovery on L2
  - Enable via `services.resolved.multicastDns = true;` (or Avahi)

## Notes

- Keep MetalLB addresses outside the DHCP pool to avoid collisions.
- Document reservations and MetalLB allocations to maintain clarity.
- In the future, this network definition may move into Nix modules if
  multiple sites/networks are managed here.
