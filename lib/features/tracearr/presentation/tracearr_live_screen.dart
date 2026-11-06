import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

const _service = ServiceKey.tracearr;

/// Live: every stream playing now on the servers Tracearr watches, one row
/// each, with how it reaches the viewer.
///
/// A flat list read when the tab opens and again on a pull. What keeps it
/// moving (Tracearr's event stream with its fallback poll), the detail sheet
/// with source against output, and Stop are what this file grows into: the
/// rows below are the shape those hang off, so each stream keeps its row.
///
/// Its state is [tracearrStreamsProvider], which the Overview and the rail
/// share, so a stream is counted once wherever it is read.
class TracearrLiveScreen extends ConsumerWidget {
  const TracearrLiveScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(_service)) {
      return NotConfiguredPlaceholder.forService(_service);
    }
    final streams = ref.watch(tracearrStreamsProvider);
    return ServiceListPage<TracearrStream>.unsummarised(
      service: _service,
      topPadding: topPadding,
      value: streams.whenData((data) => data.streams),
      serviceName: 'Tracearr streams',
      emptyIcon: Icons.play_circle_outline_rounded,
      emptyTitle: 'Nothing is playing',
      emptyMessage:
          'Streams appear here while someone watches on a server '
          'Tracearr watches.',
      onRetry: () => ref.invalidate(tracearrStreamsProvider),
      banner: _Summary(streams: streams.asData?.value),
      rowBuilder: (stream) => _StreamRow(stream: stream),
    );
  }
}

/// The one line above the rows: how many, how many transcode, and the
/// bandwidth Tracearr adds up. The bandwidth is its own preformatted figure,
/// kept as it gave it and left out when it has none (`—`).
class _Summary extends StatelessWidget {
  const _Summary({required this.streams});

  final TracearrStreams? streams;

  @override
  Widget build(BuildContext context) {
    final data = streams;
    if (data == null) return const SizedBox.shrink();
    final summary = data.summary;
    final bandwidth = summary.totalBitrate?.trim();
    final line = joinDisplayParts([
      countLabel(data.streams.length, 'stream'),
      if (summary.transcodes > 0) countLabel(summary.transcodes, 'transcode'),
      if (bandwidth != null && bandwidth != Lexicon.noFigure) bandwidth,
    ]);
    return Semantics(
      container: true,
      label: spokenFromDotted(line),
      child: ExcludeSemantics(
        child: Text(
          line,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: CupolaThemeColors.of(context).dimText,
          ),
        ),
      ),
    );
  }
}

class _StreamRow extends StatelessWidget {
  const _StreamRow({required this.stream});

  final TracearrStream stream;

  @override
  Widget build(BuildContext context) {
    final title = tracearrMediaTitleOf(stream.media);
    final progress = stream.progress;
    final detail = joinDisplayParts([
      tracearrPersonOf(stream.person),
      stream.device.name,
      tracearrServerOf(stream.server),
      progress == null ? null : formatPercent(progress * 100),
    ]);
    final method =
        tracearrMethodWord(stream.quality) ??
        (stream.isPaused ? StateWord.paused.label : 'Playing');
    final row = ServiceRecordRow(
      icon: stream.isPaused
          ? Icons.pause_circle_outline_rounded
          : Icons.play_circle_outline_rounded,
      // Somebody watching is activity, in blue: the stack is doing its job.
      // A viewer's pause rests.
      tone: stream.isPaused ? StatusTone.neutral : StatusTone.info,
      title: title,
      detail: detail,
      trailing: method,
      semanticLabel: spokenPercents(joinSpokenParts([title, detail, method])),
    );
    final key = tracearrMediaKeyOf(stream.media);
    return key == null
        ? row
        : PressableScale(
            onTap: () => context.openMedia(key),
            semanticHint: 'opens the title',
            child: row,
          );
  }
}
