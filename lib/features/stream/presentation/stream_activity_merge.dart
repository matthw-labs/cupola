/// The one list of Now playing: the media servers' own rows and what Tracearr
/// sees, said once.
library;

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_activity_row.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_stream_session.dart';

/// The streams one Tracearr connection saw, to fold into Now playing.
typedef TracearrSightings = ({String instanceId, List<TracearrStream> streams});

/// Folds what Tracearr sees into the media servers' own rows.
///
/// A playback both sources describe is **one row, and the media server's own
/// wins**: it carries what Cupola can do on that server (Stop, Play with, the
/// item there), and Tracearr only enriches it (its reasons for a transcode
/// where the server gave none, the person's picture, the way to the person's
/// page, all through [StreamActivityRow.tracearr]). A playback only Tracearr
/// sees is appended, marked as coming through it, with none of those actions:
/// it is on a server Cupola is not connected to.
///
/// Two descriptions are one playback when everything the key holds agrees:
///
///  * the kind of server (Plex, Jellyfin, Emby);
///  * the item, by the id the server gives it (the native row's `itemId`, the
///    Tracearr row's `rating_key`), compared without case or dashes since one
///    source spells a Jellyfin id as a GUID;
///  * the person, by name without case, where both sides name one;
///  * the device: every part of the native row's label (`Infuse · Living
///    room`) is a part of what Tracearr names for the player (its device,
///    player, product and platform), which is how the two sources spell the
///    same client differently;
///  * the server, by its name, **when Cupola knows it**: a service with two
///    connections has a name for each ([connectionNames]), and when Tracearr's
///    server carries the name of one of them, the row must be that
///    connection's. Names that match none say nothing, since Tracearr's name
///    for a server is the owner's and may be nothing like the one we gave it.
///
/// Each row matches at most one stream of a connection, and each stream at
/// most one row, so two people on one device (a shared screen) are two rows,
/// not one.
///
/// **A playback two Tracearr connections both see is still one row.** Two
/// connections can watch one server (a second Tracearr kept for a family
/// member, say), and each lists the playback: the first enriches the row, and
/// a later connection's sighting of what the first already took, or already
/// appended, is the same playback told twice and adds nothing. Streams of one
/// connection are never folded into each other: it lists each playback once,
/// so two of them alike are two screens.
///
/// [connectionNames] holds, per service, the lower-cased names of its
/// connections that have one (`SettingsModel.connectionName`).
List<StreamActivityRow> mergeTracearrStreams({
  required List<StreamActivityRow> native,
  required Iterable<TracearrSightings> sightings,
  Map<ServiceKey, Set<String>> connectionNames = const {},
}) {
  final rows = [...native];
  // Which connection's stream a native row was taken by, so the same
  // playback seen by a second connection is told from a second playback.
  final takenBy = <int, String>{};
  final appended = <({StreamActivityRow row, TracearrStream stream})>[];

  for (final sighting in sightings) {
    for (final stream in sighting.streams) {
      final kind = tracearrServiceOf(stream.server.type);
      var matched = -1;
      var seenBefore = false;
      if (kind != null) {
        final names = connectionNames[kind] ?? const <String>{};
        for (var i = 0; i < rows.length; i++) {
          if (rows[i].isThrough ||
              !_samePlayback(rows[i], stream, kind, names)) {
            continue;
          }
          final by = takenBy[i];
          if (by == null) {
            matched = i;
            break;
          }
          // Taken by another connection: the playback has been said already.
          if (by != sighting.instanceId) seenBefore = true;
        }
      }
      if (matched < 0 && !seenBefore) {
        seenBefore = appended.any(
          (earlier) =>
              earlier.row.instanceId != sighting.instanceId &&
              _sameStream(earlier.stream, stream),
        );
      }
      if (seenBefore && matched < 0) continue;

      final session = tracearrStreamSession(stream);
      final seen = StreamTracearrSight(
        instanceId: sighting.instanceId,
        avatarPath: _blankToNull(stream.person.avatarUrl),
      );
      if (matched >= 0) {
        takenBy[matched] = sighting.instanceId;
        final row = rows[matched];
        final own = row.session;
        rows[matched] = StreamActivityRow(
          service: row.service,
          instanceId: row.instanceId,
          connectionName: row.connectionName,
          // Tracearr explains a delivery the server did not: the reasons
          // come over only where the server gave none for a playback it
          // says is converted.
          session:
              own.transcodeReasons.isEmpty &&
                  own.playMethod != StreamPlayMethod.directPlay &&
                  session.transcodeReasons.isNotEmpty
              ? own.withTranscodeReasons(session.transcodeReasons)
              : own,
          tracearr: seen,
        );
      } else {
        appended.add((
          stream: stream,
          row: StreamActivityRow(
            service: kind ?? ServiceKey.tracearr,
            instanceId: sighting.instanceId,
            connectionName: null,
            session: session,
            through: ServiceKey.tracearr,
            tracearr: seen,
          ),
        ));
      }
    }
  }
  return [...rows, for (final entry in appended) entry.row];
}

