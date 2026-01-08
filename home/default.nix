{ pkgs, pkgs-stable, config, ... }:

{
  home = {
    stateVersion = "23.05";
    username = "dlk";
    homeDirectory = "/home/dlk";
  };

  # Use out-of-home cache to avoid nested filesystem mount issues
  xdg.cacheHome = "/fastcache/dlk";

  # Disable automatic systemd user service restarts during home-manager activation.
  # This prevents activation failures from services like fcitx5 that need a display.
  # Since we use UWSM for session management (which doesn't activate home-manager's
  # graphical-session.target), we start all graphical services via sway's startup
  # config in sway.nix instead.
  systemd.user.startServices = false;

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

    # Ghostty: modern GPU-accelerated terminal (trialing as Alacritty replacement)
    ghostty = {
      enable = true;
      enableZshIntegration = true;
      installBatSyntax = true;

      settings = {
        # Font: match Alacritty setup
        font-family = "Berkeley Mono";
        font-size = 16;
        font-thicken = true; # Slightly bolder for legibility over backgrounds

        # Theme: Catppuccin Mocha for a rich, modern aesthetic
        theme = "Catppuccin Mocha";

        # Window chrome: clean, minimal look
        gtk-titlebar = false;
        window-padding-x = 8;
        window-padding-y = 6;
        window-padding-balance = true;

        # Cursor: distinctive block cursor with smooth blinking
        cursor-style = "block";
        cursor-style-blink = true;
        cursor-color = "#f5e0dc"; # Catppuccin rosewater

        # Visual polish: subtle transparency to see wallpaper through
        background-opacity = 0.98;
        unfocused-split-opacity = 0.96;
        minimum-contrast = 1.2; # Boost for legibility with busy backgrounds

        # Splits and panes: nice visual separation
        split-divider-color = "#313244"; # Catppuccin surface0

        # Shell integration for rich features (prompt marks, etc.)
        shell-integration = "zsh";
        shell-integration-features = "cursor,sudo,title";

        # Scrollback
        scrollback-limit = 50000;

        # Copy/paste behavior
        copy-on-select = "clipboard";
        clipboard-paste-protection = true;

        # Performance: ensure GPU rendering
        gtk-single-instance = true;

        # Links: clickable URLs
        link-url = true;

        # Bell: visual flash only, no audio
        bell-features = "no-audio";

        # Use xterm-256color for better SSH compatibility
        # (remote hosts often lack xterm-ghostty terminfo)
        term = "xterm-256color";
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

    # Home Assistant CLI for agent access
    # Use 'hass' wrapper which auto-loads token from secrets
    home-assistant-cli
    (pkgs.writeShellScriptBin "hass" ''
      export HASS_SERVER="http://assistant.home.arpa"
      export HASS_TOKEN="$(cat /etc/nixos/secrets/homeassistant-token 2>/dev/null)"
      if [ -z "$HASS_TOKEN" ]; then
        echo "Error: Cannot read Home Assistant token from /etc/nixos/secrets/homeassistant-token" >&2
        exit 1
      fi
      exec ${pkgs.home-assistant-cli}/bin/hass-cli "$@"
    '')

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
