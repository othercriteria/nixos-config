# Demo VM configuration for portfolio exploration
#
# This uses the SAME observability modules as production, demonstrating
# that the config actually works without requiring real hardware or secrets.
#
# Build and run:
#   make demo
# Or directly:
#   nixos-rebuild build-vm --flake .#demo
#   ./result/bin/run-demo-vm
#
# Login: user "demo" with password "demo"
# Services available:
#   - Prometheus: http://localhost:9090
#   - Grafana: http://localhost:3000 (anonymous access enabled)
#   - Loki: http://localhost:3100

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/loki.nix
    ../../modules/promtail.nix
    ../../modules/grafana.nix
    ../../modules/prometheus-base.nix
    ../../modules/prometheus-rules.nix
  ];

  # ============================================================
  # Observability stack via shared modules (same as production!)
  # ============================================================

  custom = {
    loki.enable = true;
    promtail.enable = true;
    grafana = {
      enable = true;
      addr = "0.0.0.0"; # Allow access from host
      anonymousAccess = true; # Easy exploration without login
    };
    prometheus = {
      enable = true;
      nodeExporter.enabledCollectors = [ "systemd" ];
    };
  };

  # ============================================================
  # Basic VM configuration
  # ============================================================

  system.stateVersion = "24.11";
  networking.hostName = "demo";

  # Minimal filesystem for VM (qemu-vm module handles the rest)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  boot.loader.grub.device = "nodev";

  # Time and locale
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # Demo user with simple password for exploration
  users.users.demo = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "demo";
    description = "Demo user for VM exploration";
  };

  # Allow passwordless sudo for demo convenience
  security.sudo.wheelNeedsPassword = false;

  # Auto-login to the demo user
  services.getty.autologinUser = "demo";

  # Essential packages for exploration
  environment.systemPackages = with pkgs; [
    curl
    htop
    jq
    vim
    wget
  ];

  # Nix settings
  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # ============================================================
  # VM Configuration
  # ============================================================

  virtualisation.vmVariant = {
    # VM-specific settings
    virtualisation = {
      memorySize = 2048;
      cores = 2;
      # Forward ports for web access from host
      forwardPorts = [
        { from = "host"; host.port = 9090; guest.port = 9090; } # Prometheus
        { from = "host"; host.port = 3000; guest.port = 3000; } # Grafana
        { from = "host"; host.port = 3100; guest.port = 3100; } # Loki
      ];
    };
  };

  # Message of the day for demo
  users.motd = ''

    ╔══════════════════════════════════════════════════════════════╗
    ║           NixOS Observability Stack Demo                     ║
    ╠══════════════════════════════════════════════════════════════╣
    ║                                                              ║
    ║  This demo uses the SAME modules as production configs!      ║
    ║                                                              ║
    ║  Services (accessible from host via port forwarding):        ║
    ║    • Prometheus:  http://localhost:9090                      ║
    ║    • Grafana:     http://localhost:3000 (no login needed)    ║
    ║    • Loki:        http://localhost:3100                      ║
    ║                                                              ║
    ║  Try these commands:                                         ║
    ║    systemctl status prometheus                               ║
    ║    curl -s localhost:9090/api/v1/targets | jq .              ║
    ║    curl -s localhost:3000/api/datasources | jq .             ║
    ║                                                              ║
    ║  Source: github.com/othercriteria/nixos-config               ║
    ╚══════════════════════════════════════════════════════════════╝

  '';
}
