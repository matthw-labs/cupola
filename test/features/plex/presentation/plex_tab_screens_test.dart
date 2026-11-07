import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/plex/presentation/plex_tab_screens.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/stream_watching.dart';

final _configured = const SettingsModel(
  plexClientId: 'cupola-test',
).copyWithService(ServiceKey.plex, url: 'https://plex.test', apiKey: 'token');

void main() {
  testWidgets('all tabs stop before their providers when not configured', (
    tester,
  ) async {
    var reads = 0;
    final providerOverrides = <Override>[
      plexSessionsProvider.overrideWith((ref) async {
        reads++;
        return const [];
      }),
      plexDevicesProvider.overrideWith((ref) async {
        reads++;
        return const [];
      }),
      plexPlaylistsProvider.overrideWith((ref) async {
        reads++;
        return const [];
      }),
    ];

    for (final screen in const <Widget>[
      PlexActivitiesScreen(),
      PlexDevicesScreen(),
      PlexPlaylistsScreen(),
    ]) {
      await _pump(
        tester,
        screen: screen,
        settings: const SettingsModel(),
        overrides: providerOverrides,
      );
      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    expect(reads, 0);
  });

  testWidgets('activities draw on deck and what was added under Now '
      'playing, the on deck rows with how far in', (tester) async {
    await _pump(
      tester,
      screen: const PlexActivitiesScreen(),
      overrides: [
        plexSessionsProvider.overrideWith((ref) async => const []),
        streamWatchingProvider.overrideWith(
          (ref, key) async => switch (key.shelf) {
            StreamWatchingShelf.continueWatching => const [
              StreamItem(
                id: '42',
                title: 'Severance',
                subtitle: 'S02E05',
                kind: StreamItemKind.episode,
                posterPath: null,
                year: null,
                runtimeMs: 1000,
                isPlayed: false,
                resumeOffsetMs: 300,
                unplayedChildCount: null,
              ),
            ],
            _ => const [],
          },
        ),
      ],
    );

    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('On deck'), findsOneWidget);
    expect(find.text('Severance'), findsOneWidget);
    // Plex has no Next up of its own: its on deck is both halves.
    expect(find.text('Next up'), findsNothing);
    await tester.scrollUntilVisible(find.text('Recently added'), 200);
    expect(find.text('Nothing added lately'), findsOneWidget);
  });

  testWidgets('an answered empty on deck rests without a fake count', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const PlexActivitiesScreen(),
      overrides: [
        plexSessionsProvider.overrideWith((ref) async => const []),
        streamWatchingProvider.overrideWith((ref, key) async => const []),
      ],
    );

    expect(find.text('Nothing part-watched'), findsOneWidget);
    expect(find.textContaining('0'), findsNothing);
  });

  testWidgets('activities reuse the live-session idle state', (tester) async {
    await _pump(
      tester,
      screen: const PlexActivitiesScreen(),
      overrides: [
        plexSessionsProvider.overrideWith((ref) async => const []),
        streamWatchingProvider.overrideWith((ref, key) async => const []),
      ],
    );

    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Nobody is watching right now'), findsOneWidget);
  });

  testWidgets('devices expose product, platform and capabilities', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const PlexDevicesScreen(),
      overrides: [
        plexDevicesProvider.overrideWith(
          (ref) async => const [
            PlexDevice(
              id: 7,
              name: 'Living room TV',
              clientIdentifier: 'tv-id',
              product: 'Plex for Apple TV',
              platform: 'tvOS',
              provides: ['client', 'player'],
              createdAt: null,
              lastSeenAt: null,
            ),
          ],
        ),
      ],
    );

    expect(find.text('1 device'), findsOneWidget);
    expect(
      find.semantics.byLabel(
        'Living room TV, Plex for Apple TV, tvOS, client, player, Last seen unavailable',
      ),
      findsOneWidget,
    );
  });

  testWidgets('playlists never turn an absent item count into zero', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const PlexPlaylistsScreen(),
      overrides: [
        plexPlaylistsProvider.overrideWith(
          (ref) async => const [
            PlexPlaylist(
              ratingKey: '99',
              title: 'Evening mix',
              playlistType: 'audio',
              smart: true,
              itemCount: null,
              durationMs: null,
              addedAt: null,
              updatedAt: null,
            ),
          ],
        ),
      ],
    );

    expect(find.text('1 playlist'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(
      tester.getSemantics(find.text('Evening mix')).label,
      'Evening mix, Smart playlist, Items unavailable, audio, Updated unavailable',
    );
  });

  testWidgets('a provider failure exposes retryable error state', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const PlexDevicesScreen(),
      overrides: [
        plexDevicesProvider.overrideWith(
          (ref) => Future.error(Exception('devices unavailable')),
        ),
      ],
    );

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('long playlist data survives accessibility text size', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const PlexPlaylistsScreen(),
      textScaleFactor: 3,
      theme: AppTheme.lightTheme(),
      overrides: [
        plexPlaylistsProvider.overrideWith(
          (ref) async => const [
            PlexPlaylist(
              ratingKey: 'long',
              title: 'A Very Long Smart Playlist Name For The Whole Household',
              playlistType: 'an unusually verbose mixed media type',
              smart: true,
              itemCount: 123456,
              durationMs: 987654321,
              addedAt: null,
              updatedAt: null,
            ),
          ],
        ),
      ],
    );

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  SettingsModel? settings,
  List<Override> overrides = const [],
  double textScaleFactor = 1,
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings ?? _configured),
        ...overrides,
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
