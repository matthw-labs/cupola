/// The harness the journeys of the testlab share.
///
/// Three jobs, and nothing else:
///
/// 1. **Point the app at the lab.** The real Seerr, the real Radarr, the
///    addresses the lab publishes and the keys the lab's own state holds.
///    Every secret is read at run time from the disposable file the
///    bootstrap wrote, or from the services' own configuration: none of them
///    is written here, and none of them is ever printed.
/// 2. **Bring the app back to a known state** before every journey: a fresh
///    container, empty preferences, the connections the profile asks for, and
///    a session of its own for the household member the journey speaks for.
/// 3. **Say what the surface drew** next to **what the server says**: the
///    first is read off the widget tree, the second off the service's own
///    API. A journey that only proved the second would prove nothing about
///    the app.
///
/// The lab's own rules, kept here:
///
/// - The app talks to the **proxy ports**, so the fault layer is in the way
///   as it is in every other journey. The readings talk to the services
///   **directly**, so a fact about the server never depends on the faults.
/// - The app's state is **rebuilt** for every journey (a new container, new
///   preferences, new connections), and the data a journey leaves on the
///   server is **deleted by the journey itself** through the same API the
///   app used to write it. What the lab's world holds is never touched: the
///   world's own requests, its people and its watchlist stay as the seed
///   left them.
///
/// ## How a journey is run
///
/// ~~~bash
/// xcrun simctl boot 403B5E0A-6A4E-4CB4-A151-87A6DA34E55F   # Cupola Testlab
/// flutter test `integration_test/journeys/<journey>.dart` \
///   -d 403B5E0A-6A4E-4CB4-A151-87A6DA34E55F --tags e2e --run-skipped
/// ~~~
///
/// The `e2e` tag is the tier that drives the real services, and the repo
/// skips it by default: without `--tags e2e --run-skipped` the journey is
/// skipped and the run says so.
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/data/seerr_auth_service.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/main.dart' as cupola;

import '../../test/test_helpers/settings_scope.dart';

/// The lab's addresses: what the app talks to, and what the readings read.
///
/// The app goes through the fault layer (the proxy ports), so a journey
/// sees the lab as a person would. The readings go straight to the service,
/// so the fact they report is the service's and not the fault layer's.
class LabEndpoints {
  /// The household Seerr, through the fault layer.
  static const seerr = 'http://127.0.0.1:25055';

  /// Radarr, through the fault layer.
  static const radarr = 'http://127.0.0.1:27878';

  /// Sonarr, through the fault layer.
  static const sonarr = 'http://127.0.0.1:28989';

  /// The household Seerr, straight to the service.
  static const seerrDirect = 'http://127.0.0.1:5055';

  /// Radarr, straight to the service.
  static const radarrDirect = 'http://127.0.0.1:7878';

  /// Sonarr, straight to the service.
  static const sonarrDirect = 'http://127.0.0.1:8989';

  /// Every service the lab runs, with the port the **app** reaches it at
  /// (the proxy) and the port a **reading** reaches it at (the service).
  ///
  /// The next families (the media servers, the infrastructure) take their
  /// services from here, so no journey has to spell an address again.
  static const Map<ServiceKey, ({int proxy, int direct})> ports = {
    ServiceKey.seerr: (proxy: 25055, direct: 5055),
    ServiceKey.radarr: (proxy: 27878, direct: 7878),
    ServiceKey.sonarr: (proxy: 28989, direct: 8989),
    ServiceKey.lidarr: (proxy: 28686, direct: 8686),
    ServiceKey.readarr: (proxy: 28787, direct: 8787),
    ServiceKey.prowlarr: (proxy: 29696, direct: 9696),
    ServiceKey.bazarr: (proxy: 26767, direct: 6767),
    // Through the fault layer on the WebUI's own port, so qBittorrent accepts
    // the Host the app sends; read directly on another published port (see
    // docker-compose.testlab.yml), with the Host its WebUI expects.
    ServiceKey.qbittorrent: (proxy: 8080, direct: 18080),
    ServiceKey.transmission: (proxy: 29091, direct: 9091),
    ServiceKey.sabnzbd: (proxy: 28082, direct: 8082),
    ServiceKey.nzbget: (proxy: 26789, direct: 6789),
    ServiceKey.jellyfin: (proxy: 28096, direct: 8096),
    ServiceKey.emby: (proxy: 28098, direct: 8097),
    ServiceKey.plex: (proxy: 23240, direct: 32400),
    ServiceKey.dockge: (proxy: 25001, direct: 5001),
    ServiceKey.nginxProxyManager: (proxy: 28181, direct: 8181),
    ServiceKey.truenas: (proxy: 28460, direct: 8460),
    ServiceKey.unraid: (proxy: 28480, direct: 8480),
  };

