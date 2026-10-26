# Home Assistant CLI for assistant.home.arpa.
# The token file is git-secret plaintext under /etc/nixos/secrets.
token_file=/etc/nixos/secrets/homeassistant-token
if [[ ! -r "$token_file" ]]; then
  echo "Error: Cannot read Home Assistant token from $token_file" >&2
  exit 1
fi

export HASS_SERVER="http://assistant.home.arpa"
HASS_TOKEN=$(<"$token_file")
export HASS_TOKEN
if [[ -z "$HASS_TOKEN" ]]; then
  echo "Error: Home Assistant token in $token_file is empty" >&2
  exit 1
fi

exec hass-cli "$@"
