# Publish meteor-4 GPU metrics to skaia's Mosquitto broker.
#
# Topics (retained):
# - nixos/meteor-4/gpu/temperature  : Celsius
# - nixos/meteor-4/gpu/utilization  : percent
# - nixos/meteor-4/gpu/memory_used  : MiB
#
# COLD START: Home Assistant sensors for these topics live in the
# Yellow's /config/configuration.yaml, not in this repo. See
# docs/COLD-START.md. The publisher uses the shared nixos MQTT
# password; custom.hostSecretsManifest must allow mqtt-nixos-password.
{
  pkgs,
  ...
}:

let
  mqttHost = "skaia.home.arpa";
  mqttPort = "1883";
  mqttUser = "nixos";
  mqttPasswordFile = "/etc/nixos/secrets/mqtt-nixos-password";

  publishScript = pkgs.writeShellScript "mqtt-gpu-publisher" ''
    set -euo pipefail

    MQTT_PASS=$(cat ${mqttPasswordFile})

    publish() {
      ${pkgs.mosquitto}/bin/mosquitto_pub \
        -h ${mqttHost} -p ${mqttPort} \
        -u ${mqttUser} -P "$MQTT_PASS" \
        -t "$1" -m "$2" -r
    }

    NVIDIA_SMI="/run/current-system/sw/bin/nvidia-smi"
    if [ -x "$NVIDIA_SMI" ]; then
      GPU_TEMP=$("$NVIDIA_SMI" --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo "")
      GPU_UTIL=$("$NVIDIA_SMI" --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' || echo "")
      GPU_MEM=$("$NVIDIA_SMI" --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' || echo "")

      [ -n "$GPU_TEMP" ] && publish "nixos/meteor-4/gpu/temperature" "$GPU_TEMP"
      [ -n "$GPU_UTIL" ] && publish "nixos/meteor-4/gpu/utilization" "$GPU_UTIL"
      [ -n "$GPU_MEM" ] && publish "nixos/meteor-4/gpu/memory_used" "$GPU_MEM"
    fi
  '';
in
{
  systemd.services.mqtt-gpu-publisher = {
    description = "Publish meteor-4 GPU metrics to MQTT";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = publishScript;
      # nvidia-smi needs the host driver devices.
      User = "root";
    };
  };

  systemd.timers.mqtt-gpu-publisher = {
    description = "Publish meteor-4 GPU metrics to MQTT periodically";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "30s";
      Unit = "mqtt-gpu-publisher.service";
    };
  };
}