  /// The address the app reaches [service] at, through the fault layer.
  ///
  /// TrueNAS is the one service the lab serves over TLS with its own
  /// certificate; the fault layer forwards the TLS stream untouched, so the
  /// scheme and the pin are the upstream's.
  static String appUrlOf(ServiceKey service) {
    final scheme = service == ServiceKey.truenas ? 'https' : 'http';
    return '$scheme://127.0.0.1:${ports[service]!.proxy}';
  }

  /// The address a reading reaches [service] at, straight to the service.
  static String directUrlOf(ServiceKey service) {
    final scheme = service == ServiceKey.truenas ? 'https' : 'http';
    return '$scheme://127.0.0.1:${ports[service]!.direct}';
  }
}

/// The lab's own secrets, read from the disposable file the bootstrap wrote.
///
/// The file is 0600, lives in the lab's state, and is never committed. The
/// harness reads it, and never writes a value of it anywhere but the app's
/// own settings (in memory, for the length of a journey).
class LabCredentials {
  LabCredentials(this.values, this.path);

  final Map<String, String> values;

  /// Where the file was found, for the failure messages.
  final String path;

  /// The value of [name], or a failure that says how to get it.
  String require(String name) {
    final value = values[name]?.trim();
    if (value == null || value.isEmpty) {
      fail(
        'The lab credentials at $path have no $name. Run the bootstrap again, '
        'or point CUPOLA_TESTLAB_CREDENTIALS_FILE at another file.',
      );
    }
    return value;
  }

  /// The value of [name], or null when the lab did not write one.
  String? optional(String name) {
    final value = values[name]?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// The operator's key on the household Seerr.
  String get seerrApiKey => require('CUPOLA_TESTLAB_SEERR_API_KEY');

  /// The control plane of the lab, when it is running.
  String? get controlUrl => optional('CUPOLA_TESTLAB_CONTROL_URL');

  String? get controlToken => optional('CUPOLA_TESTLAB_CONTROL_TOKEN');

  /// The directory the credentials file lives in: the lab's state.
  String get stateDir {
    final separator = path.lastIndexOf('/');
    return separator <= 0 ? '.' : path.substring(0, separator);
  }

  /// The file, wherever it is: the one the environment names, the one under
  /// the working directory (a run on the host), or the one of the checkout
  /// the app was built from (a run on a simulator).
  ///
  /// The simulator's app sees the host's disk, but not the host's
  /// environment: the app is launched by the simulator, which gives it the
  /// device's own environment and nothing else. The path is therefore found
  /// on the disk, from the app's own place in the device's container, which
  /// is a directory of the host.
  static LabCredentials load() {
    for (final file in _candidateFiles()) {
      final values = _parse(file);
      if (values.isEmpty) continue;
      return LabCredentials(values, file.path);
    }
    fail(
      'The lab credentials were not found. Point '
      'CUPOLA_TESTLAB_CREDENTIALS_FILE at the file the bootstrap wrote '
      '($defaultCredentialsPath), or run the journey from the checkout that '
      'holds the lab.',
    );
  }

  /// The file the bootstrap writes, in the checkout that started the lab.
  static const defaultCredentialsPath =
      '.ai/scratch/zz_testlab/state/credentials.env';

  static List<File> _candidateFiles() {
    final files = <File>[];
    final named = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
    if (named != null && named.isNotEmpty) files.add(File(named));
    files.add(File(defaultCredentialsPath));
    for (final state in _candidateStateDirs()) {
      files.add(File('$state/credentials.env'));
    }
    return files;
  }

  /// The state directory a run names, then the ones found under the host's
  /// home: the checkouts in `~/Documents/Dev`.
  ///
  /// A checkout or worktree elsewhere names the lab's state with
  /// `CUPOLA_TESTLAB_STATE_DIR` (the main checkout's
  /// `.ai/scratch/zz_testlab/state`). A run on the host reads it from the
  /// environment; a run on a simulator cannot see the host's environment, so
  /// it passes the same value with `--dart-define`.
  static List<String> _candidateStateDirs() {
    final named = _namedStateDir();
    final dirs = <String>[?named];
    final home = _hostHome();
    if (home == null) return dirs;
    final checkouts = Directory('$home/Documents/Dev');
    if (!checkouts.existsSync()) return dirs;
    for (final entry in checkouts.listSync()) {
      if (entry is! Directory) continue;
      for (final shape in [
        '${entry.path}/.ai/scratch/zz_testlab/state',
        '${entry.path}/testlab/.ai/scratch/zz_testlab/state',
      ]) {
        if (File('$shape/credentials.env').existsSync()) dirs.add(shape);
      }
    }
    return dirs;
  }

  /// The state directory the run names, from the environment or from a
  /// `--dart-define`, or null.
  static String? _namedStateDir() {
    final named = Platform.environment['CUPOLA_TESTLAB_STATE_DIR'];
    if (named != null && named.isNotEmpty) return named;
    const defined = String.fromEnvironment('CUPOLA_TESTLAB_STATE_DIR');
    return defined.isEmpty ? null : defined;
  }

  /// The host's home directory, seen from the app.
  ///
  /// The simulator's app lives in the device's container, which is a
  /// directory of the host: `~/Library/Developer/CoreSimulator/Devices/…`.
  /// The host's home is above it. A run on the host has no such path and
  /// reads the environment's home instead.
  static String? _hostHome() {
    final parts = Platform.resolvedExecutable.split('/');
    final index = parts.indexOf('CoreSimulator');
    if (index > 2) return parts.sublist(0, index - 2).join('/');
    final home = Platform.environment['HOME'];
    return (home == null || home.isEmpty) ? null : home;
  }

  static Map<String, String> _parse(File file) {
    final values = <String, String>{};
    List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } on FileSystemException {
      return values;
    }
    for (final line in lines) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      values[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return values;
  }
}

/// The world's contract: the titles the flows may ask for, and the people.
///
/// The world is the lab's, not the journey's: the seed picks the free
/// titles at every run, so a journey reads them here instead of naming
/// them.
class LabWorld {
  LabWorld(this._json, this.path);

