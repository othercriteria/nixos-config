{ config, lib, pkgs, ... }:

# UxPlay - AirPlay mirroring server for receiving iPhone screen mirrors
#
# Use cases:
#   - Mirror DJI Fly app video feed to skaia
#   - General iPhone/iPad screen sharing
#
# Usage:
#   1. Ensure iPhone and skaia are on the same network
#   2. Run: uxplay (or use the systemd service)
#   3. On iPhone: Control Center > Screen Mirroring > select "skaia"
#
# For DJI drone integration:
#   1. Open DJI Fly app on iPhone
#   2. Start screen mirroring to skaia
#   3. Video feed now visible on skaia's display

let
  # Fixed ports for firewall configuration
  # Using ports in 7000 range (AirPlay traditional range)
  airplayPorts = {
    tcp = [ 7000 7001 7100 ];
    udp = [ 6000 6001 7011 ];
  };
in
{
  # Avahi is required for AirPlay discovery (mDNS/Bonjour)
  # This overrides the security-focused disable in printing.nix
  # Risk accepted: mDNS exposure limited to LAN, provides useful functionality
  services.avahi = {
    enable = lib.mkForce true;
    nssmdns4 = true; # Enable mDNS resolution for IPv4
    publish = {
      enable = true;
      userServices = true; # Allow uxplay to publish its service
    };
  };

  # Install uxplay and required GStreamer plugins
  environment.systemPackages = with pkgs; [
    uxplay

    # GStreamer plugins for video/audio decoding
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad # Required for h264 parsing
    gst_all_1.gst-plugins-ugly # Additional codecs

    # For hardware-accelerated decoding on NVIDIA
    gst_all_1.gst-vaapi
  ];

  # Set GStreamer plugin path system-wide so uxplay can find all plugins
  # including pipewiresink from the pipewire package
  environment.sessionVariables.GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPath "lib/gstreamer-1.0" (with pkgs; [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-vaapi
    pipewire # Provides pipewiresink element
  ]);

  # Open firewall ports for AirPlay
  # These are the legacy ports that uxplay uses with -p option
  networking.firewall = {
    allowedTCPPorts = airplayPorts.tcp;
    allowedUDPPorts = airplayPorts.udp;
  };

  # User service for uxplay - defined via NixOS (not home-manager) so it gets
  # placed in /etc/profiles/per-user/*/share/systemd/user/ which systemd
  # actually scans. Home-manager's ~/.config/systemd/user/ isn't scanned
  # when using the greetd→zsh→sway login workaround.
  #
  # Start with: systemctl --user start uxplay
  systemd.user.services.uxplay = {
    description = "UxPlay AirPlay Mirroring Server";
    after = [ "graphical-session.target" ];

    environment = {
      GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPath "lib/gstreamer-1.0" (with pkgs; [
        gst_all_1.gstreamer
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-bad
        gst_all_1.gst-plugins-ugly
        gst_all_1.gst-vaapi
        pipewire
      ]);
    };

    serviceConfig = {
      Type = "simple";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.uxplay}/bin/uxplay"
        "-n skaia" # Network name shown on iPhone
        "-nh" # Don't append hostname
        "-p" # Use legacy ports (7000/7001/7100, 6000/6001/7011)
        "-vs waylandsink" # Wayland video output
        "-as pipewiresink" # PipeWire audio output
        "-reset 0" # Don't auto-reset on client silence
      ];
      Restart = "on-failure";
      RestartSec = "5s";
    };

    # Don't auto-start - user starts manually when needed
    wantedBy = [ ];
  };
}
