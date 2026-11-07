import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/plex/presentation/plex_tab_screens.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';

import '../../test_helpers/settings_scope.dart';

/// A media server that refuses every connection, through the real clients:
/// so what is under test is the whole path from the socket to the pixels.
class _Refused implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: 'Connection refused',
  );
}

JellyfinClient _darkJellyfin() {
  final client = JellyfinClient(baseUrl: 'https://jf.lan', apiKey: 'key');
  client.dio.httpClientAdapter = _Refused();
  return client;
}

PlexClient _darkPlex() {
  final client = PlexClient(
    url: 'https://plex.lan:32400',
    token: 'token',
    clientIdentifier: 'test',
    platform: 'macOS',
  );
  client.api.dio.httpClientAdapter = _Refused();
  return client;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ServiceKey> configured,
  required List<Override> overrides,
  required Widget home,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices(configured),
        ),
        serviceSummaryProvider.overrideWith(
          (ref, service) async => ServiceSummary(
            service: service,
            status: ServiceSummaryStatus.offline,
            host: 'media.lan',
            version: null,
          ),
        ),
        serviceKpiProvider.overrideWith(
          (ref, service) async => const <ServiceKpi>[],
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the board reads fail rather than reading as an idle server', () {
    test('Jellyfin: sessions and libraries, at once', () async {
      final container = ProviderContainer(
        overrides: [
          jellyfinClientProvider.overrideWith((_) => _darkJellyfin()),
        ],
      );
      addTearDown(container.dispose);

      for (final future in [
        container.read(jellyfinSessionsProvider.future),
        container.read(jellyfinLibrariesProvider.future),
      ]) {
        await expectLater(
          future.timeout(const Duration(milliseconds: 300)),
          throwsA(isA<DioException>()),
        );
      }
    });

    test('Plex: sessions and libraries, at once', () async {
      final container = ProviderContainer(
        overrides: [plexClientProvider.overrideWith((_) => _darkPlex())],
      );
      addTearDown(container.dispose);

      for (final future in [
        container.read(plexSessionsProvider.future),
        container.read(plexLibrariesProvider.future),
      ]) {
        await expectLater(
          future.timeout(const Duration(milliseconds: 300)),
          throwsA(isA<PlexException>()),
        );
      }
    });
  });

  group('the Streaming reads, every connection dark or some', () {
    test('every configured server dark is a failure, not "nobody"', () async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWithServices(const [
              ServiceKey.jellyfin,
              ServiceKey.plex,
            ]),
          ),
          jellyfinClientProvider.overrideWith((_) => _darkJellyfin()),
          plexClientProvider.overrideWith((_) => _darkPlex()),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(streamActivityProvider.future)
            .timeout(const Duration(milliseconds: 300)),
        throwsA(anything),
      );
      expect(
        (await container.read(
          streamActivityOfflineProvider.future,
        )).map((source) => source.service),
        [ServiceKey.jellyfin, ServiceKey.plex],
      );
    });

    test(
      'one dark server still shows the other one\'s answer, and is named',
      () async {
        final container = ProviderContainer(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => settingsWithServices(const [
                ServiceKey.jellyfin,
                ServiceKey.plex,
              ]),
            ),
            jellyfinClientProvider.overrideWith((_) => _darkJellyfin()),
            plexSessionsProvider.overrideWith(
              (ref) async => const <StreamSession>[],
            ),
          ],
        );
        addTearDown(container.dispose);

        // Partial, and honest: Plex answered "nobody", Jellyfin is named dark.
        expect(await container.read(streamActivityProvider.future), isEmpty);
        expect(
          (await container.read(
            streamActivityOfflineProvider.future,
          )).map((source) => source.service),
          [ServiceKey.jellyfin],
        );
      },
    );
  });

  /// No exception class and no library message may reach the screen.
  void expectPlainWords() {
    for (final leak in const [
      'Exception',
      'DioException',
      'PlexException',
      'cannot be solved by the library',
    ]) {
      expect(find.textContaining(leak), findsNothing, reason: leak);
    }
  }

  testWidgets('a dark Jellyfin Overview shows one offline state, in plain '
      'words, never "Nobody is watching"', (tester) async {
    await _pump(
      tester,
      configured: const [ServiceKey.jellyfin],
      overrides: [jellyfinClientProvider.overrideWith((_) => _darkJellyfin())],
      home: const StreamOverviewScreen(
        service: ServiceKey.jellyfin,
        topPadding: 0,
      ),
    );

    expect(find.text(streamIdleMessage), findsNothing);
    expect(find.text('The server did not answer'), findsNothing);
    // One state for the server, not one error well per region.
    expect(find.byType(ServiceOfflineState), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(find.text('Jellyfin did not answer'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expectPlainWords();
  });

  testWidgets('a dark Plex Activities tab is the offline state, never "Nothing '
      'part-watched"', (tester) async {
    await _pump(
      tester,
      configured: const [ServiceKey.plex],
      overrides: [plexClientProvider.overrideWith((_) => _darkPlex())],
      home: const PlexActivitiesScreen(),
    );

    expect(find.text('Nothing part-watched'), findsNothing);
    expect(find.byType(ServiceOfflineState), findsOneWidget);
    expect(find.text('Plex did not answer'), findsOneWidget);
    expectPlainWords();
  });

  testWidgets('a dark Plex Overview collapses its three regions into one '
      'state', (tester) async {
    await _pump(
      tester,
      configured: const [ServiceKey.plex],
      overrides: [plexClientProvider.overrideWith((_) => _darkPlex())],
      home: const StreamOverviewScreen(service: ServiceKey.plex, topPadding: 0),
    );

    expect(find.text('Nothing part-watched'), findsNothing);
    expect(find.text(streamIdleMessage), findsNothing);
    expect(find.byType(ServiceOfflineState), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expectPlainWords();
  });
}
