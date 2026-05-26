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

  # Disable aggressive head-parking on the two spinning HDDs. Both ship
  # with APM=128 by default; on a 24/7 server this burns through the
  # drive's load-cycle budget in a few years. See
  # modules/hdd-power-mgmt.nix for the longer rationale.
  custom.hddPowerMgmt = {
    enable = true;
    disks = [
      "ata-WDC_WD30EZRX-00MMMB0_WD-WCAWZ2644073" # sda (STORAGE + PROJECTS)
      "ata-ST2000DM006-2DM164_Z4ZA10CF" # sdb (ATTIC)
    ];
  };
}
