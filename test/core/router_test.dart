import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/dockge/presentation/dockge_overview_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_stack_detail_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_stack_edit_screen.dart';
import 'package:cupola/features/discover/presentation/seerr_overview_screen.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/media/presentation/arr_title_opener.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/presentation/lidarr_overview_screen.dart';
import 'package:cupola/features/music/presentation/artist_page.dart';
import 'package:cupola/features/readarr/presentation/author_page.dart';
import 'package:cupola/features/npm/presentation/npm_advanced_config_screen.dart';
import 'package:cupola/features/npm/presentation/npm_overview_screen.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_overview_screen.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/outside/domain/outside_link.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_overview_screen.dart';
import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_overview_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_overview_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_overview_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_overview_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/onboarding/presentation/requester_sign_in_screen.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/presentation/pair_offer_screen.dart';
import 'package:cupola/features/pairing/presentation/pair_receive_screen.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/presentation/sonarr_overview_screen.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/arr_calendar_screen.dart';
import 'package:cupola/features/activity/presentation/arr_tab_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_history_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_library_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_providers_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:cupola/features/discover/presentation/seerr_admin_screens.dart';
import 'package:cupola/features/dockge/presentation/dockge_terminal_screen.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_tab_screens.dart';
import 'package:cupola/features/plex/presentation/plex_tab_screens.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_library_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_stats_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_activity_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_history_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_library_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_tab_screens.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_tab_screens.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/discover/domain/seerr_invite.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/presentation/stream_item_screen.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_overview_screen.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_screen.dart';
import 'package:cupola/features/unraid/presentation/unraid_screen.dart';
import 'package:cupola/features/stream/presentation/stream_libraries_screen.dart';
import 'package:cupola/features/stream/presentation/stream_library_screen.dart';
import 'package:cupola/features/settings/presentation/settings_appearance_screen.dart';
import 'package:cupola/features/settings/presentation/settings_connections_screen.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../test_helpers/fake_api_client.dart';
import '../test_helpers/fake_services.dart';
import '../test_helpers/model_builders.dart';
import '../test_helpers/pair_fixtures.dart';
import '../test_helpers/settings_scope.dart';

