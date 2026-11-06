# E2E tiers

The e2e tag drives the real Cupola service clients over HTTP, JSON-RPC,
Socket.IO and WebSocket. It is intentionally outside the offline flutter test
gate; dart_test.yaml skips it unless the caller opts in.

## Small Docker tier

This is the fast contract tier for the SABnzbd, NZBGet and Readarr tests:

~~~bash
docker compose -f docker-compose.e2e.yml up -d --wait
flutter test --tags e2e --run-skipped
docker compose -f docker-compose.e2e.yml down -v --remove-orphans
~~~

The small compose keeps its historical port layout, including SABnzbd on host
port 8080. Its seed files must not be mounted as writable long-lived state.

## Full macOS laboratory

docker-compose.testlab.yml and test/e2e/testlab/bootstrap.sh implement the
disposable lab for a native Flutter process on macOS. Containers run in
OrbStack; Cupola connects to their loopback-published ports like ordinary
self-hosted instances.

Preflight:

~~~bash
docker context show
docker version
docker compose version
~~~

The first command must print orbstack. Bootstrap or reset the disposable
project with:

~~~bash
test/e2e/testlab/bootstrap.sh --reset
~~~

A normal rerun is idempotent:

~~~bash
test/e2e/testlab/bootstrap.sh
~~~

The script pins vendor images by digest, copies tracked seeds into
.ai/scratch/zz_testlab/state, waits for all healthchecks, bootstraps Jellyfin,
Emby (its first-run wizard, then an API key named Cupola), Seerr and the first
Dockge account, and writes generated credentials to a
chmod-600 file. `--reset` includes every Compose profile, so it really stops
and recreates this disposable project rather than silently leaving profiled
containers running. Run the full Dart transport harness without putting
credentials in the command line:

~~~bash
export CUPOLA_TESTLAB_CREDENTIALS_FILE="$PWD/.ai/scratch/zz_testlab/state/credentials.env"
flutter test test/e2e/testlab_transport_e2e_test.dart \
  --tags e2e --run-skipped
~~~

The docker harness covers the eighteen registry services other than Tracearr,
Emby included (the free edition of Emby Server 4.10, with no Premiere), and
asserts a successful typed read, not merely that a container is running. Empty lists are valid
data; a failed health, authentication or payload probe fails the test.
It also probes wrong credentials against every transport: seventeen services
must reject them. The separate Plex negative probe is reported as skipped when
the container was never claimed: an unclaimed Plex runs with local
authentication disabled and accepts any `X-Plex-Token`. Once the server is
claimed, the bootstrap writes the server's own token (from its
`Preferences.xml`) to the credentials file and the probe runs.

The TrueNAS checks go over TLS with the fingerprint the bootstrap recorded in
`CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT`, at the address a person saves,
`https://127.0.0.1:8460`. The wrong key is refused as a key (classified
`unauthorized`, so a failure of the certificate can never pass for it). A pin
one digit off, and no pin at all, are each refused as an untrusted certificate
(`tls`), never as a dead host: the same test reads a port nothing listens on as
`unreachable`. The certificate probe the trust prompt uses must read the
recorded fingerprint, which is what ties the bootstrap's text to the app's.

## Control plane

`test/e2e/testlab/testlab.py` owns the lab's states. It never mounts the
OrbStack socket into a container, and it never writes a vendor database while
its container runs.

~~~bash
python3 test/e2e/testlab/testlab.py up          # containers plus proxies
python3 test/e2e/testlab/testlab.py status
python3 test/e2e/testlab/testlab.py seed
python3 test/e2e/testlab/testlab.py doctor
~~~

A snapshot stops the containers, archives every bind-mounted state directory
under `.ai/scratch/zz_testlab/state`, starts them again, and leaves out only
Dockge's disposable `docker:dind` store. A reset restores the archive, checks
it byte for byte before starting anything, and brings the lab back. A full
round trip is under a minute on this Mac.

~~~bash
python3 test/e2e/testlab/testlab.py snapshot golden
python3 test/e2e/testlab/testlab.py reset golden
~~~

Scenarios live in `test/e2e/testlab/scenarios/`, declare the Compose profiles
they need, and are idempotent. `apply` changes state through the services' APIs
and verifies it; `teardown` removes it and verifies its absence.

~~~bash
python3 test/e2e/testlab/testlab.py scenario list
python3 test/e2e/testlab/testlab.py scenario apply smoke
python3 test/e2e/testlab/testlab.py scenario teardown smoke
~~~

## Faults through Toxiproxy

The app reaches services through their Toxiproxy ports; the direct ports stay
for the transport harness, which must not depend on the fault layer. The
control plane creates one proxy per service and writes the map to
`.ai/scratch/zz_testlab/ports.json`.

| Service | App port | Direct port |
|---|---|---|
| Seerr | 25055 | 5055 |
| Radarr | 27878 | 7878 |
| Sonarr | 28989 | 8989 |
| Lidarr | 28686 | 8686 |
| Readarr | 28787 | 8787 |
| Prowlarr | 29696 | 9696 |
| Bazarr | 26767 | 6767 |
| qBittorrent | 8080 | 18080 |
| Transmission | 29091 | 9091 |
| SABnzbd | 28082 | 8082 |
| NZBGet | 26789 | 6789 |
| Jellyfin | 28096 | 8096 |
| Emby | 28098 | 8097 |
| Plex | 23240 | 32400 |
| Dockge | 25001 | 5001 |
| Nginx Proxy Manager | 28181 | 8181 |
| TrueNAS | 28460 | 8460 (TLS) |
| Unraid | 28480 | 8480 |

~~~bash
python3 test/e2e/testlab/testlab.py fault radarr down
python3 test/e2e/testlab/testlab.py fault radarr slow 1500
python3 test/e2e/testlab/testlab.py fault radarr timeout
python3 test/e2e/testlab/testlab.py fault radarr flap
python3 test/e2e/testlab/testlab.py fault radarr clear
~~~

`down` resets the connection, which the app reads as a host that did not
answer. `timeout` stops the bytes without closing the socket, `slow` adds the
given latency, `flap` times out half the connections, and `clear` removes every
toxic and enables the proxy again. The real client test is
`test/e2e/testlab_fault_e2e_test.dart`: it turns Radarr off, proves the app
classifies the failure as `unreachable` and says `Radarr did not answer`, then
clears the fault and reads the library again.

