# Loki log aggregation module
#
# Provides a configurable Loki server for log aggregation.
# Used by both production hosts and test/demo environments.
#
# Usage:
#   imports = [ ../../modules/loki.nix ];
#   custom.loki.enable = true;

{ config, lib, ... }:

let
  cfg = config.custom.loki;
in
{
  options.custom.loki = {
    enable = lib.mkEnableOption "Loki log aggregation server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3100;
      description = "HTTP listen port for Loki server.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/loki";
      description = "Directory for Loki data storage.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.loki = {
      enable = true;
      configuration = {
        server.http_listen_port = cfg.port;
        auth_enabled = false;

        common = {
          ring = {
            instance_addr = "127.0.0.1";
            kvstore.store = "inmemory";
          };
          path_prefix = cfg.dataDir;
          storage = {
            filesystem = {
              chunks_directory = "${cfg.dataDir}/chunks";
              rules_directory = "${cfg.dataDir}/rules";
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
  };
}
