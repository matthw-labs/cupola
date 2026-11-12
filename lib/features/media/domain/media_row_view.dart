import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/media_subtitles.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

/// The four shapes a row takes (the brand book's Configurations).
enum MediaRowShape {
  /// What a connection holds, and its state: name · detail · state.
  fact,

  /// Case a: `Not set up`, what the service would bring, and `Set up X`.
  notSetUp,

  /// Case c: the failure in its tone, the last known answer under it, and
  /// `Retry`.
  failed,

  /// Case b: Seerr's word about a server Cupola does not have, attributed,
  /// with `Add X to Cupola` under it.
  claim,

  /// A fault a copy reports, in amber: what is wrong as the state, the
  /// sentence under it, and its remedy as the one amber fill.
  fault,
}

/// Where a row's one way forward leads.
enum MediaRowWay {
  /// `Set up X`: the service's setup form.
  setUp,

  /// `Add X to Cupola`: the setup form of the server Seerr knows.
  add,

  /// `Retry`: the same connection asked again, and only it.
  retry,

  /// The remedy a failure names (`Paste the key again`, `Check the address`):
  /// the connection's own form.
  fix,

  /// `Review the imports`: the manual import review of the copy
  /// ([MediaRowView.targetId]) on its connection.
  review,

  /// `Add to Radarr · 4K`: the add sheet on this connection alone, for the
  /// copy it does not hold while another of the same arr does.
  addCopy,
}

/// A row of "On your server" as it is drawn and spoken: who, what, and the
/// state's word in its tone.
@immutable
class MediaRowView {
  const MediaRowView({
    this.shape = MediaRowShape.fact,
    required this.name,
    required this.detail,
    required this.state,
    required this.tone,
    this.via,
    this.hollow = false,
    this.progress,
    this.action,
    this.way,
    this.dimmed = false,
    this.connectionId,
    this.targetId,
  });

  final MediaRowShape shape;

  /// The connection's name: `Radarr`, `Radarr · 4K`.
  final String name;

  /// How the fact reached the app, when it is another service's claim:
  /// `through Seerr` (case b).
  final String? via;

  /// What the source holds: `1080p Bluray · 1.2 GB`, `Anna · Sat 12 Sep`.
  final String detail;

  /// The state's one word: `Available`, `Did not answer`, `DE wanted`.
  final String state;

  final StatusTone tone;

  /// The backlog's ring rather than a filled dot: a neutral state.
  final bool hollow;

  /// How far a download is, 0..1, drawn under the row.
  final double? progress;

  /// The one quiet way forward the row offers: `Set up Seerr`, `Retry`,
  /// `Add Radarr · 4K to Cupola`.
  final String? action;

  /// Where [action] leads; null exactly when there is no action.
  final MediaRowWay? way;

  /// Case a: the row is dimmed, and still opens the setup form.
  final bool dimmed;

  /// The connection the row reads, for its tap and for the page's focus.
  final String? connectionId;

  /// The copy's own id on its connection (a Sonarr series), for a way that
  /// acts on it ([MediaRowWay.review]).
  final int? targetId;

  /// The one sentence a screen reader speaks for the row.
  String get spoken =>
      [name, ?via, if (detail.isNotEmpty) detail, state, ?action].join('. ');
}