The same commands are available to a journey inside the app sandbox on
`127.0.0.1:8799`, authorised by `CUPOLA_TESTLAB_CONTROL_TOKEN` from the
chmod-600 credentials file. The server never prints the token, and the request
body names only the whitelisted commands.

~~~bash
python3 test/e2e/testlab/testlab.py serve
curl -H "Authorization: Bearer $CUPOLA_TESTLAB_CONTROL_TOKEN" \
  http://127.0.0.1:8799/status
~~~

## The forge spike

`testlab-forge` writes a set of variants into `/downloads/spike`, and the spike
asks the three arrs' own `manualimport` scan what they make of them:

~~~bash
python3 test/e2e/testlab/testlab.py spike
~~~

The report checks that a 1080p file parses as `WEBDL-1080p`, a 2160p as
`WEBDL-2160p`, a 480p as `WEBDL-480p`, that a file with `sample` in its name is
refused as a sample, that a 20-second file **without** the word is refused as a
sample from its duration alone, that a `Breaking.Bad.S01E02...` file matches the
series and the episode, that a FLAC track parses as FLAC, and that an unreadable
name needs a match. The music files are generated from the Discovery album
Lidarr knows, one file per track, with MusicBrainz's durations, so a partial
album is not what the spike is measuring.

## The release catalogue

`testlab-forge` writes a catalogue of 24 releases for Big Buck Bunny. They share
the one real torrent, but each has its own title, size and infohash: Radarr's
search collapses a list on the infohash, and Prowlarr forwards them as separate
rows. `testlab-indexer` answers with all of them; Prowlarr owns the indexer and
syncs it to Radarr, Sonarr, Lidarr and Readarr, so the apps have a single
Prowlarr indexer and the direct Radarr one is removed.

The rows carry what Radarr judges: qualities above and below the profile,
Italian and multi-language releases, CAM and TS sources, groups, and sizes no
one would take. The app's `Search releases` sheet shows `24 releases` and a
`Rejected` badge; the reason Radarr computes, for example `English is wanted,
but found Italian`, is in the row's expanded content. The journey
`integration_test/journeys/release_search_journey_test.dart` opens the movie
page, scrolls to Manage, opens the sheet and checks the catalogue and the badge.
`test/e2e/testlab_release_search_e2e_test.dart` grabs an accepted row, waits for
the app's qBittorrent, and checks Radarr's `grabbed` and
`downloadFolderImported` history.

The seeder and the app's qBittorrent start after the tracker is healthy.
qBittorrent keeps a negative DNS answer for a tracker in its process, and a
golden snapshot can carry a `Host not found` from the first start; the control
plane reannounces, and restarts the seeder if the answer is still stale.

Not in L5: the local NNTP server and the full Usenet states. The lot's
acceptance, a search with rejection reasons and a grab that completes, passes;
the torrent states are in L6.

## A manual import slice

`testlab-forge` makes a real 1080p MKV and a private torrent, `qbittorrent-seed`
seeds it from its own downloads folder, and `testlab-indexer` serves both a
Torznab search and a BEP 3 tracker. The seed gives Radarr the qBittorrent client
and the indexer, and adds Big Buck Bunny to the library with no file. The
release title matches the movie; the file inside is named
`The.Great.Bunny.2008.1080p...`, which Radarr cannot match, so its
`manualimport` scan reports `Unknown Movie`.

The scenario adds the torrent to the app's qBittorrent, waits for the real
download, and checks Radarr's scan. It is idempotent and has a teardown. A reset
restores the golden state, torrent and all.

~~~bash
python3 test/e2e/testlab/testlab.py snapshot golden-s1
python3 test/e2e/testlab/testlab.py scenario apply manual-import-radarr-ambiguous
python3 test/e2e/testlab/testlab.py scenario teardown manual-import-radarr-ambiguous
python3 test/e2e/testlab/testlab.py reset golden-s1
~~~

The journey starts on the dedicated iOS simulator, not the configured one. It
walks Activity, `Manual import…`, the Radarr connection, the download folder,
the scan, `Which movie?`, `Match to Big Buck Bunny`, and the import. It checks
Radarr for the file and the scan for no importable item left. Run it after the
scenario has been applied:

~~~bash
flutter test integration_test/journeys/manual_import_radarr_journey_test.dart \
  -d <dedicated-simulator-udid> --tags e2e --run-skipped
~~~

Two sentences from the original plan do not match the app and Radarr as they
are. A release Radarr grabbed is imported under the movie it grabbed, so a wrong
file name inside the download does not by itself produce an `importBlocked`
queue item; the manual import wizard is the flow that lets a person name the
movie. And the review scan reports files the service already holds, so an
imported file changes from `Needs match` to `Imported` instead of disappearing.
The journey asserts those real states.

## The arr libraries

The seed materialises the world as a library rather than a handful of rows:
41 films, 10 series (the eight real ones the lookup resolves plus two lab
specimens), 8 artists and 6 authors. Radarr creates the films from the ids in
`world.json` and asks `RefreshMovie` for the artwork in the background; Sonarr
looks up the real TVDB series and refreshes their episodes, with Brooklyn
Nine-Nine the one the lookup does not resolve; Lidarr adds each artist and its
first album; Readarr's authors and books are written
straight into its database with the container stopped (`readarr_seed.py`),
because its metadata host is gone.

Bazarr runs with `general.use_embedded_subs: false`, so the embedded provider
actually extracts instead of treating the track as already present. The
`bazarr-embedded` scenario adds an English track to a film, syncs Bazarr, and
checks the extracted `.en.srt` and the history row; a film with only a French
track stays wanted. Its teardown restores the file, the subtitle list and the
setting.

## The queue states

Four scenarios put the app's qBittorrent in the states the flow catalogue asks
for (D-16, and the journeys G-28 and G-29 that read them). Each one is
idempotent, verifies the raw state through `/api/v2/torrents/info`, and puts the
lab back: the seeder's file whole and rechecked, the client's torrent and bytes
gone, the queueing preferences as they were.

| Scenario | State | How it is made |
|---|---|---|
| `queue-stuck-47` | `stalledDL` at 47% | The seeder's file is backed up, truncated to 40 of 86 pieces and rechecked, so the only peer can serve exactly that much. |
| `queue-paused` | `stoppedDL` mid-transfer | Added stopped, given a 64 KiB/s limit, started, and stopped once some bytes are in. |
| `queue-missing-files` | `missingFiles` | The release is fetched whole, its folder moved away, and the app's qBittorrent restarted. |
| `queue-queued` | `queuedDL` | `max_active_downloads=1` with the seed's magnet holding the slot. |

