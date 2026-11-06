import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_row.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_navigation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_person_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_users_screen.dart';

const _service = ServiceKey.tracearr;

/// A person: their figures for 7 and 30 days and all time, what they like,
/// what they watched last, and a way to their violations.
///
/// Routed under the Tracearr shell (`ServiceRoutes.tracearrPerson`) and
/// resolved from the path alone: the id is Tracearr's own, and every region
/// reads by it, so a deep link, a row of Users and Live's `Go to` open the
/// same page. Each region loads and fails on its own, so a person whose
/// figures did not come still shows their history and says what is missing.
///
/// A person Tracearr does not know (a link to one that was deleted) is said so,
/// plainly, and is not a failure.
class TracearrPersonScreen extends ConsumerWidget {
  const TracearrPersonScreen({super.key, required this.userId});

  /// Tracearr's id of the person.
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(_service)) {
      return AmbientScaffold(
        accent: _service.accent,
        appBar: const GlassAppBar.inPage(pageTitle: 'Person'),
        body: SafeArea(child: NotConfiguredPlaceholder.forService(_service)),
      );
    }
    final person = ref.watch(tracearrPersonProvider(userId));
    final user = person.value;
    final name = user == null ? 'Person' : tracearrPersonName(user);
    return AmbientScaffold(
      accent: _service.accent,
      appBar: GlassAppBar.inPage(pageTitle: name),
      body: SafeArea(
        child: AsyncValueWidget<TracearrUser?>(
          value: person,
          serviceName: 'Tracearr',
          silentService: _service,
          onRetry: () => ref.invalidate(tracearrPersonProvider(userId)),
          isEmpty: (data) => data == null,
          emptyBuilder: const AppEmptyStatePage(
            emptyState: AppEmptyState(
              icon: Icons.person_off_outlined,
              title: 'Tracearr does not know this person',
              message: 'They may have been deleted from Tracearr.',
            ),
          ),
          data: (found) => _Page(user: found!),
        ),
      ),
    );
  }
}

class _Page extends ConsumerWidget {
  const _Page({required this.user});

  final TracearrUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kinds = tracearrAccountKinds(user);
    final stats = ref.watch(tracearrPersonStatsProvider(user.id));
    final history = ref.watch(tracearrPersonHistoryProvider(user.id));
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      children: [
        PageTitle.flush(
          tracearrPersonName(user),
          summary: kinds.isEmpty
              ? null
              : Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [for (final kind in kinds) GenreChip(genre: kind)],
                ),
        ),
        const SectionHeader.flush(title: 'Watching', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        AsyncValueWidget<TracearrUserStats?>.section(
          value: stats,
          service: _service,
          consequence: 'their figures are not shown',
          loadingLabel: 'Loading their figures',
          onRetry: () => ref.invalidate(tracearrPersonStatsProvider(user.id)),
          skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
          isEmpty: (data) => data == null,
          emptyBuilder: const ServiceOverviewEmpty(
            icon: Icons.insights_outlined,
            label: 'Tracearr has no figures for them yet',
          ),
          data: (data) => _Stats(stats: data!),
        ),
        const SizedBox(height: AppSpacing.lg),
        AsyncValueWidget<TracearrUserStats?>.section(
          value: stats,
          service: _service,
          consequence: 'what they like is not shown',
          onRetry: () => ref.invalidate(tracearrPersonStatsProvider(user.id)),
          isEmpty: (data) => data == null || data.topGenres.isEmpty,
          emptyBuilder: const SizedBox.shrink(),
          data: (data) => _Genres(stats: data!),
        ),
        const SectionHeader.flush(title: 'Latest', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        AsyncValueWidget<TracearrPage<TracearrHistoryEntry>>.section(
          value: history,
          service: _service,
          consequence: 'what they watched is not shown',
          loadingLabel: 'Loading what they watched',
          onRetry: () => ref.invalidate(tracearrPersonHistoryProvider(user.id)),
          skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
          isEmpty: (data) => data.items.isEmpty,
          emptyBuilder: const ServiceOverviewEmpty(
            icon: Icons.history_rounded,
            label: 'Nothing watched yet',
          ),
          data: (data) => Column(
            children: [
              for (final entry in data.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: TracearrHistoryRow(
                    entry: entry,
                    withDay: true,
                    withPerson: false,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
            visualDensity: VisualDensity.standard,
          ),
          onPressed: () => openTracearrViolationsOf(context, user.id),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Violations'),
        ),
      ],
    );
  }
}

/// Plays and time for 7 days, 30 days and all time, one sentence a row.
class _Stats extends StatelessWidget {
  const _Stats({required this.stats});

  final TracearrUserStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (label, window) in [
          ('7 days', stats.last7),
          ('30 days', stats.last30),
          ('All time', stats.allTime),
        ])
          _StatRow(label: label, window: window),
      ],
    );
  }
}

/// How long a window of watching was, the way a span reads everywhere else,
/// and `0 min` for none: a person who watched nothing watched for no time, not
/// for an unknown one.
String tracearrWatchTime(TracearrPlayWindow window) => window.watchTimeMs <= 0
    ? withUnit(0, 'min')
    : formatTimeSpan(window.watchTime);

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.window});

  final String label;
  final TracearrPlayWindow window;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plays = countLabel(window.plays, 'play');
    final time = tracearrWatchTime(window);
    return Semantics(
      container: true,
      label: '$label, $plays, $time',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: CupolaThemeColors.of(context).dimText,
                  ),
                ),
              ),
              Text(
                plays,
                style: AppTheme.data(
                  theme.brightness,
                ).copyWith(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(
                width: 84,
                child: Text(
                  time,
                  textAlign: TextAlign.end,
                  style: AppTheme.data(
                    theme.brightness,
                  ).copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Genres extends StatelessWidget {
  const _Genres({required this.stats});

  final TracearrUserStats stats;

  @override
  Widget build(BuildContext context) {
    final genres = stats.topGenres.take(6).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Semantics(
        container: true,
        label: 'Likes ${genres.map((g) => g.genre).join(', ')}',
        child: ExcludeSemantics(
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final genre in genres) GenreChip(genre: genre.genre),
            ],
          ),
        ),
      ),
    );
  }
}