/// [row] in the page's words, or null where the row draws nothing: Bazarr
/// answering that it follows no copy of the title.
///
/// [title] names a connection the way the rest of the app does
/// (`SettingsModel.connectionTitle`); [now] is the clock the request dates
/// are read against.
MediaRowView? mediaRowView(
  MediaRow row, {
  required String Function(ServiceInstance connection) title,
  required DateTime now,
}) {
  return switch (row) {
    MediaNotSetUpRow(:final service) => MediaRowView(
      shape: MediaRowShape.notSetUp,
      name: service.title,
      detail: _whatItBrings(service),
      state: StateWord.notSetUp.label,
      tone: StatusTone.neutral,
      hollow: true,
      action: Lexicon.setUp(service.title),
      way: MediaRowWay.setUp,
      dimmed: true,
    ),
    MediaThroughSeerrRow(:final copy, :final mediaInfo) => () {
      final status = seerrMediaStatus(mediaInfo, is4k: copy.copy.is4k);
      final name = copy.serverName(
        connectionTitle: (connection) => title(connection),
      );
      return MediaRowView(
        shape: MediaRowShape.claim,
        name: name,
        via: 'through Seerr',
        detail: mediaSeerrSeasonsLine(mediaInfo, is4k: copy.copy.is4k),
        state: status.label,
        tone: status.tone,
        hollow: status.tone == StatusTone.neutral,
        action: 'Add $name to Cupola',
        way: MediaRowWay.add,
      );
    }(),
    MediaServerThroughSeerrRow(server: null) => null,
    MediaServerThroughSeerrRow(:final server?, :final mediaInfo) => () {
      // What is on the player, not what is coming to it: the downloads are
      // the arr's to say.
      final status = seerrMediaStatus(
        {...?mediaInfo}
          ..remove('downloadStatus')
          ..remove('downloadStatus4k'),
      );
      // A series in part: the seasons say which, the state only that.
      final partial = status.availability == MediaAvailability.partial;
      return MediaRowView(
        shape: MediaRowShape.claim,
        name: server.title,
        via: 'through Seerr',
        detail: mediaSeerrSeasonsLine(mediaInfo),
        state: partial
            ? const MediaStatusInfo(
                availability: MediaAvailability.partial,
              ).label
            : status.label,
        tone: status.tone,
        hollow: status.tone == StatusTone.neutral,
        action: 'Add ${server.title} to Cupola',
        way: MediaRowWay.add,
      );
    }(),
    MediaConnectionRow(:final connection, :final reading) => _connectionView(
      connection,
      reading,
      name: title(connection),
      now: now,
    ),
  };
}

/// A series' seasons as Seerr has them on the server, `S1 available · S2
/// partly available`; empty for a movie, and for seasons not there yet.
/// [is4k] reads the 4K copy's.
String mediaSeerrSeasonsLine(
  Map<String, dynamic>? mediaInfo, {
  bool is4k = false,
}) {
  final seasons = [
    for (final season in switch (mediaInfo?['seasons']) {
      final List<dynamic> list => list.whereType<Map<String, dynamic>>(),
      _ => const <Map<String, dynamic>>[],
    })
      (
        number: intOrNull(season['seasonNumber']) ?? 0,
        // 4 and 5 mean the same in every numbering.
        status: SeerrMediaAvailability.fromCode(
          season[is4k ? 'status4k' : 'status'],
          numbering: null,
        ),
      ),
  ]..sort((a, b) => a.number.compareTo(b.number));
  return [
    for (final season in seasons)
      if (season.number > 0)
        if (season.status == SeerrMediaAvailability.available)
          '${formatSeasonCode(season.number)} available'
        else if (season.status == SeerrMediaAvailability.partiallyAvailable)
          '${formatSeasonCode(season.number)} partly available',
  ].join(dotSeparator);
}

/// [row] as the rows it draws: one, or none (see [mediaRowView]), except a
/// Sonarr that tracks the series, which says one row per fact (what is
/// downloading, what aired and is missing, what needs an import), and a media
/// server, which counts a series' episodes by season. [rows] are the page's,
/// for the seasons' sizes.
List<MediaRowView> mediaRowViews(
  MediaRow row, {
  required String Function(ServiceInstance connection) title,
  required DateTime now,
  required List<MediaRow> rows,
}) {
  final view = mediaRowView(row, title: title, now: now);
  if (view == null) return const [];
  if (row case MediaConnectionRow(
    :final connection,
    reading: MediaReadingAnswered(:final answer),
  )) {
    switch (answer.value) {
      // A copy this arr does not hold while another of it does: the one way
      // to it. While nobody holds the title, Add leads instead.
      case MediaRadarrCopy(movie: null) || MediaSonarrCopy(series: null)
          when _heldByAnother(row, rows):
        return [
          MediaRowView(
            name: view.name,
            detail: view.detail,
            state: view.state,
            tone: view.tone,
            hollow: view.hollow,
            action: 'Add to ${view.name}',
            way: MediaRowWay.addCopy,
            connectionId: connection.id,
          ),
        ];
      case MediaSonarrCopy(:final series?) && final copy:
        final facts = _sonarrFacts(
          copy,
          series.id,
          name: view.name,
          connectionId: connection.id,
          now: now,
        );
        return facts.isEmpty ? [view] : facts;
      // Bazarr's languages over the episodes that have them.
      case MediaBazarrCopy(series: _?, :final episodes?):
        final words = _bazarrSeriesWords(episodes, _airedBySeason(rows, now));
        return [
          MediaRowView(
            name: view.name,
            detail: words.detail,
            state: words.state,
            tone: view.tone,
            hollow: view.hollow,
            connectionId: view.connectionId,
          ),
        ];
      case MediaStreamCopy(:final item?, :final episodes?)
          when item.kind == StreamItemKind.series:
        final line = _seasonsLine(episodes, _airedBySeason(rows, now));
        if (line.isEmpty) return [view];
        return [
          MediaRowView(
            name: view.name,
            detail: line,
            state: view.state,
            tone: view.tone,
            hollow: view.hollow,
            connectionId: view.connectionId,
          ),
        ];
    }
  }
  return [view];
}

