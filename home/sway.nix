{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    blueman # Bluetooth manager
    grim # screenshots
    playerctl # media control
    pavucontrol # audio control
    slurp # screenshots
    waybar # status bar
    wlroots # Wayland compositor
    wl-clipboard # clipboard manager

    # For UI elements
    font-awesome
    noto-fonts
    noto-fonts-emoji
  ];

  wayland.windowManager.sway = {
    enable = true;

    systemd.enable = true;

    wrapperFeatures.gtk = true;

    extraOptions = [
      "--unsupported-gpu"
    ];

    config = rec {
      modifier = "Mod4"; # command

      terminal = "alacritty";

      menu = "wofi --allow-images --allow-markup --show run";
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
    '';
  };

  programs = {
    waybar = {
      enable = true;
      systemd = {
        enable = true;
        target = "sway-session.target";
      };
      style = builtins.readFile ../assets/waybar.css;
      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 34;

          modules-left = [ "sway/workspaces" "sway/mode" "wlr/taskbar" "tray" ];
          modules-center = [ "sway/window" ];
          modules-right = [ "custom/vpn-status" "pulseaudio" "memory" "cpu" "temperature" "clock" ];

          "sway/workspaces" = {
            disable-scroll = true;
            all-outputs = true;
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
            "exec" = "${pkgs.zsh}/bin/zsh -c '/etc/nixos/assets/vpn-status.zsh'";
            "interval" = 5;
            "return-type" = "json";
          };

          "cpu" = {
            "format" = "{usage}% ";
            "interval" = 5;
          };

          "memory" = {
            "format" = "{used}/{total} GiB ";
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
    layer = "overlay";
    font = "monospace 16";
    width = 450;
    height = 200;
    margin = "20";
  };
}
