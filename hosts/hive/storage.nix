{ config, lib, pkgs, ... }:

{
  # Additional storage mounts for hive
  # These are spinning disks and SSDs for bulk storage

  fileSystems = {
    # 1.8TB SSD - bulk fast storage
    "/ssd" = {
      device = "/dev/disk/by-label/BULK";
      fsType = "ext4";
      options = [ "noatime" ];
    };

    # 1.9TB HDD partition - general storage
    "/storage" = {
      device = "/dev/disk/by-label/STORAGE";
      fsType = "ext4";
    };

    # 841GB HDD partition - projects/workspaces
    "/projects" = {
      device = "/dev/disk/by-label/PROJECTS";
      fsType = "ext4";
    };

    # 1.8TB MX500 SATA SSD - added 2026-05 alongside the system NVMe swap.
    # Intended as a flexible local "wagon" -- pier mirror, scratch, future
    # backup target, etc. Not encrypted (matches BULK/STORAGE/PROJECTS).
    # COLD START: provision the label with
    #   sudo sgdisk --zap-all /dev/sdd
    #   sudo sgdisk -n 1:0:0 -t 1:8300 -c 1:"WAGON" /dev/sdd
    #   sudo partprobe /dev/sdd
    #   sudo mkfs.ext4 -L WAGON /dev/sdd1
    "/wagon" = {
      device = "/dev/disk/by-label/WAGON";
      fsType = "ext4";
      options = [ "noatime" ];
    };

    # 1.8TB Seagate ST2000DM006 7200rpm HDD - recycled in 2026-05 from a
    # defunct Windows install. Drive has ~8y of 24/7 power-on hours and
    # 397k+ load cycles (well past rated budget) but zero reallocations,
    # zero pending sectors, and clean SMART error logs. Treat /attic as
    # a no-durability scratch slot: anything important here has to live
    # somewhere else too. When the drive eventually dies, drop this
    # entry; smartd will alert on the way down.
    # COLD START: provision the label with
    #   sudo sgdisk --zap-all /dev/sdb
    #   sudo sgdisk -n 1:0:0 -t 1:8300 -c 1:"ATTIC" /dev/sdb
    #   sudo partprobe /dev/sdb
    #   sudo mkfs.ext4 -L ATTIC /dev/sdb1
    "/attic" = {
      device = "/dev/disk/by-label/ATTIC";
      fsType = "ext4";
      options = [ "noatime" "nofail" ];
    };
  };

  # Disable aggressive head-parking on the two spinning HDDs.
  #
  # Wear status as of 2026-05-26 (both drives ~8.5y of 24/7 service):
  #
  #   sda (WD30EZRX, "Green"):  POH=75,404h  Load_Cycle_Count=511,124
  #   sdb (ST2000DM006):        POH=70,168h  Load_Cycle_Count=397,228
  #
  # Both are well past the typical 300k load-cycle budget for consumer
  # spinners. Both still report zero reallocations, zero pending sectors,
  # zero CRC errors, empty SMART error logs, and PASSED self-assessment;
  # the load-cycle counter is a wear indicator in this firmware class,
  # not a failure trigger. smartd watches the real failure signals.
  #
  # hdparm only works on sdb (sda is a WD Green; "APM feature is:
  # Unavailable" -- standard ATA APM is not implemented in that firmware
  # line; the proprietary IntelliPark timer would have to be disabled via
  # idle3-tools, which requires a full power cycle to take effect and is
  # not viable for a 24/7 remote host). The accumulation rate on sda is
  # modest (~6.8 cycles/hour, not the 450/hr you'd expect at the
  # canonical 8s timer), so we accept it. See the WD caveat block in
  # modules/hdd-power-mgmt.nix for the full rationale.
  custom.hddPowerMgmt = {
    enable = true;
    disks = [
      "ata-WDC_WD30EZRX-00MMMB0_WD-WCAWZ2644073" # sda (STORAGE + PROJECTS); APM unsupported
      "ata-ST2000DM006-2DM164_Z4ZA10CF" # sdb (ATTIC); APM=254 applied
    ];
  };
}
