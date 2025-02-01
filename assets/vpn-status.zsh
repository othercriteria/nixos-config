#! /usr/bin/env zsh

# XXX: this is hacky, and relies on `protonvpn s` being broken
vpn_status=$(protonvpn s 2>/dev/null | grep -w "Status:" | awk '{print $2}')

if [[ $vpn_status == "Disconnected" ]]; then
    echo '{"text": "  VPN: disconnected"}'
elif (( $? == 1 )); then
    echo '{"text": "  VPN: connected"}'
else
    echo '{"text": "  VPN: error"}'
fi