/// What one Sonarr says of a series, one row per fact: the episodes
/// downloading, the aired ones missing, the downloads that need an import.
/// Empty when none of that is true: the row then says the files it holds.
List<MediaRowView> _sonarrFacts(
  MediaSonarrCopy copy,
  int seriesId, {
  required String name,
  required String connectionId,
  required DateTime now,
}) {
  final queue = copy.episodeQueue;
  final aired = _bySeason([
    for (final episode in copy.episodes)
      if (episode.hasAiredAt(now)) episode,
  ]);
  final downloading = <SonarrEpisode>[];
  final blocked = <SonarrEpisode>[];
  final missing = <SonarrEpisode>[];
  var downloadWord = 'Queued';
  for (final episode in copy.episodes) {
    final entry = queue.entryFor(episode.id);
    if (entry != null) {
      final status = sonarrEpisodeStatus(episode, now: now, queueEntry: entry);
      if (status.tone == StatusTone.warning || status.hasWarning) {
        blocked.add(episode);
      } else {
        downloading.add(episode);
        if (status.pipeline == MediaPipeline.downloading) {
          downloadWord = 'Downloading';
        } else if (downloadWord == 'Queued' &&
            (status.pipeline == MediaPipeline.importing ||
                status.pipeline == MediaPipeline.importPending)) {
          downloadWord = Lexicon.finishingOnTheServer;
        }
      }
    } else if (!episode.hasFile &&
        episode.monitored &&
        episode.seasonNumber > 0 &&
        episode.hasAiredAt(now) &&
        queue.isWhole) {
      missing.add(episode);
    }
  }
  MediaRowView fact(String detail, String state, StatusTone tone) =>
      MediaRowView(
        name: name,
        detail: detail,
        state: state,
        tone: tone,
        hollow: tone == StatusTone.neutral,
        connectionId: connectionId,
      );
  final upgrades = blocked.every((episode) => episode.hasFile);
  return [
    if (downloading.isNotEmpty)
      fact(_episodeSpan(downloading, aired), downloadWord, StatusTone.info),
    if (missing.isNotEmpty)
      fact(
        '${_episodeSpan(missing, aired)} aired',
        '${missing.length} missing',
        StatusTone.neutral,
      ),
    if (blocked.isNotEmpty)
      MediaRowView(
        shape: MediaRowShape.fault,
        name: name,
        state:
            '${_episodeSpan(blocked, aired)}\u00A0· ${blocked.length} '
            '${upgrades ? (blocked.length == 1 ? 'upgrade needs' : 'upgrades need') : (blocked.length == 1 ? 'episode needs' : 'episodes need')} import',
        detail: upgrades
            ? "Better versions arrived; $name won't import them on its own"
            : "The downloads are done; $name won't import them on its own",
        tone: StatusTone.warning,
        action: 'Review the imports',
        way: MediaRowWay.review,
        connectionId: connectionId,
        targetId: seriesId,
      ),
  ];
}

Map<int, List<SonarrEpisode>> _bySeason(Iterable<SonarrEpisode> episodes) {
  final seasons = <int, List<SonarrEpisode>>{};
  for (final episode in episodes) {
    seasons.putIfAbsent(episode.seasonNumber, () => []).add(episode);
  }
  return seasons;
}

