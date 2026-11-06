import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/page_tabs.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/data/acted_faults.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_history.dart';
import 'package:cupola/features/activity/domain/activity_readout.dart';
import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/features/activity/data/household_requests.dart';
import 'package:cupola/features/activity/domain/everyones_requests.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_history_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/download_table.dart';
import 'package:cupola/features/activity/presentation/widgets/everyone_request_row.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_board.dart';
import 'package:cupola/features/activity/presentation/widgets/import_done_card.dart';
import 'package:cupola/features/activity/presentation/widgets/needs_you_cards.dart';
import 'package:cupola/features/activity/presentation/widgets/violation_rows.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/home/presentation/widgets/home_well.dart';
import 'package:cupola/features/home/presentation/widgets/now_playing_module.dart';
import 'package:cupola/features/import/presentation/import_service_picker_sheet.dart';
import 'package:cupola/features/release_search/presentation/release_searches_body.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/nothing_set_up.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/core/widgets/screen_title.dart';

/// The services Activity reads: the queues, the clients, the requests and
/// whatever says who is playing. With none of them set up the page has
/// nothing to say and says how to begin.
///
/// Not `const`: the playing services come from their capability, so a new one
/// is read here without this list being touched.
final _activityServices = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.readarr,
  ServiceKey.qbittorrent,
  ServiceKey.transmission,
  ServiceKey.sabnzbd,
  ServiceKey.nzbget,
  ServiceKey.seerr,
  ...sessionServices,
];

/// The arrs whose History tab the page's foot leads to.
const _historyServices = [
  ServiceKey.sonarr,
  ServiceKey.radarr,
  ServiceKey.lidarr,
  ServiceKey.readarr,
];

/// How many downloads All draws before the way to Downloads.
const _allDownloadsLimit = 5;

/// How many waiting downloads All draws before the way to Downloads.
const _allUpNextLimit = 3;

/// How many of today's imports All draws before the way to History.
const _allFinishedLimit = 5;

/// The artwork that lights Activity: the poster of the first download stuck,
/// else of the first one moving; null for the lamp.
final activityRoomSourceProvider = Provider.autoDispose<String?>((ref) {
  final items = ref.watch(servicesQueueProvider).value?.items;
  if (items == null) return null;
  String? posterOf(bool Function(ServiceQueueItem item) leads) => [
    for (final item in items)
      if (leads(item) && (item.posterUrl ?? '').isNotEmpty) item.posterUrl!,
  ].firstOrNull;
  return posterOf((item) => isDownloadFault(item.fault)) ??
      posterOf((item) => item.isMoving);
});

