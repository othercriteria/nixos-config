# Project Structure

This document outlines the structure and organization of this NixOS
configuration.

## Key Directories and Their Purposes

- `modules/`: Contains shared NixOS and Home Manager modules that can be
  imported by various hosts or user profiles.
- `hosts/`: Contains per-host NixOS configuration files and subdirectories.
- `home/`: Contains Home Manager user configuration modules.
- `docs/`: Project documentation, including cold start and observability
  guides.
- `assets/`: Fonts, images, and other static assets.
- `private-assets/`: Private, non-public assets (not tracked in git).
- `secrets/`: Encrypted secrets managed by git-secret.
- `.cursor/rules/`: Cursor rule files for code quality and workflow standards.

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

## Directory Purposes

- `modules/`: Shared modules for NixOS and Home Manager
- `hosts/`: Per-host configuration (e.g., `skaia/`, `common/`)
- `home/`: User-level configuration
- `docs/`: Documentation for setup, cold start, and observability
- `assets/`: Static assets (fonts, images)
- `private-assets/`: Private assets (not tracked in git)
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
