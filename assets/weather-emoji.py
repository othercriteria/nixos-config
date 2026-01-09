#!/usr/bin/env python3
"""
Weather vibe as four emojis for Waybar.

Uses METAR data from nearby airports + local Ollama LLM for creative emoji selection.
This is a tiny art project - quirkiness and creativity are features.

Output: JSON with "text" (emojis) and "tooltip" (raw context the LLM saw)
"""

import json
import os
import re
import sys
from datetime import datetime
from urllib.request import urlopen, Request
from urllib.error import URLError

# Configuration
AIRPORTS = os.environ.get("METAR_AIRPORTS", "KLGA,KTEB")  # LaGuardia, Teterboro
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://ollama.home.arpa")
MODEL = os.environ.get("OLLAMA_DEFAULT_MODEL", "qwen2.5:14b-instruct-q8_0")

# Regex to match emoji characters (for filtering non-emoji from LLM output)
EMOJI_PATTERN = re.compile(
    r'['
    r'\U0001F300-\U0001F5FF'   # Misc Symbols and Pictographs
    r'\U0001F600-\U0001F64F'   # Emoticons
    r'\U0001F680-\U0001F6FF'   # Transport and Map
    r'\U0001F900-\U0001F9FF'   # Supplemental Symbols and Pictographs
    r'\U0001FA00-\U0001FA6F'   # Chess Symbols
    r'\U0001FA70-\U0001FAFF'   # Symbols and Pictographs Extended-A
    r'\U00002600-\U000026FF'   # Misc symbols (sun, cloud, etc.)
    r'\U00002700-\U000027BF'   # Dingbats
    r'\U0001F1E0-\U0001F1FF'   # Flags
    r'\uFE0F'                  # Variation selector
    r']+'
)

# Fallback emojis for padding (contextually neutral)
PADDING_EMOJIS = ["✨", "🌟", "💫", "⭐"]


def output(text: str, tooltip: str) -> None:
    """Output JSON for Waybar."""
    # ensure_ascii=False to properly handle emoji without escaping
    print(json.dumps({"text": text, "tooltip": tooltip}, ensure_ascii=False))
    sys.exit(0)


def fetch_metar() -> str | None:
    """Fetch METAR data from NOAA Aviation Weather API."""
    url = f"https://aviationweather.gov/api/data/metar?ids={AIRPORTS}&format=raw"
    try:
        with urlopen(url, timeout=10) as resp:
            return resp.read().decode("utf-8").strip()
    except (URLError, UnicodeDecodeError):
        return None


def call_ollama(context: str) -> list[str]:
    """Call Ollama to generate emojis for the given context. Returns list of emoji strings."""
    system_msg = (
        "You output JSON with emoji arrays. "
        "Use ONLY Unicode emoji symbols like ☀️🌧️❄️🏙️🚶🧥🌙💨🌫️⛈️. "
        "NEVER use Chinese characters, English words, or text of any kind. "
        "Only graphical emoji symbols."
    )
    user_msg = (
        f"You are a tiny emoji artist. Given METAR aviation weather observations, "
        f"pick 6 emojis that capture the vibe of this moment (most evocative first). "
        f"Consider wind, visibility, clouds, precipitation, temperature, time of day.\n\n"
        f"{context}\n\n"
        f"Reply with: {{\"emojis\": [\"☀️\", \"🌧️\", ...]}}"
    )

    payload = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": user_msg},
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.7,
        "max_tokens": 80,
    }).encode()

    req = Request(
        f"{OLLAMA_HOST}/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
    )

    try:
        with urlopen(req, timeout=30) as resp:
            data = json.load(resp)
            content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
            # Parse the JSON response from the LLM
            llm_json = json.loads(content)
            emojis = llm_json.get("emojis", [])
            # Filter each element to only emoji characters (remove CJK, text, etc.)
            filtered = []
            for e in emojis:
                if e:
                    # Extract only emoji from each element
                    emoji_only = "".join(EMOJI_PATTERN.findall(e))
                    if emoji_only:
                        filtered.append(emoji_only)
            return filtered
    except (URLError, json.JSONDecodeError, KeyError):
        return []


def main():
    # Fetch METAR
    metar = fetch_metar()
    if not metar:
        output("❓❓❓❓", "METAR unavailable")

    # Build context with current time
    now = datetime.now()
    datetime_str = now.strftime("%A, %B %-d, %Y at %-I:%M %p")

    context = f"Date/time: {datetime_str}\nLocation: Manhattan area\n\n{metar}"

    # Get emojis from LLM
    emoji_list = call_ollama(context)

    # Clip to first 4 (most important)
    emoji_list = emoji_list[:4]

    # Pad to exactly 4 if needed
    padding_idx = 0
    while len(emoji_list) < 4:
        emoji_list.append(PADDING_EMOJIS[padding_idx % len(PADDING_EMOJIS)])
        padding_idx += 1

    output("".join(emoji_list), context)


if __name__ == "__main__":
    main()
