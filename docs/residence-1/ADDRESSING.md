# residence-1: Addressing and DNS

This document describes LAN addressing and name resolution for
`residence-1`, the home network where `skaia`, `meteor-*`, and other
hosts reside.

## Addressing

- LAN: 192.168.0.0/24
- Router: 192.168.0.1 (TP-Link AC2300)
- DHCP pool (router-managed): 192.168.0.100–192.168.0.219
- Static DHCP reservations:
  - `skaia` → 192.168.0.160 (MAC F0-2F-74-CA-3E-AA)
  - `meteor-1` → 192.168.0.121 (MAC 58-47-CA-7F-20-99)
  - `meteor-2` → 192.168.0.122 (MAC 58-47-CA-7F-22-D1)
  - `meteor-3` → 192.168.0.123 (MAC 58-47-CA-7F-1E-71)
  - `meteor-4` → 192.168.0.124 (MAC 38-05-25-31-86-AE)
  - `hive` → 192.168.0.144 (MAC E0-D5-5E-2B-FB-72)
  - `homeassistant` → 192.168.0.184 (MAC E4-5F-01-97-C0-C6)
  - `projector` → 192.168.0.146 (MAC 7C-D5-66-55-F5-86, Fire TV Stick ~2020)
- MetalLB address pool (reserved, not in DHCP): 192.168.0.220–192.168.0.239
- Pinned LoadBalancer IPs:
  - `ingress-nginx` → 192.168.0.220 (via Flux HelmRelease values)

## DNS

- LAN DNS is served by `unbound` on `skaia` (192.168.0.160).

- Private zones:

  - `veil.home.arpa` (cluster services, all via ingress-nginx at 192.168.0.220)

    - `ingress.veil.home.arpa` → 192.168.0.220 (ingress-nginx)
    - `grafana.veil.home.arpa` → 192.168.0.220 (Grafana)
    - `prometheus.veil.home.arpa` → 192.168.0.220
    - `alertmanager.veil.home.arpa` → 192.168.0.220
    - `s3.veil.home.arpa` → 192.168.0.220 (MinIO S3 API)
    - `s3-console.veil.home.arpa` → 192.168.0.220 (MinIO console)
    - `argocd.veil.home.arpa` → 192.168.0.220
    - `argo-workflows.veil.home.arpa` → 192.168.0.220
    - `argo-rollouts.veil.home.arpa` → 192.168.0.220
    - `registry.veil.home.arpa` → 192.168.0.220 (Docker registry)

  - `home.arpa` (LAN hosts)

    - `router.home.arpa` → 192.168.0.1
    - `skaia.home.arpa` → 192.168.0.160
    - `netdata.home.arpa` → 192.168.0.160 (Netdata dashboard on skaia)
    - `cache.home.arpa` → 192.168.0.160 (Harmonia nix binary cache)
    - `meteor-1.home.arpa` → 192.168.0.121
    - `meteor-2.home.arpa` → 192.168.0.122
    - `meteor-3.home.arpa` → 192.168.0.123
    - `meteor-4.home.arpa` → 192.168.0.124
    - `hive.home.arpa` → 192.168.0.144
    - `homeassistant.home.arpa` → 192.168.0.184
    - `assistant.home.arpa` → 192.168.0.160 (HA via nginx proxy)
    - `assistant-direct.home.arpa` → 192.168.0.184 (HA direct/SSH)
    - `ollama.home.arpa` → 192.168.0.160 (Ollama LLM API via nginx)
    - `projector.home.arpa` → 192.168.0.146 (Fire TV Stick)

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
