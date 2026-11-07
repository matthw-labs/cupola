/// A season or an episode a media server lists opens its series' own page,
/// on that season, wherever it is tapped: the same title is the same page,
/// from every entry point. An album, a series the server holds no ids for and
/// a lookup that failed keep opening the server's own page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/media/presentation/media_series_sections.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/profiles/profiles.dart';

/// The whole app, on [profile]'s household, with its own router.
///
/// [before] arranges the network ahead of the first read: the Home asks for
/// what is in progress as it opens.
Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester,
  ConfigProfile profile, {
  void Function(ProfileHarness harness)? before,
}) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  before?.call(harness);
  final container = harness.container();
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await _answer(tester);
  return (harness, router, container);
}

/// Lets the household's servers answer.
Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The app down, then its providers: the whole app keeps timers of its own
/// (polls, a search asked again) that only the container's end cancels.
Future<void> _close(
  WidgetTester tester,
  ProfileHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await harness.unmount(tester);
}

/// Taps the first thing the screen reads out as [label].
Future<void> _tap(WidgetTester tester, Pattern label) async {
  final target = find.bySemanticsLabel(label);
  await tester.ensureVisible(target.first);
  await tester.tap(target.first);
  await _answer(tester);
}

/// The title page the user sees.
Iterable<MediaPage> _shown(WidgetTester tester) =>
    tester.widgetList<MediaPage>(find.byType(MediaPage).hitTestable());

/// The season the page's episodes opened on.
Future<int> _episodesOpenOn(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Episodes'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  return tester.widget<MediaEpisodes>(find.byType(MediaEpisodes)).initialSeason;
}

final _cosmos = WorldTitles.cosmosLaundromat;

// === Jellyfin ===============================================================

/// Jellyfin's own id for Cosmos Laundromat, as the world's server spells it.
final _cosmosOnJellyfin = 'jf-${_cosmos.key}';

/// An episode of Cosmos Laundromat, part-watched, as Jellyfin lists it.
Map<String, Object?> _jellyfinEpisode(int season, int number) => {
  'Id': 'jf-cosmos-s${season}e$number',
  'Name': 'Episode $number',
  'Type': 'Episode',
  'SeriesName': _cosmos.title,
  'SeriesId': _cosmosOnJellyfin,
  'ParentIndexNumber': season,
  'IndexNumber': number,
  'RunTimeTicks': 12000000000,
  'ImageTags': const <String, Object?>{},
  'UserData': {
    'Played': false,
    'PlaybackPositionTicks': 9000000000,
    'PlayedPercentage': 75.0,
  },
};

/// Jellyfin's Continue watching holds [item] and nothing else.
void _resuming(ProfileHarness harness, Map<String, Object?> item) =>
    harness.network.on(
      WorldIds.jellyfin,
      'GET',
      '/UserItems/Resume',
      (_) => NetworkReply.json({
        'Items': [item],
        'TotalRecordCount': 1,
      }),
    );

/// The two seasons of Cosmos Laundromat, as its page lists them.
void _jellyfinSeasons(ProfileHarness harness) => harness.network.on(
  WorldIds.jellyfin,
  'GET',
  '/Shows/$_cosmosOnJellyfin/Seasons',
  (_) => NetworkReply.json({
    'Items': [
      for (final number in [1, 2])
        {
          'Id': 'jf-cosmos-season$number',
          'Name': 'Season $number',
          'Type': 'Season',
          'SeriesName': _cosmos.title,
          'SeriesId': _cosmosOnJellyfin,
          'IndexNumber': number,
          'ImageTags': const <String, Object?>{},
          'UserData': {'UnplayedItemCount': 3, 'Played': false},
        },
    ],
    'TotalRecordCount': 2,
  }),
);

/// Jellyfin answers the read of Cosmos Laundromat by its id with [answer],
/// and every other read as the world does.
void _jellyfinSeriesRead(
  ProfileHarness harness,
  NetworkReply Function(NetworkRequest request) answer,
) => harness.network.on(
  WorldIds.jellyfin,
  'GET',
  '/Items',
  (request) =>
      request.query['ids'] == _cosmosOnJellyfin ? answer(request) : null,
);

/// The reads that ask Jellyfin for a series by its id: not the room's read of
/// what is playing, for its light (Sintel, a movie).
Iterable<NetworkRequest> _seriesReads(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.jellyfin)
    .where(
      (r) =>
          r.path == '/Items' &&
          r.query.containsKey('ids') &&
          r.query['ids'] != 'jf-${WorldTitles.sintel.key}',
    );

// === Plex ===================================================================

/// P1 with a Plex beside its Jellyfin.
final _withPlex = Profiles.p1.withConnection(WorldConnections.plex);

/// Plex's own rating key for Cosmos Laundromat.
const _show = '4100';

Map<String, Object?> _plexEpisode(int season, int number, String title) => {
  'ratingKey': '$_show$season$number',
  'key': '/library/metadata/$_show$season$number',
  'type': 'episode',
  'title': title,
  'grandparentTitle': 'Cosmos Laundromat',
  'grandparentRatingKey': _show,
  'parentRatingKey': '$_show$season',
  'parentIndex': season,
  'index': number,
  'duration': 720000,
  'viewOffset': 540000,
};

