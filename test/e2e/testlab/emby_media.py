#!/usr/bin/env python3
"""Emby's libraries, media and household in the testlab.

The lab's Emby (4.10) comes out of the first-run wizard with one administrator
(`cupola-admin`) and an API key named `Cupola`, which the bootstrap wrote to the
credentials file. This module brings the rest of the media server the flow
catalogue asks for, on the same folders and the same files as the lab's
Jellyfin, idempotently:

* the `Films`, `Series` and `Music` libraries (`/media/movies`, `/media/series`,
  `/media/music`), created through `POST /Library/VirtualFolders` and verified
  by reading the list back. An existing library is never recreated or deleted:
  one with the same name over another folder or another collection type makes
  the script refuse and say so.
* the household member `cupola-viewer`, a user who is not an administrator,
  with the password the bootstrap generated for the lab's requesters. Emby
  hands the new user every library by default, which is checked, not assumed.
* the files: the ones the Jellyfin module copies from the forge's spike, by the
  same code. Both servers mount `state/media`, so a copy for one is a copy for
  the other, and a kind the lab does not hold is declared, never invented.
* a scan, and a wait until `/Items` answers with a movie, an episode and a
  track.
* two viewer states, written with the API key on behalf of `cupola-viewer`:
  `Big Buck Bunny` watched, and the second episode of `Breaking Bad` left at
  30%, which is what puts it in Continue watching. Emby only lists a resume
  point whose `LastPlayedDate` is set, so the write carries one; without it the
  position is stored and Continue watching stays empty.

Run it on its own, or through the scenario that wraps it::

    python3 test/e2e/testlab/emby_media.py
    python3 test/e2e/testlab/emby_media.py --verify
    python3 test/e2e/testlab/testlab.py scenario apply emby-media

The script never writes a database while the container runs, never stops a
container and never prints a credential.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
from datetime import datetime, timezone
from typing import Any

import emby_play as play
import jellyfin_media as shared

MediaError = shared.MediaError
LIBRARIES = shared.LIBRARIES
FILM_NAME = shared.FILM_NAME
SERIES_NAME = shared.SERIES_NAME
VIEWER = shared.VIEWER
ADMIN = play.ADMIN_NAME
MEDIA_ROOT = shared.MEDIA_ROOT

#: The kinds the lab holds, in the order the summary prints them.
KINDS = ("Movie", "Series", "Episode", "MusicAlbum", "Audio")


# ---------------------------------------------------------------- transport


def key() -> str:
    return play.api_key()


def call(path: str, what: str, **kwargs: Any) -> Any:
    try:
        return play.call(path, what, **kwargs)
    except play.PlayError as error:
        raise MediaError(str(error)) from error


# ---------------------------------------------------------------- household


def users(auth: str | None = None) -> list[dict[str, Any]]:
    """The household, from `/Users/Query` (a key has no `/Users/Me`)."""
    answer = call("/Users/Query", "reading the household", token=auth or key())
    rows = answer.get("Items") if isinstance(answer, dict) else None
    return [
        {
            "name": str(user.get("Name") or ""),
            "id": str(user.get("Id") or ""),
            "administrator": bool((user.get("Policy") or {}).get("IsAdministrator")),
            "allFolders": bool((user.get("Policy") or {}).get("EnableAllFolders")),
        }
        for user in (rows if isinstance(rows, list) else [])
        if isinstance(user, dict)
    ]


def _viewer_can_sign_in() -> bool:
    try:
        play.sign_in("viewer", play.device_id_of("states"), "Cupola TestLab States")
        return True
    except play.PlayError:
        return False


def ensure_viewer() -> dict[str, Any]:
    """`cupola-viewer`, a household member, able to sign in with the lab's password."""
    household = users()
    found = next((user for user in household if user["name"] == VIEWER), None)
    if found is None:
        created = call(
            "/Users/New",
            "creating the household member",
            method="POST",
            payload={"Name": VIEWER},
            token=key(),
        )
        found = {"name": VIEWER, "id": str((created or {}).get("Id") or "")}
    if not found["id"]:
        raise MediaError(f"Emby answered no id for {VIEWER}")
    if not _viewer_can_sign_in():
        # The password is the lab's: the credentials file holds it, and the
        # request body is the only place it goes.
        password = play._required(
            play.credentials(), "CUPOLA_TESTLAB_EMBY_REQUESTER_PASSWORD"
        )
        call(
            f"/Users/{found['id']}/Password",
            "setting the household member's password",
            method="POST",
            payload={"NewPw": password},
            token=key(),
        )
        if not _viewer_can_sign_in():
            raise MediaError(f"{VIEWER} cannot sign in with the lab's password")
    return found


