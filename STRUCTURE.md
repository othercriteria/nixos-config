# Project Structure

This document outlines the structure and organization of this NixOS
configuration.

## Key Directories and Their Purposes

- `modules/`: Contains shared NixOS and Home Manager modules that can be
  imported by various hosts or user profiles.
  - `desktop-common.nix`: Shared desktop settings for workstation-like hosts
    (Thunar, XDG portals, GNUPG agent, polkit/rtkit, GVFS/Tumbler)
  - `veil/`: Veil cluster-specific shared modules (e.g., `k3s-common.nix` for
    k3s flags exposing control-plane metrics for scraping, and setting the
    default k3s join token path; `firewall.nix` for meteor firewall defaults).
    Modules follow NixOS conventions (`options` and `config` at top-level).
    Control-plane metrics endpoints (controller-manager, scheduler) are exposed
    for Prometheus by allowing `/metrics` without auth via k3s flags.
    - `kubeconfig.nix`: Installs a oneshot service that populates
      `${HOME}/.kube/config` for user `dlk` from the local k3s kubeconfig when
      k3s is enabled on the host, removing the need for `KUBECONFIG` env hacks.
      The service PATH includes `glibc.bin` and sets PATH to include
      `/run/current-system/sw/bin`, and falls back to `~user` expansion if
      `getent` is unavailable. On meteor hosts it rewrites the server to
      `https://192.168.0.121:6443` and renames the context to `veil` (injected
      conditionally via Nix `optionalString`).
- `hosts/`: Contains per-host NixOS configuration files and subdirectories.
  - `skaia/`: Primary workstation host and its modules (e.g., `unbound.nix` DNS,
    `unbound-rpz.nix` RPZ blocklist with systemd service/timer updater). Unbound
    binds on loopback and LAN addresses for local and network clients (loopback
    is required for local resolution).
  - `server-common/`: Headless server baseline for Kubernetes nodes (no GUI)
  - `meteor-1/`, `meteor-2/`, `meteor-3/`: Veil cluster nodes (k3s servers). These
    expose node-exporter on TCP/9100 and etcd metrics on TCP/2381 for Prometheus
    scraping. HostIds are set per host using machine-id–derived values.
    Firewall configuration for meteors is centralized in
    `modules/veil/firewall.nix`; per-host `hosts/meteor-*/firewall.nix` files
    have been removed.
- `home/`: Contains Home Manager user configuration modules.
- `docs/`: Project documentation, including cold start and observability
  guides.
  - `VEIL-PLAN.md`: Plan and progress for the veil cluster rollout
  - `residence-1/`: Site/network documentation
    - `ADDRESSING.md`: LAN addressing and DNS strategy for residence-1
- `flux/`: FluxCD GitOps manifests
  - `veil/`: Veil cluster manifests (Helm repositories, Helm releases,
    MetalLB pool, monitoring). `monitoring.yaml` installs
    `kube-prometheus-stack` (Grafana, Prometheus, Alertmanager) with default
    dashboards and Grafana ingress, and wires the `additional-scrape-configs`
    Secret to Prometheus. Etcd metrics are scraped from control-plane nodes on
    TCP/2381 via job `kube-etcd` defined in
    `flux/veil/additional-scrape-configs.yaml`. Grafana includes the etcd
    dashboard (gnetId 10322). Additional scrape jobs cover kube-proxy (10249),
    kube-controller-manager (10257), and kube-scheduler (10259) on meteors.
- `assets/`: Fonts, images, and other static assets.
- `private-assets/`: Private, non-public assets (git submodule initialized via
  `make add-private-assets`).
- `secrets/`: Encrypted secrets managed by git-secret (e.g., `veil-k3s-token`).
- `.cursor/rules/`: Cursor rule files for code quality and workflow standards.
  - `scripts/`: Helper scripts used by Cursor rules (e.g., for commit automation).

## NixOS Entrypoint

- `flake.nix`: The main Nix flake entrypoint for the system.
- `flake.lock`: Flake lock file for reproducible builds.
- `Makefile`: Automation for common tasks:
  - `apply-host`, `rollback`, `reveal-secrets`
  - `build-host`: build a host closure without switching
  - `check-unbound`, `check-unbound-built`: validate generated Unbound config

## Important File Locations

- `README.md`: Project documentation and usage instructions
- `.gitleaks.toml`: Configuration for secret scanning with gitleaks
- `.pre-commit-config.yaml`: Pre-commit hook configuration
- `.gitignore`: Files and directories to ignore in git
- `.secrets.baseline`: Baseline for secret scanning

### Runtime State

- `/var/lib/registry`: Storage path for the local Docker registry configured via
  `services.dockerRegistry` (backed by ZFS dataset `slowdisk/registry`).  This
  directory is created manually during cold-start and is **not** part of the
  git repository, but it is essential to system operation and therefore noted
  here.

## Directory Purposes

- `modules/`: Shared modules for NixOS and Home Manager
- `hosts/`: Per-host configuration (e.g., `skaia/`, `server-common`, `meteor-*/`)
- `home/`: User-level configuration
- `docs/`: Documentation for setup, cold start, observability, and network/site
- `flux/`: Flux GitOps manifests; subdirectories may separate clusters (e.g.,
  `flux/veil/`)
- `assets/`: Static assets (fonts, images)
- `private-assets/`: Private assets tracked as a submodule
- `secrets/`: Encrypted secrets (git-secret)

## Updating Structure

This document should be updated whenever:

- Adding, removing, or renaming directories
- Moving files between directories
- Changing the purpose of a directory
- Adding new major components

## Documentation

- [Observability Stack](docs/OBSERVABILITY.md): Details on the observability
  setup, including metrics, logs, dashboards, storage, retention, backup, and
  DR.
- [Veil Cluster Plan](docs/VEIL-PLAN.md): Working plan for the veil cluster
  rollout.
- [Residence-1 Addressing](docs/residence-1/ADDRESSING.md): Addressing/DNS for
  the home network.