/// Activity: what is moving, what is stuck, who asked and who is watching.
///
/// One page with four views, each at its own address ([ActivityTab]): All,
/// Downloads, Requests and History. A view is a choice, never a filter on
/// top of another. The page has no app bar: its name, the line under it and
/// the views scroll with it, as the Home's day does.
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key, required this.tab, this.requestsOf});

  /// The view the address names.
  final ActivityTab tab;

  /// The Seerr connection the Requests view reads (`?i=`), or null for
  /// every one.
  final String? requestsOf;

  /// How stale the page may be before returning to it earns a refetch: the
  /// Home's two minutes, for the same reads.
  static const staleAfter = Duration(minutes: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(
      navigationRefreshProvider(NavigationSection.activity),
      (_, _) => invalidateActivity(ref, tab),
    );
    ref.watchWhileLive(context, activityLivePollProvider(tab));

    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );
    final settings = ref.watch(currentSettingsProvider);
    final nothingSetUp = !_activityServices.any(settings.isServiceConfigured);
    // The room takes its light from the download that leads it: the first one
    // stuck, else the first one moving.
    final lead = nothingSetUp ? null : ref.watch(activityRoomSourceProvider);
    final light = lead == null
        ? null
        : ref.watch(titleLightProvider(lead)).value;

    return RefreshOnReturn(
      id: 'activity',
      maxAge: staleAfter,
      onStale: () => ref.triggerNavigationRefresh(NavigationSection.activity),
      child: AmbientScaffold(
        accent: light?.light,
        art: light?.art,
        accentDuration: AppAnimation.light,
        body: nothingSetUp
            ? NothingSetUpView(bottomPadding: bottomPadding)
            : Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: () => refreshActivity(ref, tab),
                    child: LayoutBuilder(
                      builder: (context, box) => HomeWell(
                        // A desktop window reads the downloads as a table,
                        // which wants the width a reading column gives up.
                        inset: AppBreakpoints.wellInset(
                          box.maxWidth,
                          well: AppBreakpoints.isDesktopShell(context)
                              ? AppBreakpoints.contentWell
                              : AppBreakpoints.readingWell,
                        ),
                        child: Builder(
                          builder: (context) {
                            Widget column(Widget child) =>
                                HomeWell.column(context, child);
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.only(bottom: bottomPadding),
                              children: [
                                column(const _ActivityHeader()),
                                column(
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.gutter,
                                      AppSpacing.md,
                                      AppSpacing.gutter,
                                      0,
                                    ),
                                    child: PageTabs<ActivityTab>(
                                      values: ActivityTab.values,
                                      selected: tab,
                                      labelBuilder: (tab) => tab.label,
                                      onSelected: (tab) =>
                                          context.go(tab.location),
                                    ),
                                  ),
                                ),
                                for (final section in _sectionsOf(tab))
                                  column(section),
                                const SizedBox(height: AppSpacing.lg),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: StatusBarScrim(),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _sectionsOf(ActivityTab tab) => switch (tab) {
    ActivityTab.all => const [
      _NeedsYouSection(),
      _EveryonesRequestsSection(),
      _WatchingNowSection(),
      _DownloadsSection(limit: _allDownloadsLimit),
      _UpNextSection(limit: _allUpNextLimit),
      _FinishedTodaySection(),
      _HistoryFoot(),
    ],
    ActivityTab.downloads => [
      ReleaseSearchesGroup(
        heading: (count) => _GroupHeading(
          title: 'Searching',
          meta: count == 1 ? '1 search' : '$count searches',
        ),
      ),
      const _DownloadsSection(),
      const _UpNextSection(),
    ],
    ActivityTab.requests => [
      RequestsBoard(key: ValueKey(requestsOf), only: requestsOf),
    ],
    ActivityTab.history => const [
      _HistoryDays(),
      _HistoryFoot(blocklist: true),
    ],
  };
}

/// The page's name over what is moving: `4 moving · 40.4 MB/s · 1 stuck`,
/// or `Nothing moving` and when the last download finished; and the menu of
/// what the page can start.
class _ActivityHeader extends ConsumerWidget {
  const _ActivityHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        MediaQuery.paddingOf(context).top + AppSpacing.sm,
        AppSpacing.xs,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ScreenTitle('Activity'),
                ),
              ),
              const _ActivityMenu(),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(right: AppSpacing.md),
            child: _Readout(),
          ),
        ],
      ),
    );
  }
}

/// What the page can start that no row starts: a manual import of a
/// download no fault names.
class _ActivityMenu extends StatelessWidget {
  const _ActivityMenu();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return PopupMenuButton<_MenuItem>(
      tooltip: 'More',
      icon: Icon(Icons.more_horiz_rounded, color: room.ink),
      onSelected: (item) => switch (item) {
        _MenuItem.manualImport => showImportServicePickerSheet(context),
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _MenuItem.manualImport,
          child: Text('Manual import…'),
        ),
      ],
    );
  }
}

enum _MenuItem { manualImport }

/// The line under the title, from the queues the Home's Downloads reads, so
/// the two never disagree.
class _Readout extends ConsumerWidget {
  const _Readout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final read = ref.watch(servicesInFlightProvider);
    final data = read.value;
    final words = AppType.body.copyWith(color: room.inkSecondary);

