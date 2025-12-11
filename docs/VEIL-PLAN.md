# Veil Cluster: Plan and Progress

This document tracks rollout of the headless Kubernetes cluster "veil"
(`meteor-1..4`) and minimal refactors. Focus is on outstanding work and
validation.

## Status

- k3s HA control plane across `meteor-1..4` is healthy (4-member etcd)
- FluxCD bootstrapped in `flux-system`, reconciling from `gitops-veil` repo
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
  - `home.arpa` (LAN hosts): `skaia`, `meteor-1..4`, `hive`
- DNS filtering enabled on `skaia` via Unbound RPZ (StevenBlack list)
- `skaia` remains on NetworkManager (no migration to systemd-networkd)
- Observability validated: Grafana reachable via `grafana.veil.home.arpa`
- Monitoring: Ingress hosts configured; default rules enabled. etcd metrics are
  scraped from control-plane nodes and the etcd dashboard is available and
  populated. kube-proxy, controller-manager, and scheduler metrics are scraped
  from nodes; corresponding alerts are clear.
- GPU support (`meteor-4`): RTX 3080 Ti via OCuLink, NVIDIA driver managed by
  NixOS, nvidia-container-toolkit for k3s containerd runtime. Device plugin
  exposes `nvidia.com/gpu`, DCGM exporter provides Prometheus metrics.

## Outstanding work

- Complete GitOps migration: move manifests from `flux/veil/` to `gitops-veil/`,
  set up deploy key and Flux GitRepository/Kustomization
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

## Distributed MinIO

- Configuration: EC(4,2) with 6 pods × 1 drive × 125 GiB = 750 GiB raw → ~500
  GiB usable
- Failure tolerance: any 2 drives in the erasure set
- StorageClass: `local-path` per-node PVCs
- AuthN/Z: root credentials via Secret `minio-root` in `object-store` namespace
- Exposure: Ingress-NGINX at `s3.veil.home.arpa`, `s3-console.veil.home.arpa`

References:

- Cold start steps: `docs/COLD-START.md`
- Network/DNS details: `docs/residence-1/ADDRESSING.md`
- GitOps manifests: `gitops-veil/` submodule (private repo)
- Legacy manifests: `flux/veil/` (to be removed after GitOps migration)

## Post-setup (later)

- [ ] Runbooks (backups)
  - On-demand etcd snapshot:

    ```bash
    sudo k3s etcd-snapshot save --name on-demand-$(date +%F)
    ```

## Open items

- (none)
