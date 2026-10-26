{ pkgs, twsPackage, ... }:

{
  home = {
    stateVersion = "23.05";
    username = "dlk";
    homeDirectory = "/home/dlk";

    # This flake tracks nixos-unstable for nixpkgs and home-manager `master`
    # (the correct pairing for an unstable channel). Around each ~biannual
    # release boundary home-manager's `release` label bumps a cycle ahead of
    # nixpkgs' (e.g. HM 26.11 vs nixpkgs 26.05pre-git in May 2026) even though
    # the two are still developed and tested together. The release check is
    # meant for setups that pin a *stable* nixpkgs and must match HM's release
    # branch; for this unstable-tracking config it only produces a false alarm
    # at the boundary, so we disable it.
    enableNixpkgsReleaseCheck = false;
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
    ./docker.nix
    ./helm.nix
    ./keyboard.nix
    ./scripts.nix
    ./sway.nix
    ./tmux.nix
    ./zsh.nix
  ];

  programs = {
    home-manager.enable = true;

    fzf.enable = true;

    # nix-direnv caches flake/direnv evals so `cd` into a project is
    # not a full Nix instantiate. The stock direnv nix hook from ~2023
    # does not.
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Ghostty already installs a bat syntax; without bat itself that
    # setting is inert. fd is the usual counterpart to ripgrep.
    bat.enable = true;
    fd.enable = true;

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
      # gitFull includes git-credential-libsecret so we can keep tokens
      # in gnome-keyring instead of ~/.git-credentials.
      package = pkgs.gitFull;
      lfs.enable = true;
      signing.format = "openpgp";
      settings = {
        user = {
          name = "Daniel Klein";
          email = "othercriteria@gmail.com";
        };
        credential.helper = "libsecret";
      };
    };

    # hosts.yml stays unmanaged (login tokens).
    gh = {
      enable = true;
      settings = {
        git_protocol = "https";
        prompt = "enabled";
        prefer_editor_prompt = "disabled";
        aliases.co = "pr checkout";
      };
    };

    # Zsh aliases ls/ll/la/lt/lla to eza. The flags live on the `eza`
    # alias, which zsh expands again, so `ll` inherits them.
    eza = {
      enable = true;
      enableZshIntegration = true;
      git = true;
      extraOptions = [ "--group-directories-first" ];
    };

    ghostty = {
      enable = true;
      enableZshIntegration = true;
      installBatSyntax = true;

      settings = {
        # Font
        font-family = "Berkeley Mono";
        font-size = 16;
        font-thicken = true; # Slightly bolder for legibility over backgrounds

        # Theme: Catppuccin Mocha for a rich, modern aesthetic
        theme = "Catppuccin Mocha";

        # Window chrome: clean, minimal look
        gtk-titlebar = false;
        window-decoration = false;
        window-padding-x = 8;
        window-padding-y = 6;
        window-padding-balance = true;

        # Cursor: distinctive block cursor with smooth blinking
        cursor-style = "block";
        cursor-style-blink = true;
        cursor-color = "#f5e0dc"; # Catppuccin rosewater
        mouse-hide-while-typing = true;

        # Visual polish: subtle transparency to see wallpaper through
        background-opacity = 0.99;
        unfocused-split-opacity = 0.97;
        minimum-contrast = 1.2; # Boost for legibility with busy backgrounds

        # Splits and panes: nice visual separation
        split-divider-color = "#313244"; # Catppuccin surface0
        resize-overlay = "never";
        confirm-close-surface = false;

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
    gnupg
    ripgrep
    jq
    nvitop
    tree
    unzip
    zip

    python3
    python3Packages.virtualenv
    uv # replaces most ad-hoc virtualenv/pip workflows

    # Creative
    asunder
    blender
    gimp-with-plugins

    # Kubernetes
    argocd
    kubectl
    k9s

    # Raw CLI. `hass` in scripts.nix adds the token and server.
    home-assistant-cli

    amp-cli # Amp (ampcode.com); nixpkgs attr is still amp-cli, binary is `amp`
    claude-code
    codex

    twsPackage # Interactive Brokers TWS (provides `tws` command)

    links2
    pandoc
    texliveFull
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
    kdePackages.ktorrent
    lutris
    maestral
    proton-vpn
    signal-desktop
    slack
    spotify
    vassal
    vlc
    wine
    zoom-us
  ];
}
