#!/usr/bin/env python3
"""Tracearr in the testlab: its two servers, its rule, and what it sees.

The lab's Tracearr (3.1.4, one container with TimescaleDB and Redis inside)
comes out of `tracearr_first_run.py` with an owner and a public key. This
module brings the rest of the monitor the flow catalogue reads, idempotently:

* **Its two servers**: the lab's Jellyfin and Emby, connected the way the
  owner connects them in the web app (`POST /api/v1/auth/<kind>/connect-api-key`).
  Tracearr dials them from inside the compose network, so it is given the
  service names (`http://jellyfin:8096`, `http://emby:8096`), not the ports the
  host sees. Each gets an API key of its own named `Tracearr`, made through the
  server's administrator, so that rewinding the key the app holds never breaks
  the monitor. Connecting a server it already holds answers the same id.
* **Its rule**: `Too many streams at once`, from Tracearr's own template
  (`concurrent-streams`) with one stream allowed and the same device not
  excused, and no cooldown. That is the rule the throwaway Tracearr of the
  probe produced real violations with; `POST /api/v1/templates/{id}/instantiate`
  is what its web app calls to make it, and it is made once, found by name.
* **What it sees**: `streams`, `history` and `violations`, read with the public
  key the way the app reads them, so a scenario can wait for Tracearr to have
  noticed a playback instead of sleeping.

Nothing here writes Tracearr's database. The owner's password is the lab's
fixed one and is only ever sent in a sign-in body; the key is read from the
credentials file; nothing secret is printed.

    python3 test/e2e/testlab/tracearr_lab.py            # connect and make the rule
    python3 test/e2e/testlab/tracearr_lab.py --verify   # read what is there

Against a disposable stack, name the addresses: the host's view of Tracearr, of
Jellyfin and of Emby (`CUPOLA_TESTLAB_TRACEARR_URL`, `CUPOLA_TESTLAB_JELLYFIN_URL`,
`CUPOLA_TESTLAB_EMBY_URL`) and the names Tracearr dials them at
(`CUPOLA_TESTLAB_TRACEARR_JELLYFIN_URL`, `CUPOLA_TESTLAB_TRACEARR_EMBY_URL`).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import emby_first_run as emby_admin
import emby_play as emby
import jellyfin_play as jellyfin
import tracearr_first_run as first_run

TRACEARR = os.environ.get("CUPOLA_TESTLAB_TRACEARR_URL", "http://127.0.0.1:3010").rstrip("/")

#: The name of the key each media server is asked for, for Tracearr alone.
KEY_APP = "Tracearr"

RULE_NAME = "Too many streams at once"
RULE_TEMPLATE = "concurrent-streams"
#: One stream allowed, and a second on the same device counts too: the scenario
#: plays two devices, but a rule that excused a device would make a second
#: playback on one of them silent, which is not what the lab wants to show.
RULE_INPUTS: dict[str, Any] = {"max": 1, "ignoreSameDevice": False}

V2 = "/api/v2/public"


class TracearrError(RuntimeError):
    """The monitor refused a step, or does not hold what the lab promised."""


@dataclass(frozen=True)
class Watched:
    """One media server Tracearr is connected to."""

    kind: str
    name: str
    #: Where Tracearr dials it: a service name on the lab's network.
    inside: str


def watched() -> tuple[Watched, ...]:
    return (
        Watched(
            "jellyfin",
            "Lab Jellyfin",
            os.environ.get("CUPOLA_TESTLAB_TRACEARR_JELLYFIN_URL", "http://jellyfin:8096"),
        ),
        Watched(
            "emby",
            "Lab Emby",
            os.environ.get("CUPOLA_TESTLAB_TRACEARR_EMBY_URL", "http://emby:8096"),
        ),
    )


# ---------------------------------------------------------------- transport


def credentials() -> dict[str, str]:
    return jellyfin.credentials()


def key() -> str:
    """The public key the app holds, from the credentials file."""
    try:
        return jellyfin._required(credentials(), "CUPOLA_TESTLAB_TRACEARR_KEY")
    except jellyfin.PlayError as error:
        raise TracearrError(str(error)) from error


def api(path: str, *, bearer: str, what: str, method: str = "GET", payload: Any | None = None) -> Any:
    """A call that must succeed, answered with its body."""
    try:
        status, _, body = first_run.retrying(
            TRACEARR, path, what, method=method, payload=payload, bearer=bearer
        )
    except first_run.FirstRunError as error:
        raise TracearrError(str(error)) from error
    if not 200 <= status < 300:
        detail = body.get("message") if isinstance(body, dict) else ""
        raise TracearrError(f"{what} failed with {status}: {detail or 'no message'}")
    return body


def owner() -> str:
    """The owner's bearer, a session of this process."""
    try:
        return first_run.sign_in(TRACEARR)
    except first_run.FirstRunError as error:
        raise TracearrError(str(error)) from error


