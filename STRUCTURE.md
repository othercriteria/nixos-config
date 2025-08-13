# Project Structure

This document outlines the structure and organization of this NixOS
configuration.

## Key Directories and Their Purposes

- `modules/`: Contains shared NixOS and Home Manager modules that can be
  imported by various hosts or user profiles.
- `hosts/`: Contains per-host NixOS configuration files and subdirectories.
  - `skaia/`: Primary workstation host and its modules
  - `server-common/`: Headless server baseline for Kubernetes nodes (no GUI)
  - `meteor-1/`, `meteor-2/`, `meteor-3/`: Veil cluster nodes (k3s servers)
- `home/`: Contains Home Manager user configuration modules.
- `docs/`: Project documentation, including cold start and observability
  guides.
  - `VEIL-PLAN.md`: Plan and progress for the veil cluster rollout
  - `residence-1/`: Site/network documentation
    - `ADDRESSING.md`: LAN addressing and DNS strategy for residence-1
- `assets/`: Fonts, images, and other static assets.
- `private-assets/`: Private, non-public assets (git submodule initialized via
  `make add-private-assets`).
- `secrets/`: Encrypted secrets managed by git-secret (e.g., `veil-k3s-token`).
- `.cursor/rules/`: Cursor rule files for code quality and workflow standards.
  - `scripts/`: Helper scripts used by Cursor rules (e.g., for commit automation).

## NixOS Entrypoint

- `flake.nix`: The main Nix flake entrypoint for the system.
- `flake.lock`: Flake lock file for reproducible builds.
- `Makefile`: Automation for common tasks (build, switch, check, etc).

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
- `hosts/`: Per-host configuration (e.g., `skaia/`, `server-common/`, `meteor-*/`)
- `home/`: User-level configuration
- `docs/`: Documentation for setup, cold start, observability, and network/site
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