~~~bash
python3 test/e2e/testlab/testlab.py scenario apply queue-stuck-47
python3 test/e2e/testlab/testlab.py scenario teardown queue-stuck-47
~~~

Two things the lab cannot do quickly. `missingFiles` is only decided when
qBittorrent starts, so that scenario restarts the app's qBittorrent container
(the arrs and the indexers are never touched). And `stalledDL` reads
`Downloading` until 30 minutes pass with nothing arriving: the app's `Stuck`
(`download_client_faults.dart`, `stuckAfter`) is a word for a long quiet, so a
journey that wants `Stuck at 47%` must either wait it out or read the state the
app maps, not the word.

## The arr rows

The catalogue's arr flows are scenarios that speak to the real services and
read the result back. They use disposable titles, clone a quality profile,
create a second root folder and a tag, and put everything back in the teardown.

| Scenario | Rows | What it proves |
|---|---|---|
| `arr-actions-radarr` | A-01, A-04, A-06, A-07 | Add by TMDB id with profile, root, tag and monitoring; a duplicate is refused; profile and monitoring are read back; `MoviesSearch`; removal with files, folder and import exclusion |
| `arr-actions-sonarr` | A-02, A-04, A-06, A-07 | Add with the first season and series type; duplicate; profile, monitoring and type; the three searches; removal and exclusion |
| `arr-library-radarr` / `arr-library-sonarr` | A-08, A-09, A-11, A-12 | The library fields behind every chip, the calendar window, wanted missing and cutoff, the history rows of the L5 grab |
| `arr-actions-lidarr` / `arr-actions-readarr` | A-04, A-06, A-07 | Profile and monitoring, the automatic searches, the removal where the service can make a disposable record |
| `arr-library-lidarr` / `arr-library-readarr` | A-08, A-09, A-10, A-11, A-12 | The library, calendar, queue envelope, wanted and history |
| `arr-queue` | A-10 | The queue envelope answers whole and empty, and the download client and indexer are reachable, so the empty is not a fault |

The limits are real and declared. The arr queue's `trackedDownloadState` needs
a grab the arr still tracks; the lab's catalogue has one torrent, so every
release shares its infohash, and `golden-l6` already carries that infohash's
import. The queue states that can be reached are the qBittorrent ones in
`queue-*`. Sonarr has no episode files, so Available, Cutoff unmet and In queue
are empty; the fields that decide the chips are verified. Readarr cannot make a
disposable author (its metadata host answers 503) and deleting a seeded one is
not reversible, so its A-07 is declared partial instead of faked.

~~~bash
flutter test --tags e2e --run-skipped test/e2e/testlab_arr_radarr_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_arr_sonarr_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_arr_lidarr_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_arr_readarr_e2e_test.dart
~~~

## Prowlarr and Bazarr

`prowlarr-indexers`, `prowlarr-apps` and `prowlarr-history` cover A-13 to A-17:
a disposable Torznab indexer is added, tested, enabled and disabled in bulk,
given a tag, synced to the apps, then deleted; the seeded indexer and apps stay
untouched. `bazarr-catalog` covers A-18 to A-20 by reusing `bazarr-embedded`:
the wanted list, the extracted subtitle in the history and the provider reset.

Prowlarr's `/api/v1/history` binds `eventType` to its numeric enum (1 grab, 2
query, 3 RSS, 4 auth), not to the names the app uses. The app translates its
names in `prowlarr_service.dart`; sending `indexerQuery` raw is a 400, and the
History tabs would load nothing.

~~~bash
flutter test --tags e2e --run-skipped test/e2e/testlab_prowlarr_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_bazarr_catalog_e2e_test.dart
~~~

## Usenet over a local NNTP server

`nntp_server.py` runs on the host (`127.0.0.1:1119`, plus a small HTTP surface
on 1120 for the NZB and the health check) and serves yEnc articles to the two
Usenet clients; the containers reach it at `host.docker.internal:1119`. The
`usenet-sab` and `usenet-nzbget` scenarios configure the client's news server
through its own API, add a real NZB, wait for the file to match byte for byte,
and exercise queue, pause, resume, delete and history. They restore the server
configuration and the jobs in the teardown.

Two traps are documented in the code: NZBGet's `saveconfig` rewrites the file
from only the options it receives, so the scenario saves and restores the five
news-server fields it touches; and the seed's `cupola-nzbget-test` specimen job
is paused while the scenario runs so it does not take the only connection.

~~~bash
flutter test --tags e2e --run-skipped test/e2e/testlab_usenet_e2e_test.dart
~~~

## The Seerr world

The household Seerr is a world, not a single account. `seerr_world.py` seeds it
through the API, idempotently: Anna (local, request only, low quota), Luca
(local, 4K and advanced requests, auto-approval), the Jellyfin-imported viewer,
requests in pending, processing, available, declined and failed states, a
series with two of its eight seasons, a 4K request, an issue with comments and
Anna's watchlist. It writes `seerr-world.json` (mode 0600) with the generated
passwords and the fixture ids; the e2e reads that contract. The failed request
is real: Seerr approves it and Radarr refuses a root folder that does not
exist, so Seerr marks it failed.

Sara's Seerr is a second server, `seerr-sara` on port 5056 with its own state
and admin (a Jellyfin user). The operator holds a local account there that may
only request, and one pending request of his own. `seerr_sara.py` initializes
and seeds it, and `bootstrap.sh` calls it after the household seed. P9 uses
both servers: the household one by key, Sara's by the operator's account. P5
uses the household Seerr and Jellyfin only, and reads the Radarr and Sonarr
from Seerr's settings, which it reaches only on the Compose network.

The Plex-imported user is not in the lab: the Plex server is claimed with the
real account, and Seerr's Plex first setup would create the admin from that
plex.tv identity. The P2-P profile covers the Plex path in the offline fakes;
the lab's second Seerr is on Jellyfin. That is a declared limit, not a fake.

~~~bash
python3 test/e2e/testlab/testlab.py scenario apply seerr-world
python3 test/e2e/testlab/testlab.py scenario teardown seerr-world
flutter test --tags e2e --run-skipped test/e2e/testlab_seerr_flows_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_seerr_p9_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_seerr_p5_e2e_test.dart
~~~

## Jellyfin, Emby and Plex

