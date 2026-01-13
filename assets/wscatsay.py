#!/usr/bin/env python3
"""
WebSocket TTS client - bidirectional streaming text-to-speech.

Reads text from stdin (or file), sends to TTS server via WebSocket,
and plays audio in real-time as it's generated. Maintains voice context
across the entire session for coherent synthesis.

Usage:
    echo "Hello world" | wscatsay
    tail -f /var/log/messages | wscatsay
    wscatsay < document.txt
"""

import argparse
import asyncio
import os
import signal
import subprocess
import sys

# Handle missing websockets gracefully
try:
    import websockets
except ImportError:
    print("Error: websockets library not found", file=sys.stderr)
    print("This should be provided by the Nix environment", file=sys.stderr)
    sys.exit(1)


async def stream_tts(
    url: str,
    voice: str,
    speed: float,
    input_stream,
    line_buffered: bool = False,
):
    """
    Connect to TTS WebSocket and stream text in, audio out.

    When line_buffered=True, also enables line_mode on the server
    (split on newlines instead of sentence boundaries).
    """
    # Build WebSocket URL with query params
    line_mode = "true" if line_buffered else "false"
    ws_url = f"{url}/v1/audio/stream?voice={voice}&speed={speed}&line_mode={line_mode}"

    # Start ffplay for audio output
    ffplay = subprocess.Popen(
        [
            "ffplay",
            "-nodisp",
            "-autoexit",
            "-infbuf",
            "-probesize", "32",
            "-analyzeduration", "0",
            "-f", "s16le",
            "-ar", "24000",
            "-ch_layout", "mono",
            "-i", "pipe:0",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        async with websockets.connect(ws_url) as ws:
            # Receive session start message
            msg = await ws.recv()
            if isinstance(msg, str):
                import json
                info = json.loads(msg)
                if info.get("type") == "error":
                    print(f"Error: {info.get('message')}", file=sys.stderr)
                    return

            async def send_text():
                """Read stdin and send text to WebSocket."""
                loop = asyncio.get_event_loop()

                if line_buffered:
                    # Line-buffered mode: send each line as it arrives
                    while True:
                        line = await loop.run_in_executor(
                            None, input_stream.readline
                        )
                        if not line:
                            break
                        await ws.send(line)
                else:
                    # Batch mode: read all, send in chunks
                    while True:
                        chunk = await loop.run_in_executor(
                            None, lambda: input_stream.read(4096)
                        )
                        if not chunk:
                            break
                        await ws.send(chunk)

                # Signal end of input
                await ws.send("")

            async def receive_audio():
                """Receive audio from WebSocket and pipe to ffplay."""
                try:
                    async for msg in ws:
                        if isinstance(msg, bytes):
                            # Binary = PCM audio
                            if ffplay.stdin:
                                ffplay.stdin.write(msg)
                                ffplay.stdin.flush()
                        elif isinstance(msg, str):
                            # Text = JSON control message
                            import json
                            try:
                                info = json.loads(msg)
                                if info.get("type") == "session_end":
                                    break
                                elif info.get("type") == "error":
                                    print(
                                        f"Error: {info.get('message')}",
                                        file=sys.stderr
                                    )
                                    break
                            except json.JSONDecodeError:
                                pass
                except websockets.exceptions.ConnectionClosed:
                    pass

            # Run send and receive concurrently
            await asyncio.gather(
                send_text(),
                receive_audio(),
            )

    finally:
        # Clean up ffplay
        if ffplay.stdin:
            ffplay.stdin.close()
        ffplay.wait()


def main():
    parser = argparse.ArgumentParser(
        description="WebSocket TTS client with bidirectional streaming"
    )
    parser.add_argument(
        "-v", "--voice",
        default=os.environ.get("TTS_VOICE", "nature"),
        help="Voice name (default: nature)",
    )
    parser.add_argument(
        "-s", "--speed",
        type=float,
        default=1.0,
        help="Speed multiplier (default: 1.0)",
    )
    parser.add_argument(
        "-l", "--line-buffered",
        action="store_true",
        help="Send each line as it arrives (for tail -f)",
    )
    parser.add_argument(
        "file",
        nargs="?",
        type=argparse.FileType("r"),
        default=sys.stdin,
        help="Input file (default: stdin)",
    )

    args = parser.parse_args()

    # Get TTS URL
    tts_url = os.environ.get("TTS_URL", "http://tts.home.arpa")
    # Convert http to ws
    ws_url = tts_url.replace("http://", "ws://").replace("https://", "wss://")

    # Handle Ctrl+C gracefully
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

    try:
        asyncio.run(
            stream_tts(
                ws_url,
                args.voice,
                args.speed,
                args.file,
                args.line_buffered,
            )
        )
    except BrokenPipeError:
        pass
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
