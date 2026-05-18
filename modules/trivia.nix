# Trivia drip-release file server.
#
# Serves a small set of files (PDFs, MP3s, etc.) for a trivia contest, with
# scheduled "drip" reveals. Each round lives in a subdirectory under
# `rootDir` named `<ISO-8601 local time>__<slug>`; the timestamp gates when
# the round becomes visible to clients, and the slug appears in URLs.
#
# Filesystem is the schedule: `mv 2026-06-07T19:00:00__r3 2026-06-07T19:10:00__r3`
# slips round 3 by ten minutes, no timer reload needed.
#
# Usage:
#   imports = [ ../../modules/trivia.nix ];
#   custom.trivia = {
#     enable = true;
#     # seedFixtures = true;   # write a test fixture set on first start
#   };
#
# This module starts the FastAPI app on 127.0.0.1:8765 inside a hardened
# systemd sandbox (see modules/hardened-service.nix). It does NOT define
# the public nginx vhost; wire that up in the host's nginx.nix to keep
# Basic Auth, rate limiting, and TLS concerns in one place.

{ config, lib, pkgs, ... }:

let
  inherit (import ./hardened-service.nix { inherit lib; }) mkServiceConfig;

  cfg = config.custom.trivia;

  appScript = pkgs.writeText "trivia-server.py"
    (builtins.readFile ../assets/trivia-server.py);

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.fastapi
    ps.uvicorn
  ]);

  # Idempotent fixture seeder. Creates a mix of well-formed rounds (some
  # in the deep past, some upcoming, one revealed +60s after deploy) and
  # intentionally invalid entries to exercise the parser's reject paths.
  # Operates as the `trivia` user so file ownership matches the service.
  fixtureScript = pkgs.writeShellScript "trivia-seed-fixtures" ''
    set -euo pipefail
    ROOT="${cfg.rootDir}"
    mkdir -p "$ROOT"
    cd "$ROOT"

    # Writes a minimal valid PDF (<300 bytes) with a recognisable title so
    # operators can byte-diff to confirm which fixture they got. Good enough
    # for a serving smoke test; not a real document.
    mkpdf() {
      local out="$1"; local title="$2"
      cat > "$out" <<EOF
    %PDF-1.4
    1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
    2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
    3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792]
       /Contents 4 0 R /Resources << >> >> endobj
    4 0 obj << /Length 44 >> stream
    BT /F1 24 Tf 100 700 Td ($title) Tj ET
    endstream endobj
    trailer << /Root 1 0 R /Size 5 >>
    %%EOF
    EOF
    }

    # 4 KB of zeros stamped as .mp3. Not playable; exercises Range and
    # Content-Type detection paths in FileResponse.
    mkmp3() {
      dd if=/dev/zero of="$1" bs=1024 count=4 status=none
    }

    # Idempotent guard. If the sentinel exists we leave the round alone so
    # this can run on every service start without clobbering edits.
    seeded() { [ -e "$1/.fixture" ]; }
    mark()   { touch "$1/.fixture"; }

    # ---- well-formed rounds ----

    # Long past: should always be revealed.
    DIR="2020-01-01T00:00:00__warmup"
    if ! seeded "$DIR"; then
      mkdir -p "$DIR"
      mkpdf "$DIR/welcome.pdf" "Welcome to Trivia"
      mkpdf "$DIR/rules.pdf"   "House Rules"
      mark "$DIR"
    fi

    # ~60 seconds in the future at deploy time. Lets you watch the drip live.
    SOON=$(date -d "+60 seconds" '+%Y-%m-%dT%H:%M:%S')
    DIR="''${SOON}__round-1"
    if ! seeded "$DIR"; then
      mkdir -p "$DIR"
      mkpdf "$DIR/questions.pdf" "Round 1 questions"
      mkmp3 "$DIR/audio-cue.mp3"
      mark "$DIR"
    fi

    # Far future: should never reveal during testing.
    DIR="2099-01-01T00:00:00__round-late"
    if ! seeded "$DIR"; then
      mkdir -p "$DIR"
      mkpdf "$DIR/questions.pdf" "Round Late questions"
      mark "$DIR"
    fi

    # ---- edge cases the parser must reject ----

    # Missing timestamp prefix.
    DIR="not-a-round"
    if ! seeded "$DIR"; then
      mkdir -p "$DIR"; mkpdf "$DIR/leak.pdf" "Should not be visible"; mark "$DIR"
    fi

    # Invalid date (month 13).
    DIR="2026-13-50T99:99:99__bad-time"
    if ! seeded "$DIR"; then
      mkdir -p "$DIR"; mkpdf "$DIR/leak.pdf" "Should not be visible"; mark "$DIR"
    fi

    # Slug fails SLUG_RE (uppercase letters).
    DIR="2026-01-01T00:00:00__BAD-CHARS-IN-SLUG"
    if ! seeded "$DIR"; then
      mkdir -p "$DIR"; mkpdf "$DIR/leak.pdf" "Should not be visible"; mark "$DIR"
    fi

    # A valid round, but with a dotfile inside; FILENAME_RE refuses to serve it.
    DIR="2020-02-02T00:00:00__has-dotfile"
    if ! seeded "$DIR"; then
      mkdir -p "$DIR"
      mkpdf "$DIR/visible.pdf" "Visible doc"
      printf 'secret\n' > "$DIR/.secret"
      mark "$DIR"
    fi

    # A valid round containing a symlink that escapes; round_file must reject.
    DIR="2020-03-03T00:00:00__has-escape"
    if ! seeded "$DIR"; then
      mkdir -p "$DIR"
      mkpdf "$DIR/legit.pdf" "Legit"
      ln -sfn /etc/passwd "$DIR/escape.txt"
      mark "$DIR"
    fi

    # A round dir that is itself a symlink to /etc; safe_round_dir must reject.
    if [ ! -L "2020-04-04T00:00:00__dir-is-symlink" ]; then
      ln -sfn /etc "2020-04-04T00:00:00__dir-is-symlink"
    fi

    # A loose file at the root; not a directory and should be ignored.
    : > "stray-file.txt"

    echo "trivia fixtures seeded under $ROOT"
  '';
