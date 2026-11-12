/// The parsed air time of each episode, keyed by the episode. Weak, so an
/// episode that leaves the cache takes its entry with it.
final _airsAt = Expando<_Airs>('sonarrEpisodeAirsAt');

/// A cached air time; a box, because a null air time is an answer too.
class _Airs {
  const _Airs(this.value);

  final DateTime? value;
}

DateTime? _parseAirs(String? airDateUtc, String? airDate) {
  final utc = airDateUtc?.trim();
  if (utc != null && utc.isNotEmpty) {
    final parsed = DateTime.tryParse(utc);
    if (parsed != null) return parsed;
  }

  final local = airDate?.trim();
  if (local != null && local.isNotEmpty) return DateTime.tryParse(local);

  return null;
}

class SonarrEpisode {
  final int id;
  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final bool hasFile;
  final bool monitored;

  /// Broadcast date in the series' own timezone, `YYYY-MM-DD`.
  ///
  /// The one fact that makes an episode row decidable without a second request:
  /// the row used to be a number, a truncated title and a magnifier, which is
  /// nothing to choose between. Sonarr returns both this and [airDateUtc] on
  /// `/api/v3/episode` by default, so neither costs an extra call.
  final String? airDate;

  /// Broadcast instant in UTC, used to tell an unaired episode from a missing
  /// one: "Not released" and "Missing" are very different rows.
  final String? airDateUtc;

  /// Episode length in minutes, when Sonarr knows it.
  final int? runtime;

  /// The file Sonarr holds for it (`episodefile`), when it has one.
  final int? episodeFileId;

  /// Sonarr's synopsis of the episode, when its metadata has one.
  final String? overview;

  const SonarrEpisode({
    required this.id,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    required this.hasFile,
    required this.monitored,
    this.airDate,
    this.airDateUtc,
    this.runtime,
    this.episodeFileId,
    this.overview,
  });

  /// When this episode airs, preferring the UTC instant over the local date.
  ///
  /// Parsed once per episode: a season's build asks for it several times for
  /// every episode, and a constant constructor leaves nowhere to keep it.
  DateTime? get airsAt {
    final cached = _airsAt[this];
    if (cached != null) return cached.value;
    final parsed = _parseAirs(airDateUtc, airDate);
    _airsAt[this] = _Airs(parsed);
    return parsed;
  }

  /// True when the broadcast has a date and the date is in the future.
  ///
  /// An episode with no air date is not unaired: Sonarr leaves the field
  /// empty for older catalogues too, and reporting "Not aired" for something
  /// from 1994 would be false. It is not aired either: see [hasAiredAt].
  bool isUnairedAt(DateTime now) {
    final airsAt = this.airsAt;
    if (airsAt == null) return false;
    return airsAt.isAfter(now);
  }

  /// True when the episode counts as broadcast, as Sonarr counts it: a date
  /// that has passed, or, with no date at all, a file on disk.
  ///
  /// An episode with no date and no file (Sonarr's `TBA`) has not aired:
  /// Sonarr's Wanted leaves it out and its statistics do not count it, so it
  /// is never `Missing` and never one of a season's aired episodes.
  bool hasAiredAt(DateTime now) {
    final airsAt = this.airsAt;
    if (airsAt == null) return hasFile;
    return !airsAt.isAfter(now);
  }

  factory SonarrEpisode.fromJson(Map<String, dynamic> json) {
    final episodeNumber = (json['episodeNumber'] as num?)?.toInt() ?? 0;

    return SonarrEpisode(
      id: (json['id'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['seasonNumber'] as num?)?.toInt() ?? 0,
      episodeNumber: episodeNumber,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Episode ${episodeNumber == 0 ? '?' : episodeNumber}',
      hasFile: json['hasFile'] as bool? ?? false,
      monitored: json['monitored'] as bool? ?? false,
      airDate: json['airDate'] as String?,
      airDateUtc: json['airDateUtc'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
      episodeFileId: switch ((json['episodeFileId'] as num?)?.toInt()) {
        final id? when id > 0 => id,
        _ => null,
      },
      overview: (json['overview'] as String?)?.trim().isNotEmpty == true
          ? (json['overview'] as String).trim()
          : null,
    );
  }
}
