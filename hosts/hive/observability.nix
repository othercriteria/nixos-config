# Observability for hive: metrics and logs flow to skaia
#
# Uses shared modules for Promtail log shipping.
# Site-specific: node exporter and netdata child node configuration.

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/promtail.nix
  ];

  # Ship logs to skaia's Loki
  custom.promtail = {
    enable = true;
    lokiUrl = "http://skaia.home.arpa:3100/loki/api/v1/push";
  };

  # Site-specific: Node exporter scraped by skaia's Prometheus
  services.prometheus.exporters.node = {
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
  services.netdata = {
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
}
