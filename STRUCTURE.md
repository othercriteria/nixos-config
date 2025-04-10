# Project Structure

This document outlines the structure and organization of this NixOS configuration
project.

## Overview

This project is organized as a NixOS configuration repository using the Nix Flakes
system. It contains configuration for different hosts, home-manager setups, and
shared modules.

## Key Directories and Their Purposes

### `.cursor/rules/`

Contains Cursor rule files (`.mdc`) that provide guidance and enforcement for
various aspects of the project.

Rules include:

- `cursor-rules-location.mdc`: Standards for organizing Cursor rule files
- `project-structure.mdc`: Standards for maintaining project structure documentation
- `nixos-commits.mdc`: Guidelines for NixOS configuration commits, including
  standardized commit messages, tracking of affected hosts, and ensuring
  documentation stays up-to-date
- `markdown-standards.mdc`: Standards for authoring Markdown files that conform to
  the project's linting requirements

### `hosts/`

Contains host-specific NixOS configurations. Each subdirectory represents a
different machine with its own specific configuration.

### `home/`

Contains Home Manager configurations for user environments.

### `modules/`

Contains shared NixOS and Home Manager modules that can be imported by various
configurations.

### `assets/` and `private-assets/`

Contains non-code assets for the system such as wallpapers, icons, or other
resources. The private-assets directory likely contains assets that shouldn't be
publicly shared.

### `secrets/`

Contains encrypted secrets managed by git-secret, based on the presence of
`.gitsecret/` directory and `.secrets.baseline` file.

## Important File Locations

- `flake.nix`: The main entry point for the NixOS flake configuration
- `flake.lock`: Lock file that pins dependencies to specific versions
- `Makefile`: Contains helpful commands and automation for managing the system
- `README.md`: Project documentation and usage instructions
- `.envrc`: Environment configuration for direnv
- `.pre-commit-config.yaml`: Configuration for pre-commit hooks
- `.gitleaks.toml`: Configuration for secret scanning with gitleaks
- `.markdownlint.json`: Configuration for markdown linting

## Component Dependencies

- The system uses Nix Flakes for dependency management
- Git and git-secret for version control and secrets management
- Pre-commit hooks for code quality and security checks
- Possibly home-manager for user environment management

## Configuration File Locations

- `flake.nix`: Main configuration entry point
- `hosts/*/`: Host-specific configurations
- `home/*/`: User-specific home configurations
- `modules/*/`: Shared module configurations
- `.cursor/rules/`: Configuration for Cursor AI assistance

## Update Guidelines

This document should be updated whenever:

- New directories are added
- Files are moved
- The overall project structure changes
- New components or hosts are introduced