def public(path: str, *, what: str, query: dict[str, Any] | None = None) -> Any:
    """One read of the public API v2 with the key the app holds."""
    suffix = f"?{urllib.parse.urlencode(query)}" if query else ""
    return api(f"{V2}{path}{suffix}", bearer=key(), what=what)


# ---------------------------------------------------------------- the servers


def _jellyfin_key() -> str:
    """Jellyfin's `Tracearr` API key, made with the administrator's token."""
    token = jellyfin.admin_token()

    def named() -> str:
        answer = jellyfin.call("/Auth/Keys", "reading Jellyfin's API keys", token=token)
        for row in (answer.get("Items") if isinstance(answer, dict) else None) or []:
            if isinstance(row, dict) and row.get("AppName") == KEY_APP:
                return str(row.get("AccessToken") or "")
        return ""

    try:
        existing = named()
        if existing:
            return existing
        jellyfin.call(
            f"/Auth/Keys?app={KEY_APP}",
            "creating Jellyfin's Tracearr key",
            method="POST",
            token=token,
        )
        made = named()
    except jellyfin.PlayError as error:
        raise TracearrError(str(error)) from error
    if not made:
        raise TracearrError("Jellyfin did not list the key it just made")
    return made


def _emby_key() -> str:
    """Emby's `Tracearr` API key, made with the administrator's session."""
    try:
        session, _ = emby_admin.sign_in(emby.EMBY)
        return emby_admin.ensure_key(emby.EMBY, session, KEY_APP)
    except emby_admin.FirstRunError as error:
        raise TracearrError(str(error)) from error


def _key_of(kind: str) -> str:
    return _jellyfin_key() if kind == "jellyfin" else _emby_key()


def servers(bearer: str) -> list[dict[str, Any]]:
    body = api("/api/v1/servers", bearer=bearer, what="reading the servers")
    rows = body.get("data") if isinstance(body, dict) else None
    return [row for row in (rows or []) if isinstance(row, dict)]


def _connect(bearer: str, server: Watched) -> None:
    api(
        f"/api/v1/auth/{server.kind}/connect-api-key",
        bearer=bearer,
        what=f"connecting {server.name}",
        method="POST",
        payload={
            "serverUrl": server.inside,
            "serverName": server.name,
            "apiKey": _key_of(server.kind),
        },
    )


def _is_up(server: Watched, row: dict[str, Any], *, timeout: float) -> bool:
    """Whether Tracearr sees the held [row] of [server] up, given [timeout] seconds to say so.

    Tracearr checks a server on its own poll, so a server it has just been
    given, or that has just come back, is not up at once: the wait is bounded
    and ends the moment the answer is `up`.
    """

    def up() -> bool:
        return any(
            state.get("server_id") == row.get("id") and state.get("status") == "up"
            for state in server_states()
        )

    try:
        return bool(wait_for(f"{server.name} up", up, timeout=timeout, interval=2))
    except TracearrError:
        return False


def _mend(bearer: str, server: Watched, row: dict[str, Any]) -> None:
    """Give a held server that is not up the key its media server holds now.

    Tracearr's volumes live outside the lab snapshots: after a restore that
    predates the seed, the media server's `Tracearr` key is gone, a new one is
    made, and Tracearr still holds the old one. The owner's edit
    (`PATCH /api/v1/servers/<id>` with `apiKey`) is the first remedy; when
    Tracearr refuses it (the address now reaches a server it does not
    recognise, or the server has history it will not re-key), the server is
    deleted and connected again, which costs only what the lab had watched.
    """
    key_now = _key_of(server.kind)
    try:
        api(
            f"/api/v1/servers/{row['id']}",
            bearer=bearer,
            what=f"re-keying {server.name}",
            method="PATCH",
            payload={"apiKey": key_now},
        )
        print(f"[tracearr] re-keyed {server.name}")
    except TracearrError:
        api(
            f"/api/v1/servers/{row['id']}",
            bearer=bearer,
            what=f"removing {server.name}",
            method="DELETE",
        )
        _connect(bearer, server)
        print(f"[tracearr] reconnected {server.name}")