/// Plex's on deck holds [episode] and nothing else.
void _plexOnDeck(ProfileHarness harness, Map<String, Object?> episode) =>
    harness.network.on(
      WorldIds.plex,
      'GET',
      '/hubs/continueWatching',
      (_) => NetworkReply.json({
        'MediaContainer': {
          'size': 1,
          'Hub': [
            {
              'Metadata': [episode],
            },
          ],
        },
      }),
    );

/// Plex answers the read of the show with [guids] as its ids.
void _plexShow(ProfileHarness harness, List<String> guids) =>
    harness.network.on(
      WorldIds.plex,
      'GET',
      '/library/metadata/$_show',
      (_) => NetworkReply.json({
        'MediaContainer': {
          'size': 1,
          'Metadata': [
            {
              'ratingKey': _show,
              'key': '/library/metadata/$_show',
              'type': 'show',
              'title': _cosmos.title,
              'Guid': [
                for (final id in guids) {'id': id},
              ],
            },
          ],
        },
      }),
    );

/// Plex holds Cosmos Laundromat: its ids, and its two seasons.
void _plexHoldsCosmos(ProfileHarness harness) {
  _plexShow(harness, ['tmdb://${_cosmos.tmdbId}', 'tvdb://${_cosmos.tvdbId}']);
  harness.network.on(
    WorldIds.plex,
    'GET',
    '/library/metadata/$_show/children',
    (_) => NetworkReply.json({
      'MediaContainer': {
        'size': 2,
        'Metadata': [
          for (final number in [1, 2])
            {
              'ratingKey': '$_show$number',
              'key': '/library/metadata/$_show$number/children',
              'type': 'season',
              'title': 'Season $number',
              'index': number,
              'parentRatingKey': _show,
              'parentTitle': _cosmos.title,
              'leafCount': 10,
            },
        ],
      },
    }),
  );
}

/// The reads that ask Plex for the show by its rating key.
Iterable<NetworkRequest> _showReads(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.plex)
    .where((r) => r.path == '/library/metadata/$_show');