/// `S2 E4–E5`, `S1 · S2 E1–E2`: [episodes] by season, a season whose aired
/// episodes are all there by its number alone; past three seasons, their
/// span (`S1–S6`).
String _episodeSpan(
  List<SonarrEpisode> episodes,
  Map<int, List<SonarrEpisode>> aired,
) => _spanOf(
  {
    for (final MapEntry(:key, :value) in _bySeason(episodes).entries)
      key: [for (final episode in value) episode.episodeNumber],
  },
  {for (final MapEntry(:key, :value) in aired.entries) key: value.length},
);

/// [seasons] (each season's episode numbers) as one span: a season whose
/// every aired episode is there by its code alone (`S1`), the rest as runs
/// (`S2 E4–E5`); past three seasons, from the first to the last (`S1–S5`).
/// [aired] counts each season's aired episodes.
String _spanOf(Map<int, List<int>> seasons, Map<int, int> aired) {
  final numbers = seasons.keys.toList()..sort();
  if (numbers.length > 3) {
    return '${formatSeasonCode(numbers.first)}–'
        '${formatSeasonCode(numbers.last)}';
  }
  return [
    for (final season in numbers)
      if (seasons[season]!.toSet().length == (aired[season] ?? -1))
        formatSeasonCode(season)
      else
        '${formatSeasonCode(season)}$episodeCodeSpace'
            '${_ranges(seasons[season]!)}',
  ].join(dotSeparator);
}

/// What Bazarr says of a series from its episodes: the languages on disk and
/// the episodes still wanting one (`English on disk · S2 E1–E3`), then what
/// is wanted (`Italian wanted`). [aired] counts each season's aired
/// episodes, so a season wanting everywhere is named whole.
({String detail, String state}) _bazarrSeriesWords(
  List<BazarrEpisode> episodes,
  Map<int, int> aired,
) {
  final wanting = [
    for (final episode in episodes)
      if (episode.missingLanguages.isNotEmpty) episode,
  ];
  final present = mediaLanguageWords(mediaSeriesLanguagesOnDisk(episodes));
  final span = wanting.isEmpty
      ? ''
      : _spanOf({
          for (final season in {for (final e in wanting) e.season})
            season: [
              for (final e in wanting)
                if (e.season == season) e.episode,
            ],
        }, aired);
  return (
    detail: [
      if (present.isNotEmpty) '$present on disk',
      if (span.isNotEmpty) span,
    ].join(dotSeparator),
    state: wanting.isEmpty
        ? 'Nothing wanted'
        : '${mediaLanguageWords(wanting.expand((e) => e.missingLanguages))} '
              'wanted',
  );
}

/// `E4–E5`, `E6, E8–E10`: [numbers] as runs.
String _ranges(List<int> numbers) {
  final sorted = numbers.toSet().toList()..sort();
  final runs = <String>[];
  var start = 0;
  for (var i = 1; i <= sorted.length; i++) {
    if (i == sorted.length || sorted[i] != sorted[i - 1] + 1) {
      runs.add(
        i - 1 == start
            ? formatEpisodeOrdinal(sorted[start])
            : '${formatEpisodeOrdinal(sorted[start])}–'
                  '${formatEpisodeOrdinal(sorted[i - 1])}',
      );
      start = i;
    }
  }
  return runs.join(', ');
}

/// How many episodes of each season have aired, by the first Sonarr that
/// tracks the series; empty without one.
Map<int, int> _airedBySeason(List<MediaRow> rows, DateTime now) {
  for (final row in rows) {
    if (row case MediaConnectionRow(
      reading: MediaReadingAnswered(:final answer),
    )) {
      if (answer.value case MediaSonarrCopy(series: _?, :final episodes)) {
        return {
          for (final MapEntry(:key, :value) in _bySeason([
            for (final episode in episodes)
              if (episode.hasAiredAt(now)) episode,
          ]).entries)
            key: value.length,
        };
      }
    }
  }
  return const {};
}

