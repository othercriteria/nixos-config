{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../common
    ../../modules/desktop-common.nix
    ./hardware-configuration.nix # Generated hardware config

    ./audio.nix
    ./ddclient.nix
    ./email-alerts.nix
    ./firewall.nix
    ./graphics.nix
    ./k3s
    ./minidlna.nix
    ./observability.nix
    ./samba.nix
    ./thermal.nix
    ./virtualisation.nix
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernel.sysctl."kernel.perf_event_paranoid" = 0;
    kernelParams = [ "zfs.zfs_arc_max=38654705664" ];
  };

  fileSystems."/bulk" =
    {
      device = "slowdisk/bulk";
      fsType = "zfs";
    };

  networking = {
    hostName = "skaia"; # XXX: this is used in email-alerts.nix
    hostId = "68ae467c";
    networkmanager.enable = true;
  };

  services = {
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
      autoSnapshot = {
        enable = true;
        frequent = 4;
        hourly = 24;
        daily = 7;
        weekly = 4;
        monthly = 12;
      };
    };

    xserver = {
      enable = true;
      videoDrivers = [ "nvidia" ];
    };

    # COLD START: Requires ZFS dataset slowdisk/registry mounted at /var/lib/registry
    dockerRegistry = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 5000;
      storagePath = "/var/lib/registry";
      enableDelete = true;
    };
  };

  # Generally, Wayland-related...
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    XDG_SESSION_TYPE = "wayland";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
    MOZ_ENABLE_WAYLAND = "1";
    EGL_STREAM = "1";
    WLR_RENDERER = "vulkan";
    NIXOS_OZONE_WL = "1";

    XDG_CURRENT_DESKTOP = "sway";
  };

  environment.systemPackages = with pkgs; [
    fio
    gptfdisk
    hydroxide
    libinput
    libva-utils
    sshfs-fuse
    vulkan-tools

    docker

    pkgs-stable.veracrypt # XXX: unstable veracrypt is broken
  ];

  programs = {
    # Needed for remote VS Code to work, per https://nixos.wiki/wiki/Visual_Studio_Code
    nix-ld.enable = true;

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    mtr.enable = true;

    steam.enable = true;

    # Configure OBS Studio with plugins
    obs-studio = {
      enable = true;
      enableVirtualCamera = true;
      plugins = with pkgs.obs-studio-plugins; [
        wlrobs
        obs-pipewire-audio-capture
        obs-vkcapture
      ];
      package = pkgs.obs-studio.override {
        cudaSupport = true;
      };
    };
  };

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
