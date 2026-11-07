"""The app's configuration for a profile, in the format the app reads.

The app keeps its configuration in two stores. `SharedPreferences` holds what
is not secret: the address of every connection, the name the person gave it,
the user id of a Jellyfin's viewer, the address away from home, the half of a
gateway's access that is not secret, the account a Seerr connection signs in
with, the roster of the connections and the preferences. The secure storage
holds what is: the API key, the password or the token of every connection, the
secret a gateway asks for, the session of a Seerr account and the map of the
trusted certificates. `SettingsService` writes one and reads the other, and
every key is derived from the id of the connection it belongs to.

This module writes that configuration for a profile of the lab into a file the
app-side writer hands to the app's own stores, key for key: nothing is
translated twice, and the app reads what the lab wrote. The file lives in the
lab's state directory with mode 600, beside the other disposable secrets, and
never in the repository.

The profiles are the ones of the world's catalogue
(`test/test_helpers/profiles/profiles.dart`), mapped onto what the lab serves:

* P1 the full household, P2 the requester, P3 the first day, P4 the arr stack
  without Seerr, P5 the arrs known only through Seerr, P6 two of a kind, P7
  the household away from home, P8 behind the gateway, P9 the household and a
  friend's Seerr, P10 the household's two media servers, Jellyfin and Emby,
  and the Tracearr that watches them.

Two of them need something the lab has to be told about:

* P7 reaches its servers at the address away from home: the second listener
  of the Toxiproxy, the port after the proxy's, which the `away-home`
  scenario switches off on command. The connections the world keeps at home
  keep only their address at home, so the app reads them as "only at home"
  while it is away.
* P8 reaches Radarr, Sonarr and Seerr at the lab's gateway: Radarr presents
  the service token the gateway admits, Sonarr presents none, and Seerr
  presents one no policy admits.

Two of the world's connections have no server of their own in the lab, and
the mapping says so rather than inventing one:

* the world's "Radarr 4K" is the lab's edge, the self-signed origin in front
  of Radarr (`edge_lab.py`), which is what the world's second Radarr is: a
  Radarr behind a certificate of its own;
* the world's "Sonarr Anime" is the lab's Sonarr under a second name, because
  the lab has one Sonarr and the app needs two instances of a service to
  exercise the lens.
"""

from __future__ import annotations

import contextlib
import http.cookiejar
import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import edge_lab
import gateway_lab
import testlab

STATE_ROOT = testlab.STATE_ROOT

#: Where the configuration of a profile is written: in the lab's state, with
#: the rest of the disposable secrets.
APP_DIR = STATE_ROOT / "app"

#: The bundle id of the testlab build of the app. Its own preferences and its
#: own keychain, so the app of the house is never touched.
BUNDLE_ID = "com.matthwlabs.cupola.testlab"

#: Matt's configured simulator holds the house's real connections. The seed
#: must never be launched on it, whatever the caller passes.
CONFIGURED_SIMULATOR_UDID = "3275916D-565E-4B49-89A3-D87227209A7F"

#: The only simulator the seed may use unless the environment names another
#: one explicitly. The name is the authorization: a UDID copied by mistake is
#: not enough.
TESTLAB_SIMULATOR_UDID = os.environ.get(
    "CUPOLA_TESTLAB_SIMULATOR_UDID", "403B5E0A-6A4E-4CB4-A151-87A6DA34E55F"
)

#: The testlab's own identity on Apple platforms.
TESTLAB_APP_GROUP = "group.com.matthwlabs.cupola.testlab"
TESTLAB_KEYCHAIN_SERVICE = "com.matthwlabs.cupola.testlab"
TESTLAB_KEYCHAIN_GROUP = "com.matthwlabs.cupola.testlab"

#: The gateway the lab plays on the host, and the edge in front of Radarr.
GATEWAY_PORT = int(os.environ.get("CUPOLA_TESTLAB_GATEWAY_PORT", "8466"))
EDGE_PORT = int(os.environ.get("CUPOLA_TESTLAB_EDGE_PORT", "8444"))

#: Sara's Seerr has no proxy of its own: it answers on its own port.
SARA_PORT = 5056

#: The key every service of the lab accepts, the ones the seed configured.
LAB_KEY = "test-key"


