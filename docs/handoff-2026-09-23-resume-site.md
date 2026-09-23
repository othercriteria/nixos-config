# Hand-off: résumé page + apex page for valueof.info (2026-09-23)

Written by a Claude Code session in `~/workspace/job-search-2026` for
the agent managing this repo. These changes are in the working tree
only: **not committed, not applied**. `modules/k3s-nvidia-runtime.nix`
was already modified before this session touched anything; leave it
to its owner.

## Update (same day)

The résumé repo is pushed. `github:othercriteria/resume` at `a852419`
on `master` carries the flake; `nix build .#site` and the deploy gate
pass. `resumeSite.enable = true` stays. The module's `branch` default
is `master` (that repo keeps the name), and the résumé alert text
matches. `STRUCTURE.md` never said `main` for this page.
`modules/k3s-nvidia-runtime.nix` is still someone else's change.

`modules/resume-site/default.nix` differs from `baltic-site` in names
and comments only, plus `branch = "master"`. The site-flake is the
other intentional difference: it re-exports the résumé flake's
`packages.site` (that derivation runs `make test` then `make site` and
passes `self.shortRev`), so a red gate fails the build and the old
page stays up.

## What changed and why

DK wants his résumé served at `valueof.info/daniel-klein-resume/` and a
real page at the apex instead of the "ingress being stood up" stub.

- `assets/valueof-info/index.html`, `assets/valueof-info/site.css` —
  the apex page (static, no scripts, no off-origin requests). Moved out
  of the inline `writeTextFile` in `hosts/skaia/nginx.nix` because the
  vhost's `default-src 'self'` CSP was blocking the stub's inline
  `<style>`; the page is now styled by a file.
- `hosts/skaia/nginx.nix` — `valueofInfoStatic` is now a `runCommand`
  copying those two assets; new `= /daniel-klein-resume` (301) and
  `/daniel-klein-resume/` (alias to `config.custom.resumeSite.docRoot`,
  strict CSP `default-src 'none'; style-src 'self'`, charset) locations.
  The book location is untouched.
- `modules/resume-site/default.nix` + `site-flake/flake.nix` — a
  near-verbatim sibling of `modules/baltic-site` (sed-renamed: unit
  `resume-site-deploy`, user/group `resume-site`, state
  `/var/lib/resume-site`, source `github:othercriteria/resume`, input
  name `resume`). The site-flake re-exports the résumé repo's
  `packages.x86_64-linux.site`, whose build runs `make test` (deploy
  gate) then `make site` with fonts pinned via `FONTCONFIG_FILE`.
- `hosts/skaia/default.nix` — import + `custom.resumeSite.enable = true`.
- `modules/prometheus-rules.nix` — `resume-site.rules`
  (`ResumeSiteDeployFailing` 30m, `ResumeSiteDeployStalled` 1h), same
  shape as the baltic rules.
- `STRUCTURE.md` — `resume-site/` and `/var/lib/resume-site` entries.

## Verification already done

- `nixfmt --check` clean over the tree. `markdownlint` reports only
  pre-existing failures (`docs/retro/2026-01-09-…`, the edge-to-hive
  runbook table, `gitops-veil/README.md`), none in touched files.
- `nix eval path:.#nixosConfigurations.skaia.config.services.nginx.virtualHosts."valueof.info".locations`
  shows the five locations; the `resume-site-deploy` ExecStart and the
  apex `root` store path evaluate.
- The résumé repo's `nix build path:.#site` succeeds in the sandbox
  (1-page PDF, gate passes).

## What is NOT done, in order

1. `make apply-host HOST=skaia`. First deploy pulls texlive on skaia;
   the unit's `TimeoutStartSec` is 30 min. Then check
   `systemctl status resume-site-deploy`, `journalctl -u
   resume-site-deploy`, and `curl -I https://valueof.info/`
   (expect `text/html`, the new page) and
   `https://valueof.info/daniel-klein-resume/`.
1. Consider whether `baltic-site` and `resume-site` should be one
   parameterised module (`custom.publishedSites.<name>`) rather than
   two copies. Deliberately not done here to keep the diff reviewable.
1. Commit per `.cursor/rules/nixos-commits.mdc` (pre-commit must pass;
   DK verifies functionality before commit). Delete this hand-off file
   in the same commit or move it under `docs/` history as you prefer.

## Related, outside this repo

- `mesokurtosis.com` (the résumé's old web link) is an S3-hosted 2018
  Hakyll site, HTTP-only. Not referenced anywhere in nixos-config. DK
  plans an S3 redirect to `https://valueof.info/`; nothing to do here.
- `ddclient.nix` publishes `stiletto-demo` but the vhost is
  `stiletto.valueof.info`; the name resolves today, so it is presumably
  a manual record at Namecheap. Noted, not changed.