  final Map<String, dynamic> _json;
  final String path;

  /// The world the seed wrote, or a failure that says to seed it.
  static LabWorld load() {
    for (final file in _files()) {
      try {
        final json = jsonDecode(file.readAsStringSync());
        if (json is Map<String, dynamic>) return LabWorld(json, file.path);
      } on Object {
        // Another checkout's file, or a half-written one: the next candidate.
      }
    }
    fail(
      'The Seerr world was not found. Seed it with '
      '"python3 test/e2e/testlab/testlab.py scenario apply seerr-world".',
    );
  }

  static List<File> _files() {
    final files = <File>[];
    final named = LabCredentials._namedStateDir();
    if (named != null) files.add(File('$named/seerr-world.json'));
    files.add(File('.ai/scratch/zz_testlab/state/seerr-world.json'));
    for (final state in LabCredentials._candidateStateDirs()) {
      files.add(File('$state/seerr-world.json'));
    }
    return files;
  }

  /// The movie the world left free for a request.
  ({String title, int tmdbId}) get askTitle => _title('ask');

  /// The series the world left free, and the season it may be asked for.
  ({String title, int tmdbId, int season}) get seriesTitle {
    final titles = (_json['titles'] as Map?)?['series'] as Map?;
    return (
      title: titles?['title'] as String? ?? '',
      tmdbId: titles?['tmdbId'] as int? ?? 0,
      season: titles?['season'] as int? ?? 1,
    );
  }

  /// The movie the world left free for an approval.
  ({String title, int tmdbId}) get approveTitle => _title('approve');

  ({String title, int tmdbId}) _title(String key) {
    final titles = (_json['titles'] as Map?)?[key] as Map?;
    return (
      title: titles?['title'] as String? ?? '',
      tmdbId: titles?['tmdbId'] as int? ?? 0,
    );
  }

  /// The household member the requester journeys speak for.
  int get requesterId {
    final people = _json['people'] as Map?;
    final anna = people?['anna'] as Map?;
    return anna?['id'] as int? ?? 0;
  }

  /// The email of the household member the requester journeys speak for.
  String get requesterEmail {
    final people = _json['people'] as Map?;
    final anna = people?['anna'] as Map?;
    final email = anna?['email'] as String?;
    if (email == null || email.isEmpty) {
      fail('The Seerr world at $path holds no email for Anna.');
    }
    return email;
  }

  /// The password of the household member, from the world's own file: the
  /// seed wrote it there, 0600, and it is never printed nor committed.
  String get requesterPassword {
    final people = _json['people'] as Map?;
    final anna = people?['anna'] as Map?;
    final password = anna?['password'] as String?;
    if (password == null || password.isEmpty) {
      fail('The Seerr world at $path holds no password for Anna.');
    }
    return password;
  }