in
{
  options.custom.trivia = {
    enable = lib.mkEnableOption "trivia drip-release file server";

    rootDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/trivia/rounds";
      description = ''
        Directory containing per-round subdirectories. Each subdirectory's
        name must match `<ISO-8601 local time>__<slug>`, e.g.
        `2026-06-07T19:00:00__round-1`. The slug appears in URL paths; the
        timestamp gates when the round is revealed to clients.
      '';
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the uvicorn server binds to.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8765;
      description = "Port the uvicorn server binds to.";
    };

    seedFixtures = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        If true, populate `rootDir` on first start with a fixture set that
        exercises both happy-path and edge-case behaviour (invalid names,
        dotfiles, escape-symlinks, etc.). Idempotent: existing entries
        marked with a `.fixture` sentinel are left alone, and any other
        existing rounds are untouched. Turn this off for the actual event.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # COLD START: drop the per-round content into `cfg.rootDir` (default
    # /var/lib/trivia/rounds) before the event. Each round is a directory
    # named `<ISO-8601 local time>__<slug>`. See docs/COLD-START.md for the
    # full operational walkthrough, including the htpasswd file used by the
    # nginx vhost. `custom.trivia.seedFixtures = true` writes a synthetic
    # round set for smoke-testing.
    users.users.trivia = {
      isSystemUser = true;
      group = "trivia";
      home = "/var/lib/trivia";
      description = "Trivia drip-release file server";
    };
    users.groups.trivia = { };

    systemd = {
      tmpfiles.rules = [
        "d /var/lib/trivia 0750 trivia trivia - -"
        "d ${cfg.rootDir}  0750 trivia trivia - -"
      ];

      services.trivia-seed-fixtures = lib.mkIf cfg.seedFixtures {
        description = "Seed trivia drip-release fixtures";
        wantedBy = [ "trivia.service" ];
        before = [ "trivia.service" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "trivia";
          Group = "trivia";
          ExecStart = "${fixtureScript}";
        };
      };

      services.trivia = {
        description = "Trivia drip-release file server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment = {
          TRIVIA_ROOT = cfg.rootDir;
          TRIVIA_HOST = cfg.listenAddress;
          TRIVIA_PORT = toString cfg.listenPort;
          PYTHONDONTWRITEBYTECODE = "1";
        };
        serviceConfig = (mkServiceConfig {
          readOnlyPaths = [ cfg.rootDir ];
          readWritePaths = [ ];
          allowOutbound = false;
        }) // {
          Type = "exec";
          User = "trivia";
          Group = "trivia";
          ExecStart = "${pythonEnv}/bin/python ${appScript}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };
  };
}
