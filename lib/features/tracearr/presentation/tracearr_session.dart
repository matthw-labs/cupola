import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_live_reducer.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';

/// One viewing, as the detail sheet reads it: a stream playing now (Live, the
/// Overview) or one that was played (History).
///
/// The two rows share what the sheet is about (who, what, on which device,
/// how it reached them), so the sheet is written once over this and not twice
/// over two models. What belongs to one side only stays optional: a viewing
/// that is going has a [progressMs]; one that was has its [startedAt] and
/// [stoppedAt], its [percentComplete] and the verdict [watched].
///
/// What someone watches is theirs, so [toString] prints the id and nothing of
/// the row.
@immutable
final class TracearrSession {
  const TracearrSession({
    required this.id,
    required this.person,
    required this.media,
    required this.device,
    required this.server,
    required this.quality,
    required this.state,
    required this.isLive,
    this.startedAt,
    this.stoppedAt,
    this.progressMs,
    this.percentComplete,
    this.watched = false,
    this.segmentCount = 1,
  });

  /// A stream playing now.
  factory TracearrSession.live(TracearrStream stream) => TracearrSession(
    id: stream.id,
    person: stream.person,
    media: stream.media,
    device: stream.device,
    server: stream.server,
    quality: stream.quality,
    state: stream.state,
    isLive: true,
    startedAt: stream.startedAt,
    progressMs: stream.progressMs,
  );

  /// A viewing from History. One Tracearr has not closed yet is still going,
  /// but History is a record and not the stream list: nothing in it ends a
  /// stream, so it is not [isLive].
  factory TracearrSession.recorded(TracearrHistoryEntry entry) =>
      TracearrSession(
        id: entry.id,
        person: entry.person,
        media: entry.media,
        device: entry.device,
        server: entry.server,
        quality: entry.quality,
        state: entry.state,
        isLive: false,
        startedAt: entry.startedAt,
        stoppedAt: entry.stoppedAt,
        progressMs: entry.progressMs,
        percentComplete: entry.percentComplete,
        watched: entry.watched,
        segmentCount: entry.segmentCount,
      );

  final String id;
  final TracearrPerson person;
  final TracearrMedia media;
  final TracearrDevice device;
  final TracearrServerRef server;
  final TracearrQuality quality;
  final TracearrStreamState state;

  /// Whether it is a stream Tracearr can end: only a row of the live list.
  final bool isLive;

  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final int? progressMs;
  final double? percentComplete;
  final bool watched;
  final int segmentCount;

  /// How far along, 0 to 1, for a viewing that has a length.
  double? get progress {
    final total = media.durationMs;
    final at = progressMs;
    if (total == null || total <= 0 || at == null) return null;
    return (at / total).clamp(0.0, 1.0);
  }

  /// The title page it opens, when its ids identify the title.
  MediaKey? get mediaKey => tracearrMediaKeyOf(media);

  @override
  String toString() => 'TracearrSession($id)';
}

/// One line of the sheet's list of facts: a label and what it says.
typedef TracearrFact = ({String label, String value});

/// One row of the source-against-output table.
typedef TracearrComparison = ({String label, String source, String output});

/// What the person is told about how a viewing reached them, first: the method
/// and, when it transcodes, why, in the server's own words.
String tracearrHowWords(TracearrQuality quality) {
  final method = tracearrMethodWord(quality);
  if (method == null) return Lexicon.noFigure;
  final reasons = quality.transcode?.reasons ?? const <String>[];
  return joinDisplayParts([
    method,
    if (quality.isTranscode) ...reasons.map(tracearrReasonWords),
  ]);
}

/// Source against output for the three things a server converts: the picture,
/// the sound and the container. A side Tracearr did not describe is the dash
/// of an unknown figure.
List<TracearrComparison> tracearrComparisonOf(TracearrQuality quality) {
  final source = quality.source;
  final output = quality.output;
  final info = quality.transcode;
  String orDash(String line) => line.isEmpty ? Lexicon.noFigure : line;
  return [
    (
      label: 'Video',
      source: orDash(
        _line([
          source.videoCodecDisplay ?? source.videoCodec,
          _heightWord(source.height),
          source.dynamicRange,
        ]),
      ),
      output: orDash(
        _line([
          output.videoCodecDisplay ?? output.videoCodec,
          _heightWord(output.height) ?? quality.resolution,
          output.dynamicRange,
        ]),
      ),
    ),
    (
      label: 'Audio',
      source: orDash(
        _line([
          source.audioCodecDisplay ?? source.audioCodec,
          quality.audioChannelsDisplay ??
              tracearrChannelsWord(source.audioChannels, source.channelLayout),
        ]),
      ),
      output: orDash(
        _line([
          output.audioCodecDisplay ?? output.audioCodec,
          tracearrChannelsWord(output.audioChannels, null),
        ]),
      ),
    ),
    if (info?.sourceContainer != null || info?.streamContainer != null)
      (
        label: 'Container',
        source: orDash(info?.sourceContainer ?? ''),
        output: orDash(info?.streamContainer ?? ''),
      ),
  ];
}