# ---------------------------------------------------------------- libraries


def virtual_folders(auth: str | None = None) -> list[dict[str, Any]]:
    answer = call(
        "/Library/VirtualFolders", "reading the libraries", token=auth or key()
    )
    return (
        [folder for folder in answer if isinstance(folder, dict)]
        if isinstance(answer, list)
        else []
    )


def ensure_libraries(auth: str | None = None) -> list[dict[str, Any]]:
    """Create the three libraries that are absent; verify all of them.

    The create call takes query parameters and an empty body, the spelling a
    real Emby 4.10 answers with 204; `refreshLibrary=true` starts the first scan
    without a second request.
    """
    auth = auth or key()
    by_name = {str(folder.get("Name") or ""): folder for folder in virtual_folders(auth)}
    for name, collection_type, path in LIBRARIES:
        folder = by_name.get(name)
        if folder is None:
            query = urllib.parse.urlencode(
                {
                    "name": name,
                    "collectionType": collection_type,
                    "paths": path,
                    "refreshLibrary": "true",
                }
            )
            call(
                f"/Library/VirtualFolders?{query}",
                f"creating the {name} library",
                method="POST",
                payload={},
                token=auth,
            )
            continue
        kind = str(folder.get("CollectionType") or "")
        locations = shared._folder_locations(folder)
        if kind != collection_type:
            raise MediaError(
                f"the library {name!r} is {kind!r}, not {collection_type!r}: "
                "this script will not repurpose a library it did not make"
            )
        if path not in locations:
            raise MediaError(
                f"the library {name!r} points at {locations}, not {path}: "
                "this script will not move a library it did not make"
            )
    after = virtual_folders(auth)
    names = {str(folder.get("Name") or "") for folder in after}
    missing = [name for name, _, _ in LIBRARIES if name not in names]
    if missing:
        raise MediaError(f"Emby did not keep the libraries {missing}")
    return after


# ---------------------------------------------------------------- the scan


def counts(auth: str | None = None) -> dict[str, int]:
    """How many of each kind the server holds, as its own totals."""
    auth = auth or key()
    result: dict[str, int] = {}
    for kind in KINDS:
        query = urllib.parse.urlencode(
            {"Recursive": "true", "IncludeItemTypes": kind, "Limit": 1}
        )
        answer = call(f"/Items?{query}", f"counting {kind}", token=auth)
        total = answer.get("TotalRecordCount") if isinstance(answer, dict) else None
        result[kind] = int(total) if isinstance(total, (int, float)) else 0
    return result


def _has_every_kind(total: dict[str, int]) -> bool:
    return all(total.get(kind, 0) >= 1 for kind in KINDS)


def wait_for_media(*, timeout: float = 180, interval: float = 3) -> dict[str, int]:
    """Scan, then wait until a movie, an episode and a track are in `/Items`."""
    if _has_every_kind(counts()):
        return counts()
    call("/Library/Refresh", "asking for a library scan", method="POST", token=key())
    deadline = time.monotonic() + timeout
    known = counts()
    while time.monotonic() < deadline:
        known = counts()
        if _has_every_kind(known):
            return known
        time.sleep(interval)
    raise MediaError(
        "the scan never produced every kind: "
        + ", ".join(f"{kind} {known.get(kind, 0)}" for kind in KINDS)
        + f" after {timeout:g}s. The files are under {MEDIA_ROOT}; a missing "
        "kind means the forge has no such file, not that Emby ignored it."
    )


# ---------------------------------------------------------------- the items