def ensure_servers(bearer: str, *, settle: float = 45) -> list[dict[str, Any]]:
    """Connect the lab's Jellyfin and Emby, and keep a held one that is up.

    A server Tracearr holds and sees up is left as it is, quietly. One it holds
    but does not see up, after a short wait, is mended with the key its media
    server holds now (see `_mend`), so the seed converges on a restored lab.
    """
    held = {(row.get("type"), row.get("url")): row for row in servers(bearer)}
    mended: list[Watched] = []
    for server in watched():
        row = held.get((server.kind, server.inside))
        if row is None:
            _connect(bearer, server)
            print(f"[tracearr] connected {server.name}")
        elif not _is_up(server, row, timeout=settle):
            _mend(bearer, server, row)
            mended.append(server)
    rows = servers(bearer)
    for server in mended:
        # Tracearr sees the new key at its next poll, not at once.
        row = next(r for r in rows if (r.get("type"), r.get("url")) == (server.kind, server.inside))
        if not _is_up(server, row, timeout=settle + 30):
            raise TracearrError(f"{server.name} is still not up after its key was renewed")
    return rows


# ---------------------------------------------------------------- the rule


def automations(bearer: str) -> list[dict[str, Any]]:
    body = api("/api/v1/automations", bearer=bearer, what="reading the automations")
    rows = body.get("data") if isinstance(body, dict) else None
    return [row for row in (rows or []) if isinstance(row, dict)]


def rule(bearer: str) -> dict[str, Any] | None:
    for row in automations(bearer):
        if row.get("name") == RULE_NAME and row.get("kind") == "policy":
            return row
    return None


def ensure_rule(bearer: str) -> dict[str, Any]:
    """`Too many streams at once`, from the template, once."""
    found = rule(bearer)
    if found is not None:
        return found
    body = api("/api/v1/templates", bearer=bearer, what="reading the templates")
    rows = body.get("data") if isinstance(body, dict) else body
    template = next(
        (
            row
            for row in (rows or [])
            if isinstance(row, dict) and row.get("slug") == RULE_TEMPLATE
        ),
        None,
    )
    if template is None:
        raise TracearrError(f"this Tracearr has no {RULE_TEMPLATE!r} template")
    made = api(
        f"/api/v1/templates/{template['id']}/instantiate",
        bearer=bearer,
        what="making the rule",
        method="POST",
        payload={"inputs": RULE_INPUTS, "name": RULE_NAME, "cooldownMinutes": 0, "isActive": True},
    )
    print(f"[tracearr] rule made: {RULE_NAME}")
    return made


# ---------------------------------------------------------------- what it sees


def streams() -> list[dict[str, Any]]:
    body = public("/streams", what="reading the live streams")
    rows = body.get("data") if isinstance(body, dict) else None
    return [row for row in (rows or []) if isinstance(row, dict)]


def history(page_size: int = 50) -> list[dict[str, Any]]:
    body = public("/history", what="reading the history", query={"pageSize": page_size})
    rows = body.get("data") if isinstance(body, dict) else None
    return [row for row in (rows or []) if isinstance(row, dict)]


def violations(page_size: int = 50) -> list[dict[str, Any]]:
    body = public("/violations", what="reading the violations", query={"pageSize": page_size})
    rows = body.get("data") if isinstance(body, dict) else None
    return [row for row in (rows or []) if isinstance(row, dict)]


def server_states() -> list[dict[str, Any]]:
    body = public("/servers", what="reading the servers' states")
    rows = body.get("data") if isinstance(body, dict) else None
    return [row for row in (rows or []) if isinstance(row, dict)]


def wait_for(what: str, probe: Any, *, timeout: float = 90, interval: float = 2) -> Any:
    """The first truthy answer of [probe], or a failure that names [what]."""
    deadline = time.monotonic() + timeout
    last: Any = None
    while time.monotonic() < deadline:
        last = probe()
        if last:
            return last
        time.sleep(interval)
    raise TracearrError(f"{what} did not happen within {timeout:g}s")


# ---------------------------------------------------------------- audit


