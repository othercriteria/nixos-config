#!/usr/bin/env python3
"""
OpenAI-compatible TTS server with Ollama-style model lifecycle management.

Features:
- OpenAI API compatible: POST /v1/audio/speech
- Lazy model loading on first request
- Automatic unloading after configurable idle timeout
- Piper TTS backend (fast, CPU-efficient)

Environment variables:
- TTS_HOST: Host to bind (default: 127.0.0.1)
- TTS_PORT: Port to bind (default: 8880)
- TTS_KEEP_ALIVE: Idle timeout in seconds (default: 300 = 5 minutes)
- TTS_VOICE: Default Piper voice (default: en_US-ryan-medium)
- TTS_DATA_DIR: Directory for voice models (default: /var/lib/tts)
- PIPER_PATH: Path to piper executable

API:
  POST /v1/audio/speech
  {
    "model": "tts-1",           # ignored, for compatibility
    "input": "Hello world",     # text to synthesize
    "voice": "en_US-ryan-medium", # Piper voice name
    "response_format": "mp3",   # mp3, wav, opus, flac
    "speed": 1.0                # speech rate multiplier
  }
  -> Returns audio bytes with appropriate Content-Type
"""

import asyncio
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

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

# Configuration from environment
HOST = os.environ.get("TTS_HOST", "127.0.0.1")
PORT = int(os.environ.get("TTS_PORT", "8880"))
KEEP_ALIVE = int(os.environ.get("TTS_KEEP_ALIVE", "300"))  # 5 minutes default
DEFAULT_VOICE = os.environ.get("TTS_VOICE", "en_US-ryan-medium")
DATA_DIR = Path(os.environ.get("TTS_DATA_DIR", "/var/lib/tts"))
PIPER_PATH = os.environ.get("PIPER_PATH", "piper")
FFMPEG_PATH = os.environ.get("FFMPEG_PATH", "ffmpeg")

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
    "pcm": "audio/pcm",
}


class SpeechRequest(BaseModel):
    """OpenAI-compatible speech synthesis request."""

    model: str = Field(default="tts-1", description="Model name (ignored)")
    input: str = Field(..., description="Text to synthesize")
    voice: str = Field(default=DEFAULT_VOICE, description="Voice name")
    response_format: str = Field(default="mp3", description="Output format")
    speed: float = Field(default=1.0, ge=0.25, le=4.0, description="Speed multiplier")


class ModelManager:
    """
    Manages TTS model lifecycle with Ollama-style idle unloading.

    The model is loaded lazily on first request and unloaded after
    keep_alive seconds of inactivity.
    """

    def __init__(self, keep_alive: int = 300):
        self.keep_alive = keep_alive
        self.last_used: float = 0
        self.loaded_voice: Optional[str] = None
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
            if self.loaded_voice and time.time() - self.last_used >= self.keep_alive:
                log.info(
                    f"Unloading voice '{self.loaded_voice}' after "
                    f"{self.keep_alive}s of inactivity"
                )
                self.loaded_voice = None
                # Piper doesn't keep persistent state, so unload is just
                # marking as unloaded. The next request will reload.

    def touch(self, voice: str):
        """Mark model as used and schedule unload timer."""
        with self._lock:
            self.last_used = time.time()
            if self.loaded_voice != voice:
                if self.loaded_voice:
                    log.info(
                        f"Switching voice: '{self.loaded_voice}' -> '{voice}'"
                    )
                else:
                    log.info(f"Loading voice: '{voice}'")
                self.loaded_voice = voice
            self._schedule_unload()

    def is_loaded(self, voice: str) -> bool:
        """Check if a specific voice is currently loaded."""
        with self._lock:
            return self.loaded_voice == voice

    def status(self) -> dict:
        """Return current model status."""
        with self._lock:
            idle_time = time.time() - self.last_used if self.last_used else None
            return {
                "loaded_voice": self.loaded_voice,
                "last_used": self.last_used,
                "idle_seconds": round(idle_time, 1) if idle_time else None,
                "keep_alive": self.keep_alive,
            }


# Global model manager
model_manager = ModelManager(keep_alive=KEEP_ALIVE)


