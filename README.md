
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
└── assets/ # Static assets (fonts, images, etc.)
```

## Setup Steps

1. Migration Plan
   - [ ] Move current configuration from `/etc/nixos`
   - [ ] Reorganize into logical modules
   - [ ] Encrypt sensitive files (ddclient-password.txt, etc.)
   - [ ] Test configuration locally
   - [ ] Create deployment script

## Quick Start

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

- Regularly update flake inputs
- Keep secrets list in `.gitsecret/paths/mapping.cfg` up to date
- Review pre-commit hook outputs carefully

## License

MIT
