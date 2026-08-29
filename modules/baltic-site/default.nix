# Publishes the-baltic-approaches static page to the valueof.info docroot.
#
# The book repo owns the page, its build, and the test suite that gates a
# deploy; this module owns fetching, building, and swapping the result in.
# The division of responsibility is written down in that repo's
# planning/site-handoff.md, which this implements.
#
# Shape: a timer resolves the tip of the book repo's release branch, and on
# a new revision builds site-flake/ against exactly that revision. The build
# runs `make test` (the deploy gate) and `make site` inside a Nix build
# sandbox, so a broken commit fails the build and the previously published
# revision keeps being served untouched.
#
# This module does NOT define the public vhost; the page is a path under the
# existing valueof.info server block in hosts/skaia/nginx.nix, following the
# same split used by modules/trivia.nix.
#
# Failing safe is silent by construction, so the `baltic-site.rules` group in
# modules/prometheus-rules.nix alerts on both a failing deploy and a timer
# that has stopped firing.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.balticSite;

  inherit (import ../hardened-service.nix { inherit lib; }) mkServiceConfig;

  # Evaluated from the flake, so this lands in the store with the system
  # closure. The deploy unit never reads it out of a mutable checkout.
  siteFlake = ./site-flake;

  deploy = pkgs.writeShellApplication {
    name = "baltic-site-deploy";
    runtimeInputs = with pkgs; [
      git
      nix
      coreutils
      findutils
    ];
    text = ''
      state="${cfg.stateDir}"
      link="${cfg.docRoot}"
      storeLink="$state/.build"
      revStamp="$state/deployed-rev"
      hashStamp="$state/published-hash"

      rev="$(git ls-remote "${cfg.gitUrl}" "refs/heads/${cfg.branch}" | cut -f1)"
      if [ -z "$rev" ]; then
        echo "could not resolve ${cfg.branch} at ${cfg.gitUrl}" >&2
        exit 1
      fi

      # Most commits on the branch are record-keeping. Short-circuit on an
      # unchanged revision rather than re-evaluating the book's flake every
      # interval.
      if [ "$rev" = "$(cat "$revStamp" 2>/dev/null || true)" ] && [ -e "$link" ]; then
        echo "already serving ''${rev:0:7}"
        exit 0
      fi

      echo "building ''${rev:0:7}"

      # --out-link is both the build and the safety net: nix writes the link
      # only after a successful build and registers it as an indirect GC
      # root, so the result survives nix-collect-garbage. A failing `make
      # test` fails the build here and leaves everything below untouched,
      # which is how a broken commit keeps off the site.
      nix build \
        --extra-experimental-features "nix-command flakes" \
        --no-write-lock-file \
        --override-input baltic "${cfg.flakeRef}/$rev" \
        --out-link "$storeLink" \
        "${siteFlake}#site"

      built="$(readlink -f "$storeLink")"

      # The build is deterministic, so most new revisions produce output
      # identical to what is already published. Republishing those would
      # churn mtimes and needlessly invalidate reader caches.
      #
      # Compare content rather than the store path. The derivation takes the
      # checkout as its source, so its path is a function of the revision and
      # changes on every commit even when the output bytes do not -- comparing
      # paths here made this branch unreachable, and a docs-only commit
      # invalidated every reader's cache. The NAR hash comes from the store's
      # own database, so it costs a lookup rather than a re-read of the tree.
      builtHash="$(nix-store --query --hash "$built")"
      if [ "$builtHash" = "$(cat "$hashStamp" 2>/dev/null || true)" ] && [ -e "$link" ]; then
        echo "$rev" > "$revStamp"
        echo "''${rev:0:7} rebuilt to the published output; nothing to swap"
        exit 0
      fi

      # Publish a copy rather than pointing the server at the store path.
      # Everything in the store has mtime epoch+1, which would leave every
      # response claiming Last-Modified 1970 and an ETag keyed only on file
      # size -- so a byte-length-preserving errata fix would never reach a
      # reader holding a cached copy. A copy carries real mtimes and makes
      # ordinary validator behaviour correct.
      release="$state/releases/$(basename "$built")"
      rm -rf "$release.tmp"
      mkdir -p "$state/releases"
      cp -rL --no-preserve=timestamps "$built" "$release.tmp"
      chmod -R u+w,a+rX "$release.tmp"
      rm -rf "$release"
      mv -T "$release.tmp" "$release"

      # rename(2) over the existing symlink, so a request either sees the
      # whole old release or the whole new one.
      ln -sfn "$release" "$link.tmp"
      mv -T "$link.tmp" "$link"

      echo "$builtHash" > "$hashStamp"
      echo "$rev" > "$revStamp"

      # Keep the previous release alongside the current one, so a request
      # that resolved the old path microseconds before the swap can still
      # open its files.
      find "$state/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
        | sort -rn | tail -n +3 | cut -d' ' -f2- \
        | while read -r old; do rm -rf "$old"; done

      echo "serving ''${rev:0:7} from $built"
    '';
  };
