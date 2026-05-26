{ config, lib, pkgs, ... }:

# CAVEAT: this module only adds polkit/NM glue so the user can drive
# ProtonVPN from the GUI. NetworkManager's default ProtonVPN connection
# installs a machine-wide default route via the VPN tunnel, so while
# the VPN is up:
#
#   - ddclient publishes the VPN exit IP instead of the home WAN IP
#     (observed in May 2026; symptom: teleport.valueof.info briefly
#      resolved to a Meta-owned VPN-exit IP).
#   - Inbound TLS to skaia-hosted public services likely breaks: the
#     SYN arrives via the LAN interface but the SYN-ACK is routed
#     through the tunnel and egresses with the VPN exit IP, so the
#     client drops the handshake.
#
# Fixing the ddclient half (e.g. by querying the LAN router's WAN IP
# rather than a public IP-echo URL) is necessary but not sufficient.
# The full fix is to scope the VPN to specific applications via a
# network namespace (see vopono / `ip netns exec`), or to relocate
# the server-side workloads off the workstation. Tracked in the
# session followups list; no module change yet.
{
  # Add polkit rules for ProtonVPN GUI
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        subject.isInGroup("networkmanager") &&
        (
          action.id.indexOf("org.freedesktop.NetworkManager.") == 0 ||
          action.id.indexOf("org.freedesktop.login1.") == 0
        )
      ) {
        return polkit.Result.YES;
      }
    });

    /* Specifically allow adding VPN connections and kill switch connections */
    polkit.addRule(function(action, subject) {
      if (
        subject.isInGroup("networkmanager") &&
        (action.id == "org.freedesktop.NetworkManager.settings.modify.system" ||
         action.id == "org.freedesktop.NetworkManager.settings.modify.own" ||
         action.id == "org.freedesktop.NetworkManager.enable-disable-network" ||
         action.id == "org.freedesktop.NetworkManager.network-control" ||
         action.id == "org.freedesktop.NetworkManager.wifi.scan")
      ) {
        return polkit.Result.YES;
      }
    });
  '';
}
