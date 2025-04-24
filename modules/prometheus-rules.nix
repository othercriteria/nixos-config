# Prometheus alerting rules module
#
# Provides a list of Prometheus alerting rules as JSON strings.
# Import and merge into your host config to supply rules to services.prometheus.rules.
# Example usage in host config:
#   (import ../../modules/prometheus-rules.nix) { inherit config; } //


{ config, lib, ... }:

{
  options.prometheusRules = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Extra Prometheus alerting rules as JSON strings.";
  };

  config = {
    prometheusRules = [
      # Node disk space low
      (builtins.toJSON {
        groups = [
          {
            name = "self-monitoring.rules";
            rules = [
              {
                alert = "PrometheusDiskSpaceLow";
                expr =
                  "(node_filesystem_avail_bytes{mountpoint=\"/zfs/prometheus\"} / node_filesystem_size_bytes{mountpoint=\"/zfs/prometheus\"}) * 100 < 15";
                "for" = "5m";
                labels = { severity = "warning"; };
                annotations = {
                  summary = "Low disk space on Prometheus volume";
                  description = "Less than 15% free on /zfs/prometheus for 5m.";
                };
              }
              # Prometheus process health
              {
                alert = "PrometheusDown";
                expr = "up{job=\"skaia\"} == 0";
                "for" = "2m";
                labels = { severity = "critical"; };
                annotations = {
                  summary = "Prometheus process is down";
                  description = "Prometheus is not responding to scrapes.";
                };
              }
              # Scrape failures
              {
                alert = "PrometheusScrapeFailures";
                expr = "increase(prometheus_target_scrapes_failed_total[5m]) > 0";
                "for" = "5m";
                labels = { severity = "warning"; };
                annotations = {
                  summary = "Prometheus scrape failures detected";
                  description = "One or more targets are failing scrapes.";
                };
              }
            ];
          }
        ];
      })
      # Node rules from original config
      (builtins.toJSON {
        groups = [
          {
            name = "node.rules";
            rules = [
              {
                alert = "DiskSpaceLow";
                expr =
                  "(node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay\", mountpoint=\"/\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|overlay\", mountpoint=\"/\"}) * 100 < 15";
                "for" = "5m";
                labels = { severity = "warning"; };
                annotations = {
                  summary = "Low disk space on {{ $labels.instance }}";
                  description = "Disk space is below 15% free on mount {{ $labels.mountpoint }}.";
                };
              }
              {
                alert = "HighCPUTemperature";
                expr =
                  "node_hwmon_temp_celsius{chip=\"platform_nct6775_656\", sensor=\"temp1\"} > 80";
                "for" = "5m";
                labels = { severity = "critical"; };
                annotations = {
                  summary = "High CPU Temperature on {{ $labels.instance }}";
                  description = "CPU temperature is above 80°C for more than 5 minutes.";
                };
              }
            ];
          }
        ];
      })
    ];
  };
}
