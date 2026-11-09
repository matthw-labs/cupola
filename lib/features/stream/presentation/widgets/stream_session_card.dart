import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/room_art.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';

/// One live playback, as three stacked lines.
///
/// **Why this is a card and not a horizontal path row.** The first design drew a
/// session as one line tracing what → how → where → rate, with connectors, on the
/// theory that a connection should be traceable end to end. That layout cannot
/// ship: `TextScaleMetrics.singleLineChromeMaxScaleFactor` is 1.3 precisely
/// because "a strip of pills with connectors between them… cannot reflow", and
/// worse, any `Flexible` distribution ellipsises the longest child first, which
/// here is the transcode *reason*, the one string the surface exists to show. The
/// layout would have eaten its own focal point. `TorrentTile`, the app's other
/// live-transfer row, reached the same conclusion and stacks.
///
/// So the path survives as **vertical reading order** instead:
///
///  1. what is playing,
///  2. how it is being delivered, and why, in the delivery's own tone: green
///     while the file is going out untouched, amber once the box is
///     re-encoding,
///  3. who is watching it, on what, and how far in.
///
/// The rate keeps its own row-end slot rather than a column, so it can update in
/// place (tabular figures) without a shared column grid to keep aligned.
///
/// **The description is one node; the controls are not inside it.** The whole
/// card used to sit under `Semantics(excludeSemantics: true)`, which is right for
/// the four text lines (read top to bottom they are a comma list with no
/// structure) and catastrophic for the buttons it also swallowed: the stop
/// control was on screen, focusable by a pointer, and completely absent from the
/// screen reader's traversal. So the exclusion now wraps the *readout* only, and
/// every action stays its own reachable node with its own name.
class StreamSessionCard extends StatelessWidget {
  const StreamSessionCard({
    super.key,
    required this.session,
    required this.accent,
    this.serverName,
    this.onStop,
    this.onTogglePause,
    this.onMessage,
    this.onOpenPerson,
    this.onOpenTitle,
    this.posterUrl,
    this.posterHeaders,
    this.light,
  });

  final StreamSession session;

  /// The title's poster beside its words: the public poster the arrs hold for
  /// it when there is one (it glows with its own light), else the server's
  /// own, fetched with [posterHeaders]. Null draws the words alone.
  final String? posterUrl;
  final Map<String, String>? posterHeaders;

  /// The picture of the title's light: a card about a title glows with it
  /// (brand book, *The title light*). Null for an unlit card.
  final RoomArt? light;
  final Color accent;

  /// Which server the session is playing from, for a list that merges two
  /// connections of one media server (`Jellyfin Cabin`). Null prints nothing:
  /// a page reading one server, or a household with one of each, has
  /// nothing to tell apart.
  final String? serverName;

  /// Stopping is optional because it is not always permitted: Plex gates
  /// termination behind Plex Pass. A null handler renders no control at all
  /// rather than a button that fails on tap.
  final VoidCallback? onStop;

  /// Pause, or resume when [StreamSession.isPaused].
  ///
  /// **Jellyfin only, and that asymmetry is the API's.** `/Sessions/{id}/Playing/Pause`
  /// and `/Unpause` are Jellyfin remote-control commands; Plex's player endpoints
  /// address the *client* by its own machine identifier over a connection the
  /// server does not proxy, so the board cannot reach them. Plex therefore keeps
  /// stop alone, and the control is absent rather than present-and-failing.
  final VoidCallback? onTogglePause;

  /// Send a line of text to the player. Jellyfin only, for the same reason as
  /// [onTogglePause].
  final VoidCallback? onMessage;

  /// The way to the viewer's page in Tracearr, where Tracearr knows who they
  /// are. A Plex card carries it, since Plex has no Users tab for the door to
  /// sit in; null draws nothing.
  final VoidCallback? onOpenPerson;

