{ config, pkgs, pkgs-stable, lib, ... }:

{
  # Headless server baseline (no GUI)
  # Imports: none of the desktop modules

  # Core nix settings
  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
      max-jobs = auto
      system-features = [ "big-parallel" ]
    '';
    settings = {
      download-buffer-size = 1000000000;
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Time and locale
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # Console
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  nixpkgs.config.allowUnfree = true;

  # Essential tools
  environment.systemPackages = with pkgs; [
    file
    git
    glances
    htop
    hwinfo
    lsof
    pciutils
    tree
    tmux
    usbutils
    wget
    emacs
  ];

  environment.pathsToLink = [ "/share/zsh" ];

  users.users.dlk = {
    isNormalUser = true;
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  # Networking stack: systemd-networkd by default for servers
  networking = {
    useNetworkd = true;
    useDHCP = lib.mkDefault true;
    networkmanager.enable = false;
  };
  services.resolved = {
    enable = true;
    # Allow mDNS if desired for .local discovery
    multicastDns = true;
  };

  services = {
    dbus.enable = true;
    openssh = {
      enable = true;
      settings = {
        PubkeyAuthentication = true;
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = [ "dlk" ];
      };
    };
    fail2ban.enable = true;
    timesyncd.enable = true;
  };

  security.sudo.enable = true;

  security.pki.certificateFiles = [
    ../../assets/certs/rootCA.pem
  ];

  # Memory: prefer zramSwap for these nodes
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };
}
