/// A media server page opened on one connection reads that connection.
///
/// Home's Now playing and Continue watching used to bring the row's
/// connection under the lens before opening its page, which moved every other
/// Jellyfin and Plex surface onto it. The connection now rides the route as
/// `?i=`, and these cases assert what the screens actually read: the requests
/// that reach each server, and where the lens still rests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/widgets/continue_watching_module.dart';
import 'package:cupola/features/home/presentation/widgets/now_playing_module.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/stream_item_screen.dart';

import '../../test_helpers/profiles/profiles.dart';

const _episode = StreamItem(
  id: 'jf-episode-7',
  title: 'The Second Cycle',
  subtitle: 'Cosmos Laundromat, S2 E3',
  kind: StreamItemKind.episode,
  posterPath: null,
  year: null,
  runtimeMs: 1500000,
  isPlayed: false,
  resumeOffsetMs: 1200000,
  unplayedChildCount: null,
  seasonNumber: 2,
  episodeNumber: 3,
);

/// Two Jellyfins, the lens on the first: the household's, with the cabin's
/// beside it.
final _twoJellyfin = Profiles.p1.withConnection(WorldConnections.jellyfinCabin);

String _lensOf(ProviderContainer container) =>
    container.read(activeInstanceProvider(ServiceKey.jellyfin))!.id;

bool _isItemRead(NetworkRequest r) => r.uri.path.contains('jf-episode-7');

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester,
  ProfileHarness harness,
  Widget child,
) async {
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  await harness.settle(tester);
  return ProviderScope.containerOf(tester.element(find.byWidget(child)));
}

