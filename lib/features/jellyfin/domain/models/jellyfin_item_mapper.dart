/// `BaseItemDto` / `SessionInfoDto` → the shared Stream models.
///
/// Every function here is top-level and pure, which is a hard requirement rather
/// than a style: the client hands whole pages to `Isolate.run`, and a closure
/// that captured the client (and through it a `Dio`) could not be sent.
///
/// Jellyfin describes a film, a series, a season, an episode, an album and a
/// track with the *same* `BaseItemDto`, so one mapper covers every depth; the
/// difference from the arr side that `StreamItem` was designed around.
library;

import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_transcode_reason.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_units.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';

/// Above this many rows, mapping moves to an isolate.
///
/// Same threshold and same reasoning as the qBittorrent list parse: a page of 50
/// costs less to map inline than to ship across a port, while an unpaged
/// `/Shows/{id}/Episodes` on a 400-episode series is exactly the jank this rule
/// exists for.
const int kJellyfinIsolateMapThreshold = 200;

/// Item types Jellyfin can return that the Stream models have a shape for.
///
/// `Video`, `MusicVideo`, `Folder`, `CollectionFolder`, `BoxSet`, `Book`,
/// `Photo`, `TvChannel` and friends all land on `other`: they render, they just
/// do not claim a vocabulary they do not have.
StreamItemKind jellyfinItemKind(Object? rawType) {
  switch (rawType?.toString()) {
    case 'Movie':
      return StreamItemKind.movie;
    case 'Series':
      return StreamItemKind.series;
    case 'Season':
      return StreamItemKind.season;
    case 'Episode':
      return StreamItemKind.episode;
    case 'MusicAlbum':
      return StreamItemKind.album;
    case 'Audio':
      return StreamItemKind.track;
    default:
      return StreamItemKind.other;
  }
}

/// The server-relative artwork path for an item, or null when it has no image.
///
/// Deliberately a *path* and not a URL, per `StreamItem.posterPath`: resolving it
/// needs the credential, and the credential must stay in a header so it never
/// becomes part of `CachedNetworkImage`'s cache key.
///
/// `?tag=` is carried along because Jellyfin's image route is otherwise
/// indistinguishable across edits: replace a poster and every cache in the chain
/// keeps serving the old bytes from the identical URL. The tag is the server's own
/// content hash, so it is both the correct cache key and free.
///
/// **Order: the item's own art, then its parent's.** `Primary` first, then the
/// other types the item actually has: an episode is routinely `Thumb`-only, and
/// asking for a `Primary` that does not exist 404s. Only when the item has no art
/// at all does this fall back to `SeriesPrimaryImageTag` (or an album's parent),
/// which is what keeps an episode list from rendering as a grid of grey
/// rectangles. Trying the series *before* the item's own `Thumb` would be the
/// worse rule: it would show the series poster for a `Thumb`-only episode while
/// showing the episode's own wide still for one that has a `Primary`, so two rows
/// of the same list would disagree about what they are picturing.
String? jellyfinPosterPath(Map<String, dynamic> item) {
  final id = item['Id']?.toString();
  final imageTags = item['ImageTags'];
  if (id != null && id.isNotEmpty && imageTags is Map) {
    for (final type in const [
      'Primary',
      'Thumb',
      'Backdrop',
      'Banner',
      'Art',
      'Logo',
    ]) {
      final tag = imageTags[type]?.toString();
      if (tag != null && tag.isNotEmpty) {
        return '/Items/$id/Images/$type?tag=$tag';
      }
    }
  }

  final seriesId = item['SeriesId']?.toString();
  final seriesTag = item['SeriesPrimaryImageTag']?.toString();
  if (seriesId != null &&
      seriesId.isNotEmpty &&
      seriesTag != null &&
      seriesTag.isNotEmpty) {
    return '/Items/$seriesId/Images/Primary?tag=$seriesTag';
  }

  // An album inherits the artist's or the parent folder's image.
  final parentId = item['AlbumId']?.toString() ?? item['ParentId']?.toString();
  final parentTag = item['AlbumPrimaryImageTag']?.toString();
  if (parentId != null &&
      parentId.isNotEmpty &&
      parentTag != null &&
      parentTag.isNotEmpty) {
    return '/Items/$parentId/Images/Primary?tag=$parentTag';
  }

  return null;
}