def audit() -> dict[str, Any]:
    """What the monitor holds, read with the owner and with the app's key."""
    bearer = owner()
    return {
        "servers": servers(bearer),
        "states": server_states(),
        "rule": rule(bearer),
    }


def assert_ready(state: dict[str, Any]) -> None:
    """The monitor watches both lab servers and holds the rule, or says what."""
    wanted = {(server.kind, server.inside) for server in watched()}
    held = {(row.get("type"), row.get("url")) for row in state["servers"]}
    missing = sorted(f"{kind} at {url}" for kind, url in wanted - held)
    if missing:
        raise TracearrError("Tracearr does not hold: " + ", ".join(missing))
    down = sorted(
        f"{row.get('server_name')} ({row.get('status')})"
        for row in state["states"]
        if row.get("status") != "up"
    )
    if down:
        raise TracearrError("Tracearr does not see these servers up: " + ", ".join(down))
    found = state["rule"]
    if found is None:
        raise TracearrError(f"Tracearr has no rule named {RULE_NAME!r}")
    if found.get("isActive") is not True:
        raise TracearrError(f"the rule {RULE_NAME!r} is paused")


def summary(state: dict[str, Any]) -> str:
    lines = ["Tracearr:"]
    for row in state["states"]:
        lines.append(
            f"  {row.get('server_name')} ({row.get('server_type')}): {row.get('status')}"
        )
    found = state["rule"]
    if found is not None:
        lines.append(f"  rule: {found.get('name')} ({found.get('severity')})")
    return "\n".join(lines)


def setup() -> dict[str, Any]:
    """Connect the servers, make the rule, and wait until both servers are up."""
    bearer = owner()
    ensure_servers(bearer)
    ensure_rule(bearer)

    def both_up() -> bool:
        states = server_states()
        return len(states) >= len(watched()) and all(
            row.get("status") == "up" for row in states
        )

    wait_for("both servers to read as up", both_up, timeout=120)
    state = audit()
    assert_ready(state)
    return state


# ---------------------------------------------------------------- the playbacks

#: The two devices of the scenario, and what each plays.
DEVICES = (("cupola-tracearr-a", "Big Buck Bunny"), ("cupola-tracearr-b", "The Matrix"))

#: How long a player holds its session open, in seconds. A playback that is
#: not kept alive is dropped by Emby within a minute, which Tracearr then
#: reads as a stream that ended: the scenario must outlive the tests that
#: read it, and its teardown ends the players long before this.
HOLD_SECONDS = 900


