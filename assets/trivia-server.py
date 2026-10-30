#!/usr/bin/env python3
"""Trivia drip-release file server.

Serves files out of ``$TRIVIA_ROOT`` (default ``/var/lib/trivia/rounds``).
Each subdirectory under the root represents one round of a trivia event and
must be named::

    <ISO-8601 local time>__<slug>

For example ``2026-06-07T19:00:00__round-1``. The timestamp gates when the
round becomes visible (the filesystem name is also the schedule). The slug
appears in URL paths; the timestamp does not. Wall times are interpreted in
the host's local timezone (``$TRIVIA_TZ`` is a display label only).

The app is deliberately tiny:

- No database: discovery is ``os.listdir`` of the root on every request.
- No cron: comparing ``datetime.now()`` to the parsed timestamp is the only
  scheduling logic.
- No state: a restart, redeploy, or reboot doesn't change anything observable.
- ``FileResponse`` (Starlette) supports HTTP ``Range`` requests so MP3 seek
  and resumable downloads work without extra effort.

Endpoints:

- ``GET /``                          Index page; lists revealed and upcoming rounds.
- ``GET /<slug>/``                   Listing for a revealed round.
- ``GET /<slug>/<filename>``         Single file inside a revealed round.

If several directories share a slug, the latest timestamp that has already
passed is the one that is served. An earlier copy does not hide a later
release, and a not-yet-released copy does not hide one that is already open.

Security considerations live in two places:

1. ``DIR_RE``/``FILENAME_RE`` restrict what counts as a valid round/file
   name. Anything else is skipped at discovery time or returns 404.
2. ``discover`` resolves every round directory and drops symlinks and paths
   that escape the root. ``round_file`` also refuses to serve symlinks.
   Combined, these block traversal via crafted names and via symlinks
   dropped into the rounds directory.

Listings are ``Cache-Control: no-store`` so a phone that loaded the index
before a round opened does not keep showing the old page. PDFs, images, and
audio are served inline. HTML and SVG are attachments with a generic media
type: those formats execute in the trivia origin, and the browser will
replay the contestant's Basic Auth credentials on any request they make.

This module is exposed as ``app`` for ``uvicorn``; ``python trivia-server.py``
also launches uvicorn directly so it can be ``ExecStart``-ed without an
extra wrapper.
"""

from __future__ import annotations

import logging
import os
import re
from datetime import datetime
from html import escape
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

ROOT = Path(os.environ.get("TRIVIA_ROOT", "/var/lib/trivia/rounds"))
HOST = os.environ.get("TRIVIA_HOST", "127.0.0.1")
PORT = int(os.environ.get("TRIVIA_PORT", "8765"))
TZ_LABEL = os.environ.get("TRIVIA_TZ") or "local time"

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
DIR_RE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"
    r"__(?P<slug>[a-z0-9][a-z0-9-]*)$"
)
FILENAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,255}$")

# Browsers should display these. HTML/SVG/XML are absent on purpose.
INLINE_TYPES = {
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".mp3": "audio/mpeg",
    ".m4a": "audio/mp4",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg",
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".txt": "text/plain",
    ".csv": "text/csv",
}

