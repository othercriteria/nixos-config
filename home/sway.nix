{ config, pkgs, ... }:

{
  imports = [
    ./waybar.nix
  ];

  home = {
    packages = with pkgs; [
      blueman # Bluetooth manager
      grim # screenshots
      playerctl # media control
      pavucontrol # audio control
      slurp # screenshots
      (pkgs.callPackage ../modules/multibg-wayland.nix { }) # per-workspace wallpapers
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

    # Disable home-manager's systemd integration - we use UWSM to manage the
    # Wayland session, which has its own systemd target handling. Using both
    # causes graphical-session.target to never activate properly, breaking
    # services like waybar that depend on it.
    systemd.enable = false;

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

      terminal = "ghostty"; # trialing as Alacritty replacement

      menu = "wofi --allow-images --allow-markup --show run";

      bars = [ ];

      startup = [
        {
          # Status bar - started via sway rather than systemd since we use
          # UWSM for session management (see systemd.enable comment above)
          # NOTE: 2025-01-10 saw 5 waybar surfaces from 1 process after overnight
          # run - cause unknown, killing waybar resolved. Monitor for recurrence.
          command = "waybar";
          always = false;
        }
        {
          # Notification daemon
          command = "mako";
          always = false;
        }
        {
          # Input method daemon
          command = "${config.i18n.inputMethod.package}/bin/fcitx5 -rd";
          always = true;
        }
        {
          # Per-workspace wallpapers from private-assets
          command = "multibg-wayland /etc/nixos/private-assets/wallpapers";
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

      # Alacritty fallback (Mod+Shift+Return) for comparison
      bindsym Mod4+Shift+Return exec alacritty

    '';
  };

  programs.wofi = {
    enable = true;
    style = builtins.readFile ../assets/wofi.css;
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
