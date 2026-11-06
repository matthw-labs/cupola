import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';

/// The list of live streams with one event of Tracearr's event stream applied.
///
/// Pure, so the whole of what keeps Live moving is tested without a socket:
///
///  * `stream.started` and `stream.updated` carry the full row, so either one
///    replaces the row with that id, or adds it at the end (Tracearr lists the
///    oldest first, and a stream that just began is the newest);
///  * `stream.progress` carries only what moves, and is applied to the row it
///    names. One for a stream we do not hold is dropped: it cannot make a row
///    out of four fields, and the full row follows within seconds in a
///    `stream.updated`;
///  * `stream.stopped` removes the row;
///  * everything else (`ready`, a violation, a server's health) leaves the
///    list alone.
///
/// The summary is derived again from the rows ([tracearrSummaryOf]), because
/// the events carry no summary of their own.
TracearrStreams applyTracearrEvent(
  TracearrStreams current,
  TracearrEvent event,
) {
  final rows = current.streams;
  switch (event) {
    case TracearrStreamStarted(:final stream) ||
        TracearrStreamUpdated(:final stream):
      final at = rows.indexWhere((row) => row.id == stream.id);
      return _with(current, [
        for (final (index, row) in rows.indexed) index == at ? stream : row,
        if (at < 0) stream,
      ]);
    case TracearrStreamProgress(:final id):
      final at = rows.indexWhere((row) => row.id == id);
      if (at < 0) return current;
      return _with(current, [
        for (final (index, row) in rows.indexed)
          index == at ? event.applyTo(row) : row,
      ]);
    case TracearrStreamStopped(:final id):
      if (!rows.any((row) => row.id == id)) return current;
      return _with(current, [
        for (final row in rows)
          if (row.id != id) row,
      ]);
    default:
      return current;
  }
}

/// [events] applied in order.
TracearrStreams applyTracearrEvents(
  TracearrStreams current,
  Iterable<TracearrEvent> events,
) => events.fold(current, applyTracearrEvent);

/// [streams] without the one that ended, for the moment between a tap on Stop
/// and the stop event that follows it.
TracearrStreams withoutTracearrStream(TracearrStreams current, String id) =>
    _with(current, [
      for (final row in current.streams)
        if (row.id != id) row,
    ]);

TracearrStreams _with(TracearrStreams current, List<TracearrStream> rows) =>
    TracearrStreams(
      streams: List.unmodifiable(rows),
      summary: tracearrSummaryOf(rows),
      byServer: _byServer(rows),
      dropped: current.dropped,
    );

/// The counts above the list, derived from the rows.
///
/// Tracearr's own summary comes with a read of the streams and is what a read
/// shows; between two reads this is its arithmetic over the rows we hold, so
/// the figures move with them. The bandwidth is the sum of the rows' bitrates,
/// which are kilobits per second, worded the way Tracearr words it
/// ([tracearrBitrateLabel]), and null when nothing is playing.
TracearrStreamSummary tracearrSummaryOf(
  List<TracearrStream> streams, {
  String? serverId,
  String? serverName,
}) {
  var transcodes = 0;
  var audioTranscodes = 0;
  var directStreams = 0;
  var directPlays = 0;
  var kbps = 0;
  for (final stream in streams) {
    final quality = stream.quality;
    if (quality.isTranscode) transcodes++;
    if (quality.audioDecision == TracearrDecision.transcode) audioTranscodes++;
    if (quality.isDirectStream) directStreams++;
    if (quality.isDirectPlay) directPlays++;
    kbps += quality.bitrate ?? 0;
  }
  return TracearrStreamSummary(
    serverId: serverId,
    serverName: serverName,
    total: streams.length,
    transcodes: transcodes,
    audioTranscodes: audioTranscodes,
    directStreams: directStreams,
    directPlays: directPlays,
    totalBitrate: tracearrBitrateLabel(kbps),
  );
}

List<TracearrStreamSummary> _byServer(List<TracearrStream> rows) {
  final byId = <String, List<TracearrStream>>{};
  for (final row in rows) {
    (byId[row.server.id] ??= []).add(row);
  }
  return List.unmodifiable([
    for (final MapEntry(:key, :value) in byId.entries)
      tracearrSummaryOf(
        value,
        serverId: key,
        serverName: value.first.server.name,
      ),
  ]);
}

/// `379 kbps`, `1.4 Mbps`: kilobits per second as Tracearr words a bandwidth,
/// with the no-break space the brand book puts between a figure and its unit.
/// Null for none, which Tracearr writes as a dash and we leave out.
String? tracearrBitrateLabel(int kbps) {
  if (kbps <= 0) return null;
  if (kbps < 1000) return withUnit(kbps, 'kbps');
  return withUnit((kbps / 1000).toStringAsFixed(1), 'Mbps');
}
