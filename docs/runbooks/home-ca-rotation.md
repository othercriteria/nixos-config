# Home CA Rotation

Rotate the `home-ca` certificate authority that signs TLS for the
veil cluster's internal ingresses. Like the
[harmonia binary cache rotation][harmonia], this uses a transitional
dual-trust window so every NixOS host accepts both the retiring and
the incoming root while leaf certificates are re-issued.

Initial generation is documented in `docs/COLD-START.md` § 11.

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

1. Generate the new CA keypair alongside the old one. Use mkcert to
   match the existing cert's metadata style; date-suffix the file
   names so both can coexist on disk:

   ```sh
   CAROOT=$(mktemp -d) mkcert -install   # generates new root in $CAROOT
   # mkcert prints the path; copy the cert and key into the repo
   cp "$CAROOT/rootCA.pem" assets/certs/rootCA-next.pem
   cp "$CAROOT/rootCA-key.pem" secrets/home-ca.key.new
   cp "$CAROOT/rootCA.pem"     secrets/home-ca.crt.new
   ```

   Alternative without mkcert (pure openssl) is fine but loses the
   subject styling consistency.

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
     ls -l /etc/static/ssl/certs/ca-certificates.crt
     awk -v RS= "/BEGIN CERTIFICATE/" /etc/static/ssl/certs/ca-certificates.crt \
       | nix shell nixpkgs#openssl -c sh -c "while read -r line; do echo \"\$line\" | openssl x509 -noout -subject -fingerprint -sha256 2>/dev/null; done" \
       | grep mkcert
   ' || true
   ```

   You should see two `mkcert ...` entries with different
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
   the old CA. The cleanest option is to delete the
   `Certificate.cert-manager.io` resources and let the controllers
   reconcile fresh requests:

   ```sh
   kubectl get certificates.cert-manager.io -A
   # for each leaf you want to roll, e.g.:
   kubectl -n <ns> delete certificate <name>
   ```

   Or, less invasive: annotate each certificate with
   `cert-manager.io/issue-temporary-certificate=true` and bump the
   renewal window. Pick the strategy that matches your fleet size.

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

| New root id  | Phase A     | Phase B     | Phase C due | Notes                                          |
|--------------|-------------|-------------|-------------|------------------------------------------------|
| _(none yet)_ | _(pending)_ | _(pending)_ | _(pending)_ | first rotation since stand-up; hygiene trigger |