/// `S1 10 of 10 · S2 3 of 10`: a media server's episodes by season, against
/// the episodes Sonarr says aired; past three seasons, or without Sonarr,
/// the total (`38 of 50 episodes`, `13 episodes`).
String _seasonsLine(List<StreamItem> episodes, Map<int, int> aired) {
  final held = <int, int>{};
  for (final episode in episodes) {
    final season = episode.seasonNumber;
    if (season != null && season > 0) {
      held[season] = (held[season] ?? 0) + 1;
    }
  }
  if (held.isEmpty) return '';
  final seasons = held.keys.toList()..sort();
  final total = held.values.fold(0, (sum, count) => sum + count);
  if (aired.isEmpty) return countLabel(total, 'episode');
  if (seasons.length > 3) {
    final of = aired.entries
        .where((entry) => entry.key > 0)
        .fold(0, (sum, entry) => sum + entry.value);
    return '$total of $of episodes';
  }
  return [
    for (final season in seasons)
      '${formatSeasonCode(season)} ${held[season]} of '
          '${aired[season] ?? held[season]}',
  ].join(dotSeparator);
}

/// What a service that is not set up would bring to the page, for its
/// dimmed row.
String _whatItBrings(ServiceKey service) => switch (service) {
  ServiceKey.seerr => 'Requests, cast and trailers need it',
  ServiceKey.radarr => 'Files and searches need it',
  ServiceKey.sonarr => 'Episodes and searches need it',
  _ => '',
};

MediaRowView? _connectionView(
  ServiceInstance connection,
  MediaReading<Object?> reading, {
  required String name,
  required DateTime now,
}) {
  switch (reading) {
    case MediaReadingWaiting():
      return MediaRowView(
        name: name,
        detail: '',
        state: '',
        tone: StatusTone.neutral,
        connectionId: connection.id,
      );
    case MediaReadingFailed(:final failure, :final gateway, :final lastKnown):
      final known = lastKnown == null
          ? null
          : _answeredView(connection, lastKnown.value, name: name, now: now);
      final since = lastKnown == null
          ? ''
          : ' since ${formatClockTime(lastKnown.at)}';
      // A Seerr connection signed in as a member refused a sign-in, not a
      // key; Plex refuses a token.
      final credential = connection.account == null
          ? refusedCredentialOf(connection.service)
          : kRefusedSignIn;
      final remedy = failureRemedy(
        failure,
        credential: credential,
        gateway: gateway,
      );
      return MediaRowView(
        shape: MediaRowShape.failed,
        name: name,
        detail: known == null
            ? ''
            : 'Last known: ${[if (known.detail.isNotEmpty) known.detail, known.state].join(dotSeparator)}',
        state:
            '${failureLabel(failure, credential: credential, gateway: gateway)}'
            '$since',
        tone: failureTone(failure),
        // The remedy the cause names, else Retry: a refused key is refused
        // again, and only its form fixes it.
        action: remedy ?? Lexicon.retry,
        way: remedy == null ? MediaRowWay.retry : MediaRowWay.fix,
        connectionId: connection.id,
      );
    case MediaReadingAnswered(:final answer):
      return _answeredView(connection, answer.value, name: name, now: now);
  }
}

