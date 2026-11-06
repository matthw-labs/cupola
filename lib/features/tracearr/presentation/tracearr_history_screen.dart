import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_filters.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_row.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_person_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

const _service = ServiceKey.tracearr;

/// History: what was watched, newest first, a section a day, a page at a time
/// with `Load more`.
///
/// One row per viewing, which may be several sessions glued together by
/// Tracearr (a pause that outlived the stream). Above the list, outside its
/// states so they stay reachable when it is empty or did not answer, are the
/// filters: person, server, type, period and only watched. Each is the
/// server's, remembered per connection (`tracearrHistoryFiltersProvider`), and
/// there is no library filter, because Tracearr has none to offer and a filter
/// over the pages already read would show an empty list while older pages held
/// plenty.
///
/// A row opens the detail of the viewing (`showTracearrSession`), with how it
/// ended. Its state is [tracearrHistoryProvider].
class TracearrHistoryScreen extends ConsumerWidget {
  const TracearrHistoryScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(_service)) {
      return NotConfiguredPlaceholder.forService(_service);
    }
    final history = ref.watch(tracearrHistoryProvider);
    final filters = ref.watch(tracearrHistoryFiltersProvider);
    final now = ref.watch(tracearrClockProvider)();
    final rows = history.asData?.value;
    return ServiceListPage<_Item>.unsummarised(
      service: _service,
      topPadding: topPadding,
      header: const _Filters(),
      value: history.whenData(
        (data) => _itemsOf(tracearrDaysOf(data.items, now: now)),
      ),
      serviceName: 'Tracearr history',
      emptyIcon: Icons.history_rounded,
      emptyTitle: filters.isNarrowed ? 'Nothing matches' : 'No history yet',
      emptyMessage: filters.isNarrowed
          ? 'No viewing Tracearr recorded fits these filters.'
          : 'What people watch on the servers Tracearr watches '
                'appears here.',
      onRetry: () => ref.invalidate(tracearrHistoryProvider),
      footer: rows == null
          ? null
          : TracearrLoadMore(
              rows: rows,
              noun: 'entries',
              onLoadMore: () =>
                  ref.read(tracearrHistoryProvider.notifier).loadMore(),
            ),
      rowBuilder: (item) => switch (item) {
        _Heading(:final label) => _DayHeading(label: label),
        _Viewing(:final entry) => TracearrHistoryRow(entry: entry),
      },
    );
  }
}

sealed class _Item {
  const _Item();
}

final class _Heading extends _Item {
  const _Heading(this.label);

  final String label;
}

final class _Viewing extends _Item {
  const _Viewing(this.entry);

  final TracearrHistoryEntry entry;
}

List<_Item> _itemsOf(List<TracearrHistoryDay> days) => [
  for (final day in days) ...[
    _Heading(day.label),
    for (final entry in day.entries) _Viewing(entry),
  ],
];

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        label,
        style: AppType.section.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );
}