  /// The id of the request the world holds for [tmdbId], when it holds one.
  int? requestIdOf(int tmdbId) {
    final requests = _json['requests'] as Map?;
    if (requests == null) return null;
    for (final entry in requests.values) {
      final row = entry as Map?;
      if (row?['tmdbId'] == tmdbId) return row?['id'] as int?;
    }
    return null;
  }
}

/// The arr's own key, read from the service's own configuration.
///
/// The arrs of the lab keep their key in their config, in the lab's state:
/// the harness reads it there, so the repository never holds one.
String? arrKeyOf(String stateDir, String service) {
  final file = File('$stateDir/$service/config.xml');
  if (!file.existsSync()) return null;
  final match = RegExp(
    r'<ApiKey>([^<]*)</ApiKey>',
  ).firstMatch(file.readAsStringSync());
  final key = match?.group(1)?.trim();
  return (key == null || key.isEmpty) ? null : key;
}

/// The lab's facts, read once per journey.
class Lab {
  Lab._(this.credentials, this.world);

  /// The lab's secrets.
  final LabCredentials credentials;

  /// The world's contract.
  final LabWorld world;

  /// The arrs' keys, read from the arrs' own configuration in the lab's
  /// state: the repository never holds one.
  late final Map<ServiceKey, String> arrKeys = {
    for (final service in const [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.readarr,
      ServiceKey.prowlarr,
      ServiceKey.bazarr,
    ])
      service: arrKeyOf(credentials.stateDir, service.name) ?? '',
  };

  /// The name the bootstrap gave the secret of a service, when it wrote one.
  static const Map<ServiceKey, String> _secretNames = {
    ServiceKey.seerr: 'CUPOLA_TESTLAB_SEERR_API_KEY',
    ServiceKey.jellyfin: 'CUPOLA_TESTLAB_JELLYFIN_TOKEN',
    ServiceKey.emby: 'CUPOLA_TESTLAB_EMBY_TOKEN',
    ServiceKey.plex: 'CUPOLA_TESTLAB_PLEX_TOKEN',
  };

  /// The names the bootstrap gave the user a key-only server is read as. An
  /// Emby API key belongs to no one, so the connection also names the
  /// administrator it browses as; a Jellyfin token is a user's own.
  static const Map<ServiceKey, String> _viewerNames = {
    ServiceKey.emby: 'CUPOLA_TESTLAB_EMBY_USER_ID',
  };

  /// The names the bootstrap gave the pair of a service, when it wrote one.
  static const Map<ServiceKey, ({String user, String password})> _pairNames = {
    ServiceKey.qbittorrent: (
      user: 'CUPOLA_TESTLAB_QBITTORRENT_USERNAME',
      password: 'CUPOLA_TESTLAB_QBITTORRENT_PASSWORD',
    ),
    ServiceKey.transmission: (
      user: 'CUPOLA_TESTLAB_TRANSMISSION_USERNAME',
      password: 'CUPOLA_TESTLAB_TRANSMISSION_PASSWORD',
    ),
    ServiceKey.nzbget: (
      user: 'CUPOLA_TESTLAB_NZBGET_USERNAME',
      password: 'CUPOLA_TESTLAB_NZBGET_PASSWORD',
    ),
    ServiceKey.nginxProxyManager: (
      user: 'CUPOLA_TESTLAB_NPM_USERNAME',
      password: 'CUPOLA_TESTLAB_NPM_PASSWORD',
    ),
    ServiceKey.dockge: (
      user: 'CUPOLA_TESTLAB_DOCKGE_USERNAME',
      password: 'CUPOLA_TESTLAB_DOCKGE_PASSWORD',
    ),
  };

  /// The keys the lab's own Compose services declare, which are not secrets:
  /// TrueNAS and Unraid read an API key, and their simulators fix it.
  static const Map<ServiceKey, String> _fixedKeys = {
    ServiceKey.truenas: 'test-key',
    ServiceKey.unraid: 'test-key',
  };

