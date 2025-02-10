{ config, ... }:

{
  systemd.services.alertmanager.serviceConfig = {
    User = "dlk";
  };

  services = {
    prometheus = {
      enable = true;
      port = 9001;

      exporters = {
        node = {
          enable = true;
          enabledCollectors = [
            "perf"
            "sysctl"
            "systemd"
            "tcpstat"
          ];
          port = 9002;
        };
      };

      scrapeConfigs = [
        {
          job_name = "skaia";
          scrape_interval = "30s";
          static_configs = [{
            targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
          }];
        }
      ];

      # Define alerting rules as a JSON string by forcing evaluation
      rules =
        let
          alertRules = {
            groups = [
              {
                name = "node.rules";
                rules = [
                  {
                    alert = "DiskSpaceLow";
                    expr =
                      "(node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay\", " +
                      "mountpoint=\"/\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|overlay\", " +
                      "mountpoint=\"/\"}) * 100 < 15";
                    "for" = "5m";
                    labels = { severity = "warning"; };
                    annotations = {
                      summary =
                        "Low disk space on {{ $labels.instance }}";
                      description =
                        "Disk space is below 15% free on mount {{ $labels.mountpoint }}.";
                    };
                  }
                  {
                    alert = "HighCPUTemperature";
                    expr =
                      "node_hwmon_temp_celsius{chip=\"platform_nct6775_656\", sensor=\"temp1\"} > 80";
                    "for" = "5m";
                    labels = { severity = "critical"; };
                    annotations = {
                      summary =
                        "High CPU Temperature on {{ $labels.instance }}";
                      description =
                        "CPU temperature is above 80°C for more than 5 minutes.";
                    };
                  }
                ];
              }
            ];
          };
        in
        [ "${builtins.toJSON alertRules}" ];

      # Alertmanager configuration nested under Prometheus
      alertmanager = {
        enable = true;
        port = 9093;
        configText = ''
          global:
            resolve_timeout: 5m
            smtp_smarthost: "127.0.0.1:1025"
            smtp_from: "daniel.l.klein@pm.me"
          route:
            receiver: "email"
            group_wait: 30s
            group_interval: 5m
            repeat_interval: 3h
          receivers:
          - name: "email"
            email_configs:
            - to: "daniel.l.klein@pm.me"
              send_resolved: true
              require_tls: false
              auth_username: "daniel.l.klein@pm.me"
              auth_password_file: "/etc/nixos/secrets/dlk-protonmail-password"
        '';
        extraFlags = [ "--cluster.listen-address=" ];
      };

      alertmanagers = [
        {
          scheme = "http";
          path_prefix = "/";
          static_configs = [
            { targets = [ "127.0.0.1:9093" ]; }
          ];
        }
      ];
    };

    grafana = {
      enable = true;
      settings.server = {
        http_port = 2342;
        http_addr = "127.0.0.1";
      };
    };

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
          storage = {
            filesystem = {
              chunks_directory = "/var/lib/loki/chunks";
              rules_directory = "/var/lib/loki/rules";
            };
          };
          replication_factor = 1;
        };

        querier = {
          max_concurrent = 2048;
          query_ingesters_within = 0;
        };
        query_scheduler = {
          max_outstanding_requests_per_tenant = 2048;
        };

        schema_config = {
          configs = [{
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
    };

    promtail = {
      enable = true;
      configuration = {
        server = {
          disable = true;
        };
        clients = [{
          url = "http://127.0.0.1:3100/loki/api/v1/push";
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
