import 'package:flutter/foundation.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/models/rating_source.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/discover/presentation/discover_detail_view_model.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// One episode of a series, as its row says it: the number, the title, and
/// one word for where it stands.
@immutable
class MediaEpisode {
  const MediaEpisode({
    required this.season,
    required this.number,
    required this.title,
    required this.state,
    required this.tone,
    this.airsAt,
    this.progress,
    this.downloading = false,
    this.missing = false,
    this.sonarrId,
    this.onServer,
    this.fromSonarr,
  });

  final int season;
  final int number;
  final String title;
  final DateTime? airsAt;

  /// `Watched`, `5 min left`, `Downloading 88%`, `Missing`, `Not on Jellyfin`,
  /// `Not aired`, `On your server`, `Finishing on the server`.
  final String state;
  final StatusTone tone;

  /// How far the viewer is ([downloading] false: a bar in the ink) or the
  /// download is ([downloading]: a bar in the info tone), 0..1.
  final double? progress;
  final bool downloading;

  /// Aired, wanted, with no file and nothing on its way: what `Search the N
  /// missing` asks Sonarr for. Never true for the requester.
  final bool missing;

  /// Sonarr's id of the episode, for a search; null without Sonarr.
  final int? sonarrId;

  /// The episode on the media server, when it is there.
  final StreamItem? onServer;

  /// Sonarr's record of the episode: its file, whether it is monitored.
  final SonarrEpisode? fromSonarr;

  /// `E3`: the number the row leads with.
  String get code => formatEpisodeOrdinal(number);

  /// The one sentence the row speaks: `Episode 3, The Second Cycle. 5 min
  /// left`.
  String get spoken => [
    'Episode $number',
    if (title.isNotEmpty && title != 'Episode $number') ', $title',
    '. $state',
  ].join();
}

/// A season's episodes, in order.
@immutable
class MediaSeason {
  const MediaSeason(this.number, this.episodes);

  final int number;
  final List<MediaEpisode> episodes;

  /// `Season 2`, or `Specials` for season 0.
  String get label => number == 0 ? 'Specials' : 'Season $number';

  /// What `Search the N missing` would ask for.
  List<MediaEpisode> get missing => [
    for (final episode in episodes)
      if (episode.missing) episode,
  ];
}

/// The seasons of a series as its rows tell them, each episode with one word
/// for where it stands.
///
/// The list is Sonarr's when a Sonarr tracks the series (every episode, aired
/// or not), else what the media server holds; nothing without either. The
/// word comes, in order, from Sonarr's queue (a download in flight), the
/// media server (watched, part-way, there), Sonarr's file and air date.
/// [focus] is the connection the page was opened from: its copy is read
/// first. A media server whose episodes did not answer says nothing of any
/// episode, never that it lacks one. Season 0, the specials, comes last and
/// only when one of them is on disk or on the server.
List<MediaSeason> mediaSeasonsOf(
  List<MediaRow> rows, {
  required Audience audience,
  required DateTime now,
  String? focus,
}) {
  final sonarr = _first<MediaSonarrCopy>(
    rows,
    focus,
    (copy) => copy.series != null,
  );
  final stream = _first<MediaStreamCopy>(
    rows,
    focus,
    (copy) => copy.episodes != null,
  );
  final served = <(int, int), StreamItem>{
    for (final item in stream?.copy.episodes ?? const <StreamItem>[])
      if ((item.seasonNumber, item.episodeNumber) case (
        final int season,
        final int number,
      ))
        (season, number): item,
  };
  final requester = audience == Audience.requester;

  final episodes = <MediaEpisode>[];
  if (sonarr != null) {
    final copy = sonarr.copy;
    final queue = copy.episodeQueue;
    for (final episode in copy.episodes) {
      episodes.add(
        _fromSonarr(
          episode,
          queue: queue,
          onServer: served[(episode.seasonNumber, episode.episodeNumber)],
          serverAnswered: stream != null,
          now: now,
          requester: requester,
        ),
      );
    }
  } else {
    for (final MapEntry(key: (season, number), value: item) in served.entries) {
      episodes.add(_fromServer(season, number, item, requester: requester));
    }
  }

  final bySeason = <int, List<MediaEpisode>>{};
  for (final episode in episodes) {
    bySeason.putIfAbsent(episode.season, () => []).add(episode);
  }
  final numbers = bySeason.keys.toList()..sort();
  return [
    for (final number in numbers)
      if (number > 0 ||
          bySeason[number]!.any(
            (episode) =>
                episode.onServer != null ||
                episode.state == _onYourServer(requester),
          ))
        MediaSeason(
          number,
          bySeason[number]!..sort((a, b) => a.number.compareTo(b.number)),
        ),
  ]..sort((a, b) {
    // Specials last.
    if (a.number == 0) return 1;
    if (b.number == 0) return -1;
    return a.number.compareTo(b.number);
  });
}

