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
  };
}
