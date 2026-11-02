# Waybar: Status bar configuration
#
# Factored out of sway.nix for maintainability.
# Includes weather+time emoji module using METAR aviation data + local LLM.

{ config, pkgs, ... }:

let
  # Store copy, same source the systemd timer runs. Waybar must not
  # exec /etc/nixos/... here: a stale checkout would ignore `show`
  # and call Ollama on every poll.
  weatherEmoji = pkgs.writeText "weather-emoji.py" (builtins.readFile ../assets/weather-emoji.py);
in
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

        modules-left = [
          "sway/workspaces"
          "wlr/taskbar"
          "tray"
        ];
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
            "default" = [
              ""
              ""
              ""
            ];
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

        # Weather + time-of-day vibe as four emojis. This exec is
        # show-only: it reads the snapshot published by
        # weather-emoji.timer and never calls Ollama. The timer is a
        # member of ollama-background.target (hosts/skaia/ollama.nix);
        # `ollama-background stop` parks it and the module goes dim.
        # One minute is just how fast the bar notices a toggle or a
        # new snapshot. The model runs at most every 10 minutes, and
        # only on a cache miss.
        "custom/vibe" = {
          "exec" = "${pkgs.python3}/bin/python3 ${weatherEmoji} show";
          "interval" = 60;
          "return-type" = "json";
          "tooltip" = true;
        };
      };
    };
  };
}