  /// The connection the app holds for [service] in this lab: its address
  /// through the fault layer, and the secret the lab's own state holds.
  ///
  /// [apiKey] overrides the key for this one connection, which is how the
  /// read-only journeys open the app on a key that can only read.
  ///
  /// The next families (the media servers, the infrastructure) take their
  /// services from here, so no journey has to spell an address or a key
  /// again.
  ServiceInstance connectionOf(ServiceKey service, {String? apiKey}) {
    final id = ServiceInstance.primaryIdFor(service);
    final url = LabEndpoints.appUrlOf(service);
    if (apiKey != null) {
      return ServiceInstance(
        id: id,
        service: service,
        url: url,
        credential: apiKey,
      );
    }
    final viewerName = _viewerNames[service];
    if (_secretNames[service] case final name?) {
      return ServiceInstance(
        id: id,
        service: service,
        url: url,
        credential: credentials.require(name),
        viewerId: viewerName == null ? '' : credentials.require(viewerName),
      );
    }
    final pair = _pairNames[service];
    if (pair != null) {
      return ServiceInstance(
        id: id,
        service: service,
        url: url,
        username: credentials.require(pair.user),
        credential: credentials.require(pair.password),
      );
    }
    return ServiceInstance(
      id: id,
      service: service,
      url: url,
      credential: _fixedKeys[service] ?? arrKeys[service] ?? '',
    );
  }

  /// The lab, read from the checkout that holds it.
  static Lab load() => Lab._(LabCredentials.load(), LabWorld.load());

  /// Runs one of the lab's own commands through its control plane.
  ///
  /// The journeys run on the simulator, where starting a process is forbidden,
  /// so the world's state (a fault in front of a service, a scenario) is
  /// changed the way the lab's own CLI changes it: `['fault', 'radarr',
  /// 'down']`, `['scenario', 'apply', 'dockge-lab']`.
  Future<Map<String, Object?>> command(List<String> arguments) async {
    final url = credentials.controlUrl;
    final token = credentials.controlToken;
    if (url == null || token == null) {
      fail(
        'the lab control API is not running: its URL and token are missing '
        'from the credentials file',
      );
    }
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$url/command'));
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      // The control API reads an exact `Content-Length` and refuses a chunked
      // body, which is what `write` alone sends.
      final payload = utf8.encode(
        jsonEncode({
          'command': arguments.first,
          'arguments': arguments.sublist(1),
        }),
      );
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        fail(
          'the lab refused "${arguments.join(' ')}" with '
          '${response.statusCode}: $body',
        );
      }
      final decoded = body.isEmpty ? null : jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : const {};
    } finally {
      client.close(force: true);
    }
  }
}

/// Who the app is for.
enum LabProfile { operator, requester }

/// The app under test, pointed at the lab.
///
/// Two profiles, and they are not a preference: the app is the operator's
/// or a household member's, and the audience follows what is set up (a Seerr
/// key, any other service, makes the app the operator's; a Seerr account
/// that may only ask, alone, makes it hers).
class LabApp {
  LabApp._({required this.lab, required this.container, required this.surface});

  /// The lab this app talks to.
  final Lab lab;

  final ProviderContainer container;

  /// What the surface drew.
  final LabSurface surface;

  /// The requests this journey made, and the ones to delete when it ends.
  final List<int> _tracked = [];

  LabCredentials get credentials => lab.credentials;

  LabWorld get world => lab.world;

  /// Opens the app as whoever runs the stack: the Seerr with its key, and
  /// the arrs the lab runs.
  ///
  /// [services] picks the connections the journey needs: the next families
  /// (the media servers, the infrastructure) name theirs here, and the
  /// defaults are the ones the requests and the approvals read.
  ///
  /// [apiKeys] overrides a service's key for this app, which is how I-15 and
  /// the Unraid read-only copy open the same lab on a key that can only read.
  static Future<LabApp> asOperator(
    WidgetTester tester, {
    Lab? lab,
    Set<ServiceKey>? services,
    Map<ServiceKey, String>? apiKeys,
  }) async {
    final theLab = lab ?? Lab.load();
    final wanted =
        services ??
        const {ServiceKey.seerr, ServiceKey.radarr, ServiceKey.sonarr};
    var settings = const SettingsModel();
    for (final service in wanted) {
      settings = settings.copyWithInstance(
        theLab.connectionOf(service, apiKey: apiKeys?[service]),
      );
    }
    if (wanted.contains(ServiceKey.truenas)) {
      // The lab's TrueNAS presents its own certificate. The app reaches it
      // through the fault layer, which forwards TLS untouched, so the pin is
      // the one the bootstrap wrote from the upstream certificate.
      settings = settings.copyWithTrustedCertificate(
        url: LabEndpoints.appUrlOf(ServiceKey.truenas),
        fingerprint: theLab.credentials.require(
          'CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT',
        ),
      );
    }
    return LabApp._open(theLab, tester, settings);
  }