def items(
    kinds: str,
    *,
    search: str = "",
    limit: int = 40,
    fields: str = "RunTimeTicks,SeriesName,Path",
    auth: str | None = None,
) -> list[dict[str, Any]]:
    query: dict[str, str] = {
        "Recursive": "true",
        "IncludeItemTypes": kinds,
        "Limit": str(limit),
        "Fields": fields,
        "SortBy": "SortName",
    }
    if search:
        query["SearchTerm"] = search
    answer = call(
        f"/Items?{urllib.parse.urlencode(query)}",
        f"reading {kinds}",
        token=auth or key(),
    )
    rows = answer.get("Items") if isinstance(answer, dict) else None
    return [row for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []


def episode_of_season(season: int, number: int) -> dict[str, Any]:
    """One episode, addressed by its place in the show and not by its title.

    The season and the number survive any scan; the name is what the file said.
    `/Shows/{id}/Episodes` is not used: a key has no user, and an episode list
    is the same `/Items` read filtered to the kind.
    """
    rows = items("Episode", search=SERIES_NAME)
    for row in rows:
        if row.get("ParentIndexNumber") == season and row.get("IndexNumber") == number:
            return row
    raise MediaError(
        f"the server holds no season {season} episode {number}; the scan found "
        + ", ".join(
            f"S{row.get('ParentIndexNumber')}E{row.get('IndexNumber')}" for row in rows
        )
    )


def samples(auth: str | None = None) -> dict[str, dict[str, Any]]:
    """One movie, one episode and one track, with the ids the e2e quotes."""
    auth = auth or key()
    film = shared.one(items("Movie", search=FILM_NAME, auth=auth), FILM_NAME, "movie")
    series = shared.one(
        items("Series", search=SERIES_NAME, auth=auth), SERIES_NAME, "series"
    )
    episode = episode_of_season(1, 2)
    track = shared.one(
        items("Audio", search="One More Time", auth=auth), "One More Time", "track"
    )
    return {
        "movie": shared._brief(film),
        "series": shared._brief(series),
        "episode": {**shared._brief(episode), "series": episode.get("SeriesName") or ""},
        "track": shared._brief(track),
    }


# ---------------------------------------------------------------- the states


def _user_data(item_id: str, viewer_id: str) -> dict[str, Any]:
    answer = call(
        f"/Users/{viewer_id}/Items/{item_id}",
        "reading the item's user data",
        token=key(),
    )
    data = answer.get("UserData") if isinstance(answer, dict) else None
    return data if isinstance(data, dict) else {}


def _now_ticks_text() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0000000Z")


def ensure_watch_states(
    viewer: dict[str, Any], found: dict[str, dict[str, Any]] | None = None
) -> dict[str, Any]:
    """The movie watched and the episode part-watched, for `cupola-viewer`.

    Both are written with the API key, for the viewer's own id:
    `POST /Users/{id}/PlayedItems/{item}` marks the movie, and
    `POST /Users/{id}/Items/{item}/UserData` sets a resume position. Emby lets
    an administrator write another person's state, where Jellyfin makes the
    household member do it.
    """
    found = found or samples()
    film = found["movie"]
    episode = found["episode"]
    viewer_id = str(viewer["id"])

    runtime = int(episode.get("runtimeTicks") or 0)
    if runtime <= 0:
        raise MediaError(f"the episode {episode['name']!r} reports no runtime")
    position = int(runtime * 0.3)

    if _user_data(film["id"], viewer_id).get("Played") is not True:
        call(
            f"/Users/{viewer_id}/PlayedItems/{film['id']}",
            "marking the movie watched",
            method="POST",
            token=key(),
        )

    episode_data = _user_data(episode["id"], viewer_id)
    stored = int(episode_data.get("PlaybackPositionTicks") or 0)
    # Half a percent: an earlier helper run may have stopped this episode a
    # few seconds on, and the fixture is 30% exactly.
    if episode_data.get("Played") is True or abs(stored - position) > runtime * 0.005:
        call(
            f"/Users/{viewer_id}/Items/{episode['id']}/UserData",
            "setting the episode's resume position",
            method="POST",
            payload={
                "PlaybackPositionTicks": position,
                "Played": False,
                "LastPlayedDate": _now_ticks_text(),
            },
            token=key(),
        )

    states = read_watch_states(viewer, found)
    if states["filmPlayed"] is not True:
        raise MediaError(f"{FILM_NAME} is not marked watched for {VIEWER}")
    if states["resume"]["percent"] < 29.5 or states["resume"]["percent"] > 30.5:
        raise MediaError(
            f"the episode's resume position is {states['resume']['percent']:g}%, "
            "not the 30% asked for"
        )
    if not states["inResume"]:
        raise MediaError(
            f"{states['resume']['title']!r} has a resume position but is not in "
            "Continue watching, so the state the app reads would be empty"
        )
    return states


def read_watch_states(
    viewer: dict[str, Any], found: dict[str, dict[str, Any]] | None = None
) -> dict[str, Any]:
    """What `cupola-viewer` holds right now, without writing anything."""
    found = found or samples()
    film = found["movie"]
    episode = found["episode"]
    viewer_id = str(viewer["id"])
    runtime = int(episode.get("runtimeTicks") or 0)
    film_data = _user_data(film["id"], viewer_id)
    episode_data = _user_data(episode["id"], viewer_id)
    stored = int(episode_data.get("PlaybackPositionTicks") or 0)
    resume = call(
        f"/Users/{viewer_id}/Items/Resume?Limit=20&MediaTypes=Video",
        "reading Continue watching",
        token=key(),
    )
    resume_ids = (
        {
            str(row.get("Id"))
            for row in (resume.get("Items") or [])
            if isinstance(row, dict)
        }
        if isinstance(resume, dict)
        else set()
    )
    return {
        "user": VIEWER,
        "watched": FILM_NAME,
        "filmPlayed": film_data.get("Played") is True,
        "resume": {
            "title": episode["name"],
            "seconds": round(stored / play.TICKS_PER_SECOND, 1),
            "percent": round(stored / runtime * 100, 1) if runtime else 0.0,
        },
        "inResume": episode["id"] in resume_ids,
    }


# ---------------------------------------------------------------- the audit


def library_rows(auth: str | None = None) -> list[dict[str, str]]:
    return [
        {
            "name": str(folder.get("Name") or ""),
            "collectionType": str(folder.get("CollectionType") or ""),
            "location": (shared._folder_locations(folder) or [""])[0],
            "itemId": str(folder.get("ItemId") or ""),
        }
        for folder in virtual_folders(auth)
    ]


def viewer_reads(
    viewer: dict[str, Any], rows: list[dict[str, str]] | None = None
) -> dict[str, int]:
    """What `cupola-viewer` itself can see in each library.

    Read with the member's own token, which is what a household member is: the
    administrator's key sees the server, and the member's sees what the policy
    exposes. Browsing is by `ParentId`, which is also how the app does it.
    """
    token, _, _ = play.sign_in(
        "viewer", play.device_id_of("states"), "Cupola TestLab States"
    )
    kinds = {"movies": "Movie", "tvshows": "Series", "music": "MusicAlbum"}
    result: dict[str, int] = {}
    for row in rows if rows is not None else library_rows():
        kind = kinds.get(row["collectionType"])
        if kind is None or not row["itemId"]:
            result[row["name"]] = 0
            continue
        query = urllib.parse.urlencode(
            {
                "ParentId": row["itemId"],
                "Recursive": "true",
                "Limit": 1,
                "IncludeItemTypes": kind,
                "UserId": viewer["id"],
            }
        )
        answer = call(
            f"/Items?{query}", f"reading {row['name']} as {VIEWER}", token=token
        )
        total = answer.get("TotalRecordCount") if isinstance(answer, dict) else 0
        result[row["name"]] = int(total) if isinstance(total, (int, float)) else 0
    return result


def audit(*, with_states: bool = True) -> dict[str, Any]:
    auth = key()
    household = users(auth)
    viewer = next((user for user in household if user["name"] == VIEWER), None)
    if viewer is None:
        raise MediaError(f"the household has no {VIEWER}")
    libraries = library_rows(auth)
    found = samples(auth)
    return {
        "libraries": libraries,
        "viewer": viewer_reads(viewer, libraries),
        "counts": counts(auth),
        "samples": found,
        "users": household,
        "states": read_watch_states(viewer, found) if with_states else None,
        "sessions": [
            play.describe(session)
            for session in play.playing_sessions(auth)
            if session.get("NowPlayingItem")
        ],
    }


def assert_ready(state: dict[str, Any]) -> None:
    """The scenario's own acceptance: every claim, re-read from the server."""
    libraries = {row["name"]: row for row in state["libraries"]}
    for name, collection_type, path in LIBRARIES:
        row = libraries.get(name)
        if row is None:
            raise MediaError(f"the {name} library is not on the server")
        if row["collectionType"] != collection_type:
            raise MediaError(f"the {name} library is {row['collectionType']!r}")
        if row["location"] != path:
            raise MediaError(f"the {name} library reads {row['location']!r}, not {path!r}")
    for kind in KINDS:
        if state["counts"].get(kind, 0) < 1:
            raise MediaError(f"the server holds no {kind}: the scan found nothing")
    names = [user["name"] for user in state["users"]]
    if ADMIN not in names or VIEWER not in names:
        raise MediaError(f"the household is {names}, without the admin and the requester")
    administrators = {user["name"] for user in state["users"] if user["administrator"]}
    if ADMIN not in administrators:
        raise MediaError(f"{ADMIN} is not an administrator")
    if VIEWER in administrators:
        raise MediaError(f"{VIEWER} is an administrator, not a household member")
    for name, _, _ in LIBRARIES:
        if state["viewer"].get(name, 0) < 1:
            raise MediaError(
                f"{VIEWER} sees nothing in {name}: the household member's policy "
                "does not expose that library"
            )
    if state["states"] is None:
        raise MediaError("the viewer's watch states were not verified")
    if state["states"]["filmPlayed"] is not True:
        raise MediaError(f"{FILM_NAME} is not watched by {VIEWER}")
    if not state["states"]["inResume"]:
        raise MediaError(
            f"{state['states']['resume']['title']!r} is not in {VIEWER}'s "
            "Continue watching"
        )


# ---------------------------------------------------------------- printing


def summary(state: dict[str, Any], copies: list[dict[str, str]] | None = None) -> str:
    lines: list[str] = []
    for row in state["libraries"]:
        lines.append(
            f"library {row['name']} · {row['collectionType']} · {row['location']}"
        )
    total = state["counts"]
    lines.append(
        "items · " + ", ".join(f"{total.get(kind, 0)} {kind}" for kind in KINDS)
    )
    for kind, sample in state["samples"].items():
        lines.append(f"{kind} · {sample['name']} · {sample['id']}")
    lines.append(
        "users · "
        + ", ".join(
            f"{user['name']}{' (admin)' if user['administrator'] else ''}"
            for user in state["users"]
        )
    )
    lines.append(
        f"{VIEWER} sees · "
        + ", ".join(f"{count} in {name}" for name, count in state["viewer"].items())
    )
    if state["states"]:
        resume = state["states"]["resume"]
        lines.append(
            f"states · {state['states']['watched']} watched by "
            f"{state['states']['user']} · {resume['title']} at "
            f"{resume['percent']:g}% ({resume['seconds']:g}s), in Continue watching"
        )
    lines.append(f"sessions · {len(state['sessions'])} playing")
    if copies:
        actions: dict[str, int] = {}
        for row in copies:
            actions[row["action"]] = actions.get(row["action"], 0) + 1
        lines.append(
            "files · "
            + ", ".join(f"{count} {action}" for action, count in sorted(actions.items()))
        )
    return "\n".join(lines)


def setup() -> dict[str, Any]:
    # The household and the libraries first: a lab whose forge has no spike
    # still gets a server with its member and its three libraries, and says
    # what is missing when the files are copied.
    viewer = ensure_viewer()
    ensure_libraries()
    copied = shared.copy_media()
    found_counts = wait_for_media()
    libraries = library_rows()
    found = samples()
    state: dict[str, Any] = {
        "libraries": libraries,
        "viewer": viewer_reads(viewer, libraries),
        "counts": found_counts,
        "samples": found,
    }
    state["states"] = ensure_watch_states(viewer, found)
    state["users"] = users()
    state["sessions"] = [
        play.describe(session)
        for session in play.playing_sessions()
        if session.get("NowPlayingItem")
    ]
    assert_ready(state)
    return {"state": state, "copies": copied}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Bring Emby's libraries, media and watch states into the testlab."
    )
    parser.add_argument("--verify", action="store_true",
                        help="read the server and assert, changing nothing")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    arguments = parser.parse_args(argv)
    try:
        if arguments.verify:
            state = audit()
            assert_ready(state)
            result: dict[str, Any] = {"state": state, "copies": []}
        else:
            result = setup()
        if arguments.json:
            print(json.dumps(result, indent=2))
        else:
            print(summary(result["state"], result["copies"]))
        return 0
    except (MediaError, play.PlayError) as error:
        print(f"emby_media: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
