# Veil Cluster: Plan and Progress

This document tracks rollout of the headless Kubernetes cluster "veil"
(`meteor-1..3`) and minimal refactors. Focus is on outstanding work and
validation.

## Status

- k3s HA control plane across `meteor-1..4` is healthy (4-member etcd)
- FluxCD bootstrapped in `flux-system`
- Core services installed via Flux:
  - MetalLB (L2, pool 192.168.0.220–239)
  - ingress-nginx (LoadBalancer)
  - kube-prometheus-stack (Prometheus, Alertmanager, Grafana)
- API readyz and etcd health verified
- MetalLB LoadBalancer assignment validated (`lb-test` at 192.168.0.222)
- LAN DNS moved to `skaia` (Unbound). DHCP updated to point clients at
  `192.168.0.160`. Zones served:
  - `veil.home.arpa` (cluster services): `ingress`, `grafana`, `prometheus`,
    `alertmanager`, `s3`, `s3-console`
  - `home.arpa` (LAN hosts): `skaia`, `meteor-1..3`, `hive`
- DNS filtering enabled on `skaia` via Unbound RPZ (StevenBlack list)
- `skaia` remains on NetworkManager (no migration to systemd-networkd)
- Observability validated: Grafana reachable via `grafana.veil.home.arpa`
- Monitoring: Ingress hosts configured; default rules enabled. etcd metrics are
  scraped from control-plane nodes and the etcd dashboard is available and
  populated. kube-proxy, controller-manager, and scheduler metrics are scraped
  from nodes; corresponding alerts are clear.

## Outstanding work

- Configure Alertmanager receivers/routes once rules are settled
- Observability robustness:
  - Enable PVC persistence for Prometheus, Grafana, and Alertmanager (initially
    with `local-path`), and consider a networked or replicated StorageClass
    (Longhorn, Rook-Ceph, OpenEBS) for node independence
  - Configure Prometheus retention and `walCompression: true`
  - Optionally add remote_write to a durable backend (Thanos/Mimir/VictoriaMetrics)
    and/or Thanos sidecar + Thanos Query for HA reads and long-term storage
  - Add PDBs and anti-affinity/topology spread where applicable
- Runbooks (backups)

## Design: Distributed MinIO

- Scope: 500 GiB working data, S3 protocol, light auth (AK/SK).

- Exposure:

  - Ingress-NGINX (192.168.0.220)
  - DNS: `s3.veil.home.arpa`, `s3-console.veil.home.arpa`

- TODO: Consider a dedicated MetalLB IP for MinIO if any of the following
  apply:
  - You want direct TCP access (bypassing Ingress) for maximum streaming
    throughput
  - You plan to separate S3 traffic from HTTP ingress for network policy
    or observability
  - You need per-service TLS termination and certificates managed outside
    of Ingress

### Option A: 2x (mirror-like via EC, ~50% usable)

- Minimum 4 drives per erasure set.

- Layout examples:

  - 4 nodes × 1 PVC × 250 GiB = 1.0 TiB raw → ~500 GiB usable
  - 3 nodes × 2 PVCs × 175 GiB = 1.05 TiB raw → ~525 GiB usable

- Failure tolerance:

  - Up to 2 drive losses in the erasure set.
  - With 3 nodes × 2 PVCs, tolerates loss of 1 node (2 drives), not 2 nodes.

- Throughput: strong small-cluster performance; writes span all drives.

- StorageClass: `local-path` per-node PVCs with node affinity.

### Option B: EC(4,2) (~66.7% usable)

- Requires 6 drives per erasure set.

- Layout example (fits ~500 GiB usable):

  - 3 nodes × 2 PVCs × 125 GiB = 750 GiB raw → ~500 GiB usable

- Failure tolerance:

  - Any 2 drives in the set (1 node failure with 2 PVCs per node).

- Throughput: better usable capacity; similar profile for small clusters.

- AuthN/Z: bootstrap AK/SK via Secret; bucket policies for coarse authZ.

- Cold start: none beyond DNS; PVCs via `local-path`.

References:

- Cold start steps: `docs/COLD-START.md`
- Network/DNS details: `docs/residence-1/ADDRESSING.md`
- Flux manifests: `flux/veil/`

## Post-setup (later)

- [ ] Runbooks (backups)
  - On-demand etcd snapshot:

    ```bash
    sudo k3s etcd-snapshot save --name on-demand-$(date +%F)
    ```

## Open items

- (none)
