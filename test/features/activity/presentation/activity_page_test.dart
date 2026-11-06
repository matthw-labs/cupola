/// Activity's four views on the profiles: what each draws, in which order,
/// what it leaves out when it has nothing to say, and what it says when a
/// source did not answer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/core/widgets/page_tabs.dart';
import 'package:cupola/core/widgets/setup_doors.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_history_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/needs_you_cards.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_board.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_job_card.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';
import '../../../test_helpers/profiles/profiles.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * 1024 * 1024;

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

/// A queue with nothing in it, whatever the profile's clients hold.
final _quiet = <Override>[
  servicesQueueProvider.overrideWith(
    (ref) async =>
        (items: const <ServiceQueueItem>[], coverage: SourceCoverage.none),
  ),
];

final _clocks = <Override>[
  arrivalsClockProvider.overrideWith(
    (ref) =>
        () => _now,
  ),
  stallClockProvider.overrideWith(
    (ref) =>
        () => _now,
  ),
];

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  ActivityTab tab, {
  String? requestsOf,
  double textScale = 1,
  Size size = const Size(430, 8000),
  List<Override> overrides = const [],
  List<ProviderObserver> observers = const [],
}) async => _mount(
  tester,
  await ProfileHarness.start(
    profile,
    now: _now,
    overrides: [..._clocks, ...overrides],
  ),
  tab,
  requestsOf: requestsOf,
  textScale: textScale,
  size: size,
  observers: observers,
);

/// Mounts the page on a harness the test has already scripted.
Future<ProfileHarness> _mount(
  WidgetTester tester,
  ProfileHarness harness,
  ActivityTab tab, {
  String? requestsOf,
  double textScale = 1,
  Size size = const Size(430, 8000),
  List<ProviderObserver> observers = const [],
}) async {
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      observers: observers,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: ActivityPage(tab: tab, requestsOf: requestsOf),
          ),
        ),
      ),
    ),
  );
  await harness.settle(tester);
  // Some answers (Seerr's list among them) are mapped on an isolate, which
  // fake time never turns: give the real loop a moment, then settle again.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await harness.settle(tester);
  return harness;
}

/// The sections the page draws, in order, as their name and what they count.
List<String> _sections(WidgetTester tester) => [
  for (final section in tester.widgetList<ActivitySection>(
    find.byType(ActivitySection),
  ))
    section.meta == null
        ? section.title
        : '${section.title}\u00A0· ${section.meta}',
];

List<String> _titles(WidgetTester tester) => [
  for (final section in tester.widgetList<ActivitySection>(
    find.byType(ActivitySection),
  ))
    section.title,
];

/// The page's name and what it says under it, before the views.
Iterable<String> _readout(WidgetTester tester) sync* {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final words = text.data ?? text.textSpan?.toPlainText() ?? '';
    if (words == 'All') return;
    yield words;
  }
}

/// [matching] inside the section named [title].
Finder _inSection(String title, Finder matching) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is ActivitySection && widget.title == title,
  ),
  matching: matching,
);

/// A download of a client no arr asked for.
WorldDownload _torrent(
  int n, {
  DownloadState state = DownloadState.downloading,
  int speed = 0,
}) => WorldDownload(
  id: 'a1f0c3d4e5f60718293a4b5c6d7e8f90123457${n.toString().padLeft(2, '0')}',
  release: 'Hand.Added.$n.2024.1080p',
  client: 'qbittorrent',
  state: state,
  progress: state == DownloadState.queued ? 0 : 0.4,
  size: _gb,
  speed: speed,
);

/// A grab of [arr], a Sonarr connection, moving through qBittorrent.
WorldDownload _grab(int n, String arr) => WorldDownload(
  id: 'a1f0c3d4e5f60718293a4b5c6d7e8f90123458${n.toString().padLeft(2, '0')}',
  release: 'Show.$n.S01E01.1080p',
  client: 'qbittorrent',
  state: DownloadState.downloading,
  progress: 0.4,
  size: _gb,
  arr: arr,
  title: WorldTitles.cosmosLaundromat,
  season: 1,
  episode: n,
  speed: 2 * _mb,
  eta: const Duration(minutes: 10),
);

/// A history record as an arr sends it, with the movie it embeds.
Map<String, Object?> _import(
  ProfileHarness harness,
  int id,
  Duration ago, {
  String event = 'downloadFolderImported',
  Map<String, Object?>? data,
}) => {
  'id': id,
  'movieId': id,
  'eventType': event,
  'sourceTitle': 'Movie.$id.2024.1080p',
  'date': harness.network.now.subtract(ago).toUtc().toIso8601String(),
  'movie': {'id': id, 'title': 'Movie $id', 'year': 2024, 'tmdbId': 900 + id},
  'data': data ?? const <String, Object?>{},
};

