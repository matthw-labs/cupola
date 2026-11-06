import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/list_rows_shimmer.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';
import 'package:cupola/core/widgets/service_list_page.dart';
import 'package:cupola/core/widgets/service_overview.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_board.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/arr_calendar_screen.dart';
import 'package:cupola/features/activity/presentation/arr_tab_screen.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_history_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_library_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_providers_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/seerr_admin_screens.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/dockge/presentation/dockge_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_terminal_screen.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_tab_screens.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/plex/presentation/plex_tab_screens.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_library_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_stats_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/presentation/readarr_activity_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_history_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_library_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_tab_screens.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_libraries_screen.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_users_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_tab_screens.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_screen.dart';

import '../../../test_helpers/capability_overrides.dart';
import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

/// What the router hands every hosted tab screen as `topPadding`: the service
/// band plus the tab bar, **without** the phone's top inset. Mirrored here
/// because the router's own constant is private.
const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

/// An iPhone 17 Pro in portrait, the surface the defect was seen on.
const Size _phone = Size(402, 874);
const double _statusBar = 62;

/// The tabs of a service room on a notched phone: the band, the tab bar under
/// it, and the tab's own screen under both.
///
/// **The bar is placed an inset below `kToolbarHeight`**, because the band
/// consumes the inset (see `ServiceHomeScreen.bandHeightOf`). A hosted screen
/// is handed the bare chrome height, so it is the screen's job to add the
/// inset, through a `SafeArea` or through `MediaQuery`. A test surface with no
/// inset cannot tell a screen that does from one that does not, which is how a
/// tab's first row sat under the bar until someone looked at a real iPhone.
void main() {
  /// The phone, with its notch. Set on the view rather than wrapped around the
  /// app, so the `MediaQuery` every widget reads is the one a device builds.
  void usePhone(WidgetTester tester) {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = _phone
      ..padding = const FakeViewPadding(top: _statusBar)
      ..viewPadding = const FakeViewPadding(top: _statusBar);
    addTearDown(tester.view.reset);
  }

  Future<void> pumpHosted(
    WidgetTester tester, {
    required ServiceKey service,
    required ServiceTab tab,
    required Widget child,
    List<Override> overrides = const [],
    bool phone = true,
  }) async {
    if (phone) usePhone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(configured: [service]),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: ServiceHomeScreen(
              service: service,
              child: ServiceTabScaffold(
                service: service,
                tab: tab,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Where the tab bar ends: the line no hosted content may start above.
  double barBottom(WidgetTester tester) => tester
      .getRect(
        find.ancestor(
          of: find.byType(ServiceTabBar),
          matching: find.byType(GlassSurface),
        ),
      )
      .bottom;

  void expectClearsTheBar(WidgetTester tester, Finder content) {
    expect(content, findsWidgets);
    expect(
      tester.getTopLeft(content.first).dy,
      greaterThanOrEqualTo(barBottom(tester)),
      reason: 'the first content starts under the tab bar',
    );
  }

  group('the phone the cases run on', () {
    testWidgets('has a status bar, and the bar sits an inset below the band', (
      tester,
    ) async {
      // The fixture itself, asserted: if the inset ever stopped reaching the
      // tree, every case below would pass for the wrong reason.
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.queue,
        child: const SizedBox.expand(),
      );

      expect(
        MediaQuery.paddingOf(tester.element(find.byType(ServiceTabBar))).top,
        _statusBar,
      );
      expect(
        barBottom(tester),
        _statusBar + kToolbarHeight + ServiceTabBar.height,
      );
      expect(barBottom(tester), _statusBar + _hostedTopPadding);
    });
  });

  group('ArrTabScreen clears the glass bars', () {
    final overrides = <Override>[
      radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
    ];

    testWidgets('an empty queue starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.queue,
        overrides: overrides,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.queue,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('Queue is empty'), findsOneWidget);
      expectClearsTheBar(tester, find.byType(AppEmptyState));
      // The picture the user reported: the icon, not just the well around it.
      expectClearsTheBar(tester, find.byIcon(Icons.download_done_rounded));
    });

    testWidgets('an empty history starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.history,
        overrides: overrides,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.history,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('No history yet'), findsOneWidget);
      expectClearsTheBar(tester, find.byType(AppEmptyState));
    });

    testWidgets('Wanted draws its pills below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.wanted,
        overrides: overrides,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.wanted,
          topPadding: _hostedTopPadding,
        ),
      );

      // The pills are Wanted's first row: missing against cutoff unmet.
      expectClearsTheBar(tester, find.text('Missing'));
    });

    testWidgets('a queue still loading starts below the tab bar', (
      tester,
    ) async {
      // Not the empty state: the skeleton is the first thing every tab shows,
      // and it rides the same padding.
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.queue,
        overrides: [
          radarrServiceProvider.overrideWith((ref) => _NeverAnswers()),
        ],
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.queue,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.byType(AppEmptyState), findsNothing);
      expectClearsTheBar(tester, find.byType(ShimmerList));
    });
  });

  group('ServiceOverviewPage clears the glass bars', () {
    // The one page every Overview but Stream's is: its body is a `SafeArea`
    // that takes the status bar's inset and hands `topPadding` to the scroll
    // view, so a first region starts below the tab bar on a notched phone.
    // The guard excuses each `*OverviewScreen` by leaning on this case.
    testWidgets('the first region starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.overview,
        overrides: [
          serviceSummaryProvider(
            ServiceKey.radarr,
          ).overrideWith((ref) => Completer<ServiceSummary>().future),
        ],
        child: ServiceOverviewPage(
          service: ServiceKey.radarr,
          topPadding: _hostedTopPadding,
          kpis: (ref) => const AsyncData(<ServiceKpi>[]),
          refresh: (ref) {},
          sections: (ref) => const [Text('First region')],
        ),
      );

      expectClearsTheBar(tester, find.byType(ServiceOverviewIdentity));
      expectClearsTheBar(tester, find.text('First region'));
    });
  });

  group('on a desktop window the inset adds nothing', () {
    testWidgets('an empty queue still sits right under the tab row', (
      tester,
    ) async {
      // A desktop window has no status bar, so the inset the fix adds is zero
      // there and the hosted screen lands exactly where it did: the phone's
      // band and bar reserved, and the screen lifted by the band the window
      // does not draw.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(1200, 800);
        addTearDown(tester.view.reset);

        await pumpHosted(
          tester,
          service: ServiceKey.radarr,
          tab: ServiceTab.queue,
          phone: false,
          overrides: [
            radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
          ],
          child: const ArrTabScreen(
            serviceType: ServiceType.movies,
            mode: ArrTabMode.queue,
            topPadding: _hostedTopPadding,
          ),
        );

        expect(find.text('Queue is empty'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(AppEmptyState)).dy,
          ServiceTabBar.height,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Bazarr tabs clear the glass bars', () {
    List<Override> over(FakeBazarrService service) => [
      bazarrServiceProvider.overrideWith((ref) => service),
    ];

    testWidgets('Wanted draws its Episodes and Movies bar below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.wanted,
        overrides: over(FakeBazarrService()),
        child: const BazarrWantedScreen(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(TabBar));
    });

    testWidgets('the Series library starts below the tab bar', (tester) async {
      final service = FakeBazarrService()
        ..seriesResult = const BazarrPagedResult(
          data: [
            BazarrSeries(
              sonarrSeriesId: 1,
              title: 'Foundation',
              year: 2021,
              monitored: true,
            ),
          ],
          total: 1,
        );
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.series,
        overrides: over(service),
        child: const BazarrLibraryScreen.series(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('Foundation'), findsOneWidget);
      expectClearsTheBar(tester, find.text('Foundation'));
    });

    testWidgets('the Movies library starts below the tab bar', (tester) async {
      final service = FakeBazarrService()
        ..moviesResult = const BazarrPagedResult(
          data: [
            BazarrMovie(
              radarrId: 1,
              title: 'Arrival',
              year: 2016,
              monitored: true,
            ),
          ],
          total: 1,
        );
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.movies,
        overrides: over(service),
        child: const BazarrLibraryScreen.movies(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.textContaining('Arrival'), findsOneWidget);
      expectClearsTheBar(tester, find.textContaining('Arrival'));
    });

    testWidgets('a library still loading starts below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.series,
        overrides: over(_BazarrNeverAnswers()),
        child: const BazarrLibraryScreen.series(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(ShimmerPlaceholder));
    });

    testWidgets('History draws its filter pills below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.history,
        overrides: over(FakeBazarrService()),
        child: const BazarrHistoryScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, _selectionPills);
    });

    testWidgets('Providers starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.providers,
        overrides: over(FakeBazarrService()),
        child: const BazarrProvidersScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });
  });

  group('Prowlarr tabs clear the glass bars', () {
    testWidgets('Indexers draws its actions row below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.prowlarr,
        tab: ServiceTab.indexers,
        overrides: [
          prowlarrIndexersProvider.overrideWith(
            (ref) async => const <ProwlarrIndexer>[],
          ),
          prowlarrIndexerStatusProvider.overrideWith(
            (ref) async => const <ProwlarrIndexerStatus>[],
          ),
          prowlarrTagsProvider.overrideWith(
            (ref) async => const <ProwlarrTag>[],
          ),
        ],
        child: const ProwlarrLibraryScreen(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byTooltip('Add indexer'));
    });

    testWidgets('History draws its filter pills below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.prowlarr,
        tab: ServiceTab.history,
        overrides: [
          prowlarrHistoryPageProvider((
            page: 1,
            pageSize: 50,
            eventType: null,
          )).overrideWith((ref) async => const ProwlarrHistoryPage()),
        ],
        child: const ProwlarrHistoryScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, _selectionPills);
    });

    testWidgets('Stats draws its window pills below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.prowlarr,
        tab: ServiceTab.stats,
        overrides: [
          prowlarrIndexerStatsForWindowProvider(
            ProwlarrStatsWindow.day,
          ).overrideWith((ref) => Completer<ProwlarrIndexerStats>().future),
        ],
        child: const ProwlarrStatsScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, _selectionPills);
    });
  });

  group('Readarr tabs clear the glass bars', () {
    final overrides = <Override>[
      readarrServiceProvider.overrideWith((ref) => _EmptyReadarr()),
    ];

    testWidgets('an empty queue starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.readarr,
        tab: ServiceTab.queue,
        overrides: overrides,
        child: const ReadarrActivityScreen(
          mode: ReadarrActivityMode.queue,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('Queue is empty'), findsOneWidget);
      expectClearsTheBar(tester, find.byType(AppEmptyState));
    });

    testWidgets('an empty Wanted starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.readarr,
        tab: ServiceTab.wanted,
        overrides: overrides,
        child: const ReadarrActivityScreen(
          mode: ReadarrActivityMode.wanted,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('Nothing missing'), findsOneWidget);
      expectClearsTheBar(tester, find.byType(AppEmptyState));
    });

    testWidgets('an empty history starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.readarr,
        tab: ServiceTab.history,
        overrides: overrides,
        child: const ReadarrHistoryScreen(topPadding: _hostedTopPadding),
      );

      expect(find.text('No history yet'), findsOneWidget);
      expectClearsTheBar(tester, find.byType(AppEmptyState));
    });

    testWidgets('Readarr Library starts below the tab bar', (tester) async {
      // The shared browse scaffold, as Radarr's: its header adds the room the
      // bands take and the inset itself.
      await pumpHosted(
        tester,
        service: ServiceKey.readarr,
        tab: ServiceTab.library,
        overrides: [readarrAuthorsProvider.overrideWith((ref) => _pending())],
        child: const ReadarrLibraryScreen(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(SearchBarHeader));
    });
  });

  group('The download clients\' tabs clear the glass bars', () {
    testWidgets('qBittorrent RSS starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.qbittorrent,
        tab: ServiceTab.rss,
        overrides: [
          qbittorrentRssFeedsProvider.overrideWith((ref) => _pending()),
          qbittorrentRssRulesProvider.overrideWith((ref) => _pending()),
        ],
        child: const QbittorrentRssScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });

    testWidgets('SABnzbd History draws its filter pills below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.sabnzbd,
        tab: ServiceTab.history,
        overrides: [sabnzbdHistoryProvider.overrideWith((ref) => _pending())],
        child: const SabnzbdHistoryScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, _selectionPills);
    });

    testWidgets('SABnzbd Servers starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.sabnzbd,
        tab: ServiceTab.servers,
        overrides: [
          sabnzbdServersProvider.overrideWith((ref) => _pending()),
          sabnzbdServerStatsProvider.overrideWith((ref) => _pending()),
        ],
        child: const SabnzbdServersScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });

    testWidgets('NZBGet History starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.nzbget,
        tab: ServiceTab.history,
        overrides: [nzbgetHistoryProvider.overrideWith((ref) => _pending())],
        child: const NzbgetHistoryScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets('NZBGet Feeds starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.nzbget,
        tab: ServiceTab.feeds,
        overrides: [nzbgetFeedsProvider.overrideWith((ref) => _pending())],
        child: const NzbgetFeedsScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets('NZBGet Messages starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.nzbget,
        tab: ServiceTab.messages,
        overrides: [nzbgetMessagesProvider.overrideWith((ref) => _pending())],
        child: const NzbgetMessagesScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets('Transmission Labels starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.transmission,
        tab: ServiceTab.labels,
        overrides: [
          transmissionTorrentsProvider.overrideWith((ref) => _pending()),
          transmissionSessionProvider.overrideWith((ref) => _pending()),
        ],
        child: const TransmissionLabelsScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets('Transmission Session starts below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.transmission,
        tab: ServiceTab.session,
        overrides: [
          transmissionSessionProvider.overrideWith((ref) => _pending()),
        ],
        child: const TransmissionSessionScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });
  });

  // These five pages wrapped their body in a `SafeArea` that took the top inset
  // only when they drew an app bar of their own, and hosted they draw none.
  group('The pages that skipped the status bar clear the glass bars', () {
    testWidgets('Dockge Stacks starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.dockge,
        tab: ServiceTab.stacks,
        overrides: [
          dockgeStackListProvider.overrideWith(
            (ref) => const Stream<List<DockgeStack>>.empty(),
          ),
          serviceKpiProvider(
            ServiceKey.dockge,
          ).overrideWith((ref) => _pending()),
        ],
        child: const DockgeScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ServiceKpiPeek));
    });

    testWidgets('Dockge Terminal starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.dockge,
        tab: ServiceTab.terminal,
        overrides: [
          dockgeStackListProvider.overrideWith(
            (ref) => const Stream<List<DockgeStack>>.empty(),
          ),
        ],
        child: const DockgeTerminalScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });

    testWidgets('Unraid Array starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.unraid,
        tab: ServiceTab.array,
        overrides: [
          serviceSummaryProvider(
            ServiceKey.unraid,
          ).overrideWith((ref) => _pending()),
          unraidArrayProvider.overrideWith((ref) => _pending()),
        ],
        child: const UnraidScreen.array(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });

    testWidgets('Nginx Proxy Manager Proxy hosts starts below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.nginxProxyManager,
        tab: ServiceTab.proxyHosts,
        overrides: [
          serviceSummaryProvider(
            ServiceKey.nginxProxyManager,
          ).overrideWith((ref) => _pending()),
          npmProxyHostsProvider.overrideWith((ref) => _pending()),
          // Answered, so the capability banner (which a probe that cannot
          // reach a real server would draw first) is not what leads the page.
          capabilityOverride(),
        ],
        child: const NpmScreen.proxyHosts(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });

    testWidgets('Jellyfin Libraries starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.jellyfin,
        tab: ServiceTab.libraries,
        overrides: [
          jellyfinLacksAdministratorProvider.overrideWithValue(false),
          jellyfinLibrariesProvider.overrideWith((ref) => _pending()),
        ],
        child: const StreamLibrariesScreen(
          service: ServiceKey.jellyfin,
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });

    testWidgets('Plex Libraries starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.plex,
        tab: ServiceTab.libraries,
        overrides: [plexLibrariesProvider.overrideWith((ref) => _pending())],
        child: const StreamLibrariesScreen(
          service: ServiceKey.plex,
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });
  });

  group('ServiceListPage takes the inset itself', () {
    // The page is handed only what the host's bands take, as the router hands
    // every tab, and nothing here adds the status bar: whatever clears the tab
    // bar does so because the page did.
    testWidgets('its first row starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.plex,
        tab: ServiceTab.devices,
        child: ServiceListPage<String>.unsummarised(
          service: ServiceKey.plex,
          topPadding: _hostedTopPadding,
          value: const AsyncData(['A first row']),
          serviceName: 'Plex devices',
          emptyIcon: Icons.devices_other_rounded,
          emptyTitle: 'No devices',
          emptyMessage: 'Nothing here.',
          onRetry: () {},
          rowBuilder: (row) => Text(row),
        ),
      );

      expect(find.text('A first row'), findsOneWidget);
      expectClearsTheBar(tester, find.text('A first row'));
    });

    testWidgets('its own header starts below the tab bar', (tester) async {
      // The header sits outside the state ladder, so it rides the padding
      // alone: this is the case where a page that forgot the inset would put
      // a filter under the glass.
      await pumpHosted(
        tester,
        service: ServiceKey.plex,
        tab: ServiceTab.devices,
        child: ServiceListPage<String>(
          service: ServiceKey.plex,
          topPadding: _hostedTopPadding,
          value: const AsyncData(['A first row']),
          serviceName: 'Plex devices',
          emptyIcon: Icons.devices_other_rounded,
          emptyTitle: 'No devices',
          emptyMessage: 'Nothing here.',
          onRetry: () {},
          summary: (rows) => '${rows.length} rows',
          header: const Text('A header'),
          rowBuilder: (row) => Text(row),
        ),
      );

      expectClearsTheBar(tester, find.text('A header'));
    });
  });

  // These pages put the room the bands take, and the inset, into their own
  // header or list padding rather than into a `SafeArea`.
  group('The library, calendar and request tabs clear the glass bars', () {
    testWidgets('Radarr Library starts below the tab bar', (tester) async {
      // The shared browse scaffold, which Sonarr's and Lidarr's libraries
      // hand their room to unchanged.
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.library,
        overrides: [moviesProvider.overrideWith((ref) => _pending())],
        child: const MoviesScreen(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(SearchBarHeader));
    });

    testWidgets('a Calendar still loading starts below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.calendar,
        overrides: [
          calendarSourceProvider.overrideWith((ref, key) => _pending()),
        ],
        child: const ArrCalendarScreen(
          service: ServiceKey.radarr,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(ShimmerList));
    });

    testWidgets('qBittorrent Queue draws its figures below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.qbittorrent,
        tab: ServiceTab.queue,
        overrides: [
          torrentsProvider.overrideWith((ref) => _pending()),
          torrentPollingProvider.overrideWith((ref) {}),
          serviceKpiProvider(
            ServiceKey.qbittorrent,
          ).overrideWith((ref) => _pending()),
        ],
        child: const QbittorrentScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ServiceKpiPeek));
    });

    testWidgets('Seerr Requests starts its list below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.seerr,
        tab: ServiceTab.requests,
        overrides: [requestsProvider.overrideWith((ref) => _pending())],
        child: const ServiceAllRequestsScreen(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(RequestsBoard));
    });

    testWidgets('Seerr Issues draws its filter pills below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.seerr,
        tab: ServiceTab.issues,
        overrides: [
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          seerrIssuesProvider.overrideWith((ref, filter) => _pending()),
        ],
        child: const SeerrIssuesScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, _selectionPills);
    });

    testWidgets('Seerr Users starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.seerr,
        tab: ServiceTab.users,
        overrides: [
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          seerrUsersProvider.overrideWith((ref) => _pending()),
        ],
        child: const SeerrUsersScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets(
      'an account that may not manage users reads why below the bar',
      (tester) async {
        await pumpHosted(
          tester,
          service: ServiceKey.seerr,
          tab: ServiceTab.users,
          overrides: [
            seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
            roleGateProvider('').overrideWithValue(
              const RoleGate(
                audience: Audience.operator,
                grant: SeerrGrant.account(permissions: 0),
              ),
            ),
          ],
          child: const SeerrUsersScreen(topPadding: _hostedTopPadding),
        );

        expect(find.byType(ListRowsShimmer), findsNothing);
        expectClearsTheBar(tester, find.byType(AppEmptyState));
      },
    );
  });

  group('Tracearr\'s tabs clear the glass bars', () {
    // Every list tab of Tracearr is a `ServiceListPage` whose first read has
    // not come back: the skeleton is the first content, and it starts below
    // the tab bar on a notched phone.
    final pending = _PendingTracearr();

    for (final (name, tab, screen) in const <(String, ServiceTab, Widget)>[
      (
        'Live',
        ServiceTab.live,
        TracearrLiveScreen(topPadding: _hostedTopPadding),
      ),
      (
        'History',
        ServiceTab.history,
        TracearrHistoryScreen(topPadding: _hostedTopPadding),
      ),
      (
        'Users',
        ServiceTab.users,
        TracearrUsersScreen(topPadding: _hostedTopPadding),
      ),
      (
        'Violations',
        ServiceTab.violations,
        TracearrViolationsScreen(topPadding: _hostedTopPadding),
      ),
    ]) {
      testWidgets('Tracearr $name starts below the tab bar', (tester) async {
        await pumpHosted(
          tester,
          service: ServiceKey.tracearr,
          tab: tab,
          overrides: [
            tracearrClientProvider.overrideWithValue(pending),
            tracearrStreamsProvider.overrideWith((ref) => _pending()),
          ],
          child: screen,
        );

        expectClearsTheBar(tester, find.byType(ListRowsShimmer));
      });
    }
  });

  group('The media servers\' tabs clear the glass bars', () {
    testWidgets('Jellyfin Users starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.jellyfin,
        tab: ServiceTab.users,
        overrides: [
          jellyfinLacksAdministratorProvider.overrideWithValue(false),
          jellyfinUsersProvider.overrideWith((ref) => _pending()),
        ],
        child: const JellyfinUsersScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets('Jellyfin Devices starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.jellyfin,
        tab: ServiceTab.devices,
        overrides: [
          jellyfinLacksAdministratorProvider.overrideWithValue(false),
          jellyfinDevicesProvider.overrideWith((ref) => _pending()),
        ],
        child: const JellyfinDevicesScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets('Jellyfin Tasks starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.jellyfin,
        tab: ServiceTab.tasks,
        overrides: [
          jellyfinLacksAdministratorProvider.overrideWithValue(false),
          jellyfinTasksProvider.overrideWith((ref) => _pending()),
        ],
        child: const JellyfinTasksScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets(
      'a household member\'s Devices placeholder starts below the bar',
      (tester) async {
        await pumpHosted(
          tester,
          service: ServiceKey.jellyfin,
          tab: ServiceTab.devices,
          overrides: [
            jellyfinLacksAdministratorProvider.overrideWithValue(true),
          ],
          child: const JellyfinDevicesScreen(topPadding: _hostedTopPadding),
        );

        expectClearsTheBar(tester, find.byType(AppEmptyStatePage));
      },
    );

    testWidgets('Jellyfin Activity starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.jellyfin,
        tab: ServiceTab.activity,
        overrides: [
          jellyfinLacksAdministratorProvider.overrideWithValue(false),
          jellyfinSessionsProvider.overrideWith((ref) => _pending()),
        ],
        child: const JellyfinActivityScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(StreamNowPlayingSection));
    });

    testWidgets('Plex On deck starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.plex,
        tab: ServiceTab.onDeck,
        overrides: [plexOnDeckTabProvider.overrideWith((ref) => _pending())],
        child: const PlexOnDeckScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ShimmerGrid));
    });

    testWidgets('Plex Activities starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.plex,
        tab: ServiceTab.activities,
        overrides: [plexSessionsProvider.overrideWith((ref) => _pending())],
        child: const PlexActivitiesScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(StreamNowPlayingSection));
    });

    testWidgets('Plex Devices starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.plex,
        tab: ServiceTab.devices,
        overrides: [plexDevicesProvider.overrideWith((ref) => _pending())],
        child: const PlexDevicesScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets('Plex Playlists starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.plex,
        tab: ServiceTab.playlists,
        overrides: [plexPlaylistsProvider.overrideWith((ref) => _pending())],
        child: const PlexPlaylistsScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });
  });
}

