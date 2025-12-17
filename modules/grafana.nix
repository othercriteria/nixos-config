# Grafana dashboard module
#
# Provides Grafana with automatic datasource provisioning for Prometheus and Loki.
# Supports optional anonymous access for demo/test environments.
#
# Usage:
#   imports = [ ../../modules/grafana.nix ];
#   custom.grafana.enable = true;
#   custom.grafana.anonymousAccess = true;  # For demos

{ config, lib, ... }:

let
  cfg = config.custom.grafana;
in
{
  options.custom.grafana = {
    enable = lib.mkEnableOption "Grafana dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "HTTP port for Grafana.";
    };

    addr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind Grafana to.";
    };

    anonymousAccess = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable anonymous access with Admin role (for demos/tests).";
    };

    prometheusUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:9090";
      description = "URL of the Prometheus server for datasource.";
    };

    lokiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:3100";
      description = "URL of the Loki server for datasource.";
    };

    provisionDatasources = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically provision Prometheus and Loki datasources.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = cfg.port;
          http_addr = cfg.addr;
        };
        "auth.anonymous" = lib.mkIf cfg.anonymousAccess {
          enabled = true;
          org_role = "Admin";
        };
      };
      provision.datasources.settings.datasources = lib.mkIf cfg.provisionDatasources [
        {
          name = "Prometheus";
          type = "prometheus";
          url = cfg.prometheusUrl;
          isDefault = true;
        }
        {
          name = "Loki";
          type = "loki";
          url = cfg.lokiUrl;
        }
      ];
    };
  };
}
