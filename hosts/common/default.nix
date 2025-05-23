{ config, pkgs, pkgs-stable, lib, ... }:

{
  # Common system configuration
  imports = [
    ../../modules/fonts.nix
    ../../modules/greetd.nix
    ../../modules/printing.nix
    ../../modules/protonvpn.nix
    ../../modules/vibectl.nix

  ];

  # Enable vibectl for any host with kubectl
  custom.vibectl.enable = true;
  custom.vibectl.anthropicApiKeyFile = "/etc/nixos/secrets/anthropic-2025-04-10-vibectl-personal-usage";

  nix = {
    package = pkgs.nixVersions.stable;

    extraOptions = ''
      experimental-features = nix-command flakes
      # Keep builds for 30 days
      keep-outputs = true
      keep-derivations = true
      # Maximum number of parallel jobs during builds
      max-jobs = auto
      # Allow up to 8 concurrent tasks during builds
      system-features = [ "big-parallel" ]
    '';

    # Optimize store by hard linking identical files
    settings = {
      download-buffer-size = 1000000000; # 1GB instead of default 1MB
      auto-optimise-store = true;
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Shared system settings
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    # useXkbConfig = true; # use xkbOptions in tty.
  };

  nixpkgs.config.allowUnfree = true;

  # Common system packages
  environment.systemPackages = with pkgs; [
    # Configuration and debugging
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

    # Text editor
    emacs
  ];

  environment.pathsToLink = [ "/share/zsh" ];

  users.users.dlk = {
    isNormalUser = true;
    extraGroups = [ "docker" "vboxusers" "wheel" "networkmanager" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

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
    keybase.enable = true;
  };

  security.sudo = {
    enable = true;
  };
}
