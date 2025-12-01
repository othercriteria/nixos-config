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
  - `meteor-2` → 192.168.0.122 (MAC 58-47-CA-7F-22-D1)
  - `meteor-3` → 192.168.0.123 (MAC 58-47-CA-7F-1E-71)
  - `hive` → 192.168.0.144 (MAC E0-D5-5E-2B-FB-72)
  - `homeassistant` → 192.168.0.184 (MAC E4-5F-01-97-C0-C6)
  - (Add MAC↔IP mapping here for auditability)
- MetalLB address pool (reserved, not in DHCP): 192.168.0.220–192.168.0.239
- Pinned LoadBalancer IPs:
  - `ingress-nginx` → 192.168.0.220 (via Flux HelmRelease values)

## DNS

- LAN DNS is served by `unbound` on `skaia` (192.168.0.160).

- Private zones:

  - `veil.home.arpa` (cluster services)

    - `ingress.veil.home.arpa` → 192.168.0.220 (ingress-nginx)
    - `grafana.veil.home.arpa` → 192.168.0.220 (Grafana via Ingress)
    - `prometheus.veil.home.arpa` → 192.168.0.220
    - `alertmanager.veil.home.arpa` → 192.168.0.220
    - `s3.veil.home.arpa` → 192.168.0.220 (MinIO S3 API via Ingress)
    - `s3-console.veil.home.arpa` → 192.168.0.220 (MinIO console via Ingress)

  - `home.arpa` (LAN hosts)

    - `skaia.home.arpa` → 192.168.0.160
    - `meteor-1.home.arpa` → 192.168.0.121
    - `meteor-2.home.arpa` → 192.168.0.122
    - `meteor-3.home.arpa` → 192.168.0.123
    - `hive.home.arpa` → 192.168.0.144
  - `homeassistant.home.arpa` → 192.168.0.184

- mDNS (`*.local`): optional for direct host discovery on L2
  - Enable via `services.resolved.multicastDns = true;` (or Avahi)

### Notes on misc DHCP names

- Optional (not preserved unless needed):
  - `ESP_4DBB32` → 192.168.0.208 (MAC 04-CF-8C-4D-BB-32)
  - `unknown client name` → 192.168.0.189 (MAC 7C-78-B2-86-82-6F)
- If these prove important, migrate them to static reservations and add
  corresponding DNS A records under the appropriate zone.

## Notes

- Keep MetalLB addresses outside the DHCP pool to avoid collisions.
- Document reservations and MetalLB allocations to maintain clarity.
- In the future, this network definition may move into Nix modules if
  multiple sites/networks are managed here.

- TODO: Consider assigning a dedicated MetalLB IP for MinIO if direct
  TCP access (bypassing Ingress) is desired for throughput, or to
  isolate S3 traffic for policy/observability/PKI reasons.