The seed adds `Series` and `Music` beside `Films` on the same `/media` folders.
The files are the forge's episode and FLACs, so the libraries hold a film, a
two-episode series and Daft Punk's Discovery with 14 tracks, not empty
collections. `jellyfin_media.py` also leaves the non-admin `cupola-viewer` with
a watched film and an episode at a third of its length in Continue watching;
`plex_media.py` leaves the watched film and episode and Plex's own next-up on
deck.

Emby is a real Emby Server 4.10 (the free edition), on the same `/media`
mount as Jellyfin, so it holds the same movie, series and album. Its first run
is `emby_first_run.py`: the Startup wizard, the administrator, and the API key
named Cupola that `POST /Auth/Keys` makes and `GET /Auth/Keys` reads back (the
create call answers 204 and no body). The key is what the app is given, as
Jellyfin's token is; because a key belongs to no user, the connection also
names `cupola-admin` as the viewer it reads as. `emby_media.py` then makes the
household member `cupola-viewer`, the three libraries, the watched movie and
the episode at a third of its length for that member. Emby only lists a resume
point that has a `LastPlayedDate`, so the seed writes one. Emby answers a few
routes differently from Jellyfin, and the e2e say where: a member's token may
read the libraries and is refused users, devices and tasks, an API key has no
`/Users/Me`, item ids are short numbers, and sign-in refuses a chunked request
body.

~~~bash
python3 test/e2e/testlab/testlab.py play "Big Buck Bunny" --server jellyfin --pause --stop
python3 test/e2e/testlab/testlab.py play "Big Buck Bunny" --server emby --pause --stop
python3 test/e2e/testlab/testlab.py play "Big Buck Bunny" --server plex --stop
python3 test/e2e/testlab/testlab.py scenario apply emby-media
~~~

Jellyfin and Emby are the controllable ones: `jellyfin_play.py` and
`emby_play.py` open a session with a dedicated device and their pause/stop
report moves the state. The app's own Pause/Stop are remote-control commands:
the server answers 204 and forwards `Playstate` to the client over the
WebSocket, so they only change the session when a client is listening
(`--listen --hold`, on Emby the socket is `/embywebsocket`). Emby's helper signs
a person in per device, because a playback reported with the API key is refused,
and announces its capabilities before the first report, which is what makes the
session remote-controllable. Plex has no
pause the app can reach; its session is a spike (a part read beside
`/:/timeline`) and its Stop is behind Plex Pass, which this server does not
have: the app does not draw it and the raw terminate answers 401. No Plex Home
user is created, because the server is claimed with the real account.

The e2e drive the app's clients and the providers behind Home, Overview and
Stack. A widget-level Now playing is L12; here the test reads the same
providers the surfaces read.

~~~bash
flutter test --tags e2e --run-skipped test/e2e/testlab_jellyfin_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_emby_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_plex_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_stream_sessions_e2e_test.dart
~~~

The L12 journeys drive the same playbacks from the screen, on the simulator.
The app cannot open a process there, so the player runs on the host and
`journey_sessions.py` owns it: it starts the devices, waits for the server to
list them, runs the journey, and ends them on the way out.

~~~bash
python3 test/e2e/testlab/journey_sessions.py S-03
python3 test/e2e/testlab/journey_sessions.py S-09
python3 test/e2e/testlab/journey_sessions.py S-03 --server emby
~~~

The media server journeys are written once for Jellyfin and Emby, and the
wrapper picks a server's own by the words its test names carry.

## TrueNAS, Unraid, NPM and Dockge

TrueNAS and Unraid are stateful simulators, not fixture bags. `mock/server.py`
serves the TrueNAS WebSocket JSON-RPC from a world built out of the lab's own
datasets, pools (one healthy, one degraded), users, shares, apps and VMs; a
scrub is a job that advances, apps and virt instances move through jobs, alerts
dismiss, and a reboot drops every socket. `test-readonly` is a second key with
the `READONLY_ADMIN` role and no write role, so every write is refused with the
`EACCES`/`EPERM` the app knows. `mock_unraid/` serves the GraphQL the client
uses: a disk disabled and emulated by parity, Docker containers, VMs with
start/stop/resume/pause, notifications with an archive and shares; a view-only
key is refused by the mutation path. Both have a contract script that compares
the answers with `test/fixtures/`: 102 and 103 checks.

NPM is the real container: two proxy hosts (one advanced block that answers on
its own location, one disabled and enabled), an expiring self-signed
certificate, an access list, the audit log and a view-only user. Dockge is the
real container on its `docker:dind`; the dind now stores `/var/lib/docker` in a
named volume, because overlayfs cannot write an upperdir on the Mac's virtiofs.
Three compose stacks (a logger, a stopped one, one that crashes) live there;
start/stop/restart/update/down, create/edit/delete and the action terminal are
driven through the app's client.

~~~bash
python3 test/e2e/testlab/testlab.py scenario apply truenas-state
python3 test/e2e/testlab/testlab.py scenario apply unraid-state
python3 test/e2e/testlab/testlab.py scenario apply npm-lab
python3 test/e2e/testlab/testlab.py scenario apply dockge-lab
flutter test --tags e2e --run-skipped test/e2e/testlab_truenas_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_unraid_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_npm_e2e_test.dart
flutter test --tags e2e --run-skipped test/e2e/testlab_dockge_e2e_test.dart
~~~

Declared limits: NPM renews only Let's Encrypt certificates, so the success
branch is a 400 on the uploaded one; its audit log and access list can never be
empty in a used lab. TrueNAS keeps its world in memory and leaves replication,
cloudsync and rsync task operations unimplemented because the app never sees
them; its reporting is synthetic. Unraid's emulated disk is `DISK_DSBL` plus
the notification, not a query field; its containers are the fixture, not a real
daemon. Dockge 1.5.0 never emits `stackStatusList`, `getStack` always reads
`Unknown` for a managed stack, and the combined terminal only joins a terminal
some action already opened.

## Guasti e casa/fuori casa

Ogni servizio del laboratorio ha già il Toxiproxy davanti, quindi un guasto è una toxica sul proxy che l'app usa e
la porta diretta resta per l'harness di trasporto, che non deve dipendere dal livello dei guasti. Quattro scenari
applicano una classe e la tolgono: `fault-down` (la connessione cade), `fault-timeout` (la connessione muore a
metà), `fault-slow` (la risposta arriva troppo tardi) e `fault-flap` (il link sbatte). `away-home` spegne il
secondo ascoltatore dello stesso upstream, l'indirizzo "fuori casa", che il compose pubblica su 27879.

