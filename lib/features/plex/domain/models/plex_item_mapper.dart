/// Plex `Metadata` / `Directory` elements → the shared Stream models.
///
/// Every function here is top-level and pure, which is a hard requirement rather
/// than a style: the client hands whole pages to `Isolate.run`, and a closure
/// that captured the client (and through it a `Dio`) could not be sent. That is
/// CONTEXT.md §3.6, and it is the reason this file exists apart from
/// `plex_client.dart`.
///
/// Plex describes a film, a show, a season, an episode, an album and a track
/// with the *same* `Metadata` element, and a `/status/sessions` entry is one of
/// those with `User`, `Player` and `Session` grafted on: so one mapper covers
/// every depth.
library;

import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/domain/models/plex_transcode_session.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';

/// Maps a `Metadata` array, dropping anything that is not a local item.
List<StreamItem> plexItemsFromMetadata(List<dynamic> metadata) {
  return metadata
      .whereType<Map>()
      .map((raw) => plexItemFromJson(raw.cast<String, dynamic>()))
      .nonNulls
      .toList(growable: false);
}

/// Maps one `Metadata` element, or null when it is not the user's own server's.
StreamItem? plexItemFromJson(Map<String, dynamic> json) {
  if (!plexIsServerItem(json)) return null;

  // Officially "an opaque string… while it often appears to be numeric, this is
  // not guaranteed", which is why nothing in this file models it as an int.
  final ratingKey = plexString(json['ratingKey']);
  if (ratingKey == null) return null;

  final kind = plexItemKindFromType(json['type']);
  final title = plexString(json['title']) ?? '';
  final parentTitle = plexString(json['parentTitle']);
  final grandparentTitle = plexString(json['grandparentTitle']);

  final viewCount = plexInt(json['viewCount']) ?? 0;
  final viewOffset = plexInt(json['viewOffset']);
  final leafCount = plexInt(json['leafCount']);
  final viewedLeafCount = plexInt(json['viewedLeafCount']);

  // There is no boolean `watched` anywhere in the API. A leaf is watched when
  // `viewCount >= 1`; a container is watched when every leaf is.
  final isPlayed = leafCount != null && leafCount > 0
      ? (viewedLeafCount ?? 0) >= leafCount
      : viewCount >= 1;

  // `viewedLeafCount` is omitted on a show nobody has started, so an absent
  // value alongside a present `leafCount` means zero watched: treating it as
  // unknown would hide the badge on exactly the shows the badge is for.
  final unplayed = leafCount == null
      ? null
      : leafCount - (viewedLeafCount ?? 0);

  return StreamItem(
    id: ratingKey,
    title: title,
    subtitle: switch (kind) {
      // Contract: an episode's subtitle is the series name, a track's is the
      // artist. Both live on `grandparentTitle`: Plex names the levels by
      // distance, not by role.
      StreamItemKind.episode => grandparentTitle,
      StreamItemKind.track => grandparentTitle ?? parentTitle,
      StreamItemKind.season => parentTitle,
      StreamItemKind.album => parentTitle,
      StreamItemKind.movie => plexInt(json['year'])?.toString(),
      _ => parentTitle,
    },
    kind: kind,
    posterPath:
        plexArtworkKey(json['thumb']) ??
        plexArtworkKey(json['parentThumb']) ??
        plexArtworkKey(json['grandparentThumb']),
    // `art` is Plex's background; an episode's is its show's.
    backdropPath: kind == StreamItemKind.episode
        ? plexArtworkKey(json['grandparentArt']) ?? plexArtworkKey(json['art'])
        : plexArtworkKey(json['art']),
    year: plexInt(json['year']),
    // Already milliseconds on Plex, unlike Jellyfin's 100ns ticks.
    runtimeMs: plexInt(json['duration']),
    isPlayed: isPlayed,
    // Absent means "no resume point", which is not the same as 0. And a 0 that
    // reached the UI would render a progress bar at the very start of an
    // untouched item.
    resumeOffsetMs: (viewOffset ?? 0) > 0 ? viewOffset : null,
    unplayedChildCount: unplayed != null && unplayed > 0 ? unplayed : null,
    externalIds: plexExternalIds(json),
    // A list read carries the frame; the range needs the item's own streams.
    video: switch (_firstMedia(json)) {
      final media? => StreamVideo(
        width: plexInt(media['width']),
        height: plexInt(media['height']),
      ),
      null => null,
    },
    overview: plexString(json['summary'])?.trim(),
    // Plex names the levels by distance, not by role: an episode's season is
    // its parent's number (`parentIndex`) and a season's own is its `index`.
    seasonNumber: switch (kind) {
      StreamItemKind.episode => plexInt(json['parentIndex']),
      StreamItemKind.season => plexInt(json['index']),
      _ => null,
    },
    episodeNumber: kind == StreamItemKind.episode
        ? plexInt(json['index'])
        : null,
    // The show is an episode's grandparent and a season's parent.
    seriesId: switch (kind) {
      StreamItemKind.episode => plexString(json['grandparentRatingKey']),
      StreamItemKind.season => plexString(json['parentRatingKey']),
      _ => null,
    },
  );
}