void main() {
  group('routerProvider', () {
    testWidgets('starts on the Home', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      expect(router.state.uri.toString(), ServiceRoutes.home);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('a first run with nothing set up starts on the Welcome', (
      tester,
    ) async {
      final container = await _pumpRouter(tester, onboardingCompleted: false);
      final router = container.read(routerProvider);

      expect(router.state.uri.toString(), ServiceRoutes.welcome);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('every other route waits for the Welcome on a first run', (
      tester,
    ) async {
      final container = await _pumpRouter(tester, onboardingCompleted: false);
      final router = container.read(routerProvider);

      router.go('/discover');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.welcome);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(DiscoverPage), findsNothing);
    });

    testWidgets('the Welcome is never sent away from', (tester) async {
      // The first connection is saved before the run is over, and "Revisit
      // onboarding" arrives with the flag on: neither may bounce off it.
      final container = await _pumpRouter(
        tester,
        settings: settingsWithServices([ServiceKey.seerr]),
      );
      final router = container.read(routerProvider);

      router.go(ServiceRoutes.welcome);
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), ServiceRoutes.welcome);

      router.go(ServiceRoutes.welcomeConnect);
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), ServiceRoutes.welcomeConnect);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('the sign-in with an account opens outside the shell, from '
        'nothing saved', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(ServiceRoutes.welcomeSignIn);
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), ServiceRoutes.welcomeSignIn);
      expect(find.byType(RequesterSignInScreen), findsOneWidget);
    });

    group('a widget\'s link', () {
      testWidgets('opens the place it names', (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        for (final link in [
          OutsideLink.to(ServiceRoutes.settings).toString(),
          '/open?to=${Uri.encodeQueryComponent(ServiceRoutes.settings)}',
        ]) {
          router.go(link);
          await tester.pumpAndSettle();
          expect(router.state.uri.toString(), ServiceRoutes.settings);
        }
      });

      testWidgets('one that names no place of the app opens the Home', (
        tester,
      ) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        router.go(OutsideLink.to('//evil.example').toString());
        await tester.pumpAndSettle();
        expect(router.state.uri.path, ServiceRoutes.home);
      });

      testWidgets('one carrying a place\'s old spelling still opens it', (
        tester,
      ) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        router.go(OutsideLink.to('/dashboard/radarr').toString());
        await tester.pumpAndSettle();
        expect(router.state.uri.path, startsWith(ServiceRoutes.radarr));
        expect(find.textContaining('GoException'), findsNothing);
      });

      testWidgets('a place no route answers is said in the app\'s words, '
          'with the way Home', (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        router.go('/no/such/place');
        await tester.pumpAndSettle();
        expect(find.text("This page isn't in Cupola"), findsOneWidget);
        expect(find.textContaining('GoException'), findsNothing);

        await tester.tap(find.text('Go to Home'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, ServiceRoutes.home);
      });

      testWidgets('a first run still goes through the way in', (tester) async {
        final container = await _pumpRouter(tester, onboardingCompleted: false);
        final router = container.read(routerProvider);

        router.go(OutsideLink.to(ServiceRoutes.settings).toString());
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), ServiceRoutes.welcome);
      });
    });

    group('an invite\'s link', () {
      const invite = SeerrInvite(
        home: 'http://nas.home.arpa:5055',
        away: 'https://seerr.example.net',
      );
      final signIn = Uri(
        path: ServiceRoutes.welcomeSignIn,
        queryParameters: invite.toUri().queryParameters,
      ).toString();

      testWidgets('opens the sign-in with the invite on a first run', (
        tester,
      ) async {
        final container = await _pumpRouter(tester, onboardingCompleted: false);
        final router = container.read(routerProvider);

        for (final link in [
          invite.toLink(),
          '/invite?${invite.toUri().query}',
        ]) {
          router.go(link);
          await tester.pumpAndSettle();
          expect(router.state.uri.toString(), signIn, reason: link);
          expect(find.byType(RequesterSignInScreen), findsOneWidget);
        }
      });

      testWidgets('opens the Seerr already here at one of its addresses: '
          'the form of a key\'s', (tester) async {
        final container = await _pumpRouter(
          tester,
          settings: const SettingsModel(
            instances: [
              ServiceInstance(
                id: 'seerr',
                service: ServiceKey.seerr,
                url: 'http://nas.home.arpa:5055',
                credential: 'key',
              ),
            ],
          ),
        );
        final router = container.read(routerProvider);

        router.go(invite.toLink());
        await tester.pump();

        expect(
          router.state.uri.toString(),
          ServiceRoutes.settingsForConnection(ServiceKey.seerr, 'seerr'),
        );
        // The page's own test of the connection and its polls, which this
        // test does not look at, end before the tree and its container.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });

      testWidgets('the page of an account\'s, found by its address away', (
        tester,
      ) async {
        final container = await _pumpRouter(
          tester,
          settings: const SettingsModel(
            instances: [
              ServiceInstance(
                id: 'seerr-2',
                service: ServiceKey.seerr,
                url: 'http://other.home.arpa:5055',
                away: ConnectionAddress(url: 'https://seerr.example.net'),
                account: SeerrAccountSignIn(
                  kind: SeerrAccountKind.local,
                  session: 'session',
                ),
              ),
            ],
          ),
        );
        final router = container.read(routerProvider);

        router.go(invite.toLink());
        await tester.pump();

        expect(
          router.state.uri.toString(),
          ServiceRoutes.settingsAccountFor(instanceId: 'seerr-2'),
        );
        // The page's own test of the connection and its polls, which this
        // test does not look at, end before the tree and its container.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
    });

    group('a pairing link', () {
      // The screen takes a link from the notifier by itself, so the cases that
      // look at the link held keep the notifier still.
      Override still() => fixedReceive(const PairReceiveWaiting()).override;
      final link = pairFixtureLink();

      for (final (name, location) in [
        ('as the system hands it over', link.toLink()),
        ('as a router normalises it', '/pair?${link.toUri().query}'),
      ]) {
        for (final onboardingCompleted in [false, true]) {
          testWidgets('opens the screen that copies, '
              '${onboardingCompleted ? 'with connections' : 'on a first run'}, '
              '$name, with the key off the location and held in memory', (
            tester,
          ) async {
            final container = await _pumpRouter(
              tester,
              onboardingCompleted: onboardingCompleted,
              settings: onboardingCompleted
                  ? settingsWithServices([ServiceKey.radarr])
                  : const SettingsModel(),
              overrides: [still()],
            );
            final router = container.read(routerProvider);

            router.go(location);
            await tester.pumpAndSettle();

            expect(router.state.uri.toString(), ServiceRoutes.welcomePair);
            expect(find.byType(PairReceiveScreen), findsOneWidget);
            // No part of the link is left in the location.
            final seen = [
              router.state.uri.toString(),
              router.state.matchedLocation,
              router.state.fullPath ?? '',
              router.routerDelegate.currentConfiguration.uri.toString(),
            ].join(' ');
            expect(seen, isNot(contains(pairFixtureKey)));
            expect(seen, isNot(contains('k=')));
            expect(seen, isNot(contains('192.168')));
            expect(container.read(pendingPairProvider)?.link, link);
            await _letTheWelcomeGo(tester, container);
          });
        }
      }

      testWidgets('one that does not read is held as not whole', (
        tester,
      ) async {
        final container = await _pumpRouter(
          tester,
          onboardingCompleted: false,
          overrides: [still()],
        );
        final router = container.read(routerProvider);

        router.go('cupola://pair?v=1&h=not-an-address&k=cut');
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), ServiceRoutes.welcomePair);
        expect(find.byType(PairReceiveScreen), findsOneWidget);
        expect(container.read(pendingPairProvider)?.link, isNull);
        expect(container.read(pendingPairProvider), isNotNull);
        await _letTheWelcomeGo(tester, container);
      });

      testWidgets('scanned, it is fetched and shown, and held nowhere', (
        tester,
      ) async {
        final fetched = <Object>[];
        final container = await _pumpRouter(
          tester,
          onboardingCompleted: false,
          overrides: [
            pairNetworkProvider.overrideWithValue(
              PairNetwork(
                fetch: (link) async {
                  fetched.add(link);
                  return pairFixturePackage();
                },
              ),
            ),
          ],
        );
        final router = container.read(routerProvider);

        router.go(link.toLink());
        await tester.pumpAndSettle();

        expect(fetched, [link]);
        expect(find.text('From your iPhone'), findsOneWidget);
        expect(container.read(pendingPairProvider), isNull);
        expect(router.state.uri.toString(), ServiceRoutes.welcomePair);
        await _letTheWelcomeGo(tester, container);
      });
    });

    testWidgets('the code another device copies from is a page of Settings', (
      tester,
    ) async {
      final offer = fixedOffer(const PairOfferPreparing());
      final container = await _pumpRouter(
        tester,
        settings: settingsWithServices([ServiceKey.radarr]),
        overrides: [offer.override],
      );
      final router = container.read(routerProvider);

      router.go(ServiceRoutes.settingsAnotherDevice);
      await tester.pump(const Duration(milliseconds: 100));

      expect(router.state.uri.toString(), ServiceRoutes.settingsAnotherDevice);
      expect(find.byType(PairOfferScreen), findsOneWidget);
      expect(offer.notifier.started, hasLength(1));
      await _letTheWelcomeGo(tester, container);
    });

    testWidgets('the old onboarding address opens the Welcome', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(ServiceRoutes.legacyOnboarding);
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.welcome);
    });

    testWidgets('redirects invalid discover detail ids back to Discover', (
      tester,
    ) async {
      // Two hops, and both are the point: the old Seerr spelling rewrites to
      // the title's page in the Discover tab, and *that* route rejects the id.
      // It falls back to the tab the page would have been pushed from rather
      // than to the app home.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/stack/seerr/movie/not-a-number');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.discover);
      expect(find.byType(MediaPage), findsNothing);
    });

    testWidgets(
      'a Seerr title lands on its own page with its poster decoded once',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);
        const encodedPosterUrl =
            'https%3A%2F%2Fcdn.example.com%2Fposter%20image.jpg';

        // A series is its own page in the Discover tab, the poster decoded
        // once.
        router.go('/stack/seerr/discover/tv/123?posterUrl=$encodedPosterUrl');
        await tester.pumpAndSettle();

        expect(
          router.state.uri.toString(),
          '/discover/media/tv/123?posterUrl=$encodedPosterUrl',
        );
        final series = tester.widget<MediaPage>(
          find.byType(MediaPage).hitTestable(),
        );
        expect(series.mediaKey, const MediaKey.tv(123));
        expect(series.posterUrl, 'https://cdn.example.com/poster image.jpg');

        // A movie is its own page in the Discover tab, the poster decoded
        // once.
        router.go(
          '/stack/seerr/discover/movie/123?posterUrl=$encodedPosterUrl',
        );
        await tester.pumpAndSettle();

        expect(
          router.state.uri.toString(),
          '/discover/media/movie/123?posterUrl=$encodedPosterUrl',
        );
        final page = tester.widget<MediaPage>(
          find.byType(MediaPage).hitTestable(),
        );
        expect(page.mediaKey, const MediaKey.movie(123));
        expect(page.posterUrl, 'https://cdn.example.com/poster image.jpg');
      },
    );

    testWidgets(
      'supports deep-linked library detail routes without extras and preserves default hero tags',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        router.go('/stack/radarr/movie/42');
        await tester.pumpAndSettle();

        // A title named by an arr's own id opens the way to its own page.
        final opener = tester.widget<ArrTitleOpener>(
          find.byType(ArrTitleOpener),
        );
        expect(opener.arr, ServiceKey.radarr);
        expect(opener.heroTag, 'movie_42');
        expect(opener.id, 42);

        router.go('${ServiceRoutes.sonarrSeriesBase}/55');
        await tester.pumpAndSettle();

        final seriesOpener = tester.widget<ArrTitleOpener>(
          find.byType(ArrTitleOpener),
        );
        expect(seriesOpener.arr, ServiceKey.sonarr);
        expect(seriesOpener.heroTag, 'series_55');
        expect(seriesOpener.id, 55);

        router.go('${ServiceRoutes.lidarrArtistBase}/9');
        await tester.pumpAndSettle();

        final artistPage = tester.widget<ArtistPage>(find.byType(ArtistPage));
        expect(artistPage.heroTag, 'artist_9');
        expect(artistPage.artistId, 9);
        expect(artistPage.initialArtist, isNull);

        router.go('${ServiceRoutes.readarrAuthorBase}/7?i=readarr-2');
        await tester.pumpAndSettle();

        final authorPage = tester.widget<AuthorPage>(find.byType(AuthorPage));
        expect(authorPage.heroTag, 'author_7');
        expect(authorPage.authorId, 7);
        expect(authorPage.instanceId, 'readarr-2');
      },
    );

    testWidgets('redirects invalid library detail ids back to the library', (
      tester,
    ) async {
      // The fallback moved with the film. A bad id used to drop the user at
      // the app home, which was the only place a detail route could name
      // before it had a tab around it; now the film is a page inside Library,
      // so the nearest place that exists is the list it was pushed from.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/stack/radarr/movie/not-a-number', extra: buildMovie(id: 42));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.radarrLibrary);
      expect(find.byType(MoviesScreen), findsOneWidget);
      expect(find.byType(ArrTitleOpener), findsNothing);
    });

    testWidgets(
      'library detail routes ignore wrong-type and mismatched extras instead of redirecting',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        // Aimed at the canonical path: the one `ServiceRoutes.radarrMovie`
        // builds and every in-app caller emits, rather than at the pre-tab
        // `radarr/movie/:id` tail. That tail still resolves, but only by
        // redirecting, and go_router re-matches a redirect with
        // `findMatch(uri)` and no extra: the preload would arrive as null and
        // the second half of this case would assert nothing.
        router.go(ServiceRoutes.radarrMovie(42), extra: buildArtist(id: 9));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), ServiceRoutes.radarrMovie(42));
        // The film is read from the path, whatever the extra carries.
        expect(
          tester.widget<ArrTitleOpener>(find.byType(ArrTitleOpener)).id,
          42,
        );

        router.go(ServiceRoutes.radarrMovie(42), extra: buildMovie(id: 7));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), ServiceRoutes.radarrMovie(42));
        expect(
          tester.widget<ArrTitleOpener>(find.byType(ArrTitleOpener)).id,
          42,
        );
      },
    );

    testWidgets('an unknown service\'s settings land on the connections, '
        'never on another service\'s form', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/service/not-a-service');
      await tester.pumpAndSettle();

      // It used to open Seerr's form under a link that named something else.
      expect(find.byType(ServiceSettingsScreen), findsNothing);
      expect(find.byType(SettingsConnectionsScreen), findsOneWidget);
      expect(router.state.uri.toString(), ServiceRoutes.settingsConnections);
    });

    testWidgets('Seerr\'s former name still opens its form', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/service/jellyseerr');
      await tester.pumpAndSettle();

      final screen = tester.widget<ServiceSettingsScreen>(
        find.byType(ServiceSettingsScreen),
      );
      expect(screen.service, ServiceKey.seerr);
      // The page prints the service's name alone: "Seerr Settings" is the name
      // of Seerr's own configuration, which is a different page from the form
      // that tells Cupola how to reach it.
      expect(find.text(ServiceKey.seerr.title), findsWidgets);
    });

    testWidgets('supports appearance and connections settings subroutes', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/appearance');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsAppearanceScreen), findsOneWidget);

      router.go('/settings/connections');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsConnectionsScreen), findsOneWidget);
    });

    testWidgets('the old services settings path redirects to connections', (
      tester,
    ) async {
      // '/settings/services' was the route before the two service lists were
      // merged; a saved deep link should land on the screen that replaced it
      // rather than 404.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/services');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsConnectionsScreen), findsOneWidget);
      expect(router.state.uri.toString(), '/settings/connections');
    });

    testWidgets('Discover is a tab, and the Search tab it replaced lands '
        'on it', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/discover');
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/discover');
      expect(find.byType(DiscoverPage), findsOneWidget);

      // One hop, query and all, for the tab and for a title opened from it.
      for (final (from, to) in [
        ('/search', '/discover'),
        (
          '/search/media/movie/603?heroTag=t',
          '/discover/media/movie/603?heroTag=t',
        ),
        ('/discover/movie/603', '/discover/media/movie/603'),
        ('/discover/requests', ServiceRoutes.seerrRequests),
      ]) {
        router.go(from);
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), to, reason: from);
      }
    });

    testWidgets('supports service dashboard routes', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      // A service on the tab model has a redirect-only prefix for a root: the
      // service home is a tab now, so the bare path names a place that draws
      // nothing and hands off to Overview.
      for (final entry in {
        ServiceRoutes.seerr: ServiceRoutes.seerrOverview,
        ServiceRoutes.radarr: ServiceRoutes.radarrOverview,
        ServiceRoutes.sonarr: ServiceRoutes.sonarrOverview,
        ServiceRoutes.lidarr: ServiceRoutes.lidarrOverview,
        ServiceRoutes.readarr: ServiceRoutes.readarrOverview,
        ServiceRoutes.qbittorrent: ServiceRoutes.qbittorrentOverview,
        ServiceRoutes.transmission: ServiceRoutes.transmissionOverview,
        ServiceRoutes.sabnzbd: ServiceRoutes.sabnzbdOverview,
        ServiceRoutes.nzbget: ServiceRoutes.nzbgetOverview,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value, reason: entry.key);
      }
    });

    testWidgets('every tab on an arr\'s bar resolves to its own location', (
      tester,
    ) async {
      // The bar draws one label per entry in `tabsFor`, so a tab the table
      // names with no branch behind it would 404 on tap rather than fail
      // anywhere a reader would look. Three of the four are faked by this
      // harness; the fourth, Readarr, needs no fake because every one of its
      // tabs checks `isServiceConfigured` before it reads anything: an
      // unconfigured service is answered without a request, so there is no
      // retry timer to leave pending.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final service in [
        ServiceKey.radarr,
        ServiceKey.sonarr,
        ServiceKey.lidarr,
        ServiceKey.readarr,
      ]) {
        for (final tab in tabsFor(service)!) {
          final location = '/stack/${service.routeParam}/${tab.segment}';
          router.go(location);
          await tester.pumpAndSettle();

          expect(
            router.state.uri.toString(),
            location,
            reason: '${service.name}.${tab.name}',
          );
        }
      }
    });

    testWidgets('every tab on Seerr\'s bar resolves to its own location', (
      tester,
    ) async {
      // The bar draws one label per entry in `tabsFor`, so a tab the table
      // names with no branch behind it would 404 on tap rather than fail
      // anywhere a reader would look. Seerr is faked by this harness, so
      // Overview, Requests and Discover all reach a service; Issues and Users
      // answer without a request.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final tab in tabsFor(ServiceKey.seerr)!) {
        final location = '/stack/seerr/${tab.segment}';
        router.go(location);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), location, reason: tab.name);
      }
    });

    testWidgets('every pre-tab Seerr path still resolves', (tester) async {
      // Seerr shipped more link shapes than any other service, all of them
      // hanging off the service root because the service root *was* Discover.
      // Every one of them lives in the app's Discover tab now, so every one
      // needs a tail, and the `.../all` literals need to be matched before
      // the `:id` details, or `/dashboard/seerr/tv/all` becomes a title whose
      // id is the word `all`. Both spellings of the prefix, because the
      // `/services` rewrite chains into these rather than duplicating them.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final prefix in [
        '/stack/seerr',
        '/dashboard/seerr',
        '/services/seerr',
      ]) {
        for (final entry in {
          '': ServiceRoutes.seerrOverview,
          '/requests': ServiceRoutes.seerrRequests,
          // The three see-alls are catalogue pages, in one hop.
          '/movies/all': '/discover/all/movie',
          '/tv/all': '/discover/all/tv',
          '/trending/all': '/discover/trending',
          '/genre/tv/28?title=Action': '/discover/genre/tv/28?title=Action',
          // A title is its own page, and a person and a collection hang
          // beside it.
          '/movie/42': '/discover/media/movie/42',
          '/tv/55': '/discover/media/tv/55',
          '/person/287?heroTag=cast_287':
              '/discover/media/person/287?heroTag=cast_287',
          '/collection/10': '/discover/media/collection/10',
          // The same shapes under the Discover tab Seerr's room used to have.
          '/discover': ServiceRoutes.discover,
          '/discover/trending/all': '/discover/trending',
          '/discover/person/287': '/discover/media/person/287',
          '/discover/media/movie/42?heroTag=t':
              '/discover/media/movie/42?heroTag=t',
        }.entries) {
          final from = '$prefix${entry.key}';
          router.go(from);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), entry.value, reason: from);
        }
      }
    });

    testWidgets('every catalogue page resolves from its path, and a path it '
        'cannot read goes back to the atrium', (tester) async {
      // No Seerr is set up, so each page draws its placeholder and asks
      // nothing: what is asserted is where the path lands.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final entry in {
        '/discover/all/movie': '/discover/all/movie',
        '/discover/trending?window=day': '/discover/trending?window=day',
        '/discover/upcoming/tv': '/discover/upcoming/tv',
        '/discover/genre/tv/16?title=Animation':
            '/discover/genre/tv/16?title=Animation',
        '/discover/network/213': '/discover/network/213',
        '/discover/studio/41077': '/discover/studio/41077',
        '/discover/keyword/movie/4379': '/discover/keyword/movie/4379',
        '/discover/language/tv/ko': '/discover/language/tv/ko',
        '/discover/decade/movie/1990': '/discover/decade/movie/1990',
        // The first catalogue's see-alls.
        '/discover/movies/all': '/discover/all/movie',
        '/discover/tv/all': '/discover/all/tv',
        '/discover/trending/all': '/discover/trending',
        // Parameters no page can be built from.
        '/discover/all/book': ServiceRoutes.discover,
        '/discover/genre/movie/x': ServiceRoutes.discover,
        '/discover/decade/movie/1995': ServiceRoutes.discover,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value, reason: entry.key);
      }
    });

    testWidgets(
      'every tab on a download client\'s bar resolves to its own location',
      (tester) async {
        // The same rule the \*arr case asserts, on the services whose bars do
        // not match each other: qBittorrent has RSS where Transmission has
        // Labels and Session, so there is no shared list and every one of them
        // has to be walked.
        //
        // No fakes: every tab of these services answers an unconfigured
        // connection without a request: the placeholder asks
        // `isServiceConfigured` first and the queues gate on it too, so there
        // is no retry timer left pending by the time the case ends.
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        for (final service in [
          ServiceKey.qbittorrent,
          ServiceKey.transmission,
          ServiceKey.sabnzbd,
          ServiceKey.nzbget,
        ]) {
          for (final tab in tabsFor(service)!) {
            final location = '/stack/${service.routeParam}/${tab.segment}';
            router.go(location);
            await tester.pumpAndSettle();

            expect(
              router.state.uri.toString(),
              location,
              reason: '${service.name}.${tab.name}',
            );
          }
        }
      },
    );

    testWidgets('every Overview that has been built is the one that draws', (
      tester,
    ) async {
      // A branch that resolves is not a branch that shows the right page: for
      // months every one of these tabs resolved to a placeholder,
      // which is a legitimate destination, so the location assertions above
      // stayed green while eight Overviews sat in the tree reachable by
      // nothing. This table is the one that would have caught it: it names
      // the widget each Overview must build, and the `findsNothing` on the
      // placeholder is what fails when a screen is unmounted again.
      //
      // Every one of the sixteen services on the tab model is listed, which
      // it can be now that the last five Overviews are mounted: nothing on
      // this model draws a placeholder on its first tab any more. TrueNAS is
      // absent because it has no bar at all: `tabsFor` returns null for it by
      // design, the console being ten sections that do not fit on one.
      //
      // Jellyfin and Plex both name `StreamOverviewScreen`, and that is the
      // assertion rather than an accident of the table: one screen serves both
      // servers, parameterised by `ServiceKey`, the way every other surface in
      // that folder is.
      //
      // No fake needed: this harness leaves every service unconfigured and
      // each of these screens checks `isServiceConfigured` before it reaches a
      // provider, so nothing is requested and no retry timer outlives the case.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      final overviews = <String, Type>{
        ServiceRoutes.radarrOverview: RadarrOverviewScreen,
        ServiceRoutes.sonarrOverview: SonarrOverviewScreen,
        ServiceRoutes.lidarrOverview: LidarrOverviewScreen,
        ServiceRoutes.readarrOverview: ReadarrOverviewScreen,
        ServiceRoutes.qbittorrentOverview: QbittorrentOverviewScreen,
        ServiceRoutes.transmissionOverview: TransmissionOverviewScreen,
        ServiceRoutes.sabnzbdOverview: SabnzbdOverviewScreen,
        ServiceRoutes.nzbgetOverview: NzbgetOverviewScreen,
        ServiceRoutes.seerrOverview: SeerrOverviewScreen,
        ServiceRoutes.bazarrOverview: BazarrOverviewScreen,
        ServiceRoutes.prowlarrOverview: ProwlarrOverviewScreen,
        ServiceRoutes.dockgeOverview: DockgeOverviewScreen,
        ServiceRoutes.unraidOverview: UnraidOverviewScreen,
        ServiceRoutes.npmOverview: NpmOverviewScreen,
        ServiceRoutes.jellyfinOverview: StreamOverviewScreen,
        ServiceRoutes.plexOverview: StreamOverviewScreen,
        ServiceRoutes.embyOverview: StreamOverviewScreen,
      };

      for (final entry in overviews.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.key, reason: entry.key);
        expect(
          find.byType(entry.value),
          findsOneWidget,
          reason: '${entry.key} must draw ${entry.value}',
        );
      }
    });

    testWidgets('every tab on Bazarr\'s bar resolves to its own location', (
      tester,
    ) async {
      // Six tabs, the widest bar in the app. No fake: every Bazarr surface
      // checks `isServiceConfigured` before it reads anything, so an
      // unconfigured connection is answered without a request and there is no
      // retry timer left pending.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final tab in tabsFor(ServiceKey.bazarr)!) {
        final location = '/stack/bazarr/${tab.segment}';
        router.go(location);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), location, reason: tab.name);
      }
    });

    testWidgets('every pre-tab Bazarr path still resolves', (tester) async {
      // Three shapes moved and one did not, which is the whole point of the
      // table: `library` was the combined Series/Movies page and lands on
      // Series, the singular `movie/:id` lands on the film inside Movies, and
      // `series/:id` is unchanged because the Series tab's root IS its base.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final prefix in [
        '/stack/bazarr',
        '/dashboard/bazarr',
        '/services/bazarr',
      ]) {
        for (final entry in {
          '': ServiceRoutes.bazarrOverview,
          '/library': ServiceRoutes.bazarrSeriesBase,
          '/wanted': ServiceRoutes.bazarrWanted,
          '/series/7': ServiceRoutes.bazarrSeries(7),
          '/movie/12': ServiceRoutes.bazarrMovie(12),
        }.entries) {
          final from = '$prefix${entry.key}';
          router.go(from);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), entry.value, reason: from);
        }
      }
    });

    testWidgets('every tab on Prowlarr\'s bar resolves to its own location', (
      tester,
    ) async {
      // No fake: every Prowlarr surface checks `isServiceConfigured` before it
      // reads anything, so an unconfigured connection is answered without a
      // request and there is no retry timer left pending.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final tab in tabsFor(ServiceKey.prowlarr)!) {
        final location = '/stack/prowlarr/${tab.segment}';
        router.go(location);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), location, reason: tab.name);
      }
    });

    testWidgets('every pre-tab Prowlarr path still resolves', (tester) async {
      // Settings is in this table for the opposite reason to the others: it is
      // NOT a tab (decision 26) and must not have moved. It hangs off the
      // service node beside the shell, so a link into any of its sections has
      // to keep landing exactly where it did.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final prefix in [
        '/stack/prowlarr',
        '/dashboard/prowlarr',
        '/services/prowlarr',
      ]) {
        for (final entry in {
          '': ServiceRoutes.prowlarrOverview,
          '/library': ServiceRoutes.prowlarrIndexers,
          '/indexer/3': ServiceRoutes.prowlarrIndexer(3),
          '/settings': ServiceRoutes.prowlarrSettings,
          '/settings/tags': ServiceRoutes.prowlarrTags,
          '/settings/sync-profiles': ServiceRoutes.prowlarrSyncProfiles,
        }.entries) {
          final from = '$prefix${entry.key}';
          router.go(from);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), entry.value, reason: from);
        }
      }
    });

    testWidgets('the pre-tab download client paths still resolve', (
      tester,
    ) async {
      // Every path shape these services ever shipped, in both spellings: the
      // bare root, the tab-less detail, and the same two under the pre-rename
      // `/services` prefix. The prefix rewrite chains into the per-service
      // redirects rather than duplicating them, so what this asserts is that
      // the chain finishes: a rewrite that stopped at the first hop would
      // leave the user on a path that draws nothing.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final entry in {
        ServiceRoutes.qbittorrent: ServiceRoutes.qbittorrentOverview,
        '/services/qbittorrent': ServiceRoutes.qbittorrentOverview,
        '/stack/qbittorrent/torrent/abc123': ServiceRoutes.qbittorrentTorrent(
          'abc123',
        ),
        '/dashboard/qbittorrent/torrent/abc123':
            ServiceRoutes.qbittorrentTorrent('abc123'),
        '/services/qbittorrent/torrent/abc123':
            ServiceRoutes.qbittorrentTorrent('abc123'),
        // Transmission carries only its root, in both spellings: it never had
        // a detail path to keep resolving.
        ServiceRoutes.transmission: ServiceRoutes.transmissionOverview,
        '/services/transmission': ServiceRoutes.transmissionOverview,
        // SABnzbd likewise: a job is an expanding row, never a pushed page.
        ServiceRoutes.sabnzbd: ServiceRoutes.sabnzbdOverview,
        '/services/sabnzbd': ServiceRoutes.sabnzbdOverview,
        // NZBGet, the same: a group is an expanding row, never a pushed page.
        ServiceRoutes.nzbget: ServiceRoutes.nzbgetOverview,
        '/services/nzbget': ServiceRoutes.nzbgetOverview,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value, reason: entry.key);
      }
    });

    testWidgets('supports service all-list routes', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/stack/seerr/requests');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/stack/seerr/requests');
      expect(find.byType(ServiceAllRequestsScreen), findsOneWidget);

      // Readarr never had a `media` tail and does not grow one here: its
      // author list always lived at `library`, which is now the tab.
      // `media` was the all-list tail the other three arrs carried. On the tab model it
      // lands on the Library tab rather than on the service root, because the
      // whole library IS a tab now; a service still off the model has nowhere
      // but its root to go.
      for (final entry in {
        '/stack/radarr/media': ServiceRoutes.radarrLibrary,
        '/stack/sonarr/media': ServiceRoutes.sonarrLibrary,
        '/stack/lidarr/media': ServiceRoutes.lidarrLibrary,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value, reason: entry.key);
        expect(find.byType(ServiceAllRequestsScreen), findsNothing);
      }
    });

    testWidgets('every pre-rename /services path still resolves', (
      tester,
    ) async {
      // The rename moved thirty-four routes and every detail tail under them.
      // A bookmark, a restored session or a shared deep link from before it
      // must not 404, and the rewrite is a prefix swap rather than a shadow
      // copy of the tree, so what this asserts is that the swap reaches the
      // *descendants*, not just the root.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      // Only services this harness fakes: an unfaked one leaves a provider
      // retry timer pending and the failure would be about the fixture rather
      // than about the rewrite.
      // `/services/radarr` takes two hops now: the prefix rewrite lands it on
      // `/stack/radarr`, which is redirect-only and hands off to Overview.
      // That chaining is the property: a rewrite that stopped at the first
      // hop would leave the user on a path that draws nothing.
      const cases = {
        '/services': '/stack',
        '/services/radarr': ServiceRoutes.radarrOverview,
        '/services/sonarr': ServiceRoutes.sonarrOverview,
        '/services/lidarr': ServiceRoutes.lidarrOverview,
        '/services/readarr': ServiceRoutes.readarrOverview,
        '/services/seerr/requests': '/stack/seerr/requests',
      };

      for (final entry in cases.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), entry.value, reason: entry.key);
      }
    });

    testWidgets('the legacy rewrite keeps the query, lens included', (
      tester,
    ) async {
      // The instance lens travels as `?i=`, so a rewrite that dropped the
      // query would silently retarget a deep link at whichever connection the
      // lens happens to point at: the one failure mode of this change that
      // moves a user's files rather than just their view.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      // `heroTag` stands in for the lens here only because pointing `i=` at a
      // connection this harness does not define leaves a provider retrying;
      // the property under test is the whole query surviving the swap, and
      // that is what `i=` rides on in production.
      // Three hops, and the query survives all of them: the prefix rewrite,
      // then the pre-tab `radarr/movie/:id` tail, then the film inside the
      // Library branch where it lives now.
      router.go('/services/radarr/movie/42?heroTag=legacy_movie');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.radarrMovieBase}/42?heroTag=legacy_movie',
      );
      expect(find.byType(ArrTitleOpener), findsOneWidget);
    });

    testWidgets('a path that merely starts with the old prefix is not moved', (
      tester,
    ) async {
      // `startsWith('/services')` would rewrite `/services-of-mine` too. The
      // rewrite matches on the segment boundary, so an unknown path stays
      // unknown and falls through to the router's own handling.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/servicesfoo');
      await tester.pumpAndSettle();

      // Asserted on what rendered rather than on `router.state`: an unmatched
      // location leaves the match list empty and reading `state` throws, which
      // would pass this test for entirely the wrong reason.
      expect(find.byType(StackScreen), findsNothing);
    });

    testWidgets('legacy top-level routes redirect to services', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      // `/discover` was one of these; it is a tab of the app now.
      const routes = {
        '/movies': ServiceRoutes.radarrLibrary,
        '/series': ServiceRoutes.sonarrLibrary,
        '/music': ServiceRoutes.lidarrLibrary,
      };
      for (final entry in routes.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value);
        expect(find.byType(StackScreen), findsNothing);
      }
    });

    testWidgets('legacy detail routes redirect to equivalent services routes', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      const encodedPosterUrl =
          'https%3A%2F%2Fcdn.example.com%2Fposter%20image.jpg';
      router.go('/discover/movie/123?posterUrl=$encodedPosterUrl');
      await tester.pumpAndSettle();

      // One hop: the pre-rename detail is the movie's own page in the
      // Discover tab. What this asserts is that it lands, query and all: a
      // rewrite that stopped early would leave the user on a path that draws
      // nothing.
      expect(
        router.state.uri.toString(),
        '/discover/media/movie/123?posterUrl=$encodedPosterUrl',
      );
      expect(find.byType(MediaPage), findsOneWidget);

      // `/movies/:id` still crosses in one hop, but its destination moved
      // inside the Library branch with the film.
      router.go('/movies/42?heroTag=legacy_movie');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.radarrMovieBase}/42?heroTag=legacy_movie',
      );
      expect(find.byType(ArrTitleOpener), findsOneWidget);

      router.go('/series/55?heroTag=legacy_series');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.sonarrSeriesBase}/55?heroTag=legacy_series',
      );
      expect(find.byType(ArrTitleOpener), findsOneWidget);

      router.go('/music/9?heroTag=legacy_artist');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.lidarrArtistBase}/9?heroTag=legacy_artist',
      );
      expect(find.byType(ArtistPage), findsOneWidget);
    });
  });

  /// Jellyfin and Plex: two services, one screen family, two different bars.
  ///
  /// Every case here is about the move onto the tab model: the service root
  /// that now redirects, the two spellings the single-page service shipped, and
  /// the declaration order inside the Libraries branch. Neither server is
  /// configured in this harness, which is deliberate: an unconfigured tab is a
  /// destination users reach routinely, every surface here gates on
  /// `isServiceConfigured` before it reaches a provider so nothing is asked of
  /// a server that is not there, and it keeps the case about routing rather
  /// than about a fixture.
  group('the media servers on the tab model', () {
    testWidgets('the bare service path lands on Overview', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final entry in {
        ServiceRoutes.jellyfin: ServiceRoutes.jellyfinOverview,
        ServiceRoutes.plex: ServiceRoutes.plexOverview,
        ServiceRoutes.emby: ServiceRoutes.embyOverview,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value, reason: entry.key);
        // One screen for both servers, so the assertion names the same type
        // twice. Asserting the type rather than the location is what makes the
        // redirect's destination a real page: for months it landed on
        // a placeholder, which resolves just as happily.
        expect(
          find.byType(StreamOverviewScreen),
          findsOneWidget,
          reason: entry.value,
        );
      }
    });

    testWidgets('every tab on the bar has a branch that resolves', (
      tester,
    ) async {
      // The bar is generated from `tabsFor`, so a tab without a branch is an
      // index that selects nothing. Walking all twelve is what makes the
      // wildcard's `UnsupportedError` a promise rather than a comment.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final service in mediaServers) {
        for (final tab in tabsFor(service)!) {
          final location =
              '${ServiceRoutes.forService(service)}/${tab.segment}';
          router.go(location);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), location, reason: location);
        }
      }
    });

    testWidgets('the Libraries tab is the library list', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(ServiceRoutes.jellyfinLibraries);
      await tester.pumpAndSettle();

      expect(find.byType(StreamLibrariesScreen), findsOneWidget);
    });

    testWidgets('the pre-tab spellings cross in ONE hop, query intact', (
      tester,
    ) async {
      // `/dashboard/jellyfin/library/:id` and `/dashboard/jellyfin/item/:id`
      // are what a one-page service could offer, and both are still in the
      // wild: `ServiceRoutes.jellyfinItem` built the second for every poster
      // tile, every search result and the availability slot on an arr detail.
      // The tails rewrite them into the Libraries branch without losing the
      // display name that spares the destination a fetch.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('${ServiceRoutes.jellyfin}/library/f137a2dd?title=Films');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.jellyfinLibraries}/f137a2dd?title=Films',
      );
      final browse = tester.widget<StreamLibraryScreen>(
        find.byType(StreamLibraryScreen),
      );
      expect(browse.libraryId, 'f137a2dd');
      expect(browse.libraryTitle, 'Films');

      router.go('${ServiceRoutes.plex}/item/9421');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.plexItem('9421'));
      expect(
        tester.widget<StreamItemScreen>(find.byType(StreamItemScreen)).itemId,
        '9421',
      );
    });

    testWidgets('?i= reaches the media server page that reads it', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(ServiceRoutes.plexItem('9421', instanceId: 'plex-2'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StreamItemScreen>(find.byType(StreamItemScreen))
            .instanceId,
        'plex-2',
      );

      router.go(ServiceRoutes.jellyfinLibrary('f137a2dd', instanceId: 'cabin'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StreamLibraryScreen>(find.byType(StreamLibraryScreen))
            .instanceId,
        'cabin',
      );

      router.go(
        ServiceRoutes.streamActivity(ServiceKey.jellyfin, instanceId: 'cabin'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<JellyfinActivityScreen>(find.byType(JellyfinActivityScreen))
            .instanceId,
        'cabin',
      );

      router.go(
        ServiceRoutes.streamActivity(ServiceKey.plex, instanceId: 'plex-2'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PlexActivitiesScreen>(find.byType(PlexActivitiesScreen))
            .instanceId,
        'plex-2',
      );

      // Without it a deep link resolves from the path alone, on the active
      // connection.
      router.go(ServiceRoutes.plexItem('9421'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StreamItemScreen>(find.byType(StreamItemScreen))
            .instanceId,
        isNull,
      );
    });

    testWidgets('the pre-tab item spelling keeps ?i= across its hop', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('${ServiceRoutes.jellyfin}/item/abc-123?i=cabin');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        ServiceRoutes.jellyfinItem('abc-123', instanceId: 'cabin'),
      );
      expect(
        tester
            .widget<StreamItemScreen>(find.byType(StreamItemScreen))
            .instanceId,
        'cabin',
      );
    });

    testWidgets('the item literal beats the library id that follows it', (
      tester,
    ) async {
      // Routes match in declaration order and `item` competes with the library
      // browse's `:id` in the same branch: declared the other way round,
      // `/dashboard/plex/libraries/item/9421` resolves as a library whose id is
      // the word `item`, and the user gets a browse of nothing.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(ServiceRoutes.plexItem('9421'));
      await tester.pumpAndSettle();

      expect(find.byType(StreamItemScreen), findsOneWidget);
      expect(find.byType(StreamLibraryScreen), findsNothing);
    });

    testWidgets('an item pushed from another app tab still resolves', (
      tester,
    ) async {
      // How every poster tile, every global search result and the availability
      // slot on a Radarr or Sonarr detail reaches an item: a `push`, from
      // wherever the user happens to be. The destination is now a page inside
      // the Libraries branch of a nested shell rather than a sibling of the
      // service root, so this asserts the push still builds the whole chain.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(ServiceRoutes.discover);
      await tester.pumpAndSettle();
      router.push(ServiceRoutes.jellyfinItem('abc-123'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<StreamItemScreen>(find.byType(StreamItemScreen)).itemId,
        'abc-123',
      );
    });

    testWidgets('the legacy /services prefix still reaches both details', (
      tester,
    ) async {
      // Three hops for the item: prefix rewrite, pre-tab tail, then the route
      // inside the branch, and what this asserts is that the chain finishes.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/services/jellyfin/item/abc-123');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        ServiceRoutes.jellyfinItem('abc-123'),
      );
      expect(find.byType(StreamItemScreen), findsOneWidget);

      router.go('/services/plex');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.plexOverview);
    });
  });

  /// Dockge, Unraid and Nginx Proxy Manager: the three that were one page each.
  ///
  /// None of them is configured in this harness, which is deliberate and is
  /// what keeps these cases about routing: every destination below gates on
  /// `isServiceConfigured` before it reaches a provider, so an unconfigured
  /// service draws its not-configured door without asking anything for
  /// anything, and a destination that did ask would leave a retrying provider
  /// behind and fail this file at teardown rather than at the assertion.
  group('the infrastructure three on the tab model', () {
    testWidgets('the bare service path lands on Overview', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final entry in {
        ServiceRoutes.dockge: (
          ServiceRoutes.dockgeOverview,
          DockgeOverviewScreen,
        ),
        ServiceRoutes.unraid: (
          ServiceRoutes.unraidOverview,
          UnraidOverviewScreen,
        ),
        ServiceRoutes.nginxProxyManager: (
          ServiceRoutes.npmOverview,
          NpmOverviewScreen,
        ),
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value.$1, reason: entry.key);
        // Naming the screen, not just the location: a placeholder resolves at
        // exactly the same location, so asserting the location alone is what
        // let three built Overviews sit in the tree reachable by nothing.
        expect(
          find.byType(entry.value.$2),
          findsOneWidget,
          reason: '${entry.value.$1} must draw ${entry.value.$2}',
        );
      }
    });

    testWidgets('every tab on the bar has a branch that resolves', (
      tester,
    ) async {
      // The bar is generated from `tabsFor`, so a tab without a branch is an
      // index that selects nothing. Walking all fourteen is what makes the
      // wildcard's `UnsupportedError` a promise rather than a comment.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final service in [
        ServiceKey.dockge,
        ServiceKey.unraid,
        ServiceKey.nginxProxyManager,
      ]) {
        for (final tab in tabsFor(service)!) {
          final location =
              '${ServiceRoutes.forService(service)}/${tab.segment}';
          router.go(location);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), location, reason: location);
        }
      }
    });

    testWidgets('a tab that draws something draws the half it names', (
      tester,
    ) async {
      // Two services split a page across a bar, and a split is only as good as
      // the wiring: `UnraidScreen.docker` mounted on the Array tab would draw a
      // plausible screen under the wrong label, which no path assertion would
      // notice.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(ServiceRoutes.unraidArray);
      await tester.pumpAndSettle();
      expect(
        tester.widget<UnraidScreen>(find.byType(UnraidScreen)).section,
        UnraidSection.array,
      );

      router.go(ServiceRoutes.unraidDocker);
      await tester.pumpAndSettle();
      expect(
        tester.widget<UnraidScreen>(find.byType(UnraidScreen)).section,
        UnraidSection.docker,
      );

      router.go(ServiceRoutes.npmProxyHosts);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NpmScreen>(find.byType(NpmScreen)).section,
        NpmSection.proxyHosts,
      );

      router.go(ServiceRoutes.npmCertificates);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NpmScreen>(find.byType(NpmScreen)).section,
        NpmSection.certificates,
      );

      // A host's advanced block is a page of its own under Proxy hosts: the
      // URL leaves the tab root, so the service header steps aside for the
      // page's app bar instead of being drawn under it.
      router.go(ServiceRoutes.npmAdvanced(4));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NpmAdvancedConfigScreen>(
              find.byType(NpmAdvancedConfigScreen),
            )
            .hostId,
        4,
      );
      expect(
        tester
            .widget<ServiceHomeScreen>(find.byType(ServiceHomeScreen))
            .showAppBar,
        isFalse,
      );

      router.go('${ServiceRoutes.npmProxyHosts}/not-a-number/advanced');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, ServiceRoutes.npmProxyHosts);

      // Dockge did not split: the stack list *was* the service, and it is the
      // Stacks tab whole.
      router.go(ServiceRoutes.dockgeStacks);
      await tester.pumpAndSettle();
      expect(find.byType(DockgeScreen), findsOneWidget);
    });

    testWidgets('the pre-tab Dockge spellings cross in ONE hop, query intact', (
      tester,
    ) async {
      // Three routes that hung off the service root when a one-page service had
      // nowhere else to hang them, and all three are still in the wild:
      // `ServiceRoutes.dockgeStack` built the first for every row of the list.
      // One hop, not two: each tail carries the deep link's own parameters
      // straight to the page inside the Stacks branch rather than bouncing
      // through the service root, which would land the user on Overview having
      // lost where they were going.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      // Nothing reads `from`. Dockge links carry no query in production. It is
      // here because the *mechanism* that would drop it is the same one that
      // drops `?i=`, and a lens pointed at a connection this harness does not
      // define would leave a provider retrying.
      router.go('${ServiceRoutes.dockge}/stack/immich?from=card');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.dockgeStack('immich')}?from=card',
      );
      expect(
        tester
            .widget<DockgeStackDetailScreen>(
              find.byType(DockgeStackDetailScreen),
            )
            .name,
        'immich',
      );

      router.go('${ServiceRoutes.dockge}/stack/immich/edit');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        ServiceRoutes.dockgeStackEdit('immich'),
      );
      expect(
        tester
            .widget<DockgeStackEditScreen>(find.byType(DockgeStackEditScreen))
            .name,
        'immich',
      );

      router.go('${ServiceRoutes.dockge}/new');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.dockgeNewStack);
      expect(
        tester
            .widget<DockgeStackEditScreen>(find.byType(DockgeStackEditScreen))
            .isNew,
        isTrue,
      );
    });

    testWidgets('a blank stack name falls back to the Stacks tab', (
      tester,
    ) async {
      // Not to the app home: the branch is where the user still is, and sending
      // them out of the service is a bigger move than the mistake. A Dockge
      // stack name is a Compose project directory: a free-form string with no
      // `safeIntParam` to run, so emptiness is the whole of what can be
      // checked.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('${ServiceRoutes.dockgeStackBase}/%20');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.dockgeStacks);
      expect(find.byType(DockgeStackDetailScreen), findsNothing);
    });

    testWidgets('the legacy /services prefix still reaches all three', (
      tester,
    ) async {
      // Two hops for a service root: the prefix rewrite lands on the
      // redirect-only node, which hands off to Overview, and three for the
      // Dockge stack, which crosses the pre-tab tail on the way into the
      // branch. What this asserts is that the chain finishes: a rewrite that
      // stopped at the first hop would leave the user on a path that draws
      // nothing.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final entry in {
        '/services/dockge': ServiceRoutes.dockgeOverview,
        '/services/unraid': ServiceRoutes.unraidOverview,
        '/services/npm': ServiceRoutes.npmOverview,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), entry.value, reason: entry.key);
      }

      router.go('/services/dockge/stack/immich');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.dockgeStack('immich'));
      expect(find.byType(DockgeStackDetailScreen), findsOneWidget);
    });
  });

  // ── What each tab actually draws ────────────────────────────────────────
  //
  // The tables above this one assert *locations*, and a location is not a
  // page: for months every tab on every bar resolved to a placeholder
  // (a legitimate destination), so the path assertions stayed green while the
  // screens behind them were unreachable. The Overview table was written to
  // close that for the sixteen Overviews. This one closes it for the other
  // seventy tabs.
  //
  // Two properties, and the second is the load-bearing one:
  //
  //  * every tab draws the widget the router names for it, **and** where one
  //    widget serves several tabs: `ArrTabScreen` is queue, wanted and
  //    history; `UnraidScreen` is five sections; `NpmScreen` is four: the
  //    entry asserts the *discriminator* too. A type-only check would pass
  //    with Queue mounted on History, which is a plausible page under the
  //    wrong label and the failure no path assertion can see.
  //  * the table is **complete by construction**. It is walked from
  //    `tabsFor`, not from its own keys, so a tab added to `serviceTabs`
  //    without an entry here fails rather than going unchecked. That is the
  //    same shape as the router's own wildcard `throw`, in the test.
  //
  // TrueNAS is absent because it has no bar at all: `tabsFor` returns null
  // for it by design, ten sections not fitting on one.
  //
  // No fake is needed: the harness leaves every service unconfigured and each
  // of these screens checks `isServiceConfigured` before it reaches a
  // provider, so nothing is requested and no retry timer outlives the case.
  group('every tab draws the screen it names', () {
    Finder drawsArrTab(ServiceType serviceType, ArrTabMode mode) =>
        find.byWidgetPredicate(
          (widget) =>
              widget is ArrTabScreen &&
              widget.serviceType == serviceType &&
              widget.mode == mode,
          description: 'ArrTabScreen(${serviceType.name}, ${mode.name})',
        );

    Finder drawsCalendar(ServiceKey service) => find.byWidgetPredicate(
      (widget) => widget is ArrCalendarScreen && widget.service == service,
      description: 'ArrCalendarScreen(${service.name})',
    );

    final expected = <ServiceKey, Map<ServiceTab, Finder>>{
      ServiceKey.seerr: {
        ServiceTab.overview: find.byType(SeerrOverviewScreen),
        ServiceTab.requests: find.byType(ServiceAllRequestsScreen),
        ServiceTab.issues: find.byType(SeerrIssuesScreen),
        ServiceTab.users: find.byType(SeerrUsersScreen),
      },
      ServiceKey.radarr: {
        ServiceTab.overview: find.byType(RadarrOverviewScreen),
        ServiceTab.library: find.byType(MoviesScreen),
        ServiceTab.calendar: drawsCalendar(ServiceKey.radarr),
        ServiceTab.queue: drawsArrTab(ServiceType.movies, ArrTabMode.queue),
        ServiceTab.wanted: drawsArrTab(ServiceType.movies, ArrTabMode.wanted),
        ServiceTab.history: drawsArrTab(ServiceType.movies, ArrTabMode.history),
      },
      ServiceKey.sonarr: {
        ServiceTab.overview: find.byType(SonarrOverviewScreen),
        ServiceTab.library: find.byType(SeriesScreen),
        ServiceTab.calendar: drawsCalendar(ServiceKey.sonarr),
        ServiceTab.queue: drawsArrTab(ServiceType.series, ArrTabMode.queue),
        ServiceTab.wanted: drawsArrTab(ServiceType.series, ArrTabMode.wanted),
        ServiceTab.history: drawsArrTab(ServiceType.series, ArrTabMode.history),
      },
      ServiceKey.lidarr: {
        ServiceTab.overview: find.byType(LidarrOverviewScreen),
        ServiceTab.library: find.byType(MusicScreen),
        ServiceTab.calendar: drawsCalendar(ServiceKey.lidarr),
        ServiceTab.queue: drawsArrTab(ServiceType.music, ArrTabMode.queue),
        ServiceTab.wanted: drawsArrTab(ServiceType.music, ArrTabMode.wanted),
        ServiceTab.history: drawsArrTab(ServiceType.music, ArrTabMode.history),
      },
      ServiceKey.readarr: {
        ServiceTab.overview: find.byType(ReadarrOverviewScreen),
        ServiceTab.library: find.byType(ReadarrLibraryScreen),
        ServiceTab.calendar: drawsCalendar(ServiceKey.readarr),
        ServiceTab.queue: find.byWidgetPredicate(
          (widget) =>
              widget is ReadarrActivityScreen &&
              widget.mode == ReadarrActivityMode.queue,
          description: 'ReadarrActivityScreen(queue)',
        ),
        ServiceTab.wanted: find.byWidgetPredicate(
          (widget) =>
              widget is ReadarrActivityScreen &&
              widget.mode == ReadarrActivityMode.wanted,
          description: 'ReadarrActivityScreen(wanted)',
        ),
        ServiceTab.history: find.byType(ReadarrHistoryScreen),
      },
      ServiceKey.qbittorrent: {
        ServiceTab.overview: find.byType(QbittorrentOverviewScreen),
        ServiceTab.queue: find.byType(QbittorrentScreen),
        ServiceTab.rss: find.byType(QbittorrentRssScreen),
      },
      ServiceKey.transmission: {
        ServiceTab.overview: find.byType(TransmissionOverviewScreen),
        ServiceTab.queue: find.byType(TransmissionScreen),
        ServiceTab.labels: find.byType(TransmissionLabelsScreen),
        ServiceTab.session: find.byType(TransmissionSessionScreen),
      },
      ServiceKey.sabnzbd: {
        ServiceTab.overview: find.byType(SabnzbdOverviewScreen),
        ServiceTab.queue: find.byType(SabnzbdScreen),
        ServiceTab.history: find.byType(SabnzbdHistoryScreen),
        ServiceTab.servers: find.byType(SabnzbdServersScreen),
      },
      ServiceKey.nzbget: {
        ServiceTab.overview: find.byType(NzbgetOverviewScreen),
        ServiceTab.queue: find.byType(NzbgetScreen),
        ServiceTab.history: find.byType(NzbgetHistoryScreen),
        ServiceTab.feeds: find.byType(NzbgetFeedsScreen),
        ServiceTab.messages: find.byType(NzbgetMessagesScreen),
      },
      ServiceKey.bazarr: {
        ServiceTab.overview: find.byType(BazarrOverviewScreen),
        ServiceTab.wanted: find.byType(BazarrWantedScreen),
        ServiceTab.series: find.byWidgetPredicate(
          (widget) =>
              widget is BazarrLibraryScreen &&
              widget.kind == BazarrLibraryKind.series,
          description: 'BazarrLibraryScreen(series)',
        ),
        ServiceTab.movies: find.byWidgetPredicate(
          (widget) =>
              widget is BazarrLibraryScreen &&
              widget.kind == BazarrLibraryKind.movies,
          description: 'BazarrLibraryScreen(movies)',
        ),
        ServiceTab.history: find.byType(BazarrHistoryScreen),
        ServiceTab.providers: find.byType(BazarrProvidersScreen),
      },
      ServiceKey.prowlarr: {
        ServiceTab.overview: find.byType(ProwlarrOverviewScreen),
        ServiceTab.indexers: find.byType(ProwlarrLibraryScreen),
        ServiceTab.history: find.byType(ProwlarrHistoryScreen),
        ServiceTab.stats: find.byType(ProwlarrStatsScreen),
      },
      ServiceKey.dockge: {
        ServiceTab.overview: find.byType(DockgeOverviewScreen),
        ServiceTab.stacks: find.byType(DockgeScreen),
        ServiceTab.terminal: find.byType(DockgeTerminalScreen),
      },
      ServiceKey.unraid: {
        ServiceTab.overview: find.byType(UnraidOverviewScreen),
        for (final entry in const {
          ServiceTab.array: UnraidSection.array,
          ServiceTab.docker: UnraidSection.docker,
          ServiceTab.vms: UnraidSection.vms,
          ServiceTab.notifications: UnraidSection.notifications,
          ServiceTab.shares: UnraidSection.shares,
        }.entries)
          entry.key: find.byWidgetPredicate(
            (widget) => widget is UnraidScreen && widget.section == entry.value,
            description: 'UnraidScreen(${entry.value.name})',
          ),
      },
      ServiceKey.nginxProxyManager: {
        ServiceTab.overview: find.byType(NpmOverviewScreen),
        for (final entry in const {
          ServiceTab.proxyHosts: NpmSection.proxyHosts,
          ServiceTab.certificates: NpmSection.certificates,
          ServiceTab.accessLists: NpmSection.accessLists,
          ServiceTab.auditLog: NpmSection.auditLog,
        }.entries)
          entry.key: find.byWidgetPredicate(
            (widget) => widget is NpmScreen && widget.section == entry.value,
            description: 'NpmScreen(${entry.value.name})',
          ),
      },
      ServiceKey.jellyfin: {
        ServiceTab.overview: find.byWidgetPredicate(
          (widget) =>
              widget is StreamOverviewScreen &&
              widget.service == ServiceKey.jellyfin,
          description: 'StreamOverviewScreen(jellyfin)',
        ),
        ServiceTab.libraries: find.byWidgetPredicate(
          (widget) =>
              widget is StreamLibrariesScreen &&
              widget.service == ServiceKey.jellyfin,
          description: 'StreamLibrariesScreen(jellyfin)',
        ),
        ServiceTab.users: find.byType(JellyfinUsersScreen),
        ServiceTab.devices: find.byType(JellyfinDevicesScreen),
        ServiceTab.tasks: find.byType(JellyfinTasksScreen),
        ServiceTab.activity: find.byType(JellyfinActivityScreen),
      },
      ServiceKey.emby: {
        ServiceTab.overview: find.byWidgetPredicate(
          (widget) =>
              widget is StreamOverviewScreen &&
              widget.service == ServiceKey.emby,
          description: 'StreamOverviewScreen(emby)',
        ),
        ServiceTab.libraries: find.byWidgetPredicate(
          (widget) =>
              widget is StreamLibrariesScreen &&
              widget.service == ServiceKey.emby,
          description: 'StreamLibrariesScreen(emby)',
        ),
        // Jellyfin's four screens, told which server they are on.
        for (final entry in {
          ServiceTab.users: JellyfinUsersScreen,
          ServiceTab.devices: JellyfinDevicesScreen,
          ServiceTab.tasks: JellyfinTasksScreen,
          ServiceTab.activity: JellyfinActivityScreen,
        }.entries)
          entry.key: find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType == entry.value &&
                _serviceOf(widget) == ServiceKey.emby,
            description: '${entry.value}(emby)',
          ),
      },
      ServiceKey.plex: {
        ServiceTab.overview: find.byWidgetPredicate(
          (widget) =>
              widget is StreamOverviewScreen &&
              widget.service == ServiceKey.plex,
          description: 'StreamOverviewScreen(plex)',
        ),
        ServiceTab.libraries: find.byWidgetPredicate(
          (widget) =>
              widget is StreamLibrariesScreen &&
              widget.service == ServiceKey.plex,
          description: 'StreamLibrariesScreen(plex)',
        ),
        ServiceTab.onDeck: find.byType(PlexOnDeckScreen),
        ServiceTab.activities: find.byType(PlexActivitiesScreen),
        ServiceTab.devices: find.byType(PlexDevicesScreen),
        ServiceTab.playlists: find.byType(PlexPlaylistsScreen),
      },
    };

    for (final service in ServiceKey.values) {
      final tabs = tabsFor(service);
      if (tabs == null) continue;

      testWidgets(service.name, (tester) async {
        final table = expected[service];
        expect(
          table,
          isNotNull,
          reason:
              '${service.name} is on the tab model but has no row in this '
              'table. Add one naming the widget each of its tabs draws.',
        );

        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        for (final tab in tabs) {
          final finder = table![tab];
          expect(
            finder,
            isNotNull,
            reason:
                '${service.name}/${tab.name} has a branch but no entry here, '
                'so nothing checks what it draws.',
          );

          final location =
              '${ServiceRoutes.forService(service)}/${tab.segment}';
          router.go(location);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), location, reason: location);
          expect(
            finder,
            findsOneWidget,
            reason: '$location must draw the screen its row names',
          );
        }
      });
    }

    group('the one page a title has', () {
      /// The title pages a user can see: a branch left keeps its stack, so
      /// the one just opened is the one that is hit-testable.
      Iterable<MediaPage> visiblePages(WidgetTester tester) =>
          tester.widgetList<MediaPage>(find.byType(MediaPage).hitTestable());

      testWidgets('draws under every tab that opens titles, and at the root', (
        tester,
      ) async {
        // Every tab of a service in `mediaMountServices`, because a title
        // opened anywhere in that service lands under the tab it was opened
        // from: a tab without the mount would be a push that matches nothing.
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);
        final froms = [
          for (final service in ServiceRoutes.mediaMountServices)
            for (final tab in tabsFor(service)!)
              '${ServiceRoutes.forService(service)}/${tab.segment}',
          ServiceRoutes.home,
          ServiceRoutes.stack,
          ServiceRoutes.activity,
          ServiceRoutes.discover,
          // Activity's other views: each is the Activity tab, so a title
          // opened from one hangs under it.
          for (final tab in ActivityTab.values)
            if (tab != ActivityTab.all) tab.location,
        ];
        for (final (index, from) in froms.indexed) {
          final key = MediaKey.movie(600 + index);
          final location = ServiceRoutes.media(
            key,
            from: from,
            focus: 'radarr-4k',
          );
          router.go(location);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), location, reason: from);
          expect(
            visiblePages(tester).map((page) => (page.mediaKey, page.focus)),
            [(key, 'radarr-4k')],
            reason: from,
          );
        }
      });

      testWidgets('reads every key, and a bad one goes back to the mount', (
        tester,
      ) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        for (final key in const [
          MediaKey.tv(1399),
          MediaKey.tvdb(300001),
          MediaKey.movie(653),
        ]) {
          router.go('${ServiceRoutes.sonarrLibrary}${key.location}');
          await tester.pumpAndSettle();
          expect(visiblePages(tester).map((page) => page.mediaKey), [
            key,
          ], reason: key.location);
        }

        for (final (location, mount) in [
          (
            '${ServiceRoutes.sonarrLibrary}/media/tv/tvdb/0',
            ServiceRoutes.sonarrLibrary,
          ),
          ('${ServiceRoutes.discover}/media/movie/x', ServiceRoutes.discover),
          ('/media/movie/-1', ServiceRoutes.home),
        ]) {
          router.go(location);
          await tester.pumpAndSettle();
          expect(router.state.uri.toString(), mount, reason: location);
        }
      });

      testWidgets('opened from a page above the tabs, it opens above it', (
        tester,
      ) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);
        // A title's own page at the root: it sits over the tabs.
        router.go(ServiceRoutes.media(const MediaKey.movie(1), from: '/'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/media/movie/1');

        unawaited(
          router.push(
            ServiceRoutes.media(
              const MediaKey.movie(653),
              from: router.state.uri.path,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(visiblePages(tester).map((page) => page.mediaKey), [
          const MediaKey.movie(653),
        ]);
      });

      testWidgets('the tile lends its poster, and the poster flies', (
        tester,
      ) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);
        const posterUrl = 'https://cdn.example.com/poster%20image.jpg';

        router.go(
          ServiceRoutes.media(
            const MediaKey.movie(653),
            from: ServiceRoutes.discover,
            heroTag: 'discover_trending_653',
            posterUrl: posterUrl,
          ),
        );
        await tester.pumpAndSettle();

        final page = visiblePages(tester).single;
        expect(page.heroTag, 'discover_trending_653');
        // Decoded once, by go_router: a `%20` in the URL itself survives.
        expect(page.posterUrl, posterUrl);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Hero && widget.tag == 'discover_trending_653',
          ),
          findsOneWidget,
        );
      });
    });
  });
}

