@Tags(['e2e'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/main.dart' as cupola;

import '../test/test_helpers/settings_scope.dart';

/// Native route/state/visual matrix for the disposable OrbStack lab.
///
/// This test deliberately injects the lab settings into a test-only
/// ProviderScope instead of typing credentials through the onboarding UI on
/// every run. The real onboarding path remains covered separately; this is the
/// repeatable way to reach every service surface and collect evidence without
/// putting credentials in source control or coupling the matrix to OS input
/// automation.
///
/// The matrix covers every tab root, every TrueNAS section root, the global
/// shell/settings roots, and the detail/editor routes that are reachable from
/// those roots. The ids are deterministic lab specimens; a real instance is
/// still required to prove populated data and mutating actions.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment(
    'CUPOLA_TESTLAB_SCREENSHOTS',
    defaultValue: true,
  );
  const driverScreenshots = bool.fromEnvironment(
    'CUPOLA_TESTLAB_DRIVER_SCREENSHOTS',
    defaultValue: false,
  );

  testWidgets('Cupola macOS lab route matrix: every tab, size and theme', (
    tester,
  ) async {
    final scenario = _scenario;
    final credentials = _loadCredentials(
      mustExist: scenario != 'not-configured',
    );
    final allRoutes = _routes();
    final routeOffset =
        int.tryParse(
          Platform.environment['CUPOLA_TESTLAB_ROUTE_OFFSET'] ?? '',
        ) ??
        0;
    final routeLimit = int.tryParse(
      Platform.environment['CUPOLA_TESTLAB_ROUTE_LIMIT'] ?? '',
    );
    final routes = allRoutes
        .skip(routeOffset.clamp(0, allRoutes.length))
        .take(
          routeLimit != null && routeLimit > 0 ? routeLimit : allRoutes.length,
        )
        .toList(growable: false);
    final allSizes = <({String name, Size size})>[
      (name: '1440x900', size: const Size(1440, 900)),
      (name: '720x450', size: const Size(720, 450)),
      (name: '390x844', size: const Size(390, 844)),
    ];
    final requestedSize = Platform.environment['CUPOLA_TESTLAB_SIZE'];
    final sizes = requestedSize == null
        ? allSizes
        : allSizes
              .where((frame) => frame.name == requestedSize)
              .toList(growable: false);
    if (sizes.isEmpty) {
      fail(
        'CUPOLA_TESTLAB_SIZE must be one of: '
        '${allSizes.map((frame) => frame.name).join(', ')}',
      );
    }
    final themes = <({String name, AppThemeMode mode})>[
      (name: 'dark', mode: AppThemeMode.dark),
      (name: 'light', mode: AppThemeMode.light),
    ];

    final screenshotDirectory = driverScreenshots
        ? null
        : (Directory(
            Platform.environment['CUPOLA_TESTLAB_SCREENSHOT_DIR'] ??
                '.ai/scratch/zz_testlab/screenshots',
          )..createSync(recursive: true));
    debugPrint(
      '[testlab] scenario=$scenario capture=$capture cwd=${Directory.current.path} '
      'screenshots=${screenshotDirectory?.absolute.path ?? 'driver'} '
      'routes=${routes.length}/${allRoutes.length} offset=$routeOffset',
    );

    for (final theme in themes) {
      final settings = _labSettings(credentials, theme.mode, scenario);
      final container = ProviderContainer(
        overrides: [
          ...await settingsScopeOverrides(customize: (_) => settings),
        ],
      );
      final router = container.read(routerProvider);
      final screenshotKey = GlobalKey();

      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: screenshotKey,
              child: const cupola.CupolaApp(),
            ),
          ),
        );
        await _pumpRoute(tester);

        for (final frame in sizes) {
          tester.view.physicalSize = frame.size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pump();
          final resizeException = tester.takeException();
          if (resizeException != null &&
              Platform.environment['CUPOLA_TESTLAB_VERBOSE'] == 'true') {
            debugPrint(
              resizeException is FlutterError
                  ? resizeException.toStringDeep()
                  : resizeException.toString(),
            );
          }
          expect(
            resizeException,
            isNull,
            reason: '${theme.name} · ${frame.name} · resize',
          );

          for (final route in routes) {
            if (Platform.environment['CUPOLA_TESTLAB_VERBOSE'] == 'true') {
              debugPrint('[testlab] ${theme.name} · ${frame.name} · $route');
            }
            router.go(route);
            await _pumpRoute(tester);
            final exception = tester.takeException();

            if (capture) {
              final slug = _slug('${theme.name}_${frame.name}_$route');
              final bytes = await _captureScreenshot(screenshotKey);
              if (driverScreenshots) {
                _addDriverScreenshot(binding, slug, bytes);
              } else {
                await File(
                  '${screenshotDirectory!.path}/$slug.png',
                ).writeAsBytes(bytes, flush: true);
              }
            }

            if (exception != null &&
                Platform.environment['CUPOLA_TESTLAB_VERBOSE'] == 'true') {
              debugPrint(
                exception is FlutterError
                    ? exception.toStringDeep()
                    : exception.toString(),
              );
            }
            expect(
              exception,
              isNull,
              reason: '${theme.name} · ${frame.name} · $route',
            );
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        router.dispose();
        container.dispose();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 45)));
}

