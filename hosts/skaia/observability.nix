{ config, ... }:

{
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