L'e2e chiede all'app di leggerle con il suo codice: `Radarr did not answer` per la connessione caduta, `Radarr
was reached but did not reply in time` per la risposta in ritardo, il link che sbatte che prima o poi torna, e
`Radarr only works at home` quando l'indirizzo di casa risponde e quello fuori no.

~~~bash
python3 test/e2e/testlab/testlab.py scenario apply fault-down
python3 test/e2e/testlab/testlab.py fault radarr slow 4000
flutter test --tags e2e --run-skipped test/e2e/testlab_faults_e2e_test.dart
~~~

Il gateway è un processo dell'host (`gateway_lab.py`, porta 8466) che porta tutti i ruoli di un gateway: il login di
Cloudflare Access e il suo rifiuto di una richiesta senza il token di servizio, la password di un proxy, gli header
personalizzati richiesti, una pagina di accesso che Cupola non può completare, e un'altra applicazione al posto del
servizio. L'e2e verifica che l'app li riconosca tutti e percorre i sei esiti di Collega: risposto, chiave rifiutata,
nessuna risposta, un certificato di cui non si fida, http in chiaro dove serve https, e il gateway che rifiuta il
token inviato.

Il bordo è un processo dell'host (`edge_lab.py`, porta 8444) con un certificato autofirmato proprio davanti a Radarr:
l'app legge l'impronta, la pin, e con la pin la connessione passa. La rotazione è a comando: il laboratorio rifà il
certificato, l'impronta cambia, e il pin vecchio viene rifiutato (`Radarr has a certificate Cupola does not trust`)
mentre quello nuovo funziona. Il bordo con Caddy (`## Il bordo con Caddy`) copre la stessa riga con tre origini e
un certificato emesso da una CA interna; questo processo resta il caso di una sola origine e di una foglia
autofirmata. Gli indirizzi sbagliati del primo avvio sono i sei esiti che il gateway copre già.

## La configurazione dell'app per un profilo

`testlab.py app-config <profilo>` scrive la configurazione dell'app per un
profilo P1–P10 nello stato del laboratorio, nel formato che l'app legge: gli
indirizzi, i nomi e la rosa delle connessioni nelle `SharedPreferences`, le
chiavi, le password, i token e le sessioni nella memoria sicura, con le chiavi
che `SettingsService` deriva dall'id di ogni connessione. Il file sta in
`.ai/scratch/zz_testlab/state/app/<profilo>.json` con mode 600, accanto agli
altri segreti usa e getta, e mai nel repository.

~~~bash
python3 test/e2e/testlab/testlab.py app-config P1
python3 test/e2e/testlab/testlab.py app-config P7 --apply macos
~~~

L'app lo legge nel suo processo, perché la memoria sicura è il suo portachiavi
e niente fuori dall'app può scriverla: `integration_test/testlab/seed_app.dart`
consegna il file alle memorie dell'app e le rilegge. Il simulatore legge il
file dove il laboratorio l'ha scritto; l'app macOS è in sandbox e non vede lo
stato del laboratorio, quindi chiede lo stesso file all'API di controllo
(`GET /app-config?profile=P1`, con il token).

I profili sono quelli del catalogo del mondo
(`test/test_helpers/profiles/profiles.dart`) portati su ciò che il laboratorio
serve. Due hanno bisogno che il laboratorio sia in un certo stato:

- P7 raggiunge i suoi server all'indirizzo fuori casa, il secondo ascoltatore
  del Toxiproxy (la porta dopo quella del proxy), che lo scenario `away-home`
  spegne a comando; le connessioni che il mondo tiene a casa non ne hanno uno;
- P8 raggiunge Radarr, Sonarr e Seerr al gateway del laboratorio: Radarr
  presenta il token di servizio che il gateway lascia passare, Sonarr non ne
  presenta e Seerr ne presenta uno che nessuna policy ammette.

Il secondo Radarr del mondo è il bordo del laboratorio, l'origine con
certificato proprio davanti a Radarr; il secondo Sonarr è il Sonarr del
laboratorio sotto un altro nome, perché il laboratorio ne ha uno solo e l'app
ha bisogno di due istanze di un servizio per provare la lente.

L'e2e (`test/e2e/testlab_app_config_e2e_test.dart`) legge il file con il
`SettingsService` vero e prova che le connessioni, le chiavi, l'indirizzo
fuori casa di P7 e il gateway di P8 sono quelli che il laboratorio scrive, e
che una connessione inesistente è dichiarata non configurata invece di
fingere.

## Il bordo con Caddy

Lo scenario `caddy-edge` alza un Caddy vero davanti a Radarr, Dockge e TrueNAS, un'origine per porta e un nome per origine (Caddy emette un certificato per nome dalla sua CA interna):

| Origine | Indirizzo | A monte |
|---|---|---|
| Radarr | https://radarr.localhost:8445 | radarr:7878 |
| Dockge | https://dockge.localhost:8446 | dockge:5001 |
| TrueNAS | https://truenas.localhost:8447 | truenas-mock:8460 (TLS, verificato in modo lasco verso il mock) |

`*.localhost` risolve a 127.0.0.1 su macOS e sul simulatore (RFC 6761), ma non dentro il container Alpine: l'healthcheck usa `curl --resolve`. Il bordo si accende e si spegne con lo scenario, e `caddy_lab.py --rotate` butta via la CA interna e riparte: le impronte cambiano, i pin vecchi non passano più.

Il pin dell'app è il certificato che la verifica di piattaforma ha rifiutato: con un certificato autofirmato è la foglia, con una catena è l'intermedio della CA. Qui le tre foglie sono distinte, ma l'app legge lo stesso intermedio per tutte e tre le origini, quindi i tre pin coincidono e restano legati a host e porta. L'e2e (`test/e2e/testlab_caddy_e2e_test.dart`) legge i pin con il probe dell'app e le foglie dal socket, e prova la rotazione su tutte e tre.

## Published endpoint map


