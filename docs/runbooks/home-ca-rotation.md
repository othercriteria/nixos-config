# Home CA Rotation

Rotate the `home-ca` certificate authority that signs TLS for the
veil cluster's internal ingresses. Like the
[harmonia binary cache rotation][harmonia], this uses a transitional
dual-trust window so every NixOS host accepts both the retiring and
the incoming root while leaf certificates are re-issued.

Initial generation is documented in
[cert-manager CA secret](../COLD-START.md#cert-manager-ca-secret).

[harmonia]: harmonia-key-rotation.md

## Trust + signing footprint

- **Trust**: `assets/certs/rootCA.pem` is loaded via
  `security.pki.certificateFiles` in `hosts/common` (skaia) and
  `hosts/server-common` (hive + meteor-1..4). Every NixOS host
  trusts the CA system-wide; rebuild + activate to pick up changes.
- **Signing**: `secrets/home-ca.{crt,key}` is loaded into
  `home-ca-secret` in the `cert-manager` namespace on veil. The
  `home-ca` ClusterIssuer
  (`gitops-veil/issuer/clusterissuer.yaml`) signs leaf certs for
  ingresses using `cert-manager.io/cluster-issuer: "home-ca"`.
- **Out-of-band trust**: any non-NixOS clients (browsers, phones)
  that were `mkcert -install`'d need a fresh trust install after
  rotation; track those manually.

## Steps

### Phase A — Dual-trust window

1. Generate the new CA keypair alongside the old one. We've moved
   away from mkcert (RSA-3072) to a leaner openssl-built ECDSA
   P-256 root with a 5-year lifetime; date-suffix the file names so
   both can coexist on disk:

   ```sh
   nix shell nixpkgs#openssl --command bash -c '
     STAMP=$(date +%Y%m%d)
     openssl ecparam -genkey -name prime256v1 -noout \
       -out secrets/home-ca.key.new
     openssl req -x509 -new -key secrets/home-ca.key.new \
       -days 1827 -sha256 \
       -subj "/O=home-ca/OU=dlk@skaia/CN=home-ca-${STAMP}" \
       -addext "basicConstraints=critical,CA:TRUE" \
       -addext "keyUsage=critical,keyCertSign,cRLSign" \
       -addext "subjectKeyIdentifier=hash" \
       -out secrets/home-ca.crt.new
     chmod 600 secrets/home-ca.key.new
     cp secrets/home-ca.crt.new assets/certs/rootCA-next.pem
   '
   ```

   Why these choices:

   - **ECDSA P-256**: smaller, faster, well-supported by every
     modern TLS client; cert-manager and kubernetes-sigs tooling
     happy with it.
   - **5 years (1827d)**: long enough that hygiene-only rotation
     isn't constant churn, short enough to keep the muscle memory
     fresh.
   - **CN `home-ca-YYYYMMDD`**: self-identifying generation in any
     chain dump.
   - **`subjectKeyIdentifier=hash`**: helps tools that chain by SKI
     rather than DN.

   _Optional hardening for a future rotation:_ add
   `nameConstraints=permitted;DNS:.home.arpa` to scope the CA. Skip
   this rotation to keep the variable count down; it's a deliberate
   forward-looking note.

1. Track the new private key with git-secret and hide it:

   ```sh
   git secret add secrets/home-ca.key.new
   git secret add secrets/home-ca.crt.new
   git secret hide
   ```

   The `.crt.new` is technically not secret (it's a public cert),
   but keeping it next to the private key during the rotation
   reduces the chance of mismatched halves landing in commits. It
   moves to `assets/certs/` in Phase C.

1. Wire both roots into the system trust list. In
   `hosts/common/default.nix` and `hosts/server-common/default.nix`,
   change:

   ```nix
   security.pki.certificateFiles = [
     ../../assets/certs/rootCA.pem
     ../../assets/certs/rootCA-next.pem
   ];
   ```

1. Apply this dual-trust change to every consumer first
   (`make apply-host` for each of `skaia`, `hive`, `meteor-1..4`).
   Do **not** swap the cluster's signing secret yet. After this
   step every host trusts both roots; the cluster is still signing
   with the old key.

1. Confirm both fingerprints are in the system trust on a consumer:

   ```sh
   ssh meteor-1.home.arpa '
     for f in /etc/ssl/certs/ca-certificates.crt; do
       awk "/BEGIN/{p=1;n++}p" "$f" \
         | csplit -z -s -b "-%02d.pem" -f /tmp/ca - "/-----END CERTIFICATE-----/+1" "{*}"
     done
     for c in /tmp/ca-*.pem; do
       openssl x509 -in "$c" -noout -subject -fingerprint -sha256 2>/dev/null \
         | grep -E "home-ca|mkcert" -A1 || true
     done
     rm -f /tmp/ca-*.pem
   '
   ```

   You should see two entries — the old `mkcert dlk@skaia` RSA root
   and the new `home-ca-YYYYMMDD` ECDSA root — with different
   fingerprints.

### Phase B — Swap signing key

1. Promote the new keypair to the active slot. On the workstation:

   ```sh
   mv secrets/home-ca.crt     secrets/home-ca.crt.prev
   mv secrets/home-ca.key     secrets/home-ca.key.prev
   mv secrets/home-ca.crt.new secrets/home-ca.crt
   mv secrets/home-ca.key.new secrets/home-ca.key
   git secret hide
   ```

   Update `.gitsecret/paths/mapping.cfg` / `.gitignore` so the
   `.new` entries are dropped and `.prev` entries are tracked
   (same dance as the harmonia runbook).

1. Replace the in-cluster CA secret. cert-manager won't reload it
   automatically; delete + recreate, then nudge the issuer:

   ```sh
   kubectl -n cert-manager delete secret home-ca-secret
   kubectl -n cert-manager create secret tls home-ca-secret \
     --cert=secrets/home-ca.crt \
     --key=secrets/home-ca.key
   kubectl -n cert-manager annotate clusterissuer home-ca \
     rotation/at="$(date -u +%FT%TZ)" --overwrite
   ```

1. Force re-issuance of every leaf certificate currently signed by
   the old CA. With only ~7 leaves (registry, monitoring/×3,
   argocd, argo-rollouts, argo-workflows) the delete-all strategy
   is simple, but **deleting the `Certificate.cert-manager.io`
   resource alone is not sufficient**: ingress-shim recreates the
   Certificate within a second or two, sees the existing (still-
   valid, just signed by the now-retired CA) leaf in the target
   `Secret`, and reports `Ready=True` without ever issuing a new
   CertificateRequest. You also need to delete the underlying
   `Secret` so cert-manager has to materialize a fresh one:

   ```sh
   # 1. delete the Certificate resources (ingress-shim will recreate)
   kubectl delete certificates.cert-manager.io -A --all
   # 2. delete the underlying leaf Secrets to force re-signing
   for nstls in <ns>/<name> ...; do
     ns=${nstls%/*}; name=${nstls#*/}
     kubectl -n "$ns" delete secret "$name"
   done
   # watch until all Certificates back to Ready=True (typically
   # 30-90s) and every target Secret has a fresh creationTimestamp
   kubectl get certificates.cert-manager.io -A -w
   ```

   At larger fleet sizes prefer `cmctl renew` (per-cert) or a
   batched annotation roll instead of mass-delete.

1. Verify a freshly-issued leaf cert chains to the new root:

   ```sh
   echo | openssl s_client -connect <ingress-host>:443 -servername <ingress-host> 2>/dev/null \
     | openssl x509 -noout -issuer -fingerprint -sha256
   ```

   The issuer fingerprint should match `assets/certs/rootCA-next.pem`.

### Phase C — Retire old root

After (a) every NixOS consumer has applied at least once after
Phase B and (b) every leaf certificate has been re-issued (no
`Certificate.cert-manager.io` resource still references the old
issuer fingerprint), retire the old root:

1. Rename so the new root takes the canonical slot:

   ```sh
   git mv assets/certs/rootCA.pem      assets/certs/rootCA.pem.old   # transient
   git mv assets/certs/rootCA-next.pem assets/certs/rootCA.pem
   rm   assets/certs/rootCA.pem.old
   ```

1. Restore the single-entry `security.pki.certificateFiles` in
   `hosts/common` and `hosts/server-common`.

1. Drop the `.prev` rollback artifacts:

   ```sh
   rm secrets/home-ca.crt.prev secrets/home-ca.key.prev
   # then edit .gitsecret/paths/mapping.cfg + .gitignore to remove
   # the .prev entries, and rm secrets/home-ca.*.prev.secret
   git secret hide
   ```

1. Apply to every consumer; commit.

## Rollback

During the dual-trust window, revert
`secrets/home-ca.{crt,key}` to the `.prev` files, re-hide, and
redo the in-cluster secret replacement. Consumers still trust the
old root during this window, so the rollback is transparent. After
Phase C the rollback path is gone — re-rotating becomes the
recovery posture.

## Out-of-band caveats

- Any `mkcert -install`'d device (browser/phone/laptop) still
  trusts only the old root until a fresh `mkcert -install` is run
  there. Track those manually.
- If clients pin certificate fingerprints (none currently known in
  this repo), update those pins before retiring the old root.

## Rotation history

| New root id        | Phase A              | Phase B              | Phase C (old retired) | Notes                                        |
|--------------------|----------------------|----------------------|-----------------------|----------------------------------------------|
| `home-ca-20260526` | 2026-05-26 (7bc8901) | 2026-05-26 (8b7e3d4) | 2026-05-30            | first rotation; ECDSA P-256/5y modernization |

Phase C was pulled in to 2026-05-30: every veil ingress leaf
(grafana, prometheus, argocd, …) was confirmed issued by the new
`CN=home-ca-20260526` ECDSA root via live `openssl s_client`
probes, all NixOS consumers had rebuilt 2026-05-26+ carrying the
dual-trust list, and the old `mkcert dlk@skaia` RSA root was
dropped from `security.pki.certificateFiles`. The `.prev` rollback
artifacts (`secrets/home-ca.{crt,key}.prev`) were removed. Any
out-of-band `mkcert -install`'d device still trusting only the old
root needs a fresh trust install — tracked separately.
