#!/usr/bin/env python3
"""A playback client for the lab's Emby, driven from the command line.

The sibling of `jellyfin_play.py`, and like it the reporting half of a player
and not a player: it opens a session, puts a title in Now playing, holds a
position, pauses, resumes and stops, and with `--listen` it obeys what the
server relays::

    python3 test/e2e/testlab/emby_play.py --device phone \\
        --title 'Big Buck Bunny' --user viewer --listen
    python3 test/e2e/testlab/emby_play.py --device phone --pause
    python3 test/e2e/testlab/emby_play.py --device phone --stop
    python3 test/e2e/testlab/emby_play.py --list

It prints the same lines as the Jellyfin helper (`listening on`, `playstate
Pause`, `message: ...`), so the tests that wait for them read either server.

Four facts about Emby 4.10 shape the file, each measured on a real server and
not read from the documentation:

**A session belongs to a signed-in device, never to the API key.** The key the
app holds has no user and no device, and a playback reported with it is
refused. So the helper signs a person in (`POST /Users/AuthenticateByName`
with an `X-Emby-Authorization` header naming the `DeviceId`), keeps that
token, and reports playback with it. Two `--device` values are two sign-ins
and two rows in `GET /Sessions`; the key is only used to read the server.

**Playback needs the capabilities first.** `POST /Sessions/Playing` without a
`PlaySessionId` is a 400 (`Value cannot be null (key)`), and a session that has
not announced `POST /Sessions/Capabilities/Full` is not remote controllable.
The sequence is capabilities, then `Playing`, then `Playing/Progress` to hold
or pause, then `Playing/Stopped`.

**A pause is the client's own report.** `POST /Sessions/{id}/Playing/Pause`
only relays a `Playstate` frame over the WebSocket the client holds at
`/embywebsocket?api_key=<token>&deviceId=<id>`; the client turns it into a
paused `Progress`. Emby does not ask the client to be paused: without `--listen`
the call is answered 204 and changes nothing, the same trap as Jellyfin's.

**Item ids are short numbers.** `15`, not a GUID, so nothing here assumes a
shape; the id is whatever `/Items` says.

The credentials come from the chmod-600 file the bootstrap writes: the
administrator's password (`CUPOLA_TESTLAB_EMBY_PASSWORD`) and the household
member's (`CUPOLA_TESTLAB_EMBY_REQUESTER_PASSWORD`), and the API key for
reading. None is printed. The one secret written is each device's access token,
in its own 0600 state file: signing in again on the same `DeviceId` makes Emby
open a new session and drop the playback the earlier token held.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Iterable

import jellyfin_play as shared

EMBY = os.environ.get("CUPOLA_TESTLAB_EMBY_URL", "http://127.0.0.1:8097")

# What the module shares with the Jellyfin helper: the errors, the lab's state,
# the tick, and the way a `--device` name becomes a stable `DeviceId`.
PlayError = shared.PlayError
STATE_ROOT = shared.STATE_ROOT
REPO_ROOT = shared.REPO_ROOT
TICKS_PER_SECOND = shared.TICKS_PER_SECOND
DEVICE_PREFIX = shared.DEVICE_PREFIX
CLIENT = shared.CLIENT
VERSION = shared.VERSION
DEVICE_DEFAULT = shared.DEVICE_DEFAULT
device_id_of = shared.device_id_of
credentials = shared.credentials
runtime_ticks = shared.runtime_ticks
position_ticks = shared.position_ticks
_required = shared._required
_now = shared._now
_device_of_id = shared._device_of_id

PLAY_STATE = STATE_ROOT / "emby-play"

DIRECT_PLAY = "DirectPlay"

ADMIN_NAME = "cupola-admin"

#: Every id Emby hands out is opaque; the helper only ever echoes it.
_ITEM_FIELDS = "RunTimeTicks,SeriesName,MediaSources,Path"


# ---------------------------------------------------------------- transport


def authorization(token: str, device_id: str, device_name: str = DEVICE_DEFAULT) -> str:
    """The `X-Emby-Authorization` value that names a client and its device."""
    parts = (
        f'MediaBrowser Client="{CLIENT}", Device="{device_name}", '
        f'DeviceId="{device_id}", Version="{VERSION}"'
    )
    return f'{parts}, Token="{token}"' if token else parts


def request(
    path: str,
    *,
    method: str = "GET",
    payload: Any | None = None,
    token: str = "",
    timeout: float = 30,
) -> tuple[int, Any]:
    """One call under `/emby`. The token travels in `X-Emby-Token`.

    No `X-Emby-Authorization`: a token already names its device, and sending
    the client's identity with the API key would register a user-less device
    in `/Sessions` for every read this helper makes.
    """
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    if token:
        headers["X-Emby-Token"] = token
    call = urllib.request.Request(
        f"{EMBY}/emby{path}", data=data, method=method, headers=headers
    )
    try:
        with urllib.request.urlopen(call, timeout=timeout) as response:
            body = response.read()
            status = response.status
    except urllib.error.HTTPError as error:
        body = error.read()
        status = error.code
    except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.HTTPException) as error:
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


def api_key(values: dict[str, str] | None = None) -> str:
    """The key the app holds, which is all the helper reads the server with."""
    return _required(values or credentials(), "CUPOLA_TESTLAB_EMBY_TOKEN")


def sign_in(user: str, device_id: str, device_name: str) -> tuple[str, str, str]:
    """Sign in as the lab's administrator or household member.

    Answers `(token, user id, name)`. The password is read from the credentials
    file and goes into the request body only; a refusal is worded from the
    username alone.
    """
    values = credentials()
    if user == "admin":
        username = ADMIN_NAME
        password = _required(values, "CUPOLA_TESTLAB_EMBY_PASSWORD")
    else:
        username = _required(values, "CUPOLA_TESTLAB_EMBY_REQUESTER_USERNAME")
        password = _required(values, "CUPOLA_TESTLAB_EMBY_REQUESTER_PASSWORD")
    body = json.dumps({"Username": username, "Pw": password}).encode("utf-8")
    headers = {
        "X-Emby-Authorization": authorization("", device_id, device_name),
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    attempt = urllib.request.Request(
        f"{EMBY}/emby/Users/AuthenticateByName",
        data=body,
        method="POST",
        headers=headers,
    )
    try:
        with urllib.request.urlopen(attempt, timeout=30) as response:
            answer = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise PlayError(
            f"signing in as {username} was refused with {error.code}"
        ) from None
    except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.HTTPException) as error:
        raise PlayError(f"signing in as {username} did not answer: {error}") from error
    token = answer.get("AccessToken") or ""
    person = answer.get("User") or {}
    user_id = person.get("Id") or ""
    if not token or not user_id:
        raise PlayError(f"signing in as {username} answered no token and no user")
    return token, user_id, person.get("Name") or username


def account(
    user: str,
    device_id: str,
    device_name: str = DEVICE_DEFAULT,
    *,
    keep: bool = False,
) -> dict[str, str]:
    """The sign-in a command runs as: `admin` or `viewer`, per device.

    The token is cached in the device's own state file and reused while the
    server still accepts it, because a second sign-in on the same `DeviceId`
    drops the playback the first one holds. A command that only acts on a
    session already open (`keep=True`: pause, stop) takes the sign-in that
    opened it, whoever the flag names, for the same reason; a start asks for
    the person it was told to.
    """
    if user == "":
        user = "admin"
    if user not in ("admin", "viewer"):
        raise PlayError(f"unknown user {user!r}: use admin or viewer")
    stored = _read_state(device_id)
    token = str(stored.get("token") or "")
    if token and (keep or str(stored.get("user") or "") == user):
        status, _ = request("/Sessions", token=token)
        if 200 <= status < 300:
            return {
                "token": token,
                "userId": str(stored.get("userId") or ""),
                "name": str(stored.get("userName") or ""),
            }
    token, user_id, name = sign_in(user, device_id, device_name)
    _write_state(
        device_id,
        {
            **stored,
            "deviceId": device_id,
            "deviceName": device_name,
            "user": user,
            "userId": user_id,
            "userName": name,
            "token": token,
            "updatedAt": _now(),
        },
    )
    return {"token": token, "userId": user_id, "name": name}


# ---------------------------------------------------------------- the item


def find_item(title: str = "", item_id: str = "", kinds: str = "Movie,Episode,Audio") -> dict[str, Any]:
    """The one item a title names, or the item an id names.

    Read with the API key and `/Items`, the route Emby honours `Fields` on (the
    item-by-id route answers 404 without a user).
    """
    key = api_key()
    if item_id:
        answer = call(
            f"/Items?{urllib.parse.urlencode({'Ids': item_id, 'Fields': _ITEM_FIELDS})}",
            "reading the item",
            token=key,
        )
        rows = answer.get("Items") if isinstance(answer, dict) else None
        if not rows:
            raise PlayError(f"the server answered no item for {item_id}")
        return rows[0]
    if not title.strip():
        raise PlayError("say what to play: --title 'Big Buck Bunny' or --item-id <id>")
    query = urllib.parse.urlencode(
        {
            "Recursive": "true",
            "SearchTerm": title,
            "IncludeItemTypes": kinds,
            "Limit": 40,
            "Fields": _ITEM_FIELDS,
        }
    )
    answer = call(f"/Items?{query}", "searching the library", token=key)
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


def media_source_id(item: dict[str, Any]) -> str:
    sources = item.get("MediaSources")
    if isinstance(sources, list) and sources:
        first = sources[0]
        if isinstance(first, dict) and first.get("Id"):
            return str(first["Id"])
    return str(item.get("Id") or "")


# ---------------------------------------------------------------- the session


def playing_sessions(token: str | None = None) -> list[dict[str, Any]]:
    """Every session the server knows about; those playing carry a title.

    Emby takes no activity window, so this is the whole list, which is what
    `--list` wants: an idle device is a fact about the lab too. The app filters
    by `LastActivityDate` and `NowPlayingItem` on its own.
    """
    answer = call("/Sessions", "reading the sessions", token=token or api_key())
    return answer if isinstance(answer, list) else []


def session_for_device(device_id: str) -> dict[str, Any] | None:
    for session in playing_sessions():
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


def announce(who: dict[str, str]) -> None:
    """Tell the server what this client can be asked to do.

    Without it the session is not remote controllable, and a `Pause` the app
    sends has nobody to land on.
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
        token=who["token"],
    )