String _onYourServer(bool requester) =>
    requester ? Lexicon.onTheServer : 'On your server';

MediaEpisode _fromSonarr(
  SonarrEpisode episode, {
  required ArrQueueSnapshot queue,
  required StreamItem? onServer,
  required bool serverAnswered,
  required DateTime now,
  required bool requester,
}) {
  MediaEpisode word(
    String state,
    StatusTone tone, {
    double? progress,
    bool downloading = false,
    bool missing = false,
  }) => MediaEpisode(
    season: episode.seasonNumber,
    number: episode.episodeNumber,
    title: episode.title,
    airsAt: episode.airsAt,
    state: state,
    tone: tone,
    progress: progress,
    downloading: downloading,
    missing: missing && !requester,
    sonarrId: episode.id,
    onServer: onServer,
    fromSonarr: episode,
  );

  // A download in flight says so first: the row is about to change.
  final entry = queue.entryFor(episode.id);
  if (entry != null) {
    final status = sonarrEpisodeStatus(episode, now: now, queueEntry: entry);
    final pipeline = status.pipeline;
    if (pipeline == MediaPipeline.downloading && !status.hasWarning) {
      final progress = status.progress;
      return word(
        progress == null
            ? 'Downloading'
            : 'Downloading ${formatPercent(progress * 100)}',
        StatusTone.info,
        progress: progress,
        downloading: true,
      );
    }
    if ((pipeline == MediaPipeline.importing ||
            pipeline == MediaPipeline.importPending) &&
        !status.hasWarning) {
      return word(Lexicon.finishingOnTheServer, StatusTone.info);
    }
    final fault = status.tone == StatusTone.warning || status.hasWarning;
    // An upgrade that is stuck leaves the episode where it was: watched, or
    // on the server. Sonarr's row says what needs a hand.
    if (!(fault && episode.hasFile)) {
      // A fault is the operator's; the requester reads that it is coming.
      if (fault && requester) {
        return word(Lexicon.onItsWayState, StatusTone.info);
      }
      return word(status.label, status.tone);
    }
  }

  if (onServer != null) return _watched(onServer, word, requester: requester);

  if (episode.hasFile) {
    // Sonarr has it and the media server, asked, does not yet: it is being
    // taken in. With no media server to ask, the file is the fact.
    return serverAnswered
        ? word(Lexicon.finishingOnTheServer, StatusTone.info)
        : word(_onYourServer(requester), StatusTone.success);
  }
  if (episode.isUnairedAt(now)) {
    return word(StateWord.notAired.label, StatusTone.neutral);
  }
  if (!episode.hasAiredAt(now)) {
    return word(StateWord.noAirDate.label, StatusTone.neutral);
  }
  if (requester) return word('Not on the server yet', StatusTone.neutral);
  // `Missing` only over a queue read whole: with it unread, an aired episode
  // with no file may be on its way.
  final status = sonarrEpisodeStatus(
    episode,
    now: now,
    queueUnknown: !queue.isWhole,
  );
  return word(
    status.label,
    StatusTone.neutral,
    missing: episode.monitored && queue.isWhole,
  );
}

