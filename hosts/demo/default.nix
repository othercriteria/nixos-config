# Demo VM configuration for portfolio exploration
#
# This is a self-contained NixOS configuration that demonstrates the
# observability stack without requiring real hardware or secrets.
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
    ../../modules/prometheus-rules.nix
  ];

  # Basic system settings
  system.stateVersion = "24.11";
  networking.hostName = "demo";

  # Use QEMU/virtio for VM
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
  # Observability Stack
  # ============================================================

  services = {
    # Prometheus with node exporter
    prometheus = {
      enable = true;
      port = 9090;

      exporters.node = {
        enable = true;
        port = 9100;
        enabledCollectors = [ "systemd" ];
      };

      scrapeConfigs = [
        {
          job_name = "node";
          scrape_interval = "15s";
          static_configs = [{
            targets = [ "localhost:9100" ];
          }];
        }
        {
          job_name = "prometheus";
          scrape_interval = "15s";
          static_configs = [{
            targets = [ "localhost:9090" ];
          }];
        }
      ];

      # Use alerting rules from our module
      rules = config.prometheusRules;
    };

    # Grafana with anonymous access for easy exploration
    grafana = {
      enable = true;
      settings = {
        server = {
          http_port = 3000;
          http_addr = "0.0.0.0";
        };
        "auth.anonymous" = {
          enabled = true;
          org_role = "Admin";
        };
      };
      provision.datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:9090";
          isDefault = true;
        }
        {
          name = "Loki";
          type = "loki";
          url = "http://localhost:3100";
        }
      ];
    };

    # Loki for log aggregation
    loki = {
      enable = true;
      configuration = {
        server.http_listen_port = 3100;
        auth_enabled = false;

        common = {
          ring = {
            instance_addr = "127.0.0.1";
            kvstore.store = "inmemory";
          };
          path_prefix = "/var/lib/loki";
          storage.filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
          replication_factor = 1;
        };

        schema_config.configs = [{
          from = "2020-10-24";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }];
      };
    };

    # Promtail to ship journal logs to Loki
    promtail = {
      enable = true;
      configuration = {
        server.disable = true;
        clients = [{ url = "http://localhost:3100/loki/api/v1/push"; }];
        scrape_configs = [{
          job_name = "journal";
          journal = {
            labels = {
              job = "systemd-journal";
              host = "demo";
            };
          };
          relabel_configs = [{
            source_labels = [ "__journal__systemd_unit" ];
            target_label = "unit";
          }];
        }];
      };
    };
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
