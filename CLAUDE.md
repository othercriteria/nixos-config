# Agent Orientation

Start here. This file exists so AI agents discover the right
context without fumbling.

## Key Files

- [README.md](README.md) — project overview, quick start, host
  inventory
- [STRUCTURE.md](STRUCTURE.md) — detailed directory layout
- [RULES.md](RULES.md) — index of all Cursor rules
- [flake.nix](flake.nix) — flake entrypoint (inputs, outputs,
  host definitions)
- [Makefile](Makefile) — build/deploy targets (`apply-host`,
  `flake-update`, `test`, etc.)

## Rules (read before making changes)

All in `.cursor/rules/`:

- `secrets-management.mdc` — git-secret workflow for secrets
- `cold-start.mdc` — document manual bootstrap steps
- `nixos-commits.mdc` — commit message format, verification
- `project-structure.mdc` — keep STRUCTURE.md in sync
- `markdown-standards.mdc` — 80-char lines, list spacing, etc.
- `security-retros.mdc` — security retrospective process
- `rules.mdc` — standards for rule files themselves

## Documentation

All in `docs/`:

- `COLD-START.md` — manual steps for new host bootstrap
- `DESIGN-DECISIONS.md` — architecture rationale
- `OBSERVABILITY.md` — metrics, logs, dashboards
- `residence-1/ADDRESSING.md` — LAN/DNS layout

## Secrets

Managed via git-secret. Plaintext lives in `secrets/`, encrypted
as `secrets/*.secret`. See `.cursor/rules/secrets-management.mdc`
for the full workflow. Key commands:

- `make reveal-secrets` — decrypt all secrets
- `git secret add secrets/<file>` — track a new secret
- `git secret hide` — encrypt before committing

Nix configs reference secrets as `/etc/nixos/secrets/<filename>`.
