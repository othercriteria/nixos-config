# NixOS Configuration

Personal NixOS configuration managed with flakes.

## Project Structure

```console
.
├── flake.nix             # Flake configuration
├── hosts/                # Host-specific configurations
│   ├── common/           # Shared configuration
│   │   └── default.nix   # Base configuration
│   ├── laptop/           # Host-specific configs
│   │   └── default.nix
│   ├── desktop/          # Host-specific configs
│   │   └── default.nix
│   └── default.nix       # Host selector
├── modules/              # Reusable NixOS modules
├── home/                 # Home-manager configurations
├── secrets/              # Encrypted secrets (using git-secret)
└── assets/               # Static assets (fonts, images, etc.) - managed with Git LFS
```

## Quick Start

1. Install Git LFS and verify installation:

   ```bash
   git lfs install
   git lfs status
   ```

1. Clone the repository:

   ```bash
   git clone --recursive https://github.com/othercriteria/nixos-config.git

   # If already cloned, initialize and update submodules:
   git submodule update --init --recursive
   ```

1. Initialize security tools:

   ```bash
   make init-security
   ```

1. Set up your email for git-secret:

   ```bash
   git secret tell your@email.com
   ```

## Security Notes

- Never commit unencrypted secrets
- Use `.gitignore` for temporary files and local overrides
- All secrets must be encrypted using git-secret before committing
- Pre-commit hooks will scan for accidental secret exposure
- Run `make scan-secrets` to check for exposed secrets

## Usage

1. Make changes to configuration
1. Sync changes to system:
   - Preview changes: `make sync-to-system`
   - Apply changes: `make force-sync-to-system`
1. Test and apply configuration:
   - Test: `make dry-run-host HOST=hostname`
   - Apply: `make apply-host HOST=hostname`

## Maintenance

- Update flake inputs: `make flake-update` (use `make flake-restore` to undo)
- Run all checks: `make check-all`
- Manage secrets:
  - Reveal encrypted files: `make reveal-secrets`
  - Keep secrets list in `.gitsecret/paths/mapping.cfg` up to date
- System management:
  - List recent generations: `make list-generations`
  - Rollback to previous state: `make rollback`

## Asset Management

Large files in the `assets/` directory are managed using Git LFS. The following
file types are automatically tracked:

- Font files (`*.ttf`, `*.otf`)
- Images (`*.png`, `*.jpg`)
- Archives (`*.zip`)

When adding new large files:

1. Ensure they are in the `assets/` directory
1. Verify they match the patterns in `.gitattributes`
1. Run `git lfs status` to confirm tracking

## License

MIT
