/// Tracearr's five rooms, drawn over the demo world's fake server with nothing
/// stubbed above the socket, and over a paged client where the paging is what
/// is under test: what each screen lists, how it says it is empty, how it says
/// Tracearr did not answer, and what the Overview leaves out rather than
/// invent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_overview_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_overview_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_users_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_screen.dart';

import '../../test_helpers/profiles/profiles.dart';

final _household = Profiles.p1
    .withConnection(WorldConnections.plex)
    .withConnection(WorldConnections.emby)
    .withConnection(WorldConnections.tracearr);

Future<ProfileHarness> _pump(
  WidgetTester tester,
  Widget screen, {
  ConfigProfile? profile,
  List<Override> overrides = const [],
}) => pumpWithProfile(
  tester,
  profile ?? _household,
  child: Scaffold(body: screen),
  overrides: overrides,
  surfaceSize: const Size(430, 3000),
);

/// The client the paged screens read, with the pages a test hands it. Nothing
/// of it reaches a socket: every read it answers is overridden.
class _PagedClient extends TracearrClient {
  _PagedClient({
    this.history = const [],
    this.users = const [],
    this.violations = const [],
    this.failSecondPage = false,
  }) : super(baseUrl: 'http://tracearr.test', apiKey: 'trr_pub_test');

  final List<List<TracearrHistoryEntry>> history;
  final List<List<TracearrUser>> users;
  final List<List<TracearrViolation>> violations;
  final bool failSecondPage;

  final cursors = <String?>[];
  final filters = <bool?>[];

  TracearrPage<T> _page<T>(List<List<T>> pages, String? cursor) {
    cursors.add(cursor);
    final index = cursor == null ? 0 : int.parse(cursor);
    if (index == 1 && failSecondPage) throw StateError('no second page');
    if (pages.isEmpty) return TracearrPage(items: const []);
    return TracearrPage(
      items: pages[index],
      nextCursor: index + 1 < pages.length ? '${index + 1}' : null,
    );
  }

  @override
  Future<TracearrPage<TracearrHistoryEntry>> getHistory({
    String? cursor,
    int pageSize = 25,
    TracearrHistoryFilter filter = const TracearrHistoryFilter(),
  }) async => _page(history, cursor);

  @override
  Future<TracearrPage<TracearrUser>> getUsers({
    String? cursor,
    int pageSize = 25,
    bool includeRemoved = false,
  }) async => _page(users, cursor);

  @override
  Future<TracearrPage<TracearrViolation>> getViolations({
    String? cursor,
    int pageSize = 25,
    TracearrViolationFilter filter = const TracearrViolationFilter(),
  }) async {
    filters.add(filter.acknowledged);
    return _page(violations, cursor);
  }
}

TracearrHistoryEntry _entry(String id, String title) => TracearrHistoryEntry(
  id: id,
  media: TracearrMedia(type: TracearrMediaType.movie, title: title),
);

TracearrViolation _violation(String id, TracearrSeverity severity) =>
    TracearrViolation(
      id: id,
      severity: severity,
      rule: TracearrRuleRef(name: 'Rule $id'),
    );

