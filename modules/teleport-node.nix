{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption optionalString types;

  cfg = config.custom.teleportNode;

  labelsString =
    let
      labelPairs = map (name: "${name}=${cfg.labels.${name}}") (lib.attrNames cfg.labels);
    in
    lib.concatStringsSep "," labelPairs;

  startScript = pkgs.writeShellScript "teleport-node-start" ''
    set -euo pipefail

    TOKEN_ARG=()
    if [ -n "''${TELEPORT_TOKEN_FILE:-}" ] && [ -s "''${TELEPORT_TOKEN_FILE}" ]; then
      TOKEN="$(tr -d '\r\n' < "''${TELEPORT_TOKEN_FILE}")"
      if [ -n "$TOKEN" ]; then
        TOKEN_ARG+=(--token "$TOKEN")
      fi
    fi

    LABELS_ARG=()
    if [ -n "''${TELEPORT_LABELS:-}" ]; then
      LABELS_ARG+=(--labels "''${TELEPORT_LABELS}")
    fi

    exec ${pkgs.teleport_18}/bin/teleport start \
      --roles=node \
      --auth-server=${cfg.authServer} \
      --data-dir=${cfg.dataDir} \
      --nodename=${cfg.nodeName} \
      "''${LABELS_ARG[@]}" \
      "''${TOKEN_ARG[@]}"
  '';
in
{
  options.custom.teleportNode = {
    enable = mkEnableOption "Teleport node service";

    tokenFile = mkOption {
      type = types.str;
      example = "/etc/nixos/secrets/teleport/meteor-1.token";
      description = ''
        Path to a file containing a one-time Teleport node join token. The
        service reads the token if the file exists and is non-empty. After the
        node has joined the cluster, the token can be removed or truncated.
      '';
    };

    authServer = mkOption {
      type = types.str;
      default = "skaia.home.arpa:3025";
      example = "teleport.valueof.info:443";
      description = "Teleport auth or proxy address the node should join.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/teleport-node";
      description = "Directory to persist Teleport node identity and state.";
    };

    nodeName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Node name as it will appear inside Teleport.";
    };

    labels = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { role = "k3s"; location = "residence-1"; };
      description = "Static labels assigned to this Teleport node.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = lib.mkIf (!(config.services.teleport.enable or false)) [
      pkgs.teleport_18
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    systemd.services.teleport-node = {
      description = "Teleport node agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.coreutils pkgs.teleport_18 ];
      serviceConfig = {
        ExecStart = startScript;
        Environment = [
          "TELEPORT_TOKEN_FILE=${cfg.tokenFile}"
          "TELEPORT_LABELS=${labelsString}"
        ];
        Restart = "on-failure";
        RestartSec = "5s";
        RuntimeDirectory = "teleport-node";
      };
    };
  };
}