| Service | Native endpoint | Auth in the lab | Transport |
|---|---|---|---|
| Seerr | http://127.0.0.1:5055 | generated API key; a local requester account with a generated password | REST + session cookie |
| Seerr (Sara) | http://127.0.0.1:5056 | generated API key; the operator's local requester account, generated | REST + session cookie |
| Radarr | http://127.0.0.1:7878 | test-key | REST v3 |
| Sonarr | http://127.0.0.1:8989 | test-key | REST v3 |
| Lidarr | http://127.0.0.1:8686 | test-key | REST v1 |
| Readarr | http://127.0.0.1:8787 | test-key | REST v1 |
| Prowlarr | http://127.0.0.1:9696 | test-key | REST v1 |
| Bazarr | http://127.0.0.1:6767 | test-key | REST |
| qBittorrent | http://127.0.0.1:8080 | admin / disposable password | form + cookie |
| Transmission | http://127.0.0.1:9091 | transmission / transmission | RPC + CSRF |
| SABnzbd | http://127.0.0.1:8082 | test-key | query API |
| NZBGet | http://127.0.0.1:6789 | nzbget / tegbzn6789 | JSON-RPC + Basic |
| Jellyfin | http://127.0.0.1:8096 | generated token + user id; a requester user with a generated password | REST |
| Emby | http://127.0.0.1:8097 (the API sits under `/emby`) | generated API key named Cupola + the administrator's user id; a requester user with a generated password | REST |
| Plex | http://127.0.0.1:32400 | unclaimed: any token; claimed: the server's own token, read by the bootstrap | REST/XML-or-JSON |
| Dockge | http://127.0.0.1:5001 | disposable account provisioned by bootstrap | Socket.IO |
| Nginx Proxy Manager | http://127.0.0.1:8181 | admin@example.com / changeme | REST + JWT |
| TrueNAS fixture | wss://127.0.0.1:8460 (self-signed; the app saves https://127.0.0.1:8460) | test-key | WebSocket JSON-RPC over TLS |
| Unraid fixture | http://127.0.0.1:8480/graphql | test-key | GraphQL |
| Caddy edge (Radarr) | https://radarr.localhost:8445 | test-key | HTTPS, certificate from Caddy's internal CA |
| Caddy edge (Dockge) | https://dockge.localhost:8446 | the lab's Dockge account | Socket.IO over TLS |
| Caddy edge (TrueNAS) | https://truenas.localhost:8447 | test-key | WebSocket JSON-RPC over TLS |

The lab-only services are not app connections: `testlab-indexer` listens on
host port 8188 for Torznab and tracker requests, the seeder's WebUI is on 8081,
and `testlab-forge` is a one-shot container that writes the release and exits.
The indexer's own port inside the Compose network stays 8088, which is what the
torrent's announce URL and Radarr's indexer use.

qBittorrent 5.1 validates the Host/Origin port, so the full lab uses host
port 8080 for qBittorrent and 8082 for SABnzbd. Transmission's LinuxServer
image consumes USER/PASS; the Compose file uses those names and the harness
asserts both the 409 CSRF challenge and the 401 wrong-password path.
Unclaimed, Plex is a transport/shape fixture: claiming it ties the lab to a
Plex account, which is the owner's choice and never the bootstrap's. Claimed,
its token stays in the chmod-600 credentials file like every other secret.

Dockge runs against its own `docker:dind` sidecar, privileged and isolated on
the compose network: the OrbStack socket is never mounted into a container.
Login, Socket.IO session, stack discovery and the stack actions Dockge offers
are safe to test; the dind daemon holds only the lab's stacks and publishes no
port to the host. The Terminal tab reads Dockge's combined action log, not an
interactive shell.

The TrueNAS fixture speaks TLS and nothing else, because Cupola refuses to dial
a TrueNAS address that is not https:// (TrueNAS 25.04 and later revoke an API key
that arrives in cleartext). Its certificate is self-signed, made once by
test/e2e/testlab/truenas_cert.sh (bootstrap.sh runs it before it starts the
containers) with `localhost` and `127.0.0.1` as names, and kept with the rest of
the lab's disposable state in `state/truenas/`; it is never committed. Cupola
trusts it the way a person does, by its fingerprint: the SHA-256 of the
certificate's DER encoding as 64 lowercase hex digits, without colons, the form
`certFingerprint` compares and `SettingsModel.trustedCertificates` stores under
the origin `https://127.0.0.1:8460`. The bootstrap writes it to the credentials
file as `CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT`. Added by hand in the app at
`https://127.0.0.1:8460`, "Test connection" reads the certificate and offers to
trust it; the fingerprint it shows is that one, written in colon-separated
uppercase pairs. A lab started before this
existed gets the certificate, the credentials entry and a mock that serves it
without a reset (the other credentials are left as they are):

~~~bash
export CUPOLA_TESTLAB_STATE_DIR="$PWD/.ai/scratch/zz_testlab/state"
test/e2e/testlab/truenas_cert.sh credentials
docker compose -p cupola-testlab -f docker-compose.testlab.yml \
  --profile core up -d --build --wait truenas-mock
~~~

The mock reads the certificate for every connection: a certificate made again
(delete the two files in `state/truenas/`, not the directory, which a running
container keeps hold of, and run the script with `credentials`) is served at
once, and every fingerprint saved before it is then refused as an untrusted
certificate, which is how a rotated certificate reads in the app.

TrueNAS and Unraid are deterministic transport fixtures, not vendor-certified
servers. They reproduce the JSON shapes, authentication and framing used by
Cupola. Certification against a real TrueNAS/Unraid host remains a separate
environmental test.

The seed is small and uses the network once, for the metadata Radarr's lookup
needs. Radarr receives Big Buck Bunny with no file, the qBittorrent client and
the local Torznab indexer; Sonarr and Lidarr receive one resolved record each;
Jellyfin, Emby and Plex receive a `Films` library; qBittorrent and Transmission
receive paused zero-data magnets; SABnzbd and NZBGet receive a disposable NZB;
and NPM receives `cupola.test`. Readarr gets its Books root and six
authors with their books, written into its database with the container stopped
because its metadata host is gone. Prowlarr owns
the Torznab indexer and syncs it to the four arrs; the direct Radarr indexer the
import slice used is removed once the sync has run. Bazarr is configured for the two arr services and extracts the English
subtitles embedded in the forge files; a file without the language stays
wanted. These are capability limits of
the lab, not claims that the corresponding Cupola screens are unreachable.

The seed reads `state/world.json`, which `dart run tool/testlab/export_world.dart`
writes from `test/test_helpers/profiles/world.dart`. The export is deterministic,
and `test/tool/export_world_test.dart` holds it to the Dart catalogue: 41 movies,
12 series, 8 artists and 6 authors. The bootstrap exports it before the seed; a
world.json that has drifted from the Dart source is a test failure, not a
surprise in the lab.