class _Opener implements BrowserOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('the Overview', () {
    testWidgets('draws the servers, what plays, the violations and the week', (
      tester,
    ) async {
      final harness = await _pump(tester, const TracearrOverviewScreen());

      // The rail above them is `serviceKpiProvider`'s, whose four figures are
      // read in the demo world test.
      expect(find.byType(ServiceKpiPeek), findsOneWidget);

      for (final title in [
        'Monitored servers',
        'Playing now',
        'Violations',
        'Most watched this week',
      ]) {
        expect(
          find.byWidgetPredicate(
            (w) => w is ServiceOverviewSection && w.title == title,
          ),
          findsOneWidget,
          reason: title,
        );
      }
      // The three servers, each in the lexicon's word, never `Online`.
      expect(find.text('nas'), findsOneWidget);
      expect(find.text('basement-nas'), findsOneWidget);
      expect(find.text('tower'), findsOneWidget);
      expect(find.textContaining('\u00A0· Answering'), findsNWidgets(3));
      expect(find.textContaining('Online'), findsNothing);
      // The first three streams of Live, with how each reaches the viewer.
      expect(find.text('Sintel'), findsWidgets);
      expect(find.text('Elephants Dream'), findsOneWidget);
      expect(find.textContaining('Direct play'), findsWidgets);
      // Severity in words; the acknowledged one is the one that has been read.
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.textContaining('4 plays'), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a server whose token Tracearr holds was refused is amber, '
        'with the one remedy only the owner can do', (tester) async {
      final opener = _Opener();
      final harness = await _pump(
        tester,
        const TracearrOverviewScreen(),
        overrides: [
          browserOpenerProvider.overrideWithValue(opener),
          tracearrServersProvider.overrideWith(
            (ref) async => const TracearrServers(
              servers: [
                TracearrServer(
                  id: 'a',
                  name: 'tower',
                  type: TracearrServerType.emby,
                  status: TracearrServerStatus.down,
                  reason: TracearrServerReason.unauthorized,
                ),
                TracearrServer(
                  id: 'b',
                  name: 'nas',
                  type: TracearrServerType.jellyfin,
                  status: TracearrServerStatus.down,
                ),
                TracearrServer(
                  id: 'c',
                  name: 'basement',
                  type: TracearrServerType.plex,
                ),
                TracearrServer(
                  id: 'd',
                  name: 'old',
                  type: TracearrServerType.plex,
                  historical: true,
                ),
              ],
            ),
          ),
        ],
      );

      expect(find.textContaining("Refused Tracearr's token"), findsOneWidget);
      expect(find.textContaining('Did not answer Tracearr'), findsOneWidget);
      // Tracearr's `unknown` is a dash, never a state word, and a server kept
      // only for its history is not one of the monitored.
      expect(find.text('Plex\u00A0· —'), findsOneWidget);
      expect(find.text('old'), findsNothing);
      expect(find.text('3 servers'), findsOneWidget);

      await tester.tap(find.text('Fix it in Tracearr'));
      await tester.pump();
      expect(
        opener.opened.single.toString(),
        endsWith('/settings/servers/connections'),
      );
      expect(opener.opened.single.host, 'tower.home.arpa');
      await harness.unmount(tester);
    });

    testWidgets('a Tracearr with no top-media read leaves the section out, '
        'which is not an empty week', (tester) async {
      final harness = await _pump(
        tester,
        const TracearrOverviewScreen(),
        overrides: [tracearrTopWeekProvider.overrideWith((ref) async => null)],
      );

      expect(find.text('Most watched this week'), findsNothing);
      expect(find.text('Nothing has been watched this week'), findsNothing);
      expect(find.text('Playing now'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a week nobody watched says so', (tester) async {
      final harness = await _pump(
        tester,
        const TracearrOverviewScreen(),
        overrides: [tracearrTopWeekProvider.overrideWith((ref) async => [])],
      );

      expect(find.text('Nothing has been watched this week'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('empty sections say what is true of them', (tester) async {
      final harness = await _pump(
        tester,
        const TracearrOverviewScreen(),
        overrides: [
          tracearrServersProvider.overrideWith(
            (ref) async => const TracearrServers(servers: []),
          ),
          tracearrStreamsProvider.overrideWith(
            (ref) async => const TracearrStreams(streams: []),
          ),
          tracearrLatestViolationsProvider.overrideWith(
            (ref) async => const TracearrPage(items: []),
          ),
        ],
      );

      expect(find.text('Tracearr watches no server yet'), findsOneWidget);
      expect(find.text('Nothing is playing'), findsOneWidget);
      expect(find.text('No rule has been broken'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('one section failing leaves the others standing', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        const TracearrOverviewScreen(),
        overrides: [
          tracearrLatestViolationsProvider.overrideWith(
            (ref) async => throw StateError('boom'),
          ),
        ],
      );

      expect(find.text('Monitored servers'), findsOneWidget);
      expect(find.textContaining('\u00A0· Answering'), findsNWidgets(3));
      expect(
        find.textContaining('the latest violations are not shown'),
        findsOneWidget,
      );
      await harness.unmount(tester);
    });

    test('a server reads as the lexicon says, and unknown is a dash', () {
      expect(
        tracearrServerState(
          const TracearrServer(id: 'a', status: TracearrServerStatus.up),
        ).word,
        'Answering',
      );
      expect(
        tracearrServerState(
          const TracearrServer(id: 'a', status: TracearrServerStatus.down),
        ).word,
        'Did not answer Tracearr',
      );
      expect(tracearrServerState(const TracearrServer(id: 'a')).tone, isNull);
      expect(tracearrServerState(const TracearrServer(id: 'a')).word, '—');
    });
  });

  group('Live', () {
    testWidgets('lists a row per stream with its method and a summary', (
      tester,
    ) async {
      final harness = await _pump(tester, const TracearrLiveScreen());

      expect(find.byType(ServiceRecordRow), findsNWidgets(3));
      expect(find.text('Elephants Dream'), findsOneWidget);
      expect(find.text('Direct play'), findsNWidgets(3));
      expect(find.textContaining('3 streams'), findsOneWidget);
      expect(find.textContaining('15.3'), findsOneWidget);
      // Who, on what, through which server.
      expect(
        find.textContaining("Luca\u00A0· Luca's iPad\u00A0· basement-nas"),
        findsOneWidget,
      );
      await harness.unmount(tester);
    });

    testWidgets('says nothing is playing, in words', (tester) async {
      final harness = await _pump(
        tester,
        const TracearrLiveScreen(),
        overrides: [
          tracearrStreamsProvider.overrideWith(
            (ref) async => const TracearrStreams(streams: []),
          ),
        ],
      );

      expect(find.text('Nothing is playing'), findsOneWidget);
      expect(find.byType(ServiceRecordRow), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a Tracearr that did not answer is a failure and not an '
        'empty list', (tester) async {
      final harness = await _pump(
        tester,
        const TracearrLiveScreen(),
        profile: _household.withBehaviour(
          WorldIds.tracearr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Nothing is playing'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a stream whose movie has a TMDB id is a door to its title', (
      tester,
    ) async {
      final harness = await _pump(tester, const TracearrLiveScreen());

      // The demo's movies carry their TMDB ids, so each is a door.
      expect(find.byType(PressableScale), findsNWidgets(3));
      await harness.unmount(tester);
    });
  });

  group('History', () {
    testWidgets('lists the viewings newest first, with how each ended', (
      tester,
    ) async {
      final harness = await _pump(tester, const TracearrHistoryScreen());

      expect(find.byType(ServiceRecordRow), findsNWidgets(4));
      expect(find.text('Watched'), findsNWidgets(3));
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('pages by cursor with Load more, and keeps its rows when a '
        'later page fails', (tester) async {
      final client = _PagedClient(
        history: [
          [_entry('1', 'One'), _entry('2', 'Two')],
          [_entry('3', 'Three')],
        ],
        failSecondPage: true,
      );
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await harness.settle(tester);

      // The page failed: the two rows stand, the sentence says so, and Retry
      // asks the same page again.
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('Could not ask for more entries'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(client.cursors, [null, '1']);
      await harness.unmount(tester);
    });

    testWidgets('the next page is appended and the button goes', (
      tester,
    ) async {
      final client = _PagedClient(
        history: [
          [_entry('1', 'One')],
          [_entry('2', 'Two')],
        ],
      );
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.text('Load more'));
      await harness.settle(tester);

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(client.cursors, [null, '1']);
      await harness.unmount(tester);
    });

    testWidgets('says there is no history, and a failure is not that', (
      tester,
    ) async {
      var harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(_PagedClient())],
      );
      expect(find.text('No history yet'), findsOneWidget);
      await harness.unmount(tester);

      harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        profile: _household.withBehaviour(
          WorldIds.tracearr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('No history yet'), findsNothing);
      await harness.unmount(tester);
    });
  });

  group('Users', () {
    testWidgets('lists the people with the kinds of server they are on', (
      tester,
    ) async {
      final harness = await _pump(tester, const TracearrUsersScreen());

      expect(find.byType(ServiceRecordRow), findsNWidgets(2));
      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Jellyfin, Plex, Emby'), findsNWidgets(2));
      expect(find.text('3 accounts'), findsNWidgets(2));
      await harness.unmount(tester);
    });

    testWidgets('an account removed from a server is not counted', (
      tester,
    ) async {
      final client = _PagedClient(
        users: [
          [
            TracearrUser(
              id: 'u',
              username: 'Sara',
              accounts: [
                const TracearrAccount(
                  serverId: 's1',
                  serverType: TracearrServerType.plex,
                ),
                TracearrAccount(
                  serverId: 's2',
                  serverType: TracearrServerType.emby,
                  removedAt: DateTime(2026, 10, 1),
                ),
              ],
            ),
          ],
        ],
      );
      final harness = await _pump(
        tester,
        const TracearrUsersScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('1 account'), findsOneWidget);
      expect(find.text('Plex'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('empty and unanswered are two different things', (
      tester,
    ) async {
      var harness = await _pump(
        tester,
        const TracearrUsersScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(_PagedClient())],
      );
      expect(find.text('No users'), findsOneWidget);
      await harness.unmount(tester);

      harness = await _pump(
        tester,
        const TracearrUsersScreen(),
        profile: _household.withBehaviour(
          WorldIds.tracearr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      expect(find.byType(AppErrorState), findsOneWidget);
      await harness.unmount(tester);
    });
  });

  group('Violations', () {
    testWidgets('opens on the unseen, in words, and All shows the rest', (
      tester,
    ) async {
      final harness = await _pump(tester, const TracearrViolationsScreen());

      expect(find.byType(ServiceRecordRow), findsNWidgets(2));
      expect(find.text('Concurrent streams'), findsOneWidget);
      // The words on the rows; the severity pills carry the same words, so
      // the rows are asked apart from them.
      Finder inRows(String word) => find.descendant(
        of: find.byType(ServiceRecordRow),
        matching: find.text(word),
      );
      expect(inRows('Warning'), findsOneWidget);
      expect(inRows('Low'), findsOneWidget);
      expect(inRows('High'), findsNothing);
      // What a violation carries (its places, its addresses) never reaches a
      // row: the unknown rule is its name alone.
      expect(find.textContaining('Turin'), findsNothing);
      expect(find.textContaining('192.'), findsNothing);

      await tester.tap(find.text('All'));
      await harness.settle(tester);

      expect(find.byType(ServiceRecordRow), findsNWidgets(3));
      expect(inRows('High'), findsOneWidget);
      expect(find.textContaining('Acknowledged'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('the scope is asked of the server and never trimmed here', (
      tester,
    ) async {
      final client = _PagedClient(
        violations: [
          [_violation('1', TracearrSeverity.low)],
        ],
      );
      final harness = await _pump(
        tester,
        const TracearrViolationsScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      expect(client.filters, [false]);

      await tester.tap(find.text('All'));
      await harness.settle(tester);
      expect(client.filters, [false, null]);
      await harness.unmount(tester);
    });

    testWidgets('nothing unseen leaves the way to All, and says so', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        const TracearrViolationsScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(_PagedClient())],
      );

      expect(find.text('Nothing unseen'), findsOneWidget);
      await tester.tap(find.text('All'));
      await harness.settle(tester);
      expect(find.text('No violations'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a Tracearr that did not answer keeps the scope reachable', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        const TracearrViolationsScreen(),
        profile: _household.withBehaviour(
          WorldIds.tracearr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Nothing unseen'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('pages with Load more', (tester) async {
      final client = _PagedClient(
        violations: [
          [_violation('1', TracearrSeverity.high)],
          [_violation('2', TracearrSeverity.low)],
        ],
      );
      final harness = await _pump(
        tester,
        const TracearrViolationsScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.text('Load more'));
      await harness.settle(tester);

      expect(find.text('Rule 1'), findsOneWidget);
      expect(find.text('Rule 2'), findsOneWidget);
      await harness.unmount(tester);
    });
  });

  group('a Tracearr that is not set up', () {
    testWidgets('every tab says so before it reads anything', (tester) async {
      for (final screen in const <Widget>[
        TracearrOverviewScreen(),
        TracearrLiveScreen(),
        TracearrHistoryScreen(),
        TracearrUsersScreen(),
        TracearrViolationsScreen(),
      ]) {
        final harness = await _pump(tester, screen, profile: Profiles.p1);
        expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
        expect(find.byType(AppErrorState), findsNothing);
        await harness.unmount(tester);
      }
    });
  });
}
