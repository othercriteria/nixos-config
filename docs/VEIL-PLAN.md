# Veil Cluster: Plan and Progress

This document tracks rollout of the headless Kubernetes cluster "veil"
(`meteor-1..3`) and minimal refactors. Focus is on outstanding work and
validation.

## Status

- k3s HA control plane across `meteor-1..3` is healthy (3-member etcd)
- FluxCD bootstrapped in `flux-system`
- Core services installed via Flux:
  - MetalLB (L2, pool 192.168.0.220–239)
  - ingress-nginx (LoadBalancer)
  - kube-prometheus-stack (Prometheus, Alertmanager, Grafana)
- API readyz and etcd health verified
- MetalLB LoadBalancer assignment validated (`lb-test` at 192.168.0.222)
- LAN DNS moved to `skaia` (Unbound). DHCP updated to point clients at
  `192.168.0.160`. Zone `veil.home.arpa` is served with records including:
  `ingress.veil.home.arpa`, `grafana.veil.home.arpa`
- DNS filtering enabled on `skaia` via Unbound RPZ (StevenBlack list)
- `skaia` remains on NetworkManager (no migration to systemd-networkd)
- Observability validated: Grafana reachable via `grafana.veil.home.arpa`

## Outstanding work

- (none)

References:

- Cold start steps: `docs/COLD-START.md`
- Network/DNS details: `docs/residence-1/ADDRESSING.md`
- Flux manifests: `flux/veil/`

## Post-setup (later)

- [ ] Admin kubeconfig for `dlk` with `veil` context

```bash
# on meteor-1
sudo cat /etc/rancher/k3s/k3s.yaml > /tmp/veil-kubeconfig
sed -i 's/127.0.0.1/192.168.0.121/' /tmp/veil-kubeconfig
scp meteor-1:/tmp/veil-kubeconfig ~/.kube/config-veil
kubectl --kubeconfig ~/.kube/config-veil config rename-context default veil
```

- [ ] Baseline Grafana dashboards and alerting rules
  - Import common Kubernetes dashboards
  - Configure Alertmanager receivers and routes

- [ ] Runbooks (backups, upgrades)
  - On-demand etcd snapshot:

    ```bash
    sudo k3s etcd-snapshot save --name on-demand-$(date +%F)
    ```

  - Rolling upgrades:

    ```bash
    kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
    # Rebuild host (NixOS), reboot, verify node Ready again
    kubectl uncordon <node>
    ```

## Open items

- (none)
