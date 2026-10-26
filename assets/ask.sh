# One-shot chat. Usage: ask "your question here"
# ASK_MODEL overrides OLLAMA_DEFAULT_MODEL from ollama.nix.
model="${ASK_MODEL:-${OLLAMA_DEFAULT_MODEL:-}}"
if [[ -z "$model" ]]; then
  echo "Error: No model specified. Set OLLAMA_DEFAULT_MODEL or ASK_MODEL." >&2
  exit 1
fi

export OLLAMA_HOST="http://ollama.home.arpa"
exec ollama run "$model" "$@"
