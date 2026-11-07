import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_episodes_graph.dart';

/// Two seasons TMDB has scored: S1\u00A0E2 the best, S2\u00A0E1 voted by few, S2\u00A0E2
/// with no votes yet.
List<MediaEpisodeFacts> _facts(int season) => switch (season) {
  1 => const [
    MediaEpisodeFacts(
      season: 1,
      number: 1,
      name: 'Pilot',
      voteAverage: 7.4,
      voteCount: 60,
    ),
    MediaEpisodeFacts(
      season: 1,
      number: 2,
      name: 'The Turn',
      voteAverage: 8.9,
      voteCount: 44,
    ),
  ],
  _ => const [
    MediaEpisodeFacts(
      season: 2,
      number: 1,
      name: 'Return',
      voteAverage: 8.1,
      voteCount: 9,
    ),
    MediaEpisodeFacts(season: 2, number: 2, name: 'Later'),
  ],
};

MediaEpisode _episode(int season, int number, String state) => MediaEpisode(
  season: season,
  number: number,
  title: 'Episode $number',
  state: state,
  tone: StatusTone.neutral,
);

/// The server lists every episode but S2\u00A0E2.
final _seasons = [
  MediaSeason(1, [_episode(1, 1, 'Watched'), _episode(1, 2, 'Missing')]),
  MediaSeason(2, [_episode(2, 1, 'Downloading')]),
];

Future<List<(int, int)>> _pump(WidgetTester tester) async {
  final opened = <(int, int)>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaSeasonFactsProvider.overrideWith(
          (ref, source) async => _facts(source.season),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              MediaEpisodesGraphSheet(
                connectionId: 'seerr',
                tvId: 1,
                seasonNumbers: const [1, 2],
                seasons: _seasons,
                onOpenEpisode: (season, number) => opened.add((season, number)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('the graph opens on the best episode, and its card opens it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final opened = await _pump(tester);
    expect(find.text('S1\u00A0E2${dotSeparator}The Turn'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Best, S1\u00A0E2\. The Turn\. 8\.9')),
      findsOneWidget,
    );
    await tester.tap(find.text('S1\u00A0E2${dotSeparator}The Turn'));
    expect(opened, [(1, 2)]);
    handle.dispose();
  });

  testWidgets('a tapped cell becomes the card, and the card opens that one', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final opened = await _pump(tester);
    final cell = find.bySemanticsLabel(
      'Season 2 episode 1, 8.1 from 9 votes, few votes',
    );
    expect(cell, findsOneWidget);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('S2\u00A0E1${dotSeparator}Return'), findsOneWidget);
    expect(find.text('9 votes${dotSeparator}Downloading'), findsOneWidget);
    expect(
      tester.getSemantics(cell),
      isSemantics(
        label: 'Season 2 episode 1, 8.1 from 9 votes, few votes',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('S2\u00A0E1${dotSeparator}Return'));
    expect(opened, [(2, 1)]);
    handle.dispose();
  });

  testWidgets('an episode the server does not list reads, but opens nothing', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final opened = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Season 2 episode 2, no votes yet'));
    await tester.pumpAndSettle();
    expect(find.text('S2\u00A0E2${dotSeparator}Later'), findsOneWidget);
    expect(find.text('No votes yet'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    await tester.tap(find.text('S2\u00A0E2${dotSeparator}Later'));
    expect(opened, isEmpty);
    handle.dispose();
  });
}
