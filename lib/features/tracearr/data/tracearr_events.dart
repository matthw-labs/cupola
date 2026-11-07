import 'dart:convert';

import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';

/// The event name of [SseFrame.keepAlive]. It holds a character no `event:`
/// field of ours can spell, since a field name is cut at its first colon.
const String kSseKeepAliveEvent = ':keep-alive';

/// One event of a server-sent-events stream, as the wire frames it.
final class SseFrame {
  const SseFrame({required this.event, required this.data, this.id});

  /// The sign of life a comment line (`: ping`) is: no event and no data, only
  /// the proof that the server is still there. The standard drops comments
  /// because a browser has no use for them, but a stalled connection can only
  /// be told from a quiet one by the bytes that keep arriving, and Tracearr's
  /// only word on a quiet stream is its ping.
  const SseFrame.keepAlive() : event = kSseKeepAliveEvent, data = '', id = null;

  /// Whether this is [SseFrame.keepAlive].
  bool get isKeepAlive => event == kSseKeepAliveEvent;

  /// The `event:` field, `message` when the frame names none.
  final String event;

  /// The `data:` lines joined with a newline.
  final String data;

  /// The last `id:` seen on the stream so far, as the standard keeps it.
  final String? id;

  /// [data] decoded as JSON, or null when it is not.
  Object? get json {
    try {
      return jsonDecode(data);
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'SseFrame($event, ${data.length} chars)';
}

/// A parser for the `text/event-stream` format, fed text as it arrives.
///
/// We wrote it ourselves, as a pure class, because no client in the app reads
/// a streaming response and a dependency for forty lines of a stable format is
/// not worth carrying. It follows the WHATWG rules: lines end in LF, CR or
/// CRLF (a CRLF split across two chunks is still one break); a line that opens
/// with `:` is a comment, dropped from the frames and counted in [comments];
/// `data:` lines accumulate and a blank line dispatches them; one space after
/// the colon is not part of the value; `retry:` takes digits only. A frame with no data is not dispatched.
final class SseParser {
  final StringBuffer _line = StringBuffer();
  final StringBuffer _data = StringBuffer();
  String _event = '';
  String? _lastId;
  bool _afterCarriageReturn = false;
  bool _atStart = true;

  /// The last `retry:` the server sent, which is how long it asks a client to
  /// wait before reconnecting. Reconnection itself is the caller's.
  Duration? retry;

  /// How many comment lines the stream has sent so far. A comment dispatches
  /// nothing, but it is the one thing a server sends to say it is still there.
  int comments = 0;

  /// Feeds [text] and returns the frames it completes.
  List<SseFrame> add(String text) {
    final frames = <SseFrame>[];
    for (final unit in text.codeUnits) {
      if (_atStart) {
        _atStart = false;
        // A byte order mark opens the stream, not the first field name.
        if (unit == 0xFEFF) continue;
      }
      if (_afterCarriageReturn) {
        _afterCarriageReturn = false;
        if (unit == 0x0A) continue;
      }
      if (unit == 0x0D || unit == 0x0A) {
        final line = _line.toString();
        _line.clear();
        _afterCarriageReturn = unit == 0x0D;
        final frame = _handle(line);
        if (frame != null) frames.add(frame);
      } else {
        _line.writeCharCode(unit);
      }
    }
    return frames;
  }

  SseFrame? _handle(String line) {
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) {
      comments++;
      return null;
    }
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        _data
          ..write(value)
          ..write('\n');
      case 'id':
        if (!value.contains('\u0000')) _lastId = value;
      case 'retry':
        if (RegExp(r'^\d+$').hasMatch(value)) {
          retry = Duration(milliseconds: int.parse(value));
        }
    }
    return null;
  }

  SseFrame? _dispatch() {
    final data = _data.toString();
    final event = _event;
    _data.clear();
    _event = '';
    if (data.isEmpty) return null;
    return SseFrame(
      event: event.isEmpty ? 'message' : event,
      data: data.substring(0, data.length - 1),
      id: _lastId,
    );
  }
}

/// The frames of a byte stream.
///
/// Decoding is chunked, so a multi-byte character cut by a chunk boundary is
/// whole when it reaches the parser. [onRetry] hears each `retry:` the server
/// sends. A frame cut off by the end of the stream is not dispatched, as the
/// standard says. With [withKeepAlives] each chunk that brought a comment line
/// also yields one [SseFrame.keepAlive], after the frames the chunk completed.
Stream<SseFrame> sseFrames(
  Stream<List<int>> bytes, {
  void Function(Duration retry)? onRetry,
  bool withKeepAlives = false,
}) async* {
  final parser = SseParser();
  // `bind`, not `transform`: a Dio body is a `Stream<Uint8List>`, and
  // `transform` would demand a transformer of exactly that type.
  await for (final text in const Utf8Decoder(
    allowMalformed: true,
  ).bind(bytes)) {
    final before = parser.retry;
    final comments = parser.comments;
    final frames = parser.add(text);
    final after = parser.retry;
    if (after != null && after != before) onRetry?.call(after);
    for (final frame in frames) {
      yield frame;
    }
    if (withKeepAlives && parser.comments != comments) {
      yield const SseFrame.keepAlive();
    }
  }
}