in
{
  options.custom.balticSite = {
    enable = lib.mkEnableOption "the-baltic-approaches static site deployment";

    gitUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/othercriteria/the-baltic-approaches.git";
      description = ''
        Git URL used to resolve the branch tip. Plain HTTPS: the site build
        needs no LFS objects and no credentials, so an anonymous clone is
        enough.
      '';
    };

    flakeRef = lib.mkOption {
      type = lib.types.str;
      default = "github:othercriteria/the-baltic-approaches";
      description = ''
        Flake reference for the same repository, without a revision. The
        deploy script appends the resolved commit so the build is pinned to
        exactly the revision that was inspected.
      '';
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch whose tip is published.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15m";
      description = ''
        How often to check for new commits. Mapped to an OnCalendar
        expression (15m, 30m, or 1h). The page has no freshness
        requirement tighter than "soon after an errata lands".
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/baltic-site";
      readOnly = true;
      description = "Where the published symlink and revision stamp live.";
    };

    docRoot = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.stateDir}/current";
      readOnly = true;
      description = ''
        Symlink to the published release directory. Point the web server at
        this rather than hardcoding the path; it is swapped atomically and
        only ever points at a complete, tested build.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.baltic-site = {
      isSystemUser = true;
      group = "baltic-site";
      home = cfg.stateDir;
      description = "the-baltic-approaches site deployment";
    };
    users.groups.baltic-site = { };

    systemd.services.baltic-site-deploy = {
      description = "Build and publish the-baltic-approaches static site";
      after = [
        "network-online.target"
        "nix-daemon.socket"
      ];
      wants = [ "network-online.target" ];

      serviceConfig =
        (mkServiceConfig {
          # Reaches GitHub for the source and the substituters for the
          # toolchain, so the loopback-only default does not apply.
          allowOutbound = true;
          # Nix's client mmaps writable+executable while evaluating.
          memoryDenyWriteExecute = false;
        })
        // {
          Type = "oneshot";
          User = "baltic-site";
          Group = "baltic-site";
          ExecStart = lib.getExe deploy;

          # 0755 so the nginx worker can traverse to the published symlink.
          StateDirectory = "baltic-site";
          StateDirectoryMode = "0755";

          Environment = [
            "HOME=${cfg.stateDir}"
            "XDG_CACHE_HOME=${cfg.stateDir}/.cache"
            "NIX_REMOTE=daemon"
            "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
          ];

          # A first build renders the cover through xelatex and can take a
          # couple of minutes cold; well short of this.
          TimeoutStartSec = "30min";
        };
    };

    systemd.timers.baltic-site-deploy = {
      description = "Check for new the-baltic-approaches commits";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # System timers treat OnStartupSec like OnBootSec (time since
        # PID 1), so a restart after boot cannot re-arm it. OnCalendar
        # always has a next wall-clock elapse; OnActiveSec covers the
        # first run after the timer unit itself starts (boot, switch,
        # or systemctl restart).
        OnActiveSec = "5m";
        OnCalendar =
          {
            "15m" = "*:0/15";
            "30m" = "*:0/30";
            "1h" = "hourly";
          }
          .${cfg.interval}
            or (throw "custom.balticSite.interval '${cfg.interval}' has no OnCalendar mapping");
        # Spread the GitHub poll so it doesn't land on the minute boundary
        # alongside every other timer on the host.
        RandomizedDelaySec = "2m";
        Persistent = true;
      };
    };
  };
}
