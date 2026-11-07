import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/async_value_kept.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/desktop_content_well.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_agenda.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_month_grid.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_week_strip.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/media/presentation/media_facts_sections.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The calendar of everything the household's arrs date in the next thirty
/// days, at `/discover/calendar`: what this week holds, the week's strip,
/// the kinds as chips, then the agenda day by day.
///
/// On a page wide enough the thirty days are a grid of weeks instead
/// ([CalendarMonthGrid]), with the selected day read in a panel beside it;
/// the arrow keys move the day and Enter opens its first title.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  final _scroll = ScrollController();
  final _days = <DateTime, GlobalKey>{};

  /// The chip: one kind, or every kind.
  CalendarKind? _kind;

  /// The strip's page, 0 for the week today is in.
  int _week = 0;

  /// The day the strip has selected; today until another is tapped.
  DateTime? _selected;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _readAgain() {
    ref.invalidate(calendarDayProvider);
    ref.invalidate(calendarSourceProvider);
    ref.invalidate(activeRequestsForProvider);
    ref.invalidate(requesterCalendarProvider);
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  /// Selects [day], and brings its rows (or the next day's, when it has
  /// none) into view.
  void _select(DateTime day, List<CalendarEvent> events) {
    setState(() => _selected = day);
    final target = events
        .map((event) => event.day)
        .where((d) => !d.isBefore(day))
        .firstOrNull;
    final context = target == null ? null : _days[target]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.15,
      duration: _reduceMotion ? Duration.zero : AppAnimation.durationMd,
      curve: AppAnimation.standardCurve,
    );
  }

  void _today(CalendarWindow window) {
    setState(() {
      _week = 0;
      _selected = window.start;
    });
    if (!_scroll.hasClients) return;
    if (_reduceMotion) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(
        0,
        duration: AppAnimation.durationMd,
        curve: AppAnimation.standardCurve,
      );
    }
  }

  void _open(CalendarEvent event) => openCalendarEvent(context, event);

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final requester = ref.watch(audienceProvider) == Audience.requester;
    final calendar = ref.watch(calendarProvider);
    final value = calendar.value;
    final now = ref.watch(calendarClockProvider)();
    final window = value?.window ?? CalendarWindow.from(now);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = FloatingNavBarMetrics.getScrollViewBottomPadding(context);

    if (!ref.watch(hasCalendarProvider)) {
      return AmbientScaffold(
        body: MediaPinnedPlates(
          inset: AppSpacing.lg,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              top + AppSpacing.md,
              AppSpacing.lg,
              bottom,
            ),
            children: [
              // The back plate floats here, pinned (`MediaPinnedPlates`).
              const SizedBox(height: MediaPinnedPlates.reserve),
              const SizedBox(height: AppSpacing.xxl),
              AppEmptyState(
                icon: Icons.calendar_month_rounded,
                title: 'Nothing to put on a calendar yet',
                message:
                    'Set up Radarr, Sonarr, Lidarr or Readarr to see what '
                    'comes out and airs in the next ${CalendarWindow.days} '
                    'days.',
                action: FilledButton(
                  // `go`: Connections lives in the Settings branch.
                  onPressed: () =>
                      context.go(ServiceRoutes.settingsConnections),
                  child: const Text('Set up a service'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final events = value?.of(_kind) ?? const <CalendarEvent>[];
    final all = value?.events ?? const <CalendarEvent>[];
    final digest = CalendarDigest.of(all, now);
    final art = digest.lead?.poster;
    final light = art == null || art.headers != null || art.url.isEmpty
        ? null
        : ref.watch(titleLightProvider(art.url)).value;
    final selected = _selected ?? window.start;
    final weeks = calendarWeeks(window);
    final week = _week.clamp(0, weeks.length - 1);
    final days = calendarWeekDays(weeks[week]);
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final event in events) {
      (byDay[event.day] ??= []).add(event);
    }

    final silences = <Widget>[
      if (value != null)
        for (final silence in value.silent)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _SilentSource(
                silence: silence,
                onRetry: () => ref.invalidate(
                  calendarSourceProvider((
                    service: silence.service,
                    connectionId: silence.connectionId,
                    from: window.start,
                  )),
                ),
              ),
            ),
          ),
    ];
    Widget head({bool wide = false}) => SliverPadding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        top + AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      sliver: SliverToBoxAdapter(
        child: _Head(
          calendar: value,
          digest: digest,
          loading: calendar.isLoading && value == null,
          requester: requester,
          onToday: () => _today(window),
          wide: wide,
        ),
      ),
    );
    final kinds = value == null
        ? null
        : SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: _Kinds(
                calendar: value,
                requester: requester,
                selected: _kind,
                onSelected: (kind) => setState(() => _kind = kind),
              ),
            ),
          );
    // Only the requester's calendar fails whole: her Seerr is its one
    // source.
    final unread = value != null
        ? null
        : SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: calendar.error != null
                  ? BriefFailureLine.line(
                      error: calendar.error,
                      onRetry: _readAgain,
                      service: ServiceKey.seerr,
                    )
                  : AppSkeleton.listRows(count: 5),
            ),
          );
    final foot = <Widget>[
      if (value != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              requester
                  ? 'Dates are for ${regionName(ref.watch(regionProvider))}. '
                        'Episodes have a date here, not a time.'
                  : _timesNote(value.kinds),
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
          ),
        ),
      if (watchSeerrConfigured(ref))
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            child: DiscoverCarousel(
              title: requester
                  ? 'Coming out, not on the server'
                  : 'Coming out, not on your server',
              subtitle: requester
                  ? 'Most popular first. Ask for one and you’ll be told when '
                        'it’s ready.'
                  : 'From Seerr, most popular first.',
              sectionId: 'coming_out',
              // What is on the calendar already is not coming out for you.
              items: ref
                  .watch(comingOutProvider)
                  .whenDataKept(
                    (items) => [
                      for (final item in items)
                        if (!all.any(
                          (event) =>
                              event.tmdbId == item.id &&
                              (event.kind == CalendarKind.movie) ==
                                  (item.mediaType == 'movie'),
                        ))
                          item,
                    ],
                  ),
              onRetry: () => ref.invalidate(comingSoonProvider),
              metaOf: (item) => _comingOut(item, now),
            ),
          ),
        ),
      SliverToBoxAdapter(child: SizedBox(height: bottom + AppSpacing.xl)),
    ];

    // The phone's page: the strip a week at a time, the agenda under it.
    List<Widget> agenda() => [
      head(),
      ...silences,
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
            0,
          ),
          child: _WeekPager(
            index: week,
            count: weeks.length,
            monday: weeks[week],
            onPage: (index) => setState(() => _week = index),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        sliver: SliverToBoxAdapter(
          child: CalendarWeekStrip(
            days: days,
            now: now,
            window: window,
            dots: {
              for (final day in days) day: ?calendarDayDot(byDay[day] ?? []),
            },
            selected: selected,
            onSelect: (day) => _select(day, events),
            countOf: (day) => byDay[day]?.length ?? 0,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          0,
        ),
        sliver: SliverToBoxAdapter(
          child: Semantics(
            liveRegion: true,
            child: Text(
              _selectedLine(selected, byDay, events, now),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ),
        ),
      ),
      ?kinds,
      if (unread != null)
        unread
      else
        for (final entry in calendarAgenda(events, window))
          SliverToBoxAdapter(
            child: switch (entry) {
              AgendaDay(:final day, events: final rows) => CalendarDayGroup(
                key: _days.putIfAbsent(day, GlobalKey.new),
                day: day,
                now: now,
                highlighted: day == selected && _selected != null,
                children: [
                  for (final event in rows)
                    requester
                        ? CalendarRow.requester(
                            event: event,
                            now: now,
                            onTap: event.target == null
                                ? null
                                : () => _open(event),
                          )
                        : CalendarRow(
                            event: event,
                            now: now,
                            onTap: event.target == null
                                ? null
                                : () => _open(event),
                          ),
                ],
              ),
              AgendaGap(:final until) => CalendarQuietLine.until(until),
              AgendaEnd() => const CalendarQuietLine.end(),
            },
          ),
      ...foot,
    ];

    // A window that lays the weeks side by side: the thirty days as a grid,
    // the selected day read beside it.
    List<Widget> grid() => [
      head(wide: true),
      ...silences,
      ?kinds,
      unread ??
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: CalendarMonthGrid(
                weeks: weeks,
                now: now,
                window: window,
                byDay: byDay,
                selected: selected,
                onSelect: (day) => setState(() => _selected = day),
              ),
            ),
          ),
      ...foot,
    ];

    Widget scroll(List<Widget> slivers, {double side = 0}) => RefreshIndicator(
      edgeOffset: top,
      onRefresh: () async {
        _readAgain();
        await ref.read(calendarProvider.future);
      },
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: side),
            sliver: SliverMainAxisGroup(slivers: slivers),
          ),
        ],
      ),
    );

    return AmbientScaffold(
      // The next release lights the page, as it lit the band that opened it.
      accent: light?.light,
      art: light?.art,
      accentDuration: AppAnimation.light,
      // The light is the window's, not the well's: it is drawn full-bleed
      // and the page keeps the well inside it.
      contentWell: false,
      body: Stack(
        children: [
          DesktopContentWell(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth < _gridWidth) {
                  // Wider than a phone, the agenda keeps a phone's measure.
                  final side = ((box.maxWidth - AppBreakpoints.readingWell) / 2)
                      .clamp(0.0, double.infinity);
                  return MediaPinnedPlates(
                    inset: side + AppSpacing.lg,
                    trailing: _TodayPlate(onTap: () => _today(window)),
                    child: scroll(agenda(), side: side),
                  );
                }
                return Focus(
                  autofocus: true,
                  onKeyEvent: (node, key) => _onKey(key, window, byDay),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: scroll(grid())),
                      SizedBox(
                        width: _panelWidth,
                        child: _DayPanel(
                          day: selected,
                          now: now,
                          events: value == null ? null : events,
                          requester: requester,
                          top: top,
                          bottom: bottom,
                          onOpen: _open,
                          onSelect: (day) => setState(() => _selected = day),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Positioned(top: 0, left: 0, right: 0, child: StatusBarScrim()),
        ],
      ),
    );
  }

  /// The page's width from which the thirty days are a grid with the
  /// selected day beside it: seven days of about ninety points, their gaps
  /// and margins, and the panel. A tablet on its side and a desktop window
  /// clear it; below it the agenda reads as on a phone.
  static const double _gridWidth = 1040;

  /// The panel beside the grid: a phone's column, as a title's pane is.
  static const double _panelWidth = 340;

  /// Arrow keys move the selected day within the thirty, a week at a time
  /// up and down; Enter opens its first title.
  KeyEventResult _onKey(
    KeyEvent key,
    CalendarWindow window,
    Map<DateTime, List<CalendarEvent>> byDay,
  ) {
    if (key is! KeyDownEvent && key is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Read now, not from the frame that built the handler: a held key
    // repeats faster than frames.
    final selected = _selected ?? window.start;
    final pressed = key.logicalKey;
    final step = pressed == LogicalKeyboardKey.arrowLeft
        ? -1
        : pressed == LogicalKeyboardKey.arrowRight
        ? 1
        : pressed == LogicalKeyboardKey.arrowUp
        ? -7
        : pressed == LogicalKeyboardKey.arrowDown
        ? 7
        : null;
    if (step != null) {
      final next = DateTime(selected.year, selected.month, selected.day + step);
      if (window.contains(next)) setState(() => _selected = next);
      return KeyEventResult.handled;
    }
    if (pressed == LogicalKeyboardKey.enter ||
        pressed == LogicalKeyboardKey.numpadEnter) {
      final first = byDay[selected]
          ?.where((event) => event.target != null)
          .firstOrNull;
      if (first == null) return KeyEventResult.ignored;
      _open(first);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// What the selected day holds, under the strip: `Fri 2 Oct · Sintel
  /// (Anniversary Edition), album · Cosmos Laundromat S3 E1 at 21:00`; an
  /// empty day names the next one.
  String _selectedLine(
    DateTime day,
    Map<DateTime, List<CalendarEvent>> byDay,
    List<CalendarEvent> events,
    DateTime now,
  ) {
    final name = calendarDayName(day, now) == 'Today'
        ? 'Today'
        : calendarShortDate(day);
    final rows = byDay[day];
    if (rows != null && rows.isNotEmpty) {
      return [
        name,
        for (final event in rows) calendarEventShort(event),
      ].join(dotSeparator);
    }
    final next = events.where((event) => event.day.isAfter(day)).firstOrNull;
    final nothing = name == 'Today' ? 'Nothing today' : 'Nothing on $name';
    return next == null
        ? nothing
        : '$nothing\u00A0· next on ${calendarShortDate(next.day)}';
  }

  /// When a title of the last shelf comes out: a movie `Out 14 Oct`, a new
  /// series `From 1 Oct`.
  static String? _comingOut(MediaPreview item, DateTime now) {
    final day = arrCalendarDate(item.releaseDate);
    if (day == null) return null;
    final date = formatDayMonth(day, now: now);
    return item.mediaType == 'tv' ? 'From $date' : 'Out $date';
  }

  /// When the rows' times are: the note under the agenda.
  static String _timesNote(Set<CalendarKind> kinds) {
    final dated = [
      for (final kind in const [
        CalendarKind.movie,
        CalendarKind.album,
        CalendarKind.book,
      ])
        if (kinds.contains(kind)) kind.plural,
    ];
    final datedWords = dated.isEmpty
        ? null
        : '${_capital(joinWithAnd(dated))} have a date, not a time.';
    return [
      if (kinds.contains(CalendarKind.episode))
        'Episode times are when they air, in your time zone.',
      ?datedWords,
    ].join(' ');
  }

  static String _capital(String words) =>
      words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// The selected day beside the grid: its name, what it holds in a
/// sentence, its rows, the rest of a season it airs, the way to its first
/// title, and the next day that has something.
class _DayPanel extends StatelessWidget {
  const _DayPanel({
    required this.day,
    required this.now,
    required this.events,
    required this.requester,
    required this.top,
    required this.bottom,
    required this.onOpen,
    required this.onSelect,
  });

  final DateTime day;
  final DateTime now;

  /// Every day's things under the chip, in the agenda's order; null while
  /// the calendar is read.
  final List<CalendarEvent>? events;
  final bool requester;
  final double top;
  final double bottom;
  final ValueChanged<CalendarEvent> onOpen;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final events = this.events;
    final rows = [
      for (final event in events ?? const <CalendarEvent>[])
        if (event.day == day) event,
    ];
    final first = rows.where((event) => event.target != null).firstOrNull;
    final next = events?.where((event) => event.day.isAfter(day)).firstOrNull;
    final seasons = <CalendarEvent>[];
    for (final row in rows) {
      if (seasons.any(
        (seen) => seen.title == row.title && seen.season == row.season,
      )) {
        continue;
      }
      if (calendarLaterInSeason(row, events!).isNotEmpty) seasons.add(row);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: room.hair)),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          top + AppSpacing.md,
          AppSpacing.lg,
          bottom + AppSpacing.xl,
        ),
        children: [
          Text(
            'Selected day',
            style: AppType.caption.copyWith(color: room.inkTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: calendarDayName(day, now),
                    style: AppType.section.copyWith(color: room.ink),
                  ),
                  TextSpan(
                    text: ' ${calendarDayDate(day, now)}',
                    style: AppType.section.copyWith(color: room.inkTertiary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (events == null)
            AppSkeleton.listRows(count: 2)
          else ...[
            Text(
              calendarDaySummary(rows),
              style: AppType.body.copyWith(color: room.inkSecondary),
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: room.slab,
                  borderRadius: BorderRadius.circular(AppRadius.group),
                  border: Border.all(color: room.hair),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, event) in rows.indexed) ...[
                      if (index > 0) Divider(height: 1, color: room.hair),
                      requester
                          ? CalendarRow.requester(
                              event: event,
                              now: now,
                              onTap: event.target == null
                                  ? null
                                  : () => onOpen(event),
                            )
                          : CalendarRow(
                              event: event,
                              now: now,
                              onTap: event.target == null
                                  ? null
                                  : () => onOpen(event),
                            ),
                    ],
                  ],
                ),
              ),
            ],
            for (final episode in seasons) ...[
              const SizedBox(height: AppSpacing.md),
              _LaterInSeason(
                episode: episode,
                later: calendarLaterInSeason(episode, events),
                now: now,
              ),
            ],
            if (first != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => onOpen(first),
                child: Text(
                  switch (first.target) {
                    CalendarShelfTarget(:final service) =>
                      'Open ${first.byline ?? first.title} in ${service.title}',
                    _ => 'Open ${first.title}',
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (next != null) ...[
              const SizedBox(height: AppSpacing.md),
              _NextDay(event: next, onTap: () => onSelect(next.day)),
            ],
            if (AppBreakpoints.isDesktopShell(context)) ...[
              const SizedBox(height: AppSpacing.xl),
              ExcludeSemantics(
                child: Text(
                  'Arrow keys move the day. Enter opens its first title.',
                  style: AppType.caption.copyWith(color: room.inkTertiary),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The rest of a season an episode of the day belongs to, inside the
/// thirty days: `Cosmos Laundromat · season 3`, how many more, and when.
class _LaterInSeason extends StatelessWidget {
  const _LaterInSeason({
    required this.episode,
    required this.later,
    required this.now,
  });

  final CalendarEvent episode;
  final List<CalendarEvent> later;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final count = later.length == 1
        ? '1 more episode'
        : '${later.length} more episodes';
    return Semantics(
      container: true,
      label:
          '${episode.title} season ${episode.season}, $count in the next '
          '${CalendarWindow.days} days: '
          '${[for (final e in later) 'episode ${e.episode} ${spokenDay(e.day, now)}'].join(', ')}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: room.slab,
            borderRadius: BorderRadius.circular(AppRadius.group),
            border: Border.all(color: room.hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${episode.title}\u00A0· season ${episode.season}',
                style: AppType.label.copyWith(color: room.ink),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '$count in the next ${CalendarWindow.days} days',
                style: AppType.meta.copyWith(color: room.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final event in later)
                    Text(
                      [
                        if (event.episode case final number?)
                          formatEpisodeOrdinal(number),
                        calendarShortDate(event.day),
                      ].join(' '),
                      style: AppType.caption.copyWith(color: room.inkSecondary),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The next day that has something, as a way to it: `Next day · Sun 4
/// Oct` over its first thing.
class _NextDay extends StatelessWidget {
  const _NextDay({required this.event, required this.onTap});

  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final date = calendarShortDate(event.day);
    final what = calendarEventShort(event);
    return Semantics(
      container: true,
      button: true,
      label: 'Next day, $date, $what',
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.group),
              border: Border.all(color: room.hair),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next day\u00A0· $date',
                        style: AppType.caption.copyWith(
                          color: room.inkTertiary,
                        ),
                      ),
                      Text(
                        what,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label.copyWith(color: room.ink),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: room.inkSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The way back and to today, the name, what this week holds, and who said
/// so.
class _Head extends StatelessWidget {
  const _Head({
    required this.calendar,
    required this.digest,
    required this.loading,
    required this.requester,
    required this.onToday,
    this.wide = false,
  });

  final LibraryCalendar? calendar;
  final CalendarDigest digest;
  final bool loading;
  final bool requester;
  final VoidCallback onToday;

  /// Beside the grid the name sits on the plates' line, so the weeks start
  /// higher and all five fit a desktop window.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final stacked = mediaStacked(context);
    final calendar = this.calendar;
    final answer = digest.answer(
      countKnown: calendar != null && calendar.silent.isEmpty,
      requester: requester,
    );
    final name = Semantics(
      header: true,
      child: Text(
        'Calendar',
        style: (stacked ? AppType.room : AppType.screen).copyWith(
          color: room.ink,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wide)
          Row(
            children: [
              const MediaBackPlate(),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: name),
              _TodayPlate(onTap: onToday),
            ],
          )
        else ...[
          // Back and Today float here, pinned over the agenda
          // (`MediaPinnedPlates`).
          const SizedBox(height: MediaPinnedPlates.reserve),
          const SizedBox(height: AppSpacing.md),
          name,
        ],
        const SizedBox(height: AppSpacing.sm),
        if (loading)
          AppSkeleton.listRows(count: 1)
        else if (calendar != null) ...[
          Text.rich(
            TextSpan(
              children: [
                if (answer.figure.isNotEmpty)
                  TextSpan(
                    text: '${answer.figure} ',
                    style: AppType.figureSmall.copyWith(color: room.ink),
                  ),
                TextSpan(text: answer.words),
                if (answer.name case final name?) ...[
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: name,
                    style: AppType.body
                        .weight(FontWeight.w600)
                        .copyWith(color: room.ink),
                  ),
                ],
                TextSpan(text: answer.tail),
              ],
            ),
            style: AppType.body.copyWith(color: room.inkSecondary),
          ),
          if (requester || calendar.answered.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              requester
                  ? 'Your requests on their way\u00A0· checked at '
                        '${formatClockTime(calendar.readAt)}'
                  : 'From ${joinWithAnd(calendar.answered)} at '
                        '${formatClockTime(calendar.readAt)}',
              style: AppType.caption.copyWith(color: room.inkTertiary),
            ),
          ],
        ],
      ],
    );
  }
}

/// `Today`, a plate like the way back: the strip back to this week, the
/// agenda back to its top.
class _TodayPlate extends StatelessWidget {
  const _TodayPlate({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      container: true,
      button: true,
      label: 'Today',
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: room.fillControl,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: room.edge),
            ),
            child: Text(
              'Today',
              style: AppType.label.copyWith(color: room.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// The week's name and its days, between the arrows that page the strip.
class _WeekPager extends StatelessWidget {
  const _WeekPager({
    required this.index,
    required this.count,
    required this.monday,
    required this.onPage,
  });

  final int index;
  final int count;
  final DateTime monday;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    Widget arrow(IconData icon, String label, int? to) => IconButton(
      onPressed: to == null ? null : () => onPage(to),
      tooltip: label,
      style: IconButton.styleFrom(visualDensity: VisualDensity.standard),
      icon: Icon(icon, color: to == null ? room.inkDisabled : room.ink),
    );
    return Row(
      children: [
        arrow(
          Icons.chevron_left_rounded,
          'Week before',
          index > 0 ? index - 1 : null,
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(
              children: [
                Text(
                  calendarWeekName(index),
                  style: AppType.label.copyWith(color: room.ink),
                ),
                Text(
                  calendarWeekRange(monday),
                  style: AppType.caption.copyWith(color: room.inkTertiary),
                ),
              ],
            ),
          ),
        ),
        arrow(
          Icons.chevron_right_rounded,
          'Week after',
          index < count - 1 ? index + 1 : null,
        ),
      ],
    );
  }
}

/// The kinds as chips, a silent kind's with a red dot, and one line for the
/// kinds the household has no service for.
class _Kinds extends StatelessWidget {
  const _Kinds({
    required this.calendar,
    required this.requester,
    required this.selected,
    required this.onSelected,
  });

  final LibraryCalendar calendar;

  /// The requester reads no service's name, so no line about the kinds no
  /// service of hers dates.
  final bool requester;
  final CalendarKind? selected;
  final ValueChanged<CalendarKind?> onSelected;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final kinds = [
      for (final kind in CalendarKind.values)
        if (calendar.kinds.contains(kind)) kind,
    ];
    final missing = [
      for (final kind in CalendarKind.values)
        if (!calendar.kinds.contains(kind)) kind,
    ];
    final silent = calendar.silentKinds;
    final values = <CalendarKind?>[null, ...kinds];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kinds.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: SelectionPills.gutter,
            child: Row(
              children: [
                for (final kind in values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SelectionPill(
                          label: kind?.chip ?? 'All',
                          selected: kind == selected,
                          onTap: () => onSelected(kind),
                        ),
                        if (silent.contains(kind))
                          Positioned(
                            top: 6,
                            right: 2,
                            child: ExcludeSemantics(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusToneColor(
                                    scheme,
                                    StatusTone.error,
                                    surface: room.ground,
                                  ),
                                  border: Border.all(color: room.ground),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (!requester &&
            missing.isNotEmpty &&
            missing.length < CalendarKind.values.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              '${_capital(joinWithAnd([for (final kind in missing) kind.plural]))} '
              'appear here when '
              '${joinWithAnd([for (final kind in missing) kind.service.title])} '
              '${missing.length == 1 ? 'is' : 'are'} set up.',
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
          ),
      ],
    );
  }

  static String _capital(String words) =>
      words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// A connection whose calendar did not arrive: what may be missing and
/// why, once, with the remedy its cause names and Retry where asking again
/// can help.
class _SilentSource extends ConsumerWidget {
  const _SilentSource({required this.silence, required this.onRetry});

  final CalendarSilence silence;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(roleGateOfProvider(silence.connectionId));
    if (!gate.namesService(silence.service)) {
      return BriefFailureLine.line(
        error: silence.error,
        onRetry: onRetry,
        service: silence.service,
        instanceId: silence.connectionId,
      );
    }
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reason = classifyConnectionFailure(silence.error);
    final gateway = accessGatewayOf(silence.error);
    final kind = CalendarKind.of(silence.service);
    final headline = failureHeadline(
      reason,
      subject: silence.name,
      gateway: gateway,
    );
    final remedy = FailureRemedy.forReason(
      silence.service,
      reason,
      instanceId: silence.connectionId,
      gateway: gateway,
    );
    final verbs = failureLineVerbs(
      context,
      remedy: remedy,
      fault: failureTone(reason) == StatusTone.warning,
      onRetry: onRetry,
      subject: silence.name,
    );
    final sentence = Row(
      children: [
        Icon(
          failureIcon(reason),
          size: 18,
          color: statusToneColor(scheme, failureTone(reason)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            [
              headline,
              if (kind != null) '${kind.plural} may be missing here',
            ].join(dotSeparator),
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        ),
      ],
    );
    return verbs.length == 1 && remedy == null
        ? Row(
            children: [
              Expanded(child: sentence),
              const SizedBox(width: AppSpacing.sm),
              verbs.single,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sentence,
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                children: verbs,
              ),
            ],
          );
  }
}

/// Opens what a calendar row is about: a movie's or a series' page under the
/// tab the row is in, an artist's or an author's shelf under its service.
void openCalendarEvent(BuildContext context, CalendarEvent event) {
  switch (event.target) {
    case CalendarMediaTarget(:final key, :final connectionId):
      context.openMedia(key, focus: connectionId);
    case CalendarShelfTarget(:final service, :final connectionId, :final id):
      // A person's shelf lives under its service's tab, in another branch.
      context.go(switch (service) {
        ServiceKey.readarr => ServiceRoutes.readarrAuthor(
          id,
          instanceId: connectionId,
        ),
        _ => ServiceRoutes.lidarrArtist(id, instanceId: connectionId),
      });
    case null:
      break;
  }
}
