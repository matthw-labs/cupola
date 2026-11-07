/// One item anywhere in a media server's tree: film, show, season, episode,
/// album or track.
///
/// **One type for every depth, on purpose.** A Jellyfin `BaseItemDto` and a Plex
/// `Metadata` element describe all of those with the same fields, which is a real
/// difference from the arr side: Radarr, Sonarr and Lidarr each needed their own
/// model and their own detail screen, and the Stream service needs one of each.
/// That is why `ServiceRoutes.jellyfinItem` is a single recursive route.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/dot_separator.dart';

enum StreamItemKind {
  movie,
  series,
  season,
  episode,
  album,
  track,
  other;

  /// Whether this kind contains other items, and so navigates deeper rather than
  /// terminating in a detail page.
  bool get hasChildren =>
      this == StreamItemKind.series ||
      this == StreamItemKind.season ||
      this == StreamItemKind.album;
}

/// How a library's whole shelf is ordered.
///
/// A library page is the library, whole (decision `P-stream-library-browse`):
/// it opens in [name] order on every title it holds, and what a viewer is
/// partway through, is up to next or was just added lives where watching is
/// the subject, the server's Activity and the glance of its Overview. The
/// browse took those once as lenses that opened the page, so a library never
/// read as the arrs' list twice; a person who opens a library wants to browse
/// it, and the history has its own room.
///
/// Every value was measured on the three servers before it was offered:
/// Jellyfin and Emby take each `SortBy` with the name as a tie-break (an Emby
/// that does not know a `SortBy` answers 500, so nothing unmeasured is sent),
/// Plex its `sort` the same way.
enum StreamLibrarySort {
  /// A to Z by the server's sort title (`The Matrix` under M).
  name(label: 'Name'),

  /// The latest the server added first.
  dateAdded(label: 'Date added'),

  /// The newest release year first, A to Z within a year.
  year(label: 'Year');

  const StreamLibrarySort({required this.label});

  final String label;
}

/// The external database ids a media server holds for one item: the other half
/// of the join with the arrs, which know a title by the same ids.
///
/// Read from the item itself (Jellyfin's `ProviderIds`, Plex's `Guid[]`), never
/// copied from the query that found it: they exist to *check* that query's
/// answer, and an id echoed back from the request would check nothing.
///
/// Values are stored as the server sent them, trimmed; comparison is the
/// matcher's business (`stream_external_match.dart`).
@immutable
class StreamExternalIds {
  final String? tmdb;
  final String? tvdb;
  final String? imdb;

  const StreamExternalIds({this.tmdb, this.tvdb, this.imdb});

  /// An item the server reported no comparable id for.
  static const StreamExternalIds none = StreamExternalIds();

  bool get isEmpty => tmdb == null && tvdb == null && imdb == null;

  @override
  bool operator ==(Object other) =>
      other is StreamExternalIds &&
      other.tmdb == tmdb &&
      other.tvdb == tvdb &&
      other.imdb == imdb;

  @override
  int get hashCode => Object.hash(tmdb, tvdb, imdb);

  @override
  String toString() =>
      'StreamExternalIds(tmdb: $tmdb, tvdb: $tvdb, imdb: $imdb)';
}

/// The picture a server holds for an item: its frame and its dynamic range,
/// as far as the read reported them.
@immutable
class StreamVideo {
  const StreamVideo({this.width, this.height, this.range});

  final int? width;
  final int? height;

  /// The dynamic range in the words the app shows (`HDR10`, `HDR10+`, `Dolby
  /// Vision`, `HLG`, `HDR`); null for SDR, and when the server did not say.
  final String? range;

  /// The resolution class, `2160p`, `1080p`, `720p`, `576p`, `480p`, from
  /// whichever side reaches it: a scope film at 1920 × 800 is 1080p. Null
  /// when the server reported no frame.
  String? get resolution {
    final width = this.width ?? 0;
    final height = this.height ?? 0;
    if (width <= 0 && height <= 0) return null;
    if (width >= 3200 || height >= 1800) return '2160p';
    if (width >= 1700 || height >= 1000) return '1080p';
    if (width >= 1200 || height >= 700) return '720p';
    if (height >= 560) return '576p';
    if (height >= 470) return '480p';
    return height > 0 ? '${height}p' : null;
  }