@dataclass(frozen=True)
class Service:
    """One service of the app's registry, as the storage keys need it.

    [key] is the name of the `ServiceKey` enum value, which is what the
    roster holds. [route] is the route param, and the id the first instance
    of the service takes: every storage key of that instance is the one the
    app used before it had more than one. [suffix] is the tail of the
    credential's storage key, which is not uniform: an arr files an
    `api_key`, qBittorrent a `password`, Plex a `token`.
    """

    key: str
    route: str
    suffix: str
    pair: bool = False
    viewer: bool = False


#: The app's registry, mirrored from `lib/features/settings/domain/
#: service_key.dart` and `lib/features/settings/data/settings_service.dart`.
SERVICES: dict[str, Service] = {
    "seerr": Service("seerr", "seerr", "api_key"),
    "radarr": Service("radarr", "radarr", "api_key"),
    "sonarr": Service("sonarr", "sonarr", "api_key"),
    "lidarr": Service("lidarr", "lidarr", "api_key"),
    "qbittorrent": Service("qbittorrent", "qbittorrent", "password", pair=True),
    "transmission": Service(
        "transmission", "transmission", "password", pair=True
    ),
    "bazarr": Service("bazarr", "bazarr", "api_key"),
    "truenas": Service("truenas", "truenas", "api_key"),
    "dockge": Service("dockge", "dockge", "password", pair=True),
    "prowlarr": Service("prowlarr", "prowlarr", "api_key"),
    "readarr": Service("readarr", "readarr", "api_key"),
    "sabnzbd": Service("sabnzbd", "sabnzbd", "api_key"),
    "nzbget": Service("nzbget", "nzbget", "password", pair=True),
    "unraid": Service("unraid", "unraid", "api_key"),
    "nginxProxyManager": Service(
        "nginxProxyManager", "npm", "password", pair=True
    ),
    "jellyfin": Service("jellyfin", "jellyfin", "api_key", viewer=True),
    "emby": Service("emby", "emby", "api_key", viewer=True),
    "plex": Service("plex", "plex", "token"),
    "tracearr": Service("tracearr", "tracearr", "api_key"),
}

#: The proxy in front of each service. The app talks to the proxy's port, so
#: a fault reaches the app; the direct port stays for the transport harness.
PROXY_OF = {"nginxProxyManager": "npm"}


@dataclass(frozen=True)
class Instance:
    """One connection of a profile, as the lab can serve it.

    [id] is the app's own id for the connection, the one every storage key
    is derived from. [address] says which of the lab's addresses the
    connection is reached at. [away] says whether it has an address away
    from home. [access] says what it presents to a gateway in front of it.
    """

    id: str
    service: str
    label: str = ""
    address: str = "proxy"
    away: bool = False
    access: str = ""


#: P1: the full household, twelve connections, all answering.
P1_INSTANCES: tuple[Instance, ...] = (
    Instance("seerr", "seerr"),
    Instance("jellyfin", "jellyfin"),
    Instance("radarr", "radarr"),
    Instance("radarr-4k00001", "radarr", label="4K", address="edge"),
    Instance("sonarr", "sonarr"),
    Instance("lidarr", "lidarr"),
    Instance("bazarr", "bazarr"),
    Instance("prowlarr", "prowlarr"),
    Instance("qbittorrent", "qbittorrent"),
    Instance("sabnzbd", "sabnzbd"),
    Instance("truenas", "truenas"),
    Instance("dockge", "dockge"),
)

#: The connections the world keeps at home while the phone is away.
HOME_ONLY = ("lidarr", "prowlarr", "sabnzbd", "truenas", "dockge")


