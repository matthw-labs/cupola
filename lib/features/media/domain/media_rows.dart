import 'package:cupola/features/discover/domain/seerr_media_copy.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One row of a Media page's "On your server": one fact, from one source.
///
/// Each row declares its case before it is drawn (brand book,
/// *Configurations*): a connection Cupola has and what it said (cases c, d, e
/// travel in its reading), a claim Seerr makes about a server Cupola does not
/// have (case b), or a service nobody set up (case a). Case f draws no row.
sealed class MediaRow {
  const MediaRow();

  /// The service the row speaks for.
  ServiceKey get service;
}

/// A connection Cupola has, and its reading of the title.
///
/// [T] is the source's fact: `MediaRadarrCopy`, `MediaStreamCopy`,
/// `MediaBazarrCopy?` or `MediaSeerrRecord`.
final class MediaConnectionRow<T> extends MediaRow {
  const MediaConnectionRow(this.connection, this.reading);

  final ServiceInstance connection;
  final MediaReading<T> reading;

  @override
  ServiceKey get service => connection.service;
}

/// Case b: a copy Seerr says an arr holds, on a server Cupola has no
/// connection to. Seerr's word, attributed, with one quiet way to set the
/// server up (rule 9); never drawn as set up.
final class MediaThroughSeerrRow extends MediaRow {
  const MediaThroughSeerrRow({
    required this.seerr,
    required this.copy,
    required this.mediaInfo,
  });

  /// The Seerr connection that made the claim.
  final ServiceInstance seerr;

  /// The copy, bound to Seerr's server for it.
  final SeerrBoundCopy copy;

  /// Seerr's media row, for the copy's status (`status` or `status4k`).
  final Map<String, dynamic>? mediaInfo;

  @override
  ServiceKey get service => copy.arr;
}

/// Case b for a player: Seerr says the title is on the media server it is set
/// up with, and Cupola has no media server of its own. Seerr's word and its
/// link to the title there, with one quiet way to set the server up
/// (rule 9): no progress, no episodes, never drawn as set up.
final class MediaServerThroughSeerrRow extends MediaRow {
  const MediaServerThroughSeerrRow({
    required this.seerr,
    required this.server,
    required this.mediaInfo,
    required this.url,
  });

  /// The Seerr connection that made the claim.
  final ServiceInstance seerr;

  /// Jellyfin, Plex or Emby: the server Seerr is set up with. Null while Seerr
  /// has not said which yet: the row draws nothing, and the lead waits for it.
  final ServiceKey? server;

  /// Seerr's media row, for the status and a series' seasons.
  final Map<String, dynamic>? mediaInfo;

  /// Seerr's link to the title in that server (`mediaUrl`).
  final Uri url;

  /// Unnamed, it draws nothing and leads nowhere; Jellyfin stands in.
  @override
  ServiceKey get service => server ?? ServiceKey.jellyfin;
}

/// Case a: [service] is not set up and nothing else knows it. One dimmed,
/// tappable row that opens its setup form (rule 3).
final class MediaNotSetUpRow extends MediaRow {
  const MediaNotSetUpRow(this.service);

  @override
  final ServiceKey service;
}
