# Prometheus alerting rules module
#
# Provides Prometheus alerting rules as a single JSON string with multiple groups.
# Import and use with services.prometheus.rules = config.prometheusRules;
#
# Example usage in host config:
#   imports = [ ../../modules/prometheus-rules.nix ];
#   services.prometheus.rules = config.prometheusRules;

{ config, lib, ... }:

{
  options.prometheusRules = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Prometheus alerting rules as JSON strings.";
  };

  config = {
    prometheusRules = [
      (builtins.toJSON {
        groups = [
          # Self-monitoring rules for Prometheus infrastructure
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
          # Home Assistant security monitoring
          {
            name = "homeassistant.rules";
            rules = [
              {
                alert = "HomeAssistantAuthFailureSpike";
                expr = ''
                  sum(increase(nginx_http_requests_total{server="assistant.valueof.info", status=~"401|403"}[5m])) > 10
                '';
                "for" = "2m";
                labels = { severity = "warning"; };
                annotations = {
                  summary = "High rate of Home Assistant auth failures";
                  description = "More than 10 failed auth attempts in 5 minutes. Possible brute-force attack.";
                };
              }
              {
                alert = "HomeAssistantDown";
                expr = "up{job=\"homeassistant\"} == 0";
                "for" = "5m";
                labels = { severity = "warning"; };
                annotations = {
                  summary = "Home Assistant is unreachable";
                  description = "Cannot scrape Home Assistant metrics for 5 minutes.";
                };
              }
            ];
          }
          # Urbit health monitoring
          {
            name = "urbit.rules";
            rules = [
              {
                alert = "UrbitUnresponsive";
                expr = "probe_success{job=\"urbit-health\"} == 0";
                "for" = "3m";
                labels = { severity = "warning"; };
                annotations = {
                  summary = "Urbit ship ~{{ $labels.ship }} is unresponsive";
                  description = "Urbit web interface at {{ $labels.instance }} has not responded for 3 minutes.";
                };
              }
              {
                alert = "UrbitSlow";
                expr = "probe_duration_seconds{job=\"urbit-health\"} > 5";
                "for" = "5m";
                labels = { severity = "warning"; };
                annotations = {
                  summary = "Urbit ship ~{{ $labels.ship }} responding slowly";
                  description = "Urbit web interface is taking >5s to respond for 5 minutes.";
                };
              }
            ];
          }
          # Node-level monitoring rules
          {
            name = "node.rules";
            rules = [
              {
                alert = "DiskIOBacklogHigh";
                expr = "rate(node_disk_io_time_weighted_seconds_total[5m]) > 10";
                "for" = "15m";
                labels = { severity = "warning"; };
                annotations = {
                  summary = "High disk I/O backlog on {{ $labels.instance }}";
                  description = "Disk {{ $labels.device }} has weighted I/O time >10 for 15 minutes. This indicates I/O pressure that may cause system slowdowns.";
                };
              }
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
