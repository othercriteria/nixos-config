# MQTT broker (Mosquitto) for Home Assistant integration
#
# Provides bidirectional state sharing between NixOS infrastructure and Home Assistant:
# - NixOS publishes system state (GPU temp, streaming status, VPN, etc.)
# - Home Assistant subscribes and creates sensors
# - Home Assistant can publish commands back to NixOS
#
# Users:
# - homeassistant: HA's MQTT integration (read/write all topics)
# - nixos: NixOS state publisher service (read/write all topics)
#
# Topics:
# - nixos/skaia/+         : System state from skaia
# - nixos/hive/+          : System state from hive (future)
# - homeassistant/+       : HA state/commands

{ config, lib, pkgs, ... }:

{
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "0.0.0.0";
        port = 1883;
        settings = {
          allow_anonymous = false;
        };
        users = {
          homeassistant = {
            passwordFile = "/etc/nixos/secrets/mqtt-homeassistant-password";
            acl = [ "readwrite #" ];
          };
          nixos = {
            passwordFile = "/etc/nixos/secrets/mqtt-nixos-password";
            acl = [ "readwrite #" ];
          };
        };
      }
    ];
  };

  # Open MQTT port for LAN access
  networking.firewall.allowedTCPPorts = [ 1883 ];
}
