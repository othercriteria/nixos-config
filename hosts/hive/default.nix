{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ./storage.nix
    ./observability.nix
  ];

  # Boot configuration with LUKS encryption
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      systemd-boot.configurationLimit = 8;
    };

    # Hardware quirks for this system
    kernelParams = [
      "pci=nomsi"
      "acpi_rev_override"
    ];

    # LUKS-encrypted root partition
    initrd.luks.devices.root = {
      device = "/dev/nvme0n1p3";
      preLVM = true;
    };
  };

  # Intel graphics - hardware video acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-vaapi-driver
      libvdpau-va-gl
      libva-vdpau-driver
      libva
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-vaapi-driver
      libvdpau-va-gl
      libva-vdpau-driver
    ];
  };

  networking = {
    hostName = "hive";
    hostId = "a8c06e01"; # unique hostId for hive
    # Uses systemd-networkd (inherited from server-common)

    firewall = {
      enable = true;
      allowPing = true;
      allowedTCPPorts = [
        22 # SSH
        3022 # Teleport SSH
        8080 # Urbit web interface (proxied through skaia nginx)
      ];
      allowedUDPPorts = [
        # Urbit Ames protocol (peer-to-peer networking)
      ];
      # Urbit uses high UDP ports for Ames protocol
      allowedUDPPortRanges = [
        { from = 13337; to = 65535; }
      ];
    };
  };

  # Teleport node for remote access
  custom.teleportNode = {
    enable = true;
    # COLD START: Generate join token on skaia with:
    #   tctl tokens add --type=node --ttl=1h
    # Then populate this file on hive
    tokenFile = "/etc/nixos/secrets/teleport/hive.token";
    labels = {
      role = "urbit";
      site = "residence-1";
    };
  };

  environment.systemPackages = with pkgs; [
    # Storage and filesystem tools
    cryptsetup
    ntfs3g
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. This was originally installed on 17.09.
  # Do NOT change this value unless you understand the implications.
  # Override server-common's stateVersion since hive was installed much earlier
  system.stateVersion = lib.mkForce "17.09";
}
