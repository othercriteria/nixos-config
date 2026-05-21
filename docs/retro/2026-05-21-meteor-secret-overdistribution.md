# Retro: Veil Meteors Hold Every Repo Secret on Disk

**Date**: 2026-05-21
**Severity**: Low (latent risk, no observed exploitation)
**Duration**: Since the meteors joined the fleet (~late 2025)
**Impact**: None observed. Trust-boundary gap discovered during
scope-expansion review.

## Summary

While scoping a job-search agent for deployment on the veil
cluster, we audited the secret-distribution mechanism and found
that every host with a workspace checkout deployed via
`make apply-host` ends up with every plaintext secret in the repo
at `/etc/nixos/secrets/`. The intent for the veil meteors was that
they should hold only `veil-k3s-token` and a per-host Teleport
token. The reality was a superset that included skaia-only items
like `harmonia-cache-private-key` and `home-ca.key`.

This is not an incident in the active-threat sense. It is a latent
trust-boundary gap that became operationally relevant once we
started considering veil as a substrate for workloads with
materially different blast-radius requirements from skaia.

## How it works

Two mechanisms compose into the gap:

1. **Encrypt-time:** `.gitsecret/keys/pubring.kbx` has two GPG keys,
   both belonging to the operator. Every `.secret` file is encrypted
   to both. Per `docs/COLD-START.md` § 0, each host imports the
   operator's private GPG key during onboarding, so each host can
   decrypt every secret in a workspace checkout.

1. **Apply-time:** `make sync-to-system` runs
   `rsync -a --delete --exclude '*.secret' secrets/ /etc/nixos/secrets/`.
   The exclude only drops the encrypted ciphertexts; the decrypted
   plaintext files are copied wholesale. Every host that applies
   gets every secret on disk.

`hosts/meteor-{1,2,3,4}/default.nix` only reference `veil-k3s-token`
(via `modules/veil/k3s-common.nix`) and `teleport/meteor-N.token`
(via `modules/teleport-node.nix`). The other ~17 secrets are dead
weight on a meteor — and several of them confer skaia-level access.

## What worked

- `.secret` files in git are GPG-encrypted at rest; no plaintext
  has ever been committed.
- Meteors are LAN-only; no external SSH exposure.
- `make reveal-secrets` chmods plaintext files to 600.
- The gap was caught by audit, not by an attacker.

## What was overlooked

- Apply-time rsync copies every plaintext to every host
  irrespective of need.
- Cold-start asks every host to import the operator's private GPG
  key, sharing the decryption capability uniformly across the
  fleet.
- No per-host "needs only X" declaration existed anywhere; each
  host's actual secret usage was implicit in service config, never
  asserted.

## Root cause

The deploy model assumes a uniform fleet where the simplest way to
"have access to the secrets you need" is "have access to all
secrets." That was acceptable when skaia was the only host doing
non-trivial things, and was acceptable for meteors during initial
bootstrap. It scales poorly once different hosts are intended to
sit on different trust levels.

## Fixes applied

1. New module `modules/host-secrets-manifest.nix`. Hosts declare a
   per-host allowlist; the activation script prunes
   `/etc/nixos/secrets/` to that subset on every `nixos-rebuild
   switch`. Encrypted `.secret` files are always preserved (they're
   ciphertext).

1. Wired into `hosts/server-common/default.nix` so all headless
   servers can opt in. Activated with explicit allowlists on
   `hosts/meteor-{1,2,3,4}/default.nix`. Meteor allowlist is
   `veil-k3s-token` + `teleport/meteor-N.token` only.

1. Design rationale captured in `docs/DESIGN-DECISIONS.md` (why
   activation-time pruning rather than SOPS-style encrypt-time
   recipients, and what this does and does not address).

## What this does not fix

- The workspace checkout on a host still holds `.secret` files plus
  the operator's GPG private key. A host compromise can still
  decrypt every secret in the repo via the operator's key. Closing
  that gap means a structurally different deploy model (push from a
  single trusted host, or move to per-host SOPS recipients). Out of
  scope here.
- `secrets/home-ca.crt` is in the GPG-encrypted set despite being a
  public certificate. Harmless but odd; worth moving to `assets/`
  in a future cleanup.
- The `Makefile` rsync rules still copy everything by default; the
  manifest scrubs post-rsync rather than filtering pre-rsync. A
  rsync-time include list would close the brief on-disk window but
  would split policy across NixOS and `Makefile`. Acceptable trade
  for now.

## Follow-up actions

- [ ] Rotate `secrets/harmonia-cache-private-key` (procedure:
      `docs/runbooks/harmonia-key-rotation.md`). The old key has
      been on every meteor's disk for months; rotation is a
      hygiene step and exercises the rotation playbook end-to-end.
- [ ] Decide whether `secrets/home-ca.key` warrants rotation.
      Bigger lift because every leaf cert downstream rolls with it;
      consider separately.
- [ ] Finish Teleport enrollment on `meteor-1..4` so SSH outages
      are not single-path. (Independent of this retro, but surfaced
      during the same audit.)
- [ ] Consider deferring per-host SOPS migration until the
      job-search agent or another in-cluster workload actually
      needs an in-cluster secret. Don't pave generic infrastructure
      ahead of a real consumer.
