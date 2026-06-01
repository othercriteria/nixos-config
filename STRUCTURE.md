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
  - NVIDIA RTX 4090 (24GB VRAM), AMD CPU
  - k3s control plane, Unbound DNS, nginx reverse proxy
  - Observability stack (Prometheus, Grafana, Loki, Netdata parent)
  - ntfy.sh push notifications (Alertmanager webhook, mobile/desktop alerts)
  - Teleport auth server, Harmonia nix cache
  - Private Forgejo instance (LAN-first, PostgreSQL, Git LFS)
  - Samba, MiniDLNA, thermal management, SRS streaming
  - Home Assistant integration (nginx proxy, MQTT broker, state publisher)
  - Ollama LLM + F5-TTS + Kokoro-FastAPI (OpenAI-compatible APIs,
    GPU-accelerated)
  - Voice assistant server-side: Wyoming faster-whisper STT + Wyoming
    F5-TTS / Kokoro bridges for HA Assist (both TTS engines run in
    parallel for A/B comparison)
- `meteor-{1,2,3,4}/`: Veil cluster k3s server nodes
  - GPU support on meteor-4
  - Node exporter for Prometheus scraping
- `hive/`: Headless server for Urbit and misc services
  - Streams metrics/logs to skaia (node exporter, Netdata child, Alloy)
  - LUKS-encrypted root, bulk storage mounts
- `demo/`: Standalone demo VM for portfolio showcase
  - Self-contained observability stack (no secrets required)
  - Uses same modules as production hosts

### `modules/`

Reusable NixOS modules:

- `desktop-common.nix`: Shared desktop settings (Thunar, XDG portals, polkit)
- `greetd.nix`: TTY greeter using tuigreet to launch Sway
- `fonts.nix`: System font configuration
- `github-runner.nix`: GitHub Actions self-hosted runner (declarative)
- `hardened-service.nix`: Reusable systemd sandbox preset (function returning
  a strict `serviceConfig` attrset for small network/compute services)
- `harmonia.nix`: Nix binary cache server (skaia only)
- `hdd-power-mgmt.nix`: Override aggressive APM head-parking on consumer
  HDDs via `hdparm -B`; activated per-host (currently hive only)
- `host-secrets-manifest.nix`: Per-host secrets allowlist enforced at system
  activation; prunes `/etc/nixos/secrets/` to the declared subset after
  `make sync-to-system` rsyncs the full set
- `kubeconfig.nix`: Kubeconfig management for k3s hosts
- `netdata-child.nix`: Netdata child-role module; streams to a parent
  (default: `skaia.home.arpa:19999`) without keeping a local dbengine
- `netdata-unlock-nodes.nix`: Parent-side workaround for Netdata's
  5-active-node SPA nerf; pre-populates `preferred_node_ids` in the
  settings file so the dashboard never shows the "deactivate nodes"
  modal
- `teleport-node.nix`: Teleport node agent for remote access
- `prometheus-base.nix`: Core Prometheus + node exporter module
- `prometheus-node-exporter-fix.nix`: Workaround for upstream
  node_exporter socket-activation regression
- `prometheus-rules.nix`: Shared Prometheus alerting rules
- `prometheus-zfs-snapshot.nix`: ZFS snapshot service for Prometheus data
- `grafana.nix`: Grafana with datasource provisioning
- `loki.nix`: Loki log aggregation server
- `ntfy.nix`: ntfy.sh push notification server (Alertmanager webhook, mobile push)
- `promtail.nix`: Alloy-backed Loki log shipper
- `protonvpn.nix`: ProtonVPN client configuration
- `trivia.nix`: Drip-release file server for trivia events (FastAPI app
  behind nginx + Basic Auth; consumes `hardened-service.nix` for sandboxing;
  uses `assets/trivia-server.py`)
- `vibectl.nix`: AI-powered kubectl wrapper
- `veil/`: Veil cluster-specific modules
  - `k3s-common.nix`: Common k3s flags, drain/uncordon hooks
  - `firewall.nix`: Firewall defaults for meteors
  - `kubeconfig.nix`: Veil-specific kubeconfig handling

### `home/`

Home Manager user configuration:

- `default.nix`: Main user config (packages, Git, direnv, etc.)
- `docker.nix`: Docker tooling (persistent `registry-cache` buildx
  builder for registry-backed BuildKit caches)
- `sway.nix`: Sway window manager configuration
- `zsh.nix`: Zsh shell configuration with Powerlevel10k
- `tmux.nix`: Tmux configuration
- `keyboard.nix`: Keyboard layout settings
- `helm.nix`: Helm/Kubernetes tooling

