# Urbit ship service for ~taptev-donwyx
#
# SAFETY: Running multiple instances of the same Urbit ship simultaneously
# can cause identity breach and require a factory reset. This service includes
# multiple safeguards:
#
# 1. systemd's native instance tracking (won't start if already running)
# 2. flock-based pier directory locking
# 3. Pre-start check for any existing urbit processes
# 4. LMDB's internal file locking (last resort)
#
# UPGRADE WORKFLOW:
# 1. Stop the service: sudo systemctl stop urbit-taptev-donwyx
# 2. Verify stopped: pgrep -f taptev-donwyx (should return nothing)
# 3. Run upgrade commands manually as dlk user:
#      cd /home/dlk/workspace/urbit/taptev-donwyx
#      ./.run next taptev-donwyx        # check for runtime updates (downloads new .run)
#      ./.run pack taptev-donwyx        # compact pier (optional, fast)
#      ./.run meld taptev-donwyx        # compact state (optional, RAM-heavy)
# 4. Start the service: sudo systemctl start urbit-taptev-donwyx
# 5. Monitor: journalctl -u urbit-taptev-donwyx -f
#
# MANUAL DOJO ACCESS:
#   When the service is running, you cannot get a Dojo terminal directly.
#   Options:
#   a) Use the web UI at http://hive.home.arpa:8080/
#   b) Stop the service, run interactively: cd $pierPath && ./.run taptev-donwyx
#   c) Use hood commands via HTTP (advanced)

{ config, lib, pkgs, ... }:

let
  # The pier directory contains .run (runtime) and the ship data in .urb/
  # Urbit expects to be run from the PARENT of the pier with the pier name as argument
  urbitBase = "/home/dlk/workspace/urbit";
  pierName = "taptev-donwyx";
  pierPath = "${urbitBase}/${pierName}";

  # Pre-start safety script: refuse to start if another instance is detected
  preStartScript = pkgs.writeShellScript "urbit-prestart-check" ''
    set -euo pipefail

    PIER_PATH="${pierPath}"
    PIER_NAME="${pierName}"

    echo "Urbit pre-start safety check for ~$PIER_NAME"

    # Check 1: Look for any running urbit processes for this pier
    if ${pkgs.procps}/bin/pgrep -f "$PIER_PATH" > /dev/null 2>&1; then
      echo "ERROR: Found existing process matching pier path!"
      echo "Running processes:"
      ${pkgs.procps}/bin/pgrep -af "$PIER_PATH" || true
      echo ""
      echo "Refusing to start. Kill existing process first or investigate."
      exit 1
    fi

    # Check 2: Verify pier directory exists and is accessible
    if [ ! -d "$PIER_PATH" ]; then
      echo "ERROR: Pier directory does not exist: $PIER_PATH"
      exit 1
    fi

    if [ ! -f "$PIER_PATH/.run" ]; then
      echo "ERROR: Urbit runtime not found at $PIER_PATH/.run"
      exit 1
    fi

    echo "Pre-start checks passed. Proceeding to start Urbit."
  '';

  # Wrapper script with flock for extra safety
  startScript = pkgs.writeShellScript "urbit-start" ''
    set -euo pipefail

    URBIT_BASE="${urbitBase}"
    PIER_NAME="${pierName}"
    PIER_PATH="${pierPath}"
    LOCK_FILE="$PIER_PATH/.service.lock"

    # Acquire exclusive lock on pier directory (will fail if another instance holds it)
    exec 200>"$LOCK_FILE"
    if ! ${pkgs.flock}/bin/flock -n 200; then
      echo "ERROR: Could not acquire lock on $LOCK_FILE"
      echo "Another instance may be running. Refusing to start."
      exit 1
    fi

    echo "Lock acquired. Starting Urbit ship ~$PIER_NAME..."

    # Start urbit in foreground (systemd manages the process)
    # Urbit expects: ./pier/.run pier_name (run from parent of pier directory)
    # -t = no TTY (suitable for service, no interactive prompts)
    # --loom 31 = 2GB memory arena (default, can increase if needed)
    # Note: Do NOT use -d (daemon mode) as systemd handles daemonization
    cd "$URBIT_BASE"
    exec ./$PIER_NAME/.run $PIER_NAME -t --loom 31
  '';
in
{
  # System service running as dlk user
  systemd.services.urbit-taptev-donwyx = {
    description = "Urbit ship ~taptev-donwyx";
    documentation = [ "https://docs.urbit.org" ];

    # Start after network is available
    after = [ "network.target" "local-fs.target" ];
    wants = [ "network.target" ];

    # Start automatically on boot
    wantedBy = [ "multi-user.target" ];

    # Rate limiting: max 3 restarts in 5 minutes (must be in [Unit] section)
    startLimitIntervalSec = 300;
    startLimitBurst = 3;

    serviceConfig = {
      Type = "simple";
      User = "dlk";
      Group = "users";
      WorkingDirectory = urbitBase;

      # Safety: pre-start check for existing instances
      ExecStartPre = "${preStartScript}";

      # Main execution with flock wrapper
      ExecStart = "${startScript}";

      # Graceful shutdown: send SIGINT (like Ctrl+C in Dojo)
      # Urbit handles this by saving state and exiting cleanly
      ExecStop = "${pkgs.coreutils}/bin/kill -INT $MAINPID";
      KillSignal = "SIGINT";
      TimeoutStopSec = 120; # Give Urbit time to save state

      # Restart policy: restart on failure, but not too aggressively
      Restart = "on-failure";
      RestartSec = 30; # Wait 30s before restart to avoid rapid cycling

      # Resource limits
      LimitNOFILE = 65536;
      MemoryMax = "48G"; # Urbit with loom 31 can use significant RAM

      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "urbit-taptev-donwyx";

      # Security hardening (compatible with urbit's needs)
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      # Allow write access to the pier directory
      ReadWritePaths = [ pierPath ];
      PrivateTmp = true;
    };
  };

  # Helper: stop service before system shutdown/reboot
  # This ensures clean Urbit shutdown even during system maintenance
  systemd.services.urbit-taptev-donwyx-stop = {
    description = "Ensure Urbit stops cleanly before shutdown";
    before = [ "shutdown.target" "reboot.target" "halt.target" ];
    wantedBy = [ "shutdown.target" "reboot.target" "halt.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = "${pkgs.systemd}/bin/systemctl stop urbit-taptev-donwyx.service || true";
    };
  };
}
