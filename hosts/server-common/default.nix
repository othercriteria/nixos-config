{
  config,
  pkgs,
  pkgs-stable,
  lib,
  ...
}:

{
  imports = [
    ../../modules/teleport-node.nix
    ../../modules/shutdown-visibility.nix
    ../../modules/host-secrets-manifest.nix
    ../../modules/netdata-child.nix
    # Protects hosts that enable services.prometheus.exporters.node
    # directly (e.g. hive) from the upstream socket-activation regression.
    ../../modules/prometheus-node-exporter-fix.nix
  ];

  # Enable shutdown visibility for better crash diagnostics.
  # 500M vacuumed meteor-2's kernel history down to ~3 weeks, so the
  # remount-ro line was already gone when we looked. Match skaia.
  custom.shutdownVisibility = {
    enable = true;
    journalMaxSize = "2G";
  };

  # Headless server baseline (no GUI)
  # Imports: none of the desktop modules

  # Same netdata GOPROXY rewrite as skaia. hive/meteors use the default
  # (non-Cloud-UI) package; Hydra may not have a 2.11.0 cache hit if
  # this cmake step failed upstream too.
  nixpkgs.overlays = [
    (_final: prev: {
      netdata = import ../../overlays/netdata-offline-go.nix prev.netdata;
    })
  ];

  # Boot loader: assume UEFI and use systemd-boot
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    # Keep the ESP from filling with leftover generations. hive sets
    # the same value explicitly; meteors inherit this.
    systemd-boot.configurationLimit = 8;
  };

  # Forbid deep NVMe APST states. AMD + NVMe is a known-bad combo: the
  # drive can fail to wake and I/O dies, after which ext4 remounts root
  # read-only. Hit on skaia (Samsung 990 PRO, 2026-04-22) and consistent
  # with meteor-2 sitting RO from 2026-08-06 until reboot 2026-09-09.
  # See skaia's kernelParams for the full write-up.
  boot.kernelParams = [ "nvme_core.default_ps_max_latency_us=0" ];

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

  # System-managed gpg-agent so git-secret + manual gpg both work out of the
  # box on headless servers. Pulls gnupg + pinentry-curses into the system
  # closure, sets GPG_TTY in shell rc, and arranges socket activation per
  # user. No SSH support: these hosts handle SSH via OpenSSH.
  # Pre-existing keys live in ~/.gnupg/ as user state (see COLD-START sec 0).
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  # Essential tools
  environment.systemPackages = with pkgs; [
    file
    git
    glances
    htop
    hwinfo
    lsof
    pciutils
    smartmontools
    tree
    tmux
    usbutils
    wget
    emacs
  ];

  environment.pathsToLink = [ "/share/zsh" ];

  users.users.dlk = {
    isNormalUser = true;
    extraGroups = [
      "docker"
      "wheel"
    ];
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

  # Networking stack: systemd-networkd by default for servers.
  # Pin DNS to Unbound on skaia. DHCP from the TP-Link also hands
  # out the router (192.168.0.1); that resolver NXDOMAINs home.arpa
  # (AS112), and systemd-resolved treats NXDOMAIN as final, so names
  # like cache.home.arpa never reach skaia.
  networking = {
    useNetworkd = true;
    useDHCP = lib.mkDefault true;
    networkmanager.enable = false;
    nameservers = [ "192.168.0.160" ];
  };
  systemd.network.networks =
    let
      ignoreDhcpDns = {
        dhcpV4Config.UseDNS = false;
        dhcpV6Config.UseDNS = false;
        ipv6AcceptRAConfig.UseDNS = false;
      };
    in
    {
      "99-ethernet-default-dhcp" = ignoreDhcpDns;
      "99-wireless-client-dhcp" = ignoreDhcpDns;
    };
  services.resolved = {
    enable = true;
    # Allow mDNS if desired for .local discovery
    settings = {
      Resolve = {
        MulticastDNS = "yes";
      };
    };
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

    # NVMe / SATA SMART monitoring. Picks up drives via smartctl
    # --scan-open, runs the upstream default short-test schedule, and
    # emits any failed attributes (wear %, available spare, media
    # errors, temperature warnings) to the journal. Journal streams to
    # skaia via netdata-child, so a future Prom/AM rule (or netdata
    # health alert) on `smartd:*` log lines is enough to surface
    # drives degrading silently. The meteor fleet is uniformly
    # Kingston OM8 NVMe; SMART attribute coverage is good there.
    smartd.enable = true;
  };

  security.sudo.enable = true;

  # home-ca root (ECDSA P-256, CN=home-ca-20260526). Rotated 2026-05-30
  # from the original mkcert RSA root; see docs/runbooks/home-ca-rotation.md.
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
