import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';

/// One live stream, a row of `GET /api/v2/public/streams` (and of the
/// `stream.started` and `stream.updated` events).
///
/// What a person watches is theirs, so [toString] prints the id and nothing of
/// the row.
final class TracearrStream {
  const TracearrStream({
    required this.id,
    this.server = const TracearrServerRef(id: ''),
    this.person = const TracearrPerson(),
    this.media = const TracearrMedia(),
    this.device = const TracearrDevice(),
    this.quality = const TracearrQuality(),
    this.state = TracearrStreamState.unknown,
    this.progressMs = 0,
    this.startedAt,
  });

  factory TracearrStream.fromJson(TracearrJson json) => TracearrStream(
    id: json.requiredText('id'),
    server: TracearrServerRef.fromFlat(json),
    person: TracearrPerson.fromStreamRow(json),
    media: TracearrMedia.fromJson(json),
    device: TracearrDevice.fromJson(json),
    quality: TracearrQuality.fromJson(json),
    state: TracearrStreamState.fromWire(json['state']),
    progressMs: json.integer('progress_ms') ?? 0,
    startedAt: json.time('started_at'),
  );

  final String id;
  final TracearrServerRef server;
  final TracearrPerson person;
  final TracearrMedia media;
  final TracearrDevice device;
  final TracearrQuality quality;
  final TracearrStreamState state;
  final int progressMs;
  final DateTime? startedAt;

  bool get isPaused => state == TracearrStreamState.paused;

  /// How far along, from 0 to 1; null when the duration is unknown or zero.
  double? get progress {
    final total = media.durationMs;
    if (total == null || total <= 0) return null;
    return (progressMs / total).clamp(0.0, 1.0);
  }

  /// The same stream with a `stream.progress` event applied: the one event
  /// that carries only the moving parts.
  TracearrStream withProgress({
    TracearrStreamState? state,
    int? progressMs,
    int? bitrate,
  }) => TracearrStream(
    id: id,
    server: server,
    person: person,
    media: media,
    device: device,
    quality: bitrate == null ? quality : quality.withBitrate(bitrate),
    state: state ?? this.state,
    progressMs: progressMs ?? this.progressMs,
    startedAt: startedAt,
  );

  @override
  String toString() => 'TracearrStream($id)';
}

/// The counts above the stream list, for the whole install or one server.
final class TracearrStreamSummary {
  const TracearrStreamSummary({
    this.serverId,
    this.serverName,
    this.total = 0,
    this.transcodes = 0,
    this.audioTranscodes = 0,
    this.directStreams = 0,
    this.directPlays = 0,
    this.totalBitrate,
  });

  factory TracearrStreamSummary.fromJson(TracearrJson json) =>
      TracearrStreamSummary(
        serverId: json.text('server_id'),
        serverName: json.text('server_name'),
        total: json.integer('total') ?? 0,
        transcodes: json.integer('transcodes') ?? 0,
        audioTranscodes: json.integer('audio_transcodes') ?? 0,
        directStreams: json.integer('direct_streams') ?? 0,
        directPlays: json.integer('direct_plays') ?? 0,
        // Left as Tracearr formats it: `12.4 Mbps`, or an em dash when nobody
        // is streaming. Re-deriving a number from it would invent precision.
        totalBitrate: json['total_bitrate'] is String
            ? json['total_bitrate'] as String
            : null,
      );

  /// Set on a per-server entry, null on the overall summary.
  final String? serverId;
  final String? serverName;

  final int total;
  final int transcodes;
  final int audioTranscodes;
  final int directStreams;
  final int directPlays;

  /// A preformatted string, kept as given. The em dash it carries when no
  /// stream is playing is data, not punctuation.
  final String? totalBitrate;

  @override
  String toString() => 'TracearrStreamSummary($total, $transcodes transcodes)';
}

/// The answer of `GET /api/v2/public/streams`: the rows and their summary.
final class TracearrStreams {
  const TracearrStreams({
    required this.streams,
    this.summary = const TracearrStreamSummary(),
    this.byServer = const [],
    this.dropped = 0,
  });

  /// A body that is not an object is a [FormatException]: wrong answer.
  factory TracearrStreams.fromJson(Object? body) {
    final json = asTracearrJson(body);
    if (json == null) {
      throw const FormatException('Tracearr streams is not an object');
    }
    final read = tracearrRows(json['data'], TracearrStream.fromJson);
    final summary = json.object('summary');
    return TracearrStreams(
      streams: read.rows,
      summary: summary == null
          ? TracearrStreamSummary(total: read.rows.length)
          : TracearrStreamSummary.fromJson(summary),
      byServer: summary == null
          ? const []
          : tracearrRows(
              summary['by_server'],
              TracearrStreamSummary.fromJson,
            ).rows,
      dropped: read.dropped,
    );
  }

  final List<TracearrStream> streams;
  final TracearrStreamSummary summary;
  final List<TracearrStreamSummary> byServer;
  final int dropped;

  @override
  String toString() => 'TracearrStreams(${streams.length} streams)';
}