void main() {
  group('All', () {
    testWidgets('P1: the sections in their order, each with what it counts', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.all);

      expect(_sections(tester), [
        'Needs you\u00A0· 3 faults\u00A0· 3 requests',
        "Everyone's requests\u00A0· 5 total",
        'Watching now\u00A0· Jellyfin',
        'Downloads\u00A0· 4 moving\u00A0· 1 stuck',
        'Up next\u00A0· 1 queued',
        'Finished today\u00A0· 3',
      ]);

      await harness.unmount(tester);
    });

    testWidgets('P1: the page says its name, what moves, how fast and what is '
        'stuck, as one sentence to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _pump(tester, Profiles.p1, ActivityTab.all);

      expect(_readout(tester), [
        'Activity',
        '4 moving',
        '·',
        '40.4 MB/\u2060s',
        '·',
        '1 stuck',
      ]);
      // The speed is part of it: a split on a plain space once dropped it.
      expect(
        find.semantics.byLabel(
          'Activity\n4 moving, 40.4 megabytes a second, 1 stuck',
        ),
        findsOneWidget,
      );
      // Its section's heading says the same without a middle dot.
      expect(
        find.semantics.byLabel('Downloads, 4 moving, 1 stuck'),
        findsOneWidget,
      );

      handle.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a section with nothing to say is not drawn: no media '
        'server, no Watching now; no queue behind a client, no Up next', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p3, ActivityTab.all);

      // P3: Radarr, Sonarr and Seerr, and no client or media server.
      expect(_titles(tester), [
        'Needs you',
        "Everyone's requests",
        'Downloads',
        'Finished today',
      ]);
      await harness.unmount(tester);
    });

    testWidgets('no Seerr, no Everyone\'s requests', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.without(ServiceKey.seerr),
        ActivityTab.all,
      );

      expect(_titles(tester), [
        'Needs you',
        'Watching now',
        'Downloads',
        'Up next',
        'Finished today',
      ]);
      expect(find.text("Everyone's requests"), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('P1: Needs you counts the faults and the requests apart, and '
        'draws each', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.all);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivityPage)),
      );
      final decisions = container.read(dashboardDecisionsProvider).decisions;
      final faults = decisions.where((d) => d.isFault).length;
      final requests = decisions
          .where((d) => d.kind == DecisionKind.pendingRequest)
          .length;
      expect((faults, requests), (3, 3));
      expect(find.text('3 faults\u00A0· 3 requests'), findsOneWidget);
      expect(find.text('3 requests wait for your approval'), findsOneWidget);
      // Every fault is a card with its way out, every request a row with
      // Approve and Decline.
      expect(find.byType(FaultCard), findsNWidgets(faults));
      expect(find.byType(DecisionRow), findsNWidgets(requests));
      for (final title in ['Charge', 'Metropolis', 'Night Shift']) {
        expect(find.byTooltip('Approve $title'), findsOneWidget);
      }

      await harness.unmount(tester);
    });

    testWidgets('faults alone read as faults, and nothing wrong draws no '
        'Needs you', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.without(ServiceKey.seerr),
        ActivityTab.all,
      );
      expect(find.text('3 faults'), findsOneWidget);
      expect(find.textContaining('request'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('P1: Everyone\'s requests counts the list, shows the latest '
        'three and sums up the rest', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.all);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivityPage)),
      );
      final total = container.read(requestsProvider).requireValue.length;
      expect(total, 8);
      // Seerr's eight less the three waiting above the section.
      expect(find.text('${total - 3} total'), findsOneWidget);
      // Three rows, newest first: what arrived and what moves. (Coffee Run
      // is also under Finished today, hence the section.)
      for (final title in ['Coffee Run', 'Sintel', 'Sprite Fright']) {
        expect(
          _inSection("Everyone's requests", find.text(title)),
          findsOneWidget,
          reason: title,
        );
      }
      expect(find.text('Ready to watch since 17:53'), findsOneWidget);
      expect(
        find.text('Downloading 62%\u00A0· ready around 21:04'),
        findsOneWidget,
      );
      expect(find.text('All 8 requests'), findsOneWidget);
      expect(find.text('2 processing'), findsOneWidget);

      await harness.unmount(tester);
    });

    group('a Seerr list that lost a page', () {
      /// 120 requests in pages of 50, the first page answering and every
      /// later one failing. [count] is what Seerr's first page says it holds.
      Future<ProfileHarness> lostPage(
        WidgetTester tester, {
        required int? count,
      }) async {
        final harness = await ProfileHarness.start(
          Profiles.p2,
          now: _now,
          overrides: _clocks,
        );
        harness.network.on(WorldIds.seerr, 'GET', '/api/v1/request', (request) {
          final skip = int.tryParse(request.query['skip'] ?? '') ?? 0;
          if (skip >= 50) {
            return NetworkReply.json({'message': 'boom'}, status: 500);
          }
          return NetworkReply.json({
            'pageInfo': {'pages': 3, 'pageSize': 50, 'results': ?count},
            'results': [
              for (var i = 0; i < 50; i++)
                {
                  'id': i + 1,
                  'status': 2,
                  'createdAt': '2026-10-09T10:00:00.000Z',
                  'type': 'movie',
                  'media': {
                    'id': i + 1,
                    'tmdbId': 1000 + i,
                    'status': 3,
                    'mediaType': 'movie',
                    'title': 'Request ${i + 1}',
                  },
                },
            ],
          });
        });
        return _mount(tester, harness, ActivityTab.all);
      }

      testWidgets("keeps Seerr's own count: 120, never the 50 that came", (
        tester,
      ) async {
        final harness = await lostPage(tester, count: 120);

        expect(
          _sections(tester),
          contains("Everyone's requests\u00A0· 120 total"),
        );
        expect(find.text('All 120 requests'), findsOneWidget);
        expect(find.text('50 total'), findsNothing);
        // What is tallied over the rows that came is short of the whole, so
        // it is left unsaid.
        expect(find.textContaining('processing'), findsNothing);

        await harness.unmount(tester);
      });

      testWidgets('with no count from Seerr the rows are a floor: 50+', (
        tester,
      ) async {
        final harness = await lostPage(tester, count: null);

        expect(
          _sections(tester),
          contains("Everyone's requests\u00A0· 50+ total"),
        );
        expect(find.text('All 50+ requests'), findsOneWidget);
        expect(find.text('50 total'), findsNothing);

        await harness.unmount(tester);
      });
    });

    testWidgets('Downloads on All stops at five rows and leads to the '
        'rest', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withDownloads([
          for (var n = 1; n <= 3; n++) _torrent(n, speed: 2 * _mb),
        ]),
        ActivityTab.all,
      );

      // Seven moving and the stuck one.
      expect(find.byType(ActivityDownloadRow), findsNWidgets(6));
      expect(find.text('All 8 downloads'), findsOneWidget);
      // The stuck row is kept, and drawn last.
      expect(find.text('Stuck at 47%'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Stuck at 47%')).dy,
        greaterThan(tester.getTopLeft(find.text('Hand.Added.1.2024.1080p')).dy),
      );

      await harness.unmount(tester);
    });

    testWidgets('Up next on All stops at three and leads to the rest', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withDownloads([
          for (var n = 1; n <= 3; n++) _torrent(n, state: DownloadState.queued),
        ]),
        ActivityTab.all,
      );

      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('4 queued'), findsOneWidget);
      final queuedRows = find.byWidgetPredicate(
        (widget) =>
            widget is ActivityDownloadRow &&
            widget.item.queued &&
            widget.item.isActive,
      );
      expect(queuedRows, findsNWidgets(3));
      expect(find.text('All 4 queued'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P1: Watching now names who and what, on which server', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.all);

      expect(find.text('Anna\u00A0· Sintel'), findsOneWidget);
      expect(find.text('Jellyfin'), findsWidgets);

      await harness.unmount(tester);
    });

    testWidgets('P1: Finished today is the day\'s imports, newest first, each '
        'with the file it became', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.all);

      expect(find.byType(ActivityHistoryRow), findsNWidgets(3));
      final spring = tester.getTopLeft(find.text('Spring (2014).mkv')).dy;
      final coffee = tester.getTopLeft(find.text('Coffee Run (2020).mkv')).dy;
      final cosmos = tester
          .getTopLeft(find.text('Cosmos.Laundromat.S02E03.1080p.WEB'))
          .dy;
      expect(spring, lessThan(coffee));
      expect(coffee, lessThan(cosmos));
      expect(find.text('Imported 18:52'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('Finished today stops at five and leads to History', (
      tester,
    ) async {
      final harness = await ProfileHarness.start(
        Profiles.p1,
        now: _now,
        overrides: _clocks,
      );
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/history/since',
        (r) => NetworkReply.json([
          for (var n = 1; n <= 6; n++)
            _import(
              harness,
              n,
              Duration(minutes: 10 * n),
              data: {'importedPath': '/m/Movie $n (2024).mkv'},
            ),
        ]),
      );
      await _mount(tester, harness, ActivityTab.all);

      // Six from Radarr and the others' three: the day has more than five.
      final shown = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is ActivitySection && widget.title == 'Finished today',
        ),
        matching: find.byType(ActivityHistoryRow),
      );
      expect(shown, findsNWidgets(5));
      expect(find.text('All of today in History'), findsOneWidget);
      // Newest first: ten minutes ago leads.
      expect(find.text('Movie 1 (2024).mkv'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  group('Downloads', () {
    testWidgets('P1: what moves as its queue orders it, the stuck one last '
        'with the proof, then Up next', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.downloads);

      expect(_sections(tester), [
        'Downloads\u00A0· 4 moving\u00A0· 1 stuck',
        'Up next\u00A0· 1 queued',
      ]);
      final order = [
        'Cosmos Laundromat\u00A0· S2 E4',
        'Sprite Fright',
        'Elephants Dream',
        'Cosmos Laundromat\u00A0· S2 E5',
        'Big Buck Bunny',
      ];
      final ys = [
        for (final title in order)
          tester.getTopLeft(_inSection('Downloads', find.text(title))).dy,
      ];
      expect(ys, [...ys]..sort());
      // The stuck row says where it stopped and how long nothing came.
      expect(find.text('Stuck at 47%'), findsOneWidget);
      expect(find.text('nothing for 3\u00A0h'), findsOneWidget);
      // Which way the bytes go, and a moving row's own speed.
      expect(find.text('Radarr 4K → SABnzbd'), findsNWidgets(2));
      expect(find.text('12.1\u00A0MB/\u2060s'), findsOneWidget);
      // Whose request brought it, and when it should be ready.
      expect(
        find.text("Anna's request\u00A0· ready around 21:04"),
        findsOneWidget,
      );
      // Up next: when SABnzbd says it starts, and who asked.
      expect(
        find.text('Queued\u00A0· starts in about 6\u00A0min'),
        findsOneWidget,
      );
      expect(find.text("Anna's request"), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P1, SABnzbd\'s disk full: the two jobs it stopped are stuck '
        'in the readout beside the one that was', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withFullDisk(WorldIds.sabnzbd),
        ActivityTab.all,
      );

      // Big Buck Bunny, and Elephants Dream and Sintel on the 4K.
      expect(_readout(tester), contains('3 stuck'));
      expect(_sections(tester), contains(startsWith('Downloads\u00A0· ')));
      expect(
        _sections(tester).firstWhere((line) => line.startsWith('Downloads')),
        endsWith('3 stuck'),
      );

      await harness.unmount(tester);
    });

    testWidgets('P1, SABnzbd paused: what it holds is listed last, stopped, '
        'where its Resume is; All leaves it out', (tester) async {
      final paused = Profiles.p1.withPausedQueue(WorldIds.sabnzbd);
      var harness = await _pump(tester, paused, ActivityTab.downloads);

      expect(find.textContaining('Stopped at'), findsWidgets);
      // Last: below every row that moves or is stuck.
      final stoppedY = tester
          .getTopLeft(find.textContaining('Stopped at').first)
          .dy;
      expect(
        tester.getTopLeft(find.text('Stuck at 47%')).dy,
        lessThan(stoppedY),
      );
      await harness.unmount(tester);

      harness = await _pump(tester, paused, ActivityTab.all);
      expect(find.textContaining('Stopped at'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('no search, no group', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.downloads);

      expect(find.text('Searching'), findsNothing);
      expect(find.byType(ReleaseSearchJobCard), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a search stands at the head, above Downloads', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.downloads);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivityPage)),
      );
      final jobs = container.read(releaseSearchJobsProvider.notifier);
      jobs.configure(runner: (_, _) => Completer<List<dynamic>>().future);
      jobs.start(
        const ReleaseSearchTarget.movie(
          movieId: 2,
          label: 'Sintel',
        ).stampedWith(WorldIds.radarr4k),
      );
      await tester.pump();

      // The heading, and the card's own state under it.
      expect(find.text('Searching'), findsWidgets);
      expect(find.text('1 search'), findsOneWidget);
      expect(find.byType(ReleaseSearchJobCard), findsOneWidget);
      // A pull reaches it as it reaches the rest: it is in the page's scroll.
      expect(
        find.ancestor(
          of: find.byType(ReleaseSearchJobCard),
          matching: find.byType(RefreshIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Searching').first).dy,
        lessThan(
          tester.getTopLeft(_inSection('Downloads', find.text('Downloads'))).dy,
        ),
      );

      await harness.unmount(tester);
    });

    testWidgets('with nothing moving the view says so, and when the last '
        'download finished', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.downloads,
        overrides: _quiet,
      );

      expect(find.text('Nothing is downloading'), findsOneWidget);
      // Under the title and under the section: the same moment.
      expect(find.text('Nothing moving'), findsOneWidget);
      expect(find.text('Last download finished 18:52'), findsNWidgets(2));
      expect(find.byType(ActivityDownloadRow), findsNothing);
      expect(_titles(tester), ['Downloads']);

      await harness.unmount(tester);
    });

    testWidgets(
      'on All a quiet queue is the title\'s to say, not a section\'s',
      (tester) async {
        final harness = await _pump(
          tester,
          Profiles.p1,
          ActivityTab.all,
          overrides: _quiet,
        );

        expect(find.text('Nothing moving'), findsOneWidget);
        expect(find.text('Last download finished 18:52'), findsOneWidget);
        expect(find.text('Nothing is downloading'), findsNothing);
        expect(_titles(tester), contains('Finished today'));
        expect(_titles(tester), isNot(contains('Downloads')));

        await harness.unmount(tester);
      },
    );

    testWidgets('a read again keeps the rows on screen: a pull or a poll '
        'never blanks the list', (tester) async {
      final gate = Completer<void>();
      var reads = 0;
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.downloads,
        overrides: [
          servicesQueueProvider.overrideWith((ref) async {
            reads++;
            // The first read answers; every later one is held open, so the
            // reload itself is what is on screen.
            if (reads > 1) await gate.future;
            return (
              items: const [
                ServiceQueueItem(
                  service: ServiceKey.radarr,
                  id: '1',
                  title: 'Furiosa.2024.2160p',
                  progress: 0.75,
                  clientLabel: 'qBittorrent',
                  clientService: ServiceKey.qbittorrent,
                  etaSeconds: 600,
                ),
              ],
              coverage: SourceCoverage.none,
            );
          }),
        ],
      );
      expect(find.byType(ActivityDownloadRow), findsOneWidget);
      expect(_sections(tester), ['Downloads\u00A0· 1 moving']);

      ProviderScope.containerOf(
        tester.element(find.byType(ActivityPage)),
      ).invalidate(servicesQueueProvider);
      await tester.pump(const Duration(milliseconds: 10));
      expect(reads, 2);

      // Mid-read the row and the count are the last answer's.
      expect(find.byType(ActivityDownloadRow), findsOneWidget);
      expect(_sections(tester), ['Downloads\u00A0· 1 moving']);
      expect(find.text('Nothing is downloading'), findsNothing);

      gate.complete();
      await harness.settle(tester);
      expect(find.byType(ActivityDownloadRow), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a queue that could not be read says so in its own place, '
        'with a Retry that reads it again', (tester) async {
      var reads = 0;
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.downloads,
        overrides: [
          servicesQueueProvider.overrideWith((ref) async {
            reads++;
            throw Exception('down');
          }),
        ],
      );
      final first = reads;

      expect(find.byType(BriefFailureLine), findsOneWidget);
      expect(find.byType(ActivityDownloadRow), findsNothing);
      expect(find.text('Nothing is downloading'), findsNothing);

      await tester.tap(find.text('Retry'));
      await harness.settle(tester);
      expect(reads, greaterThan(first));

      await harness.unmount(tester);
    });
  });

  group('Requests', () {
    testWidgets('P1: the three that wait for you, answered where they are, '
        'then everyone\'s, counted by what the section lists, in the page\'s '
        'own scroll', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.requests);

      expect(find.byType(RequestsBoard), findsOneWidget);
      expect(find.text('3 requests wait for your approval'), findsOneWidget);
      for (final title in ['Charge', 'Metropolis', 'Night Shift']) {
        expect(find.byTooltip('Approve $title'), findsOneWidget, reason: title);
      }
      expect(_titles(tester), ["Everyone's requests"]);
      // Seerr's eight less the three that wait above: what the section lists.
      expect(_inSection("Everyone's requests", find.text('5 total')), findsOne);
      for (final title in [
        'Sprite Fright',
        'Coffee Run',
        'Sintel',
        'Tears of Steel',
        'Cosmos Laundromat',
      ]) {
        expect(
          _inSection("Everyone's requests", find.text(title)),
          findsOneWidget,
          reason: title,
        );
      }
      // The list is part of the page's own scroll.
      expect(
        find.descendant(
          of: find.byType(RequestsBoard),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('no requests says so', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.requests,
        overrides: [
          requestsProvider.overrideWith((ref) async => const <SeerrRequest>[]),
        ],
      );

      expect(find.text('No requests yet'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P4: with no Seerr it says it is not set up, and asks '
        'nobody', (tester) async {
      final failures = _FailureLog();
      final harness = await _pump(
        tester,
        Profiles.p4,
        ActivityTab.requests,
        observers: [failures],
      );
      // Past the first retry a failing read would have scheduled.
      await tester.pump(const Duration(minutes: 1));

      expect(find.text('Seerr is not set up'), findsOneWidget);
      expect(find.byType(RequestsBoard), findsOneWidget);
      expect(find.text('Set up Seerr'), findsOneWidget);
      // The dead end this replaced: an error state whose Retry asked nobody.
      expect(find.text('Retry'), findsNothing);
      expect(failures.providers, isEmpty);

      await harness.unmount(tester);
    });

    testWidgets('P3: with a Seerr it reads it, and says nothing is not set '
        'up', (tester) async {
      final harness = await _pump(tester, Profiles.p3, ActivityTab.requests);

      expect(find.text('Seerr is not set up'), findsNothing);
      expect(harness.network.requestsTo(WorldIds.seerr), isNotEmpty);

      await harness.unmount(tester);
    });

    testWidgets('a link naming a Seerr that is gone reads every Seerr, not '
        'a Seerr that is not set up', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.requests,
        requestsOf: 'seerr-deleted',
      );

      expect(find.text('Seerr is not set up'), findsNothing);
      expect(find.byTooltip('Approve Charge'), findsOneWidget);
      expect(find.textContaining(' only'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('with two Seerrs every one is read, and each row names its '
        'own', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withConnection(WorldConnections.seerrCabin),
        ActivityTab.requests,
      );

      for (final id in [WorldIds.seerr, WorldIds.seerrCabin]) {
        expect(
          harness.network
              .requestsTo(id)
              .where((r) => r.path == '/api/v1/request'),
          isNotEmpty,
          reason: id,
        );
      }
      // The same world behind both: each request twice, once on each.
      expect(find.byTooltip('Approve Charge'), findsNWidgets(2));
      expect(find.text('6 requests wait for your approval'), findsOneWidget);
      // Sixteen by Seerr's count, six of them waiting above the section.
      expect(
        _inSection("Everyone's requests", find.text('10 total')),
        findsOne,
      );
      expect(
        _inSection(
          "Everyone's requests",
          find.textContaining(RegExp(r'^Seerr \S')),
        ),
        findsNWidgets(10),
      );

      await harness.unmount(tester);
    });

    testWidgets('the connection the address names is the one read, said '
        'once, with the way back to every Seerr', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withConnection(WorldConnections.seerrCabin),
        ActivityTab.requests,
        requestsOf: WorldIds.seerrCabin,
      );

      expect(
        tester.widget<RequestsBoard>(find.byType(RequestsBoard)).only,
        WorldIds.seerrCabin,
      );
      expect(
        harness.network
            .requestsTo(WorldIds.seerrCabin)
            .where((r) => r.path == '/api/v1/request'),
        isNotEmpty,
      );
      expect(find.byTooltip('Approve Charge'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Seerr .+ only$')), findsOneWidget);
      expect(find.text('Show every Seerr'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  group('History', () {
    testWidgets('P1: the week by day, newest first, with the older history '
        'and the blocklist at the foot', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.history);

      expect(_sections(tester), [
        'Today\u00A0· 3',
        'Yesterday\u00A0· 1',
        'Wed 7 Oct\u00A0· 1',
      ]);
      // Nothing of the other views.
      expect(find.byType(ActivityDownloadRow), findsNothing);
      // Each import with the file it became.
      expect(find.text('Spring (2014).mkv'), findsOneWidget);
      expect(find.text('Tears of Steel (2012).mkv'), findsOneWidget);
      expect(
        find.text(
          'Older history stays in each service, under its History tab.',
        ),
        findsOneWidget,
      );
      final foot = [
        'Sonarr history',
        'Radarr history',
        'Lidarr history',
        'Blocklist',
      ];
      final ys = [
        for (final label in foot) tester.getTopLeft(find.text(label)).dy,
      ];
      expect(ys, [...ys]..sort());
      expect(
        find.text('Releases the arrs will not take again'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('a download that failed is in its day beside the imports, '
        'with why', (tester) async {
      final harness = await ProfileHarness.start(
        Profiles.p1,
        now: _now,
        overrides: _clocks,
      );
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/history/since',
        (r) => r.query['eventType'] == 'downloadFailed'
            ? NetworkReply.json([
                _import(
                  harness,
                  41,
                  const Duration(hours: 6, minutes: 51),
                  event: 'downloadFailed',
                  data: {'message': 'Aborted by the client'},
                ),
              ])
            : null,
      );
      await _mount(tester, harness, ActivityTab.history);

      expect(_sections(tester).first, 'Today\u00A0· 4');
      expect(find.text('Download failed 14:02'), findsOneWidget);
      expect(find.text('Aborted by the client'), findsOneWidget);
      // Beside the imports, newest first: the failure is the oldest of the
      // day, so it is last.
      expect(
        tester.getTopLeft(find.text('Download failed 14:02')).dy,
        greaterThan(tester.getTopLeft(find.text('Imported 18:10')).dy),
      );

      await harness.unmount(tester);
    });

    testWidgets('a week with nothing in it says so, and keeps the foot', (
      tester,
    ) async {
      final empty = (
        entries: const <ArrHistoryEntry>[],
        coverage: SourceCoverage.none,
      );
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.history,
        overrides: [
          servicesArrivalsProvider.overrideWith((ref) async => empty),
          servicesFailuresSinceProvider.overrideWith((ref) async => empty),
        ],
      );

      expect(
        find.text('Nothing finished in the last seven days'),
        findsOneWidget,
      );
      expect(_titles(tester), isEmpty);
      expect(find.text('Sonarr history'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a connection that did not answer is named, and the days are '
        'the others\'', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withBehaviour(
          WorldIds.radarr4k,
          ConnectionBehaviour.didNotAnswer,
        ),
        ActivityTab.history,
      );

      // Under the title, for the queue, and under the week.
      expect(find.text('Not in the total: Radarr 4K'), findsNWidgets(2));
      expect(find.text('Spring (2014).mkv'), findsNothing);
      expect(find.text('Coffee Run (2020).mkv'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a week that could not be read says so, with a Retry that '
        'reads both halves again', (tester) async {
      var reads = 0;
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.history,
        overrides: [
          servicesFailuresSinceProvider.overrideWith((ref) async {
            reads++;
            throw Exception('down');
          }),
        ],
      );

      // A read that throws is asked again with a growing wait before it is
      // called failed: the page draws nothing of the week until then, and
      // never a zero.
      expect(find.byType(BriefFailureLine), findsNothing);
      expect(_titles(tester), isEmpty);
      for (var second = 0; second < 60; second += 2) {
        await tester.pump(const Duration(seconds: 2));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      final first = reads;

      expect(find.byType(BriefFailureLine), findsOneWidget);
      expect(_titles(tester), isEmpty);

      await tester.tap(find.text('Retry'));
      await harness.settle(tester);
      expect(reads, greaterThan(first));

      await harness.unmount(tester);
    });
  });

  group('reading again', () {
    // A phone's height: a pull has to travel a quarter of it to count.
    const phone = Size(430, 900);

    int reads(ProfileHarness harness, String id, String path) => harness.network
        .requestsTo(id)
        .where((request) => request.uri.path.startsWith(path))
        .length;

    Future<void> pull(WidgetTester tester, ProfileHarness harness) async {
      await tester.drag(
        find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, 300),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      await harness.settle(tester);
    }

    testWidgets('a pull on Downloads reads the queues again', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.downloads,
        size: phone,
      );
      final before = reads(harness, WorldIds.radarr, '/api/v3/queue');
      expect(before, greaterThan(0));

      await pull(tester, harness);

      expect(
        reads(harness, WorldIds.radarr, '/api/v3/queue'),
        greaterThan(before),
      );
      // What it read again is on screen, not a skeleton.
      expect(find.byType(ActivityDownloadRow), findsWidgets);

      await harness.unmount(tester);
    });

    testWidgets('a pull on History reads the week again, both halves', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.history,
        size: phone,
      );
      final before = reads(harness, WorldIds.radarr, '/api/v3/history/since');
      expect(before, greaterThan(1));

      await pull(tester, harness);

      expect(
        reads(harness, WorldIds.radarr, '/api/v3/history/since'),
        greaterThan(before),
      );

      await harness.unmount(tester);
    });

    testWidgets('a pull on Requests reads the list again', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.requests,
        size: phone,
      );
      final before = reads(harness, WorldIds.seerr, '/api/v1/request');
      expect(before, greaterThan(0));

      await pull(tester, harness);

      expect(
        reads(harness, WorldIds.seerr, '/api/v1/request'),
        greaterThan(before),
      );

      await harness.unmount(tester);
    });

    testWidgets('a second tap on the Activity tab reads the page again', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.all,
        size: phone,
      );
      final before = reads(harness, WorldIds.radarr, '/api/v3/queue');

      ProviderScope.containerOf(tester.element(find.byType(ActivityPage)))
          .read(navigationRefreshProvider(NavigationSection.activity).notifier)
          .state++;
      await harness.settle(tester);

      expect(
        reads(harness, WorldIds.radarr, '/api/v3/queue'),
        greaterThan(before),
      );

      await harness.unmount(tester);
    });
  });

  group('a source that did not answer is named and not counted', () {
    testWidgets('P1, qBittorrent silent: the title says so, and the speed is '
        'the clients that answered', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withBehaviour(
          WorldIds.qbittorrent,
          ConnectionBehaviour.didNotAnswer,
        ),
        ActivityTab.all,
      );

      expect(find.text('Not in the total: qBittorrent'), findsWidgets);
      // The torrents' rates are not in the sum: what SABnzbd reports alone.
      final words = _readout(tester).toList();
      expect(words, contains('18.0 MB/\u2060s'));
      expect(words, isNot(contains('40.4 MB/\u2060s')));

      await harness.unmount(tester);
    });

    testWidgets('P3 with Radarr and Sonarr both down: no figure at all, '
        'never Nothing moving', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _pump(
        tester,
        Profiles.p3
            .withBehaviour(WorldIds.radarr, ConnectionBehaviour.didNotAnswer)
            .withBehaviour(WorldIds.sonarr, ConnectionBehaviour.didNotAnswer),
        ActivityTab.all,
      );

      // Nobody was asked who could answer: the count is a dash, not a zero.
      expect(_readout(tester).toList(), ['Activity', '— moving']);
      expect(find.text('Nothing moving'), findsNothing);
      expect(
        find.semantics.byLabel('Activity\nmoving, count unavailable'),
        findsOneWidget,
      );
      expect(_titles(tester), isNot(contains('Downloads')));

      handle.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a full page of the queue with no total is a floor, never '
        'the figure: 202+, not 202', (tester) async {
      final harness = await ProfileHarness.start(
        Profiles.p3,
        now: _now,
        overrides: _clocks,
      );
      // A server behind a proxy that drops `totalRecords`: one full page of
      // the queue, and nothing to say whether a second one follows.
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/queue',
        (_) => NetworkReply.json({
          'page': 1,
          'pageSize': 200,
          'records': [
            for (var i = 0; i < 200; i++)
              {
                'id': i + 1,
                'title': 'Release.$i',
                'status': 'downloading',
                'size': 1000,
                'sizeleft': 500,
              },
          ],
        }),
      );
      await _mount(tester, harness, ActivityTab.all);

      // Radarr's 200 and Sonarr's two, and the walk may not be over.
      expect(_readout(tester).toList(), ['Activity', '202+ moving']);
      expect(find.text('202+ moving'), findsWidgets);
      expect(find.text('202 moving'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P2, Seerr alone: nothing about a queue is claimed beyond '
        'the readout, and no Downloads', (tester) async {
      final harness = await _pump(tester, Profiles.p2, ActivityTab.all);

      expect(_titles(tester), ["Everyone's requests"]);
      expect(find.textContaining('in the queue'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P6, Sonarr Anime silent: its own name is the one left out, '
        'the other Sonarr is counted', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p6.withBehaviour(
          WorldIds.sonarrAnime,
          ConnectionBehaviour.didNotAnswer,
        ),
        ActivityTab.all,
      );

      expect(find.text('Not in the total: Sonarr Anime'), findsWidgets);
      expect(find.text('Not in the total: Sonarr'), findsNothing);
      expect(_readout(tester).first, 'Activity');
      expect(_readout(tester), contains('4 moving'));

      await harness.unmount(tester);
    });

    testWidgets('P6: two Sonarr connections, each one\'s downloads counted '
        'once and each row naming its own', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p6.withDownloads([
          _grab(1, WorldIds.sonarr),
          _grab(2, WorldIds.sonarrAnime),
        ]),
        ActivityTab.downloads,
      );

      // Four moving and the stuck one in the world, and the two grabs.
      expect(
        _sections(tester).first,
        'Downloads\u00A0· 6 moving\u00A0· 1 stuck',
      );
      expect(find.text('Sonarr 1 → qBittorrent'), findsWidgets);
      expect(find.text('Sonarr Anime → qBittorrent'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P6, both Sonarr connections silent: each one is named, '
        'by its own name', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p6
            .withBehaviour(WorldIds.sonarr, ConnectionBehaviour.didNotAnswer)
            .withBehaviour(
              WorldIds.sonarrAnime,
              ConnectionBehaviour.didNotAnswer,
            ),
        ActivityTab.all,
      );

      expect(
        find.text('Not in the total: Sonarr 1, Sonarr Anime'),
        findsWidgets,
      );
      // The rest of the page is the other services', counted whole.
      expect(_readout(tester), contains('4 moving'));

      await harness.unmount(tester);
    });

    testWidgets('a connection that did not answer is red, never a fault in '
        'Needs you', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withBehaviour(
          WorldIds.sonarr,
          ConnectionBehaviour.didNotAnswer,
        ),
        ActivityTab.all,
      );

      expect(find.text('Not in the total: Sonarr'), findsWidgets);
      expect(find.textContaining('did not respond'), findsNothing);
      expect(find.text('Paste the key again'), findsNothing);
      // Silence is the one red on the page: the note under the title wears it.
      final note = find.ancestor(
        of: find.text('Not in the total: Sonarr').first,
        matching: find.byType(FaultNote),
      );
      expect(note, findsOneWidget);
      final glyph = find.descendant(
        of: note,
        matching: find.byIcon(Icons.error_outline_rounded),
      );
      expect(glyph, findsOneWidget);
      final scheme = Theme.of(tester.element(glyph)).colorScheme;
      expect(
        tester.widget<Icon>(glyph).color,
        statusToneColor(scheme, StatusTone.error),
      );
      // Nothing about Sonarr is a fault to answer: its silence is not one.
      expect(find.text('Refused the key'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a connection that refused the key is an amber fault with '
        'its remedy, never "did not answer"', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withBehaviour(
          WorldIds.sonarr,
          ConnectionBehaviour.refusesKey,
        ),
        ActivityTab.all,
      );

      // In Needs you, in the connection's own words, with the one way out.
      expect(find.text('Sonarr answered but refused the key'), findsOneWidget);
      expect(find.text('Paste the key again'), findsOneWidget);
      expect(find.textContaining('did not answer'), findsNothing);
      expect(
        _sections(tester).firstWhere((line) => line.startsWith('Needs you')),
        'Needs you\u00A0· 3 faults\u00A0· 3 requests',
      );
      // And the note under the title is the amber one, not the red.
      final note = find.ancestor(
        of: find.text('Not in the total: Sonarr').first,
        matching: find.byType(FaultNote),
      );
      final glyph = find.descendant(
        of: note,
        matching: find.byIcon(Icons.warning_amber_rounded),
      );
      expect(glyph, findsOneWidget);
      final scheme = Theme.of(tester.element(glyph)).colorScheme;
      expect(
        tester.widget<Icon>(glyph).color,
        statusToneColor(scheme, StatusTone.warning),
      );

      await harness.unmount(tester);
    });

    testWidgets('P7: three sources are out, each named once under the title, '
        'and no speed is claimed over none', (tester) async {
      final harness = await _pump(tester, Profiles.p7, ActivityTab.all);

      expect(_readout(tester).toList(), [
        'Activity',
        '4 moving',
        '·',
        '1 stuck',
        'Not in the total: Lidarr, SABnzbd, qBittorrent',
      ]);
      expect(
        find.text('Not in the total: Lidarr, SABnzbd, qBittorrent'),
        findsNWidgets(2),
      );

      await harness.unmount(tester);
    });

    testWidgets('P7 with Sonarr refusing its key: a silent and a refusing '
        'connection share the page, both named', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p7.withBehaviour(
          WorldIds.sonarr,
          ConnectionBehaviour.refusesKey,
        ),
        ActivityTab.all,
      );

      expect(tester.takeException(), isNull);
      // Every one that gave no answer, in the order the page reads them.
      expect(
        find.text('Not in the total: Lidarr, SABnzbd, Sonarr, qBittorrent'),
        findsWidgets,
      );
      // The refusing one says why, in the connection's own words.
      expect(find.text('Sonarr answered but refused the key'), findsWidgets);

      await harness.unmount(tester);
    });
  });

  group('the menu', () {
    testWidgets('Manual import… is in the page\'s menu and opens the '
        'connection picker', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.all);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Manual import…'), findsOneWidget);
      // Sentence case, a word rather than an icon's tooltip.
      expect(find.text('Manual Import…'), findsNothing);
      await tester.tap(find.text('Manual import…'));
      await tester.pumpAndSettle();

      expect(find.text('Manual import'), findsWidgets);
      expect(
        find.text('Pick the connection that should take the files'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });
  });

  group('the sizes', () {
    for (final tab in ActivityTab.values) {
      for (final width in [390.0, 430.0]) {
        testWidgets('P1: ${tab.label} at 200% on a ${width.round()}pt phone '
            'draws without overflowing', (tester) async {
          final harness = await _pump(
            tester,
            Profiles.p1,
            tab,
            textScale: 2,
            size: Size(width, 12000),
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(PageTabs<ActivityTab>), findsOneWidget);

          await harness.unmount(tester);
        });
      }
    }

    testWidgets('P7: All at 200% with three sources out', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p7,
        ActivityTab.all,
        textScale: 2,
        size: const Size(390, 12000),
      );

      expect(tester.takeException(), isNull);

      await harness.unmount(tester);
    });
  });

  group('with nothing to read', () {
    testWidgets('no service set up: the way in, and nothing else', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? opened;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const ActivityPage(tab: ActivityTab.all),
          ),
          GoRoute(
            path: ServiceRoutes.welcomeConnect,
            builder: (_, state) {
              opened = state.uri.path;
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: await settingsScopeOverrides(),
          child: MaterialApp.router(
            theme: AppTheme.darkTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Nothing is set up yet.'), findsOneWidget);
      // The door the Welcome and the Home have, with what it leads with.
      expect(find.text('Set up a service'), findsOneWidget);
      expect(find.text(SetupDoors.setUpHint), findsOneWidget);
      expect(find.byType(PageTabs<ActivityTab>), findsNothing);

      // It opens Connect directly: the claim was made on the way in.
      await tester.tap(find.text('Set up a service'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(opened, ServiceRoutes.welcomeConnect);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('only a media server: the page is there, and it is quiet', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.jellyfin],
            ),
            ..._clocks,
            activityLivePollProvider.overrideWith((ref, tab) {}),
            ..._quiet,
            servicesArrivalsProvider.overrideWith(
              (ref) async => (
                entries: const <ArrHistoryEntry>[],
                coverage: SourceCoverage.none,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const ActivityPage(tab: ActivityTab.all),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Nothing is set up yet.'), findsNothing);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.byType(PageTabs<ActivityTab>), findsOneWidget);
      expect(find.text('Nothing moving'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('needsYouMeta and requestsWaitLine', () {
    test('each kind counted apart, a request is not a fault', () {
      expect(
        needsYouMeta(faults: 3, requests: 2),
        '3 faults\u00A0· 2 requests',
      );
      expect(needsYouMeta(faults: 1, requests: 1), '1 fault\u00A0· 1 request');
      expect(needsYouMeta(faults: 4, requests: 0), '4 faults');
      expect(needsYouMeta(faults: 0, requests: 1), '1 request');
      expect(needsYouMeta(faults: 0, requests: 0), isEmpty);
    });

    test('violations are their own group, between faults and requests, and '
        'a floor says so', () {
      expect(
        needsYouMeta(faults: 3, requests: 2, violations: 2),
        '3 faults\u00A0· 2 violations\u00A0· 2 requests',
      );
      expect(
        needsYouMeta(faults: 0, requests: 0, violations: 1),
        '1 violation',
      );
      expect(
        needsYouMeta(
          faults: 0,
          requests: 1,
          violations: 5,
          violationsFloor: true,
        ),
        '5+ violations\u00A0· 1 request',
      );
    });

    test('the line over the waiting requests', () {
      expect(requestsWaitLine(1), '1 request waits for your approval');
      expect(requestsWaitLine(2), '2 requests wait for your approval');
      expect(requestsWaitLine(0), '0 requests wait for your approval');
    });
  });
}

/// Every provider that failed while the page was up.
final class _FailureLog extends ProviderObserver {
  final providers = <String>[];

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    providers.add('${context.provider.name ?? context.provider}: $error');
  }
}