def instances_for(profile: str) -> list[Instance]:
    """The connections of [profile], as the lab can serve them."""
    if profile == "P1":
        return list(P1_INSTANCES)
    if profile == "P2":
        # The requester: her Seerr, signed in with her own local account.
        return [Instance("seerr", "seerr")]
    if profile == "P3":
        return [
            Instance("radarr", "radarr"),
            Instance("sonarr", "sonarr"),
            Instance("seerr", "seerr"),
        ]
    if profile == "P4":
        return [
            Instance("radarr", "radarr"),
            Instance("sonarr", "sonarr"),
            Instance("lidarr", "lidarr"),
            Instance("prowlarr", "prowlarr"),
            Instance("qbittorrent", "qbittorrent"),
            Instance("transmission", "transmission"),
        ]
    if profile == "P5":
        return [
            Instance("seerr", "seerr"),
            Instance("jellyfin", "jellyfin"),
        ]
    if profile == "P6":
        # Two of a kind: a second Radarr behind the edge's certificate, a
        # second Sonarr under another name, Plex instead of Jellyfin.
        return [
            Instance("seerr", "seerr"),
            Instance("plex", "plex"),
            Instance("radarr", "radarr"),
            Instance("radarr-4k00001", "radarr", label="4K", address="edge"),
            Instance("sonarr", "sonarr"),
            Instance("sonarr-anime01", "sonarr", label="Anime"),
            Instance("bazarr", "bazarr"),
            Instance("qbittorrent", "qbittorrent"),
            Instance("sabnzbd", "sabnzbd"),
        ]
    if profile == "P7":
        # Away from home: every connection the world serves away carries the
        # second listener of its proxy as its address away.
        return [
            Instance(
                instance.id,
                instance.service,
                label=instance.label,
                address=instance.address,
                away=instance.service not in HOME_ONLY,
            )
            for instance in P1_INSTANCES
        ]
    if profile == "P8":
        # Behind the gateway: Radarr with the token the gateway admits, Sonarr
        # with none, Seerr with one no policy admits.
        return [
            Instance(
                "radarr",
                "radarr",
                address="gateway",
                access="cloudflare",
            ),
            Instance("sonarr", "sonarr", address="gateway"),
            Instance(
                "seerr",
                "seerr",
                address="gateway-refused",
                access="cloudflare",
            ),
            *[
                instance
                for instance in P1_INSTANCES
                if instance.service not in ("radarr", "sonarr", "seerr")
            ],
        ]
    if profile == "P10":
        # Two media servers side by side: Jellyfin and Emby on the same media,
        # each with a viewer of its own, which is what the Home's Now playing
        # and the lens over two servers are read against. Tracearr watches
        # both, so Now playing draws its streams in the same list and a title
        # says who watched it.
        return [
            Instance("seerr", "seerr"),
            Instance("jellyfin", "jellyfin"),
            Instance("emby", "emby"),
            Instance("tracearr", "tracearr"),
        ]
    if profile == "P9":
        # The household, plus Sara's Seerr, where the operator signs in with
        # an account of his own that may only request.
        return [
            *P1_INSTANCES,
            Instance("seerr-sara001", "seerr", label="Sara", address="sara"),
        ]
    raise testlab.LabError(
        f"unknown profile {profile!r}; choose one of "
        + ", ".join(sorted(PROFILES))
    )


#: The profiles the lab can configure, and what they are.
PROFILES: dict[str, str] = {
    "P1": "Full household",
    "P2": "Requester",
    "P3": "First day",
    "P4": "Arr stack without Seerr",
    "P5": "Arrs only through Seerr",
    "P6": "Two of a kind, Plex",
    "P7": "Full household, away from home",
    "P8": "Behind the gateway",
    "P9": "Full household and a friend's Seerr",
    "P10": "Jellyfin and Emby side by side, watched by Tracearr",
}


def proxy_port(service: str) -> int:
    """The host port of the proxy in front of [service]."""
    name = PROXY_OF.get(service, service)
    if name not in testlab.PROXIES:
        raise ValueError(f"the lab has no proxy for {service!r}")
    return testlab.PROXIES[name][2]


def away_port(service: str) -> int:
    """The host port of the address away from home of [service].

    The lab's convention: the listener right after the proxy's, on the same
    upstream. `faults_lab.away_port` says the same thing, and the `away-home`
    scenario switches it off.
    """
    return proxy_port(service) + 1


def address_of(instance: Instance) -> str:
    """The address [instance] is reached at, at home."""
    if instance.address == "edge":
        return f"https://127.0.0.1:{EDGE_PORT}"
    if instance.address == "sara":
        return f"http://127.0.0.1:{SARA_PORT}"
    if instance.address == "gateway":
        return f"http://127.0.0.1:{GATEWAY_PORT}/cf"
    if instance.address == "gateway-refused":
        return f"http://127.0.0.1:{GATEWAY_PORT}/cf-refused"
    if instance.service == "truenas":
        # TrueNAS speaks TLS even through the proxy, which only forwards the
        # bytes: the app's pin for that origin is the https one.
        return f"https://127.0.0.1:{proxy_port('truenas')}"
    return f"http://127.0.0.1:{proxy_port(instance.service)}"


