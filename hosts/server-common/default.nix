{ config, pkgs, pkgs-stable, lib, ... }:

{
  imports = [
    ../../modules/teleport-node.nix
  ];

  # Headless server baseline (no GUI)
  # Imports: none of the desktop modules

  # Boot loader: assume UEFI and use systemd-boot
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # State version for new servers
  # COLD START: Update to the actual NixOS release used for initial install
  system.stateVersion = "25.11";

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

      # Use local binary cache on skaia (served by Harmonia)
      # Falls back to cache.nixos.org if local cache unavailable
      substituters = [
        "http://cache.home.arpa"
        "https://cache.nixos.org"
      ];
      trusted-public-keys = [
        (lib.strings.removeSuffix "\n" (builtins.readFile ../../assets/harmonia-cache-public-key.txt))
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
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

  # Ensure a minimal user zsh config exists to suppress newuser prompt
  system.userActivationScripts.initialZshrcForDlk.text = ''
    set -e
    HOME_DIR=$(getent passwd dlk | cut -d: -f6)
    if [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ]; then
      if [ ! -f "$HOME_DIR/.zshrc" ]; then
        echo "# Managed by NixOS: minimal zshrc" > "$HOME_DIR/.zshrc"
        chown dlk:users "$HOME_DIR/.zshrc" || chown dlk:"$(id -gn dlk)" "$HOME_DIR/.zshrc" || true
        chmod 0644 "$HOME_DIR/.zshrc"
      fi
    fi
  '';

  # Networking stack: systemd-networkd by default for servers
  networking = {
    useNetworkd = true;
    useDHCP = lib.mkDefault true;
    networkmanager.enable = false;
  };
  services.resolved = {
    enable = true;
    # Allow mDNS if desired for .local discovery
    extraConfig = "MulticastDNS=yes";
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

  custom.teleportNode = {
    enable = lib.mkDefault false;
    authServer = lib.mkDefault "skaia.home.arpa:3025";
    dataDir = lib.mkDefault "/var/lib/teleport-node";
  };

  # Memory: prefer zramSwap for these nodes
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # Docker for container image building
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      default-ulimits = {
        nofile = {
          name = "nofile";
          hard = 64000;
          soft = 64000;
        };
      };
    };
  };
}
