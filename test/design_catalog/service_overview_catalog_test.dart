@Tags(['catalog'])
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/utils/arr_overview.dart';
import 'package:cupola/core/widgets/service_overview.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/series/presentation/sonarr_overview_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/tracearr/data/tracearr_violation_owner.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violation_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_provider.dart';

import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import '../test_helpers/fake_services.dart';
import 'catalog.dart';

/// Radarr with an address away: at home on the home network's name, away
/// on a public one.
const _radarrHomeAndAway = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      label: '',
      url: 'http://nas.home.arpa:7878',
      credential: 'k',
      away: ConnectionAddress(url: 'https://radarr.example.net'),
    ),
  ],
);

/// The route probe's verdict, given: neither address answered.
class _Unanswered extends UnansweredConnectionsNotifier {
  @override
  Set<String> build() => const {'radarr'};
}

const _oneRadarr = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      label: '',
      url: 'https://radarr.lan:7878',
      credential: 'k',
    ),
  ],
);

/// Two connections, so the identity line carries the lens chip.
const _twoRadarrs = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      label: '4K',
      url: 'https://four-k.lan:7878',
      credential: 'k',
    ),
    ServiceInstance(
      id: 'radarr-hd11111',
      service: ServiceKey.radarr,
      label: 'HD',
      url: 'https://hd.lan:7879',
      credential: 'k',
    ),
  ],
);

const _oneSonarr = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'sonarr',
      service: ServiceKey.sonarr,
      label: '',
      url: 'https://sonarr.lan:8989',
      credential: 'k',
    ),
  ],
);

/// Sonarr's Needs attention after the queue answered once and then stopped:
/// two faults still held, and the failure riding on top of them.
class _SonarrAttention
    extends AsyncNotifier<List<ArrAttentionItem<SonarrAttentionKind>>> {
  @override
  Future<List<ArrAttentionItem<SonarrAttentionKind>>> build() async => const [
    ArrAttentionItem(
      kind: SonarrAttentionKind.stalled,
      headline: 'Stuck\u00A0· Slow Horses S04 E02',
      detail: 'qBittorrent\u00A0· The download is stalled',
    ),
    ArrAttentionItem(
      kind: SonarrAttentionKind.missing,
      headline: '12 episodes missing',
      detail: 'Sonarr keeps searching',
    ),
  ];

  /// The queue stops answering: the error lands over the two rows held.
  void stopAnswering() => state = AsyncError(
    DioException(
      requestOptions: RequestOptions(path: '/api/v3/queue'),
      type: DioExceptionType.receiveTimeout,
    ),
    StackTrace.empty,
  );
}

final _sonarrAttention =
    AsyncNotifierProvider<
      _SonarrAttention,
      List<ArrAttentionItem<SonarrAttentionKind>>
    >(_SonarrAttention.new);

final _sonarrQueuePage = Provider<AsyncValue<ArrRecordPage>>(
  (ref) => const AsyncData(ArrRecordPage(records: [], total: 2)),
);

final _now = catalogNow;

/// A moment earlier today, never yesterday, so History today keeps it.
String _earlierToday(Duration ago) {
  final start = DateTime(_now.year, _now.month, _now.day);
  final at = _now.subtract(ago);
  return (at.isBefore(start) ? start : at).toIso8601String();
}

String _inDays(int days) =>
    DateTime(_now.year, _now.month, _now.day + days, 9).toIso8601String();

RadarrMovie _movie(
  int id,
  String title,
  int year, {
  bool poster = false,
  bool hasFile = true,
  String? added,
  String? digitalRelease,
  String? physicalRelease,
}) => RadarrMovie(
  id: id,
  title: title,
  sortTitle: title.toLowerCase(),
  sizeOnDisk: 0,
  status: 'released',
  hasFile: hasFile,
  monitored: true,
  year: year,
  images: poster
      ? const [
          {'coverType': 'poster', 'remoteUrl': CatalogArt.poster},
        ]
      : const [],
  tmdbId: id,
  runtime: 90,
  genres: const [],
  added: added,
  digitalRelease: digitalRelease,
  physicalRelease: physicalRelease,
);

final _library = [
  _movie(
    1,
    'Nosferatu',
    1922,
    poster: true,
    added: _earlierToday(const Duration(minutes: 20)),
  ),
  _movie(
    2,
    'Metropolis',
    1927,
    hasFile: false,
    added: _earlierToday(const Duration(hours: 2)),
    digitalRelease: _inDays(1),
  ),
  _movie(
    3,
    'The Cabinet of Dr. Caligari',
    1920,
    added: _earlierToday(const Duration(hours: 3)),
    physicalRelease: _inDays(4),
  ),
  _movie(
    4,
    'Sherlock Jr.',
    1924,
    added: _earlierToday(const Duration(hours: 4)),
  ),
];

