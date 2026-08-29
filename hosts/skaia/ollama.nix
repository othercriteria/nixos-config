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
#   pointed at http://ollama.home.arpa with the qwen3.5:9b-q8_0 model
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

  # Conversation agent for Home Assistant Assist (Phase C of the voice
  # build-out). Wired into HA via the Ollama integration; the model is
  # responsible for parsing free-form user requests, picking the right
  # HA tools, and stitching them together.
  #
  # 2026-08: qwen3:8b-q8_0 -> qwen3.5:9b-q8_0. Same q8 slot (~11 GB
  # weights; a warm Qwen3 8B sat at ~13 GB with KV cache). Qwen3.5 9B
  # is the current 8–9B default and matches the 14b-instruct-q8_0
  # quant we already trust for quality. Official library tag, not a
  # fork. HA's Ollama integration stores the model name in the HA UI
  # (Settings -> Devices & Services -> Ollama) - change it there after
  # apply or Assist keeps calling the old tag.
  #
  # Also used by waybar's weather-emoji vibe script
  # (assets/weather-emoji.py). Sharing one resident model avoids a
  # second VRAM load. The script hardcodes the name (one-off) rather
  # than being wired to a Nix-side reference.
  haAssistantModel = "qwen3.5:9b-q8_0";
in
{
  services.ollama = {
    enable = true;
    # TEMPORARY: CMake 4.2 no longer falls back to PATH when the CUDA setup
    # hook provides a CUDAToolkit_ROOT without nvcc. Remove this override once
    # nixpkgs PR #545542 is included in our pinned revision.
    package = pkgs.ollama-cuda.overrideAttrs (old: {
      preBuild = ''
        unset CUDAToolkit_ROOT
        ${old.preBuild}
      '';
    });
    host = "127.0.0.1"; # Bind localhost; nginx handles LAN exposure
    port = 11434;
    loadModels = [
      defaultModel
      haAssistantModel
    ];
  };

  # Export default model so user scripts can reference it
  environment.sessionVariables = {
    OLLAMA_DEFAULT_MODEL = defaultModel;
  };

  # Ensure ollama CLI is available system-wide
  environment.systemPackages = [ pkgs.ollama ];
}
