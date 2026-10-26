# ollama CLI pointed at the host on the LAN.
# OLLAMA_DEFAULT_MODEL comes from the system config in ollama.nix.
export OLLAMA_HOST="http://ollama.home.arpa"
exec ollama "$@"
