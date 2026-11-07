/// The way from a person in a media server to their page in Tracearr: a row of
/// the Jellyfin and Emby Users tabs, and a Plex session (Plex has no Users tab
/// to hold the door), each only where Tracearr is set up and knows the person.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/demo/world/fakes/media_fakes.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/plex/presentation/plex_tab_screens.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_person_provider.dart';

import '../../test_helpers/profiles/profiles.dart';

final _withTracearr = Profiles.p1
    .withConnection(WorldConnections.plex)
    .withConnection(WorldConnections.emby)
    .withConnection(WorldConnections.tracearr);

Future<({ProfileHarness harness, List<String> visited})> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget screen,
) async {
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  final visited = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: screen),
      ),
      GoRoute(
        path: '/:rest(.*)',
        builder: (context, state) {
          visited.add(state.uri.path);
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(const Size(430, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: harness.overrides,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await harness.settle(tester);
  return (harness: harness, visited: visited);
}

void main() {
  group('a Users row', () {
    for (final (service, name) in [
      (ServiceKey.jellyfin, 'Jellyfin'),
      (ServiceKey.emby, 'Emby'),
    ]) {
      testWidgets('on $name leads to the person in Tracearr, for the people '
          'Tracearr has an account of', (tester) async {
        final (:harness, :visited) = await _pump(
          tester,
          _withTracearr,
          JellyfinUsersScreen(service: service),
        );

        // Anna and Luca are Tracearr's people; the operator has no account
        // there, so no door.
        expect(find.text('In Tracearr'), findsNWidgets(2));

        await tester.tap(find.text(WorldPeople.anna));
        await harness.settle(tester);
        expect(visited, ['/stack/tracearr/users/${TracearrFake.annaId}']);
        await harness.unmount(tester);
      });
    }

    testWidgets('without Tracearr has no door and no mark', (tester) async {
      final (:harness, :visited) = await _pump(
        tester,
        Profiles.p1,
        const JellyfinUsersScreen(),
      );

      expect(find.text(WorldPeople.anna), findsWidgets);
      expect(find.text('In Tracearr'), findsNothing);
      await harness.unmount(tester);
    });
  });

  group('a Plex session', () {
    testWidgets('leads to the person in Tracearr from its card', (
      tester,
    ) async {
      final (:harness, :visited) = await _pump(
        tester,
        _withTracearr,
        const PlexActivitiesScreen(),
      );

      expect(find.textContaining('Elephants Dream'), findsWidgets);
      final door = find.byTooltip('Open this person in Tracearr');
      expect(door, findsOneWidget);

      await tester.tap(door);
      await harness.settle(tester);
      expect(visited, ['/stack/tracearr/users/${TracearrFake.lucaId}']);
      await harness.unmount(tester);
    });

    testWidgets('has no door without Tracearr', (tester) async {
      final (:harness, :visited) = await _pump(
        tester,
        Profiles.p1.withConnection(WorldConnections.plex),
        const PlexActivitiesScreen(),
      );

      expect(find.textContaining('Elephants Dream'), findsWidgets);
      expect(find.byTooltip('Open this person in Tracearr'), findsNothing);
      await harness.unmount(tester);
    });
  });

  group('who a session is', () {
    Future<String?> personOf({String? userId, String name = 'luca'}) async {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          tracearrPeopleProvider.overrideWith(
            (ref) async => const [
              TracearrUser(
                id: 'person-luca',
                username: 'luca',
                accounts: [
                  TracearrAccount(
                    serverId: 'srv',
                    serverType: TracearrServerType.plex,
                    externalUserId: '2',
                    username: 'luca',
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        tracearrPersonOfSessionProvider((
          service: ServiceKey.plex,
          userId: userId,
          name: name,
        )),
        (_, _) {},
      );
      addTearDown(sub.close);
      return container.read(
        tracearrPersonOfSessionProvider((
          service: ServiceKey.plex,
          userId: userId,
          name: name,
        )).future,
      );
    }

    test('is the person whose account has their id on that server', () async {
      expect(await personOf(userId: '2', name: 'whoever'), 'person-luca');
    });

    test('is found by name only when the session carries no id', () async {
      expect(await personOf(userId: null), 'person-luca');
      expect(await personOf(userId: ' '), 'person-luca');
    });

    test('is nobody when the id is one Tracearr has no account of, '
        'however well the name matches somebody', () async {
      expect(await personOf(userId: '99'), isNull);
    });
  });

  group('who an account is', () {
    test('only a media server\'s kind has a word in Tracearr', () {
      expect(tracearrServerTypeOf(ServiceKey.plex)?.name, 'plex');
      expect(tracearrServerTypeOf(ServiceKey.jellyfin)?.name, 'jellyfin');
      expect(tracearrServerTypeOf(ServiceKey.emby)?.name, 'emby');
      expect(tracearrServerTypeOf(ServiceKey.radarr), isNull);
    });
  });
}