## A household member's own Seerr account

test/e2e/testlab_requester_e2e_test.dart signs in to the lab's Seerr (3.4.1,
set up on the lab's Jellyfin 12.1) the way a household member does, through
Cupola's own code: `SeerrAuthService` for the sign-in, `seerrClientFor` for
the session cookie and the CSRF token, `SeerrAccounts` and the providers for
the account the connection keeps. The offline suite proves the same paths
against the fake Seerr in test/test_helpers/profiles/fakes/seerr_sessions.dart;
this run proves the fake answers the way Seerr does. Where the two disagree,
Seerr wins, and the fake and the app change together.

The bootstrap seeds two accounts, each with REQUEST alone (no manage
permission, no auto-approve): a local Seerr account and a Jellyfin user that
Seerr has imported. Both get new generated passwords on every run, kept only
in the chmod-600 credentials file next to the other lab secrets. The bootstrap
starts the lab and seeds them; a rerun only sets the new passwords:

~~~bash
test/e2e/testlab/bootstrap.sh
flutter test --tags e2e --run-skipped test/e2e/testlab_requester_e2e_test.dart
~~~

The test reads `CUPOLA_TESTLAB_CREDENTIALS_FILE` like the other lab tests, and
falls back to .ai/scratch/zz_testlab/state/credentials.env under the working
directory. Asking for a movie needs the lab's Seerr to reach TMDB, so that
step needs the internet. What it proves:

- the sign-in methods `SeerrServerFacts` reads from `/settings/public`;
- an email and a wrong password refused as a wrong password, the right one
  signed in, `/auth/me` read into `SeerrGrant`, the account's own requests
  and quota, and the connection test passing as the account;
- a request made as the account, a 4K one refused as not allowed, and the
  operator's writes (approve, decline) refused as a permission the account
  lacks, never as a refused key or an ended session; the account cancels its
  own pending request; a permission the operator grants reaches the grant;
- a way in the operator turned off after the methods were read, refused in
  the route's words, and a Jellyfin user the server does not take (new
  sign-ins off, never imported) refused as not allowed; the test puts both
  settings back;
- a Jellyfin username and password, and a Quick Connect code approved from
  Jellyfin;
- signing out, after which the server no longer knows the session, and a
  session ended on the server side, read as ended on every request after;
- a connection behind an access gateway (a local proxy started by the test)
  whose custom header reaches Seerr, and the same address without it turned
  away by the gateway;
- with Seerr's CSRF protection on, writes as the key and as an account, a
  sign-in, a Quick Connect code and a sign-out all pass the guard. The test
  turns the setting on, restarts the Seerr container (`docker restart
  cupola-testlab-seerr-1`, or `$CUPOLA_TESTLAB_PROJECT-seerr-1`), and puts it
  back the same way when it ends, failed or not.

Never read Seerr's database while its container runs: it writes in SQLite's
WAL mode, and a second reader over the bind mount can lose its recent writes.
Stop the container first, then open state/seerr/db/db.sqlite3. That is how
the session store's expiry was checked: 30 days after the session's last
use, not after its sign-in.

### Signing in with Plex

The Plex group is reported as skipped: it needs a Seerr set up on Plex with a
real plex.tv account, and a person to approve the PIN on app.plex.tv. Run it
by hand on a macOS build of Cupola:

1. Claim the lab's Plex for your own plex.tv account: recreate the container
   with a claim token from https://plex.tv/claim in `PLEX_CLAIM`, or sign in
   at http://127.0.0.1:32400/web.
2. Start a second Seerr on its own port and state directory, from the image
   the Compose file pins:
   `docker run -d --name cupola-testlab-seerr-plex -p 127.0.0.1:5056:5055
   -v "$PWD/.ai/scratch/zz_testlab/state/seerr-plex:/app/config" <image>`.
3. Open http://127.0.0.1:5056 in a browser, sign in with Plex, choose the
   lab's Plex server and finish the setup. To sign in as a household member
   rather than the owner, share the server with a second plex.tv account.
4. In Cupola, add a Seerr connection at http://127.0.0.1:5056, choose to sign
   in with an account, then Plex. Approve Cupola on the Plex page, and check
   that the connection reads signed in with the right name, that a request
   goes through, and that signing out ends the session.
5. Remove the container and its state directory, and revoke Cupola under
   Authorized Devices on plex.tv.

## Native macOS test plan

The service harness is only one layer. A complete run is ordered so a broken
Docker endpoint cannot be mistaken for a UI placeholder:

1. Native preflight: run flutter pub get, flutter analyze --fatal-infos,
   dart format --output=none --set-exit-if-changed ., the offline flutter test
   suite, and flutter build macos (or the unsigned Xcode compile gate when
   signing is unavailable).
2. Lab bootstrap: run the script above, record the Compose project name, and
   run the full transport harness. Stop if a service is missing, returns 401 or
   403, times out, or returns an invalid shape.
3. Cupola configuration: launch with flutter run -d macos or the built app,
   complete onboarding, add every service using the endpoint map, and verify
   each connection row. Credentials remain in the macOS keychain.
4. Route/tab pass: from /stack visit every route produced by serviceTabs
   for each configured service, plus /activity, /search and /settings. Exercise
   cold load, refresh, deep link and back navigation. TrueNAS is the deliberate
   exception to the horizontal service-tab model.
5. State pass: for each service capture success/empty, partial or degraded
   data, rejected credentials, remote error, unreachable host and
   not-configured. The transport tier already verifies rejected credentials
   for seventeen services; Plex needs an authenticated server for that one
   state. Use fixture mutations or an isolated service stop/start, then restore
   the green baseline. An unavailable figure must be an em dash, and a failed
   grid must not be silently reported as a zero total.
6. Integrated flows: test Seerr request -> arr hand-off, arr queue and
   history, Prowlarr application/indexer reads, download queues, Bazarr
   wanted/history, Jellyfin/Emby/Plex library/session views, TrueNAS queries,
   Unraid GraphQL reads, and NPM account/proxy/audit reads. Dockge mutations
   run against its isolated `docker:dind` sidecar, never OrbStack's daemon.
7. Write pass: run the safe mutations below. Every specimen is disposable;
   qBittorrent and Transmission are deleted, SABnzbd is restored paused,
   NZBGet is deleted from either queue or history, and the NPM flag is restored.