def away_address_of(instance: Instance) -> str:
    """The address [instance] is reached at away from home, or ''."""
    if not instance.away:
        return ""
    if instance.address != "proxy":
        # The edge and Sara's Seerr answer on one address only.
        return ""
    return f"http://127.0.0.1:{away_port(instance.service)}"


def credential_of(service: Service) -> tuple[str, str]:
    """The credential of [service] in the lab: (secret, username).

    The secret half goes to the secure storage, the username beside the
    address. The arrs and the fixtures take the key the seed configured; the
    others take theirs from the credentials file, which the bootstrap fills
    with a new one on every run.
    """
    values = testlab.credentials()
    if service.key == "seerr":
        return values.get("CUPOLA_TESTLAB_SEERR_API_KEY", ""), ""
    if service.key == "jellyfin":
        return values.get("CUPOLA_TESTLAB_JELLYFIN_TOKEN", ""), ""
    if service.key == "emby":
        # An API key, which no user owns: the viewer below is what the app
        # reads the server as.
        return values.get("CUPOLA_TESTLAB_EMBY_TOKEN", ""), ""
    if service.key == "plex":
        return values.get("CUPOLA_TESTLAB_PLEX_TOKEN", ""), ""
    if service.key == "tracearr":
        # The public `trr_pub_` key. The owner's sign-in (for Acknowledge and
        # Dismiss) is a thing the person does in the app, not configuration.
        return values.get("CUPOLA_TESTLAB_TRACEARR_KEY", ""), ""
    if service.pair:
        prefix = {
            "qbittorrent": "CUPOLA_TESTLAB_QBITTORRENT",
            "transmission": "CUPOLA_TESTLAB_TRANSMISSION",
            "nzbget": "CUPOLA_TESTLAB_NZBGET",
            "dockge": "CUPOLA_TESTLAB_DOCKGE",
            "nginxProxyManager": "CUPOLA_TESTLAB_NPM",
        }[service.key]
        return (
            values.get(f"{prefix}_PASSWORD", ""),
            values.get(f"{prefix}_USERNAME", ""),
        )
    return LAB_KEY, ""


def viewer_of(service: Service) -> str:
    """The viewer of [service], for the services that have one.

    Jellyfin's token is a user's and names that user; Emby's key belongs to no
    one, so the administrator's id is what the app is told to read as.
    """
    if not service.viewer:
        return ""
    name = f"CUPOLA_TESTLAB_{service.key.upper()}_USER_ID"
    return testlab.credentials().get(name, "")


