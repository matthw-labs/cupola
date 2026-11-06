import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';

const _service = ServiceKey.tracearr;

/// History: what was watched, newest first, a page at a time with `Load more`.
///
/// One row per viewing, which may be several sessions glued together by
/// Tracearr (a pause that outlived the stream). The list is not filtered and
/// not grouped by day yet; the filters (person, server, kind, only watched,
/// period) and the day headings are what this file grows into, and each
/// filter will be the server's, never a trim of the pages already read.
/// Its state is [tracearrHistoryProvider].
class TracearrHistoryScreen extends ConsumerWidget {
  const TracearrHistoryScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(_service)) {
      return NotConfiguredPlaceholder.forService(_service);
    }
    final history = ref.watch(tracearrHistoryProvider);
    final rows = history.asData?.value;
    return ServiceListPage<TracearrHistoryEntry>.unsummarised(
      service: _service,
      topPadding: topPadding,
      value: history.whenData((data) => data.items),
      serviceName: 'Tracearr history',
      emptyIcon: Icons.history_rounded,
      emptyTitle: 'No history yet',
      emptyMessage:
          'What people watch on the servers Tracearr watches '
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
      rowBuilder: (entry) => _HistoryRow(entry: entry),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final TracearrHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final title = tracearrMediaTitleOf(entry.media);
    final started = entry.startedAt;
    final detail = joinDisplayParts([
      tracearrPersonOf(entry.person),
      entry.device.name,
      tracearrServerOf(entry.server),
      started == null ? null : formatDayWords(started, now: DateTime.now()),
    ]);
    // What the viewing came to: finished and counted, finished short of it, or
    // still going. Tracearr's own verdict on `watched`, never ours.
    final percent = entry.percentComplete;
    final result = !entry.isFinished
        ? 'Playing'
        : entry.watched
        ? 'Watched'
        : percent == null
        ? 'Stopped'
        : formatPercent(percent);
    final row = ServiceRecordRow(
      icon: Icons.history_rounded,
      tone: StatusTone.neutral,
      title: title,
      detail: detail,
      trailing: result,
      semanticLabel: spokenPercents(joinSpokenParts([title, detail, result])),
    );
    final key = tracearrMediaKeyOf(entry.media);
    return key == null
        ? row
        : PressableScale(
            onTap: () => context.openMedia(key),
            semanticHint: 'opens the title',
            child: row,
          );
  }
}
