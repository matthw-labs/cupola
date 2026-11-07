import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_overview_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/media/presentation/arr_public_poster.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_bazarr_service.dart';
import '../../../test_helpers/reel_finders.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('draws the regions in the order the board draws them', (
    tester,
  ) async {
    await _pump(tester, service: FakeBazarrService());

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // The work first, then history. Providers is absent, not stubbed: the
    // client has no `GET /api/providers`.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Wanted subtitles', 'History'],
    );
    // A readout may be labelled Providers; no section is.
    expect(find.widgetWithText(SectionHeader, 'Providers'), findsNothing);
  });

  testWidgets('the readouts are Bazarr\'s backlog and its providers', (
    tester,
  ) async {
    // Moved off the retired `BazarrScreen`, which was the only place asserting
    // that the rail's first figure is a *sum*: Wanted is episodes + movies, and
    // a rail that printed the episode count under a "Wanted" label would look
    // perfectly plausible. Read off the widget rather than off the paint,
    // because the section header below prints the same total and `16` alone
    // cannot say which of the two drew it.
    await _pump(
      tester,
      service: FakeBazarrService()
        ..badges = _badges(episodes: 12, movies: 4)
        // Providers is the enabled list, not the badge (the throttled ones).
        ..providerStatuses = [
          for (final name in const ['a', 'b', 'c', 'd', 'e'])
            BazarrProviderStatus(name: name, status: 'Good'),
        ],
    );

    final peek = tester.widget<ServiceKpiPeek>(find.byType(ServiceKpiPeek));
    expect(
      {for (final kpi in peek.kpis.requireValue) kpi.label: kpi.value},
      {'Wanted': '16', 'Episodes': '12', 'Movies': '4', 'Providers': '5'},
    );
    // And the rail really painted them: `12` appears nowhere else on the page.
    expect(findLine('12'), findsOneWidget);
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester, service: FakeBazarrService());

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      ['opens the Bazarr Wanted tab', 'opens the Bazarr History tab'],
    );
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester, service: FakeBazarrService(), version: '1.5.1');

    expect(
      find.semantics.byLabel('Bazarr, bazarr.local, v1.5.1, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets(
    'an unreachable Bazarr reads Did not answer, and its version is —',
    (tester) async {
      await _pump(tester, service: FakeBazarrService(), version: null);

      expect(
        find.semantics.byLabel('Bazarr, bazarr.local, —, Did not answer'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a wanted row is spoken as a sentence, and reads as backlog', (
    tester,
  ) async {
    final service = FakeBazarrService()
      ..badges = _badges(episodes: 40, movies: 7)
      ..wantedEpisodesResult = const BazarrPagedResult(
        data: [
          BazarrWantedItem(
            seriesTitle: 'Severance',
            episodeNumber: 'S02E04',
            sonarrSeriesId: 3,
            missingLanguages: [BazarrSubtitleLanguage(name: 'Italian')],
          ),
        ],
        total: 1,
      );

    await _pump(tester, service: service);

    expect(
      find.semantics.byLabel('Severance, S2\u00A0E4, Italian, Sonarr'),
      findsOneWidget,
    );
    // The slab's title carries no count: the room's figure above is the same
    // badge, and a second copy under the title said nothing new.
    expect(
      find.widgetWithText(ServiceOverviewSection, 'Wanted subtitles'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ServiceOverviewSection, 'Wanted subtitles'),
        matching: find.text('47'),
      ),
      findsNothing,
    );
  });

  testWidgets('a wanted row wears its title\'s public poster, and the slab '
      'is lit by the first one', (tester) async {
    const poster = 'https://artworks.thetvdb.com/severance.jpg';
    final lit = <String>[];
    final service = FakeBazarrService()
      ..badges = _badges(episodes: 2, movies: 0)
      ..wantedEpisodesResult = const BazarrPagedResult(
        data: [
          BazarrWantedItem(
            seriesTitle: 'Severance',
            episodeNumber: 'S02E04',
            sonarrSeriesId: 3,
            missingLanguages: [BazarrSubtitleLanguage(name: 'Italian')],
          ),
          BazarrWantedItem(
            seriesTitle: 'Night Shift',
            episodeNumber: 'S01E01',
            sonarrSeriesId: 9,
            missingLanguages: [BazarrSubtitleLanguage(name: 'German')],
          ),
        ],
        total: 2,
      );

    await _pump(
      tester,
      service: service,
      settle: false,
      overrides: [
        arrPublicPosterByIdProvider.overrideWith(
          (ref, title) async => title.id == 3 ? poster : null,
        ),
        titleLightProvider.overrideWith((ref, url) async {
          lit.add(url);
          return null;
        }),
      ],
    );

    final art = tester
        .widgetList<ServiceOverviewArt>(find.byType(ServiceOverviewArt))
        .toList();
    expect([for (final a in art) a.posterUrl], [poster, null]);
    // No poster held: the title's initials, never an empty box.
    expect(find.text('NS'), findsOneWidget);
    expect(lit, [poster]);
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, service: _FailingHistoryBazarr());

    // The failed region says so in its own slot…
    expect(find.byType(InlineErrorRetry), findsOneWidget);
    expect(
      find.textContaining(", so its recent subtitle activity is not shown."),
      findsOneWidget,
    );
    // …and the other one still drew its heading.
    expect(find.byType(SectionHeader), findsNWidgets(2));
  });

  testWidgets('the retry on a failed section re-runs the load', (tester) async {
    // Moved off the retired `BazarrScreen`. The invariant is the one its
    // comment was written for: an earlier version of that test built a replica
    // of the error widget inside its own body and tapped *that*, so it stayed
    // green with the real retry unwired. Only a counter on the service can tell
    // a retry that reloads from a button that merely exists.
    final service = FakeBazarrService()
      ..throwOnWanted = Exception('bazarr is down');

    await _pump(tester, service: service);

    expect(service.wantedEpisodesCalls, 1);
    expect(find.byType(InlineErrorRetry), findsOneWidget);

    // Tapped by its label rather than by its button type: the line's verbs
    // are text buttons whose runtime types are private, and `find.byType`
    // matches exactly.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(service.wantedEpisodesCalls, 2);
    // Still failing, so the section stays in its error state rather than
    // flickering to empty.
    expect(find.byType(InlineErrorRetry), findsOneWidget);
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    final service = FakeBazarrService()
      ..badges = _badges(episodes: 1, movies: 0)
      ..wantedEpisodesResult = const BazarrPagedResult(
        data: [
          BazarrWantedItem(
            seriesTitle: 'A Series With A Very Long Name Indeed',
            episodeNumber: 'S02E04',
            sonarrSeriesId: 3,
            missingLanguages: [
              BazarrSubtitleLanguage(name: 'Italian', forced: true, hi: true),
            ],
          ),
        ],
        total: 1,
      );

    await _pump(tester, service: service, textScaleFactor: 3.0);

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Bazarr that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, service: FakeBazarrService(), configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.bazarr);
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required FakeBazarrService service,
  String? version = '1.5.1',
  bool configured = true,
  double textScaleFactor = 1.0,
  List<dynamic> overrides = const [],
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch a deliberately failing section
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => configured
              ? settingsWith(
                  bazarrUrl: 'http://bazarr.local',
                  bazarrApiKey: 'key',
                )
              : const SettingsModel(),
        ),
        bazarrServiceProvider.overrideWith((ref) => service),
        serviceStatusClientFactoryProvider.overrideWith(
          (ref) =>
              ({
                required String baseUrl,
                required String apiKey,
                String? pinnedCertFingerprint,
                Map<String, String> accessHeaders = const {},
              }) => _StatusClient(version),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: const BazarrOverviewScreen(topPadding: 0),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
    return;
  }
  // A poster still loading shimmers for as long as it loads.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

BazarrBadges _badges({required int episodes, required int movies}) =>
    BazarrBadges(
      episodes: episodes,
      movies: movies,
      providers: 5,
      status: true,
      sonarrSignalR: true,
      radarrSignalR: true,
      announcements: 0,
    );

class _FailingHistoryBazarr extends FakeBazarrService {
  @override
  Future<BazarrPagedResult<Map<String, dynamic>>> getEpisodesHistory({
    int start = 0,
    int length = 50,
  }) async => throw Exception('history failed');
}

/// The reachability probe, answered offline.
///
/// A null [version] is the wire shape of a service that did not answer: the
/// probe throws, which is what `_loadServiceSummary` reads as offline.
class _StatusClient extends ApiClient {
  _StatusClient(this.version)
    : super(baseUrl: 'http://bazarr.local', apiKey: 'key');

  final String? version;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    if (version == null) throw const SocketException('Connection refused');
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      // Bazarr's shape: the version lives under `data.bazarr_version`, not at
      // the top level like the \*arr family's.
      data: {
        'data': {'bazarr_version': version},
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