    Widget line(Widget child) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );

    if (data == null) {
      if (!read.hasError) return line(const SizedBox.shrink());
      return line(
        BriefFailureLine.line(
          error: read.error!,
          service: ServiceKey.radarr,
          onRetry: () => ref.invalidate(servicesQueueProvider),
        ),
      );
    }

    final coverage = data.coverage;
    final stuck = data.faults
        .where((item) => isDownloadFault(item.fault))
        .length;
    final parts = activityReadoutParts(
      moving: data.movingCount,
      stuck: stuck,
      rateBytesPerSecond: data.rateBytesPerSecond,
      coverage: coverage,
    );
    final note = coverageNote(coverage);

    if (parts.isEmpty) {
      final last = lastDownloadFinished(
        lastImportOf(
          ref.watch(servicesArrivalsProvider).value?.entries ?? const [],
        ),
        now: ref.watch(arrivalsClockProvider)(),
      );
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nothingMoving, style: AppType.body.copyWith(color: room.ink)),
            if (last != null) Text(last, style: words),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.xs),
              HomeCoverageNote(note: note, coverage: coverage),
            ],
          ],
        ),
      );
    }

    final amber = statusToneColor(
      scheme,
      StatusTone.warning,
      surface: room.ground,
    );
    final figure = AppType.figureSmall;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: spokenActivityReadout(parts),
            excludeSemantics: true,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final (index, part) in parts.indexed) ...[
                  if (index > 0)
                    Text('·', style: words.copyWith(color: room.inkTertiary)),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: part.figure,
                          style: figure.copyWith(
                            color: part.stuck ? amber : room.ink,
                          ),
                        ),
                        TextSpan(
                          text: ' ${part.words}',
                          style: part.stuck
                              ? words
                                    .weight(FontWeight.w600)
                                    .copyWith(color: amber)
                              : words,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            HomeCoverageNote(note: note, coverage: coverage),
          ],
        ],
      ),
    );
  }
}

/// A section's name with no slab under it: the searches, whose cards are
/// slabs of their own.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.title, required this.meta});

  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.section,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Semantics(
        header: true,
        label: '$title, $meta',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppType.section.copyWith(color: room.ink),
              ),
            ),
            Text(meta, style: AppType.meta.copyWith(color: room.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

/// `3 faults · 2 violations · 2 requests`: what Needs you holds, each kind
/// counted apart, since a request is somebody waiting and a violation a rule
/// somebody broke, and neither is something broken. [violationsFloor] when the
/// list of violations is longer than the one read (`5+ violations`).
String needsYouMeta({
  required int faults,
  required int requests,
  int violations = 0,
  bool violationsFloor = false,
}) => [
  if (faults > 0) faults == 1 ? '1 fault' : '$faults faults',
  if (violations > 0)
    violationsFloor
        ? '${Lexicon.floor(violations)} violations'
        : violations == 1
        ? '1 violation'
        : '$violations violations',
  if (requests > 0) requests == 1 ? '1 request' : '$requests requests',
].join(dotSeparator);

/// Needs you: every fault on its card with its way out, then the requests
/// that wait for an answer. The same list the Home's banner counts.
class _NeedsYouSection extends ConsumerStatefulWidget {
  const _NeedsYouSection();

  @override
  ConsumerState<_NeedsYouSection> createState() => _NeedsYouSectionState();
}

class _NeedsYouSectionState extends ConsumerState<_NeedsYouSection> {
  /// The cards as last drawn, for a card acted on to keep its place.
  List<FaultEntry> _shown = const [];

  @override
  Widget build(BuildContext context) {
    final decisions = ref.watch(dashboardDecisionsProvider);
    final answered = ref.watch(answeredRequestsProvider);
    final acted = ref.watch(actedFaultsProvider);
    final entries = faultEntriesOf(
      decisions.decisions.where((decision) => decision.isFault),
    );
    // A download acted on leaves the list as the queue is read again; its
    // note stays where its card was until Activity is read again.
    final present = {for (final entry in entries) entry.id};
    final cards = [...entries];
    for (final (index, entry) in _shown.indexed) {
      final key = entry.downloadKey;
      if (key != null &&
          acted.containsKey(key) &&
          !present.contains(entry.id)) {
        cards.insert(index.clamp(0, cards.length), entry);
      }
    }
    _shown = cards;
    final waiting = [
      for (final decision in decisions.decisions)
        if (decision.kind == DecisionKind.pendingRequest &&
            !answered.containsKey(decision.id))
          decision,
    ];
    final requests = [...waiting, for (final a in answered.values) ?a.decision];
    // Tracearr's unseen violations of severity high: blue, between the faults
    // and the requests, and never in the count of faults.
    final flagged = violationsOf(decisions.decisions);
    final coverage = decisions.coverage;
    // The import a Review sent reports itself here, first.
    final report = ref.watch(importReportProvider);
    if (cards.isEmpty &&
        requests.isEmpty &&
        flagged.count == 0 &&
        report == null) {
      final note = coverage.failed.isEmpty ? null : coverageNote(coverage);
      if (note == null) return const SizedBox.shrink();
      return ActivitySection(
        title: 'Needs you',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: HomeCoverageNote(note: note, coverage: coverage),
          ),
        ],
      );
    }
    final note = coverageNote(coverage);
    final scheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);
    final blue = statusToneColor(scheme, StatusTone.info, surface: room.slab);
    final meta = needsYouMeta(
      faults: entries.length,
      requests: waiting.length,
      violations: flagged.count,
      violationsFloor: flagged.floor,
    );
    final violationRows = violationRowsOf(flagged, blue);

    // On a tablet and a desktop each fault is one line with its remedy, and
    // the requests one line with Review: the whole card is on Needs you's
    // own page, where the count leads.
    final wide =
        AppBreakpoints.isDesktopShell(context) ||
        MediaQuery.sizeOf(context).width >= AppBreakpoints.touchSplit;
    if (wide &&
        (cards.isNotEmpty ||
            report != null ||
            waiting.isNotEmpty ||
            flagged.count > 0)) {
      return ActivitySection(
        title: 'Needs you',
        meta: meta.isEmpty ? null : meta,
        onOpen: meta.isEmpty
            ? null
            : () => context.push(ServiceRoutes.activityNeedsYou),
        openHint: 'Opens Needs you',
        children: [
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: HomeCoverageNote(note: note, coverage: coverage),
            ),
          if (report != null) ImportDoneCard(report: report),
          for (final (index, entry) in cards.indexed)
            NeedsYouCard.row(
              key: ValueKey(entry.id),
              entry: entry,
              divided: index > 0 || report != null,
            ),
          ...violationRows,
          if (waiting.isNotEmpty)
            RequestsWaitRow(
              requests: waiting,
              divided: cards.isNotEmpty || report != null,
              onReview: () => context.go(ActivityTab.requests.location),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActivitySection(
          title: 'Needs you',
          meta: meta.isEmpty ? null : meta,
          // The count leads to the page that holds every card whole.
          onOpen: meta.isEmpty
              ? null
              : () => context.push(ServiceRoutes.activityNeedsYou),
          openHint: 'Opens Needs you',
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: HomeCoverageNote(note: note, coverage: coverage),
              ),
            if (report != null) ImportDoneCard(report: report),
            for (final (index, entry) in cards.indexed)
              NeedsYouCard(
                key: ValueKey(entry.id),
                entry: entry,
                divided: index > 0 || report != null,
              ),
            if (cards.isEmpty && report == null) ...[
              ...violationRows,
              ...requestRowsOf(requests, answered, blue),
            ],
          ],
        ),
        if ((cards.isNotEmpty || report != null) &&
            (requests.isNotEmpty || flagged.count > 0))
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              0,
            ),
            child: ActivitySlab(
              children: [
                ...violationRows,
                ...requestRowsOf(requests, answered, blue),
              ],
            ),
          ),
      ],
    );
  }
}

