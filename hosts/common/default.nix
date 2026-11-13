{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Common system configuration
  imports = [
    ../../modules/fonts.nix
    ../../modules/glances.nix
    ../../modules/greetd.nix
    ../../modules/printing.nix
    ../../modules/protonvpn.nix
    ../../modules/shutdown-visibility.nix
    ../../modules/vibectl.nix
  ];

  custom = {
    # Enable shutdown visibility for better crash diagnostics
    shutdownVisibility.enable = true;
    # Enable vibectl for any host with kubectl
    vibectl = {
      enable = true;
      anthropicApiKeyFile = "/etc/nixos/secrets/anthropic-2025-04-10-vibectl-personal-usage";
    };
  };

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
      system-features = [
        "big-parallel"
        "kvm"
        "nixos-test"
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # nh os switch is what `make apply-host` runs. The flake path is the
  # synced /etc/nixos tree: secret files are absolute paths there, and a
  # bare `nh os switch` must not build the git checkout instead. Dry
  # builds pass the workspace path explicitly (`make build-host`).
  # nix.gc.automatic is already on, so nh's own cleaner stays off.
  programs.nh = {
    enable = true;
    flake = "/etc/nixos";
  };

  # Shared system settings
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    # useXkbConfig = true; # use xkbOptions in tty.
  };

  nixpkgs.config = {
    allowUnfree = true;
    # GTK 2 is marked broken ahead of removal before NixOS 27.05
    # (nixpkgs#410814). Interactive Brokers TWS still links it
    # (modules/tws.nix), so evaluation has to be allowed. Home Manager
    # sees meta.broken and skips its GTK 2 input-method cache, which
    # matches fcitx5-gtk shipping without the GTK 2 module.
    problems.handlers."gtk+".broken = "ignore";
  };

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
    extraGroups = [
      "docker"
      "vboxusers"
      "wheel"
      "networkmanager"
    ];
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
  systemd.user.settings.Manager = {
    DefaultEnvironment = "HOME=/home/dlk";
  };

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

  # home-ca root (ECDSA P-256, CN=home-ca-20260526). Rotated 2026-05-30
  # from the original mkcert RSA root; see docs/runbooks/home-ca-rotation.md.
  security.pki.certificateFiles = [
    ../../assets/certs/rootCA.pem
  ];
}
