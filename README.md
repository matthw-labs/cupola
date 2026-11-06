<div align="center">

<img src="assets/brand/cupola_mark.png" width="112" alt="Cupola" />

# Cupola

**A Cupola over your server.**

One native app for your entire self-hosted media stack, and the box it runs on.<br/>
**18 services. iOS, Android, macOS. No cloud, no account, no middleman.**<br/>
[**Install**](#install) · [Supported services](#supported-services) · [Security & privacy](#security--privacy)

[![CI](https://github.com/matthw-labs/cupola/actions/workflows/ci.yml/badge.svg)](https://github.com/matthw-labs/cupola/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/matthw-labs/cupola?include_prereleases&label=release)](https://github.com/matthw-labs/cupola/releases)
![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20Android%20%7C%20macOS-informational)
![Flutter](https://img.shields.io/badge/Flutter-3.47.7-02569B?logo=flutter&logoColor=white)
[![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)
[![Ko-fi](https://img.shields.io/badge/support-Ko--fi-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/matthwlabs)

<br/>

<img src="screenshots/home.png" width="240" alt="Home: what you were watching, what is new on your server and what is coming up" />
<img src="screenshots/trending.png" width="240" alt="Discover: what is trending this week" />
<img src="screenshots/title.png" width="240" alt="A movie's page, with its ratings and the button that adds it to Radarr" />

</div>

---

## Why Cupola

Running a media stack means running a dozen web UIs. On a phone, most of them are
unusable, and none of them know about each other. Cupola is one app that knows
about all of them.

- **The whole stack.** Seerr, the *arr family, four download clients,
  two media servers, and the infrastructure underneath: TrueNAS, Unraid, Dockge,
  Nginx Proxy Manager, each with its own screens.
- **No Cupola server.** No relay, no sign-up, and no telemetry of ours. The app
  speaks directly to the hosts you own, and credentials live in the device keychain.
  Two exceptions, explained under [Security & privacy](#security--privacy):
  background search hands a request to the OS, API key included, so it ships off;
  and on Android the code scanner is Google's, which reports usage to Google.
- **Built for home labs.** Self-signed certificates, services behind a reverse
  proxy, boxes that are asleep or out of reach: Cupola handles them as everyday
  states.
- **It tells you what needs you.** A stuck download, a disk with errors, an
  indexer that stopped watching for releases: Cupola says what happened and puts
  the fix on the same card.
- **Phone first.** Designed for the phone, then the tablet and the desktop window,
  with the same design on every platform.

## Contents

- [Screenshots](#screenshots)
- [Install](#install)
- [Supported services](#supported-services)
- [Features](#features)
- [Configuration](#configuration)
- [Security & privacy](#security--privacy)
- [Build from source](#build-from-source)
- [Architecture](#architecture)
- [Project status](#project-status)
- [Contributing](#contributing)
- [FAQ](#faq)
- [About this project](#about-this-project)
- [Support](#support)
- [License](#license)

---

## Screenshots

<table>
  <tr>
    <td align="center" width="33%"><img src="screenshots/home.png" alt="Home" /><br/><sub><b>Home</b> · what you were watching, what is new, what is next</sub></td>
    <td align="center" width="33%"><img src="screenshots/discover.png" alt="Discover" /><br/><sub><b>Discover</b> · calendar, trending, every way in</sub></td>
    <td align="center" width="33%"><img src="screenshots/title.png" alt="A movie's page" /><br/><sub><b>A title</b> · one page to decide and act</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/activity.png" alt="Activity" /><br/><sub><b>Activity</b> · everyone's requests, and where they stand</sub></td>
    <td align="center"><img src="screenshots/stack.png" alt="Stack" /><br/><sub><b>Stack</b> · every service at a glance</sub></td>
    <td align="center"><img src="screenshots/sonarr.png" alt="Sonarr" /><br/><sub><b>Sonarr</b> · each service with its own tabs</sub></td>
  </tr>
</table>

<details>
<summary><b>More screenshots</b>: light theme, trending</summary>
<br/>
<table>
  <tr>
    <td align="center" width="33%"><img src="screenshots/home_light.png" alt="Home, light" /><br/><sub>Home · light</sub></td>
    <td align="center" width="33%"><img src="screenshots/discover_light.png" alt="Discover, light" /><br/><sub>Discover · light</sub></td>
    <td align="center" width="33%"><img src="screenshots/trending.png" alt="Trending" /><br/><sub>Discover · trending this week</sub></td>
  </tr>
</table>
</details>

<p align="center"><img src="screenshots/desktop.png" alt="Discover on macOS, with the navigation rail and the Activity inspector" /><br/><sub><b>On the desktop</b> · the same app, with a navigation rail, a command palette and an inspector</sub></p>

---

## Install

> **Just want to use it?** iPhone and iPad install through TestFlight (or a sideloaded
> `.ipa`); Android and macOS download from
> [**Releases**](https://github.com/matthw-labs/cupola/releases).
> No toolchain needed. The App Store and Google Play come later.

> **No server at hand?** On the first screen, **Explore a demo home** opens an invented
> household with all eighteen services. It runs entirely inside the app: nothing is
> saved and nothing goes out to the network. **Settings → Leave demo** takes you back.

| Platform | Status | Get it |
| --- | --- | --- |
| **iOS / iPadOS** | Supported, iOS 17+ | [TestFlight](https://testflight.apple.com/join/tqmwnCMj), or an unsigned `.ipa` from Releases |
| **Android** | Supported, Android 7.0+ | `.apk` from Releases, or Obtainium |
| **macOS** | Supported, Apple silicon, macOS 12+ | `.dmg` from Releases |
| Windows / Linux | Built by CI, untested | `.zip` / `.tar.gz` from Releases |
| Web | Not a goal | none |

> **Coming from Seekarr?** Cupola 1.0 is a **new app**, not an update. It installs
> beside Seekarr and starts empty: add your services again (same URLs, same API keys),
> check that they answer, then uninstall Seekarr. In Obtainium, the Seekarr entry may
> offer Cupola and then refuse it, because the app ID changed: remove that entry and add
> Cupola as a new app. Releases before 1.0.0 were published as Seekarr and cover fewer
> services than this page describes.

<details>
<summary><b>iOS and iPadOS</b></summary>
<br/>

Open the [TestFlight link](https://testflight.apple.com/join/tqmwnCMj) on your iPhone or iPad, install Apple's
TestFlight app when it asks, then tap **Install**. TestFlight brings each new version
on its own. The public link has a limited number of places: if it says the beta is
full, try again after the next release.

To sideload instead, download `cupola-<version>.ipa` from Releases and install it with
AltStore, SideStore or Sideloadly. The file is unsigned: your tool signs it with your
own Apple ID. With a free Apple ID the install lasts 7 days and has to be refreshed,
and the widgets may stay empty, because they share data through an App Group that a
re-signed copy may not get. TestFlight is the way we recommend.

</details>

<details>
<summary><b>Android</b></summary>
<br/>

Download `cupola-<version>.apk` from Releases and install it. You may need to allow
installs from unknown sources for your browser or file manager. One file covers every
device.

To get updates without checking this page, add this repository's URL to
[**Obtainium**](https://obtainium.imranr.dev/): it installs the `.apk` from each new
release.

</details>

<details>
<summary><b>macOS</b></summary>
<br/>

Download the `.dmg`, drag **Cupola** to `/Applications`, and launch it. The 1.0 build
runs on Apple silicon Macs only. The app is signed with a Developer ID and notarized
by Apple, so it opens like any other.

</details>

<details>
<summary><b>Windows, Linux</b></summary>
<br/>

Both have a real runner with the desktop window. Each release carries a build made by
GitHub Actions: on Windows unzip it and run `cupola.exe` (the build is not signed, so
SmartScreen asks once); on Linux untar it and run `cupola` (it needs GTK 3 and
libsecret, present on most desktops). We have not run either ourselves, so a report
either way helps.

</details>

---

## Supported services

Configure only what you run: a service you have not set up stays out of the way.

Two columns say how far each integration goes:

- **Control.** How far Cupola goes today: full read *and* write, or mostly reading.
- **Tested.** Whether the integration has been exercised against a **real, running
  instance**. Every service also has unit tests, which is a separate thing. We fill
  this column in conservatively:
  **✅ verified** end to end · **◐ partial**, where the screens have read a real
  instance (or a faithful stand-in) but its actions have not been run against one ·
  **○ untested**, written to the official API but never run against a live
  instance. If you run one of the services we could not test, please tell us how it
  goes, whether it works or not.

### Media

| Service | What Cupola does | Auth | Control | Tested |
| --- | --- | --- | --- | :-: |
| **Seerr** (Overseerr / Jellyseerr) | Powers Discover: trending, calendar, genres, networks, studios, people, collections. Send, approve and decline requests, resolve issues, keep a watchlist. Household members sign in with their own account | API key, or a member's own sign-in (email, Jellyfin, Emby or Plex) | Read + write | ✅ |
| **Radarr** | Full movie library, calendar, queue, wanted and history; auto and interactive search, monitoring, quality profiles, manual import, delete | API key | Read + write | ✅ |
| **Sonarr** | Everything Radarr does, plus seasons and episodes with per-season / per-episode search | API key | Read + write | ✅ |
| **Lidarr** | Everything Radarr does, plus an artist's page with every album and where it stands | API key | Read + write | ✅ |
| **Bazarr** | Subtitle library, wanted episodes and movies, history, providers (and resetting their throttles) | API key | Mostly read | ◐ |
| **Readarr** | Author pages with every book and where it stands; search, monitor and delete. Adding authors is left out: Readarr is retired and its metadata service no longer answers | API key | Manage | ◐ |

### Downloads

| Service | What Cupola does | Auth | Control | Tested |
| --- | --- | --- | --- | :-: |
| **qBittorrent** | Live queue with filters, sorting and search; per-torrent Info / Files / Trackers / Actions; pause, resume, force-start, recheck, reannounce, per-torrent speed limits, the alternative speed switch, categories, tags, delete | User + password | Read + write | ✅ |
| **Transmission** | Live queue, labels and session settings; start, stop, verify, reannounce, reorder, add, delete, Slow mode | User + password | Read + write | ✅ |
| **Prowlarr** | Indexer overview and usage stats; add, edit, test, delete and bulk-manage indexers; push to connected apps; tags and app profiles | API key | Read + write | ✅ |
| **SABnzbd** | Live queue, history and servers; pause and resume one job or everything, add by URL, delete | API key | Read + write | ✅ |
| **NZBGet** | Live queue, history, feeds and messages; pause and resume, add, delete | User + password | Read + write | ✅ |

### Stream

| Service | What Cupola does | Auth | Control | Tested |
| --- | --- | --- | --- | :-: |
| **Jellyfin** | Who is watching right now, transcode reasons, resume points, libraries, users, devices and tasks; pause, stop or message a session | API key + viewer | Read + sessions | ✅ |
| **Plex** | The same session-first board, driven by Plex's own semantics: libraries, on deck, devices, playlists; stop a session | Token | Read + stop | ◐ |
| **Emby** | The same session-first board as Jellyfin, from Emby's own API: who is watching right now, resume points, libraries, users, devices and tasks; pause, stop or message a session | API key + viewer | Read + sessions | ○ ² |

² Emby is new: its client is written against answers recorded from a real Emby 4.10
server, and we have not yet run the app against one.

### Infrastructure

| Service | What Cupola does | Auth | Control | Tested |
| --- | --- | --- | --- | :-: |
| **TrueNAS** | Full console: dashboard, pools and disks, datasets and snapshots, SMB/NFS shares, apps, virtualization, replication and periodic tasks, reporting, users and groups; a disk with errors offers the scrub that repairs it | API key | Read + write | ◐ |
| **Dockge** | Compose stacks with live terminal output: start, stop, restart, update, down, and edit or deploy the compose file itself | User + password | Read + write | ✅ |
| **Unraid** | Array status, disks, shares, Docker containers, VMs and notifications; start and stop VMs, archive notifications | API key | Read + VMs | ○ ¹ |
| **Nginx Proxy Manager** | What the box is fronting, what is broken, which certificates are about to lapse; enable/disable hosts, renew a certificate | Email + password | Read + write | ◐ |

¹ Unraid is a whole operating system and we do not run it, so its integration is
tested only against recorded answers from its API.

---

## Features

<details open>
<summary><b>Home: the evening at a glance</b></summary>
<br/>

What arrived on your server, what airs or comes out next, what you were halfway
through, and what needs you, on one page. Home is made of modules: keep the ones you
want, in the order you want, and leave the rest out.

</details>

<details>
<summary><b>Discover: find something to watch</b></summary>
<br/>

Trending this week, a calendar of what is coming, and every way in: genres, networks,
studios, people, decades, moods and languages, plus the collections you have only
part of. Type once and Seerr, Radarr, Sonarr, Jellyfin, Plex and Emby answer side by side,
so "do I already have this?" takes one search.

Tap a poster and one page tells you the ratings, who is in it, where it stands on
your server, and opens the trailer. Then act from that same page: add it to your
library, send a request, pick a specific release yourself, or clear out something you
no longer want.

</details>

<details>
<summary><b>Activity: what went wrong, and how to fix it</b></summary>
<br/>

*Needs you* gathers what the stack cannot fix by itself: a download stuck for days,
imports waiting for a decision, a disk reporting errors, an indexer that stopped
watching for new releases. Each one says what happened, keeps the service's raw
message one tap away, and offers the fix first: try another download, look for peers
again, review the import, scrub the pool.

Downloads from all four clients sit in one list, moving first and stuck next. Open
one to stop or resume it; on the desktop the table does it from the row. Requests and
history are a tab away.

</details>

<details>
<summary><b>Stack: every service, with its own tabs</b></summary>
<br/>

The Stack shows the whole lab in bands (media, downloads, streaming, the box itself)
and says which services are clean and which need a look. Each service opens on its
own Overview, with its own tabs: Radarr's library, calendar, queue and wanted list;
qBittorrent's queue with filters, sorting, categories and tags;
TrueNAS's full console.

- Grab something automatically, or open the release list and choose it yourself
- Flip monitoring, change quality profile, import files that landed in the wrong place
- Delete, choosing whether the files go too and whether it may be added again

</details>

<details>
<summary><b>Outside the app: widgets and notifications</b></summary>
<br/>

Home-screen widgets on iOS and Android: *Coming up* and *Downloads* for whoever runs
the stack (Downloads also on the iPhone lock screen), *Requests* for a household
member. Two notifications, both off until you turn them on in **Settings →
Notifications**: *Needs you*, when something on the stack turns into a fault, and
*Ready to watch*, when something you asked for arrives. The phone works them out
itself, in the background, against your own services: there is no push server.
How often that background run happens is up to the operating system.

</details>

<details>
<summary><b>At home and away</b></summary>
<br/>

A connection can carry two addresses: the one it has at home and the one it has
away from it (a reverse proxy, a tunnel, a VPN name). Cupola knocks on both and uses
whichever answers, so the same app works on the sofa and on the train. A service that
only exists at home says so and shows the last thing it knew.

Setting up a second phone takes one code: **Settings → Security → Set up another
device** copies every connection across, encrypted, over your own Wi-Fi. To bring in
someone from the household, **Invite someone** from Seerr gives them a link or a QR
code that carries the server's address, never its API key.

</details>

<details>
<summary><b>For the whole household</b></summary>
<br/>

Not everyone at home runs the stack. A household member signs in to Seerr with their
own account (email, Jellyfin, Emby or Plex) and gets a simpler Cupola: Home, Discover and
their requests, without the operator controls. Cupola never shows them a button
the server would refuse.

</details>

<details>
<summary><b>Design and accessibility</b></summary>
<br/>

Cupola is a native app, with no web view inside.

- A black-and-white interface where colour carries meaning: green is done, amber is
  a fault, red is unreachable, blue is waiting
- Light and dark themes, each designed on its own
- Empty, failed and unconfigured screens explain what to do next
- Text follows the system font size, up to the largest settings, without clipping
- VoiceOver and TalkBack read each row as one sentence
- Touch targets of at least 44 points
- Designed for the phone first. On a tablet a title opens beside the list it came
  from; on the desktop the window gets a navigation rail, a command palette and an
  inspector

</details>

<details>
<summary><b>Searches that keep going in the background</b></summary>
<br/>

Interactive search is slow because your indexers are slow. Tap *Keep searching*, put the
phone away, and the answer is waiting in Activity when you come back.

On a phone that means the operating system runs the request for you, and to do that it
writes the request down, API key included, until the search ends. Any app that searches
in the background has to do this. So it ships **off**, and the switch in
**Settings → Background search** explains the same trade-off. Cupola keeps the window
narrow: a task expires after 11 minutes, finished records
are cleared at every launch and the moment you switch the feature off, and on Android none
of it is in a backup. On iOS one copy can ride along in a device backup: encrypt the
backup, or use iCloud with Advanced Data Protection, and it is covered.

On desktop the question never arises. Nothing suspends the app, so a search just keeps
running while Cupola is open.

</details>

---

## Configuration

Cupola ships with no default credentials and no bundled endpoints. Open
**Settings → Connections** and add the services you run. Each one needs a
base URL plus whatever it authenticates with (see the
[services tables](#supported-services)).

Good to know:

- **A guided first run.** On first launch Cupola helps you set up one service, then
  offers the ones your Seerr or Prowlarr already knows about.
- **Everything is optional.** Configure one service or all eighteen. Unconfigured
  services show a placeholder and never block a screen.
- **More than one of each.** Two Radarrs (say, one for 4K) are two connections; the
  app shows them together and lets you look at one at a time.
- **Behind a gateway.** A connection can carry what a gateway in front of the service
  asks for: a Cloudflare Access service token, a proxy password, or custom headers.
  Cupola recognises a gateway's sign-in page instead of reading it as an empty answer.
- **Household members** sign in to Seerr with their own account instead of the API
  key, and get the household version of the app (see [Features](#features)).
- **Test before you save.** Each connection can be checked in place, and a failure
  names its reason: wrong key, wrong host, TLS refused.
- **Jellyfin needs a viewer.** A Jellyfin API key authenticates as an administrator
  with no user attached, so the settings screen asks which user's perspective to
  use once the connection succeeds. Plex needs no equivalent: its token *is* its
  user.
- **Nginx Proxy Manager has no API key.** NPM only accepts the account email and
  password, which it exchanges for a short-lived token.
- **Region preference** shapes watch providers and content ratings where the
  upstream API is region-aware.

---

## Security & privacy

Cupola has no server of its own, so it has nowhere to send your data.

- **No account, no cloud, no telemetry of ours.** We collect nothing.
- **Two third parties, each for one thing.** Poster, backdrop and cast artwork is
  fetched straight from TMDB's CDN (`image.tmdb.org`), because that is where your
  Seerr's metadata points. Those requests carry no credential and no identifier of
  yours, but they are requests to a host that is not yours, and TMDB sees the IP
  they come from. Signing in to Seerr with a Plex account goes through plex.tv's
  own sign-in, once, and Cupola keeps none of the token it gets. Everything else,
  metadata included, comes from your own instances. A link you tap (a trailer, a
  rating) opens in its own app or in the browser, outside Cupola.
- **On Android, a third: the code scanner reports to Google.** To read the code in
  *Copy from another device*, Cupola for Android uses Google's ML Kit, which sends
  Google diagnostic and usage data: the device model and Android version, the app's
  name and version, an identifier for this installation, and how the scanner ran
  (speed, image settings, errors). Google offers no way to turn it off, so we plan
  to replace it with a scanner that sends nothing. On iPhone and iPad the scanner is
  Apple's and runs on the device; on a Mac you paste a link instead.
- **Secrets stay on the device.** API keys, tokens and passwords go into
  `flutter_secure_storage`: Keychain on Apple platforms, Keystore-backed on
  Android. Plaintext settings from older versions are migrated on first launch.
- **Self-signed certificates, pinned.** Trust-on-first-use with SHA-256
  fingerprint pinning, scoped to the **TLS origin** (host and port), because
  a certificate belongs to the host, whichever service you reach through it. Two services behind the same reverse proxy are therefore trusted, and
  revoked, together. Review or forget any of them under
  **Settings → Security → Trusted certificates**.
- **Pinning covers images too.** Posters and artwork use a separate HTTP stack, so
  they go through a pinned image cache of their own.
- **Background search is opt-in.** Letting a search survive leaving the app means
  handing the request, API key and all, to the operating system for the length of the
  task, so it is off until you turn it on, and the trade-off is written next to the
  switch.

The trust layer lives in one file: [`lib/core/network/cert_trust.dart`](lib/core/network/cert_trust.dart).

Found a vulnerability? Report it privately, as [SECURITY.md](SECURITY.md) explains.

---

## Build from source

**Prerequisites**

- Flutter **3.47.7** stable (the SDK version is set in `pubspec.yaml` and read by CI)
- **iOS / macOS**: current stable Xcode · **Android**: Android Studio, compileSdk 36
- At least one reachable service from the [tables above](#supported-services)

```bash
git clone https://github.com/matthw-labs/cupola.git
cd cupola
flutter pub get
flutter run
```

**Checks and packaging**

```bash
flutter analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
dart run tool/test_bundles/test_bundles.dart
scripts/release.sh all
```

The third line is the whole `flutter test` suite, run as one bundle per folder:
`flutter test` compiles each test file on its own, and with this many files the
compiling takes longer than the tests. `flutter test <file>` still runs one file.

`release.sh` writes the packages to `dist/<version>`. A beta keeps `pubspec.yaml` at
three numbers and takes its suffix from `CUPOLA_PRERELEASE=beta.1`, which names the
packages `cupola-<version>-beta.1.*`. Pushing the matching tag (`v<version>-beta.1`)
builds Windows and Linux on CI into a draft prerelease;
`scripts/release_attach.sh v<version>-beta.1` then adds the packages built here and
rewrites `SHA256SUMS` over every file of the draft. The macOS package needs the
team's Developer ID certificate in the keychain and `CUPOLA_NOTARY_PROFILE` naming
credentials saved with `xcrun notarytool store-credentials`.
`scripts/release.sh testflight` uploads an iOS build to App Store Connect instead.

CI runs the first three on every push to `main` and every pull request against it;
infos are fatal. The test suite is offline
and deterministic: no network, no live instance. An opt-in end-to-end tier
runs against real services in Docker:

```bash
docker compose -f docker-compose.e2e.yml up -d --wait
flutter test --tags e2e --run-skipped
```

---

## Architecture

Feature-first layers over a shared core. Adding a service starts in one file,
`ServiceKey`, the registry every other layer reads from.

```
lib/
├── core/                    # theme + tokens, router, API client, network trust,
│   │                        # reusable widgets, text-scale metrics
│   └── ...
└── features/
    └── <feature>/
        ├── data/            # clients and API calls
        ├── domain/          # models, semantics, capabilities
        └── presentation/    # screens, providers, widgets
```

| Concern | Choice |
| --- | --- |
| UI | Flutter + Material 3, a fixed palette and design tokens, bundled Bricolage Grotesque, Onest and Geist Mono |
| State | Riverpod 3: `FutureProvider` for loads, `NotifierProvider` for persisted state |
| Navigation | go_router; every detail route resolves from path params alone, so any screen is addressable by path, and the `cupola://` scheme lets a widget, a notification or an invite open one |
| HTTP | Dio, shared `ApiClient` with `X-Api-Key` for the *arr family |
| Other transports | qBittorrent WebUI v2 form login, Socket.IO for Dockge, WebSocket JSON-RPC for TrueNAS |
| Storage | `flutter_secure_storage` for secrets, `shared_preferences` for settings |
| Lists | `infinite_scroll_pagination`, `cached_network_image` behind a pinned cache |

Two conventions shape most of the code:

- **Unreachable is normal.** Missing config throws a recognizable exception that the
  shared `AsyncValueWidget` turns into a not-configured placeholder. Browse and load
  methods return empty results when a service fails; only actions the user starts
  surface errors.
- **Nothing blocks the UI thread.** Search and release fetches carry `CancelToken`s,
  and large JSON list mapping runs in an isolate, so mapping functions stay pure.

The service registry every layer reads from is
[`lib/features/settings/domain/service_key.dart`](lib/features/settings/domain/service_key.dart);
the theme in [`lib/core/theme.dart`](lib/core/theme.dart) and routing in
[`lib/core/router.dart`](lib/core/router.dart). The design system (tokens, the brand
book and a rendered card for every widget) starts at [`design/README.md`](design/README.md).
Conventions and PR expectations are written up in [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Project status

We develop Cupola actively and run it on our own stacks every day. Everything on this
page is in the app today. The badge at the top points at the
latest published release, which trails `main` between tags. 1.0.0 is the first release
of the Cupola line, and everything before it was published as Seekarr.

- **18 services integrated.** **11 we have verified against real instances**, 5
  partially, and Unraid and Emby against recorded answers only. The
  [tables above](#supported-services) say which is which, per service.
- **Nearly 1,000 test files** covering models, services, providers and widgets, offline
  by default, with an opt-in Docker-backed end-to-end tier against real services
- **Accessibility is part of the definition of done.** Dynamic Type, contrast, touch
  targets and screen-reader labels are held by tests. If something reads badly with
  VoiceOver or TalkBack, that is a bug: please report it.
- **Explicit non-goals**, so nobody files them as bugs: no server or cloud component,
  no web client, no account layer, and no localization ([why](#faq)).

---

## Contributing

Contributions are welcome: bug reports, integrations, polish, and above all reports
from anyone running a service we could not test.

Please **open an issue first** so we can agree on scope and direction before you write
code. We review issues and PRs in our spare time, so replies can take a few days.

Setup notes, conventions and PR expectations: [**CONTRIBUTING.md**](CONTRIBUTING.md).

---

## FAQ

<details>
<summary><b>Does Cupola need a server, or an account?</b></summary>
<br/>
No. It talks straight to your instances over LAN, VPN or a reverse proxy. There is
no Cupola backend, so there is nothing to sign up for and nothing reporting back to
us. What leaves your network is artwork from TMDB's image CDN, plex.tv when you
sign in to Seerr with Plex, and on Android the usage reports of Google's code scanner:
see [Security & privacy](#security--privacy).
</details>

<details>
<summary><b>Can I try it without a server?</b></summary>
<br/>
Yes. With no connections set up, the first screen offers <b>Explore a demo home</b>: an
invented household running all eighteen services, answered from inside the app. It
keeps nothing and sends nothing over the network, and widgets, notifications and
background work stay off while it runs. <b>Settings → Leave demo</b> brings you back to
the start.
</details>

<details>
<summary><b>Will it work with Overseerr and Jellyseerr?</b></summary>
<br/>
Yes. Both are supported through the same Seerr integration.
</details>

<details>
<summary><b>My services are behind a reverse proxy with a self-signed certificate.</b></summary>
<br/>
That is the expected setup. Cupola offers to trust the certificate the first time it
sees it and pins its fingerprint, scoped to the host. See
<a href="#security--privacy">Security &amp; privacy</a>.
</details>

<details>
<summary><b>Why can Cupola only read part of some services?</b></summary>
<br/>
Because we have not mapped and tested that part of its write layer yet. Each integration ships
read-first and gains actions once we know how its API behaves in practice. Open an
issue if you want us to prioritize a particular one.
</details>

<details>
<summary><b>What does "not tested" mean for a service?</b></summary>
<br/>
That we wrote the integration against the service's official API and covered it with
unit tests, but never pointed it at a live instance, because we do not run that service
ourselves. It may work perfectly, and a report from anyone who does run it turns a <b>○</b> into a <b>✅</b> (or into a
bug worth fixing).
</details>

<details>
<summary><b>Can I run it on Linux or Windows?</b></summary>
<br/>
Yes: each release carries a Windows and a Linux build made by GitHub Actions, with the
same desktop window as macOS. We have not run either ourselves, so a report is welcome.
</details>

<details>
<summary><b>Why not localized?</b></summary>
<br/>
We chose to keep Cupola in English only, so there is no localization scaffolding.
</details>

---

## About this project

We started Cupola for ourselves: managing a self-hosted *arr stack from a phone, from
anywhere. It grew to cover the rest of the home lab because our stacks never stopped at
the *arrs.

Most of our time goes into the details: how each screen behaves, what an error or an
empty page says, and the tests that keep both from slipping.

AI agents are part of how we build Cupola: we decide what it does, review every change
they make, and test it on real devices before each release.

---

## Support

If Cupola is useful to you, a donation helps us keep it moving.

<a href="https://ko-fi.com/matthwlabs"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Support on Ko-fi" /></a>

---

## License

Licensed under the **[Apache License 2.0](LICENSE)**.

Cupola was previously distributed under the MIT License. That license still covers
copies obtained before the change, and its original notice is preserved in
[LICENSE-MIT](LICENSE-MIT); see [NOTICE](NOTICE) for details.

The bundled typefaces, [Bricolage Grotesque](https://github.com/ateliertriay/bricolage),
[Onest](https://github.com/googlefonts/onest) and
[Geist Mono](https://github.com/vercel/geist-font), are licensed separately
under the SIL Open Font License 1.1; each license text ships alongside its font
in [assets/fonts/](assets/fonts/).

### Trademarks

Cupola is an independent project. It is not affiliated with, endorsed or sponsored by
the makers of the services it connects to, whose names are used only to identify them.

- Plex and Plex Media Server are trademarks of Plex and used under a license.
- TrueNAS® is a registered trademark of iXsystems, dba TrueNAS.
- Unraid® is a registered trademark of Lime Technology, Inc. This application is not
  affiliated with, endorsed, or sponsored by Lime Technology, Inc.

All other product names are trademarks of their respective owners. The same notice
ships in the app, under Settings → About → Licenses & trademarks.