  /// Opens the app as a household member: only her Seerr account, signed in
  /// with the app's own client, so the session, the permissions and the
  /// cookie are the ones the app would have.
  ///
  /// The sign-in is the journey of G-07, not of these flows: here it is the
  /// arrangement, the way the lab's operator signs her in before the day.
  static Future<LabApp> asRequester(WidgetTester tester, {Lab? lab}) async {
    final theLab = lab ?? Lab.load();
    final instance = ServiceInstance(
      id: ServiceInstance.primaryIdFor(ServiceKey.seerr),
      service: ServiceKey.seerr,
      url: LabEndpoints.seerr,
    );
    final auth = SeerrAuthService.forConnection(instance);
    final facts = await auth.readServer();
    final account = await auth.signInWithEmail(
      facts,
      email: theLab.world.requesterEmail,
      password: theLab.world.requesterPassword,
    );
    final settings = const SettingsModel().copyWithInstance(
      instance.copyWith(account: account),
    );
    return LabApp._open(theLab, tester, settings);
  }

  static Future<LabApp> _open(
    Lab lab,
    WidgetTester tester,
    SettingsModel settings,
  ) async {
    final container = ProviderContainer(
      overrides: [...await settingsScopeOverrides(customize: (_) => settings)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const cupola.CupolaApp(),
      ),
    );
    await settle(tester, const Duration(seconds: 3));
    return LabApp._(
      lab: lab,
      container: container,
      surface: LabSurface(tester),
    );
  }

  /// Opens the app again, as somebody else, on the same lab.
  ///
  /// A journey that crosses the house (a member asks, the operator answers)
  /// needs the app to be both, one after the other: the first app is closed
  /// and the second is opened on the same screen, with the same data on the
  /// server.
  Future<LabApp> reopenAs(WidgetTester tester, LabProfile profile) async {
    // The old app is taken off the screen before the new one is put on it: a
    // tree unmounted in the middle of a route's transition trips the
    // framework's own assertion, and the app would fail for a reason that
    // has nothing to do with the journey.
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, const Duration(seconds: 1));
    container.dispose();
    return switch (profile) {
      LabProfile.operator => LabApp.asOperator(tester, lab: lab),
      LabProfile.requester => LabApp.asRequester(tester, lab: lab),
    };
  }

  /// Goes to [location] and lets the page settle.
  Future<void> go(WidgetTester tester, String location) async {
    container.read(routerProvider).go(location);
    await settle(tester, const Duration(seconds: 2));
  }

  /// The app's own way to a title: the Discover tab's field, the title in
  /// the results, the title's page.
  ///
  /// The path a person takes, not a route: the field is the app's own, the
  /// result is the app's own row, and the page that opens is the one the
  /// row opens. The row is picked by its kind and the year the server dates
  /// the title with, because a catalogue holds several titles with the same
  /// name and the wrong one would be a different movie. The catalogue is a
  /// long list, so the results are walked until the row is there.
  Future<void> openTitleFromSearch(
    WidgetTester tester, {
    required String type,
    required int tmdbId,
    required String title,
  }) async {
    await go(tester, ServiceRoutes.discover);
    await settle(tester, const Duration(seconds: 1));
    final field = find.byType(TextField).first;
    expect(field, findsOneWidget, reason: 'the Discover tab has no field');
    await tester.enterText(field, title);
    final year = await yearOf(type, tmdbId);
    final kind = type == 'tv' ? 'Series' : 'Movie';
    final meta = find.textContaining('$kind$dotSeparator$year');
    await surface.waitFor(
      find.byType(SearchRow),
      reason: 'the catalogue draws no row for "$title"',
    );
    if (meta.evaluate().isEmpty) {
      // The catalogue is a long list and the row of the title may be below
      // the fold: the results are walked until it is there.
      final list = find
          .ancestor(
            of: find.byType(SearchRow),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        meta,
        200,
        scrollable: list,
        maxScrolls: 15,
      );
      // The row the walk found may sit under the app's bottom bar, which
      // would take the tap: the list is moved a little further so the row
      // is clear of it.
      await tester.drag(list, const Offset(0, -140));
      await settle(tester, const Duration(milliseconds: 400));
    }
    final row = find.ancestor(of: meta, matching: find.byType(SearchRow));
    expect(
      row,
      findsWidgets,
      reason: 'the catalogue draws no row for "$title" ($kind $year)',
    );
    await tester.tap(
      find.descendant(of: row, matching: find.text(title)).first,
    );
    await settle(tester, const Duration(seconds: 3));
  }

  /// The year the server dates a title with, as the search's rows do.
  Future<String> yearOf(String type, int tmdbId) async {
    final media = await server.media(type, tmdbId);
    final date = type == 'tv'
        ? media['firstAirDate'] as String?
        : media['releaseDate'] as String?;
    return (date ?? '').split('-').first;
  }

  /// Scrolls [target] into view, clear of the app's bottom bar, and taps it.
  ///
  /// A row of a long list may be below the fold, and a tap on a widget that
  /// is not on the screen lands on whatever is there: the journey would be
  /// testing the bar instead of the row.
  Future<void> tapIn(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await settle(tester, const Duration(milliseconds: 300));
    final list = find.ancestor(of: target, matching: find.byType(Scrollable));
    if (list.evaluate().isNotEmpty) {
      // The app's bottom bar sits over the list: the row is moved above it.
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final rect = tester.getRect(target);
      final over = rect.bottom - (screen.height - 110);
      if (over > 0) {
        await tester.drag(list.first, Offset(0, -over));
        await settle(tester, const Duration(milliseconds: 300));
      }
    }
    await tester.tap(target);
  }

  /// Remembers a request the journey made, so the lab is left as it was even
  /// when the journey fails halfway.
  ///
  /// The world's own requests are never tracked: only the ones a journey
  /// wrote, which the journey deletes.
  void trackRequest(int id) {
    _tracked.add(id);
    addTearDown(cleanUp);
  }

  /// Deletes the requests the journey made, through the operator's own key.
  Future<void> cleanUp() async {
    final admin = LabSeerr(credentials.seerrApiKey);
    for (final id in _tracked) {
      try {
        await admin.deleteRequest(id);
      } on Object {
        // The request is already gone: nothing to undo.
      }
    }
    _tracked.clear();
  }

  /// The Seerr the app talks to, through the app's own client.
  SeerrService get seerr => container.read(seerrServiceProvider);

  /// The reading side of the same fact: the service's own API, straight to
  /// the service.
  LabSeerr get server => LabSeerr(credentials.seerrApiKey);

  /// Radarr, straight to the service.
  LabRadarr get radarr => LabRadarr(lab.arrKeys[ServiceKey.radarr] ?? '');

  /// Runs one of the lab's own commands through its control plane, which is
  /// the only way a journey can change the world from the simulator.
  Future<Map<String, Object?>> command(List<String> arguments) =>
      lab.command(arguments);

  /// Puts the lab back in the state the seed left it in, when the control
  /// plane of the lab is running.
  ///
  /// The journeys clean up after themselves, so this is the safety net: the
  /// world's own requests are never touched by a journey, and a journey that
  /// failed halfway leaves its own request behind, which the next run's
  /// seed removes.
  Future<bool> restoreWorld() async {
    if (credentials.controlUrl == null || credentials.controlToken == null) {
      return false;
    }
    try {
      final answer = await command(['scenario', 'apply', 'seerr-world']);
      return answer['error'] == null;
    } on Object {
      return false;
    }
  }
}