/// Everyone's requests: the latest that move or arrived, who asked them, and
/// the way to all of them. Every Seerr's, as the Requests view reads them, so
/// the count on the link is the count there.
class _EveryonesRequestsSection extends ConsumerWidget {
  const _EveryonesRequestsSection();

  static const _title = "Everyone's requests";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reads = ref.watch(householdRequestsProvider(null));
    if (reads.isEmpty) return const SizedBox.shrink();
    final now = ref.watch(arrivalsClockProvider)();
    final household = householdRequestsOf(
      reads,
      now: now,
      gateOf: (id) => ref.watch(roleGateOfProvider(id)),
      named: reads.length > 1,
    );
    if (household.pending) return const SizedBox.shrink();
    final failures = [
      for (final source in household.failed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: BriefFailureLine.line(
            error: source.read.error!,
            service: ServiceKey.seerr,
            instanceId: source.instanceId,
            onRetry: () =>
                retryDashboardServices(ref, const [ServiceKey.seerr]),
          ),
        ),
    ];
    if (household.isEmpty) {
      if (failures.isEmpty) return const SizedBox.shrink();
      return ActivitySection(title: _title, children: failures);
    }
    final connectionOf = Map<SeerrRequest, String?>.identity()
      ..addEntries([
        for (final entry in household.rest)
          MapEntry(entry.mine.request, entry.connection),
      ]);
    final namesWhoOf = Map<SeerrRequest, bool>.identity()
      ..addEntries([
        for (final entry in household.rest)
          MapEntry(entry.mine.request, entry.namesWho),
      ]);
    final requests = MyRequests([
      for (final entry in household.rest) entry.mine,
    ]);
    final rows = everyonesLatest(requests);
    // Seerr's own count: a page or a Seerr that did not arrive leaves the
    // rows short of the household's requests, and their number is then a
    // floor, never the total. What is tallied over them (how many are being
    // fetched, how many were declined) is left unsaid rather than understated.
    final figure = '${household.total}${household.floor ? '+' : ''}';
    final summary = household.whole ? everyonesSummary(requests) : '';