/// `S2 E4`, or `E4` / `S2` when only one of the two numbers is present.
///
/// Specials sit in season 0 and routinely arrive with a null `IndexNumber`, so
/// both halves have to be independently optional.
String? jellyfinEpisodeCode(Map<String, dynamic> item) {
  return formatPartialEpisodeCode(
    season: jellyfinInt(item['ParentIndexNumber']),
    episode: jellyfinInt(item['IndexNumber']),
  );
}

/// The artist credit for a track or an album.
String? _artistLabel(Map<String, dynamic> item) {
  final albumArtist = item['AlbumArtist']?.toString();
  if (albumArtist != null && albumArtist.trim().isNotEmpty) return albumArtist;
  final artists = item['Artists'];
  if (artists is List && artists.isNotEmpty) {
    return artists.map((value) => value.toString()).join(', ');
  }
  return null;
}

/// One line that disambiguates the title, per `StreamItem.subtitle`: the series
/// for an episode, the artist for a track, the year for a film.
String? _itemSubtitle(Map<String, dynamic> item, StreamItemKind kind) {
  final year = jellyfinInt(item['ProductionYear']);
  switch (kind) {
    case StreamItemKind.episode:
      final series = item['SeriesName']?.toString();
      final code = jellyfinEpisodeCode(item);
      // The series name alone is what the contract asks for, but an episode list
      // is unreadable without the numbers and the season name is not always set.
      return [
        if (series != null && series.isNotEmpty) series,
        ?code,
      ].join(dotSeparator).ifEmptyNull();
    case StreamItemKind.season:
      return item['SeriesName']?.toString().ifEmptyNull();
    case StreamItemKind.track:
      return _artistLabel(item) ?? item['Album']?.toString().ifEmptyNull();
    case StreamItemKind.album:
      return _artistLabel(item) ?? year?.toString();
    case StreamItemKind.movie:
    case StreamItemKind.series:
    case StreamItemKind.other:
      return year?.toString();
  }
}

/// Resume offset in milliseconds, or null when the item was never started.
///
/// `PlaybackPositionTicks` is authoritative. `PlayedPercentage` is the fallback
/// for the endpoints that summarise `UserData` without the tick field, and it is
/// a **0–100** double: the one place in this feature where a value that looks
/// like a fraction is not one.
int? _resumeOffsetMs(Map<String, dynamic> userData, Object? runtimeTicks) {
  final fromTicks = jellyfinMillisecondsFromTicks(
    userData['PlaybackPositionTicks'],
    zeroAsNull: true,
  );
  // Ticks are authoritative, so a present position ends the search either way.
  // Zero already arrives as null; a position under a millisecond *truncates* to
  // zero, which would slip past that guard and light up a resume bar pinned at
  // the left edge for something nobody has watched a frame of.
  if (fromTicks != null) return fromTicks > 0 ? fromTicks : null;

  final fraction = jellyfinFractionFromPercent(userData['PlayedPercentage']);
  final runtimeMs = jellyfinMillisecondsFromTicks(
    runtimeTicks,
    zeroAsNull: true,
  );
  if (fraction == null || fraction <= 0 || runtimeMs == null) return null;
  final offset = (runtimeMs * fraction).round();
  return offset > 0 ? offset : null;
}

