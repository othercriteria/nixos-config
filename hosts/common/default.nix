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
    '';

    settings = {
      download-buffer-size = 1000000000; # 1GB instead of default 1MB
      auto-optimise-store = true;
      # System features for builds
      # - big-parallel: enable parallel builds
      # - kvm, nixos-test: enable NixOS VM integration tests
      system-features = [ "big-parallel" "kvm" "nixos-test" ];
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

  # Common environment settings
  environment = {
    # Common system packages
    systemPackages = with pkgs; [
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

    pathsToLink = [ "/share/zsh" ];

    # Ensure zsh login shells get a correct HOME even if the environment
    # inherited HOME="/". This fixes SSH/greetd sessions where zsh starts
    # with HOME unset or set to "/".
    etc."zshenv.local".text = ''
      if [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        HOME="$(getent passwd "$USER" | cut -d: -f6)"
        export HOME
      fi
    '';
  };

  users.users.dlk = {
    isNormalUser = true;
    extraGroups = [ "docker" "vboxusers" "wheel" "networkmanager" ];
    shell = pkgs.zsh;
  };

  programs = {
    zsh.enable = true;
    uwsm = {
      enable = true;
      waylandCompositors = {
        sway = {
          prettyName = "Sway";
          comment = "Sway compositor managed by UWSM";
          binPath = "/etc/profiles/per-user/dlk/bin/sway";
        };
      };
    };
  };

  # Ensure the systemd user manager has a correct HOME for login sessions
  systemd.user.extraConfig = ''
    DefaultEnvironment=HOME=/home/dlk
  '';



  services = {
    dbus = {
      enable = true;
      implementation = "broker";
    };
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

  security.pki.certificateFiles = [
    ../../assets/certs/rootCA.pem
  ];
}
