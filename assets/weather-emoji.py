#!/usr/bin/env python3
"""Weather vibe as four emojis for Waybar.

Pipeline:
  fetch METAR -> qwen3:8b-q8_0 picks 4 emojis matching weather +
              time-of-day -> emit to Waybar.

This is a tiny art project: quirkiness is a feature, accuracy is not.
There's a window right next to the bar; the emojis are vibe, not gauge.
On any failure we show four question marks rather than fake meaningful
data with a hand-coded decoder.

Reliability decisions (overhauled 2026-05):

- Hardcoded to MODEL = qwen3:8b-q8_0 to share VRAM with the HA voice
  conversation agent. The previous llama3.2:3b model claimed ~2.8 GB
  but actually allocated ~7.5 GB of VRAM (32k context cache), which
  contended with the voice agent on the 24 GB 4090. By using the same
  model that voice already keeps resident, the script costs zero
  additional VRAM. One-off: this is intentionally NOT wired to
  ollama.nix's vibeModel/haAssistantModel - if voice ever moves to
  a different model we'll re-decide.
- Native /api/chat with think=false and format="json" (Ollama guarantees
  JSON output). Tried think=true to give it a more deliberate vibe; in
  practice qwen3's reasoning mode and Ollama's JSON-format constraint
  fight each other - the model never decides it's "done thinking" when
  the answer is constrained to a small JSON object, and runs out the
  num_predict budget (verified: 2048 tokens / 24s with empty content).
  Without thinking, this is one POST and ~0.5s of warm GPU.
- File cache keyed on (METAR observation hash, time-of-day bucket).
  METAR refreshes hourly; we bucket by 3-hour slices of the day so the
  emoji "vibe" still shifts morning -> afternoon -> evening -> night
  without burning Ollama for every poll.
- No deterministic fallback. On Ollama outage we render four ?'s.

Output (Waybar JSON shape):
  {"text": "<4 emoji>", "tooltip": "<context + reasoning the LLM saw>"}
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

# ----- Config ----------------------------------------------------------

AIRPORTS = os.environ.get("METAR_AIRPORTS", "KLGA,KTEB")  # LaGuardia, Teterboro
LOCATION_LABEL = os.environ.get("WAYBAR_VIBE_LOCATION", "Manhattan area")
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://ollama.home.arpa")
MODEL = "qwen3:8b-q8_0"  # See module docstring.

CACHE_DIR = Path(
    os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))
) / "waybar-weather-emoji"
CACHE_TTL_SECS = 3 * 3600  # 3-hour slices double as time-of-day buckets

# Thinking adds ~1-2s of generation; 60s gives plenty of headroom for
# a cold model reload (the voice agent eviction case).
OLLAMA_TIMEOUT = 60
METAR_TIMEOUT = 10
NUM_EMOJIS = 4

UNKNOWN_GLYPH = "❓"

# ----- Emoji handling --------------------------------------------------

# Match Unicode emoji codepoints. Used to strip CJK / Latin / punctuation
# stragglers from LLM output before we trust it.
EMOJI_PATTERN = re.compile(
    "["
    "\U0001f300-\U0001f5ff"  # Misc Symbols and Pictographs
    "\U0001f600-\U0001f64f"  # Emoticons
    "\U0001f680-\U0001f6ff"  # Transport and Map
    "\U0001f900-\U0001f9ff"  # Supplemental Symbols and Pictographs
    "\U0001fa00-\U0001fa6f"  # Chess Symbols
    "\U0001fa70-\U0001faff"  # Symbols and Pictographs Extended-A
    "\U00002600-\U000026ff"  # Misc symbols (sun, cloud, etc.)
    "\U00002700-\U000027bf"  # Dingbats
    "\U0001f1e0-\U0001f1ff"  # Flags
    "\ufe0f"                # Variation selector
    "]+"
)

# ----- I/O primitives --------------------------------------------------


def emit(text: str, tooltip: str) -> "None":
    """Print Waybar JSON and exit. ensure_ascii=False to keep emoji bytes."""
    print(json.dumps({"text": text, "tooltip": tooltip}, ensure_ascii=False))
    sys.exit(0)


def emit_unknown(reason: str, when: datetime, metar: str | None = None) -> "None":
    when_str = when.strftime("%a %b %-d, %-I:%M %p")
    body = metar if metar else "(no METAR)"
    emit(
        UNKNOWN_GLYPH * NUM_EMOJIS,
        f"{when_str} — {LOCATION_LABEL}\n\n{body}\n\n[source: {reason}]",
    )


def fetch_metar() -> str | None:
    """Pull raw METAR text from NOAA Aviation Weather API."""
    url = (
        f"https://aviationweather.gov/api/data/metar?ids={AIRPORTS}&format=raw"
    )
    try:
        with urlopen(url, timeout=METAR_TIMEOUT) as resp:
            return resp.read().decode("utf-8", "replace").strip() or None
    except (URLError, UnicodeDecodeError, TimeoutError):
        return None


# ----- Cache -----------------------------------------------------------


def time_bucket(now: datetime) -> str:
    """3-hour slice of the day. Encodes coarse time-of-day in cache key."""
    return f"{now.strftime('%Y%m%d')}-{now.hour // 3:02d}"


def cache_key(metar: str, bucket: str) -> str:
    raw = f"{MODEL}|{bucket}|{metar}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def cache_load(key: str) -> dict | None:
    path = CACHE_DIR / f"{key}.json"
    try:
        st = path.stat()
    except FileNotFoundError:
        return None
    if time.time() - st.st_mtime > CACHE_TTL_SECS:
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def cache_store(key: str, payload: dict) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        (CACHE_DIR / f"{key}.json").write_text(
            json.dumps(payload, ensure_ascii=False), encoding="utf-8"
        )
    except OSError:
        pass  # cache is best-effort


# ----- LLM path --------------------------------------------------------


SYSTEM_PROMPT = (
    "You translate weather + time-of-day into a 4-emoji vibe for a status "
    "bar. Pick emojis that match the actual weather (rain, sun, wind, "
    "clouds, fog, snow, temperature) AND the time of day (sunrise, midday, "
    "evening, night). Be a bit playful. Use Unicode weather/nature emoji "
    "only - no Chinese characters, no text. Always return exactly 4."
)


def build_user_prompt(metar: str, when: datetime) -> str:
    when_str = when.strftime("%A, %B %-d, %Y at %-I:%M %p (%Z)")
    return (
        f"Date/time: {when_str}\n"
        f"Location: {LOCATION_LABEL}\n"
        f"METAR:\n{metar}\n\n"
        'Reply with JSON: {"emojis":["e1","e2","e3","e4"]}'
    )


def call_ollama(metar: str, when: datetime) -> dict | None:
    """Ask Ollama for 4 emojis. Returns {"emojis": [...], "thinking": "..."}.

    Returns None on any networking, JSON, or shape failure. Caller decides
    how to surface the failure.
    """
    payload = json.dumps(
        {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": build_user_prompt(metar, when)},
            ],
            "stream": False,
            # See module docstring on why thinking is off. tl;dr: qwen3
            # reasoning + Ollama format=json never converges.
            "think": False,
            "format": "json",
            "options": {
                "temperature": 0.5,
                # 120 = enough headroom for {"emojis":[...]}.
                "num_predict": 120,
            },
        }
    ).encode()

    req = Request(
        f"{OLLAMA_HOST}/api/chat",
        data=payload,
        headers={"Content-Type": "application/json"},
    )

    try:
        with urlopen(req, timeout=OLLAMA_TIMEOUT) as resp:
            data = json.load(resp)
    except (URLError, TimeoutError, json.JSONDecodeError):
        return None

    msg = data.get("message") or {}
    content = msg.get("content", "")
    thinking = msg.get("thinking", "") or ""
    if not content:
        return None

    try:
        parsed = json.loads(content)
    except json.JSONDecodeError:
        return None

    raw = parsed.get("emojis") if isinstance(parsed, dict) else None
    if not isinstance(raw, list):
        return None

    out: list[str] = []
    for item in raw:
        if not isinstance(item, str):
            continue
        emoji_only = "".join(EMOJI_PATTERN.findall(item))
        if emoji_only:
            out.append(emoji_only)

    if not out:
        return None

    return {"emojis": out, "thinking": thinking.strip()}


# ----- Glue ------------------------------------------------------------


def shape(emojis: list[str]) -> str:
    """Trim to NUM_EMOJIS; pad with unknown glyphs if short."""
    out = list(emojis[:NUM_EMOJIS])
    while len(out) < NUM_EMOJIS:
        out.append(UNKNOWN_GLYPH)
    return "".join(out)


def build_tooltip(
    metar: str,
    when: datetime,
    source: str,
    thinking: str | None,
) -> str:
    when_str = when.strftime("%a %b %-d, %-I:%M %p")
    parts = [f"{when_str} — {LOCATION_LABEL}", "", metar]
    if thinking:
        parts.extend(["", f"thinking: {thinking}"])
    parts.extend(["", f"[source: {source}]"])
    return "\n".join(parts)


def main() -> None:
    when = datetime.now()
    metar = fetch_metar()
    if not metar:
        emit_unknown("METAR unavailable", when)

    bucket = time_bucket(when)
    key = cache_key(metar, bucket)

    cached = cache_load(key)
    if cached and isinstance(cached.get("emojis"), list):
        emit(
            shape(cached["emojis"]),
            build_tooltip(metar, when, f"cache ({bucket})", cached.get("thinking")),
        )

    result = call_ollama(metar, when)
    if result:
        cache_store(
            key,
            {
                "emojis": result["emojis"],
                "thinking": result["thinking"],
                "ts": time.time(),
            },
        )
        emit(
            shape(result["emojis"]),
            build_tooltip(metar, when, f"ollama ({MODEL})", result["thinking"]),
        )

    emit_unknown("LLM call failed", when, metar)


if __name__ == "__main__":
    main()