/// The server-relative path of an item's wide artwork, or null when it has
/// none: its own backdrop, else the one it inherits (an episode's series),
/// else a thumb, else an episode's own still. Tagged like
/// [jellyfinPosterPath].
String? jellyfinBackdropPath(Map<String, dynamic> item) {
  String? first(Object? tags) =>
      tags is List && tags.isNotEmpty ? tags.first?.toString() : null;
  String? path(Object? id, String type, String? tag) {
    final owner = id?.toString();
    if (owner == null || owner.isEmpty || tag == null || tag.isEmpty) {
      return null;
    }
    return type == 'Backdrop'
        ? '/Items/$owner/Images/Backdrop/0?tag=$tag'
        : '/Items/$owner/Images/$type?tag=$tag';
  }

  final tags = item['ImageTags'];
  String? own(String type) => tags is Map ? tags[type]?.toString() : null;
  final episode = jellyfinItemKind(item['Type']) == StreamItemKind.episode;
  return path(item['Id'], 'Backdrop', first(item['BackdropImageTags'])) ??
      path(
        item['ParentBackdropItemId'],
        'Backdrop',
        first(item['ParentBackdropImageTags']),
      ) ??
      path(item['Id'], 'Thumb', own('Thumb')) ??
      path(
        item['ParentThumbItemId'],
        'Thumb',
        item['ParentThumbImageTag']?.toString(),
      ) ??
      // An episode's primary image is a still of it, as wide as a backdrop.
      (episode ? path(item['Id'], 'Primary', own('Primary')) : null);
}

/// One `BaseItemDto` → one [StreamItem].
StreamItem jellyfinStreamItemFromJson(Map<String, dynamic> item) {
  final kind = jellyfinItemKind(item['Type']);
  final rawUserData = item['UserData'];
  final userData = rawUserData is Map
      ? rawUserData.cast<String, dynamic>()
      : const <String, dynamic>{};
  final runtimeTicks = item['RunTimeTicks'];

  return StreamItem(
    id: item['Id']?.toString() ?? '',
    title: item['Name']?.toString() ?? '',
    subtitle: _itemSubtitle(item, kind),
    kind: kind,
    posterPath: jellyfinPosterPath(item),
    backdropPath: jellyfinBackdropPath(item),
    year: jellyfinInt(item['ProductionYear']),
    runtimeMs: jellyfinMillisecondsFromTicks(runtimeTicks, zeroAsNull: true),
    // `UserData` only exists on the response when the request passed
    // `enableUserData=true` *and* a userId; absent means "unknown", and false is
    // the honest reading of unknown for a watched flag.
    isPlayed: userData['Played'] == true,
    resumeOffsetMs: _resumeOffsetMs(userData, runtimeTicks),
    unplayedChildCount: jellyfinInt(userData['UnplayedItemCount']),
    externalIds: jellyfinExternalIds(item['ProviderIds']),
    video: _video(item['MediaStreams']),
    overview: _text(item['Overview']),
    // An episode's season is its parent's number; a season's own is its
    // `IndexNumber`.
    seasonNumber: switch (kind) {
      StreamItemKind.episode => jellyfinInt(item['ParentIndexNumber']),
      StreamItemKind.season => jellyfinInt(item['IndexNumber']),
      _ => null,
    },
    episodeNumber: kind == StreamItemKind.episode
        ? jellyfinInt(item['IndexNumber'])
        : null,
    seriesId: switch (kind) {
      StreamItemKind.episode ||
      StreamItemKind.season => _text(item['SeriesId']),
      _ => null,
    },
  );
}