final _queue = [
  {
    'movie': {'id': 2, 'title': 'Metropolis'},
    'title': 'Metropolis.1927.1080p.BluRay.x264',
    'trackedDownloadState': 'downloading',
    'status': 'warning',
    'errorMessage': 'The download is stalled with no connections',
    'downloadClient': 'qBittorrent',
    'added': _earlierToday(const Duration(hours: 1)),
  },
  {
    'movie': {'id': 3, 'title': 'The Cabinet of Dr. Caligari'},
    'title': 'The.Cabinet.of.Dr.Caligari.1920.720p.BluRay.x264',
    'trackedDownloadState': 'importFailed',
    'errorMessage': 'No files found are eligible for import',
    'added': _earlierToday(const Duration(hours: 2)),
  },
];

final _history = [
  {
    'movie': {'title': 'Nosferatu'},
    'eventType': 'downloadFolderImported',
    'quality': {
      'quality': {'name': 'Bluray-1080p'},
    },
    'data': {'size': '8053063680'},
    'date': _earlierToday(const Duration(minutes: 20)),
  },
  {
    'movie': {'title': 'Metropolis'},
    'eventType': 'grabbed',
    'quality': {
      'quality': {'name': 'Bluray-1080p'},
    },
    'size': 10737418240,
    'date': _earlierToday(const Duration(hours: 1)),
  },
];

/// Radarr answering every section, offline.
class _ScriptedRadarr extends FakeRadarrService {
  _ScriptedRadarr({this.libraryFailure});

  /// What the library endpoint fails with, while the rest of the server
  /// answers, or null for a library that loads. A real failure, so the app's
  /// own classification decides the tone: a bare `Exception` is a failure
  /// nobody can attribute, and would paint amber where the scene means red.
  final Object? libraryFailure;

  @override
  Future<List<RadarrMovie>> getMovies() async => _library;

  @override
  Future<List<RadarrMovie>> getMoviesOrThrow() async {
    final failure = libraryFailure;
    if (failure != null) throw failure;
    return _library;
  }

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => _queue;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => _history;

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => const ArrRecordPage(records: [], total: 3);
}

/// A Radarr that has not answered yet.
class _PendingRadarr extends FakeRadarrService {
  final _never = Completer<Never>();

  @override
  Future<List<RadarrMovie>> getMovies() => _never.future;

  @override
  Future<List<RadarrMovie>> getMoviesOrThrow() => _never.future;

  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) =>
      _never.future;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) => _never.future;

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) => _never.future;
}

/// The reachability probe. An empty [version] throws (unreachable).
class _StatusClient extends ApiClient {
  _StatusClient(this.version)
    : super(baseUrl: 'https://radarr.lan:7878', apiKey: 'k');

  final String? version;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    if (version!.isEmpty) throw const SocketException('Connection refused');
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'version': version},
    );
  }

  @override
  void close({bool force = false}) {}
}

const _oneTracearr = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'tracearr',
      service: ServiceKey.tracearr,
      label: '',
      url: 'https://tracearr.lan:3000',
      credential: 'trr_pub_k',
    ),
  ],
);

/// Invented, and not read off a real Tracearr: the places are made up, and the
/// `data` spellings are the ones the model expects. One action went through,
/// one failed and one was skipped.
TracearrViolation _travel() => TracearrViolation.fromJson({
  'id': 'v1',
  'severity': 'high',
  'created_at': catalogNow.subtract(const Duration(hours: 2)).toIso8601String(),
  'acknowledged_at': null,
  'session_id': 'session-1',
  'rule': {'id': 'rule-1', 'name': 'Impossible travel'},
  'server': {'id': 'server-1', 'name': 'Plex Living Room', 'type': 'plex'},
  'user': {'id': 'person-1', 'username': 'Anna'},
  'data': {
    'from': {'city': 'Valmora', 'region': 'North Reach', 'country': 'Nordavia'},
    'to': {'city': 'Port Aster', 'region': 'Eastmark', 'country': 'Eastmark'},
    'distance_km': 5120.4,
    'time_diff_minutes': 95,
  },
  'actions': [
    {'type': 'notify', 'success': true, 'skipped': false},
    {
      'type': 'terminate_stream',
      'success': false,
      'skipped': false,
      'error_message': 'Plex Living Room did not answer',
    },
    {
      'type': 'notify_admins',
      'success': false,
      'skipped': true,
      'skip_reason': 'cooldown',
    },
  ],
});

