"""Two streams at once on the lab's Emby, watched by Tracearr.

The seeded lab already has Tracearr connected to the lab's Jellyfin and Emby,
with its owner, its public key and its rule `Too many streams at once` (one
stream allowed). This scenario is what makes the rule fire: the household
member `cupola-viewer` plays two titles on two devices of the Emby, one after
the other, and the scenario waits until Tracearr lists both streams and has
recorded a new violation for them.

It leaves the world the e2e tier and the journeys read: two live streams in
Tracearr's Live tab, the playbacks in Emby's Now playing, and a violation of the
rule (two streams where one is allowed) in Violations.

The teardown ends the playbacks on the server, and waits until Tracearr no
longer lists them. What stays, on purpose: Tracearr's history and violations
(they are its record, and the e2e tests read them), its servers, its rule and
its key. Deleting a violation is not something the lab does, and a green
teardown must not be mistaken for a clean Tracearr: ``verify_absent`` says what
it asserts.
"""

from __future__ import annotations

from typing import Any, Callable

import jellyfin_play
import tracearr_lab as lab
from scenarios.base import Scenario, ScenarioError


def _guard(action: str, work: Callable[[], Any]) -> Any:
    try:
        return work()
    except (lab.TracearrError, lab.emby.PlayError, jellyfin_play.PlayError) as error:
        raise ScenarioError(f"tracearr-streams {action}: {error}") from error


def _helper_devices() -> set[str]:
    return {device for device, _ in lab.DEVICES}


def _helper_streams() -> list[dict[str, Any]]:
    return [row for row in lab.streams() if row.get("player") in _helper_devices()]


class TracearrStreamsScenario(Scenario):
    name = "tracearr-streams"
    profiles = ("core", "media")

    def apply(self) -> None:
        def run() -> None:
            lab.setup()
            lab.wait_for_violation(lab.play_two_streams)

        _guard("apply", run)

    def verify(self) -> None:
        def run() -> None:
            listed = _helper_streams()
            if {row.get("player") for row in listed} != _helper_devices():
                raise lab.TracearrError(
                    "Tracearr does not list both streams: "
                    + ", ".join(str(row.get("player")) for row in listed)
                )
            if not any(lab.concurrent_streams(row) >= 2 for row in lab.violations(100)):
                raise lab.TracearrError("Tracearr holds no violation of two streams")

        _guard("verify", run)

    def teardown(self) -> None:
        def run() -> None:
            lab.stop_playbacks()
            lab.wait_for(
                "Tracearr to stop listing the streams",
                lambda: not _helper_streams(),
                timeout=90,
            )

        _guard("teardown", run)

    def verify_absent(self) -> None:
        """No helper playback is left; the monitor's record stays, and must.

        Called by ``testlab.py scenario teardown`` after ``teardown``: no
        session of the helper's devices plays on Emby, Tracearr lists none of
        its streams, and Tracearr still holds its two servers and its rule.
        """

        def run() -> None:
            playing = [
                session
                for session in lab.emby.playing_sessions()
                if session.get("NowPlayingItem")
                and str(session.get("DeviceId") or "").startswith(lab.emby.DEVICE_PREFIX)
            ]
            if playing:
                raise lab.TracearrError(
                    "a playback the helper opened is still playing: "
                    + ", ".join(str(session.get("DeviceName")) for session in playing)
                )
            if _helper_streams():
                raise lab.TracearrError("Tracearr still lists a stream of the helper")
            lab.assert_ready(lab.audit())

        _guard("verify_absent", run)


SCENARIO = TracearrStreamsScenario()
