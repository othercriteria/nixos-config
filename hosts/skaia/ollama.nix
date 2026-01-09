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
  # qwen2.5:32b fits well in 24GB VRAM with good quality
  defaultModel = "qwen2.5:32b";
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
