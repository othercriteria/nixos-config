# Veil Cluster: Plan and Progress

This document tracks rollout of the headless Kubernetes cluster "veil"
(`meteor-1..3`) and minimal refactors. Use checkboxes to track progress.

## Decisions (confirmed)

- HA control plane: 3x k3s servers (embedded etcd)
- Observability: in-cluster (no host-level Prometheus for meteors)
- Email alerts: not used for meteors
- IP addressing: static via DHCP reservations on router
- Storage: k3s local-path-provisioner (no ZFS on meteors)
- Secrets: git-secret under `secrets/`
- Host networking stack: systemd-networkd (default; can switch if needed)

## Network and addressing

- Router: Archer C2300 v2.0, DHCP 192.168.0.100–192.168.0.219
- Meteor nodes reserved: 192.168.0.121–123
- MetalLB: reserve 192.168.0.220–239 (outside DHCP)
- See `docs/residence-1/ADDRESSING.md` for details

## k3s cluster design (veil)

- All three meteors run `services.k3s.role = "server"`
- `meteor-1`: `--cluster-init`; `meteor-2/3`: `--server https://192.168.0.121:6443`
- Disable Traefik; keep local-path storage; expose metrics ports

## DNS strategy

- Prefer `veil.home.arpa` (router or move to `skaia` DNS later)
- Use `sslip.io` during bootstrap
- See `docs/residence-1/ADDRESSING.md`

## Storage

- Use local-path provisioner initially
- Revisit Longhorn later if needed

## Observability (in-cluster)

- Target: `kube-prometheus-stack` (later step)

## Installation guidance (streamlined)

- Install NixOS (UEFI, ext4, no swap), create `dlk` admin; SSH enabled
- On each meteor:
  - Clone repo to `~/workspace/nixos-config`
  - Enter dev shell:
    `nix develop --extra-experimental-features nix-command \
    --extra-experimental-features flakes`
  - Secrets: either `make reveal-secrets` (with GPG) or copy the token to
    `/etc/nixos/secrets/veil-k3s-token`
  - Apply host: `make apply-host HOST=meteor-1` (then `meteor-2`, `meteor-3`)

Notes:

- Bootloader: systemd-boot default for UEFI
- stateVersion: `25.11` in `server-common`
- zsh: minimal `~/.zshrc` created to suppress newuser prompt

## Firewall policy (per node)

- Allow 6443/tcp, 2379–2380/tcp (servers), 10250/tcp, 8472/udp

## Cold start summary

- k3s HA boot sequence and token; MetalLB range reserved
- See `docs/COLD-START.md`

## Cluster services (FluxCD GitOps)

- We will use FluxCD (GitOps) to manage cluster services. No Helm CLI on
  nodes; Flux controllers reconcile from manifests in this repo.

- [x] Bootstrap FluxCD (one-time per cluster)

```bash
# Install Flux controllers (no Helm needed)
kubectl create ns flux-system || true
kubectl apply -f \
  https://github.com/fluxcd/flux2/releases/latest/download/install.yaml
# Verify controllers
kubectl -n flux-system get pods
```

- [x] Define Helm repositories (Flux sources)

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: metallb
  namespace: flux-system
spec:
  url: https://metallb.github.io/metallb
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  url: https://kubernetes.github.io/ingress-nginx
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  url: https://prometheus-community.github.io/helm-charts
```

- [x] Install MetalLB via HelmRelease and apply address pool

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: metallb
  namespace: flux-system
spec:
  interval: 10m
  install:
    createNamespace: true
  targetNamespace: metallb-system
  chart:
    spec:
      chart: metallb
      version: 0.14.8
      sourceRef:
        kind: HelmRepository
        name: metallb
        namespace: flux-system
```

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: home-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.0.220-192.168.0.239
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: home-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - home-pool
```

- [x] Install ingress-nginx via HelmRelease

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 10m
  install:
    createNamespace: true
  targetNamespace: ingress-nginx
  chart:
    spec:
      chart: ingress-nginx
      version: 4.11.2
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
        namespace: flux-system
  values:
    controller:
      service:
        type: LoadBalancer
        # Optionally pin a static IP from MetalLB pool:
        # loadBalancerIP: 192.168.0.220
```

- [x] Install kube-prometheus-stack via HelmRelease

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kube-prometheus-stack
  namespace: flux-system
spec:
  interval: 10m
  install:
    createNamespace: true
  targetNamespace: monitoring
  chart:
    spec:
      chart: kube-prometheus-stack
      version: 66.3.0
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  values:
    grafana:
      service:
        type: LoadBalancer
```

- Apply order:
  1. Flux install (controllers running in `flux-system`)
  1. HelmRepository resources
  1. HelmRelease for MetalLB
  1. MetalLB `IPAddressPool` and `L2Advertisement`
  1. HelmRelease for ingress-nginx
  1. HelmRelease for kube-prometheus-stack

- Notes:
  - Pin chart versions and upgrade via PRs.
  - Prefer `valuesFrom` with ConfigMaps/Secrets for larger overrides.
  - Document Flux bootstrap in `docs/COLD-START.md`.

- Validation:
  - `kubectl get hr -A` shows all Ready
  - `kubectl -n ingress-nginx get svc` shows LB IP in MetalLB pool
  - `kubectl -n monitoring get pods` all Running
  - `kubectl -n metallb-system get ipaddresspools,l2advertisements` present

## Post-setup (later)

- [ ] Admin kubeconfig for `dlk` with `veil` context
  - From a meteor, copy kubeconfig and point it at the API address:

```bash
# on meteor-1
sudo cat /etc/rancher/k3s/k3s.yaml > /tmp/veil-kubeconfig
sed -i 's/127.0.0.1/192.168.0.121/' /tmp/veil-kubeconfig
scp meteor-1:/tmp/veil-kubeconfig ~/.kube/config-veil
kubectl --kubeconfig ~/.kube/config-veil config rename-context default veil
```

- [ ] Baseline Grafana dashboards and alerting rules
  - Import common Kubernetes dashboards.
  - Configure Alertmanager receivers and routes for critical alerts.

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

- Optional: migrate `skaia` to systemd-networkd later
- Plan DNS move to `skaia` (host `veil.home.arpa`)
- Keep `skaia` functionally unchanged for now; consider extracting
  `desktop-common` later
- Residence name: `residence-1` (documented)
