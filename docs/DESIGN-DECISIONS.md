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
