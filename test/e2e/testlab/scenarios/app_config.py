"""The app's configuration for a profile, and the lab state it needs.

A profile is not only a list of connections: two of them need the lab to be
in a particular state before the app can read them.

* P7 reaches its servers at the address away from home, the second listener
  of the Toxiproxy on the same upstream. This scenario makes sure that
  listener exists for every connection the profile serves away; the
  `away-home` scenario is what switches it off.
* P8 reaches Radarr, Sonarr and Seerr at the lab's gateway, and P1, P6 and
  P9 reach their second Radarr at the lab's edge, the self-signed origin in
  front of Radarr. Both are processes of the host, and this scenario starts
  the ones that are not running, without touching the ones that are (the
  edge's certificate is not made again: a new one would leave the pin the
  configuration carries behind).

The scenario's own acceptance is that the configuration is there, that it is
the app's own storage, and that the addresses it names answer the lab: the
plain HTTP services with the credential the configuration carries, the rest
by the port that listens.
"""

from __future__ import annotations

import json
import os
import socket
import ssl
import urllib.error
import urllib.request
from typing import Any

import app_config
import edge_lab
import faults_lab
import gateway_lab
from scenarios.base import Scenario, ScenarioError

#: The plain HTTP services, and the path that answers with their credential.
PROBES: dict[str, tuple[str, str]] = {
    "seerr": ("/api/v1/status", "key"),
    "radarr": ("/api/v3/system/status", "key"),
    "sonarr": ("/api/v3/system/status", "key"),
    "lidarr": ("/api/v1/system/status", "key"),
    "readarr": ("/api/v1/system/status", "key"),
    "prowlarr": ("/api/v1/system/status", "key"),
    "bazarr": ("/api/system/status", "key"),
    "sabnzbd": ("/api?mode=version&apikey={key}", "query"),
    "jellyfin": ("/System/Info/Public", "none"),
    "emby": ("/emby/System/Info/Public", "none"),
    "plex": ("/identity", "none"),
    # The one read that needs the public key and names the version.
    "tracearr": ("/api/v1/public/health", "bearer"),
}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """A redirect is an answer here, not a place to go."""

    def redirect_request(self, *args: object, **kwargs: object) -> None:
        return None


def profile() -> str:
    """The profile this scenario configures the app for."""
    value = os.environ.get("CUPOLA_TESTLAB_PROFILE", "P1").strip().upper()
    if value not in app_config.PROFILES:
        raise ScenarioError(
            f"unknown profile {value!r}; choose one of "
            + ", ".join(sorted(app_config.PROFILES))
        )
    return value


def probe(
    url: str, path: str, headers: dict[str, str] | None = None
) -> int:
    """Ask [url] for [path] and answer the status, redirects aside.

    The lab's own certificates are self-signed: the edge and the TrueNAS
    fixture present one, and the app trusts it by its fingerprint, which the
    configuration carries. Here it is enough that the address answers.
    """
    request = urllib.request.Request(
        f"{url}{path}",
        headers=headers or {"Accept": "application/json"},
    )
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl._create_unverified_context()),
        _NoRedirect,
    )
    try:
        with opener.open(request, timeout=15) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except urllib.error.URLError as error:
        raise ScenarioError(f"{url}{path} did not answer: {error}") from error


def listening(url: str, timeout: float = 5.0) -> bool:
    """Whether something answers at the host of [url]."""
    host = url.split("://", 1)[-1].split("/", 1)[0].split(":")[0]
    port = int(url.split("://", 1)[-1].split("/", 1)[0].split(":")[1])
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


