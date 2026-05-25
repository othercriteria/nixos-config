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
  };
}