MediaEpisode _fromServer(
  int season,
  int number,
  StreamItem item, {
  required bool requester,
}) => _watched(
  item,
  (state, tone, {progress, downloading = false, missing = false}) =>
      MediaEpisode(
        season: season,
        number: number,
        title: item.title,
        state: state,
        tone: tone,
        progress: progress,
        onServer: item,
      ),
  requester: requester,
);

/// The media server's word for an episode it holds: watched, part-way, or
/// there.
MediaEpisode _watched(
  StreamItem item,
  MediaEpisode Function(
    String state,
    StatusTone tone, {
    double? progress,
    bool downloading,
    bool missing,
  })
  word, {
  required bool requester,
}) {
  if (item.isPlayed) return word('Watched', StatusTone.neutral);
  if (item.isInProgress) {
    return word(
      mediaTimeLeft(item) ?? 'Started',
      StatusTone.neutral,
      progress: item.resumeProgress,
    );
  }
  return word(_onYourServer(requester), StatusTone.success);
}

/// `5 min left`, `1 h 3 min left`: what remains of [item] for the viewer,
/// held together where it wraps; null without a runtime.
String? mediaTimeLeft(StreamItem item) {
  final runtime = item.runtimeMs;
  if (runtime == null || runtime <= 0) return null;
  final minutes = ((runtime - (item.resumeOffsetMs ?? 0)) / 60000).ceil();
  return '${formatRuntimeMinutes(minutes.clamp(1, 1 << 20)).replaceAll(' ', unitSpace)}${unitSpace}left';
}

/// The episode a media server's Play opens: the one the viewer is part-way
/// through, else the first unwatched after the last watched, else the first
/// of all; null when every episode is watched, or none is numbered.
StreamItem? mediaNextEpisode(List<StreamItem> episodes) {
  final numbered = [
    for (final episode in episodes)
      if (episode.seasonNumber != null &&
          episode.episodeNumber != null &&
          episode.seasonNumber! > 0)
        episode,
  ]..sort(_inOrder);
  if (numbered.isEmpty) return null;
  final started = numbered.where((episode) => episode.isInProgress).toList();
  if (started.isNotEmpty) return started.last;
  final lastWatched = numbered.lastIndexWhere((episode) => episode.isPlayed);
  for (final episode in numbered.skip(lastWatched + 1)) {
    if (!episode.isPlayed) return episode;
  }
  return lastWatched < 0 ? numbered.first : null;
}

int _inOrder(StreamItem a, StreamItem b) {
  final season = a.seasonNumber!.compareTo(b.seasonNumber!);
  return season != 0 ? season : a.episodeNumber!.compareTo(b.episodeNumber!);
}

/// The next episode to air, as the page's card says it.
@immutable
class MediaNextAiring {
  const MediaNextAiring({
    required this.season,
    required this.number,
    required this.at,
    required this.timed,
    this.seasonEpisodes,
    this.sonarrMonitors = false,
  });

  final int season;
  final int number;

  /// When it airs: an instant from Sonarr ([timed]), or a day from TMDB.
  final DateTime at;
  final bool timed;

  /// How many episodes TMDB announces for [season], when it is a premiere
  /// and only TMDB says when.
  final int? seasonEpisodes;

  /// Sonarr follows the episode: it looks for it once it airs.
  final bool sonarrMonitors;

  bool get premiere => number == 1;
}