### `docs/`

Project documentation:

- `COLD-START.md`: Manual cold-start steps for new hosts and services
  (descriptive headings; no section numbers)
- `DESIGN-DECISIONS.md`: Architecture decisions with rationale and trade-offs
- `OBSERVABILITY.md`: Metrics, logs, dashboards, backup/restore
- `VEIL-PLAN.md`: Veil cluster rollout plan
- `residence-1/ADDRESSING.md`: LAN addressing and DNS for home network
- `retro/`: Security incident retrospectives (YYYY-MM-DD-description.md)
- `runbooks/`: Operational procedures for ongoing tasks
  - `harmonia-key-rotation.md`: Rotate Harmonia binary cache signing key
  - `home-ca-rotation.md`: Rotate the home-ca certificate authority
    that signs veil cluster ingress TLS
  - `skaia-edge-to-hive.md`: Relocate the public-facing nginx /
    ACME / ddclient surface from `skaia` to `hive` so `skaia` can
    run ProtonVPN as the default network configuration
  - `sops-workflow.md`: Encrypt/edit/rotate SOPS-encrypted Secrets in
    `gitops-veil/private/`
  - `minio-root-rotation.md`: Rotate MinIO root credentials on veil
  - `hive-disk-replacement.md`: Replace hive system NVMe while keeping
    data disks and pier

### Other Directories

- `.github/workflows/`: GitHub Actions CI workflows
  - `ci.yml`: Lint, build, and integration tests (self-hosted runner)
- `assets/`: Static assets (certs, config snippets, scripts)
- `private-assets/`: Private assets submodule (fonts, wallpapers)
- `secrets/`: Encrypted secrets managed by git-secret. Notable entries:
  - `sops-age.key`: age private key for decrypting `gitops-veil/private/*.sops.yaml`
  - `ntfy-veil-alerts-password`: password for the dedicated `veil-alerts`
    ntfy user used by the veil cluster Alertmanager
- `gitops-veil/`: GitOps manifests for veil cluster (private submodule)
  - `.sops.yaml`: age public key + creation rules for `private/*.sops.yaml`
  - `private/`: in-cluster manifests + SOPS-encrypted Secret manifests
- `flux-snapshot/`: Public snapshots of GitOps manifests (illustrative)
- `tests/`: NixOS integration tests
  - `observability.nix`: Tests the observability stack modules
- `.cursor/rules/`: Cursor AI assistant rules

## Key Files

- `flake.nix`: Main Nix flake entrypoint
- `flake.lock`: Flake lock file for reproducible builds
- `Makefile`: Automation for common tasks
  - `apply-host HOST=x`: Apply config (with hostname safety check)
  - `build-host HOST=x`: Build without applying
  - `reveal-secrets`: Decrypt git-secret files
  - `check-unbound`: Validate Unbound DNS config
  - `test`: Run all integration tests
  - `demo`: Launch interactive observability demo VM

## Runtime State (not in repo)

These directories are created during cold-start and are essential to operation:

- `/var/lib/prometheus2`: Prometheus data (ZFS dataset `fastdisk/prometheus`)
- `/var/lib/docker`: Docker local storage (ZFS dataset
  `fastdisk/system/var/docker`, autosnapshots disabled)
- `/var/lib/registry`: Docker registry storage (ZFS dataset `slowdisk/registry`)
- `/var/cache/netdata/dbengine`: Netdata metrics storage
- `/fastcache/dlk`: User cache (ZFS dataset, autosnapshots disabled)
- `/var/lib/postgresql`: Forgejo PostgreSQL data (ZFS dataset
  `fastdisk/services/forgejo/postgresql`)
- `/var/lib/forgejo`: Forgejo app state (ZFS dataset
  `fastdisk/services/forgejo/app`)
- `/var/lib/forgejo-repositories`: Forgejo bare repositories (ZFS dataset
  `fastdisk/services/forgejo/repos`)
- `/var/lib/forgejo-lfs`: Forgejo Git LFS content (ZFS dataset
  `fastdisk/services/forgejo/lfs`)
- `/var/lib/trivia/rounds`: Per-round subdirectories for the trivia drip
  server (no dedicated ZFS dataset; ~150 MB total, ephemeral per event)

## Updating This Document

Update this document when:

- Adding, removing, or renaming directories
- Adding new hosts or modules
- Changing the purpose of a component
