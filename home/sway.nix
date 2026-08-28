{ config, pkgs, ... }:

let
  # Spotify 1.2 dropped Freedesktop Notify (and the in-app toggle). Track
  # changes still show up on MPRIS, so this watches playerctl and asks
  # mako to show a banner.
  spotifyNotify = pkgs.writeShellApplication {
    name = "spotify-notify";
    runtimeInputs = [ pkgs.playerctl pkgs.glib pkgs.curl pkgs.coreutils ];
    text = ''
      set -euo pipefail
      cache="''${XDG_CACHE_HOME:-$HOME/.cache}/spotify-notify"
      mkdir -p "$cache"
      last=""
      playerctl -p spotify -F metadata \
        --format $'{{status}}\t{{artist}}\t{{title}}\t{{mpris:artUrl}}' |
      while IFS=$'\t' read -r status artist title art_url; do
        [ "$status" = "Playing" ] || continue
        [ -n "$title" ] || continue
        key="$artist|$title"
        [ "$key" = "$last" ] && continue
        last="$key"

        # libnotify's notify-send leaves app_icon empty and stashes the
        # file in the image-path hint, which mako ignores. Set app_icon
        # (3rd Notify arg) to a real path instead.
        icon=spotify-client
        case "$art_url" in
          file://*)
            path="''${art_url#file://}"
            [ -s "$path" ] && icon="$path"
            ;;
          http://*|https://*)
            cover="$cache/cover.jpg"
            if curl -fsS --max-time 5 -o "$cover.tmp" "$art_url"; then
              mv "$cover.tmp" "$cover"
              icon="$cover"
            fi
            ;;
        esac

        gdbus call --session \
          --dest org.freedesktop.Notifications \
          --object-path /org/freedesktop/Notifications \
          --method org.freedesktop.Notifications.Notify \
          Spotify 42 "$icon" "''${artist:-Spotify}" "$title" \
          '[]' "{'desktop-entry': <'spotify'>, 'urgency': <byte 0>}" \
          5000 >/dev/null
      done
    '';
  };
in
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
      enable = true;
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

      terminal = "ghostty";

      menu = "wofi --allow-images --allow-markup --show run";

      bars = [ ];

      fonts = {
        names = [ "Berkeley Mono" ];
        style = "Regular";
        size = 16.0;
      };

      startup = [
        {
          # Signal UWSM that the compositor is ready and export WAYLAND_DISPLAY
          # (plus plugin vars like SWAYSOCK) into the systemd user environment.
          # Without this, wayland-wm@*.service hits its 10s startup timeout and
          # the graphical session is half-broken — which is why login had to be
          # overridden to plain sway / zsh→sway.
          # Double exec: sway's "exec" + shell replace, per UWSM docs.
          command = "exec ${pkgs.uwsm}/bin/uwsm finalize";
          always = false;
        }
        {
          # Status bar - started via sway rather than systemd since we use
          # UWSM for session management (see systemd.enable comment above)
          # NOTE: 2025-01-10 saw 5 waybar surfaces from 1 process after overnight
          # run - cause unknown, killing waybar resolved. Monitor for recurrence.
          command = "waybar";
          always = false;
        }
        {
          # Notification daemon. Start the user unit rather than exec'ing
          # mako directly: dbus.packages already registers mako.service, so
          # a second process fails to take the Notifications name.
          command = "systemctl --user start --no-block mako.service";
          always = false;
        }
        {
          command = "systemctl --user start --no-block spotify-notify.service";
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

      # Float uxplay window so it maintains video aspect ratio
      for_window [app_id="uxplay"] floating enable
    '';
  };

  programs.wofi = {
    enable = true;
    style = builtins.readFile ../assets/wofi.css;
  };

  systemd.user.services.spotify-notify = {
    Unit = {
      Description = "Desktop notifications for Spotify track changes";
      After = [ "mako.service" ];
    };
    Service = {
      ExecStart = "${spotifyNotify}/bin/spotify-notify";
      Restart = "on-failure";
      RestartSec = "3";
    };
  };

  services.mako = {
    enable = true;
    settings = {
      layer = "overlay";
      font = "Berkeley Mono 16";
      width = 450;
      height = 200;
      margin = 20;
      "background-color" = "#222222";
      "text-color" = "#cccccc";
      "border-color" = "#333333";
      "border-radius" = 8;
      "border-size" = 2;
      icons = true;
      "max-icon-size" = 96;
      # Spotify (and other Electron apps) send expire_timeout=1 ms.
      # Honor our default instead of vanishing the banner immediately.
      "default-timeout" = 8000;
      "ignore-timeout" = 1;
      "app-name=Spotify" = {
        "max-icon-size" = 128;
        "default-timeout" = 5000;
        "ignore-timeout" = 1;
      };
    };
  };
}