  /// Opens the title being played (`OpenMedia.openStreamSession`): the
  /// poster and the words are then one button. Null for a session that names
  /// no title, whose readout stays words.
  final VoidCallback? onOpenTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reason = session.transcodeReasonLabel;
    final rate = formatStreamBitrate(session.bitrate);
    final progressLabel = _progressLabel(session.progress);

    // The tone is the *session's* own, resolved in the domain layer, and walked
    // for contrast against the card's own fill rather than against the page: an
    // `AppCard.filled` paints `surfaceContainer`, and only the caller knows the
    // tone is landing on an elevated surface.
    final costColor = statusToneColor(
      colorScheme,
      session.deliveryTone,
      surface: colorScheme.surfaceContainer,
    );

    // What is playing, how, and who is watching it on what.
    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(session: session),
        const SizedBox(height: AppSpacing.sm),
        _CostRow(
          session: session,
          reason: reason,
          color: costColor,
          rate: rate,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [
            session.userName,
            session.deviceLabel,
            ?serverName,
          ].join(dotSeparator),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final poster = posterUrl;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreamSessionReadout(
          title: session.title,
          value: streamSessionValue(
            userName: session.userName,
            title: session.title,
            subtitle: session.subtitle,
            playMethodLabel: session.playMethod.label,
            transcodeReason: reason,
            deviceLabel: session.deviceLabel,
            progressLabel: progressLabel,
            bitrateLabel: rate,
            bitrateIsNominal: session.bitrateIsNominal,
            isPaused: session.isPaused,
            serverName: serverName,
          ),
          onOpenTitle: onOpenTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (poster != null && poster.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _posterWidth,
                      height: _posterHeight,
                      child: ContentCard.lit(
                        imageUrl: poster,
                        httpHeaders: posterHeaders,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: lines),
                  ],
                )
              else
                lines,
              if (session.progress != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ProgressBar(progress: session.progress!),
              ],
            ],
          ),
        ),
        if (onTogglePause != null ||
            onMessage != null ||
            onStop != null ||
            onOpenPerson != null)
          StreamSessionActions(
            isPaused: session.isPaused,
            onTogglePause: onTogglePause,
            onMessage: onMessage,
            onStop: onStop,
            onOpenPerson: onOpenPerson,
          ),
      ],
    );

    final art = light;
    if (art == null) return AppCard.filled(child: content);
    // The light lies under the words, to the card's edges: the card carries
    // its own inset inside the clip.
    return AppCard.filled(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadius.borderRadiusSlab,
        child: Stack(
          children: [
            Positioned.fill(child: SlabLight(art: art)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: content,
            ),
          ],
        ),
      ),
    );
  }

  /// The poster's size beside the words, as an Overview row's.
  static const double _posterWidth = 36;
  static const double _posterHeight = 54;

  static String? _progressLabel(double? progress) {
    if (progress == null) return null;
    return '${formatPercent(progress * 100)} in';
  }
}

/// The readout of one live playback as one spoken sentence, its parts
/// silenced: a button that opens the title when [onOpenTitle] is set, words
/// otherwise. The controls after it stay their own nodes.
class StreamSessionReadout extends StatelessWidget {
  const StreamSessionReadout({
    super.key,
    required this.title,
    required this.value,
    required this.child,
    this.onOpenTitle,
  });

  final String title;
  final String value;
  final Widget child;
  final VoidCallback? onOpenTitle;

  /// What activating an open readout does, said after the sentence.
  static const String openHint = 'Opens the title';

  @override
  Widget build(BuildContext context) {
    final open = onOpenTitle;
    if (open == null) {
      return Semantics(
        container: true,
        label: title,
        value: value,
        excludeSemantics: true,
        child: child,
      );
    }
    return PressableScale(
      onTap: open,
      semanticLabel: title,
      semanticValue: value,
      semanticHint: openHint,
      excludeChildSemantics: true,
      child: child,
    );
  }
}

