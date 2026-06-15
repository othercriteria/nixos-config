{ config, lib, pkgs, ... }:

{
  security = {
    rtkit.enable = true;
    polkit.enable = true;
    pam.loginLimits = [
      { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
    ];
  };

  programs = {
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-curses;
    };

    thunar = {
      enable = true;
      plugins = with pkgs; [
        thunar-archive-plugin
        thunar-volman
      ];
    };

    xfconf.enable = true; # Allows Thunar preference to persist without XFCE
  };

  services = {
    gvfs.enable = true;
    tumbler.enable = true;

    # Power/battery info over D-Bus. Chromium/Electron apps (Chrome, Slack,
    # Cursor, etc.) query UPower's DisplayDevice on startup; if the service is
    # not activatable the D-Bus call times out (NoReply), libdbus hits a
    # "pending != NULL" assertion and aborts the whole process (SIGABRT). Works
    # fine on battery-less desktops (just reports line power).
    upower.enable = true;
  };

  # Enable XDG portal for desktop integration
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.kdePackages.xdg-desktop-portal-kde
      pkgs.xdg-desktop-portal-gnome
    ];
    config = {
      common = {
        default = [ "gtk" ];
      };
      browsers = {
        default = [ "google-chrome-stable" ];
      };
    };
  };
}
