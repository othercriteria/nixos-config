# TTS Server - OpenAI-compatible text-to-speech with F5-TTS
#
# Provides:
# - High-quality neural TTS via F5-TTS in Docker container
# - GPU-accelerated (RTX 4090) with automatic VRAM unloading after idle
# - OpenAI-compatible API at tts.home.arpa
#
# Usage from LAN:
#   curl http://tts.home.arpa/v1/audio/speech \
#     -H "Content-Type: application/json" \
#     -d '{"input": "Hello world", "voice": "nature"}' \
#     --output speech.mp3
#
# Adding voices:
#   Place in /var/lib/tts/voices/:
#   - {name}.wav  - 5-15 second reference audio
#   - {name}.txt  - exact transcript of the audio

{ config, pkgs, ... }:

let
  # TTS server script (runs inside container)
  ttsServerScript = pkgs.writeText "tts-server.py" (builtins.readFile ../../assets/tts-server.py);

  # Default voice: bundled F5-TTS example (nature/mother nature voice)
  # This provides a working default without any manual setup
  defaultVoiceText = "Some call me nature, others call me mother nature.";
in
{
  # Use Docker backend (shared with streaming.nix)
  virtualisation.oci-containers.backend = "docker";

  # F5-TTS container
  virtualisation.oci-containers.containers.tts = {
    image = "f5-tts:latest";

    # CDI device syntax for GPU access (not --gpus)
    extraOptions = [ "--device=nvidia.com/gpu=all" ];

    ports = [
      "127.0.0.1:8880:8880" # TTS API - localhost only, nginx proxies
    ];

    volumes = [
      # Mount TTS server script
      "${ttsServerScript}:/app/tts-server.py:ro"
      # Voice reference files
      "/var/lib/tts/voices:/voices:ro"
      # HuggingFace cache for model weights (persist across restarts)
      # Note: Must mount to /hub specifically to override Dockerfile VOLUME
      "/var/lib/tts/hf-cache:/root/.cache/huggingface/hub:rw"
    ];

    environment = {
      TTS_HOST = "0.0.0.0";
      TTS_PORT = "8880";
      TTS_KEEP_ALIVE = "300"; # 5 minutes idle -> unload from VRAM
      TTS_VOICE = "nature"; # Default voice
      TTS_VOICES_DIR = "/voices";
    };

    # Run our server script instead of default Gradio app
    cmd = [ "python3" "/app/tts-server.py" ];

    # Depend on voices being set up
    dependsOn = [ ];
  };

  # Create data directories and default voice
  systemd.tmpfiles.rules = [
    "d /var/lib/tts 0755 root root -"
    "d /var/lib/tts/voices 0755 root root -"
    "d /var/lib/tts/hf-cache 0755 root root -"
  ];

  # One-shot service to set up default voice from F5-TTS examples
  # This copies the built-in example voice so the service works out of the box
  systemd.services.tts-setup-voices = {
    description = "Set up default TTS voice";
    wantedBy = [ "docker-tts.service" ];
    before = [ "docker-tts.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Create default "nature" voice if it doesn't exist
      if [ ! -f /var/lib/tts/voices/nature.wav ]; then
        echo "Setting up default voice..."

        # Extract example audio from the F5-TTS container
        ${pkgs.docker}/bin/docker run --rm \
          -v /var/lib/tts/voices:/out \
          f5-tts:latest \
          cp /workspace/F5-TTS/src/f5_tts/infer/examples/basic/basic_ref_en.wav /out/nature.wav

        # Create transcript file
        echo "${defaultVoiceText}" > /var/lib/tts/voices/nature.txt

        echo "Default voice 'nature' created"
      else
        echo "Default voice already exists"
      fi
    '';
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

        # F5-TTS can take a while for long texts + model loading
        proxy_read_timeout 180s;
        proxy_send_timeout 180s;

        # Allow large request bodies for long texts
        client_max_body_size 10M;
      '';
    };
  };

  # Firewall: HTTP is already open for nginx (80/443)
  # No additional ports needed since we proxy through nginx
}