/// The item's own external ids, from `Guid[]` (`imdb://tt0133093`,
/// `tmdb://603`, `tvdb://169`) and, for an item still on a legacy agent, from
/// its `guid` attribute (`com.plexapp.agents.themoviedb://603?lang=en`).
///
/// `Guid[]` only arrives with `includeGuids=1`, which the browse reads and the
/// arr join send.
/// It wins over the legacy attribute per provider: it is what the modern agents
/// write and what `?guid=` filters on.
///
/// A legacy value with a path after the id is **not** the item's id and is
/// skipped: an episode on the TVDB agent reads `thetvdb://81189/1/1`, and 81189
/// is its *series*. Recording it would let that episode answer for the show.
StreamExternalIds plexExternalIds(Map<String, dynamic> json) {
  final found = <String, String>{};

  final guids = json['Guid'];
  if (guids is List) {
    for (final entry in guids.whereType<Map>()) {
      final parsed = _plexGuid(plexString(entry['id']));
      if (parsed != null) found.putIfAbsent(parsed.$1, () => parsed.$2);
    }
  }

  final legacy = _plexGuid(plexString(json['guid']));
  if (legacy != null) found.putIfAbsent(legacy.$1, () => legacy.$2);

  return StreamExternalIds(
    tmdb: found['tmdb'],
    tvdb: found['tvdb'],
    imdb: found['imdb'],
  );
}

/// `scheme://value[?query]` → `(provider, value)` for the three providers the
/// arr join speaks, or null for anything else (`plex://movie/…`, `local://…`).
(String, String)? _plexGuid(String? guid) {
  if (guid == null) return null;
  final separator = guid.indexOf('://');
  if (separator <= 0) return null;

  final provider = switch (guid.substring(0, separator).toLowerCase()) {
    'tmdb' || 'com.plexapp.agents.themoviedb' => 'tmdb',
    'tvdb' || 'com.plexapp.agents.thetvdb' => 'tvdb',
    'imdb' || 'com.plexapp.agents.imdb' => 'imdb',
    _ => null,
  };
  if (provider == null) return null;

  var value = guid.substring(separator + 3);
  final query = value.indexOf('?');
  if (query >= 0) value = value.substring(0, query);
  value = value.trim();
  if (value.isEmpty || value.contains('/')) return null;
  return (provider, value);
}

/// Maps Plex's `type` string onto the shared item vocabulary.
///
/// `artist` is the one place this bends. [StreamItemKind] has no artist member,
/// and the enum's only behavioural consumer is `hasChildren`: so mapping an
/// artist to `other` would assert that an artist contains nothing and dead-end
/// a music browse before it reaches an album. `album` keeps the traversal
/// artist → album → track working and is wrong only about the level's name.
StreamItemKind plexItemKindFromType(dynamic type) {
  switch (plexString(type)?.toLowerCase()) {
    case 'movie':
      return StreamItemKind.movie;
    case 'show':
      return StreamItemKind.series;
    case 'season':
      return StreamItemKind.season;
    case 'episode':
      return StreamItemKind.episode;
    case 'artist':
    case 'album':
      return StreamItemKind.album;
    case 'track':
      return StreamItemKind.track;
    default:
      return StreamItemKind.other;
  }
}