def sign_in(url: str, email: str, password: str) -> dict[str, Any]:
    """Sign in to the Seerr at [url] as [email], and answer the account.

    The app signs in the same way (`SeerrAuthService.signInWithEmail`) and
    keeps the session under `secure_<id>_session`. Signing in here means the
    configuration carries a session that is already signed in, so the app
    reads the connection as ready instead of asking the person to sign in
    again.

    Answers the session, the id and the permissions of the account, and the
    name the server knows it by.
    """
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar)
    )
    request = urllib.request.Request(
        f"{url}/api/v1/auth/local",
        data=json.dumps({"email": email, "password": password}).encode(),
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with opener.open(request, timeout=20) as response:
            response.read()
    except urllib.error.HTTPError as error:
        raise testlab.LabError(
            f"Seerr at {url} refused the sign-in of {email}: {error.code}"
        ) from error
    except urllib.error.URLError as error:
        raise testlab.LabError(f"Seerr at {url} did not answer: {error}") from error

    session = ""
    for cookie in jar:
        if cookie.name == "connect.sid":
            session = cookie.value
    if not session:
        raise testlab.LabError(f"Seerr at {url} signed in without a session")

    who = urllib.request.Request(
        f"{url}/api/v1/auth/me", headers={"Accept": "application/json"}
    )
    with opener.open(who, timeout=20) as response:
        me = json.loads(response.read().decode("utf-8"))
    return {
        "session": session,
        "userId": int(me.get("id", 0)),
        "permissions": int(me.get("permissions", 0)),
        "displayName": str(
            me.get("displayName") or me.get("username") or email
        ),
        "email": str(me.get("email") or email),
    }


def accounts_for(profile: str) -> dict[str, dict[str, Any]]:
    """The Seerr accounts [profile] signs in with, by connection id.

    P2 is Anna, the requester, on the household's Seerr. P9 is the operator,
    on Sara's Seerr, with an account of his own that may only request; the
    household's Seerr keeps the key he holds of it, because a connection is a
    key or an account, never both.
    """
    values = testlab.credentials()
    if profile == "P2":
        email = values.get("CUPOLA_TESTLAB_SEERR_REQUESTER_EMAIL", "")
        password = values.get("CUPOLA_TESTLAB_SEERR_REQUESTER_PASSWORD", "")
        if not email or not password:
            return {}
        who = sign_in(
            f"http://127.0.0.1:{proxy_port('seerr')}", email, password
        )
        return {"seerr": {"kind": "local", "login": email, **who}}
    if profile == "P9":
        state = STATE_ROOT / "seerr-sara.json"
        if not state.is_file():
            return {}
        operator = json.loads(state.read_text(encoding="utf-8")).get(
            "operator", {}
        )
        email = str(operator.get("email", ""))
        password = str(operator.get("password", ""))
        if not email or not password:
            return {}
        who = sign_in(f"http://127.0.0.1:{SARA_PORT}", email, password)
        return {"seerr-sara001": {"kind": "local", "login": email, **who}}
    return {}


def trusted_certificates(instances: list[Instance]) -> dict[str, str]:
    """The certificates the app is to trust, keyed by their origin.

    The TrueNAS fixture speaks TLS with a certificate of its own, and the
    edge does the same in front of Radarr. A pin belongs to the origin the
    app dials, which is the proxy's port, and the certificate behind it is
    the same one the direct port serves.
    """
    pins: dict[str, str] = {}
    fingerprint = testlab.credentials().get(
        "CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT", ""
    )
    if fingerprint and any(
        instance.service == "truenas" for instance in instances
    ):
        pins[f"https://127.0.0.1:{proxy_port('truenas')}"] = fingerprint
    if any(instance.address == "edge" for instance in instances):
        try:
            edge = edge_lab.fingerprint(EDGE_PORT)
        except (OSError, ValueError):
            edge = ""
        if edge:
            pins[f"https://127.0.0.1:{EDGE_PORT}"] = edge
    return pins


def build(profile: str) -> dict[str, Any]:
    """The app's configuration for [profile], in the app's own storage.

    Two maps, one per store the app reads: `prefs` for `SharedPreferences`
    and `secure` for the secure storage, with the keys `SettingsService`
    writes and the values it reads back.
    """
    instances = instances_for(profile)
    accounts = accounts_for(profile)
    prefs: dict[str, Any] = {}
    secure: dict[str, str] = {}
    roster: list[dict[str, str]] = []
    away: list[str] = []
    summary: list[dict[str, Any]] = []

    for instance in instances:
        service = SERVICES[instance.service]
        url = address_of(instance)
        prefs[f"{instance.id}_url"] = url
        roster.append(
            {"id": instance.id, "service": service.key, "label": instance.label}
        )

        secret, username = credential_of(service)
        if service.pair and username:
            prefs[f"{instance.id}_username"] = username
        viewer = viewer_of(service)
        if viewer:
            prefs[f"{instance.id}_user_id"] = viewer

        # A Seerr connection is a key or an account, never both.
        account = accounts.get(instance.id)
        if account is not None:
            prefs[f"{instance.id}_account"] = json.dumps(
                {
                    "kind": account["kind"],
                    "login": account["login"],
                    "userId": account["userId"],
                    "displayName": account["displayName"],
                    "permissions": account["permissions"],
                    "checkedAt": datetime.now(timezone.utc).isoformat(),
                }
            )
            secure[f"secure_{instance.id}_session"] = account["session"]
        elif secret:
            secure[f"secure_{instance.id}_{service.suffix}"] = secret

        if instance.access == "cloudflare":
            prefs[f"{instance.id}_access"] = json.dumps(
                {"kind": "cloudflare", "clientId": gateway_lab.TOKEN_ID}
            )
            secure[f"secure_{instance.id}_access_secret"] = (
                gateway_lab.TOKEN_SECRET
            )

        away_url = away_address_of(instance)
        if away_url:
            prefs[f"{instance.id}_away_url"] = away_url
            away.append(instance.id)

        summary.append(
            {
                "id": instance.id,
                "service": service.key,
                "label": instance.label,
                "url": url,
                "away": away_url,
                "access": instance.access or "none",
                "credential": "account"
                if account is not None
                else ("yes" if secret else "no"),
            }
        )

    prefs["service_instances"] = json.dumps(roster)
    if away:
        prefs["connection_routes"] = json.dumps(sorted(away))
    prefs["region"] = "IT"
    prefs["theme_mode"] = "dark"
    prefs["onboarding_complete"] = True
    prefs["plex_client_id"] = "cupola-testlab-plex-client"

    pins = trusted_certificates(instances)
    if pins:
        secure["secure_trusted_certificates"] = json.dumps(pins)

    return {
        "profile": profile,
        "title": PROFILES.get(profile, profile),
        "bundleId": BUNDLE_ID,
        "writtenAt": datetime.now(timezone.utc).isoformat(),
        "stores": {
            "prefs": "SharedPreferences",
            "secure": "flutter_secure_storage",
        },
        "prefs": prefs,
        "secure": secure,
        "connections": summary,
    }


def path_for(profile: str) -> Path:
    """Where the configuration of [profile] is written."""
    return APP_DIR / f"{profile}.json"


def write(profile: str) -> Path:
    """Write the configuration of [profile] and answer the file."""
    document = build(profile)
    target = path_for(profile)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    # The file holds the keys of the lab: nobody else may read it.
    target.chmod(0o600)
    return target


def read(profile: str) -> dict[str, Any]:
    """The configuration of [profile] as it was written."""
    target = path_for(profile)
    if not target.is_file():
        raise ValueError(f"{profile} has no configuration: {target} is missing")
    return json.loads(target.read_text(encoding="utf-8"))


def summary(profile: str) -> dict[str, Any]:
    """What the configuration of [profile] holds, without a single secret."""
    document = read(profile)
    return {
        "profile": document.get("profile", profile),
        "title": document.get("title", ""),
        "file": str(path_for(profile)),
        "bundleId": document.get("bundleId", BUNDLE_ID),
        "connections": document.get("connections", []),
        "prefs": sorted(document.get("prefs", {})),
        "secure": sorted(document.get("secure", {})),
    }


#: The entry point that hands the configuration to the app's own stores.
SEED_ENTRY_POINT = "integration_test/testlab/seed_app.dart"


def authorised_simulator(udid: str | None) -> str:
    """The simulator the seed may use, or a refusal before anything runs.

    The house's simulator is refused by UDID even if someone names it. Any
    other device must be the one the environment authorises, must exist in
    ``simctl``'s list, and must be a simulator. A booted personal device or an
    unknown UDID never receives the seed.
    """
    if not udid:
        raise testlab.LabError(
            "the simulator needs its udid: --udid <the testlab simulator>"
        )
    if udid == CONFIGURED_SIMULATOR_UDID:
        raise testlab.LabError(
            "refusing the configured Cupola simulator: it holds the house's "
            "connections. Use the dedicated Cupola Testlab simulator."
        )
    if udid != TESTLAB_SIMULATOR_UDID:
        raise testlab.LabError(
            f"refusing unauthorised simulator {udid}; the testlab simulator is "
            f"{TESTLAB_SIMULATOR_UDID} (override with "
            "CUPOLA_TESTLAB_SIMULATOR_UDID)"
        )
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "-j"],
        cwd=testlab.REPO_ROOT,
        text=True,
        capture_output=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise testlab.LabError(
            "simctl could not list the simulators: "
            + (result.stderr or result.stdout).strip()[-1000:]
        )
    try:
        payload = json.loads(result.stdout)
    except ValueError as error:
        raise testlab.LabError("simctl did not answer JSON") from error
    found = {
        device.get("udid"): (runtime, device)
        for runtime, devices in payload.get("devices", {}).items()
        for device in devices
    }
    if udid not in found:
        raise testlab.LabError(f"simulator {udid} does not exist")
    runtime, device = found[udid]
    if device.get("isAvailable") is False:
        raise testlab.LabError(f"simulator {udid} is not available ({runtime})")
    return str(device.get("name") or udid)


