"""Build version stamp. Drop in as app/version.py (adjust the path hops below).

Reads the VERSION file written by the Dockerfile stamp stage. The APP_VERSION
environment variable wins if set, which keeps local runs and non-Docker
environments sane.
"""

import os
from pathlib import Path


def _stamp() -> tuple[str, str]:
    raw = os.getenv("APP_VERSION", "")
    if not raw:
        try:
            # parent.parent resolves /app/app/version.py -> /app/VERSION.
            # Adjust the number of .parent hops so this lands on the VERSION
            # file sitting next to your Dockerfile WORKDIR.
            raw = Path(__file__).resolve().parent.parent.joinpath("VERSION").read_text()
        except OSError:
            raw = ""
    version, _, commit = raw.strip().partition(" ")
    return version or "dev", commit or "unknown"


VERSION, COMMIT = _stamp()