/// The five filters, in a scrolling row of pills: four that open a choice and
/// one that toggles, with a `Clear` while any narrows the list.
class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(tracearrHistoryFiltersProvider);
    final notifier = ref.read(tracearrHistoryFiltersProvider.notifier);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: SelectionPills.gutter,
      child: Row(
        children: [
          _pill(
            label: filters.userName ?? 'Anyone',
            selected: filters.userId != null,
            onTap: () => _pickPerson(context, ref),
            chevron: true,
          ),
          _pill(
            label: filters.serverName ?? 'Any server',
            selected: filters.serverId != null,
            onTap: () => _pickServer(context, ref),
            chevron: true,
          ),
          _pill(
            label: filters.mediaType == null
                ? 'Any type'
                : tracearrHistoryTypeWord(filters.mediaType!),
            selected: filters.mediaType != null,
            onTap: () => _pickType(context, ref),
            chevron: true,
          ),
          _pill(
            label: filters.period.label,
            selected: filters.period != TracearrPeriod.anyTime,
            onTap: () => _pickPeriod(context, ref),
            chevron: true,
          ),
          _pill(
            label: 'Only watched',
            selected: filters.onlyWatched,
            onTap: () => notifier.onlyWatched(!filters.onlyWatched),
          ),
          if (filters.isNarrowed)
            _pill(label: 'Clear', selected: false, onTap: notifier.clear),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool chevron = false,
  }) => Padding(
    padding: const EdgeInsets.only(right: AppSpacing.sm),
    child: SelectionPill(
      label: label,
      selected: selected,
      onTap: onTap,
      trailing: chevron ? Icons.expand_more_rounded : null,
    ),
  );

  Future<void> _pickPerson(BuildContext context, WidgetRef ref) async {
    final List<TracearrUser> people;
    try {
      people = await ref.read(tracearrPeopleProvider.future);
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not read the people Tracearr knows. '
        '${writeFailureReason(_service, error)}',
        cause: error,
      );
      return;
    }
    if (!context.mounted) return;
    final filters = ref.read(tracearrHistoryFiltersProvider);
    final picked = await showMediaValueSheet<String?>(
      context,
      title: 'Person',
      value: filters.userId,
      currentLabel: filters.userName ?? 'Anyone',
      searchHint: 'Name',
      options: [
        const MediaDetailValueOption<String?>(value: null, label: 'Anyone'),
        for (final user in people)
          MediaDetailValueOption<String?>(
            value: user.id,
            label: tracearrPersonName(user),
          ),
      ],
    );
    if (picked == null) return;
    ref
        .read(tracearrHistoryFiltersProvider.notifier)
        .person(picked.value, picked.label);
  }

  Future<void> _pickServer(BuildContext context, WidgetRef ref) async {
    final List<TracearrServer> servers;
    try {
      servers = (await ref.read(tracearrServersProvider.future)).servers;
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not read the servers Tracearr watches. '
        '${writeFailureReason(_service, error)}',
        cause: error,
      );
      return;
    }
    if (!context.mounted) return;
    final filters = ref.read(tracearrHistoryFiltersProvider);
    final picked = await showMediaValueSheet<String?>(
      context,
      title: 'Server',
      value: filters.serverId,
      currentLabel: filters.serverName ?? 'Any server',
      options: [
        const MediaDetailValueOption<String?>(value: null, label: 'Any server'),
        for (final server in servers)
          MediaDetailValueOption<String?>(
            value: server.id,
            label: tracearrServerLabel(server),
          ),
      ],
    );
    if (picked == null) return;
    ref
        .read(tracearrHistoryFiltersProvider.notifier)
        .server(picked.value, picked.label);
  }

  Future<void> _pickType(BuildContext context, WidgetRef ref) async {
    final filters = ref.read(tracearrHistoryFiltersProvider);
    final picked = await showMediaValueSheet<TracearrHistoryMediaType?>(
      context,
      title: 'Type',
      value: filters.mediaType,
      currentLabel: filters.mediaType == null
          ? 'Any type'
          : tracearrHistoryTypeWord(filters.mediaType!),
      options: [
        const MediaDetailValueOption<TracearrHistoryMediaType?>(
          value: null,
          label: 'Any type',
        ),
        for (final type in tracearrHistoryTypes)
          MediaDetailValueOption<TracearrHistoryMediaType?>(
            value: type,
            label: tracearrHistoryTypeWord(type),
          ),
      ],
    );
    if (picked == null) return;
    ref.read(tracearrHistoryFiltersProvider.notifier).type(picked.value);
  }

  Future<void> _pickPeriod(BuildContext context, WidgetRef ref) async {
    final filters = ref.read(tracearrHistoryFiltersProvider);
    final picked = await showMediaValueSheet<TracearrPeriod>(
      context,
      title: 'Period',
      value: filters.period,
      currentLabel: filters.period.label,
      options: [
        for (final period in TracearrPeriod.values)
          MediaDetailValueOption<TracearrPeriod>(
            value: period,
            label: period.label,
          ),
      ],
    );
    if (picked == null) return;
    ref.read(tracearrHistoryFiltersProvider.notifier).period(picked.value);
  }
}