/// A Radarr that never answers its queue, so the screen stays on its skeleton.
class _NeverAnswers extends FakeRadarrService {
  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) =>
      Completer<List<dynamic>>().future;
}

/// A Bazarr that never answers a library page, so the list stays on its shimmer.
class _BazarrNeverAnswers extends FakeBazarrService {
  @override
  Future<BazarrPagedResult<BazarrSeries>> getSeries({
    int start = 0,
    int length = 50,
  }) => Completer<BazarrPagedResult<BazarrSeries>>().future;
}

/// The filter pills a screen leads with. `SelectionPills` is generic over a
/// screen's private enum, so it can only be found by its name.
final _selectionPills = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString().startsWith('SelectionPills'),
  description: 'SelectionPills',
);

/// A Readarr with nothing in its queue, its wanted list or its history.
class _EmptyReadarr extends ReadarrService {
  _EmptyReadarr() : super(FakeApiClient());

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getAllMissing({
    Map<String, dynamic>? queryParameters,
  }) async => const [];

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => const [];
}

/// A read that never answers, so a screen stays on its loading state.
Future<T> _pending<T>() => Completer<T>().future;

/// A Tracearr whose every list read is still out.
class _PendingTracearr extends TracearrClient {
  _PendingTracearr()
    : super(baseUrl: 'http://tracearr.test', apiKey: 'trr_pub_test');

  @override
  Future<TracearrPage<TracearrHistoryEntry>> getHistory({
    String? cursor,
    int pageSize = 25,
    TracearrHistoryFilter filter = const TracearrHistoryFilter(),
  }) => _pending();

  @override
  Future<TracearrPage<TracearrUser>> getUsers({
    String? cursor,
    int pageSize = 25,
    bool includeRemoved = false,
  }) => _pending();

  @override
  Future<TracearrPage<TracearrViolation>> getViolations({
    String? cursor,
    int pageSize = 25,
    TracearrViolationFilter filter = const TracearrViolationFilter(),
  }) => _pending();
}
