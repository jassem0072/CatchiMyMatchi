from __future__ import annotations

import os
import tempfile
from pathlib import Path
from urllib.parse import urlparse

import requests


def _is_url(path_or_url: str) -> bool:
    try:
        p = urlparse(path_or_url)
        return p.scheme in {"http", "https"}
    except Exception:
        return False


def resolve_local_video(path_or_url: str) -> tuple[str, callable]:
    """Returns (local_path, cleanup_fn)."""
    if not _is_url(path_or_url):
        return path_or_url, (lambda: None)

    suffix = Path(urlparse(path_or_url).path).suffix or ".mp4"
    fd, tmp_path = tempfile.mkstemp(prefix="scoutai_", suffix=suffix)
    os.close(fd)

    def cleanup() -> None:
        try:
            os.remove(tmp_path)
        except OSError:
            pass

    with requests.get(path_or_url, stream=True, timeout=60) as r:
        r.raise_for_status()
        with open(tmp_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    f.write(chunk)

    return tmp_path, cleanup