8. Visual matrix: repeat the route/state pass at 1440px desktop, 720px compact
   desktop and 390px portrait, each in dark and light theme. Record screenshots
   by route, state, width and theme. Phone landscape is out of contract.
   Include onboarding, deep links, retry/refresh, semantics and long text.
9. Cleanup and ledger: keep only aggregate results and screenshots under
   disposable .ai/scratch/zz_ paths, run Compose down -v --remove-orphans, and
   record branch, image digests, commands, failures and fixes in the ledger.

The existing integration_test/cupola_native_smoke_test.dart covers the real
bootstrap path from onboarding to dashboard. It is not a substitute for the
route/state/visual pass. Run it separately on a signed macOS target:

~~~bash
flutter test integration_test/cupola_native_smoke_test.dart -d macos
~~~

The reusable full matrix is
integration_test/testlab_ui_matrix_test.dart. It injects the disposable lab settings
inside a test-only ProviderScope, then visits every route root (the run reports
the count as `routes=N/M`): every ServiceTab
root, every TrueNAS section root, the global/settings roots, and deterministic
detail/editor specimens for Seerr, the arr clients, qBittorrent, Bazarr,
Prowlarr, Dockge, Jellyfin, Emby, Plex and TrueNAS. Each route is drawn at all three
sizes and both themes. The test also checks for a Flutter exception immediately
after every viewport resize, before the next route is opened; this keeps an
overflow attributed to the screen that caused it. It writes PNG evidence to
.ai/scratch/zz_testlab/screenshots:

The native runner is sandboxed away from the checkout. Use `flutter drive` with
the host-side driver below: the app process renders the PNG in memory and the
driver writes it back into the checkout, so no sandbox path or network sink is
needed. Before the command, export the disposable credentials into the test
process environment without putting them in the command line or source control:

~~~bash
set -a
. "$CUPOLA_TESTLAB_CREDENTIALS_FILE"
set +a
export CUPOLA_TESTLAB_DRIVER_SCREENSHOTS=true
export CUPOLA_TESTLAB_SCREENSHOT_DIR="$PWD/.ai/scratch/zz_testlab/screenshots"
flutter drive -d macos \
  --target=integration_test/testlab_ui_matrix_test.dart \
  --driver=test_driver/testlab_ui_matrix_driver.dart \
  --dart-define=CUPOLA_TESTLAB_SCREENSHOTS=true \
  --dart-define=CUPOLA_TESTLAB_DRIVER_SCREENSHOTS=true
~~~

The matrix saves TrueNAS as `https://127.0.0.1:8460` with the recorded
fingerprint as the trusted certificate of that origin, as a person's settings
hold it after they trust the lab's certificate; the credentials it exports
carry `CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT` with the rest. A run without it
stops before the first route and names the missing entry (every `unreachable`
run needs none: nothing is dialled).

This matrix is intentionally separate from onboarding: the native smoke test
proves the real first-run path, while the matrix makes the per-service visual
coverage repeatable without typing credentials into every run. Detail routes
use deterministic ids and therefore prove route construction, loading and
empty/error rendering even when the disposable vendor databases contain no
media. They do not claim that a populated detail card or a mutating workflow
has been certified; those require seeded records and an explicitly isolated
write pass.

The native driver report becomes unwieldy if every route is captured in one
process. Use route slices while retaining the same complete coverage (every
route x 3 sizes x 2 themes), for example:

~~~bash
export CUPOLA_TESTLAB_ROUTE_OFFSET=108
export CUPOLA_TESTLAB_ROUTE_LIMIT=8
export CUPOLA_TESTLAB_SCREENSHOT_DIR="$PWD/.ai/scratch/zz_testlab/screenshots"
flutter drive -d macos \
  --target=integration_test/testlab_ui_matrix_test.dart \
  --driver=test_driver/testlab_ui_matrix_driver.dart \
  --dart-define=CUPOLA_TESTLAB_SCREENSHOTS=true \
  --dart-define=CUPOLA_TESTLAB_DRIVER_SCREENSHOTS=true
~~~

Set `CUPOLA_TESTLAB_ROUTE_OFFSET`/`CUPOLA_TESTLAB_ROUTE_LIMIT` to successive
slices (or omit them for a no-screenshot smoke pass). Set
`CUPOLA_TESTLAB_SIZE=390x844`, `720x450` or `1440x900` to isolate one viewport.
The transport harness must pass before starting the visual matrix.

The matrix has five explicit scenarios selected with
`CUPOLA_TESTLAB_SCENARIO`: `healthy` (the default seeded lab),
`not-configured`, `degraded` (Radarr/Sonarr fail), `unreachable` (all endpoints
fail) and `invalid-auth` (valid URLs with rejected credentials). The latter is
bounded by the disposable qBittorrent seed's high failed-login threshold so a
negative-auth sweep cannot lock the lab out. `CUPOLA_TESTLAB_SETTLE_MS` controls
the provider settle window; keep the default 2000ms for evidence and use a
smaller value only for focused diagnostics.

### Verified macOS run

On 2026-09-21 the native macOS runner completed all 160 routes at 1440x900,
720x450 and 390x844 in both themes for `healthy`, `not-configured`, `degraded`,
`unreachable` and `invalid-auth`. The healthy run has 960 PNGs of evidence
(160 routes x 3 sizes x 2 themes). The transport pass reported 18 passing
checks and one explicit Plex skip because the disposable Plex image has local
authentication disabled. The write-safe pass reported five passing mutations;
all specimens were removed or restored.

The write-safe mutation tier is separate from the read-only transport and UI
passes:

~~~bash
export CUPOLA_TESTLAB_CREDENTIALS_FILE="$PWD/.ai/scratch/zz_testlab/state/credentials.env"
flutter test test/e2e/testlab_mutation_e2e_test.dart \
  --tags e2e --run-skipped
~~~

It intentionally does not mount the Docker socket into Dockge. Login,
Socket.IO and read-only stack discovery are tested; terminal and stack
deployment require an explicitly isolated socket/proxy profile.

## Cleanup

Keep the project name used by the run, then clean only that disposable project:

~~~bash
docker compose -p "$CUPOLA_TESTLAB_PROJECT" \
  -f docker-compose.testlab.yml \
  --profile core --profile downloads --profile media --profile infra \
  --profile protocol-mocks down -v --remove-orphans
~~~

The bootstrap's --reset performs the same project cleanup and removes only the
validated .ai/scratch/zz_testlab/state directory. Never use the personal Docker
socket or a broad recursive cleanup for this lab.
