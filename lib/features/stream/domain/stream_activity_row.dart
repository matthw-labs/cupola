/// One playback of Now playing, and what Tracearr adds to it.
library;

import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';

/// What Tracearr said of a playback that a row carries: which connection said
/// it, and the person's picture on its image proxy.
///
/// A path and never an address: the address comes from the connection's reach
/// when the picture is drawn, and the key travels in a header, so nothing here
/// can leak either. [toString] prints neither.
final class StreamTracearrSight {
  const StreamTracearrSight({required this.instanceId, this.avatarPath});

  /// The Tracearr connection that saw the playback.
  final String instanceId;

  /// The person's picture, a path on that Tracearr (`/api/v1/images/proxy?…`),
  /// or null when Tracearr holds none.
  final String? avatarPath;

  @override
  String toString() => 'StreamTracearrSight()';
}

/// One playback plus which server is serving it.
///
/// The pairing is the point: `/activity` merges sources, so a row has to be able
/// to say where it came from: the same problem the Recently Added rail solves
/// with an accent dot and a spoken `accentLabel`. [instanceId] is the connection
/// serving it, which is where its Stop goes, and [connectionName] is how the
/// row names it once its service has two (`SettingsModel.connectionName`).
///
/// A row is one of two kinds. A media server's own ([through] is null) carries
/// the actions Cupola has on that server (Stop, Play with, the item there), and
/// may be enriched by what Tracearr says of the same playback ([tracearr]). A
/// row only Tracearr sees ([through] is `tracearr`) is a playback on a server
/// Cupola is not connected to: [service] is the kind of server it is on,
/// [instanceId] is the Tracearr connection that saw it, and it has no Stop, no
/// Play and no Watch, since nothing of Cupola reaches that server.
final class StreamActivityRow {
  const StreamActivityRow({
    required this.service,
    required this.instanceId,
    required this.connectionName,
    required this.session,
    this.through,
    this.tracearr,
  });

  final ServiceKey service;
  final String instanceId;
  final String? connectionName;
  final StreamSession session;

  /// The service whose answer this playback came through, or null for a media
  /// server's own row.
  final ServiceKey? through;

  /// What Tracearr said of the playback, when it said anything.
  final StreamTracearrSight? tracearr;

  /// Whether only Tracearr sees it.
  bool get isThrough => through != null;

  /// The server as a row names it: `Plex`, and for one only Tracearr sees,
  /// `Plex · through Tracearr`, as a title Jellyfin holds that only Seerr knows
  /// reads `Jellyfin · through Seerr`. A playback whose kind of server Tracearr
  /// could not name is just `Tracearr`.
  String get serverLabel => streamServerLabel(service, through: through);

  @override
  String toString() => 'StreamActivityRow(${service.name})';
}

/// [service] as Now playing names the server a row is on.
String streamServerLabel(ServiceKey service, {ServiceKey? through}) {
  if (through == null || service == through) return service.title;
  return '${service.title}$dotSeparator'
      'through ${through.title}';
}

/// The servers a list of rows came from, as the header under Now playing
/// names them: each server once, in the order the rows came, a server only
/// Tracearr sees after the others with its `through` said once for it.
String streamServersLabel(Iterable<StreamActivityRow> rows) {
  final own = <String>{};
  final through = <String>{};
  for (final row in rows) {
    (row.isThrough ? through : own).add(row.serverLabel);
  }
  return [...own, ...through].join(dotSeparator);
}
