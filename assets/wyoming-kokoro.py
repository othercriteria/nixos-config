#!/usr/bin/env python3
"""Wyoming TTS server backed by a local Kokoro-FastAPI server.

Bridges Home Assistant's Wyoming Protocol integration to a Kokoro-FastAPI
container (Kokoro-82M; see hosts/skaia/kokoro.nix), exposed at
http://127.0.0.1:8881 on skaia.

Pipeline:

  HA (Wyoming Synthesize)
    -> this server: POST /v1/audio/speech with response_format=pcm,
       stream=true
    -> read raw PCM s16le mono 24kHz chunks
    -> forward each as Wyoming AudioChunk events
    -> emit AudioStart at the beginning, AudioStop at the end

This is a near-clone of wyoming-f5-tts.py; kept separate (rather than
factored into a shared library) because the request-shape diffs are
small, the failure modes are TTS-engine-specific, and we want either
backend to keep working when we hack on the other.

Why Kokoro alongside F5-TTS: see hosts/skaia/kokoro.nix. Short version:
Kokoro normalizes numbers/dates/times before phonemizing, F5-TTS does
not. We A/B by switching the HA pipeline's TTS engine, no rebuild
required.

Voices: Kokoro ships ~50 voices (af_heart, af_bella, am_michael, ...).
We advertise a curated subset via --voices because exposing all 50 in
HA's pipeline picker is noise. Add more by extending the CLI flag.
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

LOG = logging.getLogger("wyoming-kokoro")

# Kokoro-82M outputs at 24 kHz mono. Hardcoded; the model architecture
# fixes this, and Kokoro-FastAPI's pcm response_format passes it
# through unchanged.
SAMPLE_RATE_HZ = 24000
SAMPLE_WIDTH_BYTES = 2  # s16le
CHANNELS = 1


class KokoroTTSHandler(AsyncEventHandler):
    """Per-connection Wyoming handler that proxies Synthesize -> Kokoro."""

    def __init__(
        self,
        *args,
        kokoro_url: str,
        voices: list[str],
        default_voice: str,
        model: str,
        **kwargs,
    ) -> None:
        super().__init__(*args, **kwargs)
        self._kokoro_url = kokoro_url.rstrip("/")
        self._voices = voices
        self._default_voice = default_voice
        self._model = model
        self._info = self._build_info()

    def _build_info(self) -> Info:
        attribution = Attribution(
            name="Kokoro-82M",
            url="https://huggingface.co/hexgrad/Kokoro-82M",
        )
        return Info(
            tts=[
                TtsProgram(
                    name="kokoro",
                    description="Kokoro-82M via local Wyoming wrapper",
                    attribution=attribution,
                    installed=True,
                    version="0.1.0",
                    voices=[
                        TtsVoice(
                            name=v,
                            description=f"Kokoro voice: {v}",
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
        url = f"{self._kokoro_url}/v1/audio/speech"
        payload = {
            "model": self._model,
            "input": text,
            "voice": voice,
            # Raw 16-bit PCM at 24 kHz mono. Avoids a decode step in the
            # bridge - we just pass the bytes straight through to HA.
            "response_format": "pcm",
            "stream": True,
            "speed": 1.0,
        }

        # Generous read timeout: Kokoro is fast (~0.05x realtime warm),
        # but the first request after container start can take ~5s while
        # the model loads from disk into VRAM.
        timeout = httpx.Timeout(connect=5.0, read=60.0, write=5.0, pool=5.0)

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                async with client.stream("POST", url, json=payload) as resp:
                    if resp.status_code != 200:
                        body = (await resp.aread()).decode("utf-8", "replace")
                        LOG.error(
                            "Kokoro returned HTTP %s for voice=%s: %s",
                            resp.status_code, voice, body[:300],
                        )
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
            LOG.exception("Kokoro request failed: %s", exc)
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
        default="tcp://0.0.0.0:10210",
        help="Wyoming URI to listen on (default: tcp://0.0.0.0:10210)",
    )
    parser.add_argument(
        "--kokoro-url",
        default="http://127.0.0.1:8881",
        help="Base URL of the local Kokoro-FastAPI server",
    )
    parser.add_argument(
        "--model",
        default="kokoro",
        help="Model name to send in OpenAI-compatible request",
    )
    parser.add_argument(
        "--voices",
        default="af_heart,af_bella,af_sarah,am_michael,am_adam,bf_emma",
        help="Comma-separated list of voice names to advertise",
    )
    parser.add_argument(
        "--default-voice",
        default="af_heart",
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
        "starting wyoming-kokoro uri=%s kokoro_url=%s voices=%s default=%s",
        args.uri, args.kokoro_url, voices, args.default_voice,
    )

    server = AsyncServer.from_uri(args.uri)
    await server.run(
        partial(
            KokoroTTSHandler,
            kokoro_url=args.kokoro_url,
            voices=voices,
            default_voice=args.default_voice,
            model=args.model,
        ),
    )


if __name__ == "__main__":
    asyncio.run(main())
