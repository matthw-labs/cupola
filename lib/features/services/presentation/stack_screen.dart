import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/nothing_set_up.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_alert_band.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/core/widgets/screen_title.dart';

/// The Stack tab: every service, its light, and the way into its room.
///
/// It was the Dashboard, the app's first tab, until the Home of modules took
/// that place: what needs you, what is moving and what arrived went to the
/// Home, and this page kept the fleet. Its own redesign is the Stack surface's.
/// Settings opens from its gear, the one place the operator's bar has no tab
/// for.
class StackScreen extends ConsumerWidget {
  const StackScreen({super.key});

  /// How stale the stack may be before returning to it earns a refetch.
  ///
  /// Generous on purpose: this screen reads every service, so a return is
  /// expensive and the figures it shows are not second-by-second. Two minutes is
  /// long enough that tab-hopping never triggers it and short enough that a
  /// screen left over lunch is not believed.
  static const _staleAfter = Duration(minutes: 2);

  /// How old the four arrs' libraries may be before a silent return reads
  /// them again.
  ///
  /// They are the heaviest answers the app asks for (`GET /movie` alone can be
  /// several megabytes), and on this page they only count: Movies, Missing,
  /// Episodes, figures that move a few times a day. A return every two minutes
  /// re-reads the queues, the sessions and every probe; the libraries wait for
  /// a pull, a re-tap, or this.
  static const _librariesStaleAfter = Duration(minutes: 15);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    ref.listen<int>(navigationRefreshProvider(NavigationSection.stack), (
      previous,
      next,
    ) {
      _invalidateStack(ref);
    });

    // The libraries this page opens over have just been read, by it or by the
    // Home: that is when their clock starts.
    final clock = ref.read(pollClockProvider);
    if (!clock.hasRun(_librariesClockId)) clock.note(_librariesClockId);

    final settings = ref.watch(currentSettingsProvider);
    // The one live figure on this page is what plays, and it sits in the
    // sessions cache of the services that say who is playing, which lives as
    // long as the app: the Home may have filled it a while ago. Each
    // connection's sessions poll runs
    // here as in its room, reading again at once over an answer this page did
    // not just read and every 15 s after, so a row never says `0 streaming`
    // over a playback that has started. The two-minute return refresh below
    // stays for everything else.
    for (final service in sessionServices) {
      for (final instance in settings.configuredInstancesOf(service)) {
        ref.watchWhileLive(
          context,
          streamSessionsPollProvider((
            service: service,
            instanceId: instance.id,
          )),
        );
      }
    }
    // A Seerr account that signed out is a connection somebody set up: the
    // stack is not empty, it has a step to take.
    final allUnconfigured = ServiceKey.values.every(
      (s) => !settings.hasServiceConnection(s),
    );

    return RefreshOnReturn(
      id: 'services.stack',
      maxAge: _staleAfter,
      // The re-tap's invalidations, silent because nobody pressed anything,
      // and without the libraries until they are old enough: see
      // [_librariesStaleAfter].
      onStale: () => _invalidateStack(
        ref,
        libraries:
            clock.timeUntilDue(_librariesClockId, _librariesStaleAfter) ==
            Duration.zero,
      ),
      child: AmbientScaffold(
        // No accent passed: the room on this screen is lit by the neutral lamp,
        // like every room with no artwork. The fleet below is eighteen
        // services, and each is named by its mark and its title, never a hue.
        body: allUnconfigured
            ? NothingSetUpView(bottomPadding: bottomPadding)
            : Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: () => _refreshStack(ref),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(bottom: bottomPadding),
                      //  * the header is one line of StackHealth under the
                      //    title, and it is neutral when clear: no permanent
                      //    green
                      //  * the band is absent unless something stopped
                      //    answering
                      //  * the stack is the instrument and the launcher
                      children: const [
                        _StackHeadline(),
                        ServicesAlertBand(),
                        ServiceMatrix(),
                      ],
                    ),
                  ),
                  // The fleet passes under the clock, as Activity's rows do,
                  // and fades into the room there instead of colliding with it.
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
}

/// The title and the one line under it, in the shape Activity's header has:
/// the page's name as the screen title, its one control beside it, and the
/// line that says how the fleet stands.
///
/// The title is `Stack`, said once. It used to be an app bar saying `Stack`
/// over an h1 saying `Your stack`: two headings for one screen.
///
/// The sentence is [StackHealth]'s, counting **connections folded per
/// service** rather than the lensed summary, so a Radarr with one of its two
/// connections dark reads as *degraded* rather than inheriting whichever answer
/// the lens happened to be pointing at. Its age is redrawn every minute: an age
/// that stays where it was when the page was built is a claim that stops being
/// true while the page is open.
class _StackHeadline extends ConsumerStatefulWidget {
  const _StackHeadline();

  @override
  ConsumerState<_StackHeadline> createState() => _StackHeadlineState();
}

class _StackHeadlineState extends ConsumerState<_StackHeadline> {
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final health = ref.watch(stackHealthProvider);
    final sentence = health.sentenceAt(DateTime.now());

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        MediaQuery.paddingOf(context).top + AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ScreenTitle('Stack'),
                ),
              ),
              Tooltip(
                message: 'Settings',
                child: MediaPlate(
                  label: 'Settings',
                  icon: Icons.settings_outlined,
                  onTap: () => openSettings(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Semantics(
              label: spokenFromDotted(sentence),
              excludeSemantics: true,
              child: Text(
                sentence,
                // Neutral, always: no permanent green. A stack that is entirely
                // healthy says so in words and spends no colour on it; the tone
                // this page has to spare belongs to the one card that is not.
                style: AppType.body.copyWith(color: room.inkSecondary),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _HealthStrip(health: health),
        ],
      ),
    );
  }
}

