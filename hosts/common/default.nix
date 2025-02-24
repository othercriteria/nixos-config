{ config, pkgs, pkgs-stable, lib, ... }:

{
  # Common system configuration
  imports = [
    ../../modules/fonts.nix
    ../../modules/greetd.nix
  ];

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

    # VPN
    protonvpn-cli_2

    # Text editor
    emacs
  ];

  environment.pathsToLink = [ "/share/zsh" ];

  users.users.dlk = {
    isNormalUser = true;
    extraGroups = [ "docker" "vboxusers" "wheel" ];
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
    extraRules = [{
      groups = [ "wheel" ];
      commands = [
        {
          command = "${pkgs.protonvpn-cli_2}/bin/protonvpn c *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.protonvpn-cli_2}/bin/protonvpn d";
          options = [ "NOPASSWD" ];
        }
      ];
    }];
    extraConfig = ''
      Defaults secure_path="${lib.makeBinPath [ pkgs.protonvpn-cli_2 ]}:/run/current-system/sw/bin"
    '';
  };
}
