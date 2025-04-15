#! /usr/bin/env zsh

# Check if NetworkManager is running a ProtonVPN wireguard connection
vpn_connection=$(nmcli -t -f NAME,TYPE connection show --active | grep -E ":wireguard$" | grep -i "ProtonVPN" | cut -d':' -f1)

if [[ -n "$vpn_connection" ]]; then
  server_name=$(echo "$vpn_connection" | sed 's/^ProtonVPN //')

  echo '{"text": "VPN:  '"$server_name"'", "class": "connected"}'
else
  echo '{"text": "VPN: ", "class": "disconnected"}'
fi