/// The next episode of the series to air, from Sonarr (its episode list,
/// with the hour) else from TMDB through Seerr (a day, no hour); null when
/// neither names one still to come.
MediaNextAiring? mediaNextAiringOf(
  List<MediaRow> rows, {
  required DateTime now,
}) {
  final sonarr = _first<MediaSonarrCopy>(
    rows,
    null,
    (copy) => copy.series != null,
  );
  if (sonarr != null) {
    final upcoming = [
      for (final episode in sonarr.copy.episodes)
        if (episode.seasonNumber > 0 && episode.isUnairedAt(now)) episode,
    ]..sort((a, b) => a.airsAt!.compareTo(b.airsAt!));
    if (upcoming.firstOrNull case final next?) {
      return MediaNextAiring(
        season: next.seasonNumber,
        number: next.episodeNumber,
        at: next.airsAt!,
        timed: next.airDateUtc?.isNotEmpty ?? false,
        sonarrMonitors: next.monitored && (sonarr.copy.series!.monitored),
      );
    }
    return null;
  }
  for (final row in rows) {
    if (row case MediaConnectionRow(
      reading: MediaReadingAnswered(:final answer),
    ) when answer.value is MediaSeerrRecord) {
      final model = DiscoverDetailViewModel.of(
        (answer.value as MediaSeerrRecord).details,
      );
      final next = model.nextEpisodeToAir;
      final day = DateTime.tryParse(next?.airDate ?? '');
      final season = next?.seasonNumber;
      final number = next?.episodeNumber;
      if (day == null || season == null || number == null) return null;
      if (day.isBefore(DateTime(now.year, now.month, now.day))) return null;
      return MediaNextAiring(
        season: season,
        number: number,
        at: day,
        timed: false,
        seasonEpisodes: [
          for (final s in model.seasons)
            if (s.seasonNumber == season && s.episodeCount > 0) s.episodeCount,
        ].firstOrNull,
      );
    }
  }
  return null;
}

/// The first answered copy of type [T] that [keep] accepts, [focus]'s first.
({ServiceInstance connection, T copy})? _first<T>(
  List<MediaRow> rows,
  String? focus,
  bool Function(T copy) keep,
) {
  ({ServiceInstance connection, T copy})? found;
  for (final row in rows) {
    if (row case MediaConnectionRow(
      :final connection,
      reading: MediaReadingAnswered(:final answer),
    ) when answer.value is T && keep(answer.value as T)) {
      final hit = (connection: connection, copy: answer.value as T);
      if (connection.id == focus) return hit;
      found ??= hit;
    }
  }
  return found;
}

/// What TMDB says of one episode, through Seerr: its still, synopsis and
/// votes, read when its sheet or the episodes graph opens.
@immutable
class MediaEpisodeFacts {
  const MediaEpisodeFacts({
    required this.season,
    required this.number,
    this.name,
    this.overview,
    this.stillPath,
    this.voteAverage,
    this.voteCount = 0,
    this.airDate,
  });

  final int season;
  final int number;
  final String? name;
  final String? overview;

  /// TMDB's path to the still (`/abc.jpg`).
  final String? stillPath;

  /// TMDB's score, null when nobody has voted.
  final double? voteAverage;
  final int voteCount;

  /// `2025-08-07`, as TMDB dates it.
  final String? airDate;

  /// The still at [width], from TMDB's own address.
  String? stillUrl({int width = 780}) => switch (stillPath) {
    final path? when path.isNotEmpty =>
      'https://image.tmdb.org/t/p/w$width$path',
    _ => null,
  };
}

/// The episodes of one season TMDB's record lists (`/tv/:id/season/:n`).
List<MediaEpisodeFacts> mediaEpisodeFactsOf(Map<String, dynamic> season) {
  String? text(Object? value) {
    final string = value?.toString().trim() ?? '';
    return string.isEmpty ? null : string;
  }

  return [
    for (final episode in switch (season['episodes']) {
      final List<dynamic> list => list.whereType<Map<String, dynamic>>(),
      _ => const <Map<String, dynamic>>[],
    })
      if ((episode['seasonNumber'], episode['episodeNumber']) case (
        final num season,
        final num number,
      ))
        MediaEpisodeFacts(
          season: season.toInt(),
          number: number.toInt(),
          name: text(episode['name']),
          overview: text(episode['overview']),
          stillPath: text(episode['stillPath']),
          voteAverage: switch (episode['voteAverage']) {
            final num vote when vote > 0 => vote.toDouble(),
            _ => null,
          },
          voteCount: switch (episode['voteCount']) {
            final num count => count.toInt(),
            _ => 0,
          },
          airDate: text(episode['airDate']),
        ),
  ];
}

