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

## Outstanding work

- [ ] Admin kubeconfig for `dlk` with `veil` context
- [ ] Baseline Grafana dashboards and alerting rules
- [ ] Runbooks (backups, upgrades)
- [ ] Pin ingress LB IP (done: 192.168.0.220) and, once DNS moves to `skaia`,
  add A records (e.g., `ingress.veil.home.arpa`, `grafana.veil.home.arpa`)
- [ ] DNS move to `skaia` (host `veil.home.arpa`)
  - Note: This is independent of NetworkManager vs systemd-networkd; `skaia` can
    host DNS while continuing to use NetworkManager.
- [ ] Optional: migrate `skaia` to systemd-networkd
- [x] Consider extracting `desktop-common` for workstation profiles

References:

- Cold start steps: `docs/COLD-START.md`
- Network/DNS details: `docs/residence-1/ADDRESSING.md`
- Flux manifests: `flux/veil/`

## Validation plan

### Observability

- Clean access via DNS and Ingress will be set up after moving DNS to `skaia`.
  Until then, use port-forwarding for Grafana/Prometheus.

```bash
kubectl -n monitoring get pods
kubectl -n monitoring port-forward \
  svc/monitoring-kube-prometheus-stack-grafana 3000:80
# Browser: http://localhost:3000 (default creds chart-dependent)
# Check Kubernetes/Nodes dashboard and alert rules
```

### DNS migration (to `skaia`)

- [ ] Choose resolver on `skaia` (unbound preferred; alternatives: dnsmasq, CoreDNS)
- [ ] Implement service in NixOS on `skaia`:
  - Bind on `192.168.0.160` (LAN) and `127.0.0.1`
  - Create zone `veil.home.arpa` with static A records:
    - `ingress.veil.home.arpa` → 192.168.0.220
    - `grafana.veil.home.arpa` → 192.168.0.220
    - (add more as needed)
  - Upstream forwarding: to router DNS or public resolvers
  - Open firewall: TCP/UDP 53
- [ ] Router/DHCP: point LAN DNS to `192.168.0.160` (see COLD START)
- [ ] Validate from a LAN client:

```bash
# Replace CLIENT with any LAN host
dig +short @192.168.0.160 ingress.veil.home.arpa
# Expect: 192.168.0.220

# Ensure general resolution works (forwarding)
dig +short @192.168.0.160 example.com A
```

- [ ] Validate Ingress names resolve and route correctly once DNS is active

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

- Plan DNS move to `skaia` (host `veil.home.arpa`)
- Optional: migrate `skaia` to systemd-networkd later
- [x] Consider extracting `desktop-common` for workstation profiles