    return ActivitySection(
      title: _title,
      meta: household.totalLabel,
      children: [
        ...failures,
        for (final (index, mine) in rows.indexed)
          EveryoneRequestRow(
            key: ValueKey(mine.request.id),
            mine: mine,
            now: now,
            divided: index > 0 || failures.isNotEmpty,
            connection: connectionOf[mine.request],
            namesWho: namesWhoOf[mine.request] ?? false,
          ),
        ActivitySlabLink(
          label: figure == '1' ? 'All requests' : 'All $figure requests',
          meta: summary.isEmpty ? null : summary,
          divided: rows.isNotEmpty || failures.isNotEmpty,
          onTap: () => context.go(ActivityTab.requests.location),
        ),
      ],
    );
  }
}

/// Who is watching, on every service that says so: the Home's rows.
class _WatchingNowSection extends ConsumerWidget {
  const _WatchingNowSection();

  static const _title = 'Watching now';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!HomeModule.nowPlaying.services.any(settings.isServiceConfigured)) {
      return const SizedBox.shrink();
    }
    final sessions = ref.watch(streamActivityProvider).value;
    if (sessions == null || sessions.isEmpty) return const SizedBox.shrink();
    final servers = {
      for (final row in sessions) row.service.title,
    }.join(dotSeparator);
    return ActivitySection(
      title: _title,
      meta: servers,
      semanticLabel: [
        _title,
        sessions.length == 1 ? '1 playing' : '${sessions.length} playing',
      ].join(', '),
      children: [
        for (final (index, row) in sessions.indexed)
          NowPlayingRow(
            key: ValueKey('${row.instanceId}-${row.session.id}'),
            row: row,
            divided: index > 0,
          ),
      ],
    );
  }
}

/// Downloads: what is moving and what is stuck, as their queues order them,
/// the stuck ones after, then on Downloads those stopped on purpose. On All
/// at most [limit], with the way to the rest.
class _DownloadsSection extends ConsumerWidget {
  const _DownloadsSection({this.limit});

  final int? limit;

