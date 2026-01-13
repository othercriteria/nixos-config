# TTS Server - OpenAI-compatible text-to-speech
#
# Provides:
# - TTS service on localhost:8880 (exposed via nginx at tts.home.arpa)
# - Piper TTS backend with automatic model unloading after 5 min idle
# - OpenAI-compatible API for agents, Home Assistant, scripts
#
# Usage from LAN:
#   curl http://tts.home.arpa/v1/audio/speech \
#     -H "Content-Type: application/json" \
#     -d '{"input": "Hello world", "voice": "en_US-ryan-medium"}' \
#     --output speech.mp3
#
# Voice samples: https://rhasspy.github.io/piper-samples/

{ config, pkgs, ... }:

{
  imports = [ ../../modules/tts-server.nix ];

  services.tts-server = {
    enable = true;
    host = "127.0.0.1";
    port = 8880;
    keepAlive = 300; # 5 minutes, same as Ollama default
    defaultVoice = "en_US-ryan-medium";
    voices = [
      "en_US-ryan-medium" # Male, clear, good default
      "en_US-lessac-medium" # Female alternative
    ];
  };

  # nginx reverse proxy: tts.home.arpa -> localhost:8880 (LAN only)
  services.nginx.virtualHosts."tts.home.arpa" = {
    listen = [{ addr = "0.0.0.0"; port = 80; }];
    locations."/" = {
      extraConfig = ''
        proxy_pass http://127.0.0.1:8880;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # TTS can take a while for long texts
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;

        # Allow large request bodies for long texts
        client_max_body_size 10M;
      '';
    };
  };

  # Firewall: HTTP is already open for nginx (80/443)
  # No additional ports needed since we proxy through nginx
}