def _player(device: str, title: str) -> None:
    """A detached `emby_play.py --listen`, which keeps the session alive.

    A process of its own, because a scenario is a command that returns and a
    playback that nobody keeps alive does not last. It reports Progress every
    fifteen seconds and obeys the server's Stop, so ending the session on the
    server (the teardown, or Tracearr's own terminate) ends the process.
    """
    environment = dict(os.environ)
    environment["CUPOLA_TESTLAB_STATE_DIR"] = str(emby.STATE_ROOT)
    environment["CUPOLA_TESTLAB_CREDENTIALS_FILE"] = str(emby.STATE_ROOT / "credentials.env")
    subprocess.Popen(
        [
            sys.executable,
            str(Path(__file__).resolve().parent / "emby_play.py"),
            "--device", device,
            "--title", title,
            "--user", "viewer",
            "--percent", "10",
            "--listen",
            "--hold", str(HOLD_SECONDS),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=environment,
        start_new_session=True,
    )


def _emby_plays(device: str) -> bool:
    """Whether Emby holds a session on [device] with something playing."""
    try:
        session = emby.session_for_device(emby.device_id_of(device))
    except emby.PlayError:
        return False
    return session is not None and bool(session.get("NowPlayingItem"))


def _players_alive(device: str) -> bool:
    """Whether a `emby_play.py --listen` of [device] is still a process.

    A player that was told to stop leaves within its next keepalive (fifteen
    seconds); starting another on the same device before it has gone leaves
    two reporting one session, and the one that exits last erases the state
    the other needs to stop it.
    """
    found = subprocess.run(
        ["pgrep", "-f", f"emby_play.py --device {device} "],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return found.returncode == 0


def play_two_streams() -> list[dict[str, Any]]:
    """Two playbacks on Emby by the household member, one after the other.

    Tracearr rules a stream when it starts, against the streams already live,
    so the second is opened only once Tracearr lists the first: two playbacks
    seen in one poll would be counted in whatever order the poll found them.
    Answers the streams Tracearr lists for the two devices.
    """
    for device, title in DEVICES:
        if not _emby_plays(device):
            # A device already playing (the scenario applied, then this
            # again) keeps the player it has: a second one would only report
            # the same session twice. One that is leaving is waited for.
            wait_for(
                f"the last player on {device} to leave",
                lambda device=device: not _players_alive(device),
                timeout=40,
                interval=1,
            )
            _player(device, title)
        wait_for(
            f"Emby to list {title} on {device}",
            lambda device=device: _emby_plays(device),
            timeout=60,
            interval=1,
        )
        wait_for(
            f"Tracearr to list {title} on {device}",
            lambda device=device: [row for row in streams() if row.get("player") == device],
        )
    return [row for row in streams() if row.get("player") in {d for d, _ in DEVICES}]


def violation_ids() -> set[Any]:
    return {row.get("id") for row in violations(100)}


def wait_for_violation(play: Any) -> list[dict[str, Any]]:
    """Run [play], then wait for a violation of two streams it caused.

    Two streams that were already live are not started again, and no violation
    follows: then the record of one is what is waited for.
    """
    live = {row.get("player") for row in streams()}
    if {device for device, _ in DEVICES} <= live:
        play()
        return wait_for(
            "a violation of two streams",
            lambda: [row for row in violations(100) if concurrent_streams(row) >= 2],
            timeout=30,
        )
    before = violation_ids()
    play()
    return wait_for(
        "a new violation of the rule",
        lambda: [
            row
            for row in violations(100)
            if row.get("id") not in before and concurrent_streams(row) >= 2
        ],
        timeout=90,
    )


def concurrent_streams(violation: dict[str, Any]) -> int:
    """The number of streams a violation counted, as the rule wrote it."""
    data = violation.get("data")
    evidence = data.get("evidence") if isinstance(data, dict) else None
    for group in evidence or []:
        for condition in (group or {}).get("conditions") or []:
            if condition.get("field") == "concurrent_streams":
                return int(condition.get("actual") or 0)
    return 0


def stop_playbacks() -> list[dict[str, Any]]:
    """Stop every playback the helper opened, and wait for the players to go.

    The helper's own Stop ends a session it holds the state of. A session whose
    state is lost is ended the way Tracearr's and the app's Stop end one: the
    server relays Stop to the player, which obeys it.
    """
    try:
        ended = emby.stop_all(user="viewer")
        for session in emby.playing_sessions():
            device_id = str(session.get("DeviceId") or "")
            if session.get("NowPlayingItem") and device_id.startswith(emby.DEVICE_PREFIX):
                emby.request(
                    f"/Sessions/{session['Id']}/Playing/Stop",
                    method="POST",
                    token=emby.api_key(),
                )
        wait_for(
            "the playbacks to leave Emby",
            lambda: not any(_emby_plays(device) for device, _ in DEVICES),
            timeout=40,
            interval=1,
        )
        wait_for(
            "the players to exit",
            lambda: not any(_players_alive(device) for device, _ in DEVICES),
            timeout=40,
            interval=1,
        )
    except emby.PlayError as error:
        raise TracearrError(str(error)) from error
    return ended


# ---------------------------------------------------------------- command


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Connect the lab's media servers to Tracearr and make its rule."
    )
    parser.add_argument("--verify", action="store_true", help="read only, and assert")
    parser.add_argument("--play", action="store_true",
                        help="play two streams on Emby and wait for the violation")
    parser.add_argument("--stop", action="store_true",
                        help="stop the playbacks this module opened")
    arguments = parser.parse_args(argv)
    try:
        if arguments.stop:
            ended = stop_playbacks()
            print(f"[tracearr] stopped {sum(1 for row in ended if row.get('stopped'))} playback(s)")
            wait_for(
                "Tracearr to stop listing the streams",
                lambda: not [row for row in streams() if row.get("player") in {d for d, _ in DEVICES}],
            )
            return 0
        if arguments.play:
            state = setup()
            wait_for_violation(lambda: play_two_streams())
            print(summary(state))
            return 0
        if arguments.verify:
            state = audit()
            assert_ready(state)
        else:
            state = setup()
    except (TracearrError, jellyfin.PlayError) as error:
        print(f"tracearr_lab: {error}", file=sys.stderr)
        return 2
    print(summary(state))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
