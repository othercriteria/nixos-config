# Waybar: Status bar configuration
#
# Factored out of sway.nix for maintainability.
# Includes weather+time emoji module using METAR aviation data + local LLM.

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
          "icon-theme" = "Adwaita";
          "tooltip-format" = "{title}";
          "on-click" = "activate";
          "on-click-middle" = "close";
        };

        "pulseaudio" = {
          "interval" = 5;
          "format" = "{volume:3}% {icon}";
          "format-bluetooth" = "{volume:3}% {icon}";
          "format-muted" = "mute {icon}";
          "format-icons" = {
            "headphone" = "";
            "default" = [ "" "" "" ];
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
          "interval" = 5;
        };

        "memory" = {
          "format" = " {avail:5.1f}G ";
          "interval" = 5;
        };

        # Default thermal_zone0 on this host is iwlwifi, not the CPU.
        # k10temp Tctl; hwmon-path-abs stays valid when hwmonN shifts.
        "temperature" = {
          "hwmon-path-abs" = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
          "input-filename" = "temp1_input";
          "critical-threshold" = 90;
          "format" = "{temperatureC}°C";
          "format-critical" = "{temperatureC}°C";
          "tooltip" = true;
        };

        "clock" = {
          "format" = "{:%a %H:%M}";
          "tooltip-format" = "{:%Y-%m-%d}";
          "interval" = 60;
        };

        # Weather + time-of-day vibe as four emojis. Pulls METAR from
        # NOAA, asks Ollama (qwen3:8b-q8_0, the same model HA Assist
        # uses for voice) to translate it into a vibe. The script
        # caches per (METAR, 3-hour-of-day bucket) so most polls return
        # instantly from disk; the LLM only runs when conditions or
        # the time bucket change. 10-minute interval is a balance
        # between art (re-vibe occasionally) and not waking the
        # voice agent's GPU model unnecessarily.
        "custom/vibe" = {
          "exec" = "${pkgs.python3}/bin/python3 /etc/nixos/assets/weather-emoji.py";
          "interval" = 600;
          "return-type" = "json";
          "tooltip" = true;
        };
      };
    };
  };
}
