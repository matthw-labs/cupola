import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';

/// How Tracearr names a title in the path of `media/{ref}/watchers`: a movie
/// by its TMDB id, a series by its TMDB id or, with none, its TVDB id.
///
/// The forms are the ones Tracearr's own route parses
/// (`^(movie|show|episode):(imdb|tmdb|tvdb):(.+)$`); the series' is `show`, not
/// `tv`.
TracearrMediaRef tracearrRefOf(MediaKey key) => switch (key) {
  MediaKey(isMovie: true, tmdbId: final tmdb?) => TracearrMediaRef.movieTmdb(
    tmdb,
  ),
  MediaKey(tmdbId: final tmdb?) => TracearrMediaRef.showTmdb(tmdb),
  MediaKey(tvdbId: final tvdb?) => TracearrMediaRef.showTvdb(tvdb),
  _ => throw ArgumentError.value(key.location, 'key', 'names no title'),
};

/// One person's viewing of a title, with their accounts on every server
/// Tracearr watches added up: Tracearr lists one entry for each account, and a
/// person with a Plex and a Jellyfin account is one person.
///
/// Who watched what is theirs, so [toString] prints none of it.
final class TracearrWatchedPerson {
  const TracearrWatchedPerson({
    required this.name,
    required this.plays,
    this.personId,
    this.completion,
    this.episodes,
    this.lastDay,
  });

  /// Tracearr's id of the person, which their page is opened by; null when
  /// the row named none.
  final String? personId;
  final String name;
  final int plays;

  /// 0 to 100: the most of the title any of their accounts got through.
  final double? completion;

  /// For a series: how many different episodes they watched (the most any of
  /// their accounts did, as an episode two accounts watched is one).
  final int? episodes;

  /// The calendar day of their last viewing.
  final DateTime? lastDay;

  @override
  String toString() => 'TracearrWatchedPerson()';
}

/// [watchers] as people, the most recent viewer first (then the one who played
/// it most, then by name, so the order is stable).
List<TracearrWatchedPerson> tracearrWatchedPeople(
  TracearrMediaWatchers watchers,
) {
  final byPerson = <String, List<TracearrWatcher>>{};
  for (final watcher in watchers.watchers) {
    final key =
        watcher.userId ??
        watcher.serverUserId ??
        (watcher.displayName ?? '').toLowerCase();
    (byPerson[key] ??= []).add(watcher);
  }
  final people = [
    for (final group in byPerson.values)
      TracearrWatchedPerson(
        personId: group.map((w) => w.userId).nonNulls.firstOrNull,
        name: group
            .map((w) => w.displayName?.trim())
            .nonNulls
            .firstWhere((name) => name.isNotEmpty, orElse: () => 'Someone'),
        plays: group.fold(0, (sum, w) => sum + w.plays),
        completion: _most(group.map((w) => w.completionPct)),
        episodes: _most(
          group.map((w) => w.distinctEpisodesWatched?.toDouble()),
        )?.round(),
        lastDay: group
            .map((w) => w.lastWatchedDay)
            .nonNulls
            .fold<DateTime?>(
              null,
              (latest, day) =>
                  latest == null || day.isAfter(latest) ? day : latest,
            ),
      ),
  ];
  people.sort((a, b) {
    final byDay = (b.lastDay ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(a.lastDay ?? DateTime.fromMillisecondsSinceEpoch(0));
    if (byDay != 0) return byDay;
    final byPlays = b.plays.compareTo(a.plays);
    return byPlays != 0 ? byPlays : a.name.compareTo(b.name);
  });
  return people;
}

double? _most(Iterable<double?> values) {
  double? most;
  for (final value in values) {
    if (value != null && (most == null || value > most)) most = value;
  }
  return most;
}

/// When, as `last` follows it: `today`, `yesterday`, `12 days ago` counted in
/// calendar days (Tracearr dates a viewing by its day, not its hour), and from
/// two months on the date itself, `on Tue 29 Sep`.
String tracearrDayWords(DateTime day, {required DateTime now}) {
  final days = calendarDaysBetween(day.toLocal(), now.toLocal());
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 60) return '$days days ago';
  return 'on ${formatShortDay(day.toLocal(), now: now)}';
}

/// What follows `Watched by` when somebody has: `3 people · last 12 days ago`. The
/// section's heading carries it at its end, and [tracearrWatchedLine] after the
/// words. Empty for nobody.
String tracearrWatchedTally(
  Iterable<TracearrWatchedPerson> people, {
  required DateTime now,
}) {
  if (people.isEmpty) return '';
  DateTime? last;
  for (final person in people) {
    final day = person.lastDay;
    if (day != null && (last == null || day.isAfter(last))) last = day;
  }
  return joinDisplayParts([
    people.length == 1 ? '1 person' : '${people.length} people',
    if (last != null) 'last ${tracearrDayWords(last, now: now)}',
  ]);
}

/// What a title's Watched by says in one line, and the delete sheet with it:
/// `Watched by 3 people · last 12 days ago`, or `Nobody has watched it`.
///
/// Said only of an answer. Tracearr not knowing the title is not "nobody"
/// (the caller passes no watchers, and no line is drawn).
String tracearrWatchedLine(
  Iterable<TracearrWatchedPerson> people, {
  required DateTime now,
}) => people.isEmpty
    ? 'Nobody has watched it'
    : 'Watched by ${tracearrWatchedTally(people, now: now)}';

/// One person's row: the plays, how much of it, and when; a series counts
/// its distinct episodes before the plays.
String tracearrWatcherDetail(
  TracearrWatchedPerson person, {
  required bool series,
  required DateTime now,
}) {
  final episodes = person.episodes;
  final completion = person.completion;
  final last = person.lastDay;
  return joinDisplayParts([
    if (series && episodes != null) countLabel(episodes, 'episode'),
    countLabel(person.plays, 'play'),
    if (completion != null) formatPercent(completion),
    if (last != null) 'last ${tracearrDayWords(last, now: now)}',
  ]);
}
