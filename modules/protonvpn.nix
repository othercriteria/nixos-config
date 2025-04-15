{ config, lib, pkgs, ... }:

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
