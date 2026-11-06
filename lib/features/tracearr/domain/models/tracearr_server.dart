import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_version.dart';

/// A media server named on a row (a stream, a violation, an account).
final class TracearrServerRef {
  const TracearrServerRef({
    required this.id,
    this.name = '',
    this.type = TracearrServerType.unknown,
  });

  /// A row's server, from its flat `server_id`, `server_name` and
  /// `server_type` fields (streams and history).
  factory TracearrServerRef.fromFlat(TracearrJson json) => TracearrServerRef(
    id: json.text('server_id') ?? '',
    name: json.text('server_name') ?? '',
    type: TracearrServerType.fromWire(json['server_type']),
  );

  /// A row's server, from its nested `server` object (violations).
  factory TracearrServerRef.fromJson(TracearrJson json) => TracearrServerRef(
    id: json.text('id') ?? '',
    name: json.text('name') ?? '',
    type: TracearrServerType.fromWire(json['type']),
  );

  /// Empty when the row did not say: a row is still worth drawing without it.
  final String id;
  final String name;
  final TracearrServerType type;

  @override
  String toString() => 'TracearrServerRef($id, ${type.name})';
}

/// One server in `GET /api/v2/public/servers`.
final class TracearrServer {
  const TracearrServer({
    required this.id,
    this.name = '',
    this.type = TracearrServerType.unknown,
    this.status = TracearrServerStatus.unknown,
    this.reason,
    this.historical = false,
    this.activeStreams = 0,
    this.version,
  });

  factory TracearrServer.fromJson(TracearrJson json) => TracearrServer(
    id: json.requiredText('server_id'),
    name: json.text('server_name') ?? '',
    type: TracearrServerType.fromWire(json['server_type']),
    status: TracearrServerStatus.fromWire(json['status']),
    reason: TracearrServerReason.fromWire(json['reason']),
    historical: json.flag('historical') ?? false,
    activeStreams: json.integer('active_streams') ?? 0,
    version: json.text('version'),
  );

  final String id;
  final String name;
  final TracearrServerType type;
  final TracearrServerStatus status;

  /// Why it is not up, when Tracearr says.
  final TracearrServerReason? reason;

  /// A server Tracearr no longer polls but whose history it keeps.
  final bool historical;

  final int activeStreams;

  /// The media server's own version, not Tracearr's.
  final String? version;

  /// Tracearr reaches the server but its token there was refused: only the
  /// owner can fix it, in Tracearr.
  bool get isUnauthorized => reason == TracearrServerReason.unauthorized;

  bool get isUp => status == TracearrServerStatus.up;

  @override
  String toString() => 'TracearrServer($id, ${type.name}, ${status.name})';
}

/// The answer of `GET /api/v2/public/servers`.
final class TracearrServers {
  const TracearrServers({required this.servers, this.tracearrVersion});

  /// A body that is not an object is a [FormatException]: wrong answer.
  factory TracearrServers.fromJson(Object? body) {
    final json = asTracearrJson(body);
    if (json == null) {
      throw const FormatException('Tracearr servers is not an object');
    }
    return TracearrServers(
      servers: tracearrRows(json['data'], TracearrServer.fromJson).rows,
      tracearrVersion: json.text('tracearr_version'),
    );
  }

  final List<TracearrServer> servers;

  /// As Tracearr spells it, with the leading `v`.
  final String? tracearrVersion;

  TracearrVersion? get version => TracearrVersion.tryParse(tracearrVersion);

  @override
  String toString() =>
      'TracearrServers(${servers.length} servers, $tracearrVersion)';
}

/// A server as the v1 health read lists it.
final class TracearrHealthServer {
  const TracearrHealthServer({
    required this.id,
    this.name = '',
    this.type = TracearrServerType.unknown,
    this.online = false,
    this.historical = false,
    this.activeStreams = 0,
  });

  factory TracearrHealthServer.fromJson(TracearrJson json) =>
      TracearrHealthServer(
        id: json.requiredText('id'),
        name: json.text('name') ?? '',
        type: TracearrServerType.fromWire(json['type']),
        online: json.flag('online') ?? false,
        historical: json.flag('historical') ?? false,
        activeStreams: json.integer('activeStreams') ?? 0,
      );

  final String id;
  final String name;
  final TracearrServerType type;
  final bool online;
  final bool historical;
  final int activeStreams;

  @override
  String toString() => 'TracearrHealthServer($id, ${type.name}, $online)';
}

/// `GET /api/v1/public/health`: the one read that names the version.
final class TracearrHealth {
  const TracearrHealth({
    this.status,
    this.version,
    this.timestamp,
    this.servers = const [],
  });

  /// A body that is not an object is a [FormatException]: wrong answer.
  factory TracearrHealth.fromJson(Object? body) {
    final json = asTracearrJson(body);
    if (json == null) {
      throw const FormatException('Tracearr health is not an object');
    }
    return TracearrHealth(
      status: json.text('status'),
      version: json.text('version'),
      timestamp: json.time('timestamp'),
      servers: tracearrRows(
        json['servers'],
        TracearrHealthServer.fromJson,
      ).rows,
    );
  }

  /// `ok` when healthy.
  final String? status;

  /// As Tracearr spells it, with the leading `v`.
  final String? version;

  final DateTime? timestamp;
  final List<TracearrHealthServer> servers;

  TracearrVersion? get parsedVersion => TracearrVersion.tryParse(version);

  bool get isOk => status == 'ok';

  @override
  String toString() => 'TracearrHealth($status, $version)';
}
