#! /usr/bin/env zsh

# Check if NetworkManager is running a ProtonVPN connection (both WireGuard and OpenVPN)
vpn_info=$(nmcli -t -f NAME,TYPE connection show --active | grep -iE "ProtonVPN.*:(wireguard|vpn)$")

if [[ -n "$vpn_info" ]]; then
  # Extract connection name and type
  vpn_name=$(echo "$vpn_info" | cut -d':' -f1)
  connection_type=$(echo "$vpn_info" | cut -d':' -f2)

  # Format server name (remove ProtonVPN prefix if present)
  server_name=$(echo "$vpn_name" | sed 's/^ProtonVPN *//')

  # Capitalize connection type for display
  display_type=$(echo "$connection_type" | sed 's/^vpn$/OpenVPN/' | sed 's/^./\U&/g')

  echo '{"text": "VPN:  '"$server_name"'", "tooltip": "Connection Type: '"$display_type"'", "class": "connected"}'
else
  echo '{"text": "VPN: ", "tooltip": "Not Connected", "class": "disconnected"}'
fi
