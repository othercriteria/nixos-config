# Project Structure

This document outlines the structure and organization of this NixOS
configuration.

## Key Directories

### `hosts/`

Per-host NixOS configurations:

- `common/`: Shared desktop workstation configuration (fonts, greetd, printing,
  ProtonVPN, vibectl, user config, SSH hardening)
- `server-common/`: Headless server baseline (systemd-networkd, zramSwap,
  Docker, Teleport node agent, no GUI)
- `skaia/`: Primary workstation and infrastructure hub
  - k3s control plane, Unbound DNS, nginx reverse proxy
  - Observability stack (Prometheus, Grafana, Loki, Netdata parent)
  - Teleport auth server, Harmonia nix cache
  - Samba, MiniDLNA, thermal management
- `meteor-{1,2,3,4}/`: Veil cluster k3s server nodes
  - GPU support on meteor-4
  - Node exporter for Prometheus scraping
- `hive/`: Headless server for Urbit and misc services
  - Streams metrics/logs to skaia (node exporter, Netdata child, Promtail)
  - LUKS-encrypted root, bulk storage mounts

### `modules/`

Reusable NixOS modules:

- `desktop-common.nix`: Shared desktop settings (Thunar, XDG portals, polkit)
- `greetd.nix`: TTY greeter using tuigreet to launch Sway
- `fonts.nix`: System font configuration
- `harmonia.nix`: Nix binary cache server (skaia only)
- `kubeconfig.nix`: Kubeconfig management for k3s hosts
- `teleport-node.nix`: Teleport node agent for remote access
- `prometheus-rules.nix`: Shared Prometheus alerting rules
- `prometheus-zfs-snapshot.nix`: ZFS snapshot service for Prometheus data
- `protonvpn.nix`: ProtonVPN client configuration
- `vibectl.nix`: AI-powered kubectl wrapper
- `veil/`: Veil cluster-specific modules
  - `k3s-common.nix`: Common k3s flags, drain/uncordon hooks
  - `firewall.nix`: Firewall defaults for meteors
  - `kubeconfig.nix`: Veil-specific kubeconfig handling

### `home/`

Home Manager user configuration:

- `default.nix`: Main user config (packages, Git, direnv, etc.)
- `sway.nix`: Sway window manager configuration
- `zsh.nix`: Zsh shell configuration with Powerlevel10k
- `tmux.nix`: Tmux configuration
- `keyboard.nix`: Keyboard layout settings
- `helm.nix`: Helm/Kubernetes tooling

### `docs/`

Project documentation:

- `COLD-START.md`: Manual steps for new hosts and services
- `OBSERVABILITY.md`: Metrics, logs, dashboards, backup/restore
- `VEIL-PLAN.md`: Veil cluster rollout plan
- `residence-1/ADDRESSING.md`: LAN addressing and DNS for home network

### Other Directories

- `assets/`: Static assets (certs, config snippets, scripts)
- `private-assets/`: Private assets submodule (fonts, wallpapers)
- `secrets/`: Encrypted secrets managed by git-secret
- `gitops-veil/`: GitOps manifests for veil cluster (private submodule)
- `flux-snapshot/`: Public snapshots of GitOps manifests (illustrative)
- `.cursor/rules/`: Cursor AI assistant rules

## Key Files

- `flake.nix`: Main Nix flake entrypoint
- `flake.lock`: Flake lock file for reproducible builds
- `Makefile`: Automation for common tasks
  - `apply-host HOST=x`: Apply config (with hostname safety check)
  - `build-host HOST=x`: Build without applying
  - `reveal-secrets`: Decrypt git-secret files
  - `check-unbound`: Validate Unbound DNS config

## Runtime State (not in repo)

These directories are created during cold-start and are essential to operation:

- `/var/lib/prometheus2`: Prometheus data (ZFS dataset `fastdisk/prometheus`)
- `/var/lib/registry`: Docker registry storage (ZFS dataset `slowdisk/registry`)
- `/var/cache/netdata/dbengine`: Netdata metrics storage
- `/fastcache/dlk`: User cache (ZFS dataset, autosnapshots disabled)

## Updating This Document

Update this document when:

- Adding, removing, or renaming directories
- Adding new hosts or modules
- Changing the purpose of a component
