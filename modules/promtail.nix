# Alloy-backed Loki log shipper module
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
    enable = lib.mkEnableOption "Alloy-backed Loki log shipper";

    lokiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:3100/loki/api/v1/push";
      description = "URL of the Loki push API endpoint.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.alloy = {
      enable = true;
    };

    environment.etc."alloy/config.alloy".text = ''
      loki.relabel "journal" {
        forward_to = []

        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
      }

      loki.source.journal "read" {
        forward_to    = [loki.write.endpoint.receiver]
        relabel_rules = loki.relabel.journal.rules
        labels = {
          host = "${config.networking.hostName}",
          job  = "systemd-journal",
        }
      }

      loki.write "endpoint" {
        endpoint {
          url = "${cfg.lokiUrl}"
        }
      }
    '';
  };
}
