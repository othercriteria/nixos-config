# Prometheus ZFS snapshot automation module
#
# Sets up a systemd service and timer to snapshot the ZFS dataset for Prometheus
# (default: /zfs/prometheus) every hour and prune snapshots older than 7 days.
#
# Usage:
#   Import this module and set the dataset if needed:
#     services.prometheusZfsSnapshot.dataset = "/zfs/prometheus";

{ config, lib, pkgs, ... }:

let
  inherit (config.services.prometheusZfsSnapshot) dataset;
  snapshotName = "auto-$(date +%Y-%m-%d-%H%M)";
  pruneDays = toString config.services.prometheusZfsSnapshot.retentionDays;
  snapshotScript = pkgs.writeShellScript "prometheus-zfs-snapshot.sh" ''
    set -e
    zfs snapshot ${dataset}@auto-$(date +%Y-%m-%d-%H%M)
    # Prune old snapshots
    cutoff=$(date -d "-${pruneDays} days" +%s)
    zfs list -H -t snapshot -o name -s creation ${dataset} | \
      while IFS= read -r snap; do
        case "$snap" in
          ${dataset}@auto-*)
            snapdate=''${snap##*@auto-}
            # Convert auto-YYYY-MM-DD-HHMM to a format GNU date parses.
            snapdate_fmt=$(printf '%s\n' "$snapdate" | \
              sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2})([0-9]{2})$/\1 \2:\3/')
            snapts=$(date -d "$snapdate_fmt" +%s 2>/dev/null || true)
            if [ -n "$snapts" ] && [ "$snapts" -lt "$cutoff" ]; then
              zfs destroy "$snap"
            fi
            ;;
        esac
      done
  '';

in
{
  options.services.prometheusZfsSnapshot = {
    enable = lib.mkEnableOption "Prometheus ZFS snapshot automation";
    dataset = lib.mkOption {
      type = lib.types.str;
      default = null;
      example = "fastdisk/prometheus";
      description = ''
        ZFS dataset to snapshot (e.g., "fastdisk/prometheus").
        This must be set explicitly in your host configuration.
      '';
    };
    retentionDays = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "How many days of snapshots to keep.";
    };
  };

  config = lib.mkIf config.services.prometheusZfsSnapshot.enable {
    assertions = [
      {
        assertion = config.services.prometheusZfsSnapshot.dataset != null;
        message = "services.prometheusZfsSnapshot.dataset must be set to the ZFS dataset name (e.g., fastdisk/prometheus).";
      }
    ];
    systemd.services.prometheus-zfs-snapshot = {
      description = "Prometheus ZFS snapshot";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${snapshotScript}";
      };
      path = [ pkgs.zfs ];
    };
    systemd.timers.prometheus-zfs-snapshot = {
      description = "Prometheus ZFS snapshot timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };
  };
}
