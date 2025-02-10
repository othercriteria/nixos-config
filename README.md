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
├── assets/               # Static assets (fonts, images, etc.) - managed with Git LFS
└── private-assets/       # Private assets (fonts, images, etc.) - managed with Git LFS
```

## Quick Start

1. Clone the repository:

   ```bash
   git clone https://github.com/othercriteria/nixos-config.git
   cd nixos-config
   ```

1. Add the private assets submodule:

   ```bash
   git submodule add git@github.com:othercriteria/private-assets.git private-assets
   ```

1. Initialize Git LFS:

   ```bash
   git lfs install
   git lfs pull
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
   - Sync changes: `make sync-to-system`
1. Apply configuration:
   - Apply: `make apply-host HOST=hostname`

## Maintenance

- Update flake inputs: `make flake-update` (use `make flake-restore` to undo)
- Run all checks: `make check-all`
- Manage secrets:
  - Reveal encrypted files: `make reveal-secrets`
  - Keep secrets list in `.gitsecret/paths/mapping.cfg` up to date
  - Easy to do this with `git secret add <file>`
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

### Private Assets

For assets you don't want to share with the world, use the `private-assets`
submodule.

## License

MIT
