# Ollama: Local LLM inference with CUDA acceleration
#
# Provides:
# - Ollama service on localhost:11434 (exposed via nginx at ollama.home.arpa)
# - Models preloaded for immediate use
# - OLLAMA_DEFAULT_MODEL env var for scripts to reference
#
# Usage from LAN:
#   curl http://ollama.home.arpa/api/generate -d '{"model":"qwen2.5:14b-instruct-q8_0","prompt":"Hi"}'
#
# OpenAI-compatible endpoint (for MCP, LangChain, etc.):
#   http://ollama.home.arpa/v1/chat/completions
#
# Used by:
# - Home Assistant Assist (Settings -> Devices & Services -> Ollama),
#   pointed at http://ollama.home.arpa with the qwen3:8b-q8_0 model
#   (see haAssistantModel below). HA's CoreDNS forwards home.arpa to
#   skaia's unbound (set on the HA Yellow via `ha dns options
#   --servers dns://192.168.0.160`), so the Ollama integration container
#   resolves the FQDN natively - no need to broaden the bind address.
# - Local scripts (ask, MCP, waybar, etc.) via $OLLAMA_DEFAULT_MODEL.

{ pkgs, ... }:

let
  # Default model for interactive use and scripts (ask, MCP, etc.)
  # qwen2.5:14b-instruct-q8_0: best latency/quality tradeoff
  # - ~11GB VRAM, ~0.3s response warm, ~2-3s cold
  # - "GPT-4o-mini class" quality, q8_0 is essentially lossless
  # For complex reasoning tasks, pull qwen2.5:32b and use ASK_MODEL override
  defaultModel = "qwen2.5:14b-instruct-q8_0";

  # Lightweight model for periodic/background tasks (waybar, automation)
  # llama3.2:3b: smallest VRAM, fast, no Chinese character issues
  # - 2.8GB VRAM, ~0.27s response
  # - Better instruction-following for emoji-only output than Qwen
  vibeModel = "llama3.2:3b";

  # Conversation agent for Home Assistant Assist (Phase C of the voice
  # build-out). Wired into HA via the Ollama integration; the model is
  # responsible for parsing free-form user requests, picking the right
  # HA tools, and stitching them together. Picked qwen3:8b-q8_0
  # because as of mid-2026 the local-LLM-for-HA community has converged
  # on Qwen3 8B as the sweet spot in the ~8B class for tool calling
  # (better than Llama 3.1 8B, and the q8_0 variant fits comfortably
  # in our remaining ~12 GB VRAM headroom alongside the qwen2.5:14b
  # default model). Trade up to qwen3:14b or qwen2.5:32b if multi-step
  # reasoning ever blocks us; trade down to phi-4-mini if we want to
  # see how snappy a smaller model can be.
  haAssistantModel = "qwen3:8b-q8_0";
in
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda; # CUDA acceleration for NVIDIA GPU
    host = "127.0.0.1"; # Bind localhost; nginx handles LAN exposure
    port = 11434;
    loadModels = [ defaultModel vibeModel haAssistantModel ];
  };

  # Export default model so user scripts can reference it
  environment.sessionVariables = {
    OLLAMA_DEFAULT_MODEL = defaultModel;
  };

  # Ensure ollama CLI is available system-wide
  environment.systemPackages = [ pkgs.ollama ];
}