/// A search hub's `type` → the kind that band holds, or null when the shared
/// vocabulary has no word for it.
///
/// **Not [plexItemKindFromType], and the difference is deliberate.** That
/// function answers "what should this row behave like", so it bends `artist`
/// onto `album` to keep a music browse traversable and folds everything unknown
/// onto `other`. A *band* is a different question: what is this group of hits
/// about, and neither answer survives it: an Artists hub does not hold albums,
/// and an Actors hub labelled `other` would claim a vocabulary entry the app
/// does not have. Null says so, and the band still draws from the hub's own
/// title.
StreamItemKind? plexHubKind(dynamic type) {
  switch (plexString(type)?.toLowerCase()) {
    case 'movie':
      return StreamItemKind.movie;
    case 'show':
      return StreamItemKind.series;
    case 'season':
      return StreamItemKind.season;
    case 'episode':
      return StreamItemKind.episode;
    case 'album':
      return StreamItemKind.album;
    case 'track':
      return StreamItemKind.track;
    default:
      return null;
  }
}

/// Maps a `/library/sections` `Directory` element.
StreamLibrary? plexLibraryFromJson(Map<String, dynamic> json) {
  // Relative to `/library/sections`, so `'1'` and not `'/library/sections/1'`.
  final key = plexString(json['key']);
  if (key == null) return null;
  return StreamLibrary(
    id: key,
    name: plexString(json['title']) ?? key,
    kind: plexLibraryKindFromType(json['type']),
    // Plex does not put a count on the section; `getLibraryItemCount` fetches
    // one on request rather than making the dashboard pay per library.
    itemCount: null,
    // Plex is the server that *does* report this per section, which is why
    // `StreamLibrary.lastScannedAt` exists at all, and it is epoch seconds.
    lastScannedAt: plexEpochSeconds(json['scannedAt']),
    isRefreshing: plexBool(json['refreshing']) ?? false,
  );
}

StreamLibraryKind plexLibraryKindFromType(dynamic type) {
  switch (plexString(type)?.toLowerCase()) {
    case 'movie':
      return StreamLibraryKind.movies;
    case 'show':
      return StreamLibraryKind.shows;
    case 'artist':
      return StreamLibraryKind.music;
    case 'photo':
      return StreamLibraryKind.photos;
    default:
      return StreamLibraryKind.other;
  }
}