Future<List<int>> _captureScreenshot(GlobalKey key) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    fail('Screenshot boundary is not mounted');
  }
  final image = await boundary.toImage(pixelRatio: 1.0);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) fail('Flutter returned no PNG bytes');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void _addDriverScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
  List<int> bytes,
) {
  final data = binding.reportData ??= <String, dynamic>{};
  final screenshots =
      data.putIfAbsent('screenshots', () => <dynamic>[]) as List<dynamic>;
  screenshots.add(<String, dynamic>{'screenshotName': name, 'bytes': bytes});
}

Future<void> _pumpRoute(WidgetTester tester) async {
  // The service ring and polling surfaces can animate forever. The matrix is
  // about settled layout and route construction, so it disables authored
  // motion and gives network-backed providers a bounded window to paint.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(_settleDuration);
}

Duration get _settleDuration {
  final milliseconds =
      int.tryParse(Platform.environment['CUPOLA_TESTLAB_SETTLE_MS'] ?? '') ??
      2000;
  return Duration(milliseconds: milliseconds.clamp(0, 10000));
}

List<String> _routes() {
  final routes = <String>[
    ServiceRoutes.home,
    ServiceRoutes.stack,
    '/activity',
    '/search',
    '/settings',
    '/settings/appearance',
    '/settings/background-search',
    '/settings/certificates',
    '/settings/connections',
    '/settings/hints',
    '/settings/region',
    for (final service in ServiceKey.values)
      '/settings/service/${service.routeParam}',
    for (final service in ServiceKey.values)
      for (final tab in tabsFor(service) ?? const <ServiceTab>[])
        '${ServiceRoutes.forService(service)}/${tab.segment}',
    ServiceRoutes.discover,
    ServiceRoutes.discoverCatalog(const CatalogQuery.all(CatalogKind.movie)),
    ServiceRoutes.discoverCatalog(const CatalogQuery.trending()),
    ServiceRoutes.discoverCatalog(
      const CatalogQuery.genre(CatalogKind.movie, 28, 'Action'),
    ),
    ServiceRoutes.discoverCatalog(const CatalogQuery.network(213, 'Netflix')),
    ServiceRoutes.discoverCatalog(
      const CatalogQuery.decade(CatalogKind.tv, 1990),
    ),
    ServiceRoutes.mediaRoot(const MediaKey.movie(42)),
    ServiceRoutes.mediaRoot(const MediaKey.tv(55)),
    ServiceRoutes.person(287, from: ServiceRoutes.discover),
    ServiceRoutes.collection(10, from: ServiceRoutes.discover),
    ServiceRoutes.radarrMovie(42),
    ServiceRoutes.sonarrSeries(55),
    ServiceRoutes.lidarrArtist(9),
    ServiceRoutes.qbittorrentTorrent('abc123'),
    ServiceRoutes.bazarrSeries(7),
    ServiceRoutes.bazarrMovie(12),
    ServiceRoutes.prowlarrIndexer(3),
    ServiceRoutes.prowlarrSettings,
    for (final kind in ProwlarrProviderKind.values)
      ServiceRoutes.prowlarrSettingsSection(kind),
    ServiceRoutes.dockgeNewStack,
    ServiceRoutes.dockgeStack('immich'),
    ServiceRoutes.dockgeStackEdit('immich'),
    ServiceRoutes.jellyfinLibrary('f137a2dd', title: 'Films'),
    ServiceRoutes.jellyfinItem('abc-123'),
    ServiceRoutes.embyLibrary('3', title: 'Films'),
    ServiceRoutes.embyItem('15'),
    ServiceRoutes.plexLibrary('1', title: 'Films'),
    ServiceRoutes.plexItem('9421'),
    ServiceRoutes.truenasDashboard,
    ServiceRoutes.truenasStorage,
    ServiceRoutes.truenasDatasets,
    ServiceRoutes.truenasShares,
    ServiceRoutes.truenasDataProtection,
    ServiceRoutes.truenasContainers,
    ServiceRoutes.truenasVms,
    ServiceRoutes.truenasApps,
    ServiceRoutes.truenasReporting,
    ServiceRoutes.truenasSystem,
    ServiceRoutes.truenasPool('tank'),
    ServiceRoutes.truenasDataset('tank/media'),
    ServiceRoutes.truenasContainer('c1'),
    ServiceRoutes.truenasVm('vm1'),
    ServiceRoutes.truenasApp('appname'),
    for (final section in const [
      'general',
      'advanced',
      'services',
      'network',
      'credentials',
      'certificates',
      'email',
      'update',
      'ntp',
      'alert-settings',
    ])
      '${ServiceRoutes.truenasSystem}/$section',
  ];
  return routes.toSet().toList(growable: false);
}

