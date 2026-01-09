#!/usr/bin/env python3
"""
Weather + time vibe as three emojis for Waybar.

Uses Open-Meteo API for weather data, local Ollama LLM for creative emoji selection.
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
LAT = os.environ.get("WEATHER_LAT", "40.7831")
LON = os.environ.get("WEATHER_LON", "-73.9712")
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://ollama.home.arpa")
MODEL = os.environ.get("OLLAMA_DEFAULT_MODEL", "qwen2.5:14b-instruct-q8_0")

# Weather code descriptions (WMO codes)
WEATHER_CODES = {
    0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
    45: "Foggy", 48: "Depositing rime fog",
    51: "Light drizzle", 53: "Moderate drizzle", 55: "Dense drizzle",
    56: "Light freezing drizzle", 57: "Dense freezing drizzle",
    61: "Slight rain", 63: "Moderate rain", 65: "Heavy rain",
    66: "Light freezing rain", 67: "Heavy freezing rain",
    71: "Slight snow", 73: "Moderate snow", 75: "Heavy snow",
    77: "Snow grains",
    80: "Slight rain showers", 81: "Moderate rain showers", 82: "Violent rain showers",
    85: "Slight snow showers", 86: "Heavy snow showers",
    95: "Thunderstorm", 96: "Thunderstorm with slight hail", 99: "Thunderstorm with heavy hail",
}


def output(text: str, tooltip: str) -> None:
    """Output JSON for Waybar."""
    # ensure_ascii=False to properly handle emoji without escaping
    print(json.dumps({"text": text, "tooltip": tooltip}, ensure_ascii=False))
    sys.exit(0)


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


def fetch_weather() -> dict | None:
    """Fetch current weather from Open-Meteo API."""
    url = (
        f"https://api.open-meteo.com/v1/forecast?"
        f"latitude={LAT}&longitude={LON}"
        f"&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"
        f"&temperature_unit=fahrenheit&timezone=auto"
    )
    try:
        with urlopen(url, timeout=5) as resp:
            return json.load(resp)
    except (URLError, json.JSONDecodeError):
        return None


def call_ollama(context: str) -> list[str]:
    """Call Ollama to generate emojis for the given context. Returns list of emoji strings."""
    system_msg = (
        "You output JSON with emoji arrays. "
        "Use ONLY Unicode emoji symbols like ☀️🌧️❄️🏙️🚶🧥🌙. "
        "NEVER use Chinese characters, English words, or text of any kind. "
        "Only graphical emoji symbols."
    )
    user_msg = (
        f"Pick 6 emojis that capture the vibe of this moment (most evocative first):\n\n"
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
    # Fetch weather
    weather = fetch_weather()
    if not weather:
        output("❓❓❓", "Weather API unavailable")

    # Parse weather data
    current = weather.get("current", {})
    temp = current.get("temperature_2m", "?")
    feels_like = current.get("apparent_temperature", "?")
    humidity = current.get("relative_humidity_2m", "?")
    wind = current.get("wind_speed_10m", "?")
    code = current.get("weather_code", 0)
    is_day = current.get("is_day", 1)

    weather_desc = WEATHER_CODES.get(code, f"Unknown ({code})")
    daynight = "daytime" if is_day else "nighttime"

    # Build context
    now = datetime.now()
    datetime_str = now.strftime("%A, %B %-d, %Y at %-I:%M %p")

    context = f"""Location: Manhattan, New York
Date and time: {datetime_str}
Time of day: {daynight}
Weather: {weather_desc}
Temperature: {temp}°F (feels like {feels_like}°F)
Humidity: {humidity}%
Wind: {wind} mph"""

    # Get emojis from LLM (returns list of emoji strings)
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
