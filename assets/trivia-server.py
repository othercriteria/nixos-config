#!/usr/bin/env python3
"""Trivia drip-release file server.

Serves files out of ``$TRIVIA_ROOT`` (default ``/var/lib/trivia/rounds``).
Each subdirectory under the root represents one round of a trivia event and
must be named::

    <ISO-8601 local time>__<slug>

For example ``2026-06-07T19:00:00__round-1``. The timestamp gates when the
round becomes visible (the filesystem name is also the schedule). The slug
appears in URL paths; the timestamp does not.

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

Security considerations live in two places:

1. ``DIR_RE``/``FILENAME_RE`` restrict what counts as a valid round/file
   name. Anything else is silently ignored at discovery time or returns 404.
2. ``safe_round_dir`` resolves every candidate path and requires that the
   resolved location stay under the configured root. ``round_file`` also
   refuses to serve symlinks. Combined, these block traversal via crafted
   names and via symlinks dropped into the rounds directory.

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
from typing import Iterable

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse

ROOT = Path(os.environ.get("TRIVIA_ROOT", "/var/lib/trivia/rounds"))
HOST = os.environ.get("TRIVIA_HOST", "127.0.0.1")
PORT = int(os.environ.get("TRIVIA_PORT", "8765"))

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
DIR_RE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"
    r"__(?P<slug>[a-z0-9][a-z0-9-]*)$"
)
FILENAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,255}$")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("trivia")

app = FastAPI(
    title="trivia",
    description="Drip-release file server for a trivia contest",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)


def _now() -> datetime:
    return datetime.now()


def discover() -> Iterable[tuple[str, datetime, Path]]:
    """Yield ``(slug, release_at, directory_path)`` for well-named rounds.

    Silently skips anything that doesn't match ``DIR_RE`` or whose timestamp
    component fails ``fromisoformat``. The filesystem is the source of truth;
    fixture and operator mistakes (typoed names, dangling symlinks) drop out
    of the listing without raising.
    """
    if not ROOT.is_dir():
        return
    for child in sorted(ROOT.iterdir()):
        if not child.is_dir():
            continue
        m = DIR_RE.match(child.name)
        if not m:
            continue
        try:
            release_at = datetime.fromisoformat(m.group("ts"))
        except ValueError:
            continue
        yield m.group("slug"), release_at, child


def safe_round_dir(slug: str) -> Path:
    """Return the resolved directory for ``slug`` iff it's released and safe.

    "Safe" means the resolved real path stays under ``ROOT``. A directory
    that is itself a symlink pointing outside the root is treated as
    nonexistent.
    """
    root_real = ROOT.resolve()
    now = _now()
    for s, release_at, path in discover():
        if s != slug:
            continue
        if release_at > now:
            raise HTTPException(status_code=404)
        try:
            real = path.resolve(strict=True)
        except (FileNotFoundError, RuntimeError):
            raise HTTPException(status_code=404)
        try:
            real.relative_to(root_real)
        except ValueError:
            log.warning(
                "rejecting round dir that escapes ROOT: slug=%s path=%s real=%s",
                slug, path, real,
            )
            raise HTTPException(status_code=404)
        return real
    raise HTTPException(status_code=404)


def _page(title: str, body: str) -> str:
    return (
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
        "small{color:#57606a;}"
        ".empty{color:#57606a;font-style:italic;}"
        "</style></head><body>"
        f"<h1>{escape(title)}</h1>"
        f"{body}"
        "</body></html>"
    )


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    now = _now()
    rounds = list(discover())
    rounds.sort(key=lambda r: r[1])
    revealed = [(s, t) for s, t, _ in rounds if t <= now]
    upcoming = [(s, t) for s, t, _ in rounds if t > now]

    parts: list[str] = []
    if revealed:
        parts.append("<h2>Available</h2><ul>")
        for slug, release_at in revealed:
            parts.append(
                f'<li><a href="/{escape(slug)}/">{escape(slug)}</a> '
                f"<small>released {escape(release_at.isoformat(timespec='minutes'))}"
                "</small></li>"
            )
        parts.append("</ul>")
    else:
        parts.append('<p class="empty">No rounds available yet.</p>')

    if upcoming:
        parts.append("<h2>Upcoming</h2><ul>")
        for slug, release_at in upcoming:
            parts.append(
                f"<li>{escape(slug)} &mdash; "
                f"<small>{escape(release_at.isoformat(timespec='minutes'))}</small>"
                "</li>"
            )
        parts.append("</ul>")
    return _page("Trivia", "".join(parts))


@app.get("/{slug}/", response_class=HTMLResponse)
def round_index(slug: str) -> str:
    if not SLUG_RE.fullmatch(slug):
        raise HTTPException(status_code=404)
    base = safe_round_dir(slug)
    files = sorted(f.name for f in base.iterdir() if f.is_file() and not f.is_symlink())
    files = [f for f in files if FILENAME_RE.fullmatch(f)]
    if not files:
        body = f'<p class="empty">No files in this round.</p><p><a href="/">&larr; back</a></p>'
    else:
        items = "".join(
            f'<li><a href="/{escape(slug)}/{escape(f)}">{escape(f)}</a></li>'
            for f in files
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
    return FileResponse(raw, filename=filename)


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