void main() {
  test('the connection a link names is kept only if it is the service\'s', () {
    final settings = _twoJellyfin.settings;
    expect(
      streamInstanceFor(settings, ServiceKey.jellyfin, WorldIds.jellyfinCabin),
      WorldIds.jellyfinCabin,
    );
    // Another service's connection, a stale one, a blank one and none.
    expect(
      streamInstanceFor(settings, ServiceKey.plex, WorldIds.jellyfinCabin),
      '',
    );
    expect(streamInstanceFor(settings, ServiceKey.jellyfin, 'gone'), '');
    expect(streamInstanceFor(settings, ServiceKey.jellyfin, ' '), '');
    expect(streamInstanceFor(settings, ServiceKey.jellyfin, null), '');
  });

  testWidgets('an item opened with ?i= is read from that connection', (
    tester,
  ) async {
    final harness = await ProfileHarness.start(_twoJellyfin);
    final container = await _pumpScreen(
      tester,
      harness,
      const StreamItemScreen(
        service: ServiceKey.jellyfin,
        itemId: 'jf-episode-7',
        instanceId: WorldIds.jellyfinCabin,
      ),
    );

    expect(
      harness.network.requestsTo(WorldIds.jellyfinCabin).where(_isItemRead),
      isNotEmpty,
    );
    expect(
      harness.network.requestsTo(WorldIds.jellyfin).where(_isItemRead),
      isEmpty,
    );
    expect(_lensOf(container), WorldIds.jellyfin);

    await harness.unmount(tester);
  });

  testWidgets('an item with no ?i= is read from the active connection', (
    tester,
  ) async {
    final harness = await ProfileHarness.start(_twoJellyfin);
    await _pumpScreen(
      tester,
      harness,
      const StreamItemScreen(
        service: ServiceKey.jellyfin,
        itemId: 'jf-episode-7',
      ),
    );

    expect(
      harness.network.requestsTo(WorldIds.jellyfin).where(_isItemRead),
      isNotEmpty,
    );
    expect(
      harness.network.requestsTo(WorldIds.jellyfinCabin).where(_isItemRead),
      isEmpty,
    );

    await harness.unmount(tester);
  });

  testWidgets('a ?i= that names no Jellyfin falls back to the active one', (
    tester,
  ) async {
    final harness = await ProfileHarness.start(_twoJellyfin);
    await _pumpScreen(
      tester,
      harness,
      const StreamItemScreen(
        service: ServiceKey.jellyfin,
        itemId: 'jf-episode-7',
        instanceId: 'removed-since',
      ),
    );

    expect(
      harness.network.requestsTo(WorldIds.jellyfin).where(_isItemRead),
      isNotEmpty,
    );

    await harness.unmount(tester);
  });

  testWidgets('the Activity tab opened with ?i= reads that connection\'s '
      'playbacks and stops there', (tester) async {
    final harness = await ProfileHarness.start(_twoJellyfin);
    final container = await _pumpScreen(
      tester,
      harness,
      const JellyfinActivityScreen(instanceId: WorldIds.jellyfinCabin),
    );

    bool sessions(NetworkRequest r) => r.uri.path.endsWith('/Sessions');
    expect(
      harness.network.requestsTo(WorldIds.jellyfinCabin).where(sessions),
      isNotEmpty,
    );
    expect(
      harness.network.requestsTo(WorldIds.jellyfin).where(sessions),
      isEmpty,
    );

    await tester.tap(find.byTooltip('Stop this playback').first);
    await harness.settle(tester);
    await tester.tap(find.text('Stop playback'));
    await harness.settle(tester);

    bool stops(NetworkRequest r) =>
        r.method == 'POST' && r.uri.path.endsWith('/Playing/Stop');
    expect(
      harness.network.requestsTo(WorldIds.jellyfinCabin).where(stops),
      hasLength(1),
    );
    expect(harness.network.requestsTo(WorldIds.jellyfin).where(stops), isEmpty);
    expect(_lensOf(container), WorldIds.jellyfin);

    await harness.unmount(tester);
  });

  group('Home opens a row on its own connection', () {
    /// Pumps [child] under a router that records where it was sent.
    Future<({ProviderContainer container, List<String> visited})> pumpHome(
      WidgetTester tester,
      ProfileHarness harness,
      Widget child, {
      List<Override> overrides = const [],
    }) async {
      final visited = <String>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(body: child),
          ),
          GoRoute(
            path: '/:rest(.*)',
            builder: (context, state) {
              visited.add(state.uri.toString());
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      harness.network.followFakeTime(tester.binding);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...harness.overrides, ...overrides],
          child: MaterialApp.router(
            theme: AppTheme.darkTheme(),
            routerConfig: router,
          ),
        ),
      );
      await harness.settle(tester);
      return (
        container: ProviderScope.containerOf(
          tester.element(find.byType(Scaffold)),
        ),
        visited: visited,
      );
    }

    testWidgets('Continue watching: a row from the cabin opens its item '
        'with ?i= and leaves the lens where it was', (tester) async {
      final harness = await ProfileHarness.start(_twoJellyfin);
      final home = await pumpHome(
        tester,
        harness,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openResume(context, (
              service: ServiceKey.jellyfin,
              instanceId: WorldIds.jellyfinCabin,
              connectionName: 'Jellyfin Cabin',
              item: _episode,
            )),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await harness.settle(tester);

      expect(home.visited, [
        '/stack/jellyfin/libraries/item/jf-episode-7?i=${WorldIds.jellyfinCabin}',
      ]);
      expect(_lensOf(home.container), WorldIds.jellyfin);

      await harness.unmount(tester);
    });

    testWidgets('Now playing: a row from the cabin opens that connection\'s '
        'playbacks and leaves the lens where it was', (tester) async {
      final harness = await ProfileHarness.start(_twoJellyfin);
      final row = StreamActivityRow(
        service: ServiceKey.jellyfin,
        instanceId: WorldIds.jellyfinCabin,
        connectionName: 'Jellyfin Cabin',
        session: const StreamSession(
          id: 's-1',
          userName: 'Anna',
          title: 'Sintel',
          subtitle: null,
          deviceLabel: 'Living room TV',
          posterPath: null,
          playMethod: StreamPlayMethod.directPlay,
          transcodeReasons: [],
          bitrate: null,
          bitrateIsNominal: true,
          progress: 0.4,
          isPaused: false,
          remaining: Duration(minutes: 9),
        ),
      );
      final home = await pumpHome(
        tester,
        harness,
        const HomeNowPlayingModule(),
        overrides: [
          streamActivityProvider.overrideWith((ref) async => [row]),
          streamActivityOfflineProvider.overrideWith((ref) async => const []),
        ],
      );

      await tester.tap(find.textContaining('Sintel'));
      await harness.settle(tester);

      expect(home.visited, [
        '/stack/jellyfin/activity?i=${WorldIds.jellyfinCabin}',
      ]);
      expect(_lensOf(home.container), WorldIds.jellyfin);

      await harness.unmount(tester);
    });
  });
}
