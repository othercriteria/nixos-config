#!/usr/bin/env python3
"""Wyoming TTS server backed by the local F5-TTS HTTP server.

Bridges Home Assistant's Wyoming Protocol integration to the existing
OpenAI-compatible F5-TTS server (assets/tts-server.py, exposed at
http://localhost:8880 on skaia, and via nginx at http://tts.home.arpa).

Pipeline:

  HA (Wyoming Synthesize)
    -> this server: POST F5-TTS /v1/audio/speech with stream=True
    -> read raw PCM s16le mono 24kHz chunks
    -> forward each as Wyoming AudioChunk events
    -> emit AudioStart at the beginning, AudioStop at the end

This is intentionally a thin protocol translator: no buffering, no
re-encoding. F5-TTS's streaming chunk size (~340ms) is forwarded
verbatim.

Cold starts: F5-TTS lazily loads its model on first request (~5-10s on
GPU). The Wyoming client (HA) just waits during that window. Subsequent
requests are warm. We do not pre-warm here; pre-warming would extend
service startup time and add little value because HA also blocks on the
first request anyway.

Voices: F5-TTS reads voice reference files from /var/lib/tts/voices/.
This wrapper does not introspect the directory; it advertises a fixed
list of voices (default: ["nature"]) passed via --voices. Add new voices
by extending the CLI flag once the underlying .wav/.txt files exist.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
from functools import partial

import httpx
from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.event import Event
from wyoming.info import Attribution, Describe, Info, TtsProgram, TtsVoice
from wyoming.server import AsyncEventHandler, AsyncServer
from wyoming.tts import Synthesize

LOG = logging.getLogger("wyoming-f5-tts")

# F5-TTS streams native PCM at this format. Hardcoded; F5-TTS won't change it.
SAMPLE_RATE_HZ = 24000
SAMPLE_WIDTH_BYTES = 2  # s16le
CHANNELS = 1


class F5TTSHandler(AsyncEventHandler):
    """Per-connection Wyoming handler that proxies Synthesize -> F5-TTS."""

    def __init__(
        self,
        *args,
        f5_url: str,
        voices: list[str],
        default_voice: str,
        **kwargs,
    ) -> None:
        super().__init__(*args, **kwargs)
        self._f5_url = f5_url.rstrip("/")
        self._voices = voices
        self._default_voice = default_voice
        self._info = self._build_info()

    def _build_info(self) -> Info:
        attribution = Attribution(
            name="F5-TTS",
            url="https://github.com/SWivid/F5-TTS",
        )
        return Info(
            tts=[
                TtsProgram(
                    name="f5-tts",
                    description="F5-TTS via local Wyoming wrapper",
                    attribution=attribution,
                    installed=True,
                    version="0.1.0",
                    voices=[
                        TtsVoice(
                            name=v,
                            description=f"F5-TTS reference voice: {v}",
                            attribution=attribution,
                            installed=True,
                            version=None,
                            languages=["en"],
                        )
                        for v in self._voices
                    ],
                ),
            ],
        )

    async def handle_event(self, event: Event) -> bool:
        if Describe.is_type(event.type):
            LOG.debug("describe -> info")
            await self.write_event(self._info.event())
            return True

        if Synthesize.is_type(event.type):
            request = Synthesize.from_event(event)
            voice = self._default_voice
            if request.voice is not None and request.voice.name:
                voice = request.voice.name
            await self._synthesize(request.text, voice)
            return True

        # Unhandled event types: keep the connection alive and ignore.
        return True

    async def _synthesize(self, text: str, voice: str) -> None:
        LOG.info("synthesize voice=%s len=%d", voice, len(text))
        url = f"{self._f5_url}/v1/audio/speech"
        payload = {
            "input": text,
            "voice": voice,
            "stream": True,
            "speed": 1.0,
        }

        # Generous timeout: cold-start model load can take ~10s on GPU.
        # Within a single response, httpx applies the read timeout per
        # chunk, not over the whole stream, which suits our use case.
        timeout = httpx.Timeout(connect=5.0, read=60.0, write=5.0, pool=5.0)

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                async with client.stream("POST", url, json=payload) as resp:
                    if resp.status_code != 200:
                        body = (await resp.aread()).decode("utf-8", "replace")
                        LOG.error(
                            "F5-TTS returned HTTP %s for voice=%s: %s",
                            resp.status_code, voice, body[:300],
                        )
                        # We can't recover the synthesis; emit empty audio so
                        # HA's pipeline doesn't hang waiting for AudioStop.
                        await self._emit_empty_audio()
                        return

                    await self.write_event(
                        AudioStart(
                            rate=SAMPLE_RATE_HZ,
                            width=SAMPLE_WIDTH_BYTES,
                            channels=CHANNELS,
                        ).event()
                    )

                    bytes_streamed = 0
                    async for chunk in resp.aiter_bytes():
                        if not chunk:
                            continue
                        bytes_streamed += len(chunk)
                        await self.write_event(
                            AudioChunk(
                                rate=SAMPLE_RATE_HZ,
                                width=SAMPLE_WIDTH_BYTES,
                                channels=CHANNELS,
                                audio=chunk,
                            ).event()
                        )

                    await self.write_event(AudioStop().event())
                    duration_s = bytes_streamed / (
                        SAMPLE_RATE_HZ * SAMPLE_WIDTH_BYTES * CHANNELS
                    )
                    LOG.info(
                        "synthesize done voice=%s bytes=%d ~duration=%.2fs",
                        voice, bytes_streamed, duration_s,
                    )
        except httpx.HTTPError as exc:
            LOG.exception("F5-TTS request failed: %s", exc)
            await self._emit_empty_audio()

    async def _emit_empty_audio(self) -> None:
        """Send a minimal AudioStart/AudioStop pair so HA doesn't hang."""
        await self.write_event(
            AudioStart(
                rate=SAMPLE_RATE_HZ,
                width=SAMPLE_WIDTH_BYTES,
                channels=CHANNELS,
            ).event()
        )
        await self.write_event(AudioStop().event())


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--uri",
        default="tcp://0.0.0.0:10200",
        help="Wyoming URI to listen on (default: tcp://0.0.0.0:10200)",
    )
    parser.add_argument(
        "--f5-url",
        default="http://127.0.0.1:8880",
        help="Base URL of the local F5-TTS HTTP server",
    )
    parser.add_argument(
        "--voices",
        default="nature",
        help="Comma-separated list of voice names to advertise",
    )
    parser.add_argument(
        "--default-voice",
        default="nature",
        help="Voice to use when client does not specify one",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        help="Logging level (DEBUG, INFO, WARNING, ERROR)",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=args.log_level,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )

    voices = [v.strip() for v in args.voices.split(",") if v.strip()]
    if not voices:
        raise SystemExit("--voices must contain at least one voice name")
    if args.default_voice not in voices:
        raise SystemExit(
            f"--default-voice {args.default_voice!r} must be one of {voices}"
        )

    LOG.info(
        "starting wyoming-f5-tts uri=%s f5_url=%s voices=%s default=%s",
        args.uri, args.f5_url, voices, args.default_voice,
    )

    server = AsyncServer.from_uri(args.uri)
    await server.run(
        partial(
            F5TTSHandler,
            f5_url=args.f5_url,
            voices=voices,
            default_voice=args.default_voice,
        ),
    )


if __name__ == "__main__":
    asyncio.run(main())
