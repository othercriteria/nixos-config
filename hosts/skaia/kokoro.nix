# Kokoro TTS Server (a/b candidate alongside F5-TTS in tts.nix)
#
# Provides:
# - Kokoro-FastAPI (Kokoro-82M) in a Docker container on 127.0.0.1:8881
# - GPU-accelerated (RTX 4090) via the upstream PyTorch CUDA image
# - OpenAI-compatible /v1/audio/speech endpoint
#
# Why this lives next to tts.nix instead of replacing it: F5-TTS sounds
# more expressive but has no text-normalization frontend, so it mangles
# numbers/times/dates ("11:39" -> "eleventeen thirty-nine"). Kokoro
# uses the misaki phonemizer with English text normalization built in,
# so the same input renders as "eleven thirty-nine". We keep both
# running for now so we can flip the HA pipeline's TTS engine without
# rebuilds and decide on the basis of real voice-loop usage.
#
# Usage from skaia (raw API check):
#   curl http://127.0.0.1:8881/v1/audio/speech \
#     -H "Content-Type: application/json" \
#     -d '{"model":"kokoro","input":"It is 11:39 in the morning.",
#          "voice":"af_heart","response_format":"mp3"}' \
#     --output /tmp/kokoro.mp3
#
# Wyoming bridge: see assets/wyoming-kokoro.py + voice.nix.
#
# VRAM budget: Kokoro-82M is ~330MB on disk and uses well under 1 GB
# of VRAM at inference time. Comfortably coexists with F5-TTS (~3 GB),
# qwen2.5:14b-instruct-q8_0 (~12 GB), and qwen3:8b-q8_0 (~9 GB) on
# the 24 GB 4090 - everything fits with margin.

_:

{
  virtualisation.oci-containers.backend = "docker";

  virtualisation.oci-containers.containers.kokoro = {
    # Latest published GHCR tag at the time of writing. Upstream does
    # not maintain a floating :latest, so pin explicitly. Bump when we
    # have reason to.
    image = "ghcr.io/remsky/kokoro-fastapi-gpu:v0.2.4-master";

    # CDI device syntax for GPU access (matches tts.nix / streaming.nix)
    extraOptions = [ "--device=nvidia.com/gpu=all" ];

    ports = [
      "127.0.0.1:8881:8880"
    ];

    # No volumes by design: the Kokoro-82M weights and the v1_0 voice
    # tensors are baked into the image, so the container is fully
    # self-contained. Tradeoff: ~330 MB extra image churn on Kokoro
    # version bumps. If we ever want to A/B custom voices or pin
    # specific weights independently of the image, mount
    #   /app/api/src/models      (model weights)
    #   /app/api/src/voices/v1_0 (voice .pt files)
    # and copy the in-image content out once with `docker cp`.

    environment = {
      USE_GPU = "true";
      PYTHONUNBUFFERED = "1";
    };
  };

  # No nginx vhost: Kokoro is consumed locally by the Wyoming bridge
  # in voice.nix. If we ever want LAN/browser access (e.g. for OpenWebUI
  # integration), add a tts-kokoro.home.arpa virtualHost here.
}
