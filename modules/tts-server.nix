# TTS Server - OpenAI-compatible TTS with Ollama-style model management
#
# Provides:
# - OpenAI-compatible API at /v1/audio/speech
# - Piper TTS backend (fast, ~150 voices)
# - Lazy model loading with automatic unload after idle timeout
# - Declarative voice provisioning (auto-downloads on first boot)
#
# Usage:
#   curl http://tts.home.arpa/v1/audio/speech \
#     -H "Content-Type: application/json" \
#     -d '{"input": "Hello world", "voice": "en_US-ryan-medium"}' \
#     --output speech.mp3
#
# Voice samples: https://rhasspy.github.io/piper-samples/

{ config, lib, pkgs, ... }:

let
  cfg = config.services.tts-server;

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
  ]);

  ttsServerScript = pkgs.writeScriptBin "tts-server" ''
    #!${pythonEnv}/bin/python3
    ${builtins.readFile ../assets/tts-server.py}
  '';

  # Map voice name to Hugging Face URL components
  # Voice naming: {lang}_{region}-{name}-{quality}
  # Example: en_US-ryan-medium -> en/en_US/ryan/medium/en_US-ryan-medium
  voiceToUrl = voice:
    let
      # Parse voice name: en_US-ryan-medium
      parts = builtins.match "([a-z]+)_([A-Z]+)-([a-z]+)-([a-z]+)" voice;
      lang = builtins.elemAt parts 0; # en
      region = builtins.elemAt parts 1; # US
      name = builtins.elemAt parts 2; # ryan
      quality = builtins.elemAt parts 3; # medium
      langRegion = "${lang}_${region}"; # en_US
      basePath = "${lang}/${langRegion}/${name}/${quality}/${voice}";
      baseUrl = "https://huggingface.co/rhasspy/piper-voices/resolve/main";
    in
    {
      onnx = "${baseUrl}/${basePath}.onnx";
      json = "${baseUrl}/${basePath}.onnx.json";
    };

  # Generate download script for all configured voices
  downloadScript = pkgs.writeShellScript "tts-download-voices" ''
    set -euo pipefail
    VOICES_DIR="${cfg.dataDir}/voices"
    mkdir -p "$VOICES_DIR"

    ${lib.concatMapStringsSep "\n" (voice:
      let urls = voiceToUrl voice; in ''
        if [ ! -f "$VOICES_DIR/${voice}.onnx" ]; then
          echo "Downloading voice: ${voice}"
          ${pkgs.curl}/bin/curl -fsSL -o "$VOICES_DIR/${voice}.onnx" "${urls.onnx}"
          ${pkgs.curl}/bin/curl -fsSL -o "$VOICES_DIR/${voice}.onnx.json" "${urls.json}"
        else
          echo "Voice already present: ${voice}"
        fi
      ''
    ) cfg.voices}

    echo "All voices ready"
  '';

in
{
  options.services.tts-server = with lib; {
    enable = mkEnableOption "TTS server with OpenAI-compatible API";

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host to bind the server to";
    };

    port = mkOption {
      type = types.port;
      default = 8880;
      description = "Port to bind the server to";
    };

    keepAlive = mkOption {
      type = types.int;
      default = 300;
      description = "Seconds to keep model loaded after last request (0 = never unload)";
    };

    defaultVoice = mkOption {
      type = types.str;
      default = "en_US-ryan-medium";
      description = "Default Piper voice name";
    };

    voices = mkOption {
      type = types.listOf types.str;
      default = [ "en_US-ryan-medium" ];
      example = [ "en_US-ryan-medium" "en_US-lessac-medium" "en_GB-alan-medium" ];
      description = ''
        List of Piper voices to download. Format: {lang}_{REGION}-{name}-{quality}
        Browse available voices at https://rhasspy.github.io/piper-samples/
      '';
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/tts";
      description = "Directory for voice models and data";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure defaultVoice is in the voices list
    assertions = [{
      assertion = builtins.elem cfg.defaultVoice cfg.voices;
      message = "services.tts-server.defaultVoice must be included in services.tts-server.voices";
    }];

    systemd.services.tts-server = {
      description = "OpenAI-compatible TTS server";
      after = [ "network-online.target" "tts-download-voices.service" ];
      wants = [ "network-online.target" "tts-download-voices.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        TTS_HOST = cfg.host;
        TTS_PORT = toString cfg.port;
        TTS_KEEP_ALIVE = toString cfg.keepAlive;
        TTS_VOICE = cfg.defaultVoice;
        TTS_DATA_DIR = cfg.dataDir;
        PIPER_PATH = "${pkgs.piper-tts}/bin/piper";
        FFMPEG_PATH = "${pkgs.ffmpeg}/bin/ffmpeg";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${ttsServerScript}/bin/tts-server";
        Restart = "on-failure";
        RestartSec = "5s";

        # Run as dedicated user
        DynamicUser = true;
        User = "tts";
        Group = "tts";

        # State directory
        StateDirectory = "tts";
        StateDirectoryMode = "0755";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = false; # Python JIT needs this

        # Allow network binding
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      };
    };

    # Download voices before starting the server
    systemd.services.tts-download-voices = {
      description = "Download TTS voice models";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = downloadScript;

        # Same user/state as main service
        DynamicUser = true;
        User = "tts";
        Group = "tts";
        StateDirectory = "tts";
        StateDirectoryMode = "0755";

        # Allow network for downloads
        PrivateNetwork = false;
      };
    };

    # Ensure piper and ffmpeg are available system-wide for debugging
    environment.systemPackages = [
      pkgs.piper-tts
      pkgs.ffmpeg
    ];
  };
}