MediaRowView? _answeredView(
  ServiceInstance connection,
  Object? value, {
  required String name,
  required DateTime now,
}) {
  MediaRowView view({
    required String detail,
    required String state,
    required StatusTone tone,
    double? progress,
  }) => MediaRowView(
    name: name,
    detail: detail,
    state: state,
    tone: tone,
    hollow: tone == StatusTone.neutral,
    progress: progress,
    connectionId: connection.id,
  );

  switch (value) {
    case MediaStreamCopy(:final outcome, :final item):
      if (outcome != StreamLookupOutcome.found || item == null) {
        return view(
          detail: 'Not in any library',
          state: 'Not there',
          tone: StatusTone.neutral,
        );
      }
      // `1 h 3 min left` holds together when the detail wraps.
      final left = item.isInProgress && item.runtimeMs != null
          ? '${formatRuntimeMinutes(((item.runtimeMs! - (item.resumeOffsetMs ?? 0)) / 60000).ceil()).replaceAll(' ', '\u00A0')}\u00A0left'
          : null;
      final picture = item.video?.words ?? '';
      return view(
        detail: [
          if (picture.isNotEmpty) picture,
          if (item.isPlayed) 'Watched' else ?left,
        ].join(dotSeparator),
        state: _onDisk.label,
        tone: _onDisk.tone,
      );
    case MediaRadarrCopy(:final movie, :final status):
      if (movie == null || status == null) {
        return view(
          detail: '',
          state: 'Not added yet',
          tone: StatusTone.neutral,
        );
      }
      final file = movie.movieFile;
      return view(
        detail: [
          if (file?.qualityName case final quality? when quality.isNotEmpty)
            qualityWords(quality),
          if (file?.size case final size? when size > 0) formatBytes(size),
        ].join(dotSeparator),
        state: status.label,
        tone: status.tone,
        progress: status.progress,
      );
    case MediaSonarrCopy(:final series, :final status):
      if (series == null || status == null) {
        return view(
          detail: '',
          state: 'Not added yet',
          tone: StatusTone.neutral,
        );
      }
      final files = intOrNull(series.statistics?['episodeFileCount']);
      final episodes = intOrNull(series.statistics?['episodeCount']);
      return view(
        detail: files == null || episodes == null
            ? ''
            : '$files of $episodes episodes',
        state: status.label,
        tone: status.tone,
        progress: status.progress,
      );
    case MediaBazarrCopy(:final movie?):
      return view(
        detail: mediaLanguageCodes(movie.presentLanguages),
        state: movie.missingLanguages.isEmpty
            ? 'Nothing wanted'
            : '${mediaLanguageCodes(movie.missingLanguages)} wanted',
        tone: StatusTone.neutral,
      );
    case MediaBazarrCopy(:final series?):
      final missing = series.episodeMissingCount ?? 0;
      return view(
        detail: '',
        state: missing == 0
            ? 'Nothing wanted'
            : '${countLabel(missing, 'episode')} wanted',
        tone: StatusTone.neutral,
      );
    case MediaBazarrCopy() || null:
      return null;
    case final MediaSeerrRecord record:
      final status = seerrMediaStatus(
        record.mediaInfo,
        numbering: record.numbering,
      );
      final request = _latestRequest(record.mediaInfo);
      return view(
        // "Nobody" where Seerr has no record at all. A record whose request
        // list is empty is one Seerr found on the server by itself (a library
        // scan, an arr's sync): it says so beside the status, as Seerr does.
        // A record without the list says nothing it cannot know.
        detail: request == null
            ? switch (record.mediaInfo) {
                null => 'Nobody has asked for it',
                {'requests': List()} => 'Not requested',
                _ => '',
              }
            : [
                if (request.who.isNotEmpty) request.who,
                // A row about a request says its day as the request rows
                // elsewhere do: hours, then yesterday, a weekday, a date.
                if (request.when.isNotEmpty)
                  switch (DateTime.tryParse(request.when)) {
                    final at? => formatDayWords(at, now: now),
                    null => request.when,
                  },
              ].join(dotSeparator),
        state: status.label,
        tone: status.tone,
      );
  }
  return null;
}

/// A copy a viewer can play: the badge's own word and tone.
const _onDisk = MediaStatusInfo(availability: MediaAvailability.available);

/// The most recent request in Seerr's [mediaInfo]: who asked, and when.
({String who, String when})? _latestRequest(Map<String, dynamic>? mediaInfo) {
  final requests = mediaInfo?['requests'];
  if (requests is! List || requests.isEmpty) return null;
  final latest = requests.whereType<Map>().reduce(
    (a, b) =>
        '${a['createdAt'] ?? ''}'.compareTo('${b['createdAt'] ?? ''}') >= 0
        ? a
        : b,
  );
  final by = mapOrNull(latest['requestedBy']);
  return (
    who: '${by?['displayName'] ?? by?['username'] ?? ''}',
    when: '${latest['createdAt'] ?? ''}',
  );
}

/// Whether a connection of [row]'s arr other than [row]'s holds the title.
bool _heldByAnother(MediaConnectionRow row, List<MediaRow> rows) => rows.any(
  (other) =>
      other is MediaConnectionRow &&
      other.service == row.service &&
      other.connection.id != row.connection.id &&
      switch (other.reading) {
        MediaReadingAnswered(:final answer) => switch (answer.value) {
          MediaRadarrCopy(movie: _?) || MediaSonarrCopy(series: _?) => true,
          _ => false,
        },
        _ => false,
      },
);
