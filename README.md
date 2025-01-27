# NixOS Configuration

Personal NixOS configuration managed with flakes.

## Project Structure

```console
.
├── flake.nix
├── hosts/ # Host-specific configurations
│ └── default/ # Current machine configuration
├── modules/ # Reusable NixOS modules
├── home/ # Home-manager configurations
├── secrets/ # Encrypted secrets (using git-secret)
└── assets/ # Static assets (fonts, images, etc.) - managed with Git LFS
```

## Setup Steps

1. Migration Plan
   - [ ] Move current configuration from `/etc/nixos`
   - [ ] Reorganize into logical modules
   - [ ] Encrypt sensitive files (ddclient-password.txt, etc.)
   - [ ] Test configuration locally
   - [ ] Create deployment script

## Quick Start

1. Install Git LFS and verify installation:

   ```bash
   git lfs install
   git lfs status
   ```

1. Clone the repository:

   ```bash
   git clone https://github.com/username/nixos-config.git ~/workspace/nixos-config
   ```

1. Set up git-secret:

   ```bash
   git secret init
   git secret tell your@email.com
   ```

1. Install pre-commit hooks:

   ```bash
   pre-commit install
   ```

## Security Notes

- Never commit unencrypted secrets
- Use `.gitignore` for temporary files and local overrides
- All secrets must be encrypted using git-secret before committing
- Pre-commit hooks will scan for accidental secret exposure

## Usage

1. Make changes to configuration
1. Test locally: `nixos-rebuild test --flake .#hostname`
1. Apply changes: `sudo nixos-rebuild switch --flake .#hostname`

## Maintenance

- Regularly update flake inputs (`make flake-update`)
- Keep secrets list in `.gitsecret/paths/mapping.cfg` up to date
- Review pre-commit hook outputs carefully

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
