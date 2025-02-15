{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../common
    ./hardware-configuration.nix # Generated hardware config

    ./audio.nix
    ./ddclient.nix
    ./email-alerts.nix
    ./firewall.nix
    ./k3s.nix
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
  };

  security = {
    rtkit.enable = true;
    polkit.enable = true;
    pam.loginLimits = [
      { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
    ];
  };

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    nvidia = {
      powerManagement.enable = false;
      powerManagement.finegrained = false;

      modesetting.enable = true;

      # nvidiaPersistenced = true;

      forceFullCompositionPipeline = true;

      open = false;

      # Exposed via `nvidia-settings`.
      nvidiaSettings = true;

      package = config.boot.kernelPackages.nvidiaPackages.latest;
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

    CHROME_EXTRA_ARGS = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-gpu-rasterization --enable-zero-copy";

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

    # podman-compose
    # nvidia-docker
    # nvidia-podman
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
  };

  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  programs.thunar = {
    enable = true;
    plugins = with pkgs.xfce; [
      thunar-archive-plugin
      thunar-volman
    ];
  };
  programs.xfconf.enable = true; # Allows Thunar preference to persist without XFCE
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  # Enable XDG portal
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config = {
      common = {
        default = [ "gtk" ];
      };
      browsers = {
        default = [ "google-chrome-stable" ];
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
