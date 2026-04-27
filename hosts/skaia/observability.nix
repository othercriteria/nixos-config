# Observability stack for skaia (primary monitoring server)
#
# Uses shared modules for core functionality:
# - Prometheus with node exporter and k8s scraping
# - Grafana dashboards
# - Loki log aggregation
# - Alloy log shipping
#
# Site-specific additions:
# - Alertmanager with email notifications
# - Netdata parent node (receives streams from hive)
# - ZFS snapshot service for Prometheus data

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/loki.nix
    ../../modules/ntfy.nix
    ../../modules/promtail.nix
    ../../modules/grafana.nix
    ../../modules/prometheus-base.nix
    ../../modules/prometheus-rules.nix
    ../../modules/prometheus-zfs-snapshot.nix
  ];

  # ============================================================
  # Core observability stack via shared modules
  # ============================================================

  custom = {
    loki = {
      enable = true;
      # Listen on all interfaces to accept logs from LAN hosts (hive, etc.)
      listenAddress = "0.0.0.0";
    };
    ntfy = {
      enable = true;
      baseUrl = "https://ntfy.valueof.info";
      auth = {
        enable = true;
        username = "dlk";
        passwordFile = "/etc/nixos/secrets/ntfy-password";
      };
    };
    promtail.enable = true;
    grafana = {
      enable = true;
      port = 2342;
      prometheusUrl = "http://localhost:9001"; # skaia uses non-default port
      # COLD START: Requires /etc/nixos/secrets/grafana-secret-key to exist
      secretKeyFile = "/etc/nixos/secrets/grafana-secret-key";
      # Production: no anonymous access, bind to localhost only
    };
    prometheus = {
      enable = true;
      port = 9001;
      nodeExporter = {
        port = 9002;
        enabledCollectors = [ "perf" "sysctl" "systemd" "tcpstat" ];
        defaultScrapeJob = false; # skaia defines custom 'skaia' job in extraScrapeConfigs
      };
      extraFlags = [ "--storage.tsdb.retention.time=30d" ];
      # Can't do build-time validation, since k3s token is generated at runtime
      checkConfig = false;
      extraScrapeConfigs =
        let
          # Common TLS config for k8s
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
              targets = [ "127.0.0.1:${toString config.custom.prometheus.nodeExporter.port}" ];
            }];
          }
          # SMART/NVMe health metrics. Lets us see things like
          # smartctl_device_critical_warning, percentage_used, available_spare,
          # media_errors_total. Crucial for catching NVMe firmware/wear issues
          # on the fastdisk pool (Samsung 990 PROs) before they take the host
          # down again.
          {
            job_name = "smartctl";
            # smartctl exporter polls the disks itself on its own interval
            # (see services.prometheus.exporters.smartctl below), so we just
            # need a slow-ish scrape here. Fast scrapes don't yield fresh data.
            scrape_interval = "60s";
            static_configs = [{
              targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.smartctl.port}" ];
              labels = {
                instance = "skaia";
              };
            }];
          }
          {
            job_name = "hive";
            scrape_interval = "30s";
            static_configs = [{
              targets = [ "hive.home.arpa:9002" ];
            }];
          }
          # Blackbox probe for Urbit web interface health
          {
            job_name = "urbit-health";
            scrape_interval = "60s";
            scrape_timeout = "10s";
            metrics_path = "/probe";
            params = {
              module = [ "http_2xx_3xx" ];
            };
            static_configs = [{
              targets = [ "http://hive.home.arpa:8080/" ];
              labels = {
                service = "urbit";
                ship = "taptev-donwyx";
              };
            }];
            relabel_configs = [
              {
                source_labels = [ "__address__" ];
                target_label = "__param_target";
              }
              {
                source_labels = [ "__param_target" ];
                target_label = "instance";
              }
              {
                target_label = "__address__";
                replacement = "127.0.0.1:9115"; # Blackbox exporter
              }
            ];
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
    };
  };

  # ============================================================
  # Site-specific: Alertmanager, Netdata, ZFS snapshots
  # ============================================================

  systemd.services = {
    alertmanager.serviceConfig.User = "dlk";

    prometheus.serviceConfig = {
      User = "prometheus";
      Group = "prometheus";
    };

    # Ensure the smartctl-exporter-access ACL is present on /dev/nvme*
    # before the exporter scans devices. The NixOS module ships a udev
    # rule that ACL-grants the smartctl-exporter-access group on
    # `ACTION=="add"` events for NVMe character devices, but on a running
    # system the rule never fires for NVMes that were attached at boot
    # before the rule was loaded (e.g. immediately after a `nixos-rebuild
    # switch` that introduces or restarts the exporter). The exporter
    # caches its initial device scan, so even if the ACL becomes correct
    # later, NVMe metrics never appear until restart.
    #
    # Re-trigger udev for the nvme subsystem at every service start, as
    # root (the `+` prefix), and wait for the events to drain. This is
    # idempotent and cheap.
    prometheus-smartctl-exporter.serviceConfig.ExecStartPre = [
      "+${pkgs.systemd}/bin/udevadm trigger --action=add --subsystem-match=nvme"
      "+${pkgs.systemd}/bin/udevadm settle --timeout=5"
    ];
  };

  services = {
    prometheusZfsSnapshot = {
      enable = true;
      dataset = "fastdisk/prometheus";
    };

    # Netdata: real-time monitoring with PSI support and intelligent correlation
    # Addresses io_uring iowait misreporting by showing actual pressure metrics
    # Configured as parent node - receives streams from child nodes (e.g., hive)
    netdata = {
      enable = true;
      # Enable cloud UI (requires unfree license acceptance)
      package = pkgs.netdata.override { withCloudUi = true; };
      config = {
        global = {
          # Bind to LAN interface to receive streams from child nodes
          "bind to" = "127.0.0.1 192.168.0.160";
          "update every" = 1; # 1-second granularity
          "memory mode" = "dbengine"; # Efficient tiered storage
        };
        # DB engine storage allocation (parent node with children)
        # Data stored in /var/cache/netdata/dbengine
        db = {
          "mode" = "dbengine";
          # Tier 0: 1s resolution, ~1 week retention at 4GB
          "dbengine tier 0 disk space MB" = 4096;
          # Tier 1: 1m resolution, ~3 months retention at 4GB
          "dbengine tier 1 disk space MB" = 4096;
          # Tier 2: 1h resolution, ~2 years retention at 2GB
          "dbengine tier 2 disk space MB" = 2048;
          # Page cache for hot data (default 32MB is low for parent)
          "dbengine page cache size MB" = 128;
        };
        # PSI metrics - the "correct" signal for resource pressure
        "plugin:proc:/proc/pressure" = {
          "enable collecting pressure metrics" = "yes";
        };
        # NVIDIA GPU monitoring via nvidia-smi
        "plugin:proc" = {
          "/sys/class/powercap" = "yes";
        };
      };
      # Enable nvidia-smi collector for GPU metrics + streaming config
      configDir = {
        "go.d/nvidia_smi.conf" = pkgs.writeText "nvidia_smi.conf" ''
          jobs:
            - name: gpu0
              binary_path: ${pkgs.linuxPackages.nvidia_x11.bin}/bin/nvidia-smi
        '';
        # Parent node streaming configuration - accept streams from child nodes
        # The stream key is just an identifier (security is via firewall allow from)
        "stream.conf" = pkgs.writeText "stream.conf" ''
          # Parent configuration: accept streams from child nodes (e.g., hive)
          [336169ef-6efc-448d-9174-88ea697e1b3d]
              enabled = yes
              default memory mode = dbengine
              health enabled by default = auto
              allow from = 192.168.0.*
        '';
      };
    };

    # Prometheus exporters and alertmanager
    prometheus = {
      # smartctl_exporter: SMART/NVMe metrics for the two Samsung 990 PROs
      # backing fastdisk plus the SATA disks in slowdisk. Bound to localhost
      # only (Prometheus scrapes on the same host). The NixOS module already
      # grants the necessary CAP_SYS_RAWIO/CAP_SYS_ADMIN and DeviceAllow rules
      # so we can run it as an unprivileged smartctl-exporter user.
      exporters.smartctl = {
        enable = true;
        listenAddress = "127.0.0.1";
        # Default port is 9633; leave as-is. Polling interval defaults to 60s,
        # which matches our scrape_interval above.
      };

      # Blackbox exporter for HTTP/TCP probe monitoring
      # Used to check if services like Urbit are responding
      exporters.blackbox = {
        enable = true;
        port = 9115;
        configFile = pkgs.writeText "blackbox.yml" ''
          modules:
            http_2xx_3xx:
              prober: http
              timeout: 5s
              http:
                valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
                valid_status_codes: [200, 301, 302, 303, 307, 308]
                method: GET
                follow_redirects: false
                fail_if_ssl: false
                fail_if_not_ssl: false
                preferred_ip_protocol: "ip4"
        '';
      };

      # Alertmanager with ntfy + email notifications
      # ntfy: instant push notifications for critical/warning alerts
      # email: audit trail and less urgent notifications
      alertmanager = {
        enable = true;
        port = 9093;
        configText = ''
          global:
            resolve_timeout: 5m
            smtp_smarthost: "127.0.0.1:1025"
            smtp_from: "daniel.l.klein@pm.me"
          route:
            receiver: "ntfy-and-email"
            group_wait: 30s
            group_interval: 5m
            repeat_interval: 3h
            routes:
            # Critical alerts: high priority ntfy + email
            - match:
                severity: critical
              receiver: "ntfy-critical"
              continue: true
            # All alerts also go to the default receiver
          receivers:
          - name: "ntfy-and-email"
            webhook_configs:
            - url: "http://127.0.0.1:8090/alerts"
              send_resolved: true
              http_config:
                basic_auth:
                  username: "dlk"
                  password_file: "/etc/nixos/secrets/ntfy-password"
            email_configs:
            - to: "daniel.l.klein@pm.me"
              send_resolved: true
              require_tls: false
              auth_username: "daniel.l.klein@pm.me"
              auth_password_file: "/etc/nixos/secrets/dlk-protonmail-password"
          - name: "ntfy-critical"
            webhook_configs:
            - url: "http://127.0.0.1:8090/alerts?priority=urgent&tags=rotating_light"
              send_resolved: true
              http_config:
                basic_auth:
                  username: "dlk"
                  password_file: "/etc/nixos/secrets/ntfy-password"
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
  };
}