class AppConfig(Scenario):
    """The app's configuration for one profile, and the lab behind it."""

    name = "app-config"
    profiles = ("core",)

    def apply(self) -> None:
        chosen = profile()
        for instance in app_config.instances_for(chosen):
            if instance.away:
                faults_lab.ensure_away(instance.service)
        if chosen == "P8" and not gateway_lab.listening():
            gateway_lab.start(owner="app-config")
        if not edge_lab.listening(app_config.EDGE_PORT):
            edge_lab.up(app_config.EDGE_PORT, owner="app-config")
        app_config.write(chosen)

    def teardown(self) -> None:
        target = app_config.path_for(profile())
        if target.is_file():
            target.unlink()
        # Ownership is persisted, so a teardown in another CLI invocation
        # stops exactly what this scenario started and nothing else.
        gateway_lab.stop(owner="app-config")
        edge_lab.stop(app_config.EDGE_PORT, owner="app-config")

    def verify(self) -> None:
        chosen = profile()
        target = app_config.path_for(chosen)
        if not target.is_file():
            raise ScenarioError(f"the configuration was not written: {target}")
        mode = target.stat().st_mode & 0o777
        if mode != 0o600:
            raise ScenarioError(f"the configuration is readable by others: {mode:o}")

        document = json.loads(target.read_text(encoding="utf-8"))
        prefs = document.get("prefs", {})
        secure = document.get("secure", {})
        if not prefs:
            raise ScenarioError("the configuration holds no preferences")
        if not secure:
            raise ScenarioError("the configuration holds no secret")

        for connection in document.get("connections", []):
            self._verify_connection(chosen, document, connection)

    def verify_absent(self) -> None:
        target = app_config.path_for(profile())
        if target.is_file():
            raise ScenarioError("the configuration is still there")

    def _verify_connection(
        self,
        chosen: str,
        document: dict[str, Any],
        connection: dict[str, Any],
    ) -> None:
        """The address of one connection answers the lab, and so does away."""
        url = str(connection.get("url", ""))
        service = str(connection.get("service", ""))
        if not url:
            raise ScenarioError("a connection has no address")

        if chosen == "P8" and service in ("radarr", "sonarr", "seerr"):
            self._verify_gateway(url, connection)
        else:
            self._verify_url(document, connection, url)

        away = str(connection.get("away", "") or "")
        if away:
            # The away address is a listener of its own: publishing it in the
            # compose file is not proof that the host can reach it.
            self._verify_url(document, connection, away, away=True)

    def _verify_url(
        self,
        document: dict[str, Any],
        connection: dict[str, Any],
        url: str,
        *,
        away: bool = False,
    ) -> None:
        service = str(connection.get("service", ""))
        known = PROBES.get(service)
        if known is None:
            if not listening(url):
                raise ScenarioError(
                    f"{'away address ' if away else ''}{url} does not answer"
                )
            return

        path, kind = known
        secret = self._secret_of(document, connection)
        if kind == "key":
            status = probe(url, path, {"X-Api-Key": secret})
        elif kind == "bearer":
            status = probe(url, path, {"Authorization": f"Bearer {secret}"})
        elif kind == "query":
            status = probe(url, path.format(key=secret))
        else:
            status = probe(url, path)
        if status != 200:
            raise ScenarioError(
                f"{'away address ' if away else ''}{url}{path} answered {status}"
            )

    def _secret_of(
        self, document: dict[str, Any], connection: dict[str, Any]
    ) -> str:
        """The secret the configuration carries for one connection."""
        service = app_config.SERVICES[str(connection.get("service", ""))]
        key = f"secure_{connection.get('id')}_{service.suffix}"
        return str(document.get("secure", {}).get(key, ""))

    def _verify_gateway(self, url: str, connection: dict[str, Any]) -> None:
        """The gateway answers the way the profile says it answers."""
        headers = {
            "CF-Access-Client-Id": gateway_lab.TOKEN_ID,
            "CF-Access-Client-Secret": gateway_lab.TOKEN_SECRET,
        }
        if connection.get("access") == "cloudflare":
            status = probe(url, "", headers)
            if status not in (200, 403):
                raise ScenarioError(f"the gateway answered {status} at {url}")
            return
        # No token: the gateway answers with its own sign-in page.
        status = probe(url, "")
        if status != 302:
            raise ScenarioError(
                f"the gateway did not ask for a token: {status} at {url}"
            )


SCENARIO = AppConfig()
