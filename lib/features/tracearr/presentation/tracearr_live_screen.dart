import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/async_value_kept.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_image.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session_sheet.dart';

const _service = ServiceKey.tracearr;

/// Live: every stream playing now on the servers Tracearr watches, one row
/// each, with how it reaches the viewer.
///
/// The rows move while the tab is the page on screen and the app is in the
/// foreground: Tracearr's event stream is open then and closed otherwise, and
/// when it cannot be opened the rows are read again every ten seconds until it
/// can (`tracearrLiveFeedProvider`, watched through the gate). A row opens the
/// detail of its stream (`showTracearrSession`).
///
/// Its state is [tracearrLiveProvider], which the Overview shares, so a stream
/// is counted once wherever it is read.
class TracearrLiveScreen extends ConsumerWidget {
  const TracearrLiveScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(_service)) {
      return NotConfiguredPlaceholder.forService(_service);
    }
    ref.watchWhileLive(context, tracearrLiveFeedProvider);
    final streams = ref.watch(tracearrLiveProvider);
    return ServiceListPage<TracearrStream>.unsummarised(
      service: _service,
      topPadding: topPadding,
      value: streams.whenDataKept((data) => data.streams),
      serviceName: 'Tracearr streams',
      emptyIcon: Icons.play_circle_outline_rounded,
      emptyTitle: 'Nothing is playing',
      emptyMessage:
          'Streams appear here while someone watches on a server '
          'Tracearr watches.',
      onRetry: () => ref.invalidate(tracearrLiveProvider),
      banner: _Summary(streams: streams.value),
      // This screen's own context and ref open the sheet: a stream that stops
      // takes its row with it, and the sheet's actions must outlast the row.
      rowBuilder: (stream) => _StreamRow(
        stream: stream,
        onOpen: () =>
            showTracearrSession(context, ref, TracearrSession.live(stream)),
      ),
    );
  }
}

/// The one line above the rows: how many, how many transcode, and the
/// bandwidth. Tracearr's own figure while the rows are as a read left them,
/// ours (the sum of the rows) once events have moved them, worded the same,
/// and left out when nothing is playing.
class _Summary extends StatelessWidget {
  const _Summary({required this.streams});

  final TracearrStreams? streams;

  @override
  Widget build(BuildContext context) {
    final data = streams;
    if (data == null) return const SizedBox.shrink();
    final line = tracearrSummaryLine(data);
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

/// `3 streams · 1 transcode · 12.4 Mbps`: the count, the transcodes when there
/// are any, and the bandwidth when there is one. A bandwidth Tracearr wrote as
/// the dash of nothing is left out.
String tracearrSummaryLine(TracearrStreams data) {
  final summary = data.summary;
  final bandwidth = summary.totalBitrate?.trim();
  return joinDisplayParts([
    countLabel(data.streams.length, 'stream'),
    if (summary.transcodes > 0) countLabel(summary.transcodes, 'transcode'),
    if (bandwidth != null && bandwidth != Lexicon.noFigure) bandwidth,
  ]);
}

class _StreamRow extends ConsumerWidget {
  const _StreamRow({required this.stream, required this.onOpen});

  final TracearrStream stream;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(tracearrClientProvider);
    final poster = resolveTracearrImage(stream.media.posterUrl, client.baseUri);
    final title = tracearrMediaTitleOf(stream.media);
    final progress = stream.progress;
    final detail = joinDisplayParts([
      tracearrPersonOf(stream.person),
      stream.device.name,
      tracearrServerOf(stream.server),
      stream.isPaused ? StateWord.paused.label : null,
      progress == null ? null : formatPercent(progress * 100),
      tracearrTranscodeReason(stream.quality),
    ]);
    final method = tracearrMethodWord(stream.quality) ?? 'Playing';
    return PressableScale(
      onTap: onOpen,
      semanticHint: 'opens the details',
      child: ServiceRecordRow.poster(
        art: ServiceOverviewArt(
          posterUrl: poster?.toString(),
          title: title,
          httpHeaders: poster == null ? null : client.imageHeaders,
        ),
        // Somebody watching is activity, in blue: the stack is doing its job.
        // A viewer's pause rests.
        tone: stream.isPaused ? StatusTone.neutral : StatusTone.info,
        title: title,
        detail: detail,
        trailing: method,
        semanticLabel: spokenPercents(joinSpokenParts([title, detail, method])),
      ),
    );
  }
}
