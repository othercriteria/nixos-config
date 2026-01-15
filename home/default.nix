{ pkgs, pkgs-stable, config, twsPackage, ... }:

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

    # Ollama CLI wrapper - auto-configures for network access
    # Uses OLLAMA_DEFAULT_MODEL from system config (set in ollama.nix)
    (pkgs.writeShellScriptBin "oll" ''
      export OLLAMA_HOST="http://ollama.home.arpa"
      exec ${pkgs.ollama}/bin/ollama "$@"
    '')

    # Quick chat helper for interactive use
    # Usage: ask "your question here"
    # Override model with ASK_MODEL env var
    (pkgs.writeShellScriptBin "ask" ''
      MODEL="''${ASK_MODEL:-$OLLAMA_DEFAULT_MODEL}"
      if [ -z "$MODEL" ]; then
        echo "Error: No model specified. Set OLLAMA_DEFAULT_MODEL or ASK_MODEL." >&2
        exit 1
      fi
      export OLLAMA_HOST="http://ollama.home.arpa"
      exec ${pkgs.ollama}/bin/ollama run "$MODEL" "$@"
    '')

    # TTS helper - speak text via F5-TTS (HTTP API, batch mode)
    # Usage: echo "Hello" | catsay
    #        catsay file.txt
    #        echo "Hello" | tee /dev/stderr | catsay  # show + speak
    # For streaming input (tail -f), use tailsay instead
    (pkgs.writeShellScriptBin "catsay" ''
      set -euo pipefail
      TTS_URL="''${TTS_URL:-http://tts.home.arpa}"
      TTS_VOICE="''${TTS_VOICE:-nature}"
      STREAM=true

      # Parse flags
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --voice|-v) TTS_VOICE="$2"; shift 2 ;;
          --no-stream) STREAM=false; shift ;;
          --help|-h)
            echo "Usage: catsay [OPTIONS] [FILE]"
            echo "Speak text via TTS (batch mode with streaming audio output)."
            echo ""
            echo "Options:"
            echo "  -v, --voice NAME   Voice to use (default: nature)"
            echo "  --no-stream        Wait for full audio before playing"
            echo ""
            echo "For streaming input (tail -f), use 'tailsay' instead."
            echo "Use 'tee /dev/stderr' for simultaneous text display."
            exit 0 ;;
          -*) echo "Unknown option: $1" >&2; exit 1 ;;
          *) INPUT_FILE="$1"; shift ;;
        esac
      done

      # Read all input to temp file (avoids shell argument length limits)
      TMPFILE=$(mktemp)
      trap "rm -f '$TMPFILE'" EXIT

      if [[ -n "''${INPUT_FILE:-}" ]]; then
        cat "$INPUT_FILE" > "$TMPFILE"
      else
        cat > "$TMPFILE"
      fi

      # Skip if empty
      [[ ! -s "$TMPFILE" ]] && exit 0

      # Build JSON payload using jq with file input (no arg length limit)
      if [[ "$STREAM" == "true" ]]; then
        ${pkgs.jq}/bin/jq -Rs --arg voice "$TTS_VOICE" \
            '{input: ., voice: $voice, stream: true}' "$TMPFILE" \
          | ${pkgs.curl}/bin/curl -sN "''${TTS_URL}/v1/audio/speech" \
              -H "Content-Type: application/json" -d @- \
          | ${pkgs.ffmpeg}/bin/ffplay -nodisp -autoexit -infbuf -probesize 32 -analyzeduration 0 \
              -f s16le -ar 24000 -ch_layout mono -i pipe:0 >/dev/null 2>&1
      else
        ${pkgs.jq}/bin/jq -Rs --arg voice "$TTS_VOICE" \
            '{input: ., voice: $voice, response_format: "wav"}' "$TMPFILE" \
          | ${pkgs.curl}/bin/curl -s "''${TTS_URL}/v1/audio/speech" \
              -H "Content-Type: application/json" -d @- \
          | ${pkgs.pulseaudio}/bin/paplay --file-format=wav /dev/stdin 2>/dev/null
      fi
    '')

    # tailsay - WebSocket TTS for streaming input (maintains voice context)
    # Usage: tail -f /var/log/messages | tailsay
    #        for i in 1 2 3; do echo "Line $i"; sleep 1; done | tailsay
    # Speaks each line as it arrives, with coherent voice across lines
    (
      let
        tailsayPython = pkgs.writers.writePython3Bin "tailsay-py"
          {
            libraries = [ pkgs.python3Packages.websockets ];
            flakeIgnore = [ "E265" "E501" "W503" ];
          }
          (builtins.readFile ../assets/wscatsay.py);
      in
      pkgs.writeShellScriptBin "tailsay" ''
        export PATH="${pkgs.ffmpeg}/bin:$PATH"
        exec ${tailsayPython}/bin/tailsay-py --line-buffered "$@"
      ''
    )

    amp-cli # TODO: migrate to ampcode
    claude-code

    twsPackage # Interactive Brokers TWS (provides `tws` command)


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
    # TODO: simplify to just `vassal` now that _JAVA_AWT_WM_NONREPARENTING is set
    # globally in hosts/skaia/default.nix
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
