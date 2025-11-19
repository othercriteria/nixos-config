{ config, pkgs, ... }:

{
  home = {
    packages = with pkgs; [
      blueman # Bluetooth manager
      grim # screenshots
      playerctl # media control
      pavucontrol # audio control
      slurp # screenshots
      waybar # status bar
      wlroots # Wayland compositor
      wl-clipboard # clipboard manager
      wofi-emoji # emoji picker

      # For UI elements
      font-awesome
      noto-fonts
      noto-fonts-color-emoji

      jq
    ];

    pointerCursor = {
      gtk.enable = true;
      sway.enable = true;
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 32;
    };
  };


  wayland.windowManager.sway = {
    enable = true;

    systemd.enable = true;

    wrapperFeatures.gtk = true;

    extraOptions = [
      "--unsupported-gpu"
    ];

    extraSessionCommands = ''
      # Input method configuration
      export GTK_IM_MODULE=fcitx
      export QT_IM_MODULE=fcitx
      export XMODIFIERS=@im=fcitx
      export SDL_IM_MODULE=fcitx
      export GLFW_IM_MODULE=fcitx
    '';

    config = rec {
      modifier = "Mod4"; # command

      terminal = "alacritty";

      menu = "wofi --allow-images --allow-markup --show run";

      bars = [ ];

      startup = [
        {
          # Ensure the input method daemon is running even when systemd
          # user units are not restarted automatically during activation.
          command = "${config.i18n.inputMethod.package}/bin/fcitx5 -rd";
          always = true;
        }
      ];
    };

    # TODO: the display settings should be host-specific
    extraConfig = ''
      output DP-1 mode 3840x2160@144Hz
      output DP-1 adaptive_sync on
      output DP-1 subpixel rgb

      input * xkb_options caps:escape

      font pango:mono regular 16

      bindsym Print       exec grim ~/screenshots/screenshot_$(date +"%Y-%m-%d_%H-%M-%S").png
      bindsym Print+Shift exec grim -g "$(slurp)" ~/screenshots/screenshot_$(date +"%Y-%m-%d_%H-%M-%S").png

      bindsym XF86AudioRaiseVolume exec 'wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+'
      bindsym XF86AudioLowerVolume exec 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-'
      bindsym XF86AudioMute exec 'wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle'

      # Media control
      bindsym XF86AudioPlay exec playerctl play-pause
      bindsym XF86AudioNext exec playerctl next
      bindsym XF86AudioPrev exec playerctl previous

      # Interactive workspace renaming
      bindsym Mod4+Shift+R exec /etc/nixos/assets/rename-workspace.sh

      # Dismiss all notifications
      bindsym Mod4+Period exec makoctl dismiss -a

      # Emoji picker (overrides existing shortcut for exiting sway)
      bindsym --no-warn Mod4+Shift+E exec wofi-emoji

    '';
  };

  programs = {
    waybar = {
      enable = true;
      systemd = {
        enable = true;
        target = "graphical-session.target";
      };
      style = builtins.readFile ../assets/waybar.css;
      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 34;

          modules-left = [ "sway/workspaces" "wlr/taskbar" "tray" ];
          modules-center = [ "sway/window" ];
          modules-right = [ "pulseaudio" "custom/vpn-status" "network" "memory" "cpu" "temperature" "clock" ];

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
            "format" = "{volume}% {icon}";
            "format-bluetooth" = "{volume}% {icon}";
            "format-muted" = "";
            "format-icons" = {
              "headphone" = "";
              "default" = [ "" "" ];
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
            "format" = "{bandwidthUpBytes}↑{ifname}↓{bandwidthDownBytes}";
            "interface" = "enp67s0";
            "interval" = 5;
          };

          "cpu" = {
            "format" = "{usage}% ";
            "hwmon-path" = "/sys/devices/platform/nct6775.656/hwmon/hwmon14/temp2_input";
            "interval" = 5;
          };

          "memory" = {
            "format" = "{avail:0.1f} GiB ";
            "interval" = 5;
          };
        };
      };
    };

    wofi = {
      enable = true;
      style = builtins.readFile ../assets/wofi.css;
    };
  };

  services.mako = {
    enable = true;
    settings = {
      layer = "overlay";
      font = "monospace 16";
      width = "450";
      height = "200";
      margin = "20";
    };
  };
}
