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
                # Dataset is fastdisk/prometheus, mounted at
                # /var/lib/prometheus2 (see docs/OBSERVABILITY.md). The
                # old /zfs/prometheus mountpoint never existed, so this
                # rule could not fire.
                expr = "(node_filesystem_avail_bytes{mountpoint=\"/var/lib/prometheus2\"} / node_filesystem_size_bytes{mountpoint=\"/var/lib/prometheus2\"}) * 100 < 15";
                "for" = "5m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Low disk space on Prometheus volume";
                  description = "Less than 15% free on /var/lib/prometheus2 for 5m.";
                };
              }
              {
                alert = "PrometheusDown";
                expr = "up{job=\"skaia\"} == 0";
                "for" = "2m";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "Prometheus process is down";
                  description = "Prometheus is not responding to scrapes.";
                };
              }
              {
                alert = "PrometheusScrapeFailures";
                expr = "increase(prometheus_target_scrapes_failed_total[5m]) > 0";
                "for" = "5m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Prometheus scrape failures detected";
                  description = "One or more targets are failing scrapes.";
                };
              }
              {
                # Catches the regression we hit on skaia where
                # prometheus-node-exporter died silently for ~4 days because
                # systemd hit its start-limit. Any scrape job staying down
                # for 15 minutes should page us so we can't silently lose
                # telemetry again.
                alert = "ScrapeTargetDown";
                expr = "up == 0";
                "for" = "15m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Scrape target {{ $labels.job }} on {{ $labels.instance }} is down";
                  description = "Prometheus has been unable to scrape {{ $labels.job }} at {{ $labels.instance }} for 15 minutes (up == 0).";
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
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "High rate of Home Assistant auth failures";
                  description = "More than 10 failed auth attempts in 5 minutes. Possible brute-force attack.";
                };
              }
              {
                alert = "HomeAssistantDown";
                expr = "up{job=\"homeassistant\"} == 0";
                "for" = "5m";
                labels = {
                  severity = "warning";
                };
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
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Urbit ship ~{{ $labels.ship }} is unresponsive";
                  description = "Urbit web interface at {{ $labels.instance }} has not responded for 3 minutes.";
                };
              }
              {
                alert = "UrbitSlow";
                expr = "probe_duration_seconds{job=\"urbit-health\"} > 5";
                "for" = "5m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Urbit ship ~{{ $labels.ship }} responding slowly";
                  description = "Urbit web interface is taking >5s to respond for 5 minutes.";
                };
              }
            ];
          }
          # the-baltic-approaches site publishing (modules/baltic-site).
          # The deploy is designed to fail safe: a broken upstream commit
          # or a failed fetch leaves the previous build serving. That is
          # the right behaviour but it is silent, so the page can go stale
          # indefinitely with nothing visibly wrong. These two rules cover
          # the two ways that happens: the deploy runs and fails, or the
          # deploy stops running at all. Both are warnings rather than
          # critical -- readers keep getting the last good build.
          {
            name = "baltic-site.rules";
            rules = [
              {
                alert = "BalticSiteDeployFailing";
                expr = ''
                  node_systemd_unit_state{name="baltic-site-deploy.service",state="failed"} == 1
                '';
                # The timer fires every 15m (plus up to 2m of jitter), so
                # 30m means at least two consecutive failures and a
                # transient GitHub or substituter blip stays quiet.
                "for" = "30m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "the-baltic-approaches site deploy is failing";
                  description = "baltic-site-deploy.service on {{ $labels.instance }} has been in the failed state for 30 minutes, so valueof.info/the-baltic-approaches/ is still serving the previously published build. Check `journalctl -u baltic-site-deploy`: either the book repo's test suite is red on main or the build/fetch is broken.";
                };
              }
              {
                alert = "BalticSiteDeployStalled";
                # Catches the case the failure alert cannot see: the timer
                # itself stopped firing (masked, disabled, or lost across a
                # rebuild), so the service never runs and never fails. The
                # `> 0` guard keeps this quiet after a reboot, before the
                # timer has triggered for the first time.
                expr = ''
                  node_systemd_timer_last_trigger_seconds{name="baltic-site-deploy.timer"} > 0
                  and
                  time() - node_systemd_timer_last_trigger_seconds{name="baltic-site-deploy.timer"} > 3600
                '';
                "for" = "10m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "the-baltic-approaches deploy timer has stopped firing";
                  description = "baltic-site-deploy.timer on {{ $labels.instance }} last triggered over an hour ago, against a 15m schedule. New commits on the book repo's main are not reaching valueof.info/the-baltic-approaches/. Check `systemctl list-timers baltic-site-deploy`.";
                };
              }
            ];
          }
          # SMART/NVMe health rules. Driven by smartctl_exporter where it
          # is enabled (currently only skaia). These give us early warning
          # for the kind of NVMe issue that left fastdisk in a precarious
          # state in April 2026.
          {
            name = "smart.rules";
            rules = [
              {
                alert = "SmartHealthFailing";
                # smartctl_device_smart_status: 1 = passed, 0 = failed
                expr = "smartctl_device_smart_status == 0";
                "for" = "5m";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "SMART self-assessment failing on {{ $labels.device }}";
                  description = "smartctl reports SMART overall-health FAILED on {{ $labels.device }} ({{ $labels.model_name }}) at {{ $labels.instance }}. Investigate / replace immediately.";
                };
              }
              {
                alert = "NvmeCriticalWarning";
                expr = "smartctl_device_critical_warning > 0";
                "for" = "5m";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "NVMe critical warning on {{ $labels.device }}";
                  description = "smartctl_device_critical_warning is {{ $value }} on {{ $labels.device }} ({{ $labels.model_name }}) at {{ $labels.instance }}. Any non-zero value indicates an NVMe controller-reported critical condition.";
                };
              }
              {
                alert = "NvmeMediaErrors";
                expr = "increase(smartctl_device_media_errors_total[1h]) > 0";
                "for" = "5m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "New NVMe media/integrity errors on {{ $labels.device }}";
                  description = "smartctl_device_media_errors_total increased by {{ $value }} in the last hour on {{ $labels.device }} at {{ $labels.instance }}.";
                };
              }
              {
                alert = "NvmeWearHigh";
                expr = "smartctl_device_percentage_used > 80";
                "for" = "1h";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "NVMe wear above 80% on {{ $labels.device }}";
                  description = "Percentage Used is {{ $value }}% on {{ $labels.device }} ({{ $labels.model_name }}) at {{ $labels.instance }}. Plan replacement before the drive enters read-only fallback at 100%.";
                };
              }
              {
                alert = "NvmeAvailableSpareLow";
                # NVMe Available Spare is reported as a percentage; healthy
                # drives sit at 100. Once it drops below the threshold
                # (typically 10), the controller raises a critical warning.
                expr = "smartctl_device_available_spare < 20";
                "for" = "10m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "NVMe available spare low on {{ $labels.device }}";
                  description = "Available Spare is {{ $value }}% on {{ $labels.device }} at {{ $labels.instance }}. Approaching the controller's available_spare_threshold; replacement should be planned.";
                };
              }
            ];
          }
          # ZFS pool health from pdf/zfs_exporter (skaia). 0 = ONLINE.
          {
            name = "zfs.rules";
            rules = [
              {
                alert = "ZfsPoolUnhealthy";
                expr = "zfs_pool_health > 0";
                "for" = "2m";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "ZFS pool {{ $labels.pool }} is unhealthy";
                  description = "zfs_pool_health is {{ $value }} on {{ $labels.pool }} at {{ $labels.instance }} (0=ONLINE, 1=DEGRADED, 2=FAULTED, 3=OFFLINE, 4=UNAVAIL, 5=REMOVED, 6=SUSPENDED). Check `zpool status`.";
                };
              }
              {
                alert = "ZfsPoolOutOfSpace";
                expr = "zfs_pool_free_bytes * 100 / zfs_pool_size_bytes < 10 and zfs_pool_size_bytes > 0";
                "for" = "10m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "ZFS pool {{ $labels.pool }} is below 10% free";
                  description = "Pool {{ $labels.pool }} on {{ $labels.instance }} has {{ $value }}% free. Dataset-level quotas can hide this from filesystem alerts.";
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
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "High disk I/O backlog on {{ $labels.instance }}";
                  description = "Disk {{ $labels.device }} has weighted I/O time >10 for 15 minutes. This indicates I/O pressure that may cause system slowdowns.";
                };
              }
              {
                alert = "DiskSpaceLow";
                # Watch every real filesystem, not just /. skaia splits
                # /var, /nix, /home, /bulk, and service datasets onto
                # their own ZFS datasets; filling any of those would
                # previously stay silent.
                expr = "(node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay|squashfs|ramfs|aufs|devtmpfs|fuse.*\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|overlay|squashfs|ramfs|aufs|devtmpfs|fuse.*\"}) * 100 < 15";
                "for" = "5m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Low disk space on {{ $labels.instance }} {{ $labels.mountpoint }}";
                  description = "Disk space is below 15% free on mount {{ $labels.mountpoint }} ({{ $labels.fstype }}).";
                };
              }
              {
                alert = "BootDiskSpaceLow";
                # EFI vfat is small; leftover systemd-boot generations
                # fill it and the next rebuild cannot install a kernel.
                expr = "(node_filesystem_avail_bytes{mountpoint=\"/boot\"} / node_filesystem_size_bytes{mountpoint=\"/boot\"}) * 100 < 20";
                "for" = "15m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Low space on /boot on {{ $labels.instance }}";
                  description = "Less than 20% free on /boot. systemd-boot will fail to install a new generation once the ESP is full.";
                };
              }
              {
                alert = "HighCPUTemperature";
                expr = "node_hwmon_temp_celsius{chip=\"platform_nct6775_656\", sensor=\"temp1\"} > 80";
                "for" = "5m";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "High CPU Temperature on {{ $labels.instance }}";
                  description = "CPU temperature is above 80°C for more than 5 minutes.";
                };
              }
            ];
          }
          # ntfy.sh (self-hosted). Scraped from modules/ntfy.nix when both
          # ntfy and Prometheus are enabled on the host. NtfyDown is
          # critical because it is the push path for other alerts; the
          # default Alertmanager route still emails if ntfy itself is
          # unreachable. ScrapeTargetDown also covers this at 15m.
          {
            name = "ntfy.rules";
            rules = [
              {
                alert = "NtfyDown";
                expr = "up{job=\"ntfy\"} == 0";
                "for" = "2m";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "ntfy is not being scraped";
                  description = "Prometheus cannot scrape ntfy at {{ $labels.instance }} for 2 minutes. iOS/Android push and Alertmanager webhooks will fail until ntfy-sh.service recovers.";
                };
              }
              {
                alert = "NtfyPublishFailures";
                expr = "increase(ntfy_messages_published_failure[15m]) > 5";
                "for" = "15m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "ntfy publish failures";
                  description = "{{ $value }} ntfy publishes failed in 15 minutes (auth, rate-limit, or upstream). Check ntfy-sh.service logs.";
                };
              }
            ];
          }
        ];
      })
    ];
  };
}
