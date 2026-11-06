/// Watched by: who has watched a title, from Tracearr. The words, the section
/// on a title's page, and the line the removal sheet says, over the demo
/// world's Tracearr, with the rule that holds all three: an unknown title is
/// no section and never "nobody".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_watched_by.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_watched.dart';

import '../../test_helpers/profiles/profiles.dart';

final _now = DateTime(2026, 11, 6, 12);

TracearrWatcher _watcher(
  String? user,
  String name, {
  int plays = 1,
  double? completion,
  int? episodes,
  DateTime? last,
}) => TracearrWatcher(
  userId: user,
  serverUserId: 'account-$name',
  username: name,
  plays: plays,
  completionPct: completion,
  distinctEpisodesWatched: episodes,
  lastWatchedDay: last,
);

void main() {
  group('the reference Tracearr is asked by', () {
    test('a movie by its TMDB id, a series by its TMDB or TVDB id', () {
      expect(tracearrRefOf(const MediaKey.movie(603)).value, 'movie:tmdb:603');
      expect(tracearrRefOf(const MediaKey.tv(1396)).value, 'show:tmdb:1396');
      expect(
        tracearrRefOf(const MediaKey.tvdb(81189)).value,
        'show:tvdb:81189',
      );
    });
  });

  group('the words', () {
    test('a person is their accounts on every server, added up', () {
      final people = tracearrWatchedPeople(
        TracearrMediaWatchers(
          watchers: [
            _watcher(
              'p1',
              'anna',
              plays: 2,
              completion: 40,
              episodes: 3,
              last: DateTime(2026, 11, 1),
            ),
            _watcher(
              'p1',
              'anna',
              plays: 1,
              completion: 100,
              episodes: 2,
              last: DateTime(2026, 11, 4),
            ),
            _watcher('p2', 'luca', plays: 5, last: DateTime(2026, 11, 5)),
          ],
        ),
      );

      expect(people.map((p) => p.name), ['luca', 'anna']);
      final anna = people.last;
      expect(anna.plays, 3);
      expect(anna.completion, 100);
      expect(anna.episodes, 3);
      expect(anna.lastDay, DateTime(2026, 11, 4));
      expect(anna.personId, 'p1');
    });

    test('Watched by 3 and when, counted in calendar days', () {
      final people = [
        for (final day in [12, 20, 40])
          TracearrWatchedPerson(
            name: 'p$day',
            plays: 1,
            lastDay: _now.subtract(Duration(days: day)),
          ),
      ];
      expect(
        tracearrWatchedLine(people, now: _now),
        'Watched by 3\u00A0· last 12 days ago',
      );
      expect(
        tracearrWatchedTally(people, now: _now),
        '3\u00A0· last 12 days ago',
      );
    });

    test('nobody is said only of an answer that held no watchers', () {
      expect(tracearrWatchedLine(const [], now: _now), 'Nobody has watched it');
    });

    test('today, yesterday and a date from two months on', () {
      expect(tracearrDayWords(_now, now: _now), 'today');
      expect(
        tracearrDayWords(_now.subtract(const Duration(days: 1)), now: _now),
        'yesterday',
      );
      expect(
        tracearrDayWords(DateTime(2026, 8, 1), now: _now),
        startsWith('on '),
      );
    });

    test('a series counts its episodes before the plays', () {
      final person = TracearrWatchedPerson(
        name: 'Luca',
        plays: 9,
        completion: 31.5,
        episodes: 7,
        lastDay: _now.subtract(const Duration(days: 1)),
      );
      expect(
        tracearrWatcherDetail(person, series: true, now: _now),
        '7 episodes\u00A0· 9 plays\u00A0· 32%\u00A0· last yesterday',
      );
      expect(
        tracearrWatcherDetail(person, series: false, now: _now),
        '9 plays\u00A0· 32%\u00A0· last yesterday',
      );
    });
  });

  group('the section on a title\'s page', () {
    Future<ProviderContainer> pumpSection(
      WidgetTester tester,
      ConfigProfile profile,
      MediaKey key,
    ) async {
      final harness = await ProfileHarness.start(profile);
      harness.network.followFakeTime(tester.binding);
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final section = MediaWatchedBy(mediaKey: key, now: harness.network.now);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: harness.overrides,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Scaffold(body: SingleChildScrollView(child: section)),
          ),
        ),
      );
      await harness.settle(tester);
      return ProviderScope.containerOf(tester.element(find.byWidget(section)));
    }

    final household = Profiles.p1.withConnection(WorldConnections.tracearr);

    testWidgets('a movie: who, how often, how far, and when', (tester) async {
      await pumpSection(tester, household, const MediaKey.movie(45745));

      expect(find.text('Watched by'), findsOne);
      expect(find.text('2\u00A0· last 2 days ago'), findsOne);
      expect(find.text('Anna'), findsOne);
      expect(find.text('4 plays\u00A0· 100%\u00A0· last 2 days ago'), findsOne);
      expect(find.text('Luca'), findsOne);
      expect(find.text('1 play\u00A0· 62%\u00A0· last 12 days ago'), findsOne);
    });

    testWidgets('a series counts distinct episodes, by either id', (
      tester,
    ) async {
      for (final key in const [MediaKey.tv(358332), MediaKey.tvdb(300001)]) {
        await pumpSection(tester, household, key);
        expect(
          find.text(
            '7 episodes\u00A0· 9 plays\u00A0· 32%\u00A0· last yesterday',
          ),
          findsOne,
          reason: key.location,
        );
      }
    });

    testWidgets('a title Tracearr holds and nobody played says so', (
      tester,
    ) async {
      await pumpSection(
        tester,
        household,
        MediaKey.movie(WorldTitles.bigBuckBunny.tmdbId),
      );

      expect(find.text('Watched by'), findsOne);
      expect(find.text('Nobody has watched it'), findsOne);
    });

    testWidgets('a title Tracearr does not know draws nothing, never '
        '"nobody"', (tester) async {
      await pumpSection(tester, household, const MediaKey.movie(999999));

      expect(find.text('Watched by'), findsNothing);
      expect(find.text('Nobody has watched it'), findsNothing);
    });

    testWidgets('without Tracearr the section is not drawn', (tester) async {
      await pumpSection(tester, Profiles.p1, const MediaKey.movie(45745));
      expect(find.text('Watched by'), findsNothing);
    });

    testWidgets('a Tracearr that does not answer draws nothing', (
      tester,
    ) async {
      await pumpSection(
        tester,
        household.withBehaviour(
          WorldIds.tracearr,
          ConnectionBehaviour.refusesKey,
        ),
        const MediaKey.movie(45745),
      );
      expect(find.text('Watched by'), findsNothing);
      expect(find.text('Nobody has watched it'), findsNothing);
    });
  });

  group('the line the removal sheet says', () {
    Future<String?> noteFor(
      WidgetTester tester,
      ConfigProfile profile,
      MediaKey key,
    ) async {
      final harness = await ProfileHarness.start(profile);
      harness.network.followFakeTime(tester.binding);
      String? note;
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          // A scope of its own: one test reads two households.
          key: UniqueKey(),
          overrides: harness.overrides,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  captured = ref;
                  // The page that opens the sheet is watching the section.
                  return SingleChildScrollView(
                    child: MediaWatchedBy(
                      mediaKey: key,
                      now: harness.network.now,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await harness.settle(tester);
      note = mediaWatchedByNote(captured, key, now: harness.network.now);
      return note;
    }

    final household = Profiles.p1.withConnection(WorldConnections.tracearr);

    testWidgets('Watched by 2 and the last time, once the page has read it', (
      tester,
    ) async {
      expect(
        await noteFor(tester, household, const MediaKey.movie(45745)),
        'Watched by 2\u00A0· last 2 days ago',
      );
    });

    testWidgets('nobody, for a title Tracearr holds that nobody played', (
      tester,
    ) async {
      expect(
        await noteFor(
          tester,
          household,
          MediaKey.movie(WorldTitles.bigBuckBunny.tmdbId),
        ),
        'Nobody has watched it',
      );
    });

    testWidgets('no line for a title it does not know, or without Tracearr', (
      tester,
    ) async {
      expect(
        await noteFor(tester, household, const MediaKey.movie(999999)),
        isNull,
      );
      expect(
        await noteFor(tester, Profiles.p1, const MediaKey.movie(45745)),
        isNull,
      );
    });
  });
}
