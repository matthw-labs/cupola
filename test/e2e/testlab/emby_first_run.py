#!/usr/bin/env python3
"""Emby's first run in the testlab: the wizard, the administrator and the key.

A fresh Emby 4.10 asks for a name, a language and a first user before it does
anything else, and it has no API key until an administrator makes one. The
bootstrap calls this module once, after the container is healthy, and takes
two facts out of it: the administrator's user id, and the API key the app is
given. It is idempotent, so a second bootstrap on the same state finds the
wizard done and the key made, and answers the same two facts.

The sequence is the one measured on a real 4.10.2 (nothing here is read from
Emby's OpenAPI file, which is wrong about several of these routes):

1. `GET /emby/Startup/Configuration` answers 200 while the wizard is open and
   401 once it is done, which is the one honest way to tell the two apart (the
   public info carries no such flag, unlike Jellyfin's).
2. `POST /Startup/Configuration`, `POST /Startup/User` with the administrator's
   name and password, `POST /Startup/Complete`.
3. `POST /Users/AuthenticateByName` with an `X-Emby-Authorization` header, which
   is a person's session and not a key.
4. `POST /Auth/Keys?App=Cupola` with that session's token, then `GET /Auth/Keys`
   to read the key back: the create call answers 204 and no body.

The key is named `Cupola` and nothing else, so a lab that already has one is
recognised by that name. The password is the lab's fixed administrator password
(`cupola-pass`, the same as Jellyfin's) and the answer is written to a file of
mode 600 that the caller names; no secret is printed.

    python3 test/e2e/testlab/emby_first_run.py --url http://127.0.0.1:8097 \\
        --output "$state_dir/.emby-first-run.json"
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

ADMIN_NAME = "cupola-admin"
ADMIN_PASSWORD = "cupola-pass"
KEY_APP = "Cupola"

_HEADER = (
    'MediaBrowser Client="Cupola", Device="Cupola TestLab", '
    'DeviceId="cupola-testlab", Version="1.0"'
)


class FirstRunError(RuntimeError):
    """The server refused a step, said without any secret in it."""


def _call(
    base: str,
    path: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    token: str = "",
    timeout: float = 30,
) -> tuple[int, Any]:
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-Emby-Authorization": _HEADER,
    }
    if token:
        headers["X-Emby-Token"] = token
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{base}/emby{path}", data=data, method=method, headers=headers
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body, status = response.read(), response.status
    except urllib.error.HTTPError as error:
        body, status = error.read(), error.code
    except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.HTTPException) as error:
        raise FirstRunError(f"{method} {path} did not answer: {error}") from error
    if not body:
        return status, None
    try:
        return status, json.loads(body.decode("utf-8"))
    except json.JSONDecodeError:
        return status, body.decode("utf-8", errors="replace")


def wait_until_up(base: str, *, timeout: float = 120) -> None:
    """Wait for the unauthenticated route the container's healthcheck uses."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            status, _ = _call(base, "/System/Info/Public", timeout=3)
            if status == 200:
                return
        except FirstRunError:
            pass
        time.sleep(1)
    raise FirstRunError(f"Emby did not answer within {timeout:g}s")


def wizard_open(base: str) -> bool:
    status, _ = _call(base, "/Startup/Configuration")
    return status == 200


def walk_wizard(base: str) -> None:
    """The three first-run posts, with the administrator's name and password."""
    steps = (
        (
            "/Startup/Configuration",
            {
                "ServerName": "Cupola Lab",
                "UICulture": "en-US",
                "MetadataCountryCode": "US",
                "PreferredMetadataLanguage": "en",
            },
        ),
        ("/Startup/User", {"Name": ADMIN_NAME, "Password": ADMIN_PASSWORD}),
        ("/Startup/Complete", None),
    )
    for path, payload in steps:
        status, _ = _call(base, path, method="POST", payload=payload)
        if not 200 <= status < 300:
            raise FirstRunError(f"the wizard refused {path} with {status}")


def sign_in(base: str) -> tuple[str, str]:
    """The administrator's session: `(token, user id)`."""
    status, answer = _call(
        base,
        "/Users/AuthenticateByName",
        method="POST",
        payload={"Username": ADMIN_NAME, "Pw": ADMIN_PASSWORD},
    )
    if status != 200 or not isinstance(answer, dict):
        raise FirstRunError(f"signing in as {ADMIN_NAME} was refused with {status}")
    token = str(answer.get("AccessToken") or "")
    user_id = str((answer.get("User") or {}).get("Id") or "")
    if not token or not user_id:
        raise FirstRunError(f"signing in as {ADMIN_NAME} answered no token and no user")
    return token, user_id


def _key_named(base: str, session: str) -> str:
    status, answer = _call(base, "/Auth/Keys", token=session)
    if status != 200 or not isinstance(answer, dict):
        raise FirstRunError(f"reading the API keys was refused with {status}")
    for row in answer.get("Items") or []:
        if isinstance(row, dict) and row.get("AppName") == KEY_APP:
            return str(row.get("AccessToken") or "")
    return ""


def ensure_key(base: str, session: str) -> str:
    """The `Cupola` API key, made once and read back."""
    existing = _key_named(base, session)
    if existing:
        return existing
    status, _ = _call(
        base, f"/Auth/Keys?App={KEY_APP}", method="POST", token=session
    )
    if not 200 <= status < 300:
        raise FirstRunError(f"creating the API key was refused with {status}")
    made = _key_named(base, session)
    if not made:
        raise FirstRunError("Emby did not list the API key it just made")
    return made


def first_run(base: str) -> dict[str, Any]:
    """Walk the wizard if it is open; answer the key and the administrator."""
    base = base.rstrip("/")
    wait_until_up(base)
    walked = False
    if wizard_open(base):
        walk_wizard(base)
        walked = True
    session, user_id = sign_in(base)
    return {
        "wizard": "walked" if walked else "already done",
        "userId": user_id,
        "token": ensure_key(base, session),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Walk Emby's first-run wizard and make the lab's API key."
    )
    parser.add_argument("--url", default="http://127.0.0.1:8097")
    parser.add_argument("--output", type=Path, required=True,
                        help="where to write the answer (mode 600)")
    arguments = parser.parse_args(argv)
    try:
        answer = first_run(arguments.url)
    except FirstRunError as error:
        print(f"emby_first_run: {error}", file=sys.stderr)
        return 2
    # The file holds the key: open it 0600 from the first byte.
    descriptor = os.open(arguments.output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(answer, handle)
    print(f"[emby] first run: wizard {answer['wizard']}, API key ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
