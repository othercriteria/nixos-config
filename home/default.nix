{ pkgs, pkgs-stable, config, ... }:

{
  home = {
    stateVersion = "23.05";
    username = "dlk";
    homeDirectory = "/home/dlk";
  };

  # Use out-of-home cache to avoid nested filesystem mount issues
  xdg.cacheHome = "/fastcache/dlk";

  imports = [
    ./helm.nix
    ./keyboard.nix
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

    git = {
      enable = true;
      lfs.enable = true;
      settings = {
        user = {
          name = "Daniel Klein";
          email = "othercriteria@gmail.com";
        };
        credential.helper = "store";
      };
    };

    vscode = {
      enable = true;
      profiles.default.extensions = with pkgs.vscode-extensions; [
        dracula-theme.theme-dracula
        yzhang.markdown-all-in-one
      ];
    };

    alacritty = {
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
  };

  home.packages = with pkgs; [
    dive
    git-crypt
    git-lfs
    gnupg
    ripgrep
    jq
    nvitop
    tree
    unzip
    zip

    python312Packages.python
    python312Packages.virtualenv

    # Creative
    asunder
    blender
    gimp-with-plugins

    # Kubernetes
    argocd
    kubectl
    k9s

    amp-cli # TODO: migrate to ampcode
    claude-code

    links2
    pandoc
    texlive.combined.scheme-full
    yt-dlp

    code-cursor
    discord
    firefox
    flightgear
    (google-chrome.override {
      commandLineArgs = "--enable-wayland-ime --wayland-text-input-version=3";
    })
    gnome-keyring # For ProtonVPN
    keepassxc
    keybase-gui
    kdePackages.ktorrent
    lutris
    maestral
    protonvpn-gui
    signal-desktop-bin
    slack
    spotify
    (
      let
        vassal-original = vassal;
      in
      pkgs.writeShellScriptBin "vassal-with-env" ''
        export _JAVA_AWT_WM_NONREPARENTING=1
        exec ${vassal-original}/bin/vassal
      ''
    )
    vlc
    warp-terminal
    windsurf
    wine
    zoom-us
  ];
}
