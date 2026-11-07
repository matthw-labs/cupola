#!/usr/bin/env python3
"""Runs a session journey with the playbacks the app cannot open itself.

S-03 and S-09 drive *Now playing* from the app, and the app's Pause and Stop
are remote control: the server only changes a session when a client is
listening. The only such client is the lab's own player, and it has to run on
the host, because a journey runs on the iOS simulator where starting a process
is forbidden.

So this wrapper owns the host side of those two journeys: it reads the lab's
own titles from the server (Jellyfin by default, Emby with `--server emby`),
opens one playback for S-03 (or two, on two devices, for S-09), waits until the
server lists them, runs the journey, and ends the players on the way out (their
sockets close, and the server drops the playback).

~~~bash
python3 test/e2e/testlab/journey_sessions.py S-03
python3 test/e2e/testlab/journey_sessions.py S-09 --simulator 403B5E0A-6A4E-4CB4-A151-87A6DA34E55F
python3 test/e2e/testlab/journey_sessions.py S-03 --server emby
~~~

Nothing secret is printed: the token is read from the lab's credentials file,
which bootstrap wrote with mode 600, and travels only in the player's
environment and in this process's requests.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TESTLAB = ROOT / "test" / "e2e" / "testlab"
JOURNEY_FILE = ROOT / "integration_test" / "journeys" / "media_server_journey_test.dart"
SIMULATOR = "403B5E0A-6A4E-4CB4-A151-87A6DA34E55F"


@dataclass(frozen=True)
class Server:
    """One media server of the lab, as the wrapper has to speak to it."""

    name: str
    url: str
    #: Where the API lives under the address (Emby answers under `/emby`).
    base: str
    #: The credentials-file name of what the wrapper reads the server with.
    credential: str
    #: The playback client that holds a session on it.
    player: str
    #: The journey tests of this server, by the words their names carry. A
    #: plain-name filter is a substring match, so each is distinctive enough
    #: not to select the other server's test.
    journey: dict[str, str]


SERVERS = {
    "jellyfin": Server(
        name="Jellyfin",
        url="http://127.0.0.1:8096",
        base="",
        credential="CUPOLA_TESTLAB_JELLYFIN_TOKEN",
        player="jellyfin_play.py",
        journey={
            "S-03": "S-03 · pause, resume, message and stop a Jellyfin playback",
            "S-09": "S-09 · Now playing draws one and two playbacks",
        },
    ),
    "emby": Server(
        name="Emby",
        url="http://127.0.0.1:8097",
        base="/emby",
        credential="CUPOLA_TESTLAB_EMBY_TOKEN",
        player="emby_play.py",
        journey={
            "S-03": "S-03 · pause, resume, message and stop an Emby playback",
            "S-09": "S-09 · Now playing draws one and two Emby playbacks",
        },
    ),
}

# The two devices S-09 draws as two rows, and the one S-03 commands.
S03_DEVICE = "cupola-s03"
S09_DEVICES = ("cupola-s09a", "cupola-s09b")


class JourneyError(RuntimeError):
    """Something the wrapper can say plainly, without a traceback."""


def state_root() -> Path:
    override = os.environ.get("CUPOLA_TESTLAB_STATE_DIR")
    return Path(override) if override else ROOT / ".ai" / "scratch" / "zz_testlab" / "state"


def credentials() -> Path:
    override = os.environ.get("CUPOLA_TESTLAB_CREDENTIALS_FILE")
    return Path(override) if override else state_root() / "credentials.env"


def token(server: Server) -> str:
    path = credentials()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise JourneyError(f"the lab credentials at {path} cannot be read: {error}")
    for line in lines:
        name, separator, value = line.partition("=")
        if separator and name.strip() == server.credential:
            value = value.strip().strip('"').strip("'")
            if value:
                return value
    raise JourneyError(f"the lab credentials at {path} hold no {server.name} token")


def read(server: Server, path: str, *, token_value: str) -> object:
    request = urllib.request.Request(f"{server.url}{server.base}{path}")
    if server is SERVERS["emby"]:
        # Emby reads the key from one header, whatever the route.
        request.add_header("X-Emby-Token", token_value)
    else:
        request.add_header(
            "Authorization",
            f'MediaBrowser Client="Cupola journeys", Device="host", '
            f'DeviceId="cupola-journey-host", Version="test", Token="{token_value}"',
        )
    request.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=20) as answer:
            body = answer.read()
    except OSError as error:
        raise JourneyError(f"{server.name} did not answer {path}: {error}")
    return json.loads(body) if body else None


def titles(server: Server, token_value: str) -> tuple[str, str]:
    """The lab's own film and episode, by the names the app draws."""

    def first(kind: str) -> str:
        answer = read(
            server,
            f"/Items?IncludeItemTypes={kind}&Recursive=true&Limit=1",
            token_value=token_value,
        )
        rows = answer.get("Items") if isinstance(answer, dict) else None
        if not rows:
            raise JourneyError(f"the {server.name} library holds no {kind.lower()}")
        return rows[0]["Name"]

    return first("Movie"), first("Episode")


def sessions(server: Server, token_value: str) -> list[dict]:
    answer = read(server, "/Sessions", token_value=token_value)
    return [row for row in answer if isinstance(row, dict)] if isinstance(answer, list) else []


def wait_for(
    server: Server, devices: tuple[str, ...], token_value: str, timeout: float = 40
) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        names = {row.get("DeviceName") for row in sessions(server, token_value)}
        if all(device in names for device in devices):
            return
        time.sleep(0.5)
    raise JourneyError(f"the server never listed the playback on {', '.join(devices)}")


def player(server: Server, device: str, title: str) -> subprocess.Popen:
    environment = dict(os.environ)
    environment["CUPOLA_TESTLAB_STATE_DIR"] = str(state_root())
    environment["CUPOLA_TESTLAB_CREDENTIALS_FILE"] = str(credentials())
    return subprocess.Popen(
        [
            sys.executable,
            str(TESTLAB / server.player),
            "--device",
            device,
            "--title",
            title,
            "--listen",
            "--hold",
            "600",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=environment,
    )


def run(mode: str, simulator: str, server: Server) -> int:
    token_value = token(server)
    film, episode = titles(server, token_value)
    if mode == "S-03":
        devices = (S03_DEVICE,)
        players = [player(server, S03_DEVICE, film)]
    elif mode == "S-09":
        devices = S09_DEVICES
        players = [
            player(server, S09_DEVICES[0], film),
            player(server, S09_DEVICES[1], episode),
        ]
    else:
        raise JourneyError(f"unknown journey {mode}; use S-03 or S-09")
    try:
        wait_for(server, devices, token_value)
        command = [
            "flutter",
            "test",
            "--no-pub",
            str(JOURNEY_FILE),
            "-d",
            simulator,
            "--tags",
            "e2e",
            "--run-skipped",
            "--plain-name",
            server.journey[mode],
        ]
        return subprocess.run(command, cwd=ROOT).returncode
    finally:
        for process in players:
            process.terminate()
        for process in players:
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("S-03", "S-09"))
    parser.add_argument("--simulator", default=SIMULATOR)
    parser.add_argument("--server", choices=tuple(SERVERS), default="jellyfin")
    arguments = parser.parse_args()
    try:
        return run(arguments.mode, arguments.simulator, SERVERS[arguments.server])
    except JourneyError as error:
        print(f"journey_sessions: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
