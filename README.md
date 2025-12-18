# NixOS Configuration

Personal NixOS configuration managed with flakes.

## Project Structure

```text
.
├── flake.nix             # Flake entrypoint
├── hosts/                # Host-specific configurations
│   ├── common/           # Shared desktop workstation config
│   ├── server-common/    # Shared headless server config
│   ├── skaia/            # Primary workstation + k3s control plane
│   ├── meteor-{1,2,3,4}/ # Veil cluster k3s nodes
│   └── hive/             # Headless server (Urbit, etc.)
├── modules/              # Reusable NixOS modules
├── home/                 # Home Manager configuration
├── docs/                 # Documentation (cold start, observability, etc.)
├── secrets/              # Encrypted secrets (git-secret)
├── assets/               # Static assets (certs, configs)
├── private-assets/       # Private assets submodule (fonts, wallpapers)
└── gitops-veil/          # GitOps submodule for veil cluster
```

## Quick Start

1. Clone the repository:

   ```bash
   git clone https://github.com/othercriteria/nixos-config.git
   cd nixos-config
   ```

1. Enter the dev shell (provides tools like git-secret, nixpkgs-fmt, etc.):

   ```bash
   nix develop
   ```

1. Initialize submodules (as needed):

   ```bash
   make add-private-assets    # Private assets (fonts, etc.)
   make add-gitops-veil       # GitOps for veil cluster (optional)
   ```

1. Initialize Git LFS and reveal secrets:

   ```bash
   git lfs install
   git lfs pull
   make reveal-secrets        # Requires GPG key - see docs/COLD-START.md
   ```

## Usage

Apply configuration to a host:

```bash
make apply-host HOST=skaia
```

The `apply-host` target includes a safety check - if the current hostname
doesn't match `HOST`, you'll be prompted to confirm before applying.

Build without applying (useful for testing or cross-host builds):

```bash
make build-host HOST=hive
```

## Hosts

| Host | Type | Purpose |
| ---- | ---- | ------- |
| `skaia` | Desktop + Server | Primary workstation, k3s control plane, DNS, observability |
| `meteor-1..4` | Server | Veil cluster k3s nodes |
| `hive` | Server | Headless server for Urbit and misc services |
| `demo` | VM | Standalone observability demo (no secrets required) |

## Security Notes

- Never commit unencrypted secrets
- All secrets are encrypted with git-secret before committing
- Pre-commit hooks scan for accidental secret exposure
- Run `make scan-secrets` to check for exposed secrets

## Demo & Testing

Try the observability stack without any setup:

```bash
make demo
```

This builds and runs a self-contained VM with Prometheus, Grafana, and Loki.
Access the services from your host (ports offset to avoid conflicts):

- Prometheus: <http://localhost:19090>
- Grafana: <http://localhost:13000> (anonymous access enabled)
- Loki: <http://localhost:13100/ready>

Demo VM management:

```bash
make demo-status    # Show VM status and port info
make demo-stop      # Stop the running VM
make demo-clean     # Remove disk image for fresh start
make demo-fresh     # Stop, clean, and restart in one command
```

Run the integration test suite:

```bash
make test                  # All tests
make test-observability    # Just the observability stack test
```

## Continuous Integration

CI runs on a self-hosted GitHub Actions runner (on `skaia`), which provides:

- **Lint & format checks** — nixfmt, statix, deadnix
- **Build validation** — All host configurations built in parallel
- **Integration tests** — NixOS VM tests with KVM

Builds automatically populate the [Harmonia](modules/harmonia.nix) binary cache
(`cache.home.arpa`), so other hosts benefit from cached derivations.

See [`.github/workflows/ci.yml`](.github/workflows/ci.yml) for the workflow
definition and [`docs/COLD-START.md`](docs/COLD-START.md#20-github-actions-self-hosted-runner)
for runner setup.

## Maintenance

- Update flake inputs: `make flake-update` (use `make flake-restore` to undo)
- Run all checks: `make check-all`
- List recent generations: `make list-generations`
- Rollback to previous state: `make rollback`
- Reveal secrets: `make reveal-secrets`

## Documentation

- [Cold Start Guide](docs/COLD-START.md) - Manual steps for new hosts
- [Observability](docs/OBSERVABILITY.md) - Metrics, logs, dashboards
- [Addressing](docs/residence-1/ADDRESSING.md) - LAN/DNS configuration
- [Project Structure](STRUCTURE.md) - Detailed directory documentation

## License

MIT
