# Capture the uxplay window. Usage: airplay-snapshot [output.png]
out="${1:-/tmp/airplay-$(date +%s).png}"

geom=$(
  swaymsg -t get_tree |
    jq -r '.. | select(.app_id? == "uxplay") | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"' |
    head -1
)

if [[ -z "$geom" ]]; then
  echo "Error: No uxplay window found. Is AirPlay streaming?" >&2
  exit 1
fi

grim -g "$geom" "$out"
echo "$out"