HTML_HEADERS = {
    "Cache-Control": "no-store",
    "Content-Security-Policy": (
        "default-src 'none'; style-src 'unsafe-inline'; "
        "img-src 'self'; base-uri 'none'; form-action 'none'"
    ),
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("trivia")

# Misnamed rounds are easy to miss at 7pm. Log each name once per process
# so a typo shows up in the journal without a line per refresh.
_noted: set[str] = set()

app = FastAPI(
    title="trivia",
    description="Drip-release file server for a trivia contest",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)


def _now() -> datetime:
    return datetime.now()


def _note(name: str, reason: str) -> None:
    if name in _noted:
        return
    _noted.add(name)
    log.warning("ignoring round entry %s: %s", name, reason)


def _format_when(release_at: datetime) -> str:
    # Directory timestamps are naive local wall times. The label is the
    # host timezone name so contestants are not left guessing UTC.
    # Include the calendar date. Weekday and clock alone make a
    # previous contest look like the coming weekend.
    return f"{release_at.strftime('%a %b %-d, %-I:%M %p')} {TZ_LABEL}"


def discover() -> list[tuple[str, datetime, Path]]:
    """Return ``(slug, release_at, resolved_directory)`` for safe rounds.

    Skips non-directories, symlink directories, names that fail ``DIR_RE``
    or ``fromisoformat``, and anything whose resolved path escapes ``ROOT``.
    """
    if not ROOT.is_dir():
        return []
    root_real = ROOT.resolve()
    found: list[tuple[str, datetime, Path]] = []
    for child in sorted(ROOT.iterdir()):
        name = child.name
        if child.is_symlink():
            if DIR_RE.fullmatch(name):
                _note(name, "round directory is a symlink")
            continue
        if not child.is_dir():
            continue
        match = DIR_RE.fullmatch(name)
        if not match:
            _note(name, "name is not <local-time>__<slug>")
            continue
        try:
            release_at = datetime.fromisoformat(match.group("ts"))
        except ValueError:
            _note(name, "timestamp is not a real local time")
            continue
        try:
            real = child.resolve(strict=True)
            real.relative_to(root_real)
        except (OSError, RuntimeError, ValueError):
            _note(name, "resolved path escapes the rounds directory")
            continue
        found.append((match.group("slug"), release_at, real))
    return found


def safe_round_dir(slug: str) -> Path:
    """Resolved directory for the latest released copy of ``slug``."""
    now = _now()
    best: tuple[datetime, Path] | None = None
    for found_slug, release_at, path in discover():
        if found_slug != slug or release_at > now:
            continue
        if best is None or release_at > best[0]:
            best = (release_at, path)
    if best is None:
        raise HTTPException(status_code=404)
    return best[1]


def _suffix(filename: str) -> str:
    dot = filename.rfind(".")
    if dot <= 0:
        return ""
    return filename[dot:].lower()


def _page(title: str, body: str) -> HTMLResponse:
    html = (
        "<!doctype html>"
        "<html lang=\"en\"><head><meta charset=\"utf-8\">"
        f"<title>{escape(title)}</title>"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
        "<style>"
        "body{font-family:system-ui,-apple-system,sans-serif;max-width:42rem;"
        "margin:2rem auto;padding:0 1rem;color:#1f2328;background:#fafbfc;}"
        "h1{margin-bottom:0.25rem;}"
        "h2{margin-top:1.75rem;font-size:1.1rem;color:#57606a;"
        "border-bottom:1px solid #d0d7de;padding-bottom:0.25rem;}"
        "ul{padding-left:1.25rem;}"
        "li{margin:0.25rem 0;}"
        "a{color:#0969da;text-decoration:none;}"
        "a:hover{text-decoration:underline;}"
        "small,p.hint{color:#57606a;}"
        ".empty{color:#57606a;font-style:italic;}"
        "</style></head><body>"
        f"<h1>{escape(title)}</h1>"
        f"{body}"
        "</body></html>"
    )
    return HTMLResponse(html, headers=HTML_HEADERS)


def _schedule(now: datetime) -> tuple[list[tuple[str, datetime]], list[tuple[str, datetime]]]:
    released: dict[str, datetime] = {}
    upcoming: dict[str, datetime] = {}
    for slug, release_at, _path in discover():
        if release_at <= now:
            previous = released.get(slug)
            if previous is None or release_at > previous:
                released[slug] = release_at
        else:
            previous = upcoming.get(slug)
            if previous is None or release_at < previous:
                upcoming[slug] = release_at
    for slug in released:
        upcoming.pop(slug, None)
    revealed_rows = sorted(released.items(), key=lambda item: item[1])
    upcoming_rows = sorted(upcoming.items(), key=lambda item: item[1])
    return revealed_rows, upcoming_rows


@app.exception_handler(StarletteHTTPException)
async def no_store_errors(_request, exc: StarletteHTTPException) -> JSONResponse:
    # A cached 404 from before a round opens would outlive the reveal.
    headers = dict(exc.headers or {})
    headers["Cache-Control"] = "no-store"
    return JSONResponse(
        {"detail": exc.detail},
        status_code=exc.status_code,
        headers=headers,
    )


@app.get("/", response_class=HTMLResponse)
def index() -> HTMLResponse:
    now = _now()
    revealed, upcoming = _schedule(now)

    parts: list[str] = [
        '<p class="hint">Refresh this page when a round is due. '
        "Times are local to the server.</p>"
    ]
    if revealed:
        parts.append("<h2>Available</h2><ul>")
        for slug, release_at in revealed:
            parts.append(
                f'<li><a href="/{escape(slug)}/">{escape(slug)}</a> '
                f"<small>released {escape(_format_when(release_at))}</small></li>"
            )
        parts.append("</ul>")
    else:
        parts.append('<p class="empty">No rounds available yet.</p>')

    if upcoming:
        parts.append("<h2>Upcoming</h2><ul>")
        for slug, release_at in upcoming:
            parts.append(
                f"<li>{escape(slug)} &mdash; "
                f"<small>{escape(_format_when(release_at))}</small></li>"
            )
        parts.append("</ul>")
    return _page("Trivia", "".join(parts))


@app.get("/{slug}/", response_class=HTMLResponse)
def round_index(slug: str) -> HTMLResponse:
    if not SLUG_RE.fullmatch(slug):
        raise HTTPException(status_code=404)
    base = safe_round_dir(slug)
    names = sorted(
        entry.name
        for entry in base.iterdir()
        if entry.is_file() and not entry.is_symlink() and FILENAME_RE.fullmatch(entry.name)
    )
    if not names:
        body = '<p class="empty">No files in this round.</p><p><a href="/">&larr; back</a></p>'
    else:
        items = "".join(
            f'<li><a href="/{escape(slug)}/{escape(name)}">{escape(name)}</a></li>'
            for name in names
        )
        body = f"<ul>{items}</ul><p><a href=\"/\">&larr; back</a></p>"
    return _page(slug, body)


@app.get("/{slug}/{filename}")
def round_file(slug: str, filename: str) -> FileResponse:
    if not SLUG_RE.fullmatch(slug) or not FILENAME_RE.fullmatch(filename):
        raise HTTPException(status_code=404)
    base = safe_round_dir(slug)
    raw = base / filename
    # Refuse symlinks outright: even if they resolve inside the round dir,
    # we have no reason to serve them and they're an easy escape vector.
    if raw.is_symlink():
        log.warning("rejecting symlink: slug=%s filename=%s", slug, filename)
        raise HTTPException(status_code=404)
    if not raw.is_file():
        raise HTTPException(status_code=404)
    try:
        real = raw.resolve(strict=True)
        real.relative_to(base)
    except (OSError, RuntimeError, ValueError):
        log.warning("rejecting file that escapes round dir: slug=%s filename=%s", slug, filename)
        raise HTTPException(status_code=404)

    headers = {"Cache-Control": "private"}
    media_type = INLINE_TYPES.get(_suffix(filename))
    if media_type is None:
        # HTML, SVG, and anything else we do not explicitly display.
        # application/octet-stream plus attachment keeps it from running
        # as a page on this origin.
        return FileResponse(
            real,
            filename=filename,
            media_type="application/octet-stream",
            content_disposition_type="attachment",
            headers=headers,
        )
    return FileResponse(
        real,
        filename=filename,
        media_type=media_type,
        content_disposition_type="inline",
        headers=headers,
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host=HOST,
        port=PORT,
        log_level="info",
        access_log=False,
        proxy_headers=True,
        forwarded_allow_ips="127.0.0.1",
    )