/// Whether two Tracearr streams, told by different connections, are one
/// playback: the same kind of server, the same item, the same person on the
/// same player. A stream that names no item by id says it by its title, and
/// one that names neither is never taken for another.
bool _sameStream(TracearrStream a, TracearrStream b) {
  if (a.server.type != b.server.type) return false;
  final itemA = _idOf(a.media.ids.ratingKey) ?? _titleOf(a);
  final itemB = _idOf(b.media.ids.ratingKey) ?? _titleOf(b);
  if (itemA == null || itemA != itemB) return false;
  if (a.person.name.trim().toLowerCase() !=
      b.person.name.trim().toLowerCase()) {
    return false;
  }
  return _playerNames(a).containsAll(_playerNames(b)) &&
      _playerNames(b).containsAll(_playerNames(a));
}

String? _titleOf(TracearrStream stream) {
  final title = stream.media.title.trim().toLowerCase();
  return title.isEmpty ? null : 'title:$title:${stream.media.year ?? ''}';
}

Set<String> _playerNames(TracearrStream stream) {
  final device = stream.device;
  return {
    for (final name in [
      device.device,
      device.player,
      device.product,
      device.platform,
    ])
      if (name != null && name.trim().isNotEmpty) name.trim().toLowerCase(),
  };
}

bool _samePlayback(
  StreamActivityRow row,
  TracearrStream stream,
  ServiceKey kind,
  Set<String> namesOfKind,
) {
  if (row.service != kind) return false;
  final session = row.session;

  final item = _idOf(session.itemId);
  final seen = _idOf(stream.media.ids.ratingKey);
  if (item == null || seen == null || item != seen) return false;

  final who = session.userName.trim().toLowerCase();
  final seenWho = stream.person.name.trim().toLowerCase();
  if (who.isNotEmpty && seenWho.isNotEmpty && who != seenWho) return false;

  if (!_sameDevice(session.deviceLabel, stream)) return false;

  final named = row.connectionName?.trim().toLowerCase();
  final serverName = stream.server.name.trim().toLowerCase();
  if (named != null &&
      named.isNotEmpty &&
      serverName.isNotEmpty &&
      namesOfKind.contains(serverName) &&
      named != serverName) {
    return false;
  }
  return true;
}

/// An item id as the two sources compare it: no case, no dashes.
String? _idOf(String? id) {
  final text = id?.trim().toLowerCase().replaceAll('-', '') ?? '';
  return text.isEmpty ? null : text;
}

/// Whether every part of the native label is a name Tracearr gives the
/// player. A label with no parts says nothing about the device, and so does
/// a stream that names none.
bool _sameDevice(String label, TracearrStream stream) {
  final parts = [
    for (final part in label.split(RegExp('[\u00A0 ]· ')))
      if (part.trim().isNotEmpty) part.trim().toLowerCase(),
  ];
  if (parts.isEmpty) return true;
  final names = _playerNames(stream);
  if (names.isEmpty) return true;
  return parts.every(names.contains);
}

String? _blankToNull(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
