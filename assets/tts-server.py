#!/usr/bin/env python3
"""
OpenAI-compatible TTS server with Ollama-style model lifecycle management.

Features:
- OpenAI API compatible: POST /v1/audio/speech
- F5-TTS backend (high-quality neural TTS)
- Lazy model loading on first request
- Automatic GPU VRAM unloading after configurable idle timeout
- Voice = reference audio + text pair

Environment variables:
- TTS_HOST: Host to bind (default: 0.0.0.0)
- TTS_PORT: Port to bind (default: 8880)
- TTS_KEEP_ALIVE: Idle timeout in seconds (default: 300 = 5 minutes)
- TTS_VOICE: Default voice name (default: nature)
- TTS_VOICES_DIR: Directory containing voice reference files

API:
  POST /v1/audio/speech
  {
    "model": "tts-1",           # ignored, for compatibility
    "input": "Hello world",     # text to synthesize
    "voice": "nature",          # voice name (maps to ref audio)
    "response_format": "mp3",   # mp3, wav, opus, flac
    "speed": 1.0                # speech rate multiplier
  }
  -> Returns audio bytes with appropriate Content-Type

Voice format:
  Each voice requires two files in TTS_VOICES_DIR:
    - {voice}.wav  - reference audio (5-15 seconds recommended)
    - {voice}.txt  - transcript of the reference audio
"""

import gc
import io
import logging
import os
import subprocess
import tempfile
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import soundfile as sf
import torch
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

# Configuration from environment
HOST = os.environ.get("TTS_HOST", "0.0.0.0")
PORT = int(os.environ.get("TTS_PORT", "8880"))
KEEP_ALIVE = int(os.environ.get("TTS_KEEP_ALIVE", "300"))  # 5 minutes default
DEFAULT_VOICE = os.environ.get("TTS_VOICE", "nature")
VOICES_DIR = Path(os.environ.get("TTS_VOICES_DIR", "/voices"))

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("tts-server")

# Content types for response formats
CONTENT_TYPES = {
    "mp3": "audio/mpeg",
    "wav": "audio/wav",
    "opus": "audio/opus",
    "flac": "audio/flac",
}


class SpeechRequest(BaseModel):
    """OpenAI-compatible speech synthesis request."""

    model: str = Field(default="tts-1", description="Model name (ignored)")
    input: str = Field(..., description="Text to synthesize")
    voice: str = Field(default=DEFAULT_VOICE, description="Voice name")
    response_format: str = Field(default="mp3", description="Output format")
    speed: float = Field(default=1.0, ge=0.25, le=4.0, description="Speed multiplier")


class F5TTSManager:
    """
    Manages F5-TTS model lifecycle with Ollama-style idle unloading.

    The model is loaded lazily on first request and unloaded after
    keep_alive seconds of inactivity to free GPU VRAM.
    """

    def __init__(self, keep_alive: int = 300):
        self.keep_alive = keep_alive
        self.last_used: float = 0
        self.model = None
        self._lock = threading.Lock()
        self._unload_timer: Optional[threading.Timer] = None

    def _schedule_unload(self):
        """Schedule model unload after keep_alive seconds."""
        if self._unload_timer:
            self._unload_timer.cancel()

        if self.keep_alive > 0:
            self._unload_timer = threading.Timer(self.keep_alive, self._check_unload)
            self._unload_timer.daemon = True
            self._unload_timer.start()

    def _check_unload(self):
        """Check if model should be unloaded due to inactivity."""
        with self._lock:
            if self.model and time.time() - self.last_used >= self.keep_alive:
                log.info(f"Unloading F5-TTS model after {self.keep_alive}s of inactivity")
                self._unload_model()

    def _unload_model(self):
        """Unload model and free GPU memory."""
        if self.model:
            del self.model
            self.model = None
            gc.collect()
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            log.info("F5-TTS model unloaded, GPU memory freed")

    def get_model(self):
        """Get or load the F5-TTS model."""
        with self._lock:
            self.last_used = time.time()
            self._schedule_unload()

            if self.model is None:
                log.info("Loading F5-TTS model...")
                start = time.time()
                from f5_tts.api import F5TTS
                self.model = F5TTS()
                elapsed = time.time() - start
                log.info(f"F5-TTS model loaded in {elapsed:.1f}s on {self.model.device}")

            return self.model

    def is_loaded(self) -> bool:
        """Check if model is currently loaded."""
        with self._lock:
            return self.model is not None

    def status(self) -> dict:
        """Return current model status."""
        with self._lock:
            idle_time = time.time() - self.last_used if self.last_used else None
            vram_used = None
            if torch.cuda.is_available():
                vram_used = round(torch.cuda.memory_allocated() / 1024**3, 2)
            return {
                "loaded": self.model is not None,
                "last_used": self.last_used,
                "idle_seconds": round(idle_time, 1) if idle_time else None,
                "keep_alive": self.keep_alive,
                "vram_gb": vram_used,
                "device": str(self.model.device) if self.model else None,
            }


# Global model manager
model_manager = F5TTSManager(keep_alive=KEEP_ALIVE)


