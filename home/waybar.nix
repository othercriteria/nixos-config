# Waybar: Status bar configuration
#
# Factored out of sway.nix for maintainability.
# Includes weather+time emoji module using Open-Meteo API.

{ config, pkgs, ... }:

{
  programs.waybar = {
    enable = true;
    # Disabled: we start waybar via sway's startup config instead of systemd
    # because UWSM manages our Wayland session and home-manager's systemd
    # targets don't activate properly with UWSM.
    systemd.enable = false;
    style = builtins.readFile ../assets/waybar.css;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 34;

        modules-left = [ "sway/workspaces" "wlr/taskbar" "tray" ];
        modules-center = [ "sway/window" ];
        modules-right = [
          "pulseaudio"
          "custom/vpn-status"
          "network"
          "memory"
          "cpu"
          "temperature"
          "custom/vibe"
          "clock"
        ];

        "sway/workspaces" = {
          disable-scroll = true;
          all-outputs = true;
        };

        "wlr/taskbar" = {
          "format" = "{icon}";
          "icon-size" = 16;
          "icon-theme" = "hicolor";
          "tooltip-format" = "{title}";
          "on-click" = "activate";
          "on-click-middle" = "close";
        };

        "pulseaudio" = {
          "interval" = 5;
          "format" = " {volume:3}% {icon}";
          "format-bluetooth" = " {volume:3}% {icon}";
          "format-muted" = "    ";
          "format-icons" = {
            "headphone" = "";
            "default" = [ "" "" ];
          };
          "scroll-step" = 1;
          "on-click" = "${pkgs.pavucontrol}/bin/pavucontrol";
        };

        "tray" = {
          "icon-size" = 16;
          "spacing" = 10;
        };

        "custom/vpn-status" = {
          "exec" = "${pkgs.zsh}/bin/zsh -c '/etc/nixos/assets/nm-vpn-status.zsh'";
          "interval" = 5;
          "return-type" = "json";
        };

        "network" = {
          "format" = " {bandwidthUpBytes}↑{ifname}↓{bandwidthDownBytes}";
          "interface" = "enp67s0";
          "interval" = 5;
        };

        "cpu" = {
          "format" = " {usage:3}% ";
          "hwmon-path" = "/sys/devices/platform/nct6775.656/hwmon/hwmon14/temp2_input";
          "interval" = 5;
        };

        "memory" = {
          "format" = " {avail:5.1f}G ";
          "interval" = 5;
        };

        # Weather + time-of-day vibe as three emojis
        # Uses Open-Meteo API + local Ollama LLM for creative emoji selection
        "custom/vibe" = {
          "exec" = "${pkgs.python3}/bin/python3 /etc/nixos/assets/weather-emoji.py";
          "interval" = 120; # Update every 2 minutes
          "return-type" = "json";
          "tooltip" = true;
        };
      };
    };
  };
}
