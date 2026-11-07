import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_image.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

/// One viewing as a row, in History and on a person's page: the poster, the
/// title, who and where, and what it came to. A tap opens its detail.
///
/// [withDay] says the day as well as the time. History groups its rows under a
/// day heading and gives the time alone; a person's page lists their latest
/// across days with no heading, so each row says its own.
///
/// The row does not open its own sheet: [onOpen] is the screen's, because a row
/// is unmounted when the list is read again, and a sheet whose actions ran
/// from it would find nobody to act (`showTracearrSession`).
class TracearrHistoryRow extends ConsumerWidget {
  const TracearrHistoryRow({
    super.key,
    required this.entry,
    required this.onOpen,
    this.withDay = false,
    this.withPerson = true,
  });

  final TracearrHistoryEntry entry;

  /// Opens the viewing's detail, from the screen the row is listed on.
  final VoidCallback onOpen;
  final bool withDay;

  /// Whether the row names the person: not on their own page, where every row
  /// is theirs.
  final bool withPerson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(tracearrClientProvider);
    final poster = resolveTracearrImage(entry.media.posterUrl, client.baseUri);
    final title = tracearrMediaTitleOf(entry.media);
    final started = entry.startedAt;
    final when = started == null
        ? null
        : withDay
        ? formatDayWords(started, now: DateTime.now())
        : formatClockTime(started);
    final detail = joinDisplayParts([
      if (withPerson) tracearrPersonOf(entry.person),
      entry.device.name,
      tracearrServerOf(entry.server),
      when,
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
    return PressableScale(
      onTap: onOpen,
      semanticHint: 'opens the details',
      child: ServiceRecordRow.poster(
        art: ServiceOverviewArt(
          posterUrl: poster?.toString(),
          title: title,
          httpHeaders: poster == null ? null : client.imageHeaders,
        ),
        tone: StatusTone.neutral,
        title: title,
        detail: detail,
        trailing: result,
        semanticLabel: spokenPercents(joinSpokenParts([title, detail, result])),
      ),
    );
  }
}