/// What the surface drew.
///
/// The reading of the widget tree, and nothing else: the texts, how many
/// of them there are, and whether a control is there. A journey that only
/// read the server would prove nothing about the app.
class LabSurface {
  LabSurface(this._tester);

  final WidgetTester _tester;

  /// The texts the surface is drawing, in the order it draws them.
  List<String> texts() => _tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .where((data) => data.isNotEmpty)
      .toList();

  /// How many lines of text the surface draws: the rows of a list, the
  /// lines of a card, all of them.
  int get lines => find.byType(Text).evaluate().length;

  /// How many widgets of [type] the surface draws.
  int count(Type type) => find.byType(type).evaluate().length;

  /// Whether the surface draws [text] right now.
  bool draws(String text) => find.text(text).evaluate().isNotEmpty;

  /// Whether the surface draws a line that holds [fragment] right now.
  bool drawsPart(String fragment) =>
      find.textContaining(fragment).evaluate().isNotEmpty;

  /// Waits until the surface draws [text], and fails with what it drew.
  Future<void> see(
    String text, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (await _until(find.text(text), timeout)) return;
    fail('The surface never drew "$text". It drew: ${texts().join(' | ')}');
  }

  /// Waits until the surface draws a line that holds [fragment].
  Future<void> seePart(
    String fragment, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (await _until(find.textContaining(fragment), timeout)) return;
    fail(
      'The surface never drew a line holding "$fragment". '
      'It drew: ${texts().join(' | ')}',
    );
  }

  /// Waits until the surface stops drawing [text].
  Future<void> unsee(
    String text, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (await _until(find.text(text), timeout, present: false)) return;
    fail('The surface still draws "$text". It drew: ${texts().join(' | ')}');
  }