#: The Flutter the seed runs with. It must know ``--no-uninstall``: without it
#: an integration test removes the app, and its container with the seeded
#: stores, as soon as it ends (Flutter 3.38.7 does exactly that on iOS).
TESTLAB_FLUTTER = os.environ.get("CUPOLA_TESTLAB_FLUTTER", "flutter")


def keeps_app_installed(flutter: str = TESTLAB_FLUTTER) -> bool:
    """Whether ``flutter test`` can leave the seeded app installed."""
    result = subprocess.run(
        [flutter, "test", "-h"],
        cwd=testlab.REPO_ROOT,
        text=True,
        capture_output=True,
        timeout=120,
    )
    return "--[no-]uninstall" in (result.stdout or "")


#: What a newer Flutter rewrites on its own when it builds the seed: the Swift
#: Package Manager migration, the lockfile it resolves and the files it
#: "upgrades". The project's gate is another Flutter, so none of it may stay.
GENERATED_TRACKED = (
    "analysis_options.yaml",
    "pubspec.lock",
    "ios/Flutter/AppFrameworkInfo.plist",
    "ios/Podfile",
    "ios/Podfile.lock",
    "ios/Runner.xcodeproj/project.pbxproj",
    "ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme",
    "macos/Podfile",
    "macos/Podfile.lock",
    "macos/Runner.xcodeproj/project.pbxproj",
    "macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme",
)
GENERATED_UNTRACKED = (
    "ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm",
    "ios/Runner.xcworkspace/xcshareddata/swiftpm",
    "macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm",
    "macos/Runner.xcworkspace/xcshareddata/swiftpm",
)


