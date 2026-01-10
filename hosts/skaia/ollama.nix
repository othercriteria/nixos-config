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

{ config, pkgs, ... }:

let
  # Default model for interactive use and scripts (ask, MCP, etc.)
  # qwen2.5:14b-instruct-q8_0: best latency/quality tradeoff
  # - ~11GB VRAM, ~0.3s response warm, ~2-3s cold
  # - "GPT-4o-mini class" quality, q8_0 is essentially lossless
  # For complex reasoning tasks, pull qwen2.5:32b and use ASK_MODEL override
  defaultModel = "qwen2.5:14b-instruct-q8_0";

  # Lightweight model for periodic/background tasks (waybar, automation)
  # qwen2.5:3b-instruct-q8_0: minimal VRAM, very fast
  # - 3.7GB VRAM, ~0.31s response
  # - Good instruction-following, sufficient for structured output tasks
  vibeModel = "qwen2.5:3b-instruct-q8_0";
in
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda; # CUDA acceleration for NVIDIA GPU
    host = "127.0.0.1"; # Bind localhost; nginx handles LAN exposure
    port = 11434;
    loadModels = [ defaultModel vibeModel ];
  };

  # Export default model so user scripts can reference it
  environment.sessionVariables = {
    OLLAMA_DEFAULT_MODEL = defaultModel;
  };

  # Ensure ollama CLI is available system-wide
  environment.systemPackages = [ pkgs.ollama ];
}
