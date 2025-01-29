{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    grim # screenshots
    slurp # screenshots
    wlroots
    wl-clipboard
    playerctl # media control
  ];

  wayland.windowManager.sway = {
    enable = true;

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

  programs.wofi = {
    enable = true;
    style = builtins.readFile ../assets/wofi-styles.css;
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
