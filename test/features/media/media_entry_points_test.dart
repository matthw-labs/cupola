/// A movie or a series opened from the app's own entry points lands on its
/// one page, under the tab it was opened from, and the page draws it: what a
/// route test alone cannot say (a placeholder and a real screen resolve the
/// same).
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

import '../../test_helpers/profiles/profiles.dart';

/// The whole app, on [profile]'s household, with its own router.
Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester,
  ConfigProfile profile,
) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The household's startup overrides, onboarding done included.
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
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

/// The title page the user sees.
Iterable<MediaPage> _shown(WidgetTester tester) =>
    tester.widgetList<MediaPage>(find.byType(MediaPage).hitTestable());

void main() {
  testWidgets('a film in the Radarr library opens on its own page, in the '
      'Library tab', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.radarrLibrary);
    await _answer(tester);

    final tile = find.bySemanticsLabel(RegExp('^Tears of Steel'));
    await tester.ensureVisible(tile.first);
    await tester.tap(tile.first);
    await _answer(tester);

    expect(
      router.state.uri.path,
      '${ServiceRoutes.radarrLibrary}/media/movie/'
      '${WorldTitles.tearsOfSteel.tmdbId}',
    );
    expect(_shown(tester).map((page) => page.mediaKey), [
      MediaKey.movie(WorldTitles.tearsOfSteel.tmdbId),
    ]);
    expect(find.text('On your server'), findsOneWidget);

    await _close(tester, harness, container);
  });

  testWidgets('a movie in a Jellyfin library opens on its own page, that '
      "server's copy leading, and so does a series", (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.jellyfinLibrary('films'));
    await _answer(tester);

    final movie = find.bySemanticsLabel(RegExp('^Tears of Steel'));
    await tester.ensureVisible(movie.first);
    await tester.tap(movie.first);
    await _answer(tester);

    expect(
      router.state.uri.path,
      '${ServiceRoutes.jellyfinLibraries}/media/movie/'
      '${WorldTitles.tearsOfSteel.tmdbId}',
    );
    expect(_shown(tester).single.focus, WorldIds.jellyfin);
    expect(find.text('On your server'), findsOneWidget);

    router.go(ServiceRoutes.jellyfinLibrary('films'));
    await _answer(tester);
    final series = find.bySemanticsLabel(
      RegExp('^${WorldTitles.cosmosLaundromat.title}'),
    );
    await tester.ensureVisible(series.first);
    await tester.tap(series.first);
    await _answer(tester);

    expect(
      router.state.uri.path,
      '${ServiceRoutes.jellyfinLibraries}/media/tv/'
      '${WorldTitles.cosmosLaundromat.tmdbId}',
    );
    expect(_shown(tester).single.focus, WorldIds.jellyfin);

    await _close(tester, harness, container);
  });

  testWidgets('a series in the Sonarr library opens on its own page, in the '
      'Library tab', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.sonarrLibrary);
    await _answer(tester);

    final tile = find.bySemanticsLabel(
      RegExp('^${WorldTitles.cosmosLaundromat.title}'),
    );
    await tester.ensureVisible(tile.first);
    await tester.tap(tile.first);
    await _answer(tester);

    expect(
      router.state.uri.path,
      '${ServiceRoutes.sonarrLibrary}/media/tv/'
      '${WorldTitles.cosmosLaundromat.tmdbId}',
    );
    expect(_shown(tester).map((page) => page.mediaKey), [
      MediaKey.tv(WorldTitles.cosmosLaundromat.tmdbId),
    ]);
    // Under the lead, the title's downloads now stand above the episodes: the
    // page reads down to them.
    await tester.scrollUntilVisible(
      find.text('Episodes'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Episodes'), findsWidgets);

    await _close(tester, harness, container);
  });

  group('a link that names a season of a series', () {
    final series = WorldTitles.cosmosLaundromat;
    final at = '${ServiceRoutes.sonarrLibrary}/media/tv/${series.tmdbId}';

    /// The season the episodes open on, once the page has drawn them.
    Future<int> opensOn(
      WidgetTester tester,
      GoRouter router,
      String link,
    ) async {
      router.go(link);
      await _answer(tester);
      await tester.scrollUntilVisible(
        find.text('Episodes'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      return tester
          .widget<MediaEpisodes>(find.byType(MediaEpisodes))
          .initialSeason;
    }

    testWidgets('opens on that season, from the location alone', (
      tester,
    ) async {
      final (harness, router, container) = await _app(tester, Profiles.p1);

      // Play would continue the second: the link asks for the first.
      expect(await opensOn(tester, router, '$at?season=1'), 1);
      expect(_shown(tester).single.season, 1);
      expect(find.text('Episode 10'), findsOneWidget);
      expect(find.text('The Second Cycle'), findsNothing);

      await _close(tester, harness, container);
    });

    testWidgets('a link without one opens where the page always did', (
      tester,
    ) async {
      final (harness, router, container) = await _app(tester, Profiles.p1);

      expect(await opensOn(tester, router, at), 2);
      expect(_shown(tester).single.season, isNull);
      expect(find.text('The Second Cycle'), findsOneWidget);

      await _close(tester, harness, container);
    });

    testWidgets('a season the series does not have falls back to what the '
        'page would open on', (tester) async {
      final (harness, router, container) = await _app(tester, Profiles.p1);

      for (final link in ['$at?season=9', '$at?season=0', '$at?season=x']) {
        expect(await opensOn(tester, router, link), 2, reason: link);
      }

      await _close(tester, harness, container);
    });
  });

  group("a link that names a series by Sonarr's own id", () {
    testWidgets('lands on its page, on that copy', (tester) async {
      final (harness, router, container) = await _app(tester, Profiles.p1);
      router.go(ServiceRoutes.sonarrSeries(1, instanceId: WorldIds.sonarr));
      await _answer(tester);

      expect(
        router.state.uri.toString(),
        startsWith(
          '${ServiceRoutes.sonarrLibrary}/media/tv/'
          '${WorldTitles.cosmosLaundromat.tmdbId}?',
        ),
      );
      expect(_shown(tester).single.focus, WorldIds.sonarr);

      await _close(tester, harness, container);
    });

    /// Sonarr v3: a record with no TMDB id.
    void v3(ProfileHarness harness) => harness.network.on(
      WorldIds.sonarr,
      'GET',
      '/api/v3/series/1',
      (_) => NetworkReply.json({
        'id': 1,
        'title': WorldTitles.cosmosLaundromat.title,
        'tvdbId': WorldTitles.cosmosLaundromat.tvdbId,
        'tmdbId': 0,
      }),
    );

    testWidgets('on Sonarr v3, Seerr names it by TMDB: the same page as '
        "Seerr's", (tester) async {
      final (harness, router, container) = await _app(tester, Profiles.p1);
      v3(harness);
      harness.network.on(
        WorldIds.seerr,
        'GET',
        '/api/v1/search',
        (request) => NetworkReply.json({
          'results': [
            if (request.uri.queryParameters['query'] ==
                'tvdb:${WorldTitles.cosmosLaundromat.tvdbId}')
              {
                'id': WorldTitles.cosmosLaundromat.tmdbId,
                'mediaType': 'tv',
                'name': WorldTitles.cosmosLaundromat.title,
              },
          ],
        }),
      );
      router.go(ServiceRoutes.sonarrSeries(1, instanceId: WorldIds.sonarr));
      await _answer(tester);

      expect(
        router.state.uri.path,
        '${ServiceRoutes.sonarrLibrary}/media/tv/'
        '${WorldTitles.cosmosLaundromat.tmdbId}',
      );

      await _close(tester, harness, container);
    });

    testWidgets('on Sonarr v3 with no Seerr, it opens by TVDB', (tester) async {
      final (harness, router, container) = await _app(tester, Profiles.p4);
      v3(harness);
      router.go(ServiceRoutes.sonarrSeries(1, instanceId: WorldIds.sonarr));
      await _answer(tester);

      expect(
        router.state.uri.path,
        '${ServiceRoutes.sonarrLibrary}/media/tv/tvdb/'
        '${WorldTitles.cosmosLaundromat.tvdbId}',
      );
      expect(_shown(tester).single.mediaKey.tvdbId, isNotNull);

      await _close(tester, harness, container);
    });
  });

  testWidgets('a link that names a film by Radarr\'s own id lands on its '
      'page, on that copy', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.radarrMovie(5, instanceId: WorldIds.radarr));
    await _answer(tester);

    expect(
      router.state.uri.toString(),
      startsWith(
        '${ServiceRoutes.radarrLibrary}/media/movie/'
        '${WorldTitles.tearsOfSteel.tmdbId}?',
      ),
    );
    expect(router.state.uri.queryParameters['i'], WorldIds.radarr);
    expect(_shown(tester).single.focus, WorldIds.radarr);
    expect(find.text('Tears of Steel'), findsWidgets);

    await _close(tester, harness, container);
  });
}