  /// Waits until [finder] finds something, and fails with what the surface
  /// drew when it does not.
  Future<void> waitFor(
    Finder finder, {
    String? reason,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (await _until(finder, timeout)) return;
    fail(reason ?? 'The surface never drew what the journey waited for.');
  }

  Future<bool> _until(
    Finder finder,
    Duration timeout, {
    bool present = true,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final there = finder.evaluate().isNotEmpty;
      if (there == present) return true;
      await _tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }
}

/// Seerr's own API, read straight to the service.
class LabSeerr {
  LabSeerr(this.apiKey);

  final String apiKey;

  /// Every request the server holds, newest first.
  Future<List<Map<String, dynamic>>> requests() async {
    final value = await _get('/api/v1/request?take=100&skip=0&sort=added');
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  /// One request, or null when the server does not hold it.
  Future<Map<String, dynamic>?> request(int id) async {
    try {
      final value = await _get('/api/v1/request/$id');
      return value is Map<String, dynamic> ? value : null;
    } on LabHttpError {
      return null;
    }
  }

  /// The requests [requesterId] made.
  Future<List<Map<String, dynamic>>> requestsOf(int requesterId) async {
    final all = await requests();
    return [
      for (final request in all)
        if ((request['requestedBy'] as Map?)?['id'] == requesterId) request,
    ];
  }

  /// The record of a title, as Seerr knows it.
  Future<Map<String, dynamic>> media(String type, int tmdbId) async {
    final value = await _get('/api/v1/$type/$tmdbId');
    return value is Map<String, dynamic> ? value : const {};
  }

  /// Deletes a request, as the lab's cleanup does.
  Future<void> deleteRequest(int id) async {
    await _send('DELETE', '/api/v1/request/$id');
  }

  Future<Object?> _get(String path) => _send('GET', path);

  Future<Object?> _send(String method, String path) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('${LabEndpoints.seerrDirect}$path'),
      );
      request.headers.set('X-Api-Key', apiKey);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LabHttpError(response.statusCode, body);
      }
      if (body.isEmpty) return null;
      return jsonDecode(body);
    } on FormatException {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// Radarr's own API, read straight to the service.
class LabRadarr {
  LabRadarr(this.apiKey);

  final String apiKey;

  /// The movie Radarr holds for [tmdbId], or null when it holds none.
  Future<Map<String, dynamic>?> movie(int tmdbId) async {
    final value = await _get('/api/v3/movie');
    if (value is! List) return null;
    for (final item in value) {
      if (item is Map && item['tmdbId'] == tmdbId) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  /// The quality profiles Radarr offers, by id and name.
  Future<List<({int id, String name})>> profiles() async {
    final value = await _get('/api/v3/qualityprofile');
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map)
          (id: item['id'] as int? ?? 0, name: item['name'] as String? ?? ''),
    ];
  }

  /// The root folders Radarr offers.
  Future<List<String>> rootFolders() async {
    final value = await _get('/api/v3/rootfolder');
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map && item['path'] is String) item['path'] as String,
    ];
  }

  /// Takes a movie out of Radarr, with its files, as the lab's cleanup does.
  Future<void> deleteMovie(int id, {bool withFiles = true}) async {
    await _send(
      'DELETE',
      '/api/v3/movie/$id?deleteFiles=$withFiles&addImportExclusion=false',
    );
  }

  /// The import exclusions Radarr holds.
  Future<List<({int id, String title})>> exclusions() async {
    final value = await _get('/api/v3/exclusions');
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map)
          (id: item['id'] as int? ?? 0, title: item['title'] as String? ?? ''),
    ];
  }

  /// Takes the import exclusions of [title] out of Radarr, as the lab's
  /// cleanup does: a search that grabbed a release leaves one behind.
  Future<void> deleteExclusionsOf(String title) async {
    for (final exclusion in await exclusions()) {
      if (!exclusion.title.contains(title)) continue;
      await _send('DELETE', '/api/v3/exclusions/${exclusion.id}');
    }
  }

  Future<Object?> _get(String path) => _send('GET', path);

  Future<Object?> _send(String method, String path) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('${LabEndpoints.radarrDirect}$path'),
      );
      request.headers.set('X-Api-Key', apiKey);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LabHttpError(response.statusCode, body);
      }
      if (body.isEmpty) return null;
      return jsonDecode(body);
    } on FormatException {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// An answer the service did not give.
class LabHttpError implements Exception {
  LabHttpError(this.status, this.body);

  final int status;
  final String body;

  @override
  String toString() => 'the service answered $status';
}

/// Lets the app settle: the frames it needs, and the time it needs them.
Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