String _line(Iterable<String?> parts) => joinDisplayParts(parts);

String? _heightWord(int? height) {
  if (height == null || height <= 0) return null;
  return '${height}p';
}

/// `Stereo`, `5.1`, `7.1`, or the count of channels; null when unknown.
String? tracearrChannelsWord(int? channels, String? layout) {
  if (layout != null && layout.trim().isNotEmpty) {
    final named = layout.trim().toLowerCase();
    if (named == 'stereo') return 'Stereo';
    if (named == 'mono') return 'Mono';
    if (RegExp(r'^\d(\.\d)?(\(.*\))?$').hasMatch(named)) return named;
  }
  return switch (channels) {
    null || <= 0 => null,
    1 => 'Mono',
    2 => 'Stereo',
    6 => '5.1',
    8 => '7.1',
    final count => '$count channels',
  };
}

/// What the sheet lists under the table, in the order a person asks: how much
/// it takes, where the work is done, whether it keeps up, subtitles, then who
/// and where it came from and how far it got.
///
/// Pure, so each fact and the rule that leaves it out are tested without a
/// widget. A fact Tracearr did not state is absent, never a guess.
List<TracearrFact> tracearrFactsOf(TracearrSession session, {DateTime? now}) {
  final quality = session.quality;
  final info = quality.transcode;
  final facts = <TracearrFact>[];

  final kbps = quality.bitrate;
  final bandwidth = kbps == null ? null : tracearrBitrateLabel(kbps);
  if (bandwidth != null) facts.add((label: 'Bitrate', value: bandwidth));

  if (info != null) {
    final hardware = _hardwareWords(info);
    if (hardware != null) facts.add((label: 'Hardware', value: hardware));
    final speed = info.speed;
    if (speed != null || info.throttled == true) {
      facts.add((
        label: 'Speed',
        value: joinDisplayParts([
          if (speed != null) '${_trimmed(speed)}x',
          if (info.throttled == true) 'Throttled',
        ]),
      ));
    }
  }

  final subtitles = _subtitleWords(quality.subtitle);
  if (subtitles != null) facts.add((label: 'Subtitles', value: subtitles));

  final server = tracearrServerOf(session.server);
  if (server != null) facts.add((label: 'Server', value: server));
  final device = joinDisplayParts([
    session.device.device,
    session.device.player,
    session.device.product,
  ]);
  if (device.isNotEmpty) facts.add((label: 'Device', value: device));

  final started = session.startedAt;
  if (started != null) {
    facts.add((
      label: 'Started',
      value: formatRelativeDateTime(started, now: now),
    ));
  }
  final ran = tracearrRanFor(session);
  if (ran != null) facts.add((label: 'Ran for', value: ran));
  final progress = session.progress;
  if (session.isLive) {
    if (progress != null) {
      facts.add((label: 'Progress', value: formatPercent(progress * 100)));
    }
  } else {
    final completion = _completionWords(session);
    if (completion != null) facts.add((label: 'Completion', value: completion));
  }
  return facts;
}

String? _hardwareWords(TracearrTranscodeInfo info) {
  final decoding = info.hwDecoding;
  final encoding = info.hwEncoding;
  if (decoding != null || encoding != null) {
    return joinDisplayParts([
      if (decoding != null) 'Decoding on $decoding',
      if (encoding != null) 'encoding on $encoding',
    ]);
  }
  if (info.hwRequested == true) return 'Asked for, not used';
  return null;
}

/// A subtitle track as the server decided it. The decision word is the
/// server's and the contract does not fix its set, so the ones we know are
/// said in words and any other is shown as it came.
String? _subtitleWords(TracearrSubtitle? subtitle) {
  if (subtitle == null) return null;
  final decision = subtitle.decision?.trim().toLowerCase();
  if (decision == null || decision == 'none') return null;
  final how = switch (decision) {
    'burn' => 'Burned in',
    'copy' || 'directplay' => 'Sent as they are',
    'transcode' => 'Converted',
    final other => other[0].toUpperCase() + other.substring(1),
  };
  return joinDisplayParts([
    how,
    subtitle.language,
    subtitle.codec,
    if (subtitle.forced == true) 'Forced',
  ]);
}

/// How a recorded viewing ended: counted as watched, stopped part of the way,
/// or still going, with how many pieces Tracearr glued it from.
String? _completionWords(TracearrSession session) {
  final percent = session.percentComplete;
  final pieces = session.segmentCount > 1
      ? countLabel(session.segmentCount, 'segment')
      : null;
  if (session.stoppedAt == null) {
    return joinDisplayParts(['Still playing', pieces]);
  }
  if (session.watched) return joinDisplayParts(['Watched', pieces]);
  return joinDisplayParts([
    percent == null ? 'Stopped' : 'Stopped at ${formatPercent(percent)}',
    pieces,
  ]);
}

String _trimmed(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// How long a viewing ran, for a recorded one that has both ends.
String? tracearrRanFor(TracearrSession session) {
  final started = session.startedAt;
  final stopped = session.stoppedAt;
  if (started == null || stopped == null) return null;
  return formatTimeSpan(stopped.difference(started));
}
