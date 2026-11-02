#!/usr/bin/env python3
"""Weather vibe as four emojis for Waybar.

Pipeline:
  fetch METAR -> qwen3.5:9b-q8_0 picks 4 emojis matching weather +
              time-of-day -> emit to Waybar.

This is a tiny art project: quirkiness is a feature, accuracy is not.
There's a window right next to the bar; the emojis are vibe, not gauge.
On any failure we show four question marks rather than fake meaningful
data with a hand-coded decoder.

Reliability decisions (overhauled 2026-05, prompt/cache 2026-08):

- Hardcoded to MODEL = qwen3.5:9b-q8_0 to share VRAM with the HA
  voice conversation agent (see hosts/skaia/ollama.nix). Same q8
  slot as the previous qwen3:8b-q8_0 (~13 GB resident with KV
  cache). A dedicated smaller vibe model would be a second load.
- Two modes. `show` (the default Waybar exec) reads the last
  published JSON and never calls Ollama. `--refresh` is the
  systemd timer on ollama-background.target, and the only mode
  that fetches METAR or calls the model. `--refresh` returns
  before any network I/O unless /run/ollama-background/enabled
  exists, so `ollama-background stop` cannot be raced by a poll.
  Stopping that target does not unload this model: HA Assist
  shares it. `ollama stop qwen3.5:9b-q8_0` unloads it, and drops
  Assist's warm copy too.
- Native /api/chat with think=false and a JSON schema (Ollama
  guarantees the shape). Thinking + a tiny JSON object still does
  not converge well (verified on Qwen3: 2048 tokens / 24s empty
  content). Keep thinking off for this poll.
- File cache keyed on (METAR observation hash, time-of-day bucket).
  METAR refreshes hourly; we bucket by 3-hour slices of the day so
  the emoji "vibe" still shifts morning -> afternoon -> evening ->
  night without burning Ollama for every poll. Expired entries are
  deleted so the cache dir does not grow without bound. The timer
  also publishes the latest Waybar JSON beside that cache.
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
MODEL = "qwen3.5:9b-q8_0"  # See module docstring.

# NOAA asks clients to identify themselves. Default urllib UA gets
# throttled or 403'd.
METAR_USER_AGENT = os.environ.get(
    "METAR_USER_AGENT",
    "nixos-config/weather-emoji (skaia; KLGA,KTEB)",
)

CACHE_DIR = Path(
    os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))
) / "waybar-weather-emoji"
LATEST_PATH = CACHE_DIR / "latest.json"
CACHE_TTL_SECS = 3 * 3600  # 3-hour slices double as time-of-day buckets

# Present only while ollama-background.target is active. The gate
# unit owns the file; stopping the target removes it. Override is
# for a manual check, not a second switch.
GATE_PATH = Path(
    os.environ.get(
        "OLLAMA_BACKGROUND_GATE",
        "/run/ollama-background/enabled",
    )
)

# Thinking adds ~1-2s of generation; 60s gives plenty of headroom for
# a cold model reload (the voice agent eviction case).
OLLAMA_TIMEOUT = 60
METAR_TIMEOUT = 10
NUM_EMOJIS = 4

UNKNOWN_GLYPH = "❓"

EMOJI_SCHEMA = {
    "type": "object",
    "properties": {
        "emojis": {
            "type": "array",
            "items": {"type": "string"},
            "minItems": NUM_EMOJIS,
            "maxItems": NUM_EMOJIS,
        }
    },
    "required": ["emojis"],
}

# ----- Emoji handling --------------------------------------------------

# Match Unicode emoji codepoints. Used to strip CJK / Latin / punctuation
# stragglers from LLM output before we trust it. ZWJ keeps sequences
# like ⛈️ as one glyph instead of splitting on the joiner.
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
    "\u200d"                # Zero-width joiner
    "\ufe0f"                # Variation selector
    "]+"
)

# ----- I/O primitives --------------------------------------------------


def payload_for(text: str, tooltip: str) -> dict:
    return {"text": text, "tooltip": tooltip}


def unknown_payload(
    reason: str, when: datetime, metar: str | None = None
) -> dict:
    when_str = when.strftime("%a %b %-d, %-I:%M %p")
    body = metar if metar else "(no METAR)"
    return payload_for(
        UNKNOWN_GLYPH * NUM_EMOJIS,
        f"{when_str} — {LOCATION_LABEL}\n\n{body}\n\n[source: {reason}]",
    )


def gate_open() -> bool:
    return GATE_PATH.is_file()


def publish(payload: dict) -> None:
    """Atomically replace the snapshot Waybar reads."""
    raw = json.dumps(payload, ensure_ascii=False)
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = LATEST_PATH.with_suffix(".json.tmp")
        tmp.write_text(raw, encoding="utf-8")
        tmp.replace(LATEST_PATH)
    except OSError:
        print("weather-emoji: could not publish snapshot", file=sys.stderr)


def fetch_metar() -> str | None:
    """Pull raw METAR text from NOAA Aviation Weather API."""
    url = (
        f"https://aviationweather.gov/api/data/metar?ids={AIRPORTS}&format=raw"
    )
    req = Request(url, headers={"User-Agent": METAR_USER_AGENT})
    try:
        with urlopen(req, timeout=METAR_TIMEOUT) as resp:
            return resp.read().decode("utf-8", "replace").strip() or None
    except (URLError, UnicodeDecodeError, TimeoutError):
        return None


# ----- Cache -----------------------------------------------------------


def time_bucket(now: datetime) -> str:
    """3-hour slice of the day. Encodes coarse time-of-day in cache key."""
    return f"{now.strftime('%Y%m%d')}-{now.hour // 3:02d}"


def day_period(now: datetime) -> str:
    """Human period for the prompt. Clock hour, not METAR time."""
    h = now.hour
    if 5 <= h < 8:
        return "early morning / sunrise"
    if 8 <= h < 12:
        return "morning"
    if 12 <= h < 17:
        return "afternoon"
    if 17 <= h < 21:
        return "evening / sunset"
    return "night"


def cache_key(metar: str, bucket: str) -> str:
    raw = f"{MODEL}|{bucket}|{metar}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def cache_prune() -> None:
    try:
        cutoff = time.time() - CACHE_TTL_SECS
        for path in CACHE_DIR.glob("*.json"):
            try:
                if path.stat().st_mtime < cutoff:
                    path.unlink()
            except OSError:
                continue
    except OSError:
        pass


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
    "bar. Pick emojis that match the actual METAR (rain, sun, wind, "
    "clouds, fog, snow, temperature) AND the period of day the user "
    "names. Time-of-day glyphs must match that period only: no moons, "
    "stars, or night cityscapes in the afternoon; no sunrise at dusk. "
    "Be a bit playful. Unicode weather/nature emoji only - no Chinese "
    "characters, no letters. Always return exactly 4 emoji strings."
)


def build_user_prompt(metar: str, when: datetime) -> str:
    when_str = when.strftime("%A, %B %-d, %Y at %-I:%M %p (%Z)")
    period = day_period(when)
    return (
        f"Date/time: {when_str}\n"
        f"Period of day: {period}\n"
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
            # See module docstring on why thinking is off. tl;dr:
            # reasoning + a JSON constraint never converges.
            "think": False,
            "format": EMOJI_SCHEMA,
            # Share the HA-resident weights across the 10-minute
            # poll. This resets the model's unload timer, so it
            # only runs while ollama-background.target is up.
            "keep_alive": "30m",
            "options": {
                "temperature": 0.4,
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


def show() -> None:
    """Print the last published vibe. Never touches the network."""
    paused = not gate_open()
    data = None
    try:
        data = json.loads(LATEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        data = None

    if isinstance(data, dict) and isinstance(data.get("text"), str):
        tooltip = data.get("tooltip")
        body = payload_for(
            data["text"], tooltip if isinstance(tooltip, str) else ""
        )
    else:
        body = unknown_payload("no vibe yet", datetime.now().astimezone())

    if paused:
        body["class"] = "paused"
        body["tooltip"] = "ollama-background stopped\n\n" + body["tooltip"]
    print(json.dumps(body, ensure_ascii=False))


def refresh() -> None:
    """Fetch METAR and, on a cache miss, call Ollama. Publish the result.

    A closed gate is success and does no I/O, so stopping the target
    mid-timer cannot reload the model.
    """
    if not gate_open():
        print(
            "ollama-background gate closed; not calling Ollama",
            file=sys.stderr,
        )
        return

    when = datetime.now().astimezone()
    cache_prune()
    metar = fetch_metar()
    if not metar:
        publish(unknown_payload("METAR unavailable", when))
        return

    bucket = time_bucket(when)
    key = cache_key(metar, bucket)

    cached = cache_load(key)
    if cached and isinstance(cached.get("emojis"), list):
        publish(
            payload_for(
                shape(cached["emojis"]),
                build_tooltip(
                    metar, when, f"cache ({bucket})", cached.get("thinking")
                ),
            )
        )
        return

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
        publish(
            payload_for(
                shape(result["emojis"]),
                build_tooltip(
                    metar, when, f"ollama ({MODEL})", result["thinking"]
                ),
            )
        )
        return

    publish(unknown_payload("LLM call failed", when, metar))


def main(argv: list[str] | None = None) -> None:
    args = list(sys.argv[1:] if argv is None else argv)
    if args in ([], ["show"]):
        show()
        return
    if args == ["--refresh"]:
        refresh()
        return
    print("usage: weather-emoji.py [show|--refresh]", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
