@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../test_helpers/fake_secure_settings_store.dart';

/// The app's configuration for a profile, read by the app's own code.
///
/// The lab writes that configuration into its state directory, in the app's
/// own storage: the addresses, the names and the roster in
/// `SharedPreferences`, the keys, the passwords, the tokens and the sessions
/// in the secure storage, with the keys `SettingsService` derives from the id
/// of every connection. This suite proves that what the lab wrote is what
/// the app reads:
///
/// * the connections of P1, with the lab's addresses and the lab's keys;
/// * the address away from home of P7, the second listener of the Toxiproxy,
///   and the route that reaches it;
/// * the gateway of P8, with what each connection presents to it;
/// * a connection that does not exist, which the app must declare not set up
///   rather than pretend.
///
/// The configuration is written by `testlab.py app-config <profile>`, which
/// this suite runs: the file it leaves behind is the one the app-side writer
/// hands to the app's stores, and the reader here is the app's own
/// `SettingsService`.
void main() {
  late Map<String, String> credentials;

  setUpAll(() {
    credentials = _loadCredentials();
  });

  test('the command writes the configuration of a profile', () async {
    final document = await _writeConfiguration('P1');

    expect(document['profile'], 'P1');
    expect(document['bundleId'], 'com.matthwlabs.cupola.testlab');
    expect(document['stores'], {
      'prefs': 'SharedPreferences',
      'secure': 'flutter_secure_storage',
    });

    final file = File(_statePath('app/P1.json'));
    expect(file.existsSync(), isTrue, reason: 'the configuration is missing');
    expect(
      file.statSync().mode & 0x1FF,
      0x180,
      reason: 'the configuration holds the keys of the lab: 0600',
    );

    final prefs = document['prefs'] as Map;
    final secure = document['secure'] as Map;
    expect(prefs['radarr_url'], 'http://127.0.0.1:27878');
    expect(prefs['onboarding_complete'], isTrue);
    expect(secure.containsKey('secure_radarr_api_key'), isTrue);
    expect(secure.containsKey('secure_trusted_certificates'), isTrue);

    final roster = jsonDecode(prefs['service_instances']! as String) as List;
    expect(roster, hasLength(12));
    expect(roster.map((row) => (row as Map)['id']), [
      'seerr',
      'jellyfin',
      'radarr',
      'radarr-4k00001',
      'sonarr',
      'lidarr',
      'bazarr',
      'prowlarr',
      'qbittorrent',
      'sabnzbd',
      'truenas',
      'dockge',
    ]);
  });

  test('the app reads the connections and the keys of P1', () async {
    final document = await _writeConfiguration('P1');
    final app = await _readWithTheApp(document);
    final settings = app.settings;

    expect(settings.instances.map((instance) => instance.id), [
      'seerr',
      'jellyfin',
      'radarr',
      'radarr-4k00001',
      'sonarr',
      'lidarr',
      'bazarr',
      'prowlarr',
      'qbittorrent',
      'sabnzbd',
      'truenas',
      'dockge',
    ]);

    expect(settings.instanceById('radarr')!.url, 'http://127.0.0.1:27878');
    expect(settings.instanceById('sonarr')!.url, 'http://127.0.0.1:28989');
    expect(settings.instanceById('jellyfin')!.url, 'http://127.0.0.1:28096');
    expect(settings.instanceById('truenas')!.url, 'https://127.0.0.1:28460');
    expect(
      settings.instanceById('radarr-4k00001')!.url,
      'https://127.0.0.1:8444',
      reason: 'the second Radarr is the edge, the origin with its certificate',
    );
    expect(settings.instanceById('radarr-4k00001')!.label, '4K');

    // The keys the lab holds, read by the app as the connection's own.
    expect(
      settings.instanceById('seerr')!.credential,
      credentials['CUPOLA_TESTLAB_SEERR_API_KEY'],
    );
    expect(
      settings.instanceById('jellyfin')!.credential,
      credentials['CUPOLA_TESTLAB_JELLYFIN_TOKEN'],
    );
    expect(
      settings.instanceById('jellyfin')!.viewerId,
      credentials['CUPOLA_TESTLAB_JELLYFIN_USER_ID'],
    );
    expect(settings.instanceById('plex'), isNull, reason: 'P1 has no Plex');
    expect(
      settings.instanceById('qbittorrent')!.username,
      credentials['CUPOLA_TESTLAB_QBITTORRENT_USERNAME'],
    );
    expect(settings.instanceById('radarr')!.credential, isNotEmpty);

    // The certificate the TrueNAS fixture speaks TLS with, pinned by its
    // origin, and the one of the edge.
    expect(
      settings.trustedCertificates['https://127.0.0.1:28460'],
      credentials['CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT'],
    );
    expect(
      settings.trustedCertificates['https://127.0.0.1:8444'],
      isNotEmpty,
      reason: 'the edge presents a certificate of its own',
    );
  });

  test('the app reads Emby beside Jellyfin in P10', () async {
    final document = await _writeConfiguration('P10');
    final app = await _readWithTheApp(document);
    final settings = app.settings;

    expect(settings.instances.map((instance) => instance.id), [
      'seerr',
      'jellyfin',
      'emby',
    ]);
    final emby = settings.instanceById('emby')!;
    expect(emby.service, ServiceKey.emby);
    expect(emby.url, 'http://127.0.0.1:28098');
    // The API key, which no user owns, and the administrator the app reads
    // the server as: the same two facts the connection form saves.
    expect(emby.credential, credentials['CUPOLA_TESTLAB_EMBY_TOKEN']);
    expect(emby.viewerId, credentials['CUPOLA_TESTLAB_EMBY_USER_ID']);
    expect(settings.isServiceConfigured(ServiceKey.emby), isTrue);
    expect(
      settings.instanceById('jellyfin')!.viewerId,
      credentials['CUPOLA_TESTLAB_JELLYFIN_USER_ID'],
      reason: 'each media server keeps the viewer of its own',
    );
  });

  test('a service the profile does not have reads as not set up', () async {
    final document = await _writeConfiguration('P2');
    final app = await _readWithTheApp(document);
    final settings = app.settings;

    expect(settings.instances, hasLength(1));
    expect(settings.instances.single.service, ServiceKey.seerr);

    for (final service in ServiceKey.values) {
      if (service == ServiceKey.seerr) continue;
      expect(
        settings.isServiceConfigured(service),
        isFalse,
        reason: '${service.title} is not in P2: the app must say so',
      );
      expect(
        () => _transport(settings, service).ensureConfigured(service),
        throwsA(
          isA<ServiceNotConfigured>().having(
            (error) => error.service,
            'service',
            service,
          ),
        ),
        reason: '${service.title} must be refused, not faked',
      );
    }
  });

  test('a connection whose key is missing reads as not set up', () async {
    final document = await _writeConfiguration('P1');
    final secure = Map<String, dynamic>.from(document['secure'] as Map)
      ..remove('secure_sabnzbd_api_key');
    final missing = Map<String, dynamic>.from(document)..['secure'] = secure;

    final file = File(_statePath('app/P1-no-key.json'))
      ..writeAsStringSync(jsonEncode(missing));
    await Process.run('chmod', ['600', file.path]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    final app = await _readWithTheApp(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );

    expect(app.settings.instanceById('sabnzbd')!.url, isNotEmpty);
    expect(app.settings.isServiceConfigured(ServiceKey.sabnzbd), isFalse);
    expect(
      () => _transport(
        app.settings,
        ServiceKey.sabnzbd,
      ).ensureConfigured(ServiceKey.sabnzbd),
      throwsA(isA<ServiceNotConfigured>()),
    );
    expect(
      app.settings.isServiceConfigured(ServiceKey.radarr),
      isTrue,
      reason: 'the other connections are untouched',
    );
  });

  test('P7 reaches its servers at the address away from home', () async {
    final document = await _writeConfiguration('P7');
    final app = await _readWithTheApp(document);
    final settings = app.settings;

    final radarr = settings.instanceById('radarr')!;
    expect(radarr.url, 'http://127.0.0.1:27878');
    expect(
      radarr.away?.url,
      'http://127.0.0.1:27879',
      reason: 'the away address is the second listener of the proxy',
    );
    expect(
      reachOf(settings, radarr, ConnectionRoute.away).url,
      'http://127.0.0.1:27879',
    );
    expect(
      reachOf(settings, radarr, ConnectionRoute.home).url,
      'http://127.0.0.1:27878',
    );
    expect(
      app.service.loadConnectionRoutes()['radarr'],
      ConnectionRoute.away,
      reason: 'the route the app kept says away',
    );

    // The connections the world keeps at home carry no address away.
    for (final id in ['lidarr', 'prowlarr', 'sabnzbd', 'truenas', 'dockge']) {
      expect(
        settings.instanceById(id)!.away,
        isNull,
        reason: '$id only works at home',
      );
    }
  });

  test('P8 reaches the gateway with what each connection presents', () async {
    final document = await _writeConfiguration('P8');
    final app = await _readWithTheApp(document);
    final settings = app.settings;

    final radarr = settings.instanceById('radarr')!;
    expect(radarr.url, 'http://127.0.0.1:8466/cf');
    expect(radarr.access, isA<CloudflareServiceToken>());
    final token = radarr.access as CloudflareServiceToken;
    expect(token.clientId, 'cupola-testlab-client-id');
    expect(token.clientSecret, 'cupola-testlab-client-secret');
    expect(token.headers(), {
      'CF-Access-Client-Id': 'cupola-testlab-client-id',
      'CF-Access-Client-Secret': 'cupola-testlab-client-secret',
    });

    final sonarr = settings.instanceById('sonarr')!;
    expect(sonarr.url, 'http://127.0.0.1:8466/cf');
    expect(
      sonarr.access,
      isA<NoAccess>(),
      reason: 'Sonarr presents no token: the gateway asks for one',
    );

    final seerr = settings.instanceById('seerr')!;
    expect(seerr.url, 'http://127.0.0.1:8466/cf-refused');
    expect(seerr.access, isA<CloudflareServiceToken>());
  });

  test('the configuration the app reads is the one the lab answers', () async {
    final document = await _writeConfiguration('P1');
    final app = await _readWithTheApp(document);
    final settings = app.settings;

    final radarr = settings.instanceById('radarr')!;
    final client = ApiClient(baseUrl: radarr.url, apiKey: radarr.credential);
    addTearDown(client.close);
    final status = await client.get('/api/v3/system/status');
    expect(status.statusCode, 200);
    expect(status.data, isA<Map>());

    final seerr = settings.instanceById('seerr')!;
    final seerrClient = ApiClient(baseUrl: seerr.url, apiKey: seerr.credential);
    addTearDown(seerrClient.close);
    final seerrStatus = await seerrClient.get('/api/v1/status');
    expect(seerrStatus.statusCode, 200);
  });

  test('the gateway refuses the token of P8, and the app says so', () async {
    final document = await _writeConfiguration('P8');
    final app = await _readWithTheApp(document);
    final seerr = app.settings.instanceById('seerr')!;

    final client = ApiClient(
      baseUrl: seerr.url,
      apiKey: seerr.credential,
      accessHeaders: seerr.access.headers(),
    );
    addTearDown(client.close);

    Object? failure;
    try {
      await client.get('/');
    } catch (error) {
      failure = error;
    }
    expect(failure, isNotNull, reason: 'the gateway refused the token');
    final answer = accessGatewayOf(failure!);
    expect(answer, isNotNull, reason: 'the refusal is not recognised');
    expect(answer!.kind, AccessGatewayKind.cloudflareAccess);
    expect(answer.credentialsSent, isTrue);
  });
}

/// The app's own transport for [service], as the providers build it.
ServiceTransport _transport(SettingsModel settings, ServiceKey service) {
  final instance = settings.primaryOf(service);
  return (
    configured: settings.isServiceConfigured(service),
    url: instance?.url ?? '',
    apiKey: instance?.credential ?? '',
    username: instance?.username ?? '',
    pin: settings.pinForUrl(instance?.url ?? ''),
    access: instance?.access ?? const NoAccess(),
    session: instance?.account?.session ?? '',
    instanceId: instance?.id ?? '',
    onlyAtHome: false,
  );
}

/// The configuration of [profile], as the lab wrote it.
Future<Map<String, dynamic>> _writeConfiguration(String profile) async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/testlab.py',
    'app-config',
    profile,
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'the command failed: ${result.stdout}${result.stderr}',
  );
  final file = File(_statePath('app/$profile.json'));
  expect(file.existsSync(), isTrue, reason: 'the configuration is missing');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// The configuration, read by the app's own `SettingsService`.