def _dirty(paths: tuple[str, ...]) -> set[str]:
    result = subprocess.run(
        ["git", "status", "--porcelain", "--", *paths],
        cwd=testlab.REPO_ROOT,
        text=True,
        capture_output=True,
        timeout=60,
    )
    return {line[3:].strip() for line in result.stdout.splitlines() if line}


@contextlib.contextmanager
def _keeping_generated_files():
    """Undo what the seed's build generated, and only that.

    A file already changed before the seed is someone's work and is left
    alone; a file that was clean, or a folder that did not exist, is put back.
    """
    before = _dirty(GENERATED_TRACKED)
    absent = [
        path for path in GENERATED_UNTRACKED if not (testlab.REPO_ROOT / path).exists()
    ]
    try:
        yield
    finally:
        changed = sorted(_dirty(GENERATED_TRACKED) - before)
        if changed:
            subprocess.run(
                ["git", "checkout", "--", *changed],
                cwd=testlab.REPO_ROOT,
                check=True,
                timeout=60,
            )
        for path in absent:
            shutil.rmtree(testlab.REPO_ROOT / path, ignore_errors=True)


def _run_seed(
    device: str,
    profile: str,
    entitlements: str,
    environment: dict[str, str],
) -> str:
    values = testlab.credentials()
    control_url = values.get("CUPOLA_TESTLAB_CONTROL_URL", "")
    control_token = values.get("CUPOLA_TESTLAB_CONTROL_TOKEN", "")
    if not control_url or not control_token:
        raise testlab.LabError(
            "the control API is not configured: run bootstrap.sh so that "
            "credentials.env carries its URL and token"
        )
    # The build settings are read by Flutter and passed to xcodebuild. They
    # make the .app a different identity, not a renamed preference domain.
    environment.update(
        {
            "FLUTTER_XCODE_CUPOLA_BUNDLE_SUFFIX": ".testlab",
            "FLUTTER_XCODE_CUPOLA_APP_GROUP": TESTLAB_APP_GROUP,
            "FLUTTER_XCODE_CUPOLA_ENTITLEMENTS": entitlements,
        }
    )
    if device == "macos":
        # No provisioning profile exists for a bundle id Apple has never seen,
        # and a sandboxed build cannot be signed without one. The testlab Mac
        # app is therefore not sandboxed: its isolation is the bundle id, the
        # preferences file and the Keychain service, not a container.
        environment["FLUTTER_XCODE_ENABLE_APP_SANDBOX"] = "NO"
    keeps = keeps_app_installed()
    if not keeps and device != "macos":
        raise testlab.LabError(
            f"{TESTLAB_FLUTTER} has no --no-uninstall: it would remove the "
            "seeded app from the simulator as soon as the seed ends. Point "
            "CUPOLA_TESTLAB_FLUTTER at a Flutter that has it."
        )
    command = [
        TESTLAB_FLUTTER,
        "test",
        SEED_ENTRY_POINT,
        "-d",
        device,
        "--tags",
        "e2e",
        "--run-skipped",
        *(["--no-uninstall"] if keeps else []),
        f"--dart-define=CUPOLA_TESTLAB=1",
        f"--dart-define=CUPOLA_TESTLAB_PROFILE={profile}",
        f"--dart-define=CUPOLA_TESTLAB_CONTROL_URL={control_url}",
        f"--dart-define=CUPOLA_TESTLAB_CONTROL_TOKEN={control_token}",
        f"--dart-define=CUPOLA_TESTLAB_KEYCHAIN_SERVICE={TESTLAB_KEYCHAIN_SERVICE}",
        # A macOS Keychain access group needs a provisioning profile, which a
        # testlab bundle cannot get. The bundle id and the service name already
        # give the app a Keychain of its own; the group stays empty here.
        "--dart-define=CUPOLA_TESTLAB_KEYCHAIN_GROUP="
        if device == "macos"
        else f"--dart-define=CUPOLA_TESTLAB_KEYCHAIN_GROUP={TESTLAB_KEYCHAIN_GROUP}",
        f"--dart-define=CUPOLA_TESTLAB_APP_GROUP={TESTLAB_APP_GROUP}",
    ]
    with _keeping_generated_files():
        result = subprocess.run(
            command,
            cwd=testlab.REPO_ROOT,
            env=environment,
            text=True,
            capture_output=True,
            timeout=1800,
        )
    output = (result.stdout or "") + (result.stderr or "")
    marker = f"[testlab] applied profile={profile} bundle={BUNDLE_ID}"
    if result.returncode != 0:
        raise testlab.LabError(
            "the app did not apply the profile: its process failed with "
            f"exit {result.returncode}. {output[-3000:]}"
        )
    if marker not in output:
        raise testlab.LabError(
            "the app exited zero but never confirmed the readback: "
            f"{marker!r} is missing. {output[-3000:]}"
        )
    return output


