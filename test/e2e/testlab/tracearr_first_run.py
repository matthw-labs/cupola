#!/usr/bin/env python3
"""Tracearr's first run in the testlab: the owner and the public API key.

A fresh Tracearr 3.1.4 has no one in it. The first account that signs up is its
owner, and the `trr_pub_` key the app reads with does not exist until the owner
asks for it. The bootstrap calls this module once, after the container is
healthy, and takes the key out of it. It is idempotent: a second bootstrap on
the same state finds the owner made and the key issued, and answers the same
key.

The sequence is the one measured on a real 3.1.4 (not read from its source):

1. `GET /health` answers 200 even while the migrations run, with
   `"mode":"maintenance"`; only `"mode":"ready"` is a Tracearr that can be
   spoken to.
2. `GET /api/v1/setup/status` says `needsSetup` while nobody is in. Then
   `POST /api/v1/auth/sign-up/email` makes the owner and answers the bearer in
   the `set-auth-token` header (the body's `token` is only the unsigned half).
   A username takes letters, digits, `_` and `.` and nothing else: a hyphen is
   a 400.
3. Once someone is in, the same route refuses, so the owner signs in with
   `POST /api/v1/auth/sign-in/email`.
4. `GET /api/v1/settings/api-key` reads the key, and
   `POST /api/v1/settings/api-key/regenerate` makes one when there is none.
   Regenerating replaces the key, so it is done only when the key is absent:
   the key the app holds must keep working across bootstraps.

The email and password are the lab's fixed owner (`cupola-pass`, the same as
Emby's administrator) and are the only credentials the module knows; the
bearer and the key never leave this process except in the mode 600 file the
caller names. Nothing secret is printed.

    python3 test/e2e/testlab/tracearr_first_run.py --url http://127.0.0.1:3010 \\
        --output "$state_dir/.tracearr-first-run.json"
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

OWNER_EMAIL = "owner@cupola.test"
OWNER_PASSWORD = "cupola-pass"
OWNER_NAME = "Cupola Lab"
OWNER_USERNAME = "cupola_owner"

KEY_PREFIX = "trr_pub_"


class FirstRunError(RuntimeError):
    """Tracearr refused a step, said without any secret in it."""


def call(
    base: str,
    path: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    bearer: str = "",
    timeout: float = 30,
) -> tuple[int, dict[str, str], Any]:
    """One call. Answers `(status, headers, body)`; the body is JSON or text.

    Headers come back lower-cased, which is how `set-auth-token` is read.
    """
    headers = {"Accept": "application/json"}
    if payload is not None:
        # Fastify refuses a JSON content type with no body (a DELETE, say).
        headers["Content-Type"] = "application/json"
    if bearer:
        headers["Authorization"] = f"Bearer {bearer}"
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{base}{path}", data=data, method=method, headers=headers
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body, status, answered = response.read(), response.status, response.headers
    except urllib.error.HTTPError as error:
        body, status, answered = error.read(), error.code, error.headers
    except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.HTTPException) as error:
        raise FirstRunError(f"{method} {path} did not answer: {error}") from error
    lowered = {name.lower(): value for name, value in answered.items()}
    if not body:
        return status, lowered, None
    try:
        return status, lowered, json.loads(body.decode("utf-8"))
    except json.JSONDecodeError:
        return status, lowered, body.decode("utf-8", errors="replace")


def wait_until_ready(base: str, *, timeout: float = 240) -> None:
    """Wait for `"mode":"ready"`, which the container's healthcheck also reads."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            status, _, body = call(base, "/health", timeout=3)
            if status == 200 and isinstance(body, dict) and body.get("mode") == "ready":
                return
        except FirstRunError:
            pass
        time.sleep(2)
    raise FirstRunError(f"Tracearr was not ready within {timeout:g}s")


def retrying(
    base: str, path: str, what: str, **kwargs: Any
) -> tuple[int, dict[str, str], Any]:
    """The call, again after a pause while Tracearr says 429 (its limiter)."""
    for attempt in range(6):
        status, headers, body = call(base, path, **kwargs)
        if status != 429:
            return status, headers, body
        time.sleep(min(30, 5 * (attempt + 1)))
    raise FirstRunError(f"{what} was rate limited for too long")


def needs_setup(base: str) -> bool:
    status, _, body = call(base, "/api/v1/setup/status")
    if status != 200 or not isinstance(body, dict):
        raise FirstRunError(f"the setup status answered {status}")
    return body.get("needsSetup") is True


def _bearer_of(status: int, headers: dict[str, str], what: str) -> str:
    token = headers.get("set-auth-token", "")
    if status != 200 or not token:
        raise FirstRunError(f"{what} answered {status} and no bearer")
    return token


def sign_up(base: str) -> str:
    status, headers, _ = retrying(
        base,
        "/api/v1/auth/sign-up/email",
        "the owner's sign-up",
        method="POST",
        payload={
            "email": OWNER_EMAIL,
            "password": OWNER_PASSWORD,
            "name": OWNER_NAME,
            "username": OWNER_USERNAME,
        },
    )
    return _bearer_of(status, headers, "the owner's sign-up")


def sign_in(base: str) -> str:
    """The owner's bearer. A refusal is worded without the password."""
    status, headers, _ = retrying(
        base,
        "/api/v1/auth/sign-in/email",
        "the owner's sign-in",
        method="POST",
        payload={"email": OWNER_EMAIL, "password": OWNER_PASSWORD},
    )
    return _bearer_of(status, headers, f"signing in as {OWNER_EMAIL}")


def _key_in(body: Any) -> str:
    """The `trr_pub_` string in an answer, wherever the answer keeps it."""
    if isinstance(body, str):
        return body if body.startswith(KEY_PREFIX) else ""
    if isinstance(body, dict):
        for value in body.values():
            found = _key_in(value)
            if found:
                return found
    return ""


def ensure_key(base: str, bearer: str) -> str:
    """The public API key: read if it exists, made once if it does not."""
    status, _, body = call(base, "/api/v1/settings/api-key", bearer=bearer)
    if status == 200:
        existing = _key_in(body)
        if existing:
            return existing
    status, _, body = call(
        base, "/api/v1/settings/api-key/regenerate", method="POST", payload={}, bearer=bearer
    )
    made = _key_in(body) if 200 <= status < 300 else ""
    if not made:
        raise FirstRunError(f"making the API key was refused with {status}")
    return made


def first_run(base: str) -> dict[str, Any]:
    """Make the owner if nobody is in; answer the bearer and the key.

    The bearer is for the module that goes on to connect the servers; it is
    never written to the file the bootstrap reads.
    """
    base = base.rstrip("/")
    wait_until_ready(base)
    made = False
    if needs_setup(base):
        bearer = sign_up(base)
        made = True
    else:
        bearer = sign_in(base)
    return {
        "owner": "made" if made else "already there",
        "bearer": bearer,
        "key": ensure_key(base, bearer),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Make Tracearr's owner and its public API key for the lab."
    )
    parser.add_argument("--url", default="http://127.0.0.1:3010")
    parser.add_argument("--output", type=Path, required=True,
                        help="where to write the answer (mode 600)")
    arguments = parser.parse_args(argv)
    try:
        answer = first_run(arguments.url)
    except FirstRunError as error:
        print(f"tracearr_first_run: {error}", file=sys.stderr)
        return 2
    # The file holds the key: open it 0600 from the first byte. The bearer is
    # a session and stays with this process.
    document = {"key": answer["key"], "ownerEmail": OWNER_EMAIL}
    descriptor = os.open(arguments.output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(document, handle)
    print(f"[tracearr] first run: owner {answer['owner']}, API key ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
