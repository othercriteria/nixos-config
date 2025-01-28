{ pkgs, config, ... }:

{
  home = {
    stateVersion = "23.05";
    username = "dlk";
    homeDirectory = "/home/dlk";
  };

  imports = [
    ./tmux.nix
    ./zsh.nix
  ];

  programs = {
    home-manager.enable = true;

    fzf.enable = true;

    direnv.enable = true;

    zathura = {
      enable = true;
      extraConfig = builtins.readFile ../assets/zathura-config.txt;
      options = {
        font = "Berkeley Mono 16";
      };
    };

    emacs = {
      enable = true;
      extraPackages = epkgs: [ epkgs.nix-mode ];
    };
  };

  home.packages = with pkgs; [
    dive
    git-crypt
    git-lfs
    gnupg
    ripgrep
    jq
    nvtopPackages.full
    tree
    unzip
    zip

    grim # screenshots
    slurp # screenshots
    wlroots
    wl-clipboard

    python312Packages.python
    python312Packages.virtualenv

    # Creative
    asunder
    blender
    # gimp-with-plugins # XXX: commenting out due to broken build

    kubectl
    (wrapHelm kubernetes-helm {
      plugins = with pkgs.kubernetes-helmPlugins; [
        helm-secrets
        helm-diff
        helm-s3
        helm-git
      ];
    })

    links2
    pandoc
    texlive.combined.scheme-full
    yt-dlp

    code-cursor
    discord
    firefox-wayland
    flightgear
    google-chrome
    keepassxc
    keybase-gui
    ktorrent
    lutris
    maestral
    slack
    spotify
    veracrypt
    vlc
    warp-terminal
    zoom-us
  ];

  programs.git = {
    enable = true;
    userName = "Daniel Klein";
    userEmail = "othercriteria@gmail.com";
    lfs.enable = true;
    extraConfig = {
      credential.helper = "store";
    };
  };

  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      dracula-theme.theme-dracula
      yzhang.markdown-all-in-one
    ];
  };

  programs.alacritty = {
    enable = true;
    settings = {
      env = {
        # XXX: can we be using wayland-0?
        WAYLAND_DISPLAY = "wayland-1";
      };
      font = {
        normal = {
          family = "Berkeley Mono";
          style = "Regular";
        };
        size = 16;
      };
    };
  };

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
      output DP-1 mode 3840x2160@119.998Hz
      output DP-1 adaptive_sync on
      output DP-1 subpixel rgb

      input * xkb_options caps:escape

      font pango:mono regular 16

      bindsym Print       exec grim ~/screenshots/screenshot_$(date +"%Y-%m-%d_%H-%M-%S").png
      bindsym Print+Shift exec grim -g "$(slurp)" ~/screenshots/screenshot_$(date +"%Y-%m-%d_%H-%M-%S").png

      bindsym XF86AudioRaiseVolume exec 'wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+'
      bindsym XF86AudioLowerVolume exec 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-'
      bindsym XF86AudioMute exec 'wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle'
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

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    x11 = {
      enable = true;
      defaultCursor = "Adwaita";
    };
  };
}