/// What `GET /api/v2/public/events` tells us.
sealed class TracearrEvent {
  const TracearrEvent({this.at});

  /// When Tracearr says it happened.
  final DateTime? at;
}

/// A comment line (`: ping`, about every 25 seconds on Tracearr 3.1.4): the
/// server is there and has nothing to say. It moves no row; the feed loop
/// listens for it to know the connection is alive.
final class TracearrKeepAlive extends TracearrEvent {
  const TracearrKeepAlive({super.at});
}

/// The stream is open and the server is talking.
final class TracearrReady extends TracearrEvent {
  const TracearrReady({super.at});
}

final class TracearrStreamStarted extends TracearrEvent {
  const TracearrStreamStarted(this.stream, {super.at});

  final TracearrStream stream;
}

final class TracearrStreamUpdated extends TracearrEvent {
  const TracearrStreamUpdated(this.stream, {super.at});

  final TracearrStream stream;
}

/// The cheap tick of a running stream: only what moves.
final class TracearrStreamProgress extends TracearrEvent {
  const TracearrStreamProgress({
    required this.id,
    this.serverId,
    this.state = TracearrStreamState.unknown,
    this.progressMs,
    this.bitrate,
    super.at,
  });

  final String id;
  final String? serverId;
  final TracearrStreamState state;
  final int? progressMs;
  final int? bitrate;

  /// [stream] with this tick applied.
  TracearrStream applyTo(TracearrStream stream) => stream.withProgress(
    state: state == TracearrStreamState.unknown ? null : state,
    progressMs: progressMs,
    bitrate: bitrate,
  );
}

final class TracearrStreamStopped extends TracearrEvent {
  const TracearrStreamStopped({
    required this.id,
    this.serverId,
    this.stream,
    super.at,
  });

  final String id;
  final String? serverId;

  /// The stream as it was when it stopped, when Tracearr sends it.
  final TracearrStream? stream;
}

final class TracearrViolationCreated extends TracearrEvent {
  const TracearrViolationCreated(this.violation, {super.at});

  final TracearrViolation violation;
}

/// A server went up or down, or lost its token.
final class TracearrServerHealth extends TracearrEvent {
  const TracearrServerHealth({
    required this.serverId,
    this.serverName = '',
    this.status = TracearrServerStatus.unknown,
    this.reason,
    super.at,
  });

  final String serverId;
  final String serverName;
  final TracearrServerStatus status;
  final TracearrServerReason? reason;
}

/// The typed event of [frame], or null for one we ignore: an event we do not
/// know (Tracearr will add some), a payload that is not JSON, or one without
/// what its kind cannot do without.
///
/// Tracearr wraps each payload as `{type, at, data}`. The `event:` field names
/// the kind too; when a frame leaves it at `message` we fall back to `type`.
TracearrEvent? tracearrEventFrom(SseFrame frame) {
  if (frame.isKeepAlive) return const TracearrKeepAlive();
  final payload = asTracearrJson(frame.json);
  if (payload == null) return null;
  final wrapped = payload['type'] is String && payload['data'] != null;
  final data = wrapped ? asTracearrJson(payload['data']) : payload;
  if (data == null) return null;
  final kind = frame.event != 'message'
      ? frame.event
      : (payload.text('type') ?? '');
  final at = wrapped ? payload.time('at') : null;
  try {
    return switch (kind) {
      'ready' => TracearrReady(at: at),
      'stream.started' => TracearrStreamStarted(
        TracearrStream.fromJson(data),
        at: at,
      ),
      'stream.updated' => TracearrStreamUpdated(
        TracearrStream.fromJson(data),
        at: at,
      ),
      'stream.progress' => TracearrStreamProgress(
        id: data.requiredText('id'),
        serverId: data.text('server_id'),
        state: TracearrStreamState.fromWire(data['state']),
        progressMs: data.integer('progress_ms'),
        bitrate: data.integer('bitrate'),
        at: at,
      ),
      'stream.stopped' => _stopped(data, at),
      'violation.created' => TracearrViolationCreated(
        TracearrViolation.fromJson(data),
        at: at,
      ),
      'server.health' => TracearrServerHealth(
        serverId: data.requiredText('server_id'),
        serverName: data.text('server_name') ?? '',
        status: TracearrServerStatus.fromWire(data['status']),
        reason: TracearrServerReason.fromWire(data['reason']),
        at: at,
      ),
      _ => null,
    };
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

TracearrStreamStopped _stopped(TracearrJson data, DateTime? at) {
  final stream = data.object('stream');
  return TracearrStreamStopped(
    id: data.requiredText('id'),
    serverId: data.text('server_id'),
    stream: stream == null ? null : _streamOrNull(stream),
    at: at,
  );
}

TracearrStream? _streamOrNull(TracearrJson json) {
  try {
    return TracearrStream.fromJson(json);
  } on FormatException {
    return null;
  }
}