/// [raw] trimmed, or null when it says nothing.
String? _text(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

/// The first video stream of `MediaStreams`, present only when the request
/// asked for that field.
StreamVideo? _video(Object? streams) {
  if (streams is! List) return null;
  for (final stream in streams) {
    if (stream is Map && stream['Type'] == 'Video') {
      return StreamVideo(
        width: jellyfinInt(stream['Width']),
        height: jellyfinInt(stream['Height']),
        range: StreamVideo.rangeWord(
          stream['VideoRangeType'],
          stream['VideoRange'],
        ),
      );
    }
  }
  return null;
}

/// `ProviderIds` → [StreamExternalIds].
///
/// Only present when the request listed `ProviderIds` in `fields`, which the
/// browse reads and the arr join do. The keys are Jellyfin's provider names (`Tmdb`, `Tvdb`,
/// `Imdb`) and are read case-insensitively, since plugins and older builds have
/// not always agreed on the casing; `TmdbCollection` and the other composite
/// keys are different ids and are ignored.
StreamExternalIds jellyfinExternalIds(Object? raw) {
  if (raw is! Map) return StreamExternalIds.none;
  String? read(String provider) {
    for (final entry in raw.entries) {
      if (entry.key.toString().toLowerCase() != provider) continue;
      final value = entry.value?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  return StreamExternalIds(
    tmdb: read('tmdb'),
    tvdb: read('tvdb'),
    imdb: read('imdb'),
  );
}

/// A whole page of items. The `Isolate.run` entry point, hence top-level.
List<StreamItem> jellyfinStreamItemsFromJson(Object? raw) =>
    jsonObjects(raw, jellyfinStreamItemFromJson);

/// One `SearchHint` from `GET /Search/Hints` → one [StreamItem].
///
/// **A hint is not a `BaseItemDto`, and the differences are all renames.** The
/// search endpoint returns its own flattened DTO: the id is `ItemId`, the series
/// is `Series` rather than `SeriesName`, and artwork arrives as loose
/// `*ImageTag` strings instead of the `ImageTags` map every other endpoint
/// sends. So this normalises the hint into the shape the one item mapper already
/// speaks and hands it over, rather than growing a second parallel mapper that
/// would drift on the subtitle rules within a release.
///
/// A hint carries **no `UserData`** at any `enableUserData` setting, so watch
/// state is absent by construction: every hit maps to `isPlayed: false` with no
/// resume point. That is a property of the endpoint, not a missing parameter:
/// a search page that wants the watch mark has to re-read the item.
StreamItem jellyfinSearchHintFromJson(Map<String, dynamic> hint) {
  final primaryTag = hint['PrimaryImageTag']?.toString();
  final thumbTag = hint['ThumbImageTag']?.toString();

  return jellyfinStreamItemFromJson({
    // `ItemId` is the hint's own spelling; `Id` appears on 10.9+ and is the same
    // value. Both are read so the mapper does not depend on the server version.
    'Id': hint['ItemId']?.toString() ?? hint['Id']?.toString() ?? '',
    'Name': hint['Name'],
    'Type': hint['Type'],
    'ProductionYear': hint['ProductionYear'],
    'RunTimeTicks': hint['RunTimeTicks'],
    'IndexNumber': hint['IndexNumber'],
    'ParentIndexNumber': hint['ParentIndexNumber'],
    'SeriesName': hint['Series'],
    'Album': hint['Album'],
    'AlbumArtist': hint['AlbumArtist'],
    if (primaryTag != null && primaryTag.isNotEmpty ||
        thumbTag != null && thumbTag.isNotEmpty)
      'ImageTags': {
        if (primaryTag != null && primaryTag.isNotEmpty) 'Primary': primaryTag,
        if (thumbTag != null && thumbTag.isNotEmpty) 'Thumb': thumbTag,
      },
  });
}

/// Jellyfin's `PlayMethod` → the shared decision enum.
///
/// A missing `PlayMethod` with a live `TranscodingInfo` is treated as a
/// transcode: the field is populated asynchronously as playback starts, and the
/// board must not spend those seconds claiming a stream is free.
StreamPlayMethod jellyfinPlayMethod(
  Object? rawPlayMethod, {
  required bool hasTranscodingInfo,
}) {
  switch (rawPlayMethod?.toString()) {
    case 'DirectPlay':
      return StreamPlayMethod.directPlay;
    case 'DirectStream':
      return StreamPlayMethod.directStream;
    case 'Transcode':
      return StreamPlayMethod.transcode;
    default:
      return hasTranscodingInfo
          ? StreamPlayMethod.transcode
          : StreamPlayMethod.directPlay;
  }
}

/// `Jellyfin Web · Chrome`: the client, then the device it runs on.
/// Whether the client announced it takes remote control: the session's own
/// `SupportsRemoteControl` or `SupportsMediaControl`, or the latter inside its
/// `Capabilities` (where Emby and older Jellyfin keep it). A client that
/// announced nothing is not listening for a Pause, whatever the 204 says.
bool _takesCommands(Map<String, dynamic> session) {
  final capabilities = session['Capabilities'];
  return session['SupportsRemoteControl'] == true ||
      session['SupportsMediaControl'] == true ||
      (capabilities is Map && capabilities['SupportsMediaControl'] == true);
}

/// The general commands the client announced, wherever the server put them.
Set<String> _supportedCommands(Map<String, dynamic> session) {
  final capabilities = session['Capabilities'];
  return {
    for (final source in [
      session['SupportedCommands'],
      if (capabilities is Map) capabilities['SupportedCommands'],
    ])
      if (source is List)
        for (final command in source) command.toString(),
  };
}

String _deviceLabel(Map<String, dynamic> session) {
  final client = session['Client']?.toString().trim() ?? '';
  final device = session['DeviceName']?.toString().trim() ?? '';
  if (client.isNotEmpty && device.isNotEmpty) return '$client\u00A0· $device';
  if (client.isNotEmpty) return client;
  if (device.isNotEmpty) return device;
  // `DeviceType` is the last resort; it is often null on third-party clients.
  return session['DeviceType']?.toString() ?? '';
}

/// The `Bitrate` of the media source that is actually being played.
///
/// The fallback for a direct play, which has no rate of its own anywhere in the
/// payload. It describes the *file*, not the wire, which is exactly what
/// `StreamSession.bitrateIsNominal` exists to declare.
///
/// [mediaSourceId] is `PlayState.MediaSourceId` and is what makes this correct on
/// a library that keeps more than one version of a film: `MediaSources` then holds
/// both the 4K remux and the 1080p encode, and only one of them is on the wire.
/// Picking the largest, or the first, would report a 60 Mbps remux for somebody
/// watching the 1080p file, on the one row the board exists to make trustworthy.
/// The largest is still the fallback for the case where the id names no source we
/// can see (a version deleted mid-playback, or a proxy that trimmed the array).
int? _nominalBitrate(Map<String, dynamic> nowPlaying, Object? mediaSourceId) {
  final sources = nowPlaying['MediaSources'];
  if (sources is List) {
    final playing = mediaSourceId?.toString().trim() ?? '';
    int? best;
    for (final source in sources) {
      if (source is! Map) continue;
      final bitrate = jellyfinBitsPerSecond(source['Bitrate']);
      if (bitrate == null) continue;
      if (playing.isNotEmpty && source['Id']?.toString() == playing) {
        return bitrate;
      }
      if (best == null || bitrate > best) best = bitrate;
    }
    if (best != null) return best;
  }
  return jellyfinBitsPerSecond(nowPlaying['Bitrate']);
}

/// One `SessionInfoDto` → one [StreamSession], or null when nothing is playing.
///
/// `/Sessions` returns every *connected* client, not every playing one: an idle
/// browser tab sits in that array for as long as it holds the WebSocket, with
/// `NowPlayingItem: null`. Filtering on that field is the only thing separating
/// "nobody is watching" from "seven people are watching".
StreamSession? jellyfinStreamSessionFromJson(Map<String, dynamic> session) {
  final rawNowPlaying = session['NowPlayingItem'];
  if (rawNowPlaying is! Map) return null;
  final nowPlaying = rawNowPlaying.cast<String, dynamic>();

  final rawPlayState = session['PlayState'];
  final playState = rawPlayState is Map
      ? rawPlayState.cast<String, dynamic>()
      : const <String, dynamic>{};
  final rawTranscoding = session['TranscodingInfo'];
  final transcoding = rawTranscoding is Map
      ? rawTranscoding.cast<String, dynamic>()
      : null;

  final playMethod = jellyfinPlayMethod(
    playState['PlayMethod'],
    hasTranscodingInfo: transcoding != null,
  );

  // A transcode reports the encoder's actual target, so that figure is real. Any
  // other method has no rate field at all and falls back to the source file's
  // bitrate: nominal, and flagged as such so the board can never present it as
  // measured throughput it does not have.
  final transcodeBitrate = transcoding == null
      ? null
      : jellyfinBitsPerSecond(transcoding['Bitrate']);
  final bitrate =
      transcodeBitrate ??
      _nominalBitrate(nowPlaying, playState['MediaSourceId']);

  final kind = jellyfinItemKind(nowPlaying['Type']);
  final name = nowPlaying['Name']?.toString() ?? '';
  final seriesName = nowPlaying['SeriesName']?.toString() ?? '';

  // For an episode the *series* is the headline and the episode is the detail:
  // the opposite of `StreamItem`, and what makes a session row readable at a
  // glance. See `StreamSession.title`.
  final isEpisode = kind == StreamItemKind.episode && seriesName.isNotEmpty;
  final episodeCode = jellyfinEpisodeCode(nowPlaying);

  return StreamSession(
    // `Id`, never `DeviceId`: the stop command 404s on any other identifier.
    id: session['Id']?.toString() ?? '',
    userName: session['UserName']?.toString() ?? '',
    title: isEpisode ? seriesName : name,
    subtitle: isEpisode
        ? [?episodeCode, name].join(dotSeparator).ifEmptyNull()
        : _itemSubtitle(nowPlaying, kind),
    deviceLabel: _deviceLabel(session),
    posterPath: jellyfinPosterPath(nowPlaying),
    backdropPath: jellyfinBackdropPath(nowPlaying),
    playMethod: playMethod,
    // A direct stream has reasons too, and dropping them was the bug: Jellyfin
    // remuxes *because of something* (an unsupported container, an external
    // subtitle track), and reports it in the same `TranscodeReasons` array. The
    // model says so at `StreamSession.transcodeReasons`, and Plex has always
    // passed its decisions through unconditionally, so the byte-identical
    // session explained itself on one server and not the other.
    //
    // Only a direct play is gated, and on the play method rather than on the
    // array being empty: nothing is being done to the file, so an array that
    // arrived anyway (a stale session row mid-transition) would explain
    // something that is not happening.
    transcodeReasons: playMethod == StreamPlayMethod.directPlay
        ? const []
        : jellyfinTranscodeReasonPhrases(transcoding?['TranscodeReasons']),
    bitrate: bitrate,
    bitrateIsNominal: transcodeBitrate == null,
    progress: jellyfinFractionFromTicks(
      position: playState['PositionTicks'],
      runtime: nowPlaying['RunTimeTicks'],
    ),
    isPaused: playState['IsPaused'] == true,
    remaining: jellyfinRemainingFromTicks(
      position: playState['PositionTicks'],
      runtime: nowPlaying['RunTimeTicks'],
    ),
    titleId: switch (kind) {
      StreamItemKind.episode => nowPlaying['SeriesId']?.toString(),
      StreamItemKind.movie => nowPlaying['Id']?.toString(),
      _ => null,
    }?.ifEmptyNull(),
    itemId: nowPlaying['Id']?.toString().ifEmptyNull(),
    userId: session['UserId']?.toString().ifEmptyNull(),
    takesCommands: _takesCommands(session),
    takesMessages:
        _takesCommands(session) &&
        _supportedCommands(session).contains('DisplayMessage'),
  );
}

/// Every playing session, most expensive first. The `Isolate.run` entry point.
///
/// "Most expensive" is the enum's own order (transcode → direct stream → direct
/// play), then bitrate, then the viewer's name so the list is stable between
/// polls: `List.sort` is not stable, and a board that reshuffled two identical
/// transcodes every three seconds would look broken.
List<StreamSession> jellyfinStreamSessionsFromJson(Object? raw) {
  if (raw is! List) return const [];
  final sessions = <StreamSession>[];
  for (final element in raw) {
    if (element is! Map) continue;
    final session = jellyfinStreamSessionFromJson(
      element.cast<String, dynamic>(),
    );
    if (session != null) sessions.add(session);
  }

  sessions.sort((a, b) {
    final byMethod = b.playMethod.index.compareTo(a.playMethod.index);
    if (byMethod != 0) return byMethod;
    final byBitrate = (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    if (byBitrate != 0) return byBitrate;
    return a.userName.compareTo(b.userName);
  });
  return sessions;
}

extension _NullIfEmpty on String {
  /// `''` is never a useful subtitle; null lets the widget drop the line.
  String? ifEmptyNull() => trim().isEmpty ? null : this;
}