void main() {
  group('Jellyfin', () {
    testWidgets('an episode in Continue watching opens its series\' page, on '
        'its season', (tester) async {
      // The season Play would continue is the second: this one is the first.
      final (harness, router, container) = await _app(
        tester,
        Profiles.p1,
        before: (harness) => _resuming(harness, _jellyfinEpisode(1, 4)),
      );
      router.go(ServiceRoutes.home);
      await _answer(tester);

      await _tap(tester, RegExp('^${_cosmos.title}'));

      expect(
        router.state.uri.path,
        '${ServiceRoutes.home}/media/tv/${_cosmos.tmdbId}',
      );
      expect(router.state.uri.queryParameters, {
        'i': WorldIds.jellyfin,
        'season': '1',
      });
      expect(_shown(tester).single.mediaKey, MediaKey.tv(_cosmos.tmdbId));
      expect(_shown(tester).single.focus, WorldIds.jellyfin);
      expect(_shown(tester).single.season, 1);
      // One read of the series, through its own connection.
      expect(_seriesReads(harness).map((r) => r.query['ids']), [
        _cosmosOnJellyfin,
      ]);
      expect(await _episodesOpenOn(tester), 1);
      expect(find.text('Episode 10'), findsOneWidget);

      await _close(tester, harness, container);
    });

    testWidgets('a season on its series\' page opens that series\' page, on '
        'that season', (tester) async {
      final (harness, router, container) = await _app(
        tester,
        Profiles.p1,
        before: _jellyfinSeasons,
      );
      router.go(ServiceRoutes.jellyfinItem(_cosmosOnJellyfin));
      await _answer(tester);

      await _tap(tester, RegExp('^Season 1'));

      expect(
        router.state.uri.path,
        '${ServiceRoutes.jellyfinLibraries}/media/tv/${_cosmos.tmdbId}',
      );
      expect(router.state.uri.queryParameters['season'], '1');
      expect(_shown(tester).single.season, 1);
      expect(_shown(tester).single.focus, WorldIds.jellyfin);
      expect(await _episodesOpenOn(tester), 1);

      await _close(tester, harness, container);
    });

    testWidgets('an album keeps opening the server\'s own page, and asks '
        'nothing of a series', (tester) async {
      final (harness, router, container) = await _app(
        tester,
        Profiles.p1,
        before: (harness) => _resuming(harness, {
          'Id': 'jf-album-1',
          'Name': 'Sintel Soundtrack',
          'Type': 'MusicAlbum',
          'AlbumArtist': 'Jan Morgenstern',
          'ImageTags': const <String, Object?>{},
        }),
      );
      // Continue watching is in the server's Activity.
      router.go(ServiceRoutes.streamActivity(ServiceKey.jellyfin));
      await _answer(tester);

      await _tap(tester, RegExp('^Sintel Soundtrack'));

      expect(
        router.state.uri.path,
        '${ServiceRoutes.jellyfinItemBase}/jf-album-1',
      );
      expect(_shown(tester), isEmpty);
      expect(_seriesReads(harness), isEmpty);

      await _close(tester, harness, container);
    });

    testWidgets('a series the server holds no ids for opens the server\'s '
        'own page, as before', (tester) async {
      final (harness, router, container) = await _app(
        tester,
        Profiles.p1,
        before: (harness) {
          _resuming(harness, _jellyfinEpisode(1, 4));
          _jellyfinSeriesRead(
            harness,
            (_) => NetworkReply.json({
              'Items': [
                {
                  'Id': _cosmosOnJellyfin,
                  'Name': _cosmos.title,
                  'Type': 'Series',
                  'ProviderIds': const <String, Object?>{},
                },
              ],
              'TotalRecordCount': 1,
            }),
          );
        },
      );
      router.go(ServiceRoutes.home);
      await _answer(tester);

      await _tap(tester, RegExp('^${_cosmos.title}'));

      expect(
        router.state.uri.path,
        '${ServiceRoutes.jellyfinItemBase}/jf-cosmos-s1e4',
      );
      expect(_shown(tester), isEmpty);
      expect(_seriesReads(harness), hasLength(1));

      await _close(tester, harness, container);
    });

    testWidgets('a series read the server refuses opens the server\'s own '
        'page, asks once and says nothing', (tester) async {
      final (harness, router, container) = await _app(
        tester,
        Profiles.p1,
        before: (harness) {
          _resuming(harness, _jellyfinEpisode(1, 4));
          _jellyfinSeriesRead(harness, (_) => const NetworkReply(500));
        },
      );
      router.go(ServiceRoutes.home);
      await _answer(tester);

      await _tap(tester, RegExp('^${_cosmos.title}'));

      expect(
        router.state.uri.path,
        '${ServiceRoutes.jellyfinItemBase}/jf-cosmos-s1e4',
      );
      expect(_shown(tester), isEmpty);
      // No retry storm, and no word about a lookup the tap made for itself.
      expect(_seriesReads(harness), hasLength(1));
      expect(find.byType(SnackBar), findsNothing);

      await _close(tester, harness, container);
    });
  });

  group('Plex', () {
    testWidgets('an episode on deck opens its show\'s page, on its season', (
      tester,
    ) async {
      final (harness, router, container) = await _app(
        tester,
        _withPlex,
        before: (harness) {
          _plexHoldsCosmos(harness);
          _plexOnDeck(harness, _plexEpisode(1, 4, 'The Seventh Cycle'));
        },
      );
      // On deck is in Activities, a row named by its series.
      router.go(ServiceRoutes.plexActivities);
      await _answer(tester);

      await _tap(tester, RegExp('^Cosmos Laundromat'));

      // Under the tab it was opened from.
      expect(
        router.state.uri.path,
        '${ServiceRoutes.plexActivities}/media/tv/${_cosmos.tmdbId}',
      );
      expect(router.state.uri.queryParameters, {
        'i': WorldIds.plex,
        'season': '1',
      });
      expect(_shown(tester).single.mediaKey, MediaKey.tv(_cosmos.tmdbId));
      expect(_shown(tester).single.focus, WorldIds.plex);
      expect(_shown(tester).single.season, 1);
      expect(_showReads(harness), hasLength(1));
      expect(_showReads(harness).single.query['includeGuids'], '1');
      expect(await _episodesOpenOn(tester), 1);

      await _close(tester, harness, container);
    });

    testWidgets('a season on its show\'s page opens that show\'s page, on '
        'that season', (tester) async {
      final (harness, router, container) = await _app(
        tester,
        _withPlex,
        before: _plexHoldsCosmos,
      );
      router.go(ServiceRoutes.plexItem(_show));
      await _answer(tester);

      await _tap(tester, RegExp('^Season 2'));

      expect(
        router.state.uri.path,
        '${ServiceRoutes.plexLibraries}/media/tv/${_cosmos.tmdbId}',
      );
      expect(router.state.uri.queryParameters['season'], '2');
      expect(_shown(tester).single.season, 2);
      expect(await _episodesOpenOn(tester), 2);

      await _close(tester, harness, container);
    });

    testWidgets('a show Plex holds no ids for opens the server\'s own page, '
        'as before', (tester) async {
      final (harness, router, container) = await _app(
        tester,
        _withPlex,
        before: (harness) {
          _plexOnDeck(harness, _plexEpisode(1, 4, 'The Seventh Cycle'));
          _plexShow(harness, ['plex://show/5d9c081b170e910020f16a4f']);
        },
      );
      router.go(ServiceRoutes.plexActivities);
      await _answer(tester);

      await _tap(tester, RegExp('^Cosmos Laundromat'));

      expect(router.state.uri.path, '${ServiceRoutes.plexItemBase}/${_show}14');
      expect(_shown(tester), isEmpty);
      expect(_showReads(harness), hasLength(1));

      await _close(tester, harness, container);
    });
  });
}
