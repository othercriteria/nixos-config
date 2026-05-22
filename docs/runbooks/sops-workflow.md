# SOPS Workflow for `gitops-veil`

SOPS-encrypted Kubernetes Secret manifests live under
`gitops-veil/private/` with the `.sops.yaml` suffix. Flux's
kustomize-controller decrypts them at apply time using the age private
key stored in the `sops-age` Secret in `flux-system`. The matching
public key is committed to `gitops-veil/.sops.yaml`.

Bootstrap of the keypair + in-cluster Secret is described in
`docs/COLD-START.md` § 10. This document covers everyday usage:
encrypt a new Secret, edit an existing one, and rotate the key.

## Prerequisites

- The repo dev shell (`nix develop`) provides `sops` and `age`.
- The age private key must be available locally to decrypt or edit
  existing files. Two ways to provide it:

  - **Recommended:** decrypt `nixos-config/secrets/sops-age.key` via
    `make reveal-secrets`, then export
    `SOPS_AGE_KEY_FILE=$(pwd)/secrets/sops-age.key`.
  - **Alternative:** copy the key body (one line, starts with
    `AGE-SECRET-KEY-`) into `~/.config/sops/age/keys.txt` — SOPS reads
    that file by default.

## Encrypt a new Secret manifest

The `.sops.yaml` creation rule matches paths of the form
`private/<name>.sops.yaml`. Write the cleartext at the target path,
then encrypt in place:

```bash
cd gitops-veil

# Write the cleartext manifest where it will live (path matters for
# the SOPS creation rule to match).
cat > private/my-new-secret.sops.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-new-secret
  namespace: my-namespace
type: Opaque
stringData:
  api_token: "REPLACE-WITH-REAL-VALUE"
EOF

# Encrypt in place. Only `data`/`stringData` values are encrypted;
# metadata stays readable so kustomize can index by name/namespace.
sops --encrypt --in-place private/my-new-secret.sops.yaml

# Add the new resource to the private kustomization
$EDITOR private/kustomization.yaml   # append under resources:

git add private/my-new-secret.sops.yaml private/kustomization.yaml
git commit -m "secrets: add my-new-secret"
git push
```

Flux will pick the change up within ~1 minute and apply the decrypted
Secret to the cluster.

## Edit an existing encrypted Secret

```bash
cd gitops-veil
sops private/my-new-secret.sops.yaml   # opens $EDITOR with cleartext
# Save + exit; SOPS re-encrypts on close.
git diff             # only the ciphertext blob + mac change
git commit -am "secrets: rotate api_token for my-new-secret"
git push
```

## Rotate the age keypair

Use this when the private key may have been exposed, or as periodic
hygiene.

1. Generate a new keypair:

   ```bash
   age-keygen -o /tmp/sops-age.new
   ```

1. Update `gitops-veil/.sops.yaml` so the `age:` field lists the new
   public key (append; rotation is atomic per `sops updatekeys`).

1. Re-encrypt every encrypted file with the new recipient list:

   ```bash
   cd gitops-veil
   for f in $(git ls-files 'private/*.sops.yaml'); do
     sops updatekeys -y "$f"
   done
   ```

1. Replace the in-cluster Secret with the new key:

   ```bash
   kubectl -n flux-system delete secret sops-age
   kubectl -n flux-system create secret generic sops-age \
     --from-file=age.agekey=/tmp/sops-age.new
   ```

1. Replace the encrypted copy in `nixos-config/secrets/`:

   ```bash
   cp /tmp/sops-age.new nixos-config/secrets/sops-age.key
   cd nixos-config
   git secret hide
   git commit -am "secrets: rotate sops-age key"
   shred -u /tmp/sops-age.new
   ```

1. Once Flux has reconciled successfully against the new key, drop
   the old public key from `.sops.yaml` and rerun `sops updatekeys`
   to strip the old recipient from every file.

## Verifying a Secret was decrypted in-cluster

```bash
kubectl -n monitoring get secret alertmanager-ntfy-credentials \
  -o jsonpath='{.data.password}' | base64 -d
```

If decryption failed, Flux's kustomize-controller logs will say so:

```bash
kubectl -n flux-system logs -l app=kustomize-controller --tail=200
```