  static const _title = 'Downloads';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(servicesQueueProvider);
    final queue = read.value;
    if (queue == null) {
      if (!read.hasError) return const SizedBox.shrink();
      return ActivitySection(
        title: _title,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: BriefFailureLine.line(
              error: read.error!,
              service: ServiceKey.radarr,
              onRetry: () => ref.invalidate(servicesQueueProvider),
            ),
          ),
        ],
      );
    }
    final coverage = queue.coverage;
    final moving = [
      for (final item in queue.items)
        if (item.isMoving) item,
    ];
    final stuck = [
      for (final item in queue.items)
        if (isDownloadFault(item.fault)) item,
    ];
    // Stopped on purpose: the backlog, not what is happening, so All leaves
    // them out and Downloads lists them last, in the neutral. Without them a
    // download stopped from its page had nowhere to be resumed from.
    final stopped = [
      for (final item in queue.items)
        if (item.fault == null && item.held) item,
    ];
    if (moving.isEmpty && stuck.isEmpty && (limit != null || stopped.isEmpty)) {
      // On All a quiet queue is the header's to say; Downloads says it in
      // its own place.
      if (limit != null) return const SizedBox.shrink();
      return const _NothingDownloading();
    }
    final cap = limit;
    final rows = cap == null
        ? [...moving, ...stuck, ...stopped]
        : downloadRowsOf(moving, stuck, limit: cap);
    final requests = ref.watch(downloadAskersProvider);
    final total = moving.length + stuck.length + stopped.length;
    final meta = [
      if (moving.isNotEmpty) '${coveredFigure(moving.length, coverage)} moving',
      // The stopped rows say so themselves, and a third count does not fit
      // beside the name on a phone.
      if (stuck.isNotEmpty) '${coveredFigure(stuck.length, coverage)} stuck',
    ].join(dotSeparator);
    final now = ref.watch(stallClockProvider)();
    final note = coverageNote(coverage);

    // The slab glows with its first download's light.
    final lead = [
      for (final item in rows)
        if ((item.posterUrl ?? '').isNotEmpty) item.posterUrl!,
    ].firstOrNull;
    return ActivitySection(
      title: _title,
      meta: meta,
      semanticLabel: [_title, spokenDownloadsSubtitle(meta)].join(', '),
      light: lead == null
          ? null
          : ref.watch(titleLightProvider(lead)).value?.art,
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: HomeCoverageNote(note: note, coverage: coverage),
          ),
        // A desktop window reads them as a table, the chosen one in the
        // inspector.
        if (AppBreakpoints.isDesktopShell(context))
          DownloadTable(items: rows, now: now, requests: requests)
        else
          for (final (index, item) in rows.indexed)
            ActivityDownloadRow(
              key: ValueKey('${item.service}-${item.instanceId}-${item.id}'),
              item: item,
              now: now,
              request: requestFor(item, requests),
              divided: index > 0,
            ),
        if (total > rows.length)
          ActivitySlabLink(
            label: 'All $total downloads',
            onTap: () => context.go(ActivityTab.downloads.location),
          ),
      ],
    );
  }
}

/// The household's requests the downloads are matched against, for who
/// asked for each (`requestFor`): the lens Seerr's list while one is set up,
/// as last read; nothing otherwise.
final downloadAskersProvider = Provider.autoDispose<List<SeerrRequest>>((ref) {
  final seerr = ref.watch(
    currentSettingsProvider.select(
      (settings) => settings.isServiceConfigured(ServiceKey.seerr),
    ),
  );
  if (!seerr) return const [];
  return ref.watch(requestsProvider).value ?? const [];
});

/// Up next: the downloads waiting their turn, in the order they will start,
/// with when where the client says. On All at most [limit].
class _UpNextSection extends ConsumerWidget {
  const _UpNextSection({this.limit});

  final int? limit;

  static const _title = 'Up next';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the queue's value: a reload keeps the previous value while it is
    // loading, so this rebuilds once per change, not on the loading frame too.
    final queue = ref.watch(
      servicesQueueProvider.select((async) => async.value),
    );
    if (queue == null) return const SizedBox.shrink();
    final queued = [
      for (final item in queue.items)
        if (item.isActive && item.queued) item,
    ];
    if (queued.isEmpty) return const SizedBox.shrink();
    final cap = limit;
    final rows = cap == null ? queued : queued.take(cap).toList();
    final count = coveredFigure(queued.length, queue.coverage);
    final meta = '$count queued';
    final now = ref.watch(stallClockProvider)();
    final requests = ref.watch(downloadAskersProvider);
    return ActivitySection(
      title: _title,
      meta: meta,
      semanticLabel: [_title, spokenCountPhrase(meta)].join(', '),
      children: [
        if (AppBreakpoints.isDesktopShell(context))
          DownloadTable.queued(items: rows, now: now, requests: requests)
        else
          for (final (index, item) in rows.indexed)
            ActivityDownloadRow.queued(
              key: ValueKey('${item.service}-${item.instanceId}-${item.id}'),
              item: item,
              now: now,
              request: requestFor(item, requests),
              divided: index > 0,
            ),
        if (queued.length > rows.length)
          ActivitySlabLink(
            label: 'All ${queued.length} queued',
            onTap: () => context.go(ActivityTab.downloads.location),
          ),
      ],
    );
  }
}