/// Maps one `/status/sessions` entry.
///
/// A session is an ordinary `Metadata` object with `User`, `Player`, `Session`
/// and possibly `TranscodeSession` grafted on, so most of it is read the same
/// way [plexItemFromJson] reads a library row.
StreamSession? plexSessionFromJson(Map<String, dynamic> json) {
  final transcode = PlexTranscodeSession.maybeFrom(json);
  final player = _childObject(json['Player']);
  final user = _childObject(json['User']);
  final session = _childObject(json['Session']);

  final kind = plexItemKindFromType(json['type']);
  final title = plexString(json['title']) ?? '';
  final parentTitle = plexString(json['parentTitle']);
  final grandparentTitle = plexString(json['grandparentTitle']);

  final durationMs = plexInt(json['duration']);
  final viewOffsetMs = plexInt(json['viewOffset']);

  return StreamSession(
    // `Session.id`. Empty when the server reported no nested `Session` element,
    // in which case there is nothing to terminate: `stopSession` refuses an
    // empty id locally rather than sending one and getting a misleading 403.
    id: plexString(session?['id']) ?? '',
    // Empty rather than a placeholder: how an unnamed viewer reads is the
    // board's decision, not the client's.
    userName: plexString(user?['title']) ?? '',
    // For an episode the headline is the series and the subtitle carries the
    // episode: the inverse of a library row, where the episode is the thing
    // being listed.
    title: kind == StreamItemKind.episode ? (grandparentTitle ?? title) : title,
    subtitle: switch (kind) {
      StreamItemKind.episode => _episodeSubtitle(json, title),
      StreamItemKind.track => [
        grandparentTitle,
        parentTitle,
      ].nonNulls.join(dotSeparator).ifEmptyNull,
      StreamItemKind.movie => plexInt(json['year'])?.toString(),
      _ => parentTitle,
    },
    // `Infuse · iPhone`: the app first, then the hardware it is running on.
    deviceLabel: [
      plexString(player?['product']),
      plexString(player?['device']) ??
          plexString(player?['platform']) ??
          plexString(player?['title']),
    ].nonNulls.join(dotSeparator),
    posterPath: kind == StreamItemKind.episode
        // The series poster reads better than an episode still at grid size.
        ? plexArtworkKey(json['grandparentThumb']) ??
              plexArtworkKey(json['parentThumb']) ??
              plexArtworkKey(json['thumb'])
        : plexArtworkKey(json['thumb']) ??
              plexArtworkKey(json['parentThumb']) ??
              plexArtworkKey(json['grandparentThumb']),
    // `art` is Plex's background, an episode's its show's; an episode's own
    // `thumb` is a still of it, as wide.
    backdropPath: kind == StreamItemKind.episode
        ? plexArtworkKey(json['grandparentArt']) ??
              plexArtworkKey(json['art']) ??
              plexArtworkKey(json['thumb'])
        : plexArtworkKey(json['art']),
    // No `TranscodeSession` at all is the *only* signal Plex gives for a direct
    // play; there is no field that says so.
    playMethod: transcode?.playMethod ?? StreamPlayMethod.directPlay,
    transcodeReasons: transcode?.reasons ?? const [],
    // `Session.bandwidth` is kilobits per second; the model is bits per second.
    // Falls back to the file's own bitrate, also kbps, when the server did not
    // reserve bandwidth for this stream.
    bitrate: _bitsPerSecond(
      plexInt(session?['bandwidth']) ?? plexInt(_firstMedia(json)?['bitrate']),
    ),
    // **Always true on Plex.** `Session.bandwidth` is a reservation made by
    // Plex's streaming brain, not measured egress, and `Media.bitrate` describes
    // the file. Neither is throughput, and labelling either as such, or summing
    // them into a "total", would be a fabricated claim.
    bitrateIsNominal: true,
    progress: durationMs != null && durationMs > 0 && viewOffsetMs != null
        ? (viewOffsetMs / durationMs).clamp(0.0, 1.0)
        : null,
    isPaused: plexString(player?['state'])?.toLowerCase() == 'paused',
    remaining: durationMs != null && durationMs > 0 && viewOffsetMs != null
        ? Duration(
            milliseconds: (durationMs - viewOffsetMs).clamp(0, durationMs),
          )
        : null,
    titleId: switch (kind) {
      StreamItemKind.episode => plexString(json['grandparentRatingKey']),
      StreamItemKind.movie => plexString(json['ratingKey']),
      _ => null,
    },
    itemId: plexString(json['ratingKey']),
    userId: plexString(user?['id']),
  );
}

/// `S1 E4 · Title`, skipping whatever the server did not send.
String? _episodeSubtitle(Map<String, dynamic> json, String title) {
  final code = formatPartialEpisodeCode(
    season: plexInt(json['parentIndex']),
    episode: plexInt(json['index']),
  );
  final parts = <String>[?code, if (title.isNotEmpty) title];
  return parts.isEmpty ? null : parts.join(dotSeparator);
}

/// Plex writes every child element as an array in JSON even when there is one of
/// them, but the container key itself is optional, and some builds send a bare
/// object for the singletons (`User`, `Player`, `Session`).
Map<String, dynamic>? _childObject(dynamic raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is List) {
    final first = raw.whereType<Map>().firstOrNull;
    return first?.cast<String, dynamic>();
  }
  return null;
}

Map<String, dynamic>? _firstMedia(Map<String, dynamic> json) =>
    _childObject(json['Media']);

/// kbps → bits per second. Null in, null out; a zero is not a bitrate.
int? _bitsPerSecond(int? kilobitsPerSecond) {
  if (kilobitsPerSecond == null || kilobitsPerSecond <= 0) return null;
  return kilobitsPerSecond * 1000;
}

extension _NullIfEmpty on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
