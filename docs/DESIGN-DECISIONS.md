# Design Decisions

This document records significant design choices in this NixOS configuration,
including the reasoning, trade-offs, and alternatives considered. Each decision
includes a rough timestamp to help identify when it might be due for
reconsideration.

Format inspired by [Architecture Decision Records (ADRs)](https://adr.github.io/).

---

## Using Nix Flakes

**Date:** Pre-2024 (inherited) | **Status:** Active | **Last reviewed:** Dec 2025

**Problem:** Need reproducible, composable NixOS configuration management.

**Decision:** Use flakes as the primary configuration mechanism (`flake.nix`).

**Why:** Flakes provide hermetic evaluation via `flake.lock`, standardized
structure, easy composition of external modules, and alignment with modern Nix
tooling (`nix develop`, `nix build`, `nix flake`). Most new NixOS projects
assume flakes.

**Trade-offs:**

- ✅ Reproducible builds across machines and time
- ✅ Clean dependency management
- ❌ Still technically "experimental" (though widely adopted)
- ❌ Learning curve; some older docs don't apply

**Alternatives:** Traditional `configuration.nix` (simpler but less
reproducible), Niv + channels (pre-flakes pinning, more manual).

**Risks:** Flakes API could change before stabilization (low risk given
adoption). Some tools/docs still assume non-flake setups.

**Reconsider if:** Flakes are deprecated, or a better alternative emerges.

---

## Host NVIDIA Drivers for Kubernetes

**Date:** ~2025 | **Status:** Active | **Last reviewed:** Dec 2025

**Problem:** GPU workloads in Kubernetes typically use the NVIDIA GPU Operator,
which assumes FHS-compliant filesystem layout (`/usr/lib`, etc.) and manages
drivers independently. NixOS has non-standard paths and immutable configuration.

**Decision:** Use NixOS-managed NVIDIA drivers on the host with
`nvidia-container-toolkit` for containerd integration, rather than GPU Operator.

**Why:**

- GPU Operator assumes FHS paths that don't exist on NixOS
- Driver version controlled via NixOS config, not separate operator lifecycle
- Host drivers are tested with NixOS kernel; container drivers may mismatch
- No need for compatibility shims or workarounds

**Implementation:**

```nix
services.xserver.videoDrivers = [ "nvidia" ];
hardware.nvidia-container-toolkit.enable = true;
```

Kubernetes accesses GPUs via device plugin (`nvidia.com/gpu` resource).

**Trade-offs:**

- ✅ Works reliably on NixOS
- ✅ Declarative driver management
- ❌ Can't use GPU Operator's automatic updates
- ❌ Driver updates require host rebuild

**Alternatives:** GPU Operator with workarounds (extensive patching needed),
pre-built images with baked-in drivers (loses flexibility).

**Risks:** Must manually track NVIDIA driver updates. Most k8s GPU docs assume
GPU Operator.

**Reconsider if:** GPU Operator gains NixOS support, NVIDIA releases official
NixOS packaging, or multi-distro cluster standardization becomes important.

---

## CI on Push Only (No PR Triggers)

**Date:** Dec 2025 | **Status:** Active | **Last reviewed:** Dec 2025

**Problem:** GitHub Actions CI can trigger on `push` and `pull_request`. This
repo uses a self-hosted runner on `skaia` with KVM access for NixOS VM tests.
The repo is public.

**Decision:** Only trigger CI on `push` to `main`, not on `pull_request`.

**Why:** GitHub
[explicitly warns](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#self-hosted-runner-security)
that forks of public repos can run arbitrary code on self-hosted runners via
PRs. With `pull_request` enabled, anyone could fork the repo, modify the
workflow, open a PR, and execute arbitrary commands on `skaia`.

**Implementation:**

```yaml
# .github/workflows/ci.yml
on:
  push:
    branches: [main]
  # pull_request: deliberately omitted for security
```

**Trade-offs:**

- ✅ No arbitrary code execution from forks
- ✅ Simpler security model
- ❌ No automatic PR checks
- ❌ Must run tests manually before merging
- ❌ External contributors don't get CI feedback

**Alternatives:**

1. **Make repo private** — eliminates risk but loses portfolio value
1. **Require approval for fork PRs** — GitHub setting adds friction but allows
   PR checks after manual review
1. **GitHub-hosted for PRs, self-hosted for main** — complex, limited free tier,
   no KVM
1. **Isolated VM runner** — more infrastructure to manage

**Mitigations:** Run `make test` locally before pushing. Pre-commit hooks catch
common issues. Consider Option B if external contributions increase.

**Risks:** Broken code could be pushed if local testing is skipped. External
contributors won't see CI results.

**Reconsider if:** Repo becomes private, GitHub adds better runner isolation,
external contributions increase, or CI moves to isolated environment.

---

## Per-host Secrets Allowlist (vs. encrypt-time recipients)

**Date:** May 2026 | **Status:** Active | **Last reviewed:** May 2026

**Problem:** `make sync-to-system` rsyncs the entire decrypted
`secrets/` directory from the workspace into `/etc/nixos/secrets/` on
the target host (modulo `*.secret`). Combined with the cold-start
practice of importing the operator's GPG key on each host, this
gives every host on-disk access to every plaintext secret in the
repo. The blast radius is wider than necessary for nodes like the
veil meteors that only need a small subset (k3s join token, per-host
Teleport token).

**Decision:** Enforce a per-host allowlist at NixOS activation time
(`modules/host-secrets-manifest.nix`). Each host declares the
relative paths under `/etc/nixos/secrets/` its services actually
reference; the activation script deletes anything else.

**Why activation-time, not encrypt-time:**

- The encrypted `.secret` files in the repo are encrypted to the
  operator's personal GPG key, not to per-host keys. Restricting
  *who can decrypt* would require restructuring the recipient model
  (e.g. SOPS with per-host age keys), which is a larger refactor
  with broader consequences.
- The actual runtime blast radius is what services on a host can
  read from disk. Pruning post-rsync addresses that directly,
  needs no recipient restructuring, and is opt-in per host.
- Plaintext briefly exists on disk between the rsync and the
  activation scrub. That window is acceptable in this threat model;
  closing it further would require either filtering at rsync time
  (more brittle, lives in the `Makefile` not in NixOS) or
  reorganising recipients.

**Trade-offs:**

- Defense against service-level compromise: a misconfigured or
  exploited service sees only its host's manifested subset
- Defense against fs-read on a meteor: only veil-relevant secrets,
  not skaia's signing keys or OAuth tokens
- Opt-in: hosts without a manifest behave as before (no change)
- Does NOT address the workspace-checkout-plus-GPG-key blast
  radius. A host that holds both the encrypted `.secret` files and
  the operator's GPG private key can still decrypt everything. That
  is a separate, larger refactor (e.g. deploy secrets from a single
  trusted host instead of decrypting on each host).

**Alternatives:**

- SOPS with per-host age recipients. Cleaner conceptually, but a
  larger lift, and would be more disruptive to the existing
  git-secret workflow that works well for skaia.
- Filter at rsync time via per-host include lists in the
  `Makefile`. Smaller change but moves policy out of NixOS into
  shell glue; easier to skip accidentally.
- Stop deploying with a workspace checkout on each host; push
  secrets out-of-band from a single trusted host. Right answer
  long-term, much bigger change.

**Risks:** A future contributor adds a service on a host without
updating its manifest and the activation script deletes the secret
it needs at next rebuild. Mitigation: the activation script logs
each pruned path to journald, and `nixos-rebuild switch` runs
activation immediately, so the breakage surfaces during the same
rebuild that introduced it.

**Reconsider if:** We migrate to SOPS (subsumes this), or we adopt a
deploy-from-trusted-host model (also subsumes this).

**In config:** `modules/host-secrets-manifest.nix`,
`hosts/server-common/default.nix` (import),
`hosts/meteor-{1,2,3,4}/default.nix` (current consumers).

---

## Adding New Decisions

When documenting a new decision, include:

- **Date/Status:** When decided, current state
- **Problem:** What situation prompted this
- **Decision:** What we chose
- **Why:** Rationale
- **Trade-offs:** Benefits (✅) and costs (❌)
- **Alternatives:** What else was considered
- **Risks:** What could go wrong
- **Reconsider if:** Triggers for revisiting
