# Flux Snapshot

**These manifests are illustrative snapshots, not the source of truth.**

The authoritative manifests live in private `gitops-*` submodules. This
directory contains periodic snapshots of the `public/` portions for reference.

## Contents

- `veil/public/` — Public manifests for the veil cluster

## Notes

- Snapshots may be stale; check `gitops-veil/public/` for current state
- Private manifests are not included
- Do not edit files here; edit in the submodule and re-sync

## Sync

```bash
make snapshot-gitops
```
