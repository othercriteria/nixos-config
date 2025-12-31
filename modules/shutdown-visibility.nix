# Shutdown visibility module
#
# Provides persistent journal storage and shutdown reason logging
# to help diagnose unexpected shutdowns and crashes.
#
# Usage:
#   imports = [ ../../modules/shutdown-visibility.nix ];
#   custom.shutdownVisibility.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.custom.shutdownVisibility;
in
{
  options.custom.shutdownVisibility = {
    enable = lib.mkEnableOption "shutdown visibility (persistent journal + shutdown logging)";

    journalMaxSize = lib.mkOption {
      type = lib.types.str;
      default = "500M";
      description = "Maximum disk space for persistent journal storage.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistent journal storage - survives reboots
    services.journald.extraConfig = ''
      Storage=persistent
      SystemMaxUse=${cfg.journalMaxSize}
    '';

    systemd = {
      # Ensure journal directory exists with correct permissions
      tmpfiles.rules = [
        "d /var/log/journal 2755 root systemd-journal -"
      ];

      services = {
        # Log shutdown events to a dedicated file
        log-shutdown-reason = {
          description = "Log shutdown/reboot reason";
          wantedBy = [ "halt.target" "poweroff.target" "reboot.target" "kexec.target" ];
          before = [ "halt.target" "poweroff.target" "reboot.target" "kexec.target" ];
          # Don't block shutdown if this fails
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStop = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/date \"+%Y-%m-%d %H:%M:%S - Shutdown initiated (target: $JOURNAL_TARGET)\" >> /var/log/shutdown-reasons.log'";
          };
          # Capture which target triggered the shutdown
          environment.JOURNAL_TARGET = "%i";
        };

        # Also log unexpected shutdowns by checking last boot
        log-boot-check = {
          description = "Check for unexpected shutdown on boot";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-journald.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "check-last-shutdown" ''
              set -euo pipefail
              LOG="/var/log/shutdown-reasons.log"

              # Get last shutdown type from previous boot journal
              LAST_SHUTDOWN=$(${pkgs.systemd}/bin/journalctl -b -1 --output=cat \
                -u systemd-shutdown.service 2>/dev/null | tail -1 || echo "unknown")

              # Check if previous boot ended cleanly
              CLEAN_SHUTDOWN=$(${pkgs.systemd}/bin/journalctl -b -1 \
                -u halt.target -u poweroff.target -u reboot.target \
                --output=cat 2>/dev/null | grep -c "Reached target" || echo "0")

              BOOT_TIME=$(${pkgs.coreutils}/bin/date "+%Y-%m-%d %H:%M:%S")

              if [ "$CLEAN_SHUTDOWN" = "0" ]; then
                echo "$BOOT_TIME - BOOT after possible unclean shutdown (last: $LAST_SHUTDOWN)" >> "$LOG"
              else
                echo "$BOOT_TIME - BOOT after clean shutdown" >> "$LOG"
              fi

              # Keep log file from growing indefinitely
              if [ -f "$LOG" ]; then
                ${pkgs.coreutils}/bin/tail -100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
              fi
            '';
          };
        };
      };
    };
  };
}