/// The Welcome under a page opened over it, and a connection's own checks,
/// keep timers: the tree and the container go before the test ends.
Future<void> _letTheWelcomeGo(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
}

Future<ProviderContainer> _pumpRouter(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  bool onboardingCompleted = true,
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      initialOnboardingCompletedProvider.overrideWith(
        (ref) => onboardingCompleted,
      ),
      currentSettingsProvider.overrideWith((ref) => settings),
      seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
      radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
      sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
      lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
      // Prowlarr has no hand-written fake, and does not need one: every call
      // its screens make is a GET whose envelope is an array or an object that
      // degrades to `{}`, so one canned empty array answers all of them. What
      // it buys is a *quiet* teardown: an unconfigured `ProwlarrService`
      // throws, and Riverpod retries the throw on a timer that outlives the
      // widget tree. Prowlarr's Settings pages and its indexer detail are
      // reachable from this file's tables, and neither gates on configuration.
      prowlarrServiceProvider.overrideWith(
        (ref) => ProwlarrService(FakeApiClient()..getResponseData = const []),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Reduce Motion, because these cases are about *where* the router lands
      // and one of the destinations owns a continuous animation: the onboarding
      // ring sweeps forever by design, so with motion on `pumpAndSettle` waits
      // for a frame that never stops coming.
      child: MaterialApp.router(
        routerConfig: container.read(routerProvider),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return container;
}

/// The server one of Jellyfin's four tab screens is told it is on, or null for
/// any other widget.
ServiceKey? _serviceOf(Widget widget) => switch (widget) {
  JellyfinUsersScreen(:final service) ||
  JellyfinDevicesScreen(:final service) ||
  JellyfinTasksScreen(:final service) ||
  JellyfinActivityScreen(:final service) => service,
  _ => null,
};