def _report(
    path: str,
    *,
    who: dict[str, str],
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
    if not path.endswith("/Stopped"):
        payload.update(
            {
                "IsPaused": bool(paused),
                "IsMuted": False,
                "PlayMethod": DIRECT_PLAY,
                "CanSeek": True,
                "VolumeLevel": 80,
                "RepeatMode": "RepeatNone",
                "EventName": "pause" if paused else "timeupdate",
            }
        )
    call(
        path,
        "reporting playback",
        method="POST",
        payload=payload,
        token=who["token"],
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
    item = find_item(title=title, item_id=item_id)
    position = position_ticks(item, seconds, percent)
    play_session = uuid.uuid4().hex
    announce(who)
    _report(
        "/Sessions/Playing",
        who=who,
        item_id=str(item["Id"]),
        source_id=media_source_id(item),
        play_session_id=play_session,
        position=position,
        paused=paused,
    )
    session = session_for_device(device_id)
    if session is None:
        raise PlayError(
            f"the server accepted playback for {device!r} but lists no such session"
        )
    reported = describe(session)
    _write_state(
        device_id,
        {
            **_read_state(device_id),
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


def _held(device: str, user: str) -> tuple[str, dict[str, str], dict[str, Any], dict[str, Any], dict[str, Any]]:
    """The device's id, its sign-in, its session, the item it plays and its state."""
    device_id = device_id_of(device)
    who = account(user, device_id, device, keep=True)
    session = session_for_device(device_id)
    if session is None or not session.get("NowPlayingItem"):
        raise PlayError(f"{device!r} holds no playing session")
    playing = session.get("NowPlayingItem") or {}
    item = find_item(item_id=str(playing.get("Id") or ""))
    return device_id, who, session, item, _read_state(device_id)


def set_paused(
    device: str,
    *,
    paused: bool,
    user: str = "admin",
    seconds: float | None = None,
    percent: float | None = None,
) -> dict[str, Any]:
    """Report a pause or a resume for the session `device` already holds."""
    device_id, who, session, item, stored = _held(device, user)
    position = int(_play_state(session).get("PositionTicks") or 0)
    if seconds is not None or percent is not None:
        position = position_ticks(item, seconds, percent)
    _report(
        "/Sessions/Playing/Progress",
        who=who,
        item_id=str(item["Id"]),
        source_id=media_source_id(item),
        play_session_id=stored.get("playSessionId") or uuid.uuid4().hex,
        position=position,
        paused=paused,
    )
    after = session_for_device(device_id)
    if after is None:
        raise PlayError(f"{device!r} vanished from the session list while pausing")
    reported = describe(after)
    _write_state(
        device_id,
        {
            **stored,
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


def stop(
    device: str,
    *,
    user: str = "admin",
    seconds: float | None = None,
    percent: float | None = None,
) -> dict[str, Any]:
    """End the session `device` holds: `POST /Sessions/Playing/Stopped`."""
    device_id = device_id_of(device)
    session = session_for_device(device_id)
    if session is None or not session.get("NowPlayingItem"):
        _remove_state(device_id)
        return {"stopped": False, "device": device, "reason": "no playing session"}
    who = account(user, device_id, device, keep=True)
    playing = session.get("NowPlayingItem") or {}
    item = find_item(item_id=str(playing.get("Id") or ""))
    position = int(_play_state(session).get("PositionTicks") or 0)
    if seconds is not None or percent is not None:
        position = position_ticks(item, seconds, percent)
    stored = _read_state(device_id)
    _report(
        "/Sessions/Playing/Stopped",
        who=who,
        item_id=str(item["Id"]),
        source_id=media_source_id(item),
        play_session_id=stored.get("playSessionId") or uuid.uuid4().hex,
        position=position,
        paused=True,
    )
    _remove_state(device_id)
    after = session_for_device(device_id)
    return {
        "stopped": after is None or not (after.get("NowPlayingItem") or {}),
        "device": device,
        "title": playing.get("Name") or "",
        "positionSeconds": round(position / TICKS_PER_SECOND, 1),
    }


def session_id_for(device: str) -> str:
    """The server's id of the session on `device`, for Cupola's own commands."""
    session = session_for_device(device_id_of(device))
    return str((session or {}).get("Id") or "")


def stop_all(*, user: str = "admin") -> list[dict[str, Any]]:
    """Stop every session whose device this helper made.

    A device is the helper's when its `DeviceId` starts with `cupola-play-`.
    Anything else in the list (the app's key, a browser) is left alone.
    """
    stopped: list[dict[str, Any]] = []
    for session in playing_sessions():
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

    The frames that matter are `Playstate` (Pause, Unpause, PlayPause, Stop,
    Seek) and `GeneralCommand` with `DisplayMessage`. Every state change is
    reported back with `Progress`, so a pause issued from Cupola's session card
    is visible to the next `/Sessions` read and not only dispatched.
    """
    try:
        from websockets.sync.client import connect
    except ImportError as error:  # pragma: no cover - the lab's Mac has it
        raise PlayError(
            "the Python package 'websockets' is missing: pip3 install websockets"
        ) from error

    device_id, who, session, item, stored = _held(device, user)
    play_session = stored.get("playSessionId") or uuid.uuid4().hex
    position = int(_play_state(session).get("PositionTicks") or 0)
    if seconds is not None or percent is not None:
        position = position_ticks(item, seconds, percent)
    paused = _play_state(session).get("IsPaused") is True

    uri = (
        EMBY.replace("http://", "ws://").replace("https://", "wss://")
        + "/embywebsocket?"
        + urllib.parse.urlencode({"api_key": who["token"], "deviceId": device_id})
    )
    last_keepalive = 0.0
    last_activity = time.monotonic()
    deadline = time.monotonic() + hold_seconds
    stop_asked = False
    ended_elsewhere = False
    messages: list[str] = []

    def report(now_paused: bool) -> None:
        _report(
            "/Sessions/Playing/Progress",
            who=who,
            item_id=str(item["Id"]),
            source_id=media_source_id(item),
            play_session_id=play_session,
            position=position,
            paused=now_paused,
        )

    with connect(uri, open_timeout=10) as socket:
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
                    if str(data.get("Name") or "") == "DisplayMessage":
                        text = (data.get("Arguments") or {}).get("Text") or ""
                        messages.append(f"message {text!r}")
                        if verbose:
                            print(f"message: {text}", flush=True)
            now = time.monotonic()
            if not paused and now - last_activity >= 1:
                position += int((now - last_activity) * TICKS_PER_SECOND)
                last_activity = now
            if now - last_keepalive >= keepalive_seconds:
                last_keepalive = now
                # Somebody else may have stopped this session. A keepalive
                # would open it again, so the server is asked first.
                current = session_for_device(device_id)
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
    after = session_for_device(device_id)
    still_playing = after is not None and bool(after.get("NowPlayingItem"))
    if still_playing:
        _write_state(
            device_id,
            {
                **stored,
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
        _remove_state(device_id)
    return {
        "device": device,
        "stopped": False,
        "endedElsewhere": ended_elsewhere,
        "paused": paused,
        "playing": still_playing,
        "messages": messages,
    }


# ---------------------------------------------------------------- state file


def _state_path(device_id: str) -> Path:
    return PLAY_STATE / f"{_device_of_id(device_id)}.json"


def _write_state(device_id: str, state: dict[str, Any]) -> None:
    PLAY_STATE.mkdir(parents=True, exist_ok=True)
    os.chmod(PLAY_STATE, 0o700)
    path = _state_path(device_id)
    path.write_text(json.dumps(state, indent=2), encoding="utf-8")
    os.chmod(path, 0o600)


def _read_state(device_id: str) -> dict[str, Any]:
    path = _state_path(device_id)
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _remove_state(device_id: str) -> None:
    path = _state_path(device_id)
    if path.exists():
        path.unlink()


# ---------------------------------------------------------------- printing


def _print_sessions(sessions: Iterable[dict[str, Any]]) -> None:
    rows = list(sessions)
    playing = [describe(session) for session in rows if session.get("NowPlayingItem")]
    idle = [describe(session) for session in rows if not session.get("NowPlayingItem")]
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
        description="Open, pause, resume or stop a playback session on the lab's Emby."
    )
    parser.add_argument("--device", help="a dedicated device name, for example 'phone'")
    parser.add_argument("--title", help="what to play, by title")
    parser.add_argument("--item-id", help="what to play, by Emby item id")
    parser.add_argument("--user", default="admin", choices=("admin", "viewer"),
                        help="who signs in on the device (default: admin)")
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
            sessions = playing_sessions()
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
            if arguments.json:
                print(json.dumps(row, indent=2))
            else:
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
        print(f"emby_play: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