SettingsModel _labSettings(
  Map<String, String> credentials,
  AppThemeMode theme,
  String scenario,
) {
  if (scenario == 'not-configured') {
    return settingsWith(themeMode: theme);
  }

  final unreachable = scenario == 'unreachable';
  final invalidAuth = scenario == 'invalid-auth';
  final degraded = scenario == 'degraded';
  final apiKey = invalidAuth ? 'wrong-key' : 'test-key';
  String endpoint(String value, {bool broken = false}) {
    if (unreachable || (degraded && broken)) return 'http://127.0.0.1:1';
    return value;
  }

  // TrueNAS is saved as https://, the only scheme the client will send its key
  // to; it dials wss:// from it. The mock's certificate is self-signed, so the
  // settings carry its fingerprint the way a person's do after trusting it. In
  // the unreachable scenario nothing is dialled, so there is no pin to carry.
  final truenasUrl = unreachable
      ? 'https://127.0.0.1:1'
      : 'https://127.0.0.1:8460';
  final truenasPin = unreachable
      ? ''
      : _required(credentials, 'CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT');

  String username(String key) =>
      invalidAuth ? 'wrong-user' : _required(credentials, key);

  String password(String key) =>
      invalidAuth ? 'wrong-password' : _required(credentials, key);

  final settings = settingsWith(
    themeMode: theme,
    plexClientId: 'cupola-testlab-ui-matrix',
    seerrUrl: endpoint('http://127.0.0.1:5055'),
    seerrApiKey: invalidAuth
        ? 'wrong-key'
        : _required(credentials, 'CUPOLA_TESTLAB_SEERR_API_KEY'),
    radarrUrl: endpoint('http://127.0.0.1:7878', broken: true),
    radarrApiKey: apiKey,
    sonarrUrl: endpoint('http://127.0.0.1:8989', broken: true),
    sonarrApiKey: apiKey,
    lidarrUrl: endpoint('http://127.0.0.1:8686'),
    lidarrApiKey: apiKey,
    readarrUrl: endpoint('http://127.0.0.1:8787'),
    readarrApiKey: apiKey,
    prowlarrUrl: endpoint('http://127.0.0.1:9696'),
    prowlarrApiKey: apiKey,
    bazarrUrl: endpoint('http://127.0.0.1:6767'),
    bazarrApiKey: apiKey,
    qbittorrentUrl: endpoint('http://127.0.0.1:8080'),
    qbittorrentUsername: username('CUPOLA_TESTLAB_QBITTORRENT_USERNAME'),
    qbittorrentPassword: password('CUPOLA_TESTLAB_QBITTORRENT_PASSWORD'),
    transmissionUrl: endpoint('http://127.0.0.1:9091'),
    transmissionUsername: username('CUPOLA_TESTLAB_TRANSMISSION_USERNAME'),
    transmissionPassword: password('CUPOLA_TESTLAB_TRANSMISSION_PASSWORD'),
    sabnzbdUrl: endpoint('http://127.0.0.1:8082'),
    sabnzbdApiKey: apiKey,
    nzbgetUrl: endpoint('http://127.0.0.1:6789'),
    nzbgetUsername: username('CUPOLA_TESTLAB_NZBGET_USERNAME'),
    nzbgetPassword: password('CUPOLA_TESTLAB_NZBGET_PASSWORD'),
    jellyfinUrl: endpoint('http://127.0.0.1:8096'),
    jellyfinApiKey: invalidAuth
        ? 'wrong-token'
        : _required(credentials, 'CUPOLA_TESTLAB_JELLYFIN_TOKEN'),
    jellyfinUserId: _required(credentials, 'CUPOLA_TESTLAB_JELLYFIN_USER_ID'),
    embyUrl: endpoint('http://127.0.0.1:8097'),
    embyApiKey: invalidAuth
        ? 'wrong-token'
        : _required(credentials, 'CUPOLA_TESTLAB_EMBY_TOKEN'),
    embyUserId: _required(credentials, 'CUPOLA_TESTLAB_EMBY_USER_ID'),
    plexUrl: endpoint('http://127.0.0.1:32400'),
    plexToken: invalidAuth
        ? 'wrong-token'
        : _required(credentials, 'CUPOLA_TESTLAB_PLEX_TOKEN'),
    dockgeUrl: endpoint('http://127.0.0.1:5001'),
    dockgeUsername: username('CUPOLA_TESTLAB_DOCKGE_USERNAME'),
    dockgePassword: password('CUPOLA_TESTLAB_DOCKGE_PASSWORD'),
    npmUrl: endpoint('http://127.0.0.1:8181'),
    npmUsername: username('CUPOLA_TESTLAB_NPM_USERNAME'),
    npmPassword: password('CUPOLA_TESTLAB_NPM_PASSWORD'),
    truenasUrl: truenasUrl,
    truenasApiKey: apiKey,
    unraidUrl: endpoint('http://127.0.0.1:8480'),
    unraidApiKey: apiKey,
  );
  return settings.copyWithTrustedCertificate(
    url: truenasUrl,
    fingerprint: truenasPin,
  );
}