Future<_App> _readWithTheApp(Map<String, dynamic> document) async {
  final prefs = <String, Object>{};
  for (final entry in (document['prefs'] as Map).entries) {
    prefs[entry.key as String] = entry.value as Object;
  }
  SharedPreferences.setMockInitialValues(prefs);

  final store = FakeSecureSettingsStore();
  for (final entry in (document['secure'] as Map).entries) {
    await store.write(key: entry.key as String, value: entry.value as String);
  }

  final service = SettingsService(await SharedPreferences.getInstance(), store);
  return _App(service, await service.loadSettings());
}

/// Where the lab keeps its state.
String _statePath(String relative) {
  final root =
      Platform.environment['CUPOLA_TESTLAB_STATE_DIR'] ??
      '.ai/scratch/zz_testlab/state';
  return '$root/$relative';
}

/// The lab's secrets, from the bootstrap's file.
Map<String, String> _loadCredentials() {
  final path =
      Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'] ??
      _statePath('credentials.env');
  final file = File(path);
  if (!file.existsSync()) {
    fail(
      'The lab credentials are missing: $path. Run '
      'test/e2e/testlab/bootstrap.sh, or point '
      'CUPOLA_TESTLAB_CREDENTIALS_FILE at the file.',
    );
  }
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return values;
}

/// The service and the settings, as the app read them.
class _App {
  _App(this.service, this.settings);

  final SettingsService service;
  final SettingsModel settings;
}