/// Downloads with nothing moving: the calm line, and when the last download
/// finished.
class _NothingDownloading extends ConsumerWidget {
  const _NothingDownloading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final last = lastDownloadFinished(
      lastImportOf(
        ref.watch(servicesArrivalsProvider).value?.entries ?? const [],
      ),
      now: ref.watch(arrivalsClockProvider)(),
    );
    return ActivitySection(
      title: 'Downloads',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nothing is downloading',
                style: AppType.row.copyWith(color: room.ink),
              ),
              if (last != null)
                Text(
                  last,
                  style: AppType.meta.copyWith(color: room.inkSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Finished today: what the libraries imported since midnight, newest
/// first, with the file each became.
class _FinishedTodaySection extends ConsumerWidget {
  const _FinishedTodaySection();

  static const _title = 'Finished today';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(servicesArrivalsProvider).value;
    if (read == null) return const SizedBox.shrink();
    final now = ref.watch(arrivalsClockProvider)();
    final today = finishedTodayOf(read.entries, now: now);
    if (today.isEmpty) return const SizedBox.shrink();
    final shown = today.take(_allFinishedLimit).toList(growable: false);
    final count = coveredFigure(today.length, read.coverage);
    return ActivitySection(
      title: _title,
      meta: count,
      semanticLabel: '$_title, $count',
      children: [
        for (final (index, entry) in shown.indexed)
          ActivityHistoryRow(
            key: ValueKey('${entry.instanceId}-${entry.id}'),
            entry: entry,
            divided: index > 0,
          ),
        if (today.length > shown.length)
          ActivitySlabLink(
            label: 'All of today in History',
            onTap: () => context.go(ActivityTab.history.location),
          ),
      ],
    );
  }
}

/// The week History draws: what was imported and what failed, one list
/// over the coverage of both reads.
final _weekProvider = FutureProvider.autoDispose<ArrHistory>((ref) async {
  final reads = await Future.wait([
    ref.watch(servicesArrivalsProvider.future),
    ref.watch(servicesFailuresSinceProvider.future),
  ]);
  return (
    entries: [for (final read in reads) ...read.entries],
    coverage: SourceCoverage.merge(reads.map((read) => read.coverage)),
  );
});

/// History: the last seven days, a section a day, newest first.
class _HistoryDays extends ConsumerWidget {
  const _HistoryDays();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(_weekProvider);
    final value = read.value;
    final room = CupolaRoom.of(context);
    if (value == null) {
      if (!read.hasError) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.section,
          AppSpacing.gutter,
          0,
        ),
        child: BriefFailureLine.line(
          error: read.error!,
          service: ServiceKey.radarr,
          onRetry: () {
            ref.invalidate(servicesArrivalsProvider);
            ref.invalidate(servicesFailuresSinceProvider);
          },
        ),
      );
    }
    final now = ref.watch(arrivalsClockProvider)();
    final days = activityDaysOf(
      value.entries,
      now: now,
      since: now.subtract(arrivalsWindow),
    );
    final note = coverageNote(value.coverage);
    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.section,
          AppSpacing.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note != null)
              HomeCoverageNote(note: note, coverage: value.coverage),
            Text(
              'Nothing finished in the last seven days',
              style: AppType.row.copyWith(color: room.ink),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              0,
            ),
            child: HomeCoverageNote(note: note, coverage: value.coverage),
          ),
        for (final day in days)
          ActivitySection(
            key: ValueKey(day.day),
            title: day.label,
            meta: '${day.entries.length}',
            children: [
              for (final (index, entry) in day.entries.indexed)
                ActivityHistoryRow(
                  key: ValueKey('${entry.instanceId}-${entry.id}'),
                  entry: entry,
                  divided: index > 0,
                ),
            ],
          ),
      ],
    );
  }
}

/// The page's foot: older history stays with each arr, under its History
/// tab, one row each.
class _HistoryFoot extends ConsumerWidget {
  const _HistoryFoot({this.blocklist = false});

  /// Whether the foot ends with the arrs' blocklist, as History's does.
  final bool blocklist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final services = _historyServices
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (services.isEmpty) return const SizedBox.shrink();
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.section,
        AppSpacing.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Older history stays in each service, under its History tab.',
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          ActivitySlab(
            children: [
              for (final (index, service) in services.indexed)
                ActivitySlabLink(
                  label: '${service.title} history',
                  divided: index > 0,
                  onTap: () => context.go(
                    '${ServiceRoutes.forService(service)}/history',
                  ),
                ),
              if (blocklist)
                ActivitySlabLink(
                  label: 'Blocklist',
                  meta: 'Releases the arrs will not take again',
                  onTap: () => context.push(ServiceRoutes.activityBlocklist),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