def get_voice_model_path(voice: str) -> Path:
    """Get path to voice model file, downloading if necessary."""
    # Piper voices are stored as .onnx files with accompanying .json config
    model_dir = DATA_DIR / "voices"
    model_path = model_dir / f"{voice}.onnx"

    if not model_path.exists():
        # For now, expect voices to be pre-downloaded
        # Future: auto-download from Piper releases
        raise HTTPException(
            status_code=404,
            detail=f"Voice '{voice}' not found. Available voices are in {model_dir}",
        )

    return model_path


def synthesize_speech(
    text: str,
    voice: str,
    output_format: str = "mp3",
    speed: float = 1.0,
) -> bytes:
    """
    Synthesize speech using Piper TTS.

    Args:
        text: Text to synthesize
        voice: Piper voice name (e.g., en_US-ryan-medium)
        output_format: Output format (mp3, wav, opus, flac)
        speed: Speech rate multiplier

    Returns:
        Audio data as bytes
    """
    model_manager.touch(voice)
    model_path = get_voice_model_path(voice)

    # Piper outputs raw WAV to stdout
    # We'll convert to requested format using ffmpeg if needed
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as wav_file:
        wav_path = wav_file.name

    try:
        # Run Piper
        piper_cmd = [
            PIPER_PATH,
            "--model", str(model_path),
            "--output_file", wav_path,
            "--length_scale", str(1.0 / speed),  # length_scale is inverse of speed
        ]

        result = subprocess.run(
            piper_cmd,
            input=text.encode("utf-8"),
            capture_output=True,
            timeout=60,
        )

        if result.returncode != 0:
            log.error(f"Piper failed: {result.stderr.decode()}")
            raise HTTPException(
                status_code=500,
                detail=f"TTS synthesis failed: {result.stderr.decode()[:200]}",
            )

        # Convert to requested format
        if output_format == "wav":
            with open(wav_path, "rb") as f:
                return f.read()

        # Use ffmpeg for format conversion
        ffmpeg_cmd = [
            FFMPEG_PATH,
            "-y",  # Overwrite output
            "-i", wav_path,
            "-f", output_format,
        ]

        # Format-specific options
        if output_format == "mp3":
            ffmpeg_cmd.extend(["-codec:a", "libmp3lame", "-q:a", "2"])
        elif output_format == "opus":
            ffmpeg_cmd.extend(["-codec:a", "libopus", "-b:a", "64k"])
        elif output_format == "flac":
            ffmpeg_cmd.extend(["-codec:a", "flac"])

        ffmpeg_cmd.append("pipe:1")  # Output to stdout

        result = subprocess.run(
            ffmpeg_cmd,
            capture_output=True,
            timeout=60,
        )

        if result.returncode != 0:
            log.error(f"ffmpeg failed: {result.stderr.decode()}")
            raise HTTPException(
                status_code=500,
                detail="Audio format conversion failed",
            )

        return result.stdout

    finally:
        # Clean up temp file
        Path(wav_path).unlink(missing_ok=True)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    log.info(f"TTS server starting on {HOST}:{PORT}")
    log.info(f"Keep-alive timeout: {KEEP_ALIVE}s")
    log.info(f"Default voice: {DEFAULT_VOICE}")
    log.info(f"Data directory: {DATA_DIR}")
    yield
    log.info("TTS server shutting down")


app = FastAPI(
    title="TTS Server",
    description="OpenAI-compatible TTS with Ollama-style model management",
    version="0.1.0",
    lifespan=lifespan,
)


@app.post("/v1/audio/speech")
async def create_speech(request: SpeechRequest) -> Response:
    """
    Generate speech from text (OpenAI-compatible endpoint).

    Returns audio in the requested format.
    """
    if not request.input.strip():
        raise HTTPException(status_code=400, detail="Input text cannot be empty")

    if request.response_format not in CONTENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported format: {request.response_format}. "
            f"Supported: {list(CONTENT_TYPES.keys())}",
        )

    log.info(
        f"Synthesizing {len(request.input)} chars with voice '{request.voice}' "
        f"-> {request.response_format}"
    )

    # Run synthesis in thread pool to not block event loop
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
    voices_dir = DATA_DIR / "voices"
    voices = []

    if voices_dir.exists():
        for model_file in voices_dir.glob("*.onnx"):
            voice_name = model_file.stem
            voices.append({
                "voice_id": voice_name,
                "name": voice_name,
            })

    return {"voices": voices}


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
        "version": "0.1.0",
        "endpoints": {
            "speech": "POST /v1/audio/speech",
            "voices": "GET /v1/audio/voices",
            "health": "GET /health",
        },
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
