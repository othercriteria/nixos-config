# Promtail log shipper module
#
# Ships systemd journal logs to a Loki instance.
# Used by both production hosts and test/demo environments.
#
# Usage:
#   imports = [ ../../modules/promtail.nix ];
#   custom.promtail.enable = true;
#   custom.promtail.lokiUrl = "http://loki-server:3100/loki/api/v1/push";

{ config, lib, ... }:

let
  cfg = config.custom.promtail;
in
{
  options.custom.promtail = {
    enable = lib.mkEnableOption "Promtail log shipper";

    lokiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:3100/loki/api/v1/push";
      description = "URL of the Loki push API endpoint.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          disable = true;
        };
        clients = [{
          url = cfg.lokiUrl;
        }];
        scrape_configs = [
          {
            job_name = "journal";
            journal = {
              labels = {
                job = "systemd-journal";
                host = config.networking.hostName;
              };
            };
            relabel_configs = [{
              source_labels = [ "__journal__systemd_unit" ];
              target_label = "unit";
            }];
          }
        ];
      };
    };
  };
}
