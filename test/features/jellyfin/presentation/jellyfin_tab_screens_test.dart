import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/data/media_browser_client.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/stream_watching.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart' show weekdayName;
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final _configured = const SettingsModel().copyWithService(
  ServiceKey.jellyfin,
  url: 'https://jellyfin.test',
  apiKey: 'key',
);

void main() {
  testWidgets('all tabs stop before their providers when not configured', (
    tester,
  ) async {
    var reads = 0;
    final providerOverrides = <Override>[
      jellyfinUsersProvider.overrideWith((ref) async {
        reads++;
        return const [];
      }),
      jellyfinDevicesProvider.overrideWith((ref) async {
        reads++;
        return const [];
      }),
      jellyfinTasksProvider.overrideWith((ref) async {
        reads++;
        return const [];
      }),
      jellyfinSessionsProvider.overrideWith((ref) async {
        reads++;
        return const [];
      }),
    ];

    for (final screen in const <Widget>[
      JellyfinUsersScreen(),
      JellyfinDevicesScreen(),
      JellyfinTasksScreen(),
      JellyfinActivityScreen(),
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

  testWidgets('users preserve roles, disabled state and missing activity', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const JellyfinUsersScreen(),
      overrides: [
        jellyfinUsersProvider.overrideWith(
          (ref) async => const [
            JellyfinUserDto(
              id: 'admin',
              name: 'nadia',
              isAdministrator: true,
              isDisabled: false,
              lastActivityAt: null,
            ),
            JellyfinUserDto(
              id: 'guest',
              name: 'guest',
              isAdministrator: false,
              isDisabled: true,
              lastActivityAt: null,
            ),
          ],
        ),
      ],
    );

    expect(find.text('2 users\u00A0· 1 disabled'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('Last activity unavailable'), findsNWidgets(2));
    expect(
      find.semantics.byLabel('guest, Disabled, Last activity unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('a user\'s last activity is said by its day', (tester) async {
    final at = DateTime.now().subtract(const Duration(days: 3));
    await _pump(
      tester,
      screen: const JellyfinUsersScreen(),
      overrides: [
        jellyfinUsersProvider.overrideWith(
          (ref) async => [
            JellyfinUserDto(
              id: 'u',
              name: 'nadia',
              isAdministrator: false,
              isDisabled: false,
              lastActivityAt: at,
            ),
          ],
        ),
      ],
    );

    expect(find.text('Last active ${weekdayName(at)}'), findsOneWidget);
  });

  testWidgets('devices speak one complete inventory sentence', (tester) async {
    await _pump(
      tester,
      screen: const JellyfinDevicesScreen(),
      overrides: [
        jellyfinDevicesProvider.overrideWith(
          (ref) async => const [
            JellyfinDevice(
              id: 'tv',
              name: 'Apple TV 4K',
              appName: 'Jellyfin for tvOS',
              appVersion: '1.4',
              lastUserName: 'nadia',
              lastActivityAt: null,
            ),
          ],
        ),
      ],
    );

    expect(find.text('1 device'), findsOneWidget);
    expect(
      find.semantics.byLabel(
        'Apple TV 4K, nadia, Jellyfin for tvOS 1.4, Last seen unavailable',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tasks use blue for running and amber for a failed last run', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const JellyfinTasksScreen(),
      overrides: [
        jellyfinTasksProvider.overrideWith(
          (ref) async => const [
            JellyfinScheduledTask(
              id: 'scan',
              name: 'Extract chapter images',
              state: 'Running',
              progress: 38,
              lastStatus: '',
              lastStartedAt: null,
              lastEndedAt: null,
              errorMessage: '',
            ),
            JellyfinScheduledTask(
              id: 'people',
              name: 'Refresh people',
              state: 'Idle',
              progress: null,
              lastStatus: 'Failed',
              lastStartedAt: null,
              lastEndedAt: null,
              errorMessage: 'timeout after 30 min',
            ),
          ],
        ),
      ],
    );

    expect(find.text('2 scheduled\u00A0· 1 running'), findsOneWidget);
    expect(find.text('Running\u00A0· 38%'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.textContaining('timeout after 30 min'), findsOneWidget);
    expect(find.text('0 s'), findsNothing);

    final failedText = tester.widget<Text>(find.text('Failed'));
    final context = tester.element(find.text('Failed'));
    expect(
      failedText.style?.color,
      statusToneColor(Theme.of(context).colorScheme, StatusTone.warning),
    );
  });

  testWidgets('activity reuses the live-session idle state', (tester) async {
    await _pump(
      tester,
      screen: const JellyfinActivityScreen(),
      overrides: [
        jellyfinSessionsProvider.overrideWith((ref) async => const []),
        streamWatchingProvider.overrideWith((ref, key) async => const []),
      ],
    );

    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Nobody is watching right now'), findsOneWidget);
  });

  testWidgets('activity draws what is in progress, up next and added under '
      'Now playing, and asks whose watch state when nobody is chosen', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const JellyfinActivityScreen(),
      overrides: [
        jellyfinSessionsProvider.overrideWith((ref) async => const []),
        streamWatchingProvider.overrideWith(
          (ref, key) async => switch (key.shelf) {
            StreamWatchingShelf.recentlyAdded => const [
              StreamItem(
                id: 'jf-1',
                title: 'Sintel',
                subtitle: null,
                kind: StreamItemKind.movie,
                posterPath: null,
                year: 2010,
                runtimeMs: 888000,
                isPlayed: false,
                resumeOffsetMs: null,
                unplayedChildCount: null,
              ),
            ],
            _ => throw const JellyfinViewerRequired(),
          },
        ),
      ],
    );

    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Next up'), findsOneWidget);
    // A watch state with nobody to read it for is a question, not a fault.
    expect(find.text('Choose whose watch state to show'), findsNWidgets(2));
    expect(find.byType(InlineErrorRetry), findsNothing);
    // The page's own list, not the grid inside it.
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Recently added'),
      200,
      scrollable: page,
    );
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Sintel'),
      200,
      scrollable: page,
    );
    expect(find.bySemanticsLabel('Sintel'), findsOneWidget);
  });

  testWidgets('a provider failure exposes retryable error state', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const JellyfinUsersScreen(),
      overrides: [
        jellyfinUsersProvider.overrideWith(
          (ref) => Future.error(Exception('users unavailable')),
        ),
      ],
    );

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('long device fields survive accessibility text size', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const JellyfinDevicesScreen(),
      textScaleFactor: 3,
      theme: AppTheme.lightTheme(),
      overrides: [
        jellyfinDevicesProvider.overrideWith(
          (ref) async => const [
            JellyfinDevice(
              id: 'long',
              name: 'Living Room Television With A Very Long Custom Name',
              appName: 'Jellyfin for an unusually verbose television client',
              appVersion: '2026.9.18-build-extended',
              lastUserName: 'A household member with a long display name',
              lastActivityAt: null,
            ),
          ],
        ),
      ],
    );

    expect(tester.takeException(), isNull);
  });
  group('a household member\'s token', () {
    final member = jellyfinCredentialKindProvider.overrideWith(
      (ref) async => JellyfinCredentialKind.user,
    );

    for (final (screen, what) in const [
      (JellyfinDevicesScreen(), 'devices'),
      (JellyfinTasksScreen(), 'scheduled tasks'),
    ]) {
      testWidgets('$what: a calm administrator placeholder, not an error', (
        tester,
      ) async {
        await _pump(
          tester,
          screen: screen,
          overrides: [
            member,
            // Refused, as the server refuses a non-administrator. The
            // refusal never reaches the screen.
            jellyfinDevicesProvider.overrideWith(
              (ref) async => throw Exception('403'),
            ),
            jellyfinTasksProvider.overrideWith(
              (ref) async => throw Exception('403'),
            ),
          ],
        );
        expect(find.text('Needs a Jellyfin administrator'), findsOneWidget);
        expect(find.textContaining('list $what'), findsOneWidget);
        expect(find.byType(AppErrorState), findsNothing);
        expect(find.text('Update the key'), findsOneWidget);
      });
    }

    testWidgets('Now playing says it shows only this account', (tester) async {
      await _pump(
        tester,
        screen: const JellyfinActivityScreen(),
        overrides: [
          member,
          jellyfinSessionsProvider.overrideWith((ref) async => const []),
          streamWatchingProvider.overrideWith((ref, key) async => const []),
        ],
      );
      expect(
        find.text('Showing only this account\'s playback'),
        findsOneWidget,
      );
    });

    testWidgets('an API key sees the lists and no note', (tester) async {
      await _pump(
        tester,
        screen: const JellyfinDevicesScreen(),
        overrides: [
          jellyfinCredentialKindProvider.overrideWith(
            (ref) async => JellyfinCredentialKind.apiKey,
          ),
          jellyfinDevicesProvider.overrideWith((ref) async => const []),
        ],
      );
      expect(find.text('Needs a Jellyfin administrator'), findsNothing);
    });
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
