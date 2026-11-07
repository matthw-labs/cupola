/// History and Users: the day headings, the filters (the server's, remembered
/// per connection), paging with a filter on, the detail of a viewing, and the
/// person's page a row leads to. Over a client that answers the recorded
/// fixtures and records what it was asked, so what is said here is what the
/// server would be asked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_filters.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_person_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_users_screen.dart';

import '../../test_helpers/fixtures.dart';
import '../../test_helpers/profiles/profiles.dart';
import '../../test_helpers/recorded_pictures.dart';

final _household = Profiles.p1.withConnection(WorldConnections.tracearr);

const _annaId = '7a3e91c4-5d28-4b6f-8e10-2f4a6c8d0b13';

/// A client with no socket: the history is the recorded page, split the way a
/// test says, and every history read is recorded with its filter and cursor.
class _Client extends TracearrClient {
  _Client({List<List<TracearrHistoryEntry>>? pages, this.failHistory = false})
    : _pages = pages ?? [_recorded()],
      super(baseUrl: 'https://tracearr.test', apiKey: 'trr_pub_test');

  final List<List<TracearrHistoryEntry>> _pages;
  bool failHistory;

  /// Whether the people list does not answer.
  bool failUsers = false;

  final reads = <({String? cursor, TracearrHistoryFilter filter})>[];
  final userReads = <bool>[];

  static List<TracearrHistoryEntry> _recorded() => TracearrPage.fromJson(
    jsonFixture('tracearr/history_page.json'),
    TracearrHistoryEntry.fromJson,
  ).items;

  @override
  Future<TracearrPage<TracearrHistoryEntry>> getHistory({
    String? cursor,
    int pageSize = 25,
    TracearrHistoryFilter filter = const TracearrHistoryFilter(),
  }) async {
    reads.add((cursor: cursor, filter: filter));
    if (failHistory) throw StateError('did not answer');
    final index = cursor == null ? 0 : int.parse(cursor);
    return TracearrPage(
      items: _pages[index],
      nextCursor: index + 1 < _pages.length ? '${index + 1}' : null,
    );
  }

  @override
  Future<TracearrPage<TracearrUser>> getUsers({
    String? cursor,
    int pageSize = 25,
    bool includeRemoved = false,
  }) async {
    userReads.add(includeRemoved);
    if (failUsers) throw StateError('did not answer');
    return TracearrPage.fromJson(
      jsonFixture('tracearr/users.json'),
      TracearrUser.fromJson,
    );
  }

  @override
  Future<TracearrUser?> getUser(String id) async {
    final page = await getUsers();
    return page.items.where((u) => u.id == id).firstOrNull;
  }

  @override
  Future<TracearrUserStats?> getUserStats(String id) async =>
      TracearrUserStats.fromJson(jsonFixture('tracearr/user_stats.json'));

  @override
  Future<TracearrServers> getServers() async =>
      TracearrServers.fromJson(jsonFixture('tracearr/servers.json'));
}

