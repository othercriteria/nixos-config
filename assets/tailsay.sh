# WebSocket TTS for streaming input. Voice context holds across lines.
# Usage: tail -f /var/log/messages | tailsay
exec tailsay-py --line-buffered "$@"