/// A rule Cupola does not read, acknowledged an hour ago.
TracearrViolation _unknownRule() => TracearrViolation.fromJson({
  'id': 'v2',
  'severity': 'low',
  'created_at': catalogNow.subtract(const Duration(days: 1)).toIso8601String(),
  'acknowledged_at': catalogNow
      .subtract(const Duration(hours: 1))
      .toIso8601String(),
  'rule': {'id': 'rule-2', 'name': 'Night owl'},
  'server': {'id': 'server-2', 'name': 'Jellyfin Attic', 'type': 'jellyfin'},
  'user': {'id': 'person-2', 'username': 'Luca'},
  'data': {'city': 'Valmora', 'hour': 3},
  'actions': <Object>[],
});

/// Nobody has signed in as the owner, or somebody has.
class _OwnerStub implements TracearrViolationOwner {
  @override
  Future<TracearrOwnerOutcome> acknowledge(String violationId) async =>
      TracearrOwnerOutcome.done;

  @override
  Future<TracearrOwnerOutcome> dismiss(String violationId) async =>
      TracearrOwnerOutcome.done;
}

Widget _violation(TracearrViolation violation, {bool owner = false}) =>
    _Isolated([
      sharedPreferencesProvider.overrideWithValue(_prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWithValue(_oneTracearr),
      initialOnboardingCompletedProvider.overrideWithValue(true),
      initialActiveInstancesProvider.overrideWithValue(const {}),
      tracearrViolationProvider.overrideWith((ref, key) async => violation),
      if (owner)
        tracearrViolationOwnerProvider.overrideWith((ref, id) => _OwnerStub()),
    ], TracearrViolationScreen(violationId: violation.id));

late SharedPreferences _prefs;

/// One scene's own root container.
///
/// A nested `ProviderScope` only replaces the providers it names: everything
/// derived from them (the Overview's sections, the identity, the readouts)
/// still resolves in the sheet's root, so each scene gets a container of its
/// own. Retry is off, so a failed source stays failed instead of flickering
/// back to loading on its backoff.
class _Isolated extends StatefulWidget {
  const _Isolated(this.overrides, this.child);

  final List<Override> overrides;
  final Widget child;

  @override
  State<_Isolated> createState() => _IsolatedState();
}

class _IsolatedState extends State<_Isolated> {
  late final _container = ProviderContainer(
    overrides: widget.overrides,
    retry: (_, _) => null,
  );

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UncontrolledProviderScope(container: _container, child: widget.child);
}

Widget _radarr(
  RadarrService service,
  Widget child, {
  String? version = '5.14.0',
  SettingsModel settings = _oneRadarr,
  bool away = false,
  bool unanswered = false,
}) => _Isolated([
  // Away from home: a connection with no address away is reached only at
  // home, and asked nothing.
  if (away) awayFromHomeProvider.overrideWithValue(true),
  // Neither of the connection's addresses answered the route probe.
  if (unanswered) unansweredConnectionsProvider.overrideWith(_Unanswered.new),
  sharedPreferencesProvider.overrideWithValue(_prefs),
  secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
  initialSettingsProvider.overrideWithValue(settings),
  initialOnboardingCompletedProvider.overrideWithValue(true),
  initialActiveInstancesProvider.overrideWithValue(const {}),
  radarrServiceProvider.overrideWithValue(service),
  radarrServiceForProvider.overrideWith((ref, instanceId) => service),
  // A probe still in flight. Overridden above the client rather than through
  // it: the client's timeout would leave a timer running past the sheet.
  if (version == null)
    serviceSummaryProvider.overrideWith(
      (ref, service) => Completer<ServiceSummary>().future,
    ),
  serviceStatusClientFactoryProvider.overrideWithValue(
    ({
      required String baseUrl,
      required String apiKey,
      String? pinnedCertFingerprint,
      Map<String, String> accessHeaders = const {},
    }) => _StatusClient(version),
  ),
], child);

/// The five shapes a [ServiceOverviewRow] takes, one under another, as a
/// Needs attention section would draw them. Tones are walked against the
/// surface the rows sit on, as the screens do.
class _RowKinds extends StatelessWidget {
  const _RowKinds();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amber = statusToneColor(
      scheme,
      StatusTone.warning,
      surface: scheme.surfaceContainerLow,
    );
    Widget glyph(IconData icon) => Icon(icon, size: 18, color: amber);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServiceOverviewRow(
            spoken: 'Nickel Boys, only read',
            leading: glyph(Icons.sync_problem_rounded),
            title: 'Stuck\u00A0· Nickel Boys',
            titleColor: amber,
            detail: 'qBittorrent\u00A0· Nothing is arriving',
          ),
          ServiceOverviewRow(
            spoken: '3 indexers failing, a door',
            leading: glyph(Icons.error_outline_rounded),
            title: '3 indexers failing',
            titleColor: amber,
            detail: 'Nyaa, 1337x, Bitsearch',
            onTap: () {},
            doorHint: 'opens the Prowlarr Indexers tab',
          ),
          ServiceOverviewRow(
            spoken: 'Nyaa, a door with a figure',
            leading: glyph(Icons.error_outline_rounded),
            title: 'Nyaa',
            detail: 'failing\u00A0· disabled until 15:40',
            trailing: '298 queries',
            onTap: () {},
            doorHint: 'opens the Prowlarr Indexers tab',
          ),
          ServiceOverviewRow(
            spoken: 'Nyaa failing, a door with its remedy',
            leading: glyph(Icons.error_outline_rounded),
            title: 'Nyaa',
            titleColor: amber,
            detail: 'failing\u00A0· disabled until 15:40',
            onTap: () {},
            doorHint: 'opens Nyaa',
            action: ServiceOverviewRowAction.remedy(
              label: 'Test',
              hint: 'tests Nyaa',
              onPressed: () {},
            ),
          ),
          ServiceOverviewRow(
            spoken: 'Stuck, Nickel Boys, a door with a long remedy',
            leading: glyph(Icons.sync_problem_rounded),
            title: 'Stuck\u00A0· Nickel.Boys.2024.2160p.WEB-DL',
            titleColor: amber,
            detail: '18%\u00A0· idle 42\u00A0min\u00A0· no seeds',
            onTap: () {},
            doorHint: 'opens this download',
            action: ServiceOverviewRowAction.remedy(
              label: 'Look for peers again',
              hint: 'asks the trackers again for Nickel Boys',
              onPressed: () {},
            ),
          ),
          ServiceOverviewRow(
            spoken: 'immich is stopped, a verb alone',
            leading: glyph(Icons.stop_circle_outlined),
            title: '1 stack is stopped',
            detail: 'immich\u00A0· Dockge does not say why',
            action: ServiceOverviewRowAction(
              label: 'Start',
              hint: 'starts immich',
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  catalogCard(
    'ServiceOverview',
    width: 1328,
    scenes: [
      CatalogScene(
        'RadarrOverviewScreen · loaded · identity, readouts, then Coming up, '
        'Needs attention, Recently added and History in one scroll',
        (_) => _radarr(
          _ScriptedRadarr(),
          const RadarrOverviewScreen(topPadding: 0),
        ),
        width: 390,
        height: 900,
      ),
      CatalogScene(
        'RadarrOverviewScreen · the library timed out · the server answers, '
        'so the failure is amber: every figure the library owns reads —, and '
        'the two sections built on it fail in their own slots while the queue '
        'and history still draw',
        (_) => _radarr(
          _ScriptedRadarr(
            libraryFailure: DioException(
              requestOptions: RequestOptions(path: '/api/v3/movie'),
              type: DioExceptionType.receiveTimeout,
            ),
          ),
          const RadarrOverviewScreen(topPadding: 0),
        ),
        width: 390,
        height: 1180,
      ),
      CatalogScene(
        'RadarrOverviewScreen · did not answer · red, and only here: the '
        'version is —, never the v3 API fallback',
        (_) => _radarr(
          _ScriptedRadarr(
            libraryFailure: const SocketException('Connection refused'),
          ),
          const RadarrOverviewScreen(topPadding: 0),
          version: '',
        ),
        width: 390,
        height: 420,
      ),
      CatalogScene(
        'RadarrOverviewScreen · away from home, a connection with no address '
        'away · Only at home on the identity line, then one line for the whole '
        'page with Add an address away in ink, never one per section',
        (_) => _radarr(
          _ScriptedRadarr(),
          const RadarrOverviewScreen(topPadding: 0),
          away: true,
        ),
        width: 390,
        height: 260,
      ),
      CatalogScene(
        'RadarrOverviewScreen · neither address answered · Did not answer on '
        'the identity line, then one red for the whole page naming both '
        'addresses, with Retry a ghost in ink that knocks at both',
        (_) => _radarr(
          _ScriptedRadarr(
            libraryFailure: const SocketException('Connection refused'),
          ),
          const RadarrOverviewScreen(topPadding: 0),
          version: '',
          settings: _radarrHomeAndAway,
          unanswered: true,
        ),
        width: 390,
        height: 300,
      ),
      CatalogScene(
        'RadarrOverviewScreen · loading · Checking, row skeletons and a — '
        'count while every source is in flight',
        (_) => _radarr(
          _PendingRadarr(),
          const RadarrOverviewScreen(topPadding: 0),
          version: null,
        ),
        width: 390,
        height: 760,
      ),
      CatalogScene(
        'ServiceTabScaffold + RadarrOverviewScreen · desktop window, two '
        'connections · the lit header replaces both phone bands; the lens '
        'chip joins the identity line',
        (_) => _radarr(
          _ScriptedRadarr(),
          const ServiceTabScaffold(
            service: ServiceKey.radarr,
            tab: ServiceTab.overview,
            child: RadarrOverviewScreen(
              topPadding: kToolbarHeight + ServiceTabBar.height,
            ),
          ),
          settings: _twoRadarrs,
        ),
        width: 1280,
        height: 940,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'ServiceOverviewRow · what a row can be: a plain row (only read), a '
        'door with its chevron (one button, the whole row at least 44 tall), '
        'a door with a figure, a door with a verb beside it (the verb is the '
        'mark, in the ink, never the fault\'s tone), the same with a long verb '
        '(capped under half the row, the words keep the rest) and a verb with '
        'no door',
        (_) => const _RowKinds(),
        width: 390,
        height: 520,
      ),
      CatalogScene(
        'Text at 200% · ServiceOverviewRow as a door and as a door with its '
        'verb: the title wraps, the verb stays one line at its 44pt floor',
        (_) => const _RowKinds(),
        width: 390,
        height: 1500,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · RadarrOverviewScreen loaded: identity, readouts and '
        'the sections at twice the reading size',
        (_) => _radarr(
          _ScriptedRadarr(),
          const RadarrOverviewScreen(topPadding: 0),
        ),
        width: 390,
        height: 1600,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'ArrNeedsAttentionSection · Sonarr, the queue stopped answering after '
        'it had: the header keeps counting the two faults still drawn under it '
        '(Sonarr and Lidarr printed a dash here, over rows they were showing)',
        (_) => _radarr(
          _ScriptedRadarr(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ArrNeedsAttentionSection<SonarrAttentionKind>(
              service: ServiceKey.sonarr,
              items: _sonarrAttention,
              queueRecords: _sonarrQueuePage,
              retry: const [],
            ),
          ),
          settings: _oneSonarr,
        ),
        width: 390,
        height: 440,
        id: 'arr-needs-attention-failed-after-answering',
        act: (tester, scene) async {
          final section = find.descendant(
            of: scene,
            matching: find.byType(
              ArrNeedsAttentionSection<SonarrAttentionKind>,
            ),
          );
          ProviderScope.containerOf(
            tester.element(section),
          ).read(_sonarrAttention.notifier).stopAnswering();
        },
      ),
      CatalogScene(
        'TracearrViolationScreen · an unseen violation: the rule blue, the '
        'two places and the distance, the automatic actions with the failed '
        'one amber, and Acknowledge and Dismiss dimmed (no owner signed in)',
        (_) => _violation(_travel()),
        width: 390,
        height: 1500,
        id: 'tracearr-violation-unseen-travel',
      ),
      CatalogScene(
        'TracearrViolationScreen · a rule Cupola does not read, already '
        'acknowledged, the owner signed in: its name and the way to open '
        'Tracearr, Dismiss at full ink and no Acknowledge',
        (_) => _violation(_unknownRule(), owner: true),
        width: 390,
        height: 1100,
        id: 'tracearr-violation-unknown-rule',
      ),
      CatalogScene(
        'Text at 200% · RadarrOverviewScreen, the library timed out: the amber '
        'failure and the figures that read a dash',
        (_) => _radarr(
          _ScriptedRadarr(
            libraryFailure: DioException(
              requestOptions: RequestOptions(path: '/api/v3/movie'),
              type: DioExceptionType.receiveTimeout,
            ),
          ),
          const RadarrOverviewScreen(topPadding: 0),
        ),
        width: 390,
        height: 1800,
        textScale: catalogTextScale,
      ),
    ],
  );
}
