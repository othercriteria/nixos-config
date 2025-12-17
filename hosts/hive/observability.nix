{ config, lib, pkgs, ... }:

{
  # Observability for hive: metrics and logs flow to skaia
  # - Node exporter: scraped by skaia's Prometheus
  # - Promtail: ships logs to skaia's Loki
  # - Netdata: streams to skaia (parent) for centralized monitoring

  services = {
    prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [
        "systemd"
        "tcpstat"
      ];
      port = 9002;
      # Allow skaia to scrape
      openFirewall = true;
    };

    # Netdata child node - streams to skaia (parent)
    # Access hive's metrics via skaia's dashboard at netdata.home.arpa
    netdata = {
      enable = true;
      config = {
        global = {
          # Child node: don't store data locally, stream to parent
          "memory mode" = "none";
          "update every" = 1;
        };
        # Disable ML and health on child - parent handles these
        ml = {
          "enabled" = "no";
        };
        health = {
          "enabled" = "no";
        };
      };
      # Configure streaming to skaia
      # The stream key is just an identifier (matches key configured on skaia parent)
      configDir = {
        "stream.conf" = pkgs.writeText "stream.conf" ''
          [stream]
              enabled = yes
              destination = skaia.home.arpa:19999
              api key = 336169ef-6efc-448d-9174-88ea697e1b3d
        '';
      };
    };

    # Promtail ships journal logs to skaia's Loki
    promtail = {
      enable = true;
      configuration = {
        server.disable = true;
        clients = [{
          url = "http://skaia.home.arpa:3100/loki/api/v1/push";
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

  # Allow netdata streaming to skaia (outbound only, no firewall needed)
  # Allow promtail to reach Loki (outbound only)
}
