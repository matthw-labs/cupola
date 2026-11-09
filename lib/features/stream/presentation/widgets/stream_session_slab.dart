import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/home/domain/now_playing.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';

/// The picture a session in a room's Now playing is drawn with: the title's
/// wide artwork from the server (behind its key, so it lights nothing), else
/// its poster.
typedef StreamSessionPicture = ({String url, Map<String, String>? headers});

/// The one playback of a room, drawn large: the title's picture across the
/// slab, `Anna · Sintel`, where and how it plays, how long is left, the bar,
/// and the controls the server allows.
///
/// A room with more than one playback draws [StreamSessionLine]s instead: a
/// second picture that size would push the rest of the room off the phone.
class StreamSessionFeature extends StatelessWidget {
  const StreamSessionFeature({
    super.key,
    required this.session,
    this.picture,
    this.onStop,
    this.onTogglePause,
    this.onMessage,
    this.onOpenTitle,
  });

  final StreamSession session;
  final StreamSessionPicture? picture;
  final VoidCallback? onStop;
  final VoidCallback? onTogglePause;
  final VoidCallback? onMessage;

  /// Opens the title being played; see [StreamSessionCard.onOpenTitle].
  final VoidCallback? onOpenTitle;

  @override
  Widget build(BuildContext context) {
    final picture = this.picture;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Readout(
          session: session,
          onOpenTitle: onOpenTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (picture != null) ...[
                AspectRatio(
                  aspectRatio: _wide,
                  child: ContentCard(
                    imageUrl: picture.url,
                    httpHeaders: picture.headers,
                    fallbackIcon: Icons.play_circle_outline_rounded,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _Words(session: session, large: true),
              const SizedBox(height: AppSpacing.sm),
              _Remaining(session: session),
            ],
          ),
        ),
        StreamSessionActions(
          isPaused: session.isPaused,
          onTogglePause: onTogglePause,
          onMessage: onMessage,
          onStop: onStop,
        ),
      ],
    );
  }
}

/// One playback among several in a room's Now playing: a wide thumbnail
/// beside who, what, where and how, then the bar and how long is left, then
/// the controls the server allows.
class StreamSessionLine extends StatelessWidget {
  const StreamSessionLine({
    super.key,
    required this.session,
    this.picture,
    this.onStop,
    this.onTogglePause,
    this.onMessage,
    this.onOpenTitle,
  });

  final StreamSession session;
  final StreamSessionPicture? picture;
  final VoidCallback? onStop;
  final VoidCallback? onTogglePause;
  final VoidCallback? onMessage;

  /// Opens the title being played; see [StreamSessionCard.onOpenTitle].
  final VoidCallback? onOpenTitle;

  /// The thumbnail's width; its height follows the wide ratio.
  static const double thumbWidth = 112;

  @override
  Widget build(BuildContext context) {
    final picture = this.picture;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Readout(
          session: session,
          onOpenTitle: onOpenTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: thumbWidth,
                    height: thumbWidth / _wide,
                    child: ContentCard(
                      imageUrl: picture?.url,
                      httpHeaders: picture?.headers,
                      fallbackIcon: Icons.play_circle_outline_rounded,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _Words(session: session, large: false)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _Remaining(session: session),
            ],
          ),
        ),
        StreamSessionActions(
          isPaused: session.isPaused,
          onTogglePause: onTogglePause,
          onMessage: onMessage,
          onStop: onStop,
        ),
      ],
    );
  }
}

/// A wide picture's ratio: a backdrop's, an episode still's.
const double _wide = 16 / 9;

/// The readout of a playback as one sentence, its parts silenced; the
/// controls after it stay their own nodes.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.session,
    required this.child,
    this.onOpenTitle,
  });

  final StreamSession session;
  final Widget child;
  final VoidCallback? onOpenTitle;

  @override
  Widget build(BuildContext context) {
    final progress = session.progress;
    final remaining = session.remaining;
    return StreamSessionReadout(
      title: session.title,
      onOpenTitle: onOpenTitle,
      value: streamSessionValue(
        userName: session.userName,
        title: session.title,
        subtitle: session.subtitle,
        playMethodLabel: session.playMethod.label,
        transcodeReason: session.transcodeReasonLabel,
        deviceLabel: session.deviceLabel,
        progressLabel: _spokenProgress(progress, remaining),
        bitrateLabel: formatStreamBitrate(session.bitrate),
        bitrateIsNominal: session.bitrateIsNominal,
        isPaused: session.isPaused,
      ),
      child: child,
    );
  }
}

/// How far in and how long is left, as said; null when the server says
/// neither.
String? _spokenProgress(double? progress, Duration? remaining) {
  final parts = [
    if (progress != null) '${spokenPercent(progress * 100)} in',
    if (remaining != null) '${formatTimeSpan(remaining)} left',
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

/// `Anna · Sintel`, then the screen, then how it plays in its tone.
class _Words extends StatelessWidget {
  const _Words({required this.session, required this.large});

  final StreamSession session;

  /// The one playback of a room (its words share the line with the screen),
  /// or a line among several (the screen on a line of its own).
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = CupolaRoom.of(context);
    final device = session.deviceLabel.trim();
    final title = Text(
      nowPlayingTitle(session),
      maxLines: large ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style:
          (large ? theme.textTheme.titleMedium! : theme.textTheme.titleSmall!)
              .weight(FontWeight.w600),
    );
    final where = device.isEmpty
        ? null
        : Text(
            device,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: room.inkSecondary,
            ),
          );
    final how = _Delivery(session: session);
    if (large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [?where, how],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        ?where,
        const SizedBox(height: AppSpacing.xs),
        how,
      ],
    );
  }
}

/// How the bytes go out, after a dot in the delivery's tone: green while the
/// file goes out untouched, amber while the server re-encodes it, and why.
class _Delivery extends StatelessWidget {
  const _Delivery({required this.session});

  final StreamSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusToneColor(
      theme.colorScheme,
      session.deliveryTone,
      surface: CupolaRoom.of(context).slab,
    );
    final words = [
      if (session.isPaused) StateWord.paused.label,
      session.playMethod.label,
      ?session.transcodeReasonLabel,
    ].join(dotSeparator);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _dot,
          height: _dot,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            words,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium!
                .weight(FontWeight.w600)
                .copyWith(color: color),
          ),
        ),
      ],
    );
  }

  static const double _dot = 6;
}

/// The bar, in ink (watching is not a status), and how long is left after
/// it; nothing for a server that says neither.
class _Remaining extends StatelessWidget {
  const _Remaining({required this.session});

  final StreamSession session;

  @override
  Widget build(BuildContext context) {
    final progress = session.progress;
    final remaining = session.remaining;
    if (progress == null && remaining == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final room = CupolaRoom.of(context);
    return Row(
      children: [
        Expanded(
          child: progress == null
              ? const SizedBox.shrink()
              : ClipRRect(
                  borderRadius: AppRadius.borderRadiusXs,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    color: room.ink,
                    backgroundColor: room.fillTrack,
                  ),
                ),
        ),
        if (remaining != null) ...[
          const SizedBox(width: AppSpacing.md),
          Text(
            '${formatTimeSpan(remaining)} left',
            maxLines: 1,
            style: theme.textTheme.labelMedium!.tabular.copyWith(
              color: room.inkSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
