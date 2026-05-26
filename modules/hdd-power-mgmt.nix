# Override aggressive HDD APM (head-parking) defaults
#
# Many consumer HDDs ship with APM level 128, which parks the heads after
# only a few seconds of idle. On a 24/7 server this can rack up hundreds of
# thousands of load cycles per year, far exceeding the drive's rated load-
# cycle budget (typically 300-600k). The drive's read/write performance is
# also briefly affected on every wake.
#
# This module sets APM to 254 (performance, no idle parking) on the named
# disks at boot. APM=255 (entirely disable) is also valid but is silently
# clamped to 254 by some controller firmwares; 254 is the well-supported
# "loud" setting.
#
# Setting APM has no effect on SSDs (they have no heads to park) but is also
# harmless. We still reference disks by stable /dev/disk/by-id paths so the
# config can't accidentally target the wrong device after a SATA reshuffle.
#
# Caveat: Western Digital Green/Red firmware does not implement standard ATA
# APM at all. `hdparm -B 254` will appear to succeed but a subsequent query
# returns `APM_level = not supported`. The actual idle-park timer on those
# drives is the proprietary "IntelliPark" feature, manageable only via
# vendor-specific commands (`idle3-tools` / `hdparm -J`) that require a full
# power cycle to take effect -- not viable for a remote 24/7 server. If you
# need to suppress IntelliPark on a remote WD drive, the realistic option is
# a small periodic-read daemon (parkverbot-style) that resets the firmware's
# inactivity timer non-destructively. This module does not yet ship that.
#
# Background: hive's pair of HDDs accumulated 397k+ load cycles over 8 years
# of 24/7 service before we noticed; sda is in a similar lineage. The damage
# already done isn't reversible, but this stops it from getting worse and
# is documented in docs/COLD-START.md as a default we want everywhere we
# run spinning disks.
{ config, lib, pkgs, ... }:

let
  cfg = config.custom.hddPowerMgmt;
in
{
  options.custom.hddPowerMgmt = {
    enable = lib.mkEnableOption "Override aggressive HDD power management";

    disks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ata-WDC_WD30EZRX-00MMMB0_WD-WCAWZ2644073" ];
      description = ''
        List of disk identifiers under /dev/disk/by-id/, without the
        leading directory. Each entry should resolve to a real block
        device at activation time; missing entries warn but do not fail.
      '';
    };

    apmLevel = lib.mkOption {
      type = lib.types.ints.between 1 254;
      default = 254;
      description = ''
        APM level to set via hdparm -B. 1=most aggressive idle parking,
        128=common factory default (aggressive on servers), 254=performance
        with no idle parking. Values above 127 disable spindown entirely.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.hdd-power-mgmt = {
      description = "Reduce aggressive HDD head-parking via hdparm APM";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      path = [ pkgs.hdparm ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        rc=0
        for d in ${lib.concatMapStringsSep " " (x: "/dev/disk/by-id/${x}") cfg.disks}; do
          if [ -e "$d" ]; then
            echo "Setting APM=${toString cfg.apmLevel} on $d"
            hdparm -B ${toString cfg.apmLevel} "$d" || rc=1
          else
            echo "WARN: $d not present at activation; skipping" >&2
          fi
        done
        exit $rc
      '';
    };
  };
}
