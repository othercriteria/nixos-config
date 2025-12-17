# Prometheus base module
#
# Provides core Prometheus functionality with node exporter.
# Hosts can extend with additional scrape configs for their specific needs.
#
# Usage:
#   imports = [ ../../modules/prometheus-base.nix ../../modules/prometheus-rules.nix ];
#   custom.prometheus.enable = true;
#   custom.prometheus.extraScrapeConfigs = [ { job_name = "custom"; ... } ];

{ config, lib, ... }:

let
  cfg = config.custom.prometheus;
in
{
  options.custom.prometheus = {
    enable = lib.mkEnableOption "Prometheus monitoring";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "HTTP port for Prometheus server.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind Prometheus to. Use 0.0.0.0 for VM/container access.";
    };

    nodeExporter = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable node exporter.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9100;
        description = "Port for node exporter.";
      };

      enabledCollectors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "systemd" ];
        description = "Node exporter collectors to enable.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open firewall for node exporter (for remote scraping).";
      };

      defaultScrapeJob = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create default 'node' scrape job. Disable if defining custom job in extraScrapeConfigs.";
      };
    };

    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = "Default scrape interval.";
    };

    extraScrapeConfigs = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Additional scrape configurations to add.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra command-line flags for Prometheus.";
    };

    checkConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to check config at build time (disable for runtime secrets).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      inherit (cfg) port listenAddress extraFlags checkConfig;

      exporters.node = lib.mkIf cfg.nodeExporter.enable {
        enable = true;
        inherit (cfg.nodeExporter) port enabledCollectors openFirewall;
      };

      scrapeConfigs =
        (lib.optional cfg.nodeExporter.defaultScrapeJob {
          job_name = "node";
          scrape_interval = cfg.scrapeInterval;
          static_configs = [{
            targets = [ "localhost:${toString cfg.nodeExporter.port}" ];
          }];
        })
        ++ [
          {
            job_name = "prometheus";
            scrape_interval = cfg.scrapeInterval;
            static_configs = [{
              targets = [ "localhost:${toString cfg.port}" ];
            }];
          }
        ] ++ cfg.extraScrapeConfigs;

      # Use rules from prometheus-rules.nix if imported
      rules = lib.mkIf (config ? prometheusRules) config.prometheusRules;
    };
  };
}
