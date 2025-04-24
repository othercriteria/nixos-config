{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/prometheus-rules.nix
    ../../modules/prometheus-zfs-snapshot.nix
  ];

  services.prometheusZfsSnapshot.dataset = "fastdisk/prometheus";

  systemd.services.alertmanager.serviceConfig = {
    User = "dlk";
  };

  systemd.services.prometheus.serviceConfig = {
    User = "prometheus";
    Group = "prometheus";
  };

  services = {
    prometheus = {
      enable = true;
      port = 9001;
      # Prometheus data is stored in /var/lib/prometheus2 by default.
      # Ensure your ZFS dataset is mounted at /var/lib/prometheus2 for optimal performance and durability.
      extraFlags = [ "--storage.tsdb.retention.time=30d" ];
      # Can't do build-time validation, since k3s token is generated at runtime
      checkConfig = false;

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

      scrapeConfigs =
        let
          # Common TLS config
          baseTlsConfig = {
            insecure_skip_verify = true;
            cert_file = "/var/lib/prometheus-k3s/client.crt";
            key_file = "/var/lib/prometheus-k3s/client.key";
          };

          # Common k8s SD config
          baseK8sSdConfig = {
            api_server = "https://localhost:6443";
            tls_config = baseTlsConfig;
          };

          # Common node relabeling
          nodeRelabelConfigs = [
            {
              action = "labelmap";
              regex = "__meta_kubernetes_node_label_(.+)";
            }
            {
              target_label = "__address__";
              replacement = "localhost:10250";
            }
            {
              target_label = "cluster";
              replacement = "frog";
            }
          ];

          # Common service endpoint relabeling
          serviceRelabelConfigs = [
            {
              source_labels = [ "__meta_kubernetes_service_annotation_prometheus_io_scrape" ];
              action = "keep";
              regex = "true";
            }
            {
              source_labels = [ "__meta_kubernetes_service_annotation_prometheus_io_scheme" ];
              action = "replace";
              target_label = "__scheme__";
              regex = "(https?)";
              replacement = "$1";
            }
            {
              source_labels = [ "__meta_kubernetes_service_annotation_prometheus_io_path" ];
              action = "replace";
              target_label = "__metrics_path__";
              regex = "(.+)";
            }
            {
              source_labels = [ "__address__" "__meta_kubernetes_service_annotation_prometheus_io_port" ];
              action = "replace";
              target_label = "__address__";
              regex = "([^:]+)(?::\\d+)?;(\\d+)";
              replacement = "$1:$2";
            }
            {
              action = "labelmap";
              regex = "__meta_kubernetes_service_label_(.+)";
            }
            {
              source_labels = [ "__meta_kubernetes_namespace" ];
              action = "replace";
              target_label = "kubernetes_namespace";
            }
            {
              source_labels = [ "__meta_kubernetes_service_name" ];
              action = "replace";
              target_label = "kubernetes_name";
            }
            {
              target_label = "cluster";
              replacement = "frog";
            }
          ];
        in
        [
          {
            job_name = "skaia";
            scrape_interval = "30s";
            static_configs = [{
              targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
            }];
          }
          {
            job_name = "kubernetes-apiservers";
            scheme = "https";
            tls_config = baseTlsConfig;
            kubernetes_sd_configs = [{
              role = "endpoints";
              inherit (baseK8sSdConfig) api_server tls_config;
            }];
            relabel_configs = [
              {
                source_labels = [ "__meta_kubernetes_namespace" "__meta_kubernetes_service_name" "__meta_kubernetes_endpoint_port_name" ];
                action = "keep";
                regex = "default;kubernetes;https";
              }
              {
                target_label = "cluster";
                replacement = "frog";
              }
            ];
          }
          {
            job_name = "kubernetes-nodes";
            scheme = "https";
            tls_config = baseTlsConfig;
            kubernetes_sd_configs = [{
              role = "node";
              inherit (baseK8sSdConfig) api_server tls_config;
            }];
            relabel_configs = nodeRelabelConfigs;
          }
          {
            job_name = "kubernetes-cadvisor";
            scheme = "https";
            metrics_path = "/metrics/cadvisor";
            tls_config = baseTlsConfig;
            kubernetes_sd_configs = [{
              role = "node";
              inherit (baseK8sSdConfig) api_server tls_config;
            }];
            relabel_configs = nodeRelabelConfigs;
          }
          {
            job_name = "kubernetes-service-endpoints";
            scheme = "http";
            tls_config = baseTlsConfig;
            kubernetes_sd_configs = [{
              role = "endpoints";
              inherit (baseK8sSdConfig) api_server tls_config;
            }];
            relabel_configs = serviceRelabelConfigs;
          }
        ];

      # Use factored-out rules from module
      rules = config.prometheusRules;

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

    prometheusZfsSnapshot.enable = true;
  };
}