/// The resolution a Sonarr quality profile's cutoff asks for, `1080p`: the
/// cutoff quality's, or the best of the cutoff group's. Null when the
/// profile names none.
String? sonarrCutoffResolution(Map<String, dynamic> profile) {
  final cutoff = profile['cutoff'];
  int? resolution(Map<String, dynamic> item) {
    final quality = item['quality'];
    if (quality is Map && quality['resolution'] is num) {
      return (quality['resolution'] as num).toInt();
    }
    final group = item['items'];
    if (group is List) {
      final values = [
        for (final inner in group.whereType<Map<String, dynamic>>())
          ?resolution(inner),
      ];
      return values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
    }
    return null;
  }

  for (final item in switch (profile['items']) {
    final List<dynamic> list => list.whereType<Map<String, dynamic>>(),
    _ => const <Map<String, dynamic>>[],
  }) {
    final quality = item['quality'];
    final id = quality is Map ? quality['id'] : item['id'];
    if (id == cutoff) {
      final value = resolution(item);
      return value == null || value <= 0 ? null : '${value}p';
    }
  }
  return null;
}

/// The episodes graph: TMDB's votes, a season to a column.
@immutable
class MediaEpisodesGraph {
  const MediaEpisodesGraph({
    required this.seasons,
    required this.best,
    this.stronger,
  });

  /// Fewer votes than this, and a cell is drawn uncertain.
  static const fewVotes = ratingVoteFloor;

  /// The steps of the one-colour scale: under 7.3, then every 0.3, to 8.5
  /// and above.
  static const steps = [7.3, 7.6, 7.9, 8.2, 8.5];

  final List<({int number, double? average, List<MediaEpisodeFacts> episodes})>
  seasons;

  /// The three best-scored episodes, the best first.
  final List<MediaEpisodeFacts> best;

  /// The season whose average leads, against the next one, and how many of
  /// its episodes have few votes; null with fewer than two seasons scored.
  final ({int season, double average, double other, int fewVotes})? stronger;

  /// The scale's step for [vote]: 0 under 7.3, 5 at 8.5 and above.
  static int stepOf(double vote) =>
      steps.where((threshold) => vote >= threshold).length;

  bool get isEmpty => best.isEmpty;
}

/// The graph of [seasons], each a season's episodes as TMDB lists them.
MediaEpisodesGraph mediaEpisodesGraphOf(
  Map<int, List<MediaEpisodeFacts>> seasons,
) {
  final numbers = seasons.keys.where((n) => n > 0).toList()..sort();
  final columns = [
    for (final number in numbers)
      () {
        final episodes = [...seasons[number]!]
          ..sort((a, b) => a.number.compareTo(b.number));
        final votes = [for (final e in episodes) ?e.voteAverage];
        return (
          number: number,
          average: votes.isEmpty
              ? null
              : votes.reduce((a, b) => a + b) / votes.length,
          episodes: episodes,
        );
      }(),
  ];
  final scored = [
    for (final column in columns)
      for (final e in column.episodes)
        if (e.voteAverage != null) e,
  ]..sort((a, b) => b.voteAverage!.compareTo(a.voteAverage!));
  final ranked = [
    for (final column in columns)
      if (column.average != null) column,
  ]..sort((a, b) => b.average!.compareTo(a.average!));
  return MediaEpisodesGraph(
    seasons: columns,
    best: scored.take(3).toList(),
    stronger: ranked.length < 2
        ? null
        : (
            season: ranked[0].number,
            average: ranked[0].average!,
            other: ranked[1].average!,
            fewVotes: ranked[0].episodes
                .where(
                  (e) =>
                      e.voteAverage != null &&
                      e.voteCount < MediaEpisodesGraph.fewVotes,
                )
                .length,
          ),
  );
}