  /// `2160p · HDR10`: what the row says of the picture, or empty.
  String get words => [?resolution, ?range].join(dotSeparator);

  /// Jellyfin's `VideoRangeType` (or, from older servers, `VideoRange`) in the
  /// app's words.
  static String? rangeWord(Object? rangeType, Object? range) {
    final type = rangeType?.toString() ?? '';
    if (type.startsWith('DOVI')) return 'Dolby Vision';
    return switch (type) {
      'HDR10Plus' => 'HDR10+',
      'HDR10' => 'HDR10',
      'HLG' => 'HLG',
      _ when range?.toString() == 'HDR' => 'HDR',
      _ => null,
    };
  }
}

@immutable
class StreamItem {
  /// Opaque server id: a Jellyfin GUID or a Plex `ratingKey`.
  final String id;

  final String title;

  /// Series name for an episode, artist for a track, year for a film.
  final String? subtitle;

  final StreamItemKind kind;

  /// Relative artwork path; resolved by the client layer, which owns the
  /// credential. See [StreamSession.posterPath] for why this is not a URL.
  final String? posterPath;

  /// Relative path of the item's wide artwork (a backdrop, or an episode's
  /// series backdrop), resolved like [posterPath]; null when the server has
  /// none or the read did not carry it.
  final String? backdropPath;

  final int? year;

  /// Total runtime in milliseconds.
  ///
  /// Milliseconds rather than either server's native unit, because the two
  /// disagree and both are traps: Jellyfin counts .NET *ticks* (100ns, so
  /// `/ 10000`) and Plex counts milliseconds for `duration`/`viewOffset` but
  /// *epoch seconds* for `addedAt`/`lastViewedAt`. Normalising at the client
  /// boundary is what keeps a two-hour film from rendering as two minutes.
  final int? runtimeMs;

  /// Whether this item is fully watched **by the viewer this was fetched for**.
  final bool isPlayed;

  /// Resume position in milliseconds, when part-watched.
  final int? resumeOffsetMs;

  /// Unwatched children, for a series or season badge.
  final int? unplayedChildCount;

  /// The TMDB / TVDB / IMDb ids the server holds for this item, when the
  /// request asked for them; see [StreamExternalIds]. Empty is "not reported",
  /// never "has none". The browse reads ask too: a movie with a TMDB id opens
  /// on its own page (`MediaKey.ofStreamItem`).
  final StreamExternalIds externalIds;

  /// The server's synopsis, when the read carried it: what the Media page
  /// says of a title only a media server knows.
  final String? overview;

  /// The season an episode is in, or a season's own number, as the server
  /// numbers them (the specials are 0); null for anything else, and for one
  /// the server has not numbered.
  final int? seasonNumber;

  /// An episode's number in its season, as the server numbers it; null for
  /// anything else, and for an episode the server has not numbered.
  final int? episodeNumber;

  /// The id, on this server, of the series a season or an episode belongs
  /// to: what the series' own page is read by. Null for anything else, and
  /// for a season or an episode the read did not name a series for (a search
  /// hint does not).
  final String? seriesId;

  /// The picture of the item's first version, when the read asked for it.
  /// Null is "not reported": only the Media page's lookup asks.
  final StreamVideo? video;

  const StreamItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.posterPath,
    required this.year,
    required this.runtimeMs,
    required this.isPlayed,
    required this.resumeOffsetMs,
    required this.unplayedChildCount,
    this.externalIds = StreamExternalIds.none,
    this.video,
    this.overview,
    this.seasonNumber,
    this.episodeNumber,
    this.seriesId,
    this.backdropPath,
  });

  /// Fraction watched, 0..1, or null when there is no resume point.
  double? get resumeProgress {
    final offset = resumeOffsetMs;
    final total = runtimeMs;
    if (offset == null || total == null || total <= 0) return null;
    return (offset / total).clamp(0.0, 1.0);
  }

  bool get isInProgress => resumeProgress != null && !isPlayed;
}
