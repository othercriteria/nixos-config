# Bypass Netdata's "5 active nodes" local-dashboard nerf.
#
# Background: starting in Netdata v2.x the SPA dashboard pops a modal that
# limits anonymous (non-Cloud-Business) users to 5 active nodes. The C
# backend (src/web/api/v3/api_v3_settings.c) has no node-count check; it
# only reads and writes <varlib>/settings/default verbatim. The cap is
# enforced purely in the frontend, based on `value.preferred_node_ids`
# in that JSON file.
#
# Workaround: query the parent's registry for every registered child's
# machine_guid and stamp them all into `preferred_node_ids`. The SPA then
# treats every node as already-user-selected and never shows the modal.
#
# A systemd timer re-runs the update so newly registered children get
# picked up without manual intervention. The C backend re-reads the file
# on every request, so no netdata restart is required for changes to
# take effect.
#
# Usage (parent-side only):
#   imports = [ ../../modules/netdata-unlock-nodes.nix ];
#   custom.netdataUnlockNodes.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.custom.netdataUnlockNodes;

  updateScript = pkgs.writeShellApplication {
    name = "netdata-unlock-nodes-update";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    text = ''
      set -euo pipefail

      registry_url="http://127.0.0.1:${toString cfg.port}/api/v1/registry?action=hello"
      settings_dir="${cfg.dataDir}/settings"
      settings_file="$settings_dir/default"

      mkdir -p "$settings_dir"
      tmp_file="$(mktemp -p "$settings_dir" .default.new.XXXXXX)"
      trap 'rm -f "$tmp_file"' EXIT

      # Fetch the registry; tolerate a brief startup window where netdata
      # is up as a unit but not yet accepting HTTP. Timer reruns will
      # converge anyway, so this is just a small first-boot smoother.
      attempt=1
      while ! curl --silent --fail --max-time 5 "$registry_url" \
              > "$tmp_file.raw"; do
        if [ "$attempt" -ge 5 ]; then
          echo "netdata-unlock-nodes: registry not reachable after $attempt tries" >&2
          exit 1
        fi
        attempt=$((attempt + 1))
        sleep 2
      done

      jq --compact-output '
        {
          version: 1,
          value: {
            preferred_node_ids: ([.nodes[].machine_guid] | sort)
          }
        }
      ' < "$tmp_file.raw" > "$tmp_file"
      rm -f "$tmp_file.raw"

      if [ -f "$settings_file" ] && cmp -s "$tmp_file" "$settings_file"; then
        exit 0
      fi

      chmod 0640 "$tmp_file"
      mv "$tmp_file" "$settings_file"
      n="$(jq '.value.preferred_node_ids | length' < "$settings_file")"
      echo "netdata-unlock-nodes: stamped $n machine_guid(s) into $settings_file"
    '';
  };
in
{
  options.custom.netdataUnlockNodes = {
    enable = lib.mkEnableOption
      "Pre-populate Netdata settings to bypass the 5-active-node UI nerf";

    port = lib.mkOption {
      type = lib.types.port;
      default = 19999;
      description = "Local Netdata HTTP port to query the registry on.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/netdata";
      description = ''
        Netdata varlib dir. The settings file is written to
        <dataDir>/settings/default.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = ''
        systemd OnUnitActiveSec for the refresh timer. Catches newly
        registered children without manual intervention.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.services.netdata.enable;
      message = "custom.netdataUnlockNodes requires services.netdata.enable = true";
    }];

    systemd.services.netdata-unlock-nodes = {
      description = "Stamp all registered machine_guids into Netdata's preferred_node_ids";
      after = [ "netdata.service" ];
      requires = [ "netdata.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "netdata";
        Group = "netdata";
        ExecStart = "${updateScript}/bin/netdata-unlock-nodes-update";
      };
    };

    systemd.timers.netdata-unlock-nodes = {
      description = "Periodic refresh of Netdata unlock-nodes settings";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.interval;
        Unit = "netdata-unlock-nodes.service";
      };
    };
  };
}
