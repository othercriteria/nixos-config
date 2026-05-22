# Netdata child node: streams real-time metrics to a parent Netdata host.
#
# Parent must be configured to accept streams with the same `apiKey`
# (see the `stream.conf` parent block in hosts/skaia/observability.nix).
# Security boundary is the parent's `allow from` rule, not the key.
#
# This module covers the "small servers that just stream" role. The
# parent retains the dbengine and serves the dashboard.
#
# Usage:
#   imports = [ ../../modules/netdata-child.nix ];
#   custom.netdataChild.enable = true;
#   # parent and apiKey have working defaults for residence-1.

{ config, lib, pkgs, ... }:

let
  cfg = config.custom.netdataChild;
in
{
  options.custom.netdataChild = {
    enable = lib.mkEnableOption "Netdata child node streaming to a parent";

    parent = lib.mkOption {
      type = lib.types.str;
      default = "skaia.home.arpa:19999";
      description = "Parent Netdata host:port to stream metrics to.";
    };

    apiKey = lib.mkOption {
      type = lib.types.str;
      default = "336169ef-6efc-448d-9174-88ea697e1b3d";
      description = ''
        Stream API key. Must match a stream block in the parent's
        stream.conf. Defaults to the residence-1 parent's accept-key
        (see hosts/skaia/observability.nix). Not a secret per se —
        the parent enforces source-IP via `allow from`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.netdata = {
      enable = true;
      config = {
        global = {
          # Child role: don't store data locally, stream everything to parent.
          "memory mode" = "none";
          "update every" = 1;
        };
        # Parent runs ML and health checks; children just emit metrics.
        ml = { "enabled" = "no"; };
        health = { "enabled" = "no"; };
      };
      configDir = {
        "stream.conf" = pkgs.writeText "stream.conf" ''
          [stream]
              enabled = yes
              destination = ${cfg.parent}
              api key = ${cfg.apiKey}
        '';
      };
    };
  };
}
