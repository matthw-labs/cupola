import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';

/// How a title is named in the path of `media/{ref}` reads.
///
/// The contract types it as a plain string and describes no form. We know two
/// (a Tracearr media id, and `movie:tmdb:603`); the series forms follow the same
/// pattern but are our reading of it, to be confirmed on the lab. Anything else
/// goes through [TracearrMediaRef.raw].
final class TracearrMediaRef {
  const TracearrMediaRef.raw(this.value);

  /// Tracearr's own id of a title.
  const TracearrMediaRef.id(String mediaId) : value = mediaId;

  TracearrMediaRef.movieTmdb(int tmdbId) : value = 'movie:tmdb:$tmdbId';

  /// A series, by its TMDB id.
  TracearrMediaRef.showTmdb(int tmdbId) : value = 'show:tmdb:$tmdbId';

  /// A series, by its TVDB id.
  TracearrMediaRef.showTvdb(int tvdbId) : value = 'show:tvdb:$tvdbId';

  final String value;

  @override
  String toString() => 'TracearrMediaRef($value)';
}

/// One person's viewing of a title.
///
/// Who watched what is theirs: [toString] prints none of it.
final class TracearrWatcher {
  const TracearrWatcher({
    this.userId,
    this.serverUserId,
    this.username,
    this.identityName,
    this.plays = 0,
    this.watchTimeMs = 0,
    this.completionPct,
    this.lastWatchedDay,
    this.distinctEpisodesWatched,
  });

  factory TracearrWatcher.fromJson(TracearrJson json) {
    final user = json.object('user');
    return TracearrWatcher(
      userId: user?.text('user_id'),
      serverUserId: user?.text('server_user_id'),
      username: user?.text('username'),
      identityName: user?.text('identity_name'),
      plays: json.integer('plays') ?? 0,
      watchTimeMs: json.integer('watch_time_ms') ?? 0,
      completionPct: json.number('completion_pct'),
      lastWatchedDay: json.time('last_watched_day'),
      distinctEpisodesWatched: json.integer('distinct_episodes_watched'),
    );
  }

  /// Tracearr's id of the person across servers.
  final String? userId;
  final String? serverUserId;
  final String? username;
  final String? identityName;

  final int plays;
  final int watchTimeMs;

  /// 0 to 100; for a series, how much of it.
  final double? completionPct;

  /// The calendar day of the last viewing, as a date at midnight.
  final DateTime? lastWatchedDay;

  /// For a series: how many different episodes they watched.
  final int? distinctEpisodesWatched;

  String? get displayName => identityName ?? username;

  Duration get watchTime => Duration(milliseconds: watchTimeMs);

  @override
  String toString() => 'TracearrWatcher()';
}

/// `GET /api/v2/public/media/{ref}/watchers`.
final class TracearrMediaWatchers {
  const TracearrMediaWatchers({
    this.mediaId,
    this.mediaType = TracearrMediaType.unknown,
    this.window = TracearrWindow.unknown,
    this.watchers = const [],
  });

  /// A body that is not an object is a [FormatException]: wrong answer.
  factory TracearrMediaWatchers.fromJson(Object? body) {
    final json = asTracearrJson(body);
    if (json == null) {
      throw const FormatException('Tracearr watchers is not an object');
    }
    return TracearrMediaWatchers(
      mediaId: json.text('media_id'),
      mediaType: TracearrMediaType.fromWire(json['media_type']),
      window: TracearrWindow.fromWire(json['window']),
      watchers: tracearrRows(json['watchers'], TracearrWatcher.fromJson).rows,
    );
  }

  final String? mediaId;
  final TracearrMediaType mediaType;
  final TracearrWindow window;
  final List<TracearrWatcher> watchers;

  /// The most recent viewing among [watchers], null when nobody watched.
  DateTime? get lastWatchedDay {
    DateTime? latest;
    for (final watcher in watchers) {
      final day = watcher.lastWatchedDay;
      if (day != null && (latest == null || day.isAfter(latest))) latest = day;
    }
    return latest;
  }
}

/// One title of `GET /api/v2/public/top-media`.
final class TracearrTopMedia {
  const TracearrTopMedia({
    required this.mediaId,
    this.mediaType = TracearrMediaType.unknown,
    this.title = '',
    this.year,
    this.tmdbId,
    this.tvdbId,
    this.plays = 0,
    this.watchTimeMs = 0,
    this.uniqueUsers = 0,
    this.lastWatchedDay,
  });

  factory TracearrTopMedia.fromJson(TracearrJson json) => TracearrTopMedia(
    mediaId: json.requiredText('media_id'),
    mediaType: TracearrMediaType.fromWire(json['media_type']),
    title: json.text('title') ?? '',
    year: json.integer('year'),
    tmdbId: json.integer('tmdb_id'),
    tvdbId: json.integer('tvdb_id'),
    plays: json.integer('plays') ?? 0,
    watchTimeMs: json.integer('watch_time_ms') ?? 0,
    uniqueUsers: json.integer('unique_users') ?? 0,
    lastWatchedDay: json.time('last_watched_day'),
  );

  final String mediaId;
  final TracearrMediaType mediaType;
  final String title;
  final int? year;
  final int? tmdbId;
  final int? tvdbId;
  final int plays;
  final int watchTimeMs;
  final int uniqueUsers;
  final DateTime? lastWatchedDay;

  Duration get watchTime => Duration(milliseconds: watchTimeMs);
}

/// `GET /api/v1/public/stats/today`: the Overview's day figures.
final class TracearrToday {
  const TracearrToday({
    this.activeStreams = 0,
    this.todayPlays = 0,
    this.todaySessions = 0,
    this.watchTimeHours = 0,
    this.alertsLast24h = 0,
    this.activeUsersToday = 0,
  });

  /// A body that is not an object is a [FormatException]: wrong answer.
  factory TracearrToday.fromJson(Object? body) {
    final json = asTracearrJson(body);
    if (json == null) {
      throw const FormatException('Tracearr today is not an object');
    }
    return TracearrToday(
      activeStreams: json.integer('activeStreams') ?? 0,
      todayPlays: json.integer('todayPlays') ?? 0,
      todaySessions: json.integer('todaySessions') ?? 0,
      watchTimeHours: json.number('watchTimeHours') ?? 0,
      alertsLast24h: json.integer('alertsLast24h') ?? 0,
      activeUsersToday: json.integer('activeUsersToday') ?? 0,
    );
  }

  final int activeStreams;
  final int todayPlays;
  final int todaySessions;
  final double watchTimeHours;
  final int alertsLast24h;
  final int activeUsersToday;

  Duration get watchTime =>
      Duration(milliseconds: (watchTimeHours * 3600000).round());
}
