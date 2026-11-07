#!/usr/bin/env python3
"""A playback client for the lab's Jellyfin, driven from the command line.

This is not a video player. It is the reporting half of one, which is all
Jellyfin needs to open a session, put a title in Now playing, hold a position,
pause, resume and stop::

    python3 test/e2e/testlab/jellyfin_play.py --device phone \\
        --title 'Big Buck Bunny' --user viewer
    python3 test/e2e/testlab/jellyfin_play.py --device phone --pause
    python3 test/e2e/testlab/jellyfin_play.py --device phone --stop
    python3 test/e2e/testlab/jellyfin_play.py --list

Three protocol facts shape the file.

**The session belongs to the device, not to the request.** Jellyfin keys a
session on the `DeviceId` the client presents in its `Authorization` header, so
two `--device` values are two rows in `GET /Sessions` and one device cannot hold
two titles at once. Playback is reported with `POST /Sessions/Playing`, kept
alive and paused with `POST /Sessions/Playing/Progress`, and ended with
`POST /Sessions/Playing/Stopped`. Nothing here calls `/Sessions/Logout`: that
would sign the device out of the server and would be the test harness deleting
the thing it came to measure.

**A pause is the client's own report, not the server's command.** Jellyfin's
`POST /Sessions/{id}/Playing/Pause` is remote control: the server relays a
`Playstate` frame over the WebSocket the client holds open, and the client is
what turns that into a paused `Progress` report. `--listen` holds that
WebSocket and obeys, which is what makes a pause issued from Cupola's session
card change the state a later `/Sessions` read sees. Without `--listen` the
command is answered 204 and changes nothing, which is the same trap the app
documents in `pauseSession`.

**Position is ticks.** Jellyfin counts 10 000 ticks per millisecond and advances
a playing session from the last report, so `--position 30` is 30 seconds and a
`--listen` loop carries that position forward while it plays.

The token comes from the chmod-600 credentials file the bootstrap writes. The
administrator's token is used by default; `--user viewer` signs in as the
Jellyfin requester with the generated password, and that is the account to use
for anything a household member should see. Neither is ever printed, and the
password is never written anywhere. The one secret that is written is the
viewer's `AccessToken`, cached in the device's own 0600 state file: signing in
again on the same `DeviceId` makes Jellyfin drop the playback that token is
holding, so a client keeps it for the life of the session.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Iterable

JELLYFIN = os.environ.get("CUPOLA_TESTLAB_JELLYFIN_URL", "http://127.0.0.1:8096")

REPO_ROOT = Path(__file__).resolve().parents[3]
STATE_ROOT = Path(
    os.environ.get("CUPOLA_TESTLAB_STATE_DIR", REPO_ROOT / ".ai" / "scratch" / "zz_testlab" / "state")
).resolve()
CREDENTIALS = STATE_ROOT / "credentials.env"
PLAY_STATE = STATE_ROOT / "jellyfin-play"

CLIENT = "Cupola TestLab"
DEVICE_DEFAULT = "Cupola TestLab Play"
VERSION = "1.0"

# Jellyfin's tick: 100 nanoseconds.
TICKS_PER_SECOND = 10_000_000

DIRECT_PLAY = "DirectPlay"


class PlayError(RuntimeError):
    """A request the server refused, or an answer that made no sense."""


# ---------------------------------------------------------------- credentials


def credentials() -> dict[str, str]:
    values: dict[str, str] = {}
    if not CREDENTIALS.exists():
        return values
    for line in CREDENTIALS.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def _required(values: dict[str, str], name: str) -> str:
    value = values.get(name, "")
    if not value:
        raise PlayError(
            f"the lab credentials have no {name}: run test/e2e/testlab/bootstrap.sh"
        )
    return value


# ---------------------------------------------------------------- transport


def authorization(token: str, device_id: str, device_name: str = DEVICE_DEFAULT) -> str:
    """The `MediaBrowser` header every Jellyfin request and socket carries."""
    return (
        f'MediaBrowser Client="{CLIENT}", Device="{device_name}", '
        f'DeviceId="{device_id}", Version="{VERSION}", Token="{token}"'
    )


def request(
    path: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    token: str = "",
    device_id: str = "cupola-testlab-cli",
    device_name: str = DEVICE_DEFAULT,
    timeout: float = 30,
) -> tuple[int, Any]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = authorization(token, device_id, device_name)
    call = urllib.request.Request(
        f"{JELLYFIN}{path}", data=data, method=method, headers=headers
    )
    try:
        with urllib.request.urlopen(call, timeout=timeout) as response:
            body = response.read()
            status = response.status
    except urllib.error.HTTPError as error:
        body = error.read()
        status = error.code
    except (urllib.error.URLError, TimeoutError) as error:
        raise PlayError(f"{method} {path} did not answer: {error}") from error
    if not body:
        return status, None
    try:
        return status, json.loads(body.decode("utf-8"))
    except json.JSONDecodeError:
        return status, body.decode("utf-8", errors="replace")


def call(path: str, what: str, **kwargs: Any) -> Any:
    status, body = request(path, **kwargs)
    if not 200 <= status < 300:
        raise PlayError(f"{what} failed with {status}: {_answer(body)}")
    return body


def _answer(body: Any) -> str:
    if isinstance(body, str):
        return body[:300]
    if body is None:
        return "no body"
    return json.dumps(body)[:300]


# ---------------------------------------------------------------- accounts


def admin_token(values: dict[str, str] | None = None) -> str:
    return _required(values or credentials(), "CUPOLA_TESTLAB_JELLYFIN_TOKEN")


def viewer_token(
    device_id: str, device_name: str = DEVICE_DEFAULT
) -> tuple[str, str, str]:
    """Sign in as the lab's requester: `(token, user id, name)`.

    A generated password, read from the same file as the administrator's token
    and never echoed. Signing in does not open a playback session, so this is
    safe to call before every command.
    """
    values = credentials()
    username = _required(values, "CUPOLA_TESTLAB_JELLYFIN_REQUESTER_USERNAME")
    password = _required(values, "CUPOLA_TESTLAB_JELLYFIN_REQUESTER_PASSWORD")
    headers = {
        "Authorization": authorization("", device_id, device_name),
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    # Jellyfin answers 401 for a wrong password. That message is written here
    # from the username alone, never from the password.
    call_body = json.dumps({"Username": username, "Pw": password}).encode("utf-8")
    request_ = urllib.request.Request(
        f"{JELLYFIN}/Users/AuthenticateByName",
        data=call_body,
        method="POST",
        headers=headers,
    )
    try:
        with urllib.request.urlopen(request_, timeout=30) as response:
            answer = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise PlayError(
            f"signing in as {username} was refused with {error.code}"
        ) from None
    except (urllib.error.URLError, TimeoutError) as error:
        raise PlayError(f"signing in as {username} did not answer: {error}") from error
    token = answer.get("AccessToken") or ""
    user = answer.get("User") or {}
    user_id = user.get("Id") or ""
    if not token or not user_id:
        raise PlayError(f"signing in as {username} answered no token and no user")
    return token, user_id, user.get("Name") or username


def account(
    user: str, device_id: str, device_name: str = DEVICE_DEFAULT
) -> dict[str, str]:
    """The credential a command runs as: `admin` (default) or `viewer`.

    A viewer's `AccessToken` is cached in the device's own state file (0600) and
    reused, because signing in again on the same `DeviceId` makes Jellyfin open a
    new client session for that device: the playback the earlier token reported
    is dropped, and `--pause` would find nothing to pause. That is a property of
    the server, not of this helper; a real client authenticates once and keeps
    its token for the life of the session.
    """
    if user in ("", "admin"):
        values = credentials()
        token = _required(values, "CUPOLA_TESTLAB_JELLYFIN_TOKEN")
        user_id = values.get("CUPOLA_TESTLAB_JELLYFIN_USER_ID", "")
        if not user_id:
            user_id = _user_id_of(token, "cupola-admin")
        return {"token": token, "userId": user_id, "name": "cupola-admin"}
    if user == "viewer":
        stored = _read_state(_device_of_id(device_id))
        token = str(stored.get("token") or "")
        if token and str(stored.get("user") or "") == "viewer":
            status, _ = request("/Users/Me", token=token, device_id=device_id)
            if 200 <= status < 300:
                return {
                    "token": token,
                    "userId": str(stored.get("userId") or ""),
                    "name": str(stored.get("userName") or "cupola-viewer"),
                }
        token, user_id, name = viewer_token(device_id, device_name)
        _write_state(
            _device_of_id(device_id),
            {
                **stored,
                "deviceId": device_id,
                "user": "viewer",
                "userId": user_id,
                "userName": name,
                "token": token,
                "updatedAt": _now(),
            },
        )
        return {"token": token, "userId": user_id, "name": name}
    raise PlayError(f"unknown user {user!r}: use admin or viewer")


def _user_id_of(token: str, name: str) -> str:
    users = call("/Users", "reading the household", token=token)
    for user in users if isinstance(users, list) else []:
        if user.get("Name") == name:
            return user.get("Id") or ""
    raise PlayError(f"the server has no user named {name}")


# ---------------------------------------------------------------- the item


def find_item(
    token: str,
    user_id: str,
    title: str = "",
    item_id: str = "",
    kinds: str = "Movie,Episode,Audio",
) -> dict[str, Any]:
    """The one item a title names, or the item an id names."""
    if item_id:
        item = call(
            f"/Items/{item_id}?userId={urllib.parse.quote(user_id)}",
            "reading the item",
            token=token,
        )
        if not isinstance(item, dict):
            raise PlayError(f"the server answered no item for {item_id}")
        return item
    if not title.strip():
        raise PlayError("say what to play: --title 'Big Buck Bunny' or --item-id <id>")
    query = urllib.parse.urlencode(
        {
            "recursive": "true",
            "searchTerm": title,
            "includeItemTypes": kinds,
            "userId": user_id,
            "limit": 40,
            "fields": "RunTimeTicks,SeriesName,MediaSources",
        }
    )
    answer = call(f"/Items?{query}", "searching the library", token=token)
    items = answer.get("Items") if isinstance(answer, dict) else None
    if not items:
        raise PlayError(f"nothing in the library matches {title!r}")
    wanted = title.strip().casefold()
    exact = [item for item in items if (item.get("Name") or "").casefold() == wanted]
    near = [
        item
        for item in items
        if wanted in (item.get("Name") or "").casefold()
        or wanted in (item.get("SeriesName") or "").casefold()
    ]
    chosen = exact or near
    if not chosen:
        raise PlayError(
            f"nothing in the library matches {title!r}; the server offered "
            + ", ".join(repr(item.get("Name")) for item in items[:5])
        )
    return chosen[0]


def runtime_ticks(item: dict[str, Any]) -> int:
    value = item.get("RunTimeTicks")
    return int(value) if isinstance(value, (int, float)) and value > 0 else 0


def position_ticks(item: dict[str, Any], seconds: float | None, percent: float | None) -> int:
    """Where to report playback: an explicit position, or a share of the item."""
    runtime = runtime_ticks(item)
    if percent is not None:
        if runtime <= 0:
            raise PlayError("this item reports no runtime, so a percentage means nothing")
        return int(runtime * (percent / 100.0))
    if seconds is None:
        return 0
    return max(0, int(seconds * TICKS_PER_SECOND))


def media_source_id(item: dict[str, Any]) -> str:
    sources = item.get("MediaSources")
    if isinstance(sources, list) and sources:
        first = sources[0]
        if isinstance(first, dict) and first.get("Id"):
            return str(first["Id"])
    return str(item.get("Id") or "")


# ---------------------------------------------------------------- the session


def playing_sessions(token: str, *, active_within: int = 0) -> list[dict[str, Any]]:
    """Every session the server knows about; those playing carry a title.

    `activeWithinSeconds=0` asks for all of them, which is what `--list` wants:
    an idle device is a fact about the lab too. The app asks for 180, and its
    mapper drops the rows with no `NowPlayingItem`, so a stopped device is not
    a stream in Cupola either way.
    """
    query = "" if not active_within else f"?activeWithinSeconds={active_within}"
    answer = call(f"/Sessions{query}", "reading the sessions", token=token)
    return answer if isinstance(answer, list) else []


def session_for_device(token: str, device_id: str) -> dict[str, Any] | None:
    for session in playing_sessions(token):
        if session.get("DeviceId") == device_id:
            return session
    return None


def _play_state(session: dict[str, Any]) -> dict[str, Any]:
    state = session.get("PlayState")
    return state if isinstance(state, dict) else {}


def describe(session: dict[str, Any]) -> dict[str, Any]:
    playing = session.get("NowPlayingItem")
    item = playing if isinstance(playing, dict) else {}
    state = _play_state(session)
    runtime = int(item.get("RunTimeTicks") or 0)
    position = int(state.get("PositionTicks") or 0)
    return {
        "id": session.get("Id") or "",
        "device": session.get("DeviceName") or "",
        "deviceId": session.get("DeviceId") or "",
        "user": session.get("UserName") or "",
        "client": session.get("Client") or "",
        "title": item.get("Name") or "",
        "series": item.get("SeriesName") or "",
        "itemId": item.get("Id") or "",
        "paused": state.get("IsPaused") is True,
        "positionSeconds": round(position / TICKS_PER_SECOND, 1),
        "runtimeSeconds": round(runtime / TICKS_PER_SECOND, 1) if runtime else None,
        "progress": round(position / runtime, 3) if runtime else None,
        "playing": bool(item),
    }


def _report(
    path: str,
    *,
    token: str,
    device_id: str,
    device_name: str,
    item_id: str,
    source_id: str,
    play_session_id: str,
    position: int,
    paused: bool,
) -> None:
    payload: dict[str, Any] = {
        "ItemId": item_id,
        "MediaSourceId": source_id,
        "PlaySessionId": play_session_id,
        "PositionTicks": int(position),
    }
    if path.endswith("/Stopped"):
        # `PlaybackStopInfo` is narrower than `PlaybackProgressInfo`: the played
        # flag is the server's decision from the position, and only `Failed`
        # says the stop was not a normal end.
        payload["Failed"] = False
    else:
        payload.update(
            {
                "IsPaused": bool(paused),
                "IsMuted": False,
                "PlayMethod": DIRECT_PLAY,
                "CanSeek": True,
                "VolumeLevel": 80,
                "RepeatMode": "RepeatNone",
            }
        )
        if path.endswith("/Playing"):
            payload["PlaybackStartTimeTicks"] = (
                int(time.time() * TICKS_PER_SECOND) - position
            )
    call(path, "reporting playback", method="POST", payload=payload, token=token,
         device_id=device_id, device_name=device_name)


def announce(token: str, *, device_id: str, device_name: str) -> None:
    """Tell the server what this client can be asked to do, as real clients do.

    Cupola draws Pause, Stop and Message only for a player that announced media
    control and `DisplayMessage`: Jellyfin relays the commands to anyone, but a
    client that announced nothing is, in the wild, one that is not listening.
    """
    call(
        "/Sessions/Capabilities/Full",
        "announcing the client",
        method="POST",
        payload={
            "PlayableMediaTypes": ["Video", "Audio"],
            "SupportedCommands": ["DisplayMessage"],
            "SupportsMediaControl": True,
        },
        token=token,
        device_id=device_id,
        device_name=device_name,
    )


def start(
    *,
    device: str,
    title: str = "",
    item_id: str = "",
    user: str = "admin",
    seconds: float | None = None,
    percent: float | None = None,
    paused: bool = False,
) -> dict[str, Any]:
    """Open a session on `device` and return it as the server reports it."""
    device_id = device_id_of(device)
    who = account(user, device_id, device)
    item = find_item(who["token"], who["userId"], title=title, item_id=item_id)
    position = position_ticks(item, seconds, percent)
    play_session = uuid.uuid4().hex
    announce(who["token"], device_id=device_id, device_name=device)
    _report(
        "/Sessions/Playing",
        token=who["token"],
        device_id=device_id,
        device_name=device,
        item_id=str(item["Id"]),
        source_id=media_source_id(item),
        play_session_id=play_session,
        position=position,
        paused=paused,
    )
    session = session_for_device(who["token"], device_id)
    if session is None:
        raise PlayError(
            f"the server accepted playback for {device!r} but lists no such session"
        )
    reported = describe(session)
    _write_state(
        device,
        {
            **_read_state(device),
            "deviceId": device_id,
            "user": user,
            "itemId": str(item["Id"]),
            "title": reported["title"],
            "sessionId": reported["id"],
            "playSessionId": play_session,
            "positionTicks": position,
            "paused": paused,
            "updatedAt": _now(),
        },
    )
    return reported


def set_paused(device: str, *, paused: bool, user: str = "admin",
               seconds: float | None = None, percent: float | None = None) -> dict[str, Any]:
    """Report a pause or a resume for the session `device` already holds."""
    device_id = device_id_of(device)
    who = account(user, device_id, device)
    session = session_for_device(who["token"], device_id)
    if session is None or not session.get("NowPlayingItem"):
        raise PlayError(f"{device!r} holds no playing session to pause or resume")
    state = _play_state(session)
    playing = session.get("NowPlayingItem") or {}
    item = find_item(who["token"], who["userId"], item_id=str(playing.get("Id") or ""))
    position = int(state.get("PositionTicks") or 0)
    if seconds is not None or percent is not None:
        position = position_ticks(item, seconds, percent)
    stored = _read_state(device)
    _report(
        "/Sessions/Playing/Progress",
        token=who["token"],
        device_id=device_id,
        device_name=device,
        item_id=str(item["Id"]),
        source_id=media_source_id(item),
        play_session_id=stored.get("playSessionId") or uuid.uuid4().hex,
        position=position,
        paused=paused,
    )
    after = session_for_device(who["token"], device_id)
    if after is None:
        raise PlayError(f"{device!r} vanished from the session list while pausing")
    reported = describe(after)
    _write_state(
        device,
        {
            **(stored or {}),
            "deviceId": device_id,
            "user": user,
            "itemId": str(item["Id"]),
            "title": reported["title"],
            "sessionId": reported["id"],
            "positionTicks": position,
            "paused": paused,
            "updatedAt": _now(),
        },
    )
    return reported


def stop(device: str, *, user: str = "admin", seconds: float | None = None,
         percent: float | None = None) -> dict[str, Any]:
    """End the session `device` holds: `POST /Sessions/Playing/Stopped`."""
    device_id = device_id_of(device)
    who = account(user, device_id, device)
    session = session_for_device(who["token"], device_id)
    if session is None or not session.get("NowPlayingItem"):
        _remove_state(device)
        return {"stopped": False, "device": device, "reason": "no playing session"}
    playing = session.get("NowPlayingItem") or {}
    state = _play_state(session)
    item = find_item(who["token"], who["userId"], item_id=str(playing.get("Id") or ""))
    position = int(state.get("PositionTicks") or 0)
    if seconds is not None or percent is not None:
        position = position_ticks(item, seconds, percent)
    stored = _read_state(device)
    _report(
        "/Sessions/Playing/Stopped",
        token=who["token"],
        device_id=device_id,
        device_name=device,
        item_id=str(item["Id"]),
        source_id=media_source_id(item),
        play_session_id=stored.get("playSessionId") or uuid.uuid4().hex,
        position=position,
        paused=True,
    )
    _remove_state(device)
    after = session_for_device(who["token"], device_id)
    return {
        "stopped": after is None or not (after.get("NowPlayingItem") or {}),
        "device": device,
        "title": playing.get("Name") or "",
        "positionSeconds": round(position / TICKS_PER_SECOND, 1),
    }


def session_id_for(device: str, *, user: str = "admin") -> str:
    """The server's id of the session on `device`, for Cupola's own commands.

    `StreamSession.id` is this field and never the `DeviceId`: Jellyfin answers
    404 to `POST /Sessions/{id}/Playing/Stop` for anything else.
    """
    device_id = device_id_of(device)
    who = account(user, device_id, device)
    session = session_for_device(who["token"], device_id)
    return str((session or {}).get("Id") or "")


def stop_all(*, user: str = "admin") -> list[dict[str, Any]]:
    """Stop every session whose device this helper made.

    A device is the helper's when its `DeviceId` starts with `cupola-play-`.
    Anything else in the list (the app, a browser) is left alone.
    """
    device_id = device_id_of("cli")
    who = account(user, device_id, "Cupola TestLab CLI")
    stopped: list[dict[str, Any]] = []
    for session in playing_sessions(who["token"]):
        if not session.get("NowPlayingItem"):
            continue
        device_id = str(session.get("DeviceId") or "")
        if not device_id.startswith(DEVICE_PREFIX):
            continue
        try:
            stopped.append(stop(_device_of_id(device_id), user=user))
        except PlayError as error:
            stopped.append(
                {"device": _device_of_id(device_id), "stopped": False, "reason": str(error)}
            )
    return stopped


# ---------------------------------------------------------------- listen


def listen(
    device: str,
    *,
    user: str = "admin",
    hold_seconds: float = 300,
    seconds: float | None = None,
    percent: float | None = None,
    keepalive_seconds: float = 15,
    verbose: bool = True,
) -> dict[str, Any]:
    """Hold the device's WebSocket open and obey what the server relays.

    The messages that matter are `Playstate` (Pause, Unpause, PlayPause, Stop)
    and `GeneralCommand`/`DisplayMessage`; `ForceKeepAlive` is the server asking
    to hear from us. Every state change is reported back with `Progress`, so a
    pause issued from Cupola's session card is visible to the next `/Sessions`
    read instead of only having been dispatched.
    """
    try:
        from websockets.sync.client import connect
    except ImportError as error:  # pragma: no cover - the lab's Mac has it
        raise PlayError(
            "the Python package 'websockets' is missing: pip3 install websockets"
        ) from error

    device_id = device_id_of(device)
    who = account(user, device_id, device)
    session = session_for_device(who["token"], device_id)
    if session is None or not session.get("NowPlayingItem"):
        raise PlayError(f"{device!r} holds no playing session to listen for")
    item = find_item(who["token"], who["userId"],
                     item_id=str((session.get("NowPlayingItem") or {}).get("Id") or ""))
    stored = _read_state(device)
    play_session = stored.get("playSessionId") or uuid.uuid4().hex
    position = int(_play_state(session).get("PositionTicks") or 0)
    if seconds is not None or percent is not None:
        position = position_ticks(item, seconds, percent)
    paused = _play_state(session).get("IsPaused") is True

    headers = {"Authorization": authorization(who["token"], device_id, device)}
    uri = f"{JELLYFIN.replace('http://', 'ws://').replace('https://', 'wss://')}/socket?deviceId={device_id}"
    last_keepalive = 0.0
    last_activity = time.monotonic()
    deadline = time.monotonic() + hold_seconds
    stop_asked = False
    ended_elsewhere = False
    messages: list[str] = []

    def report(now_paused: bool) -> None:
        _report(
            "/Sessions/Playing/Progress",
            token=who["token"],
            device_id=device_id,
            device_name=device,
            item_id=str(item["Id"]),
            source_id=media_source_id(item),
            play_session_id=play_session,
            position=position,
            paused=now_paused,
        )

    with connect(uri, open_timeout=10, additional_headers=headers) as socket:
        if verbose:
            print(f"listening on {device!r} as {who['name']}", flush=True)
        while time.monotonic() < deadline:
            try:
                raw = socket.recv(timeout=0.5)
            except TimeoutError:
                raw = None
            except Exception as error:  # a closed socket ends the loop
                messages.append(f"socket closed: {type(error).__name__}")
                break
            if raw:
                try:
                    message = json.loads(raw)
                except json.JSONDecodeError:
                    message = {}
                kind = message.get("MessageType") or ""
                data = message.get("Data") or {}
                if kind == "ForceKeepAlive":
                    socket.send(json.dumps({"MessageType": "KeepAlive"}))
                elif kind == "Playstate":
                    command = str(data.get("Command") or "")
                    messages.append(f"playstate {command}")
                    if verbose:
                        print(f"playstate {command}", flush=True)
                    if command == "Pause":
                        paused = True
                        report(True)
                    elif command == "Unpause":
                        paused = False
                        report(False)
                    elif command == "PlayPause":
                        paused = not paused
                        report(paused)
                    elif command == "Stop":
                        stop_asked = True
                        break
                    elif command == "Seek" and data.get("SeekPositionTicks") is not None:
                        position = int(data["SeekPositionTicks"])
                        report(paused)
                elif kind == "GeneralCommand":
                    name = str(data.get("Name") or "")
                    if name == "DisplayMessage":
                        text = (data.get("Arguments") or {}).get("Text") or ""
                        messages.append(f"message {text!r}")
                        if verbose:
                            print(f"message: {text}", flush=True)
                elif kind == "Play":
                    messages.append("play requested")
                elif kind == "UserDataChanged":
                    pass
            now = time.monotonic()
            if not paused and now - last_activity >= 1:
                position += int((now - last_activity) * TICKS_PER_SECOND)
                last_activity = now
            if now - last_keepalive >= keepalive_seconds:
                last_keepalive = now
                # Somebody else may have stopped this session (the CLI, or a
                # second process on the same device). A keepalive would open it
                # again, so the server is asked first.
                current = session_for_device(who["token"], device_id)
                if current is None or not current.get("NowPlayingItem"):
                    messages.append("session ended elsewhere")
                    ended_elsewhere = True
                    break
                try:
                    report(paused)
                except PlayError as error:
                    messages.append(f"keepalive failed: {error}")

    if stop_asked:
        ended = stop(device, user=user)
        return {"device": device, "stopped": True, "ended": ended, "messages": messages}
    # The hold ran out: the socket closes, and Jellyfin drops the playing state
    # of a client it no longer hears from. Report what the server says rather
    # than what we asked for.
    after = session_for_device(who["token"], device_id)
    still_playing = after is not None and bool(after.get("NowPlayingItem"))
    if still_playing:
        _write_state(
            device,
            {
                **(stored or {}),
                "deviceId": device_id,
                "user": user,
                "itemId": str(item["Id"]),
                "title": (session.get("NowPlayingItem") or {}).get("Name") or "",
                "sessionId": str(session.get("Id") or ""),
                "playSessionId": play_session,
                "positionTicks": position,
                "paused": paused,
                "playing": True,
                "updatedAt": _now(),
            },
        )
    else:
        # Nothing is playing, so there is nothing to resume and no token worth
        # keeping at rest.
        _remove_state(device)
    return {
        "device": device,
        "stopped": False,
        "endedElsewhere": ended_elsewhere,
        "paused": paused,
        "playing": still_playing,
        "messages": messages,
    }


# ---------------------------------------------------------------- state file


DEVICE_PREFIX = "cupola-play-"


def device_id_of(device: str) -> str:
    """The `DeviceId` a `--device` value means.

    Stable, so `--pause` finds the session `--device phone` opened in another
    process, and namespaced, so the helper can recognise its own sessions and
    nothing else's.
    """
    slug = re.sub(r"[^a-z0-9]+", "-", device.strip().casefold()).strip("-")
    if not slug:
        raise PlayError("--device needs a name, for example 'phone'")
    if slug.startswith(DEVICE_PREFIX):
        return slug
    return f"{DEVICE_PREFIX}{slug}"


def _device_of_id(device_id: str) -> str:
    return device_id[len(DEVICE_PREFIX):] if device_id.startswith(DEVICE_PREFIX) else device_id


def _state_path(device: str) -> Path:
    return PLAY_STATE / f"{_device_of_id(device_id_of(device))}.json"


def _write_state(device: str, state: dict[str, Any]) -> None:
    PLAY_STATE.mkdir(parents=True, exist_ok=True)
    os.chmod(PLAY_STATE, 0o700)
    path = _state_path(device)
    path.write_text(json.dumps(state, indent=2), encoding="utf-8")
    os.chmod(path, 0o600)


def _read_state(device: str) -> dict[str, Any]:
    path = _state_path(device)
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _remove_state(device: str) -> None:
    path = _state_path(device)
    if path.exists():
        path.unlink()


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


# ---------------------------------------------------------------- printing


def _print_sessions(sessions: Iterable[dict[str, Any]]) -> None:
    playing = [describe(session) for session in sessions if session.get("NowPlayingItem")]
    idle = [describe(session) for session in sessions if not session.get("NowPlayingItem")]
    if not playing:
        print("no sessions are playing")
    for row in playing:
        head = row["title"]
        if row["series"]:
            head = f"{row['series']} · {head}"
        position = row["positionSeconds"]
        runtime = row["runtimeSeconds"]
        where = f"{position:g}s" if not runtime else f"{position:g}s of {runtime:g}s"
        state = "paused" if row["paused"] else "playing"
        print(
            f"{row['device'] or row['deviceId']} · {row['user'] or 'no user'} · "
            f"{head} · {state} · {where} · session {row['id']}"
        )
    if idle:
        labels = sorted({row["device"] or row["deviceId"] for row in idle})
        print(
            f"connected but not playing: {len(idle)} clients"
            + (f" ({', '.join(labels)})" if len(labels) <= 4 else "")
        )


def _print_one(row: dict[str, Any]) -> None:
    head = row["title"]
    if row.get("series"):
        head = f"{row['series']} · {head}"
    state = "paused" if row["paused"] else "playing"
    print(
        f"{row['device']} · {row['user']} · {head} · {state} · "
        f"{row['positionSeconds']:g}s · session {row['id']}"
    )


# ---------------------------------------------------------------- CLI


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Open, pause, resume or stop a playback session on the lab's Jellyfin."
    )
    parser.add_argument("--device", help="a dedicated device name, for example 'phone'")
    parser.add_argument("--title", help="what to play, by title")
    parser.add_argument("--item-id", help="what to play, by Jellyfin item id")
    parser.add_argument("--user", default="admin", choices=("admin", "viewer"),
                        help="whose token to use (default: admin)")
    parser.add_argument("--position", type=float, help="start at this many seconds")
    parser.add_argument("--percent", type=float, help="start at this share (0 to 100)")
    parser.add_argument("--pause", action="store_true", help="report the session paused")
    parser.add_argument("--resume", action="store_true", help="report the session playing")
    parser.add_argument("--stop", action="store_true", help="end the session")
    parser.add_argument("--list", action="store_true", help="print every session")
    parser.add_argument("--listen", action="store_true",
                        help="hold the WebSocket and obey Pause, Unpause and Stop")
    parser.add_argument("--hold", type=float, default=300,
                        help="seconds --listen stays open (default: 300)")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    arguments = parser.parse_args(argv)

    try:
        if arguments.list:
            token = admin_token()
            sessions = playing_sessions(token)
            if arguments.json:
                print(json.dumps([describe(session) for session in sessions], indent=2))
            else:
                _print_sessions(sessions)
            return 0

        if not arguments.device:
            raise PlayError("--device is required for playback commands")
        device = arguments.device

        if arguments.stop:
            ended = stop(device, user=arguments.user,
                         seconds=arguments.position, percent=arguments.percent)
            print(json.dumps(ended, indent=2) if arguments.json else
                  f"{device} stopped" if ended.get("stopped") else
                  f"{device} had no playing session")
            return 0

        if arguments.pause or arguments.resume:
            row = set_paused(device, paused=arguments.pause, user=arguments.user,
                             seconds=arguments.position, percent=arguments.percent)
            print(json.dumps(row, indent=2) if arguments.json else "")
            if not arguments.json:
                _print_one(row)
            return 0

        row = start(
            device=device,
            title=arguments.title or "",
            item_id=arguments.item_id or "",
            user=arguments.user,
            seconds=arguments.position,
            percent=arguments.percent,
        )
        if arguments.json:
            print(json.dumps(row, indent=2))
        else:
            _print_one(row)
        if arguments.listen:
            outcome = listen(device, user=arguments.user, hold_seconds=arguments.hold,
                             seconds=arguments.position, percent=arguments.percent)
            if arguments.json:
                print(json.dumps(outcome, indent=2))
            else:
                if outcome.get("stopped"):
                    print("session ended by the server")
                elif outcome.get("playing"):
                    print("the server still lists the session playing")
                elif outcome.get("endedElsewhere"):
                    print("the session was stopped outside this process")
                else:
                    print("hold ended, and the server no longer lists the session")
        return 0
    except PlayError as error:
        print(f"jellyfin_play: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