/// The controls for one live playback, on its card and in a room's Now
/// playing; nothing when the server allows none.
///
/// A trailing row at the card's foot rather than a glyph tucked beside the
/// title: three of them do not fit a phone's title line beside a two-line title,
/// and pinning them there is what forced the old single stop button down to
/// `VisualDensity.compact`: a 40pt target on a surface whose whole job is to
/// interrupt someone. Each one keeps `IconButton`'s full 48×48 and carries a
/// tooltip, which is also its spoken name.
class StreamSessionActions extends StatelessWidget {
  const StreamSessionActions({
    super.key,
    required this.isPaused,
    required this.onTogglePause,
    required this.onMessage,
    required this.onStop,
    this.onOpenPerson,
  });

  final bool isPaused;
  final VoidCallback? onTogglePause;
  final VoidCallback? onMessage;
  final VoidCallback? onStop;

  /// The viewer's page in Tracearr; see [StreamSessionCard.onOpenPerson].
  final VoidCallback? onOpenPerson;

  @override
  Widget build(BuildContext context) {
    if (onTogglePause == null &&
        onMessage == null &&
        onStop == null &&
        onOpenPerson == null) {
      return const SizedBox.shrink();
    }
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (onOpenPerson != null)
          IconButton(
            onPressed: onOpenPerson,
            icon: const Icon(Icons.person_outline_rounded, size: 20),
            color: color,
            tooltip: 'Open this person in Tracearr',
          ),
        if (onTogglePause != null)
          IconButton(
            onPressed: onTogglePause,
            icon: Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 20,
            ),
            color: color,
            // Named for what the tap does, not for the state it is in: "Pause"
            // on an already-paused session is the one label that cannot be read
            // two ways.
            tooltip: isPaused ? 'Resume this playback' : 'Pause this playback',
          ),
        if (onMessage != null)
          IconButton(
            onPressed: onMessage,
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
            color: color,
            tooltip: 'Send a message to this player',
          ),
        if (onStop != null)
          IconButton(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            color: color,
            tooltip: 'Stop this playback',
          ),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.session});

  final StreamSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = session.subtitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (session.isPaused)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs, top: 2),
            child: Icon(
              Icons.pause_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// How the bytes are being delivered, and what it costs.
///
/// A `Wrap` rather than a `Row`, so the reason can take a second line instead of
/// eliding; see the class doc on [StreamSessionCard]. The rate sits in the same
/// wrap so it follows the reason down rather than pinning a column.
class _CostRow extends StatelessWidget {
  const _CostRow({
    required this.session,
    required this.reason,
    required this.color,
    required this.rate,
  });

  final StreamSession session;
  final String? reason;
  final Color color;
  final String? rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              session.needsAttention
                  ? Icons.memory_rounded
                  : Icons.bolt_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              session.playMethod.label,
              style: theme.textTheme.labelMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: color),
            ),
          ],
        ),
        if (reason != null)
          Text(
            reason!,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        if (rate != null)
          Text(
            // "~" carries the same hedge the spoken form says as "about". Neither
            // server reports measured throughput, so an unqualified figure would
            // assert egress the API never gave us.
            session.bitrateIsNominal ? '~$rate' : rate!,
            style: theme.textTheme.labelMedium!.tabular.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 3,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

/// Bits per second as a short human figure.
///
/// Decimal megabits, because that is the unit every media server, router and ISP
/// states a stream in. Bytes here would be correct and unreadable. Returns null
/// for a null or non-positive input so callers can omit the slot rather than
/// printing "0 Mbps" for a session whose rate the server simply did not report.
String? formatStreamBitrate(int? bitsPerSecond) {
  if (bitsPerSecond == null || bitsPerSecond <= 0) return null;
  final mbps = bitsPerSecond / 1000000;
  if (mbps >= 10) return withUnit(mbps.round(), 'Mbps');
  if (mbps >= 1) return withUnit(mbps.toStringAsFixed(1), 'Mbps');
  return withUnit((bitsPerSecond / 1000).round(), 'kbps');
}
