import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/outside/data/outside_run.dart';
import 'package:cupola/features/outside/data/outside_shelf.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/outside/domain/outside_snapshot.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

import '../../../test_helpers/settings_scope.dart';

/// The run: what it reads, what it writes where the widgets read it, and
/// what it says.
void main() {
  // Friday 16 October 2026, 14:02.
  final now = DateTime(2026, 10, 16, 14, 2);
  late Directory folder;
  late OutsideShelf shelf;
  final fetched = <String>[];

  setUp(() {
    folder = Directory.systemTemp.createTempSync('outside');
    shelf = OutsideShelf(folder);
    fetched.clear();
  });
  tearDown(() => folder.deleteSync(recursive: true));

  OutsideRun runner({DateTime? at}) => OutsideRun(
    shelf: shelf,
    clock: () => at ?? now,
    fetch: (source) async {
      fetched.add(source.url);
      return utf8.encode('picture of ${source.url}');
    },
  );

  final tonight = CalendarEvent(
    identity: 'Sintel',
    kind: CalendarKind.episode,
    day: DateTime(2026, 10, 16),
    airsAt: DateTime(2026, 10, 16, 21),
    title: 'Sintel',
    season: 1,
    episode: 4,
    state: const CalendarState.notYet(),
    poster: (url: 'https://sonarr.home/poster.jpg', headers: null),
    target: const CalendarMediaTarget(MediaKey.tv(7)),
  );

  ServicesInFlight queue() => (
    preview: const [
      ServiceQueueItem(
        service: ServiceKey.radarr,
        id: '1',
        title: 'Tears of Steel',
        progress: 0.68,
        clientLabel: 'qBittorrent',
        etaSeconds: 360,
        clientService: ServiceKey.qbittorrent,
        instanceId: 'radarr',
      ),
    ],
    activeCount: 1,
    movingCount: 1,
    queued: const [],
    faults: const [],
    held: 0,
    rateBytesPerSecond: 2400000,
    clients: 1,
    coverage: SourceCoverage.merge([
      SourceCoverage.answeredBy(ServiceKey.radarr),
      SourceCoverage.answeredBy(ServiceKey.qbittorrent),
    ]),
  );

  DashboardDecision stuck(String title) => DashboardDecision(
    kind: DecisionKind.stalledDownload,
    id: 'stalled-$title',
    service: ServiceKey.qbittorrent,
    title: title,
    detail: 'detail',
    occurredAt: null,
  );

  var sourceReads = 0;

  Future<ProviderContainer> operator({
    List<DashboardDecision> faults = const [],
    bool queueAnswers = true,
  }) async {
    final overrides = <Override>[
      ...await settingsScopeOverrides(
        configured: const [
          ServiceKey.sonarr,
          ServiceKey.radarr,
          ServiceKey.qbittorrent,
        ],
      ),
      hasLibraryCalendarProvider.overrideWithValue(true),
      libraryCalendarProvider.overrideWith(
        (ref) async => LibraryCalendar(
          window: CalendarWindow.from(now),
          events: [tonight],
          answered: const ['Sonarr'],
          silent: const [],
          kinds: const {CalendarKind.episode},
          readAt: now,
        ),
      ),
      servicesInFlightProvider.overrideWith(
        (ref) async =>
            queueAnswers ? queue() : throw const SocketException('away'),
      ),
      dashboardDecisionSourceProvider.overrideWith((ref, source) async {
        sourceReads++;
        return (decisions: faults, coverage: SourceCoverage.none);
      }),
      dashboardFaultDecisionsProvider.overrideWithValue((
        decisions: faults,
        coverage: SourceCoverage.answeredBy(ServiceKey.qbittorrent),
      )),
    ];
    // As the run with no screen builds its own: a read that failed is a read
    // that did not answer, not one to wait on while it is tried again.
    final container = ProviderContainer(
      overrides: overrides,
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  Map<String, Object?> snapshot() =>
      jsonDecode(File('${folder.path}/outside.json').readAsStringSync())
          as Map<String, Object?>;

  test(
    'the operator\'s widgets are written, with the pictures they name',
    () async {
      final container = await operator();
      await runner().run(
        container,
        speak: false,
        enabled: const {},
        probe: false,
      );
      final json = snapshot();
      expect(json['audience'], 'operator');
      final widgets = json['widgets']! as Map;
      expect(widgets.keys, unorderedEquals(['comingUp', 'downloads']));
      final lead = (widgets['comingUp'] as List).first['face']['lead'] as Map;
      expect(lead['title'], 'Sintel');
      expect(fetched, ['https://sonarr.home/poster.jpg']);
      expect(
        File('${shelf.pictures.path}/${lead['poster']}').existsSync(),
        isTrue,
      );
    },
  );

  test('a picture that never arrives does not hold the snapshot back', () async {
    // A server that accepts the connection and then says nothing: the cache
    // manager has no deadline, so the run used to wait on it for as long as the
    // socket lived, with the frames it had already read unwritten.
    final patient = OutsideShelf(
      folder,
      pictureTimeout: const Duration(milliseconds: 200),
    );
    final run = OutsideRun(
      shelf: patient,
      clock: () => now,
      fetch: (_) => Completer<List<int>?>().future,
    );

    await run
        .run(await operator(), speak: false, enabled: const {}, probe: false)
        .timeout(const Duration(seconds: 5));

    final widgets = snapshot()['widgets']! as Map;
    expect(widgets.keys, unorderedEquals(['comingUp', 'downloads']));
    expect(
      patient.pictures.listSync(),
      isEmpty,
      reason: 'the widget draws without the poster',
    );
  });

  test('a widget whose read did not answer keeps the frames it had', () async {
    await runner().run(
      await operator(),
      speak: false,
      enabled: const {},
      probe: false,
    );
    final before = (snapshot()['widgets'] as Map)['downloads'];
    await runner(at: now.add(const Duration(minutes: 30))).run(
      await operator(queueAnswers: false),
      speak: false,
      enabled: const {},
      probe: false,
    );
    expect((snapshot()['widgets'] as Map)['downloads'], before);
  });

  test('a fault is said once it is new, never at the first read', () async {
    const needsYou = {OutsideNoticeKind.needsYou};
    final first = await runner().run(
      await operator(faults: [stuck('Charge')]),
      speak: true,
      enabled: needsYou,
      probe: false,
    );
    expect(first.say, isEmpty);
    final second = await runner(at: now.add(const Duration(minutes: 15))).run(
      await operator(faults: [stuck('Charge'), stuck('Spring')]),
      speak: true,
      enabled: needsYou,
      probe: false,
    );
    expect(second.say.map((notice) => notice.body), ['Spring is stuck']);
  });

  test('a kind switched off asks its servers nothing', () async {
    sourceReads = 0;
    await runner().run(
      await operator(faults: [stuck('Charge')]),
      speak: true,
      enabled: const {},
      probe: false,
    );
    expect(sourceReads, 0);
  });

  test('the requester gets her widget and none of the operator\'s', () async {
    final request = SeerrRequest.fromJson({
      'id': 4,
      'status': 2,
      'type': 'movie',
      'createdAt': now.subtract(const Duration(days: 2)).toIso8601String(),
      'media': {
        'id': 4,
        'tmdbId': 104,
        'mediaType': 'movie',
        'status': 5,
        'title': 'Spring',
        'posterPath': '/spring.jpg',
        'mediaAddedAt': now
            .subtract(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
      },
    }, numbering: SeerrNumbering.seerr);
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(configured: const [ServiceKey.seerr]),
        shellAudienceProvider.overrideWith(_Requester.new),
        requestsProvider.overrideWith((ref) async => [request]),
      ],
    );
    addTearDown(container.dispose);
    await runner().run(
      container,
      speak: false,
      enabled: const {},
      probe: false,
    );
    final json = snapshot();
    expect(json['audience'], 'requester');
    expect((json['widgets'] as Map).keys, ['requests']);
  });

  test('another person\'s frames are not kept', () async {
    await runner().run(
      await operator(),
      speak: false,
      enabled: const {},
      probe: false,
    );
    final plan = await shelf.plan(
      OutsideSnapshot(takenAt: now, audience: 'requester', frames: const {}),
      unread: {OutsideWidget.downloads},
    );
    expect((plan.json['widgets'] as Map).containsKey('downloads'), isFalse);
  });
}

class _Requester extends ShellAudienceNotifier {
  @override
  Audience build() => Audience.requester;
}
