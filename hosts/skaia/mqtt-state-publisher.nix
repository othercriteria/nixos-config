# MQTT State Publisher for Home Assistant integration
#
# Publishes NixOS system state to MQTT topics that Home Assistant
# can subscribe to and create sensors from.
#
# Published topics:
# - nixos/skaia/status           : online/offline (with LWT)
# - nixos/skaia/gpu/temperature  : GPU temperature in Celsius
# - nixos/skaia/gpu/utilization  : GPU utilization percentage
# - nixos/skaia/gpu/memory_used  : GPU memory used in MiB
# - nixos/skaia/streaming        : on/off (OBS streaming status)
# - nixos/skaia/vpn              : connected/disconnected

{ config, lib, pkgs, ... }:

let
  mqttHost = "localhost";
  mqttPort = "1883";
  mqttUser = "nixos";
  mqttPasswordFile = "/etc/nixos/secrets/mqtt-nixos-password";

  publishScript = pkgs.writeShellScript "mqtt-state-publisher" ''
    set -euo pipefail

    MQTT_HOST="${mqttHost}"
    MQTT_PORT="${mqttPort}"
    MQTT_USER="${mqttUser}"
    MQTT_PASS=$(cat ${mqttPasswordFile})

    publish() {
      ${pkgs.mosquitto}/bin/mosquitto_pub \
        -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "$1" -m "$2" -r
    }

    # Publish online status
    publish "nixos/skaia/status" "online"

    # GPU metrics (skaia has NVIDIA GPU)
    NVIDIA_SMI="/run/current-system/sw/bin/nvidia-smi"
    if [ -x "$NVIDIA_SMI" ]; then
      GPU_TEMP=$("$NVIDIA_SMI" --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo "")
      GPU_UTIL=$("$NVIDIA_SMI" --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' || echo "")
      GPU_MEM=$("$NVIDIA_SMI" --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' || echo "")

      [ -n "$GPU_TEMP" ] && publish "nixos/skaia/gpu/temperature" "$GPU_TEMP"
      [ -n "$GPU_UTIL" ] && publish "nixos/skaia/gpu/utilization" "$GPU_UTIL"
      [ -n "$GPU_MEM" ] && publish "nixos/skaia/gpu/memory_used" "$GPU_MEM"
    fi

    # Streaming status (check if SRS has active streams)
    if curl -sf localhost:1985/api/v1/streams/ 2>/dev/null | ${pkgs.jq}/bin/jq -e '.streams | length > 0' > /dev/null 2>&1; then
      publish "nixos/skaia/streaming" "on"
    else
      publish "nixos/skaia/streaming" "off"
    fi

    # VPN status (check NetworkManager)
    if ${pkgs.networkmanager}/bin/nmcli -t -f TYPE,STATE con show --active 2>/dev/null | grep -q "vpn:activated"; then
      publish "nixos/skaia/vpn" "connected"
    else
      publish "nixos/skaia/vpn" "disconnected"
    fi
  '';
in
{
  imports = [ ./mqtt.nix ];

  systemd.services.mqtt-state-publisher = {
    description = "Publish NixOS state to MQTT for Home Assistant";
    after = [ "network.target" "mosquitto.service" ];
    wants = [ "mosquitto.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = publishScript;
      # Run as root to access nvidia-smi and NetworkManager
      User = "root";
    };
  };

  systemd.timers.mqtt-state-publisher = {
    description = "Publish NixOS state to MQTT periodically";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "30s";
      Unit = "mqtt-state-publisher.service";
    };
  };
}