/// The fleet at a glance: one segment a service, lit by how it stands,
/// in the order the sentence above counts them: answering, at fault, signed
/// out, silent, still asked, and the ones nobody set up as empty outlines.
/// The sentence is what a screen reader hears; the strip says nothing more.
class _HealthStrip extends StatelessWidget {
  const _HealthStrip({required this.health});

  final StackHealth health;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    Color tone(StatusTone tone) => statusToneColor(scheme, tone);
    final clean = (health.answering - health.faulted - health.degraded).clamp(
      0,
      health.configured,
    );
    final segments = <Color?>[
      for (var i = 0; i < clean; i++) tone(StatusTone.success),
      // A fault, a disagreement and a silence that timed out are all amber:
      // the host is there.
      for (var i = 0; i < health.faulted + health.degraded + health.stuck; i++)
        tone(StatusTone.warning),
      for (var i = 0; i < health.signedOut; i++) tone(StatusTone.info),
      for (var i = 0; i < health.unreachable; i++) tone(StatusTone.error),
      for (var i = 0; i < health.checking + health.onlyAtHome; i++)
        room.fillStrong,
      for (var i = 0; i < health.notSetUp; i++) null,
    ];
    if (segments.isEmpty) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: SizedBox(
        height: 6,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, color) in segments.indexed) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color?.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(3),
                    border: color == null ? Border.all(color: room.edge) : null,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pull-to-refresh: drop everything the screen shows, then hold the spinner
/// until the slowest of it has actually come back.
///
/// `onRefresh` used to be `() async => _invalidateStack(ref)`, whose
/// future completes on the same microtask, so the indicator retracted while
/// thirteen summaries and three merged lists were still in flight. A control-room
/// screen that says "done" before it has re-read anything is worse than one with
/// no refresh: the user reads the stale figure as the fresh one.
///
/// Failures are swallowed rather than propagated. Every source here already
/// degrades to `[]`/offline and paints its own state; letting one rejection out
/// would abort `Future.wait` and retract the spinner early: the exact bug being
/// fixed, restored by the unhappy path.
Future<void> _refreshStack(WidgetRef ref) async {
  _invalidateStack(ref);

  Future<void> settle(Future<Object?> pending) async {
    try {
      await pending;
    } catch (_) {}
  }

  await Future.wait([
    for (final service in ServiceKey.values)
      settle(ref.read(serviceSummaryProvider(service).future)),
  ]);
}

/// The [PollClock] key for the age of the arrs' libraries on this page.
const _librariesClockId = 'services.stack.libraries';

/// Invalidates what the stack reads; [libraries] says whether the arrs' whole
/// libraries are among it ([serviceKpiLibrarySources]). Only a silent return
/// leaves them out.
void _invalidateStack(WidgetRef ref, {bool libraries = true}) {
  for (final service in ServiceKey.values) {
    ref.invalidate(serviceSummaryProvider(service));
    // The matrix's live line is the reason to pull-to-refresh this screen, and
    // it was the one thing refresh did not touch: the KPI providers were only
    // ever invalidated from the individual service pages.
    ref.invalidate(serviceKpiProvider(service));
    // The stack card's two figures. Reduced from the same KPI list, but its own
    // `autoDispose` family entry; invalidating only the single-figure provider
    // left the cards showing the figures from before the pull.
    ref.invalidate(serviceSignalPairProvider(service));
    // And the fleet's, for the multi-connection cards. Its own family entry
    // again, and it reads every connection rather than the lens, so a refresh
    // that stopped at the lens left a folded card stale by N-1 servers.
    ref.invalidate(foldedServiceKpisProvider(service));
    ref.invalidate(foldedServiceSignalPairProvider(service));
  }
  // The per-connection leg, invalidated as a whole family: it is keyed on the
  // connection, and the loop above only knows service keys.
  ref.invalidate(serviceKpiForProvider);
  // And the reachability probe itself, which is the same shape of mistake one
  // layer down: `serviceSummaryProvider` only delegates to this, so the loop
  // above rebuilt a wrapper that awaited an answer already in the cache. A pull
  // that redrew every figure and re-asked no server whether it was up.
  ref.invalidate(instanceSummaryProvider);
  if (libraries) ref.read(pollClockProvider).note(_librariesClockId);
  // The library providers the KPI builders read through, and therefore the two
  // figures on every stack card. Invalidating `serviceKpiProvider` alone would
  // recompute the same numbers from the same cached libraries, which is a pull
  // that looks like it worked and changes nothing. The recently-added rail no
  // longer reads these: it rides one history page per arr.
  if (libraries) {
    ref.invalidate(moviesProvider);
    ref.invalidate(seriesProvider);
    ref.invalidate(musicProvider);
  }
  // And the four non-swallowing reads the rail makes of those same libraries.
  // They are separate providers so that a server which did not answer reads an
  // em dash rather than a confident zero; separate also means a pull that
  // stopped at the line above refreshed the grids and left every figure on
  // every stack card exactly where it was.
  //
  // Every service's, not four: `serviceKpiSources` is exhaustive over
  // `ServiceKey`, which the hand-written list of the four arrs was not.
  for (final service in ServiceKey.values) {
    final skipped = serviceKpiLibrarySources(service);
    for (final source in serviceKpiSources(service)) {
      if (libraries || !skipped.contains(source)) ref.invalidate(source);
    }
  }
}
