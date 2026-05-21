# Harmonia Binary Cache Signing Key Rotation

Rotate the Harmonia signing key periodically (hygiene) or when it
has been exposed to a host that should no longer be trusted with
it. The procedure uses a transitional dual-trust window so that
consumers (`meteor-1..4`, `hive`, the workstation) keep accepting
cached paths signed with the old key until the new key has
propagated everywhere.

Initial generation of the signing key is documented in
`docs/COLD-START.md` § 18. Service definition is in
`modules/harmonia.nix`.

## Steps

1. Generate the new keypair alongside the old one. Date-suffix the
   key name so both can coexist in `trusted-public-keys` and so the
   signing key on a given `.narinfo` is self-identifying:

   ```sh
   nix-store --generate-binary-cache-key cache.home.arpa-$(date +%Y%m%d) \
     secrets/harmonia-cache-private-key.new \
     assets/harmonia-cache-public-key-next.txt
   ```

1. Add the new public key as a second entry in `trusted-public-keys`
   in `hosts/server-common/default.nix` alongside the existing one:

   ```nix
   trusted-public-keys = [
     (lib.strings.removeSuffix "\n" (builtins.readFile ../../assets/harmonia-cache-public-key.txt))
     (lib.strings.removeSuffix "\n" (builtins.readFile ../../assets/harmonia-cache-public-key-next.txt))
     "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
   ];
   ```

1. Apply this dual-trust change to every consumer first
   (`make apply-host` for each of `hive`, `meteor-1..4`, the
   workstation, etc.). Do **not** swap the skaia private key yet.
   After this step every consumer trusts both keys, but skaia is
   still signing with the old one.

1. Confirm the new key is in the trust list on a consumer:

   ```sh
   nix show-config | grep trusted-public-keys
   ```

1. Swap the active signing key on `skaia`:

   ```sh
   mv secrets/harmonia-cache-private-key      secrets/harmonia-cache-private-key.prev
   mv secrets/harmonia-cache-private-key.new  secrets/harmonia-cache-private-key
   git secret hide
   make apply-host HOST=skaia
   sudo systemctl restart harmonia.service
   ```

   Harmonia now signs new responses with the new key. Cached
   responses already signed with the old key remain valid on
   consumers because both public keys are still trusted.

1. Verify a fresh signature on a never-before-served path:

   ```sh
   curl -s http://cache.home.arpa/<store-hash>.narinfo | grep ^Sig:
   ```

   The signature prefix should be `cache.home.arpa-YYYYMMDD:...`.

1. After at least one full rebuild cycle on every consumer (so any
   path signed with the old key has either been re-served or
   garbage-collected), retire the old key:

   - Replace `assets/harmonia-cache-public-key.txt` with the contents
     of `assets/harmonia-cache-public-key-next.txt`.
   - Delete `assets/harmonia-cache-public-key-next.txt`.
   - Remove the second `builtins.readFile` entry from
     `trusted-public-keys` in `hosts/server-common/default.nix`.
   - `rm secrets/harmonia-cache-private-key.prev` and
     `secrets/harmonia-cache-private-key.prev.secret`.
   - Re-run `git secret hide` and apply to every consumer to drop
     the now-unused trust entry.

1. Commit:

   ```sh
   git add assets/harmonia-cache-public-key.txt \
           secrets/harmonia-cache-private-key.secret \
           hosts/server-common/default.nix
   git commit -m "config: rotate harmonia binary cache signing key"
   ```

## Rollback

During the dual-trust window, revert `secrets/harmonia-cache-private-key`
to the `.prev` file and re-apply skaia. Consumers still trust the old
key during this window, so the rollback is transparent.