def apply_to_target(
    target: str, profile: str, udid: str | None = None
) -> dict[str, Any]:
    """Configure the app on [target] with the configuration of [profile].

    The app reads the configuration in its own process, because the secure
    storage is the app's own keychain and nothing outside the app can write
    it. The entry point is `integration_test/testlab/seed_app.dart`, run on
    the device or in the simulator with the testlab build settings; it
    replaces the stores and reads them back. The command fails if the app
    failed, and a profile is never reported as applied without the app's own
    readback marker.
    """
    if profile not in PROFILES:
        raise testlab.LabError(f"unknown profile {profile!r}")
    document = read(profile)
    if document.get("bundleId") != BUNDLE_ID:
        raise testlab.LabError(
            f"{profile} was written for {document.get('bundleId')!r}, not "
            f"{BUNDLE_ID}"
        )

    if target == "macos":
        device = "macos"
        entitlements = "Runner/Testlab.entitlements"
        container = None
        preferences = Path.home() / "Library/Preferences" / f"{BUNDLE_ID}.plist"
    elif target == "ios-simulator":
        authorised_simulator(udid)
        device = str(udid)
        entitlements = "Runner/RunnerTestlab.entitlements"
        container = None
        preferences = None
    else:
        raise testlab.LabError(f"unknown target {target!r}")

    output = _run_seed(device, profile, entitlements, os.environ.copy())
    if target == "macos":
        # The testlab Mac build is not sandboxed (it cannot get a provisioning
        # profile for a bundle id Apple has never seen), so the destination it
        # proves is the preferences file named by its own bundle id.
        if preferences is None or not preferences.is_file():
            raise testlab.LabError(
                f"the seed ran but the testlab preferences are missing: "
                f"{preferences}"
            )
        container = preferences.parent
    elif target == "ios-simulator":
        # `--no-uninstall` keeps the app (and its container) on the simulator:
        # this is the app the next launch will actually read, not a test runner
        # that wrote and vanished.
        result = subprocess.run(
            ["xcrun", "simctl", "get_app_container", device, BUNDLE_ID, "data"],
            cwd=testlab.REPO_ROOT,
            text=True,
            capture_output=True,
            timeout=60,
        )
        if result.returncode != 0:
            raise testlab.LabError(
                f"the seed ran but {BUNDLE_ID} is not installed in its own "
                f"container: {(result.stderr or result.stdout).strip()}"
            )
        container = Path(result.stdout.strip())
    if container is None or not container.is_dir():
        raise testlab.LabError(
            f"the seed ran but the testlab container is missing: {container}"
        )
    return {
        "target": target,
        "device": device,
        "profile": profile,
        "bundleId": BUNDLE_ID,
        "container": str(container),
        "preferences": str(preferences) if preferences is not None else None,
        "entryPoint": SEED_ENTRY_POINT,
        "applied": True,
        "output": output[-4000:],
    }
