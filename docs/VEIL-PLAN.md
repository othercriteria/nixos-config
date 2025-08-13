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

## Repository structure

- [x] Create `hosts/server-common/default.nix` (headless server baseline)
- [x] Add `hosts/meteor-1..3` with k3s + firewall
- [x] Add `meteor-*` to `flake.nix`
- [x] Document residence-1 and veil plan in `docs/`
- [x] Add encrypted `secrets/veil-k3s-token.secret`
- [ ] Keep `skaia` functionally unchanged (future: consider `desktop-common`)

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
  - Secrets: either `make reveal-secrets` (with GPG) or copy the token to `/etc/nixos/secrets/veil-k3s-token`
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

## Bootstrap checklist

Preparation

- [x] Adjust router DHCP pool to avoid MetalLB range
- [x] Confirm MetalLB pool (192.168.0.220-239) and reserve it
- [x] Create k3s join token secret (encrypted)
- [ ] Create DHCP reservations for `meteor-1..3` (record MAC↔IP)

Bring-up

- [x] Add `hosts/server-common` and `hosts/meteor-*` skeleton
- [x] Add `meteor-*` to `flake.nix`
- [x] Build and boot `meteor-1` (server, `--cluster-init`)
- [x] Verify API health
- [x] Build and boot `meteor-2` (server role)
- [ ] Build and boot `meteor-3` (server role)
- [ ] Verify etcd cluster health (all 3 members)

Two-node verification (done)

- [x] Nodes Ready: `k3s kubectl get nodes -o wide`
- [x] API health: `k3s kubectl get --raw "/readyz?verbose"`
- [ ] etcd2 health (interim):
  - `ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
    --cert=/var/lib/rancher/k3s/server/tls/etcd/client.crt \
    --key=/var/lib/rancher/k3s/server/tls/etcd/client.key member list`
- [ ] kube-system pods healthy on both nodes:
  - `watch -n2 'k3s kubectl get pods -A -o wide'`

Cluster services (later)

- [ ] Install MetalLB and apply address pool
- [ ] Install ingress-nginx
- [ ] Install kube-prometheus-stack
- [ ] (Optional) Install Loki + Promtail

Post-setup (later)

- [ ] Admin kubeconfig for `dlk` with `veil` context
- [ ] Baseline Grafana dashboards and alerting rules
- [ ] Runbooks (backups, upgrades)

## Open items

- Optional: migrate `skaia` to systemd-networkd later
- Plan DNS move to `skaia` (host `veil.home.arpa`)
- Residence name: `residence-1` (documented)
