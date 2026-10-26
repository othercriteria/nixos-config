# Speak text via F5-TTS (HTTP, batch). For streaming input (tail -f),
# use tailsay.
#
# Usage: echo "Hello" | catsay
#        catsay file.txt
#        echo "Hello" | tee /dev/stderr | catsay
tts_url="${TTS_URL:-http://tts.home.arpa}"
tts_voice="${TTS_VOICE:-nature}"
stream=true
input_file=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --voice | -v)
      tts_voice="$2"
      shift 2
      ;;
    --no-stream)
      stream=false
      shift
      ;;
    --help | -h)
      cat <<'EOF'
Usage: catsay [OPTIONS] [FILE]
Speak text via TTS (batch mode with streaming audio output).

Options:
  -v, --voice NAME   Voice to use (default: nature)
  --no-stream        Wait for full audio before playing

For streaming input (tail -f), use 'tailsay' instead.
Use 'tee /dev/stderr' for simultaneous text display.
EOF
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      input_file="$1"
      shift
      ;;
  esac
done

# Temp file avoids the shell argument length limit on long input.
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

if [[ -n "$input_file" ]]; then
  cat -- "$input_file" >"$tmpfile"
else
  cat >"$tmpfile"
fi

if [[ ! -s "$tmpfile" ]]; then
  exit 0
fi

if [[ "$stream" == true ]]; then
  jq -Rs --arg voice "$tts_voice" \
    '{input: ., voice: $voice, stream: true}' "$tmpfile" |
    curl -sN "${tts_url}/v1/audio/speech" \
      -H "Content-Type: application/json" -d @- |
    ffplay -nodisp -autoexit -infbuf -probesize 32 -analyzeduration 0 \
      -f s16le -ar 24000 -ch_layout mono -i pipe:0 >/dev/null 2>&1
else
  jq -Rs --arg voice "$tts_voice" \
    '{input: ., voice: $voice, response_format: "wav"}' "$tmpfile" |
    curl -s "${tts_url}/v1/audio/speech" \
      -H "Content-Type: application/json" -d @- |
    paplay --file-format=wav /dev/stdin 2>/dev/null
fi
