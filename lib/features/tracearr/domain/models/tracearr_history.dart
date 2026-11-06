import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';

/// One row of `GET /api/v2/public/history`: a viewing, finished or not.
///
/// A viewing may be several sessions glued together (a pause that outlived the
/// stream, a reconnect): [segmentCount] says how many. What someone watched is
/// theirs, so [toString] prints the id and nothing of the row.
final class TracearrHistoryEntry {
  const TracearrHistoryEntry({
    required this.id,
    this.referenceId,
    this.server = const TracearrServerRef(id: ''),
    this.person = const TracearrPerson(),
    this.media = const TracearrMedia(),
    this.device = const TracearrDevice(),
    this.quality = const TracearrQuality(),
    this.state = TracearrStreamState.unknown,
    this.startedAt,
    this.stoppedAt,
    this.progressMs,
    this.totalDurationMs,
    this.percentComplete,
    this.watched = false,
    this.segmentCount = 1,
  });

  factory TracearrHistoryEntry.fromJson(TracearrJson json) {
    final user = json.object('user');
    return TracearrHistoryEntry(
      id: json.requiredText('id'),
      referenceId: json.text('reference_id'),
      server: TracearrServerRef.fromFlat(json),
      person: user == null
          ? const TracearrPerson()
          : TracearrPerson.fromJson(user),
      media: TracearrMedia.fromJson(json),
      device: TracearrDevice.fromJson(json),
      quality: TracearrQuality.fromJson(json),
      state: TracearrStreamState.fromWire(json['state']),
      startedAt: json.time('started_at'),
      stoppedAt: json.time('stopped_at'),
      progressMs: json.integer('progress_ms'),
      totalDurationMs: json.integer('total_duration_ms'),
      percentComplete: json.number('percent_complete'),
      watched: json.flag('watched') ?? false,
      segmentCount: json.integer('segment_count') ?? 1,
    );
  }

  final String id;

  /// The id the segments of one viewing share.
  final String? referenceId;

  final TracearrServerRef server;
  final TracearrPerson person;
  final TracearrMedia media;
  final TracearrDevice device;
  final TracearrQuality quality;
  final TracearrStreamState state;
  final DateTime? startedAt;

  /// Null while it is still going.
  final DateTime? stoppedAt;

  final int? progressMs;

  /// The duration summed across segments. The contract says no more than that,
  /// so a screen should lean on [percentComplete] and [watched] instead.
  final int? totalDurationMs;

  /// 0 to 100, as Tracearr computes it.
  final double? percentComplete;

  /// Whether Tracearr counts it as watched (past its completion threshold).
  final bool watched;

  final int segmentCount;

  bool get isFinished => stoppedAt != null;

  @override
  String toString() => 'TracearrHistoryEntry($id)';
}
