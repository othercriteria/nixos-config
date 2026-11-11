#!/usr/bin/env python3
"""Weather vibe as four emojis for Waybar.

Pipeline:
  fetch METAR -> qwen3.5:9b-q8_0 picks 4 emojis matching weather +
              time-of-day -> publish a snapshot Waybar reads.

This is a tiny art project: quirkiness is a feature, accuracy is not.
There's a window right next to the bar; the emojis are vibe, not gauge.
On any failure we show four question marks rather than invent a
hand-coded forecast.

- The model is qwen3.5:9b-q8_0, the same one HA Assist keeps warm
  (hosts/skaia/ollama.nix). A second vibe model would be a second
  VRAM load. Ollama's JSON schema is the format; the poll does not
  think.
- `show` (Waybar) reads the snapshot and never calls Ollama.
  `--refresh` (weather-emoji.timer) is the only mode that fetches
  METAR or calls the model, and it does neither unless
  /run/ollama-background/enabled exists. Stopping
  ollama-background.target does not unload this model.
- The snapshot and the METAR cache live under XDG_CACHE_HOME.
  Waybar's session sets that to /fastcache/dlk. The systemd unit
  has to set the same variable; a system service does not inherit
  the session, and a snapshot in ~/.cache is invisible to the bar.
- Cache key is the METAR plus a 3-hour slice of the day, so the
  vibe still moves morning to night without a model call on every
  poll.

Output (Waybar JSON):
  {"text": "<4 emoji>", "tooltip": "<when, METAR, source>"}
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

AIRPORTS = os.environ.get("METAR_AIRPORTS", "KLGA,KTEB")  # LaGuardia, Teterboro
LOCATION_LABEL = os.environ.get("WAYBAR_VIBE_LOCATION", "Manhattan area")
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://ollama.home.arpa")
MODEL = "qwen3.5:9b-q8_0"

# NOAA asks clients to identify themselves. Default urllib UA gets
# throttled or 403'd.
METAR_USER_AGENT = os.environ.get(
    "METAR_USER_AGENT",
    "nixos-config/weather-emoji (skaia; KLGA,KTEB)",
)

CACHE_DIR = Path(
    os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))
) / "waybar-weather-emoji"
LATEST_NAME = "latest.json"
LATEST_PATH = CACHE_DIR / LATEST_NAME
CACHE_TTL_SECS = 3 * 3600  # 3-hour slices double as time-of-day buckets

# Present only while ollama-background.target is active. The gate
# unit owns the file; stopping the target removes it.
GATE_PATH = Path(
    os.environ.get(
        "OLLAMA_BACKGROUND_GATE",
        "/run/ollama-background/enabled",
    )
)

# 60s covers a cold reload of the shared model.
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

SYSTEM_PROMPT = (
    "Turn the METAR and the named time of day into exactly four emoji "
    "for a status bar. Both the weather and the time of day have to "
    "show. Be a bit playful."
)


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


def time_bucket(now: datetime) -> str:
    """3-hour slice of the day. Encodes coarse time-of-day in the cache key."""
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
            if path.name == LATEST_NAME:
                continue
            try:
                if path.stat().st_mtime < cutoff:
                    path.unlink()
            except OSError:
                continue
    except OSError:
        pass


def cache_load(key: str) -> list[str] | None:
    path = CACHE_DIR / f"{key}.json"
    try:
        st = path.stat()
    except FileNotFoundError:
        return None
    if time.time() - st.st_mtime > CACHE_TTL_SECS:
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    emojis = data.get("emojis") if isinstance(data, dict) else None
    if not isinstance(emojis, list):
        return None
    return [item for item in emojis if isinstance(item, str)]


def cache_store(key: str, emojis: list[str]) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        (CACHE_DIR / f"{key}.json").write_text(
            json.dumps({"emojis": emojis}, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError:
        pass  # cache is best-effort


def build_user_prompt(metar: str, when: datetime) -> str:
    when_str = when.strftime("%A, %B %-d, %Y at %-I:%M %p (%Z)")
    return (
        f"Date/time: {when_str}\n"
        f"Period of day: {day_period(when)}\n"
        f"Location: {LOCATION_LABEL}\n"
        f"METAR:\n{metar}"
    )


def call_ollama(metar: str, when: datetime) -> list[str] | None:
    """Ask Ollama for four emoji. None on any transport or shape failure."""
    payload = json.dumps(
        {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": build_user_prompt(metar, when)},
            ],
            "stream": False,
            "think": False,
            "format": EMOJI_SCHEMA,
            # Resets the shared model's unload timer. Only runs while
            # ollama-background.target is up.
            "keep_alive": "30m",
            "options": {"temperature": 0.4},
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

    content = (data.get("message") or {}).get("content", "")
    if not content:
        return None
    try:
        parsed = json.loads(content)
    except json.JSONDecodeError:
        return None

    emojis = parsed.get("emojis") if isinstance(parsed, dict) else None
    if (
        not isinstance(emojis, list)
        or len(emojis) != NUM_EMOJIS
        or not all(isinstance(item, str) and item.strip() for item in emojis)
    ):
        return None
    return emojis


def build_tooltip(metar: str, when: datetime, source: str) -> str:
    when_str = when.strftime("%a %b %-d, %-I:%M %p")
    return (
        f"{when_str} — {LOCATION_LABEL}\n\n{metar}\n\n[source: {source}]"
    )


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

    A closed gate returns before any network I/O. The target's PartOf
    relationship stops a refresh that is already running.
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
    if cached:
        publish(
            payload_for(
                "".join(cached),
                build_tooltip(metar, when, f"cache ({bucket})"),
            )
        )
        return

    emojis = call_ollama(metar, when)
    if emojis:
        cache_store(key, emojis)
        publish(
            payload_for(
                "".join(emojis),
                build_tooltip(metar, when, f"ollama ({MODEL})"),
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