def get_voice_files(voice: str) -> tuple[Path, str]:
    """
    Get reference audio path and text for a voice.

    Returns:
        Tuple of (audio_path, reference_text)
    """
    audio_path = VOICES_DIR / f"{voice}.wav"
    text_path = VOICES_DIR / f"{voice}.txt"

    if not audio_path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Voice '{voice}' not found. Missing: {audio_path}",
        )

    if not text_path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Voice '{voice}' missing transcript. Missing: {text_path}",
        )

    ref_text = text_path.read_text().strip()
    return audio_path, ref_text


def synthesize_speech(
    text: str,
    voice: str,
    output_format: str = "mp3",
    speed: float = 1.0,
) -> bytes:
    """
    Synthesize speech using F5-TTS.

    Args:
        text: Text to synthesize
        voice: Voice name (maps to reference audio/text)
        output_format: Output format (mp3, wav, opus, flac)
        speed: Speech rate multiplier

    Returns:
        Audio data as bytes
    """
    ref_audio, ref_text = get_voice_files(voice)
    model = model_manager.get_model()

    log.info(f"Synthesizing {len(text)} chars with voice '{voice}'")
    start = time.time()

    # Generate speech
    wav, sr, _ = model.infer(
        ref_file=str(ref_audio),
        ref_text=ref_text,
        gen_text=text,
        speed=speed,
    )

    elapsed = time.time() - start
    duration = len(wav) / sr
    log.info(f"Generated {duration:.1f}s audio in {elapsed:.2f}s (RTF: {elapsed/duration:.3f})")

    # Convert to requested format
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        sf.write(tmp.name, wav, sr)
        wav_path = tmp.name

    try:
        if output_format == "wav":
            with open(wav_path, "rb") as f:
                return f.read()

        # Use ffmpeg for format conversion
        ffmpeg_cmd = ["ffmpeg", "-y", "-i", wav_path, "-f", output_format]

        if output_format == "mp3":
            ffmpeg_cmd.extend(["-codec:a", "libmp3lame", "-q:a", "2"])
        elif output_format == "opus":
            ffmpeg_cmd.extend(["-codec:a", "libopus", "-b:a", "96k"])
        elif output_format == "flac":
            ffmpeg_cmd.extend(["-codec:a", "flac"])

        ffmpeg_cmd.append("pipe:1")

        result = subprocess.run(ffmpeg_cmd, capture_output=True, timeout=60)

        if result.returncode != 0:
            log.error(f"ffmpeg failed: {result.stderr.decode()}")
            raise HTTPException(status_code=500, detail="Audio format conversion failed")

        return result.stdout

    finally:
        Path(wav_path).unlink(missing_ok=True)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    log.info(f"TTS server starting on {HOST}:{PORT}")
    log.info(f"Keep-alive timeout: {KEEP_ALIVE}s")
    log.info(f"Default voice: {DEFAULT_VOICE}")
    log.info(f"Voices directory: {VOICES_DIR}")
    if torch.cuda.is_available():
        log.info(f"CUDA available: {torch.cuda.get_device_name()}")
    yield
    log.info("TTS server shutting down")


app = FastAPI(
    title="TTS Server",
    description="OpenAI-compatible TTS with F5-TTS backend and Ollama-style model management",
    version="0.2.0",
    lifespan=lifespan,
)


@app.post("/v1/audio/speech")
async def create_speech(request: SpeechRequest) -> Response:
    """Generate speech from text (OpenAI-compatible endpoint)."""
    if not request.input.strip():
        raise HTTPException(status_code=400, detail="Input text cannot be empty")

    if request.response_format not in CONTENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported format: {request.response_format}. "
            f"Supported: {list(CONTENT_TYPES.keys())}",
        )

    import asyncio
    loop = asyncio.get_event_loop()
    audio_data = await loop.run_in_executor(
        None,
        synthesize_speech,
        request.input,
        request.voice,
        request.response_format,
        request.speed,
    )

    return Response(
        content=audio_data,
        media_type=CONTENT_TYPES[request.response_format],
        headers={
            "Content-Disposition": f'attachment; filename="speech.{request.response_format}"'
        },
    )


@app.get("/v1/audio/voices")
async def list_voices() -> dict:
    """List available voices."""
    voices = []

    if VOICES_DIR.exists():
        for audio_file in VOICES_DIR.glob("*.wav"):
            voice_name = audio_file.stem
            text_file = VOICES_DIR / f"{voice_name}.txt"
            if text_file.exists():
                voices.append({
                    "voice_id": voice_name,
                    "name": voice_name,
                    "has_transcript": True,
                })

    return {"voices": voices, "default": DEFAULT_VOICE}


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint."""
    return {
        "status": "ok",
        "model": model_manager.status(),
    }


@app.get("/")
async def root() -> dict:
    """Root endpoint with service info."""
    return {
        "service": "tts-server",
        "version": "0.2.0",
        "backend": "F5-TTS",
        "endpoints": {
            "speech": "POST /v1/audio/speech",
            "voices": "GET /v1/audio/voices",
            "health": "GET /health",
        },
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
