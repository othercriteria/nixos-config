# libnotify's notify-send leaves app_icon empty and stashes the file in
# the image-path hint, which mako ignores. Set app_icon (3rd Notify arg)
# to a real path instead.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/spotify-notify"
mkdir -p "$cache"
last=""
playerctl -p spotify -F metadata \
  --format $'{{status}}\t{{artist}}\t{{title}}\t{{mpris:artUrl}}' |
  while IFS=$'\t' read -r status artist title art_url; do
    [[ "$status" == "Playing" ]] || continue
    [[ -n "$title" ]] || continue
    key="$artist|$title"
    [[ "$key" == "$last" ]] && continue
    last="$key"

    icon=spotify-client
    case "$art_url" in
      file://*)
        path="${art_url#file://}"
        [[ -s "$path" ]] && icon="$path"
        ;;
      http://* | https://*)
        cover="$cache/cover.jpg"
        if curl -fsS --max-time 5 -o "$cover.tmp" "$art_url"; then
          mv "$cover.tmp" "$cover"
          icon="$cover"
        fi
        ;;
    esac

    gdbus call --session \
      --dest org.freedesktop.Notifications \
      --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.Notify \
      Spotify 42 "$icon" "${artist:-Spotify}" "$title" \
      '[]' "{'desktop-entry': <'spotify'>, 'urgency': <byte 0>}" \
      5000 >/dev/null
  done
