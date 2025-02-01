#!/usr/bin/env bash

# XXX: this is hacky, and relies on `protonvpn s` being broken
status=$(protonvpn s 2>/dev/null | grep "Status:" | awk '{print $2}')
if [ "$status" = "Disconnected" ]; then
    echo "{\"text\": \" VPN: disconnected\"}"
elif [ $? -eq 1 ]; then
    echo "{\"text\": \" VPN: connected\"}"
else
    echo "{\"text\": \" VPN: error\"}"
fi
