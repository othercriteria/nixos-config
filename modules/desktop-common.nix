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
      plugins = with pkgs.xfce; [
        thunar-archive-plugin
        thunar-volman
      ];
    };

    xfconf.enable = true; # Allows Thunar preference to persist without XFCE
  };

  services.gvfs.enable = true;
  services.tumbler.enable = true;

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