String get _scenario {
  const allowed = {
    'healthy',
    'not-configured',
    'degraded',
    'unreachable',
    'invalid-auth',
  };
  final value = Platform.environment['CUPOLA_TESTLAB_SCENARIO'] ?? 'healthy';
  if (!allowed.contains(value)) {
    fail('CUPOLA_TESTLAB_SCENARIO must be one of: ${allowed.join(', ')}');
  }
  return value;
}

Map<String, String> _loadCredentials({required bool mustExist}) {
  final path = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
  final values = <String, String>{};
  // A native macOS integration-test runner is sandboxed away from the
  // checkout, while the Dart VM transport test can read the disposable file
  // directly. Prefer it when available, then fall back to inherited
  // CUPOLA_TESTLAB_* variables for the native runner. The bootstrap file is
  // still the only source of the values; this fallback avoids putting them in
  // source control or in command-line arguments.
  if (path != null && path.isNotEmpty) {
    final file = File(path);
    try {
      for (final line in file.readAsLinesSync()) {
        if (line.isEmpty || line.startsWith('#')) continue;
        final separator = line.indexOf('=');
        if (separator <= 0) continue;
        values[line.substring(0, separator)] = line.substring(separator + 1);
      }
    } on FileSystemException {
      // The native test app cannot see the host checkout; use its environment
      // below instead.
    }
  }
  for (final entry in Platform.environment.entries) {
    if (entry.key.startsWith('CUPOLA_TESTLAB_')) {
      values.putIfAbsent(entry.key, () => entry.value);
    }
  }
  if (mustExist && values.isEmpty) {
    fail(
      'Provide CUPOLA_TESTLAB_* environment variables from the bootstrap '
      'credentials.env, or a readable CUPOLA_TESTLAB_CREDENTIALS_FILE',
    );
  }
  return values;
}

String _required(Map<String, String> values, String key) {
  final value = values[key];
  if (value == null || value.isEmpty) fail('Missing $key in lab credentials');
  return value;
}

String _slug(String value) => value
    .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
    .replaceAll(RegExp(r'_+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');
