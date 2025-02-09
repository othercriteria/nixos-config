{ pkgs, pkgs-stable, config, ... }:

{
  home = {
    stateVersion = "23.05";
    username = "dlk";
    homeDirectory = "/home/dlk";
  };

  imports = [
    ./sway.nix
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

    python312Packages.python
    python312Packages.virtualenv

    # Creative
    asunder
    blender
    gimp-with-plugins

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
