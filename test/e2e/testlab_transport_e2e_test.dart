@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
import 'package:cupola/features/emby/data/emby_client.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';

/// Disposable transport smoke for the full macOS/OrbStack laboratory.
///
/// The bootstrap writes the generated Seerr/Jellyfin values to a chmod-600
/// file. Pass its path with CUPOLA_TESTLAB_CREDENTIALS_FILE; fixed passwords and
/// API keys are intentionally kept in that file too, rather than in Git.
///
/// This suite proves service reachability, authentication and the first typed
/// read used by Cupola. It is not the native visual/integration suite: a green
/// result here does not prove that a route draws the right screen.
void main() {
  final credentials = _loadCredentials();

  test('Seerr REST + session', () async {
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:5055',
      apiKey: credentials['CUPOLA_TESTLAB_SEERR_API_KEY']!,
    );
    addTearDown(client.close);
    final service = SeerrService(client);
    final me = await client.get('/api/v1/auth/me');
    expect(me.data, isA<Map>());
    expect(await service.getRadarrServers(), isNotEmpty);
    expect(await service.getSonarrServers(), isNotEmpty);
    expect((await service.getRequests()), isA<List>());
  });

  test('Radarr REST + movie parser', () async {
    final client = _arr('http://127.0.0.1:7878');
    addTearDown(client.close);
    final service = RadarrService(client);
    final status = await client.get('/api/v3/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getMoviesOrThrow(), isNotEmpty);
    expect(await service.getQueue(), isA<List>());
  });

  test('Sonarr REST + series parser', () async {
    final client = _arr('http://127.0.0.1:8989');
    addTearDown(client.close);
    final service = SonarrService(client);
    final status = await client.get('/api/v3/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getSeriesOrThrow(), isNotEmpty);
    expect(await service.getQueue(), isA<List>());
  });

  test('Lidarr REST + artist parser', () async {
    final client = _arr('http://127.0.0.1:8686');
    addTearDown(client.close);
    final service = LidarrService(client);
    final status = await client.get('/api/v1/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getArtistsOrThrow(), isNotEmpty);
    expect(await service.getQueue(), isA<List>());
  });

  test('Readarr REST + author parser', () async {
    final client = _arr('http://127.0.0.1:8787');
    addTearDown(client.close);
    final service = ReadarrService(client);
    final status = await client.get('/api/v1/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getAuthorsOrThrow(), isA<List>());
    expect(await service.getQueue(), isA<List>());
  });

  test('Prowlarr REST + indexer parser', () async {
    final client = _arr('http://127.0.0.1:9696');
    addTearDown(client.close);
    final service = ProwlarrService(client);
    final status = await client.get('/api/v1/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getHealth(), isA<List>());
    expect(await service.getIndexers(), isA<List>());
  });

  test('Bazarr REST + badges parser', () async {
    final client = _arr('http://127.0.0.1:6767');
    addTearDown(client.close);
    final service = BazarrService(client);
    final badges = await service.getBadges();
    expect(badges, isNotNull);
    expect((await service.getSeries()).data, isA<List>());
    expect((await service.getMovies()).data, isA<List>());
  });

  test('qBittorrent form auth + torrent parser', () async {
    final client = QbittorrentClient(
      url: 'http://127.0.0.1:8080',
      username: credentials['CUPOLA_TESTLAB_QBITTORRENT_USERNAME'],
      password: credentials['CUPOLA_TESTLAB_QBITTORRENT_PASSWORD'],
    );
    addTearDown(client.close);
    final service = QbittorrentService(client);
    expect(await service.authenticate(), isTrue);
    expect(await service.getVersion(), isNotEmpty);
    final first = await service.mainData();
    expect(first.torrents, isNotEmpty);
    expect(first.transfer.dlSpeed, greaterThanOrEqualTo(0));
    // The next read asks only for what changed, and still holds every torrent.
    final next = await service.mainData();
    expect(
      next.torrents.map((t) => t.hash).toSet(),
      first.torrents.map((t) => t.hash).toSet(),
    );
  });

  test('Transmission RPC auth + CSRF handshake', () async {
    final client = TransmissionClient(
      url: 'http://127.0.0.1:9091',
      username: credentials['CUPOLA_TESTLAB_TRANSMISSION_USERNAME'],
      password: credentials['CUPOLA_TESTLAB_TRANSMISSION_PASSWORD'],
    );
    addTearDown(client.close);
    expect(await client.testConnection(), isTrue);
    expect(await client.version(), isNotEmpty);
    expect(await client.torrents(), isNotEmpty);
  });

  test('SABnzbd query auth + queue parser', () async {
    final client = SabnzbdClient(
      url: 'http://127.0.0.1:8082',
      apiKey: 'test-key',
    );
    addTearDown(client.close);
    expect(await client.getVersion(), isNotEmpty);
    final queue = await client.getQueue();
    final history = await client.getHistory();
    expect(
      [
        ...queue.slots.map((slot) => slot.filename),
        ...history.map((slot) => slot.name),
      ].any((name) => name.toLowerCase().contains('cupola-test')),
      isTrue,
      reason: 'SABnzbd seed specimen',
    );
    expect((await client.getServerStats()).total, greaterThanOrEqualTo(0));
  });

  test('NZBGet Basic auth + positional JSON-RPC', () async {
    final client = NzbgetClient(
      url: 'http://127.0.0.1:6789',
      username: credentials['CUPOLA_TESTLAB_NZBGET_USERNAME'],
      password: credentials['CUPOLA_TESTLAB_NZBGET_PASSWORD'],
    );
    addTearDown(client.close);
    expect(await client.testConnection(), isTrue);
    expect(await client.version(), isNotEmpty);
    expect(await client.status(), isNotNull);
    final groups = await client.listGroups();
    final history = await client.history();
    expect(
      [
        ...groups.map((item) => item.name),
        ...history.map((item) => item.name),
      ].any((name) => name.toLowerCase().contains('cupola-test')),
      isTrue,
      reason: 'NZBGet seed specimen',
    );
  });

  test('Jellyfin token auth + library parser', () async {
    final client = JellyfinClient(
      baseUrl: 'http://127.0.0.1:8096',
      apiKey: credentials['CUPOLA_TESTLAB_JELLYFIN_TOKEN']!,
      userId: credentials['CUPOLA_TESTLAB_JELLYFIN_USER_ID']!,
      deviceName: 'Cupola TestLab E2E',
      deviceId: 'cupola-testlab-e2e',
    );
    addTearDown(client.close);
    expect(await client.verifyCredential(), isTrue);
    expect(await client.probeVersion(), isNotEmpty);
    expect(await client.getLibraries(), isNotEmpty);
    expect(await client.getSessions(), isA<List>());
  });

  test('Emby API key auth + library parser', () async {
    final client = EmbyClient(
      baseUrl: 'http://127.0.0.1:8097',
      apiKey: credentials['CUPOLA_TESTLAB_EMBY_TOKEN']!,
      userId: credentials['CUPOLA_TESTLAB_EMBY_USER_ID']!,
    );
    addTearDown(client.close);
    expect(await client.verifyCredential(), isTrue);
    expect(await client.probeVersion(), isNotEmpty);
    expect(await client.getLibraries(), isNotEmpty);
    expect(await client.getSessions(), isA<List>());
  });

  test('Tracearr public key auth + version + servers parser', () async {
    final client = TracearrClient(
      baseUrl: 'http://127.0.0.1:3010',
      apiKey: credentials['CUPOLA_TESTLAB_TRACEARR_KEY']!,
    );
    addTearDown(client.close);
    final health = await client.checkCredentialAndVersion();
    expect(health.isOk, isTrue);
    expect(health.version, startsWith('v'));
    expect((await client.getServers()).servers, isNotEmpty);
    expect(await client.getStreams(), isNotNull);
  });

  test('Plex token auth + identity parser', () async {
    final client = PlexClient(
      url: 'http://127.0.0.1:32400',
      token: credentials['CUPOLA_TESTLAB_PLEX_TOKEN']!,
      clientIdentifier: 'cupola-testlab-e2e',
    );
    addTearDown(client.close);
    expect(await client.verifyCredential(), isTrue);
    expect(await client.probeVersion(), isNotEmpty);
    expect(await client.getIdentity(), isNotNull);
    expect(await client.getLibraries(), isNotEmpty);
    // A real server filters `?guid=` on its own guid only: the external id
    // reaches the title through the server's matcher. Needs the server online
    // to Plex's metadata, and The Matrix in its Films library.
    final lookup = await client.lookupByExternalId(
      tmdbId: '603',
      kind: StreamItemKind.movie,
    );
    expect(lookup.outcome, StreamLookupOutcome.found, reason: 'Plex');
    expect(lookup.item?.title, 'The Matrix');
  });

  test('Dockge Socket.IO login + stack list', () async {
    final client = DockgeClient(
      baseUrl: 'http://127.0.0.1:5001',
      username: credentials['CUPOLA_TESTLAB_DOCKGE_USERNAME'],
      password: credentials['CUPOLA_TESTLAB_DOCKGE_PASSWORD'],
    );
    addTearDown(client.close);
    final service = DockgeService(client);
    // Dockge installations may omit the optional version field while still
    // accepting the authenticated Socket.IO session.
    await service.fetchVersion();
    expect(await service.fetchStacks(), isA<List>());
  });

  test('Nginx Proxy Manager login + proxy host parser', () async {
    final client = NpmClient(
      url: 'http://127.0.0.1:8181',
      identity: credentials['CUPOLA_TESTLAB_NPM_USERNAME'],
      secret: credentials['CUPOLA_TESTLAB_NPM_PASSWORD'],
    );
    addTearDown(client.close);
    expect(await client.testConnection(), isTrue);
    expect(await client.version(), isNotEmpty);
    expect(await client.proxyHosts(), isNotEmpty);
    expect(await client.auditLog(), isA<List>());
  });

  test('TrueNAS WebSocket JSON-RPC over TLS + dashboard parser', () async {
    // The address a person saves: https://, with the self-signed certificate
    // trusted by its fingerprint. The client dials wss:// from it.
    final client = TrueNasWsClient(
      baseUrl: _truenasUrl,
      apiKey: 'test-key',
      certFingerprint: _truenasPin(credentials),
    );
    addTearDown(client.close);
    expect(client.resolveEndpoint().scheme, 'wss');
    final service = TrueNasService(client);
    expect(await service.ping(), isTrue);
    final dashboard = await service.loadDashboard();
    expect(dashboard.system.hostname, isNotEmpty);
    expect(dashboard.pools, isA<List>());
  });

  test(
    'TrueNAS certificate probe reads the fingerprint the lab recorded',
    () async {
      // The trust prompt on "Test connection" shows what this probe reads, and a
      // person's saved pin is that same text: the bootstrap's must be too.
      final certificate = await probeServerCertificate(
        '127.0.0.1',
        _truenasPort,
      );
      expect(certificate, isNotNull);
      expect(certificate!.fingerprint, _truenasPin(credentials));
    },
  );

  test('TrueNAS refuses a certificate it was not told to trust as untrusted, '
      'not as a dead server', () async {
    final pin = _truenasPin(credentials);
    // The server is there and answers: the same address, with its own pin.
    final trusted = TrueNasWsClient(
      baseUrl: _truenasUrl,
      apiKey: 'test-key',
      certFingerprint: pin,
    );
    addTearDown(trusted.close);
    expect(await TrueNasService(trusted).ping(), isTrue);

    // A pin that is one digit off: a certificate that was replaced after the
    // person trusted the old one. Never sent a key, never read as a dead host.
    final rotated = TrueNasWsClient(
      baseUrl: _truenasUrl,
      apiKey: 'test-key',
      certFingerprint: _oneDigitOff(pin),
    );
    addTearDown(rotated.close);
    await _expectUntrusted(
      TrueNasService(rotated).ping(),
      'a pin one digit off',
    );

    // No pin at all: the platform's trust store does not know the lab's
    // self-signed certificate, and nothing makes an exception for it.
    final unpinned = TrueNasWsClient(baseUrl: _truenasUrl, apiKey: 'test-key');
    addTearDown(unpinned.close);
    await _expectUntrusted(TrueNasService(unpinned).ping(), 'no pin');

    // The contrast: where nothing listens, the same code reads unreachable.
    final dead = TrueNasWsClient(
      baseUrl: 'https://127.0.0.1:${await _closedPort()}',
      apiKey: 'test-key',
      certFingerprint: pin,
    );
    addTearDown(dead.close);
    await expectLater(
      TrueNasService(dead).ping(),
      throwsA(
        isA<TrueNasException>().having(
          (error) => classifyConnectionFailure(error),
          'reason',
          ServiceFailureReason.unreachable,
        ),
      ),
      reason: 'a port nothing listens on',
    );
  });

  test('Unraid GraphQL + dashboard parsers', () async {
    final client = UnraidClient(
      url: 'http://127.0.0.1:8480',
      apiKey: 'test-key',
    );
    addTearDown(client.close);
    expect(await client.testConnection(), isTrue);
    expect((await client.getArray()).state, isNotEmpty);
    expect(await client.getDockerContainers(), isA<List>());
    expect(await client.getNotifications(), isNotNull);
  });

  test('wrong credentials are rejected by every auth transport', () async {
    final apiKeyCases = <Map<String, String>>[
      {
        'name': 'Seerr',
        'url': 'http://127.0.0.1:5055',
        'path': '/api/v1/auth/me',
      },
      {
        'name': 'Radarr',
        'url': 'http://127.0.0.1:7878',
        'path': '/api/v3/system/status',
      },
      {
        'name': 'Sonarr',
        'url': 'http://127.0.0.1:8989',
        'path': '/api/v3/system/status',
      },
      {
        'name': 'Lidarr',
        'url': 'http://127.0.0.1:8686',
        'path': '/api/v1/system/status',
      },
      {
        'name': 'Readarr',
        'url': 'http://127.0.0.1:8787',
        'path': '/api/v1/system/status',
      },
      {
        'name': 'Prowlarr',
        'url': 'http://127.0.0.1:9696',
        'path': '/api/v1/system/status',
      },
      {'name': 'Bazarr', 'url': 'http://127.0.0.1:6767', 'path': '/api/badges'},
    ];
    for (final item in apiKeyCases) {
      final client = ApiClient(baseUrl: item['url']!, apiKey: 'wrong-key');
      addTearDown(client.close);
      await expectLater(
        client.get(item['path']!),
        throwsA(anything),
        reason: item['name'],
      );
    }

    final qbit = QbittorrentClient(
      url: 'http://127.0.0.1:8080',
      username: credentials['CUPOLA_TESTLAB_QBITTORRENT_USERNAME'],
      password: 'wrong-password',
    );
    addTearDown(qbit.close);
    expect(await qbit.authenticate(), isFalse, reason: 'qBittorrent');

    final transmission = TransmissionClient(
      url: 'http://127.0.0.1:9091',
      username: credentials['CUPOLA_TESTLAB_TRANSMISSION_USERNAME'],
      password: 'wrong-password',
    );
    addTearDown(transmission.close);
    await expectLater(
      transmission.testConnection(),
      throwsA(anything),
      reason: 'Transmission',
    );

    final sabnzbd = SabnzbdClient(
      url: 'http://127.0.0.1:8082',
      apiKey: 'wrong-key',
    );
    addTearDown(sabnzbd.close);
    await expectLater(
      sabnzbd.testConnection(),
      throwsA(anything),
      reason: 'SABnzbd',
    );

    final nzbget = NzbgetClient(
      url: 'http://127.0.0.1:6789',
      username: credentials['CUPOLA_TESTLAB_NZBGET_USERNAME'],
      password: 'wrong-password',
    );
    addTearDown(nzbget.close);
    await expectLater(
      nzbget.testConnection(),
      throwsA(anything),
      reason: 'NZBGet',
    );

    final jellyfin = JellyfinClient(
      baseUrl: 'http://127.0.0.1:8096',
      apiKey: 'wrong-token',
      userId: credentials['CUPOLA_TESTLAB_JELLYFIN_USER_ID']!,
      deviceName: 'Cupola TestLab invalid-auth probe',
      deviceId: 'cupola-testlab-invalid-auth',
    );
    addTearDown(jellyfin.close);
    expect(await jellyfin.verifyCredential(), isFalse, reason: 'Jellyfin');

    final emby = EmbyClient(
      baseUrl: 'http://127.0.0.1:8097',
      apiKey: 'wrong-token',
      userId: credentials['CUPOLA_TESTLAB_EMBY_USER_ID']!,
    );
    addTearDown(emby.close);
    expect(await emby.verifyCredential(), isFalse, reason: 'Emby');

    final tracearr = TracearrClient(
      baseUrl: 'http://127.0.0.1:3010',
      apiKey: 'trr_pub_wrong-token',
    );
    addTearDown(tracearr.close);
    await expectLater(
      tracearr.checkCredentialAndVersion(),
      throwsA(anything),
      reason: 'Tracearr',
    );

    final dockge = DockgeClient(
      baseUrl: 'http://127.0.0.1:5001',
      username: credentials['CUPOLA_TESTLAB_DOCKGE_USERNAME'],
      password: 'wrong-password',
    );
    addTearDown(dockge.close);
    await expectLater(dockge.ping(), throwsA(anything), reason: 'Dockge');

    final npm = NpmClient(
      url: 'http://127.0.0.1:8181',
      identity: credentials['CUPOLA_TESTLAB_NPM_USERNAME'],
      secret: 'wrong-password',
    );
    addTearDown(npm.close);
    await expectLater(
      npm.testConnection(),
      throwsA(anything),
      reason: 'Nginx Proxy Manager',
    );

    // Past the certificate, with the right pin: the refusal is the key's.
    final truenas = TrueNasWsClient(
      baseUrl: _truenasUrl,
      apiKey: 'wrong-key',
      certFingerprint: _truenasPin(credentials),
    );
    addTearDown(truenas.close);
    await expectLater(
      TrueNasService(truenas).ping(),
      throwsA(
        isA<TrueNasException>().having(
          (error) => classifyConnectionFailure(error),
          'reason',
          ServiceFailureReason.unauthorized,
        ),
      ),
      reason: 'TrueNAS',
    );

    final unraid = UnraidClient(
      url: 'http://127.0.0.1:8480',
      apiKey: 'wrong-key',
    );
    addTearDown(unraid.close);
    await expectLater(
      unraid.testConnection(),
      throwsA(anything),
      reason: 'Unraid',
    );
  });

  test('Plex wrong-token probe is explicit when auth is disabled', () async {
    final client = PlexClient(
      url: 'http://127.0.0.1:32400',
      token: 'wrong-token',
      clientIdentifier: 'cupola-testlab-invalid-auth',
    );
    addTearDown(client.close);
    final accepted = await client.verifyCredential();
    if (accepted) {
      markTestSkipped(
        'The disposable Plex container is running with local authentication '
        'disabled; a wrong token cannot be rejected. Use a claimed/authenticated '
        'Plex server to verify token rejection.',
      );
      return;
    }
    expect(accepted, isFalse, reason: 'Plex');
  });
}

ApiClient _arr(String baseUrl) =>
    ApiClient(baseUrl: baseUrl, apiKey: 'test-key');

const _truenasPort = 8460;

/// TrueNAS as a person saves it. The client derives `wss://` from it.
const _truenasUrl = 'https://127.0.0.1:$_truenasPort';

/// The fingerprint the bootstrap recorded for the TrueNAS mock's certificate:
/// 64 lowercase hex digits, the form `certFingerprint` compares.
String _truenasPin(Map<String, String> credentials) {
  final pin = credentials['CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT'];
  if (pin == null || pin.isEmpty) {
    fail(
      'Missing CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT in the lab credentials: '
      'run test/e2e/testlab/truenas_cert.sh credentials (see test/e2e/README.md)',
    );
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)) {
    fail(
      'CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT must be 64 lowercase hex digits '
      'without colons, the SHA-256 of the certificate',
    );
  }
  return pin;
}

/// [pin] with its first digit changed, still a well-formed fingerprint.
String _oneDigitOff(String pin) =>
    '${pin.startsWith('0') ? '1' : '0'}${pin.substring(1)}';

/// A loopback port nothing listens on: bound a moment ago, then released.
Future<int> _closedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// [call] fails the way a certificate the app does not trust fails: a TLS
/// refusal, classified [ServiceFailureReason.tls] and nothing else. Not
/// unreachable (the server answered the handshake), not a refused key (no key
/// was sent), not the cleartext refusal (the address was dialled).
Future<void> _expectUntrusted(Future<Object?> call, String reason) =>
    expectLater(
      call,
      throwsA(
        isA<TrueNasException>()
            .having(
              (error) => classifyConnectionFailure(error),
              'reason',
              ServiceFailureReason.tls,
            )
            .having(
              (error) => error is TrueNasInsecureTransportException,
              'refused as cleartext',
              isFalse,
            ),
      ),
      reason: reason,
    );

Map<String, String> _loadCredentials() {
  final path = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
  if (path == null || path.isEmpty) {
    fail(
      'CUPOLA_TESTLAB_CREDENTIALS_FILE must point to the bootstrap output '
      '(.ai/scratch/zz_testlab/state/credentials.env)',
    );
  }
  final file = File(path);
  if (!file.existsSync()) fail('Missing testlab credentials file: $path');
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return values;
}
