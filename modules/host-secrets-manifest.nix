# Per-host secrets allowlist enforcement.
#
# Background:
#
# The deploy path (`make sync-to-system` in the workspace Makefile)
# rsyncs the entire decrypted `secrets/` directory from the workspace
# into `/etc/nixos/secrets/` on the target host, modulo `*.secret`. That
# gives every host on-disk access to every plaintext secret in the repo.
# Fine for `skaia` where most services live, but substantially overshares
# for hosts like the veil meteors that only need a small subset (k3s
# join token, per-host Teleport token).
#
# What this module does:
#
# At every system activation (which is what `nixos-rebuild switch` ends
# with, and what `make apply-host` invokes after rsync), prune the
# secrets directory down to a declared per-host allowlist. Anything not
# on the allowlist is removed. Encrypted `*.secret` files are always
# preserved — they're encrypted to the operator's GPG key, and they may
# be present in a workspace checkout colocated under /etc/nixos/.
#
# Threat model addressed:
#
# - A service compromise (or a misconfigured service running as a
#   different user) can only read the subset of secrets the host's
#   manifest declares.
# - An attacker with filesystem read on a meteor finds only veil-
#   relevant secrets, not skaia's signing keys, OAuth tokens, etc.
#
# Threat model NOT addressed:
#
# - The workspace checkout on a host may still hold `.secret` files
#   alongside the operator's GPG private key (per docs/COLD-START.md
#   section 0). A full host compromise can still decrypt all secrets
#   via the operator's key. Closing that gap is a separate, larger
#   refactor (e.g. deploying secrets from a single trusted host
#   instead of decrypting on each host).
#
# Usage:
#
#   { ... }:
#   {
#     custom.hostSecretsManifest = {
#       enable = true;
#       allowed = [
#         "veil-k3s-token"
#         "teleport/meteor-2.token"
#       ];
#     };
#   }
#
# Paths are relative to `secretsDir` (default /etc/nixos/secrets) and
# may include subdirectories. Allowed entries that do not exist on
# disk are simply allowed-when-they-show-up; the scrub is delete-only.

{ config, lib, pkgs, ... }:

let
  cfg = config.custom.hostSecretsManifest;

  manifestFile = pkgs.writeText "host-secrets-allowlist.txt"
    (lib.concatStringsSep "\n" (lib.sort (a: b: a < b) cfg.allowed) + "\n");

  scrubScript = pkgs.writeShellApplication {
    name = "scrub-host-secrets";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils ];
    text = ''
      set -euo pipefail

      SECRETS_DIR=''${1:-/etc/nixos/secrets}
      MANIFEST=''${2:-/etc/host-secrets-allowlist.txt}

      if [ ! -d "$SECRETS_DIR" ]; then
        exit 0
      fi
      if [ ! -f "$MANIFEST" ]; then
        echo "scrub-host-secrets: manifest not found at $MANIFEST; skipping" >&2
        exit 0
      fi

      declare -A allowed
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        allowed["$line"]=1
      done < "$MANIFEST"

      removed=0
      while IFS= read -r -d "" f; do
        rel=''${f#"$SECRETS_DIR"/}
        case "$rel" in
          *.secret) continue ;;
        esac
        if [ -z "''${allowed[$rel]:-}" ]; then
          rm -f -- "$f"
          echo "scrub-host-secrets: removed $rel"
          removed=$((removed + 1))
        fi
      done < <(find "$SECRETS_DIR" -type f -print0)

      find "$SECRETS_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true

      if [ "$removed" -gt 0 ]; then
        echo "scrub-host-secrets: pruned $removed file(s) not on allowlist"
      fi
    '';
  };
in
{
  options.custom.hostSecretsManifest = {
    enable = lib.mkEnableOption "per-host secrets allowlist enforcement";

    allowed = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "veil-k3s-token" "teleport/meteor-1.token" ];
      description = ''
        Relative paths under `secretsDir` that this host is allowed to
        keep on disk after activation. Files present in `secretsDir`
        whose relative path is not on this list are deleted during
        system activation. Encrypted `*.secret` files are always
        preserved.
      '';
    };

    secretsDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/secrets";
      description = "Directory containing deployed plaintext secrets.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."host-secrets-allowlist.txt" = {
      source = manifestFile;
      mode = "0444";
    };

    # Run as part of activation so every `nixos-rebuild switch` (which is
    # what `make apply-host` ends with) prunes whatever the preceding
    # rsync just dropped into /etc/nixos/secrets/. `etc` is the standard
    # NixOS activation step that installs files into /etc; depending on
    # it guarantees the manifest is in place before the scrub runs.
    system.activationScripts.scrub-host-secrets = {
      deps = [ "etc" ];
      text = ''
        ${scrubScript}/bin/scrub-host-secrets "${cfg.secretsDir}" \
          /etc/host-secrets-allowlist.txt || true
      '';
    };
  };
}
