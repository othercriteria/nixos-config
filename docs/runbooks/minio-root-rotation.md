# MinIO Root Password Rotation

Rotate the MinIO root credential when it may have been exposed or as
periodic hygiene. Root is SOPS-managed
(`gitops-veil/private/minio-root.sops.yaml`) and consumed only by MinIO
itself; bucket-scoped users (`registry-svc`, `jsa-agent`, `stiletto-svc`)
are unaffected.

Initial setup and the scoped-user model are documented in
[MinIO root credentials](../COLD-START.md#minio-root-credentials-object-store).

## Steps

1. Edit the SOPS secret and reconcile so the cluster Secret updates:

   ```sh
   ( cd gitops-veil && sops private/minio-root.sops.yaml )   # change root-password
   git -C gitops-veil add -A && git -C gitops-veil commit -m "chore: rotate minio root" \
     && git -C gitops-veil push
   # bump the submodule in nixos-config, then on the cluster:
   flux reconcile source git gitops-veil -n flux-system
   flux reconcile kustomization veil-cluster -n flux-system
   ```

1. Restart MinIO so it re-reads the env (root creds load only at startup):

   ```sh
   kubectl -n object-store delete pod \
     object-store-minio-0 object-store-minio-1 object-store-minio-2 \
     object-store-minio-3 object-store-minio-4 object-store-minio-5
   ```

   The StatefulSet uses `podManagementPolicy: Parallel`, so all pods
   recreate together. Wait for quorum (~15s) before testing.

1. Verify with an `mc` pod: new root works, old password rejected, scoped
   users still list/write their buckets (`mc admin info`, `mc ls`).

## In config

- `gitops-veil/public/minio.yaml` — HelmRelease, `auth.existingSecret`
- `gitops-veil/private/minio-root.sops.yaml` — root creds (SOPS)