/// Taps a pill of the filter row, scrolling the row to it first: it scrolls
/// sideways, and the last pills are past the edge of a phone.
Future<void> _tapPill(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<ProfileHarness> _pump(
  WidgetTester tester,
  Widget screen,
  _Client client, {
  List<Override> overrides = const [],
  DateTime? now,
  Size size = const Size(430, 3000),
}) {
  recordPictures();
  return pumpWithProfile(
    tester,
    _household,
    child: Scaffold(body: screen),
    overrides: [
      tracearrClientProvider.overrideWithValue(client),
      tracearrClockProvider.overrideWithValue(
        () => now ?? DateTime(2026, 11, 6, 12),
      ),
      ...overrides,
    ],
    surfaceSize: size,
  );
}

TracearrHistoryEntry _entry(String id, DateTime? startedAt, {String? title}) =>
    TracearrHistoryEntry.fromJson({
      'id': id,
      'media_title': title ?? 'Title $id',
      'media_type': 'movie',
      'state': 'stopped',
      'started_at': startedAt?.toUtc().toIso8601String(),
      'stopped_at': startedAt
          ?.add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
      'watched': true,
      'percent_complete': 100,
      'user': {'id': 'u', 'username': 'Anna'},
    });

void main() {
  group('the days', () {
    final now = DateTime(2026, 11, 6, 9, 30);

    test('a viewing at 23:50 and one at 00:10 are two days, in this '
        'device\'s time', () {
      final days = tracearrDaysOf([
        _entry('late', DateTime(2026, 11, 5, 23, 50)),
        _entry('early', DateTime(2026, 11, 5, 0, 10)),
        _entry('next', DateTime(2026, 11, 4, 23, 59)),
      ], now: now);

      expect(days.map((d) => d.label), ['Yesterday', 'Wed 4 Nov']);
      expect(days[0].entries.map((e) => e.id), ['late', 'early']);
      expect(days[1].entries.map((e) => e.id), ['next']);
    });

    test('midnight itself starts the new day', () {
      final days = tracearrDaysOf([
        _entry('after', DateTime(2026, 11, 6, 0, 0)),
        _entry('before', DateTime(2026, 11, 5, 23, 59, 59)),
      ], now: now);

      expect(days.map((d) => d.label), ['Today', 'Yesterday']);
    });

    test(
      'an instant is read in local time, not as the UTC day it falls on',
      () {
        // 23:50 UTC is the next calendar day wherever the device is ahead of
        // UTC, and the same day wherever it is not: the heading follows the
        // device, which is what `toLocal` is for.
        final instant = DateTime.utc(2026, 11, 5, 23, 50);
        final days = tracearrDaysOf([
          TracearrHistoryEntry(id: 'x', startedAt: instant),
        ], now: now);

        final local = instant.toLocal();
        expect(days.single.day, DateTime(local.year, local.month, local.day));
      },
    );

    test(
      'a day continued on the next page is one section, not two headings',
      () {
        final page1 = [_entry('a', DateTime(2026, 11, 5, 22))];
        final page2 = [
          _entry('b', DateTime(2026, 11, 5, 8)),
          _entry('c', DateTime(2026, 11, 4, 20)),
        ];

        final days = tracearrDaysOf([...page1, ...page2], now: now);

        expect(days.map((d) => d.label), ['Yesterday', 'Wed 4 Nov']);
        expect(days.first.entries.map((e) => e.id), ['a', 'b']);
      },
    );

    test('a viewing with no start goes with the one before it, and today when '
        'it is first', () {
      final days = tracearrDaysOf([
        _entry('none', null),
        _entry('a', DateTime(2026, 11, 5, 12)),
        _entry('also none', null),
      ], now: now);

      expect(days.map((d) => d.label), ['Today', 'Yesterday']);
      expect(days.last.entries.map((e) => e.id), ['a', 'also none']);
    });

    test('a year away is named with its year', () {
      final days = tracearrDaysOf([
        _entry('old', DateTime(2025, 3, 2, 12)),
      ], now: now);

      expect(days.single.label, 'Sun 2 Mar 2025');
    });

    test('nothing is no days', () {
      expect(tracearrDaysOf(const [], now: now), isEmpty);
    });
  });

  group('the filters', () {
    test('are the server\'s: each becomes a query parameter, period from the '
        'start of the day', () {
      final filters = const TracearrHistoryFilters()
          .copyWith(person: (id: 'u1', name: 'Anna'))
          .copyWith(server: (id: 's1', name: 'nas'))
          .copyWith(type: (type: TracearrHistoryMediaType.episode))
          .copyWith(onlyWatched: true, period: TracearrPeriod.last7);

      final query = filters.toQuery(DateTime(2026, 11, 6, 15, 45)).toQuery();

      expect(query['user_id'], 'u1');
      expect(query['server_id'], 's1');
      expect(query['media_type'], 'episode');
      expect(query['watched'], true);
      expect(
        query['since'],
        DateTime(2026, 10, 31).toUtc().toIso8601String(),
        reason: 'seven calendar days, today included',
      );
    });

    test('there is no library among them', () {
      final query = const TracearrHistoryFilters().toQuery(DateTime.now());

      expect(query.toQuery().keys, isEmpty);
      expect(
        const TracearrHistoryFilters()
            .copyWith(onlyWatched: true)
            .toQuery(DateTime.now())
            .toQuery()
            .keys,
        everyElement(isNot(contains('library'))),
      );
    });

    test('today starts at midnight on the device, a month at thirty days', () {
      final now = DateTime(2026, 11, 6, 23, 59);

      expect(TracearrPeriod.today.since(now), DateTime(2026, 11, 6));
      expect(TracearrPeriod.last30.since(now), DateTime(2026, 10, 8));
      expect(TracearrPeriod.anyTime.since(now), isNull);
    });

    test('survive being written and read, and a bad word is no filter', () {
      final filters = const TracearrHistoryFilters()
          .copyWith(person: (id: 'u1', name: 'Anna'))
          .copyWith(type: (type: TracearrHistoryMediaType.track))
          .copyWith(onlyWatched: true, period: TracearrPeriod.today);

      expect(TracearrHistoryFilters.fromJson(filters.toJson()), filters);
      expect(
        TracearrHistoryFilters.fromJson('not json'),
        const TracearrHistoryFilters(),
      );
      expect(
        TracearrHistoryFilters.fromJson('[1]'),
        const TracearrHistoryFilters(),
      );
      expect(
        TracearrHistoryFilters.fromJson('{"t":"show","p":"someday"}'),
        const TracearrHistoryFilters(),
        reason: 'show is a 400 on the history route, so it cannot be read back',
      );
      expect(
        TracearrHistoryFilters.fromJson(null),
        const TracearrHistoryFilters(),
      );
    });

    group('remembered', () {
      ServiceInstance instance(String id) => ServiceInstance(
        id: id,
        service: ServiceKey.tracearr,
        label: id,
        url: 'http://$id.test',
        credential: 'trr_pub_test',
      );

      Future<ProviderContainer> container(
        SharedPreferences prefs,
        String connection,
      ) async {
        final c = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            activeInstanceProvider(
              ServiceKey.tracearr,
            ).overrideWithValue(instance(connection)),
          ],
        );
        addTearDown(c.dispose);
        return c;
      }

      test('across a rebuild, and per connection', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final first = await container(prefs, 'tracearr');
        first.read(tracearrHistoryFiltersProvider.notifier)
          ..person('u1', 'Anna')
          ..type(TracearrHistoryMediaType.movie)
          ..onlyWatched(true)
          ..period(TracearrPeriod.last30);
        first.dispose();

        // A new container over the same preferences: a new launch.
        final again = await container(prefs, 'tracearr');
        final back = again.read(tracearrHistoryFiltersProvider);
        expect(back.userId, 'u1');
        expect(back.userName, 'Anna');
        expect(back.mediaType, TracearrHistoryMediaType.movie);
        expect(back.onlyWatched, isTrue);
        expect(back.period, TracearrPeriod.last30);

        // Another connection has its own, untouched.
        final other = await container(prefs, 'tracearr-attic');
        expect(
          other.read(tracearrHistoryFiltersProvider),
          const TracearrHistoryFilters(),
        );
        other
            .read(tracearrHistoryFiltersProvider.notifier)
            .server('s9', 'attic');
        expect(
          again.read(tracearrHistoryFiltersProvider).serverId,
          isNull,
          reason: 'the first connection did not hear it',
        );
        final third = await container(prefs, 'tracearr');
        expect(third.read(tracearrHistoryFiltersProvider).userId, 'u1');
        expect(third.read(tracearrHistoryFiltersProvider).serverId, isNull);
      });

      test('clearing forgets them, and so does the key', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final c = await container(prefs, 'tracearr');
        final notifier = c.read(tracearrHistoryFiltersProvider.notifier)
          ..onlyWatched(true);
        expect(
          prefs.getString(tracearrHistoryFiltersKey('tracearr')),
          isNotNull,
        );

        notifier.clear();

        expect(prefs.getString(tracearrHistoryFiltersKey('tracearr')), isNull);
        expect(
          c.read(tracearrHistoryFiltersProvider),
          const TracearrHistoryFilters(),
        );
      });

      test('a person chosen and then Anyone leaves no name behind', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final c = await container(prefs, 'tracearr');
        final notifier = c.read(tracearrHistoryFiltersProvider.notifier)
          ..person('u1', 'Anna')
          ..person(null, 'Anna');

        expect(c.read(tracearrHistoryFiltersProvider).userName, isNull);
        expect(notifier, isNotNull);
      });
    });
  });

  group('the screen', () {
    testWidgets('groups the viewings under their day, newest first', (
      tester,
    ) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
        now: DateTime(2026, 11, 6, 12),
      );

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('The Lantern Keeper'), findsOneWidget);
      expect(find.text('Harbor Lights\u00A0· S2\u00A0E4'), findsOneWidget);
      expect(find.text('Anna\u00A0· Night Ferry'), findsNothing);
      expect(find.textContaining('Night Ferry'), findsOneWidget);
      // How each ended: counted, short of it, short of it.
      expect(find.text('Watched'), findsOneWidget);
      expect(find.text('48%'), findsOneWidget);
      // The track has no end yet: still playing.
      expect(find.text('Playing'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('asks the server with the first page and no filter', (
      tester,
    ) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );

      expect(client.reads.first.cursor, isNull);
      expect(client.reads.first.filter.toQuery(), isEmpty);
      await harness.unmount(tester);
    });

    testWidgets('a filter chosen asks the server again from the first page, '
        'and is remembered', (tester) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );

      // Person: chosen from the people Tracearr lists.
      await _tapPill(tester, 'Anyone');
      await tester.tap(find.text('Anna').last);
      await tester.pumpAndSettle();

      expect(client.reads.last.filter.userId, _annaId);
      expect(client.reads.last.cursor, isNull);
      expect(find.text('Anna'), findsOneWidget, reason: 'the pill wears it');

      // Type.
      await _tapPill(tester, 'Any type');
      await tester.tap(find.text('Episodes'));
      await tester.pumpAndSettle();
      expect(
        client.reads.last.filter.mediaType,
        TracearrHistoryMediaType.episode,
      );
      expect(client.reads.last.filter.userId, _annaId, reason: 'still on');

      // Period, and the toggle.
      await _tapPill(tester, 'Any time');
      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();
      await _tapPill(tester, 'Only watched');
      final last = client.reads.last.filter;
      expect(last.watched, isTrue);
      expect(last.since, DateTime(2026, 10, 31));

      // Server.
      await _tapPill(tester, 'Any server');
      await tester.tap(find.text('Plex Living Room').last);
      await tester.pumpAndSettle();
      expect(client.reads.last.filter.serverId, isNotNull);
      await harness.unmount(tester);
    });

    testWidgets('a filter is written to the device under its connection, and '
        'read back by a page built again', (tester) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );
      await _tapPill(tester, 'Only watched');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TracearrHistoryScreen)),
      );
      final prefs = container.read(sharedPreferencesProvider);
      final stored = TracearrHistoryFilters.fromJson(
        prefs.getString(tracearrHistoryFiltersKey(WorldIds.tracearr)),
      );
      expect(stored.onlyWatched, isTrue);

      // The page goes and comes back over the same store.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: TracearrHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Clear'), findsOneWidget);
      expect(client.reads.last.filter.watched, isTrue);
      await harness.unmount(tester);
    });

    testWidgets('every active filter and Clear are on screen at 390pt, '
        'with no scrolling', (tester) async {
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        _Client(),
        size: const Size(390, 3000),
      );
      ProviderScope.containerOf(
          tester.element(find.byType(TracearrHistoryScreen)),
        ).read(tracearrHistoryFiltersProvider.notifier)
        ..onlyWatched(true)
        ..period(TracearrPeriod.last7);
      await tester.pumpAndSettle();
      const width = 390.0;
      for (final label in ['Last 7 days', 'Only watched', 'Clear']) {
        final box = tester.getRect(find.text(label));
        expect(box.left, greaterThanOrEqualTo(0), reason: label);
        expect(box.right, lessThanOrEqualTo(width), reason: label);
        final pill = tester.getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(SelectionPill),
          ),
        );
        expect(pill.height, greaterThanOrEqualTo(44), reason: label);
      }
      expect(
        find.descendant(
          of: find.byType(TracearrHistoryScreen),
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        ),
        findsNothing,
      );
      await harness.unmount(tester);
    });

    testWidgets('Clear puts every filter back and asks for everything', (
      tester,
    ) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );
      await _tapPill(tester, 'Only watched');
      expect(find.text('Clear'), findsOneWidget);

      await _tapPill(tester, 'Clear');

      expect(client.reads.last.filter.toQuery(), isEmpty);
      expect(find.text('Clear'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('pages by cursor with the filter still on', (tester) async {
      final client = _Client(
        pages: [
          [_entry('1', DateTime(2026, 11, 5, 20))],
          [_entry('2', DateTime(2026, 11, 5, 10))],
        ],
      );
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );
      await _tapPill(tester, 'Only watched');

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(find.text('Title 1'), findsOneWidget);
      expect(find.text('Title 2'), findsOneWidget);
      expect(
        find.text('Yesterday'),
        findsOneWidget,
        reason: 'one day, one heading',
      );
      final next = client.reads.last;
      expect(next.cursor, '1');
      expect(next.filter.watched, isTrue);
      await harness.unmount(tester);
    });

    testWidgets('an empty answer under a filter says it is the filter, with '
        'the filters still reachable', (tester) async {
      final client = _Client(pages: [const []]);
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );
      expect(find.text('No history yet'), findsOneWidget);

      await _tapPill(tester, 'Only watched');

      expect(find.text('Nothing matches'), findsOneWidget);
      expect(find.text('Only watched'), findsOneWidget);
      await _tapPill(tester, 'Clear');
      expect(find.text('No history yet'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a Tracearr that did not answer is a failure, with the '
        'filters still there to change', (tester) async {
      final client = _Client(failHistory: true);
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('No history yet'), findsNothing);
      expect(find.text('Only watched'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('the person filter reads the people again after a read that '
        'failed, instead of keeping the failure', (tester) async {
      final client = _Client()..failUsers = true;
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );

      await _tapPill(tester, 'Anyone');
      expect(
        find.textContaining('Could not read the people Tracearr knows'),
        findsOneWidget,
      );
      expect(client.userReads, [false]);

      client.failUsers = false;
      await _tapPill(tester, 'Anyone');

      expect(client.userReads, [false, false], reason: 'asked a second time');
      expect(find.text('Person'), findsOneWidget, reason: 'the picker opened');
      expect(find.text('Anna'), findsWidgets);
      await harness.unmount(tester);
    });

    testWidgets('a row opens the detail with how it ended, and no Stop', (
      tester,
    ) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );

      await tester.tap(find.text('Harbor Lights\u00A0· S2\u00A0E4'));
      await tester.pumpAndSettle();

      expect(find.text('Completion'), findsOneWidget);
      expect(find.text('Stopped at 48%'), findsOneWidget);
      expect(find.text('Stop stream'), findsNothing);
      await harness.unmount(tester);
    });
  });

  group('the door to a person from a viewing', () {
    testWidgets('is there from History, which carries the person\'s id', (
      tester,
    ) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrHistoryScreen(),
        client,
      );

      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();

      expect(find.text('Go to Anna'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('is left out on that person\'s own page, where it would open '
        'the page it is on', (tester) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrPersonScreen(userId: _annaId),
        client,
      );

      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();
      expect(find.text('Open title'), findsOneWidget, reason: 'the sheet');
      expect(find.text('Go to Anna'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('Users', () {
    testWidgets('a chip for each kind of server, each once, and the count', (
      tester,
    ) async {
      final client = _Client();
      final harness = await _pump(tester, const TracearrUsersScreen(), client);

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('luca'), findsOneWidget);
      expect(find.widgetWithText(GenreChip, 'Plex'), findsOneWidget);
      expect(find.widgetWithText(GenreChip, 'Emby'), findsNWidgets(2));
      // Anna's Jellyfin account was removed: no chip, and not counted.
      expect(find.widgetWithText(GenreChip, 'Jellyfin'), findsNothing);
      expect(find.text('2 accounts'), findsOneWidget);
      expect(find.text('1 account'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('removed accounts are excluded until asked for, and the list '
        'is read again when they are', (tester) async {
      final client = _Client();
      final harness = await _pump(tester, const TracearrUsersScreen(), client);
      expect(client.userReads, [false]);

      await tester.tap(find.text('Include removed'));
      await tester.pumpAndSettle();

      expect(client.userReads, [false, true]);
      await harness.unmount(tester);
    });

    test('the kinds are each listed once, in the order Tracearr gave them, '
        'and a removed person lists what they had', () {
      final user = TracearrUser(
        id: 'u',
        accounts: [
          const TracearrAccount(
            serverId: 's1',
            serverType: TracearrServerType.plex,
          ),
          const TracearrAccount(
            serverId: 's2',
            serverType: TracearrServerType.jellyfin,
          ),
          const TracearrAccount(
            serverId: 's3',
            serverType: TracearrServerType.jellyfin,
          ),
        ],
      );
      expect(tracearrAccountKinds(user), ['Plex', 'Jellyfin']);

      final gone = TracearrUser(
        id: 'g',
        accounts: [
          TracearrAccount(
            serverId: 's1',
            serverType: TracearrServerType.emby,
            removedAt: DateTime(2026, 10, 1),
          ),
        ],
      );
      expect(tracearrAccountKinds(gone), ['Emby']);
    });

    testWidgets('a row opens the person', (tester) async {
      final client = _Client();
      recordPictures();
      final harness = await ProfileHarness.start(
        _household,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      harness.network.followFakeTime(tester.binding);
      await tester.binding.setSurfaceSize(const Size(430, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        initialLocation: '/stack/tracearr/users',
        routes: [
          GoRoute(
            path: '/stack/tracearr/users',
            builder: (_, _) => const Scaffold(body: TracearrUsersScreen()),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    TracearrPersonScreen(userId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await harness.settle(tester);

      await tester.tap(find.text('Anna'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/stack/tracearr/users/$_annaId');
      expect(find.byType(TracearrPersonScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('a person', () {
    testWidgets('has their figures for 7 and 30 days and all time, what they '
        'like, and what they watched last', (tester) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrPersonScreen(userId: _annaId),
        client,
      );

      expect(find.text('Anna'), findsWidgets);
      expect(find.widgetWithText(GenreChip, 'Plex'), findsOneWidget);
      for (final window in ['7 days', '30 days', 'All time']) {
        expect(find.text(window), findsOneWidget);
      }
      expect(find.text('Watching'), findsOneWidget);
      expect(find.text('Latest'), findsOneWidget);
      // Their recent history reuses the row of History, with the day and
      // without their own name.
      expect(find.byType(ServiceRecordRow), findsWidgets);
      expect(find.text('Violations'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('the figures are plays and time, and none is a guess', (
      tester,
    ) async {
      final client = _FiguresClient();
      final harness = await _pump(
        tester,
        const TracearrPersonScreen(userId: _annaId),
        client,
      );

      expect(find.text('4 plays'), findsOneWidget);
      expect(find.text('2\u00A0h 5\u00A0min'), findsOneWidget);
      expect(find.text('11 plays'), findsOneWidget);
      expect(find.text('38 plays'), findsOneWidget);
      expect(find.text('1\u00A0d 17\u00A0h'), findsOneWidget);
      expect(find.widgetWithText(GenreChip, 'Drama'), findsOneWidget);
      expect(find.widgetWithText(GenreChip, 'Fantasy'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a person Tracearr does not know is said so, not failed', (
      tester,
    ) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrPersonScreen(userId: 'nobody'),
        client,
      );

      expect(find.text('Tracearr does not know this person'), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('one region failing leaves the others standing', (
      tester,
    ) async {
      final client = _FiguresClient(failStats: true);
      final harness = await _pump(
        tester,
        const TracearrPersonScreen(userId: _annaId),
        client,
      );

      expect(
        find.textContaining('their figures are not shown'),
        findsOneWidget,
      );
      expect(find.text('Latest'), findsOneWidget);
      expect(find.byType(ServiceRecordRow), findsWidgets);
      await harness.unmount(tester);
    });

    testWidgets('the way to their violations goes to the tab with them named '
        'by `?user=`', (tester) async {
      final client = _Client();
      recordPictures();
      final harness = await ProfileHarness.start(
        _household,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      harness.network.followFakeTime(tester.binding);
      await tester.binding.setSurfaceSize(const Size(430, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        initialLocation: '/stack/tracearr/users/$_annaId',
        routes: [
          GoRoute(
            path: '/stack/tracearr/users/:id',
            builder: (_, state) =>
                TracearrPersonScreen(userId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/stack/tracearr/violations',
            builder: (_, state) => Text('violations ${state.uri.query}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await harness.settle(tester);

      await tester.ensureVisible(find.text('Violations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Violations'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/stack/tracearr/violations');
      expect(router.state.uri.queryParameters['user'], _annaId);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}

/// A client whose person has figures to read.
class _FiguresClient extends _Client {
  _FiguresClient({this.failStats = false});

  final bool failStats;

  @override
  Future<TracearrUserStats?> getUserStats(String id) async {
    if (failStats) throw StateError('did not answer');
    return TracearrUserStats.fromJson({
      'user_id': id,
      'windows': {
        'last_7': {'plays': 4, 'watch_time_ms': 125 * 60 * 1000},
        'last_30': {'plays': 11, 'watch_time_ms': 520 * 60 * 1000},
        'all_time': {'plays': 38, 'watch_time_ms': 41 * 3600 * 1000},
      },
      'top_genres': [
        {'genre': 'Drama', 'plays': 9},
        {'genre': 'Fantasy', 'plays': 3},
      ],
    });
  }
}
