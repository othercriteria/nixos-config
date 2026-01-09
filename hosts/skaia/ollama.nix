# Ollama: Local LLM inference with CUDA acceleration
#
# Provides:
# - Ollama service on localhost:11434 (exposed via nginx at ollama.home.arpa)
# - Default model preloaded for immediate use
# - OLLAMA_DEFAULT_MODEL env var for scripts to reference
#
# Usage from LAN:
#   curl http://ollama.home.arpa/api/generate -d '{"model":"qwen2.5:32b","prompt":"Hi"}'
#
# OpenAI-compatible endpoint (for MCP, LangChain, etc.):
#   http://ollama.home.arpa/v1/chat/completions

{ config, pkgs, ... }:

let
  # Default model for preloading and scripts
  # qwen2.5:14b-instruct-q8_0: best latency/quality tradeoff for automation
  # - 14.9GB VRAM (no CPU offload), 52 tok/s, 1.3s MCP latency
  # - "GPT-4o-mini class" quality, q8_0 is essentially lossless
  # - Leaves ~9GB headroom for desktop/streaming workloads
  # For complex reasoning tasks, pull qwen2.5:32b and use ASK_MODEL override
  defaultModel = "qwen2.5:14b-instruct-q8_0";
in
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda; # CUDA acceleration for NVIDIA GPU
    host = "127.0.0.1"; # Bind localhost; nginx handles LAN exposure
    port = 11434;
    loadModels = [ defaultModel ];
  };

  # Export default model so user scripts can reference it
  environment.sessionVariables = {
    OLLAMA_DEFAULT_MODEL = defaultModel;
  };

  # Ensure ollama CLI is available system-wide
  environment.systemPackages = [ pkgs.ollama ];
}
