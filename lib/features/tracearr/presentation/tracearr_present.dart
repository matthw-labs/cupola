import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';

/// What every Tracearr screen says about its rows, written once: a row read
/// on the Overview, in Live, in History and in the Violations list is the
/// same words each time.
///
/// Pure functions of the models, so a test says them without a widget.

/// Who is on a row. A row that names nobody is `Someone`, never a blank.
String tracearrPersonOf(TracearrPerson person) =>
    person.name.trim().isEmpty ? 'Someone' : person.name.trim();

/// The kind of media server, as the person knows it. An unknown kind has no
/// word of its own and the row falls back to the server's name.
String? tracearrServerTypeWord(TracearrServerType type) => switch (type) {
  TracearrServerType.plex => 'Plex',
  TracearrServerType.jellyfin => 'Jellyfin',
  TracearrServerType.emby => 'Emby',
  TracearrServerType.unknown => null,
};

/// The server a row names: its own name, which is what the owner called it in
/// Tracearr, or the kind of server when it has none.
String? tracearrServerOf(TracearrServerRef server) {
  final name = server.name.trim();
  return name.isNotEmpty ? name : tracearrServerTypeWord(server.type);
}

/// How bad a violation is, in the word Tracearr uses. An unknown severity is
/// the dash that stands for a figure nobody could read, never a made-up word.
String tracearrSeverityWord(TracearrSeverity severity) => switch (severity) {
  TracearrSeverity.low => 'Low',
  TracearrSeverity.warning => 'Warning',
  TracearrSeverity.high => 'High',
  TracearrSeverity.unknown => Lexicon.noFigure,
};

/// How a stream reaches the viewer, in Tracearr's three words. Null when the
/// row carries no decision at all: it is not claimed as a direct play.
String? tracearrMethodWord(TracearrQuality quality) {
  if (quality.isTranscode) return 'Transcode';
  if (quality.isDirectStream) return 'Direct stream';
  if (quality.isDirectPlay) return 'Direct play';
  return null;
}

/// What is playing, as a row's title: a movie by its title, an episode by its
/// show and its code (`Night Shift · S1 E2`), a track by its artist.
String tracearrMediaTitleOf(TracearrMedia media) {
  final title = media.title.trim();
  final show = media.showTitle?.trim();
  switch (media.type) {
    case TracearrMediaType.episode || TracearrMediaType.season:
      final season = media.seasonNumber;
      final episode = media.episodeNumber;
      final code = season != null && episode != null
          ? formatEpisodeCode(season, episode)
          : null;
      final named = joinDisplayParts([show, code, if (show == null) title]);
      return named.isEmpty ? (title.isEmpty ? 'Untitled' : title) : named;
    case TracearrMediaType.track:
      final named = joinDisplayParts([media.artist, title]);
      return named.isEmpty ? 'Untitled' : named;
    default:
      return title.isEmpty ? 'Untitled' : title;
  }
}

/// The page a row opens: a movie by its TMDB id. Null for everything else.
///
/// An episode's TMDB id on a Tracearr row is not the series': the row names
/// the series by Tracearr's own id, which Cupola cannot open a page by, so an
/// episode, a track or a title with no external id is a row that is only read,
/// never a door that leads nowhere.
MediaKey? tracearrMediaKeyOf(TracearrMedia media) {
  final tmdb = media.ids.tmdb;
  if (media.type != TracearrMediaType.movie || tmdb == null || tmdb <= 0) {
    return null;
  }
  return MediaKey.movie(tmdb);
}

/// What Tracearr did about a violation, in a person's words. The two actions
/// the owner's rules commonly carry are named; any other is its own word made
/// readable (`log_only` is `Log only`), never the raw key.
String tracearrActionWord(String type) => switch (type.trim()) {
  'notify' => 'Sent a notification',
  'terminate_stream' => 'Ended the stream',
  '' => 'An action',
  final other => humanizeCamelCase(other),
};

/// How an action ended, as a short word and, where Tracearr said why, the
/// reason: a skip's own word (`cooldown`) or a failure's message. A failed
/// action is the fault; a skipped one is Tracearr's choice and rests.
({String word, String? why}) tracearrActionResult(
  TracearrViolationAction action,
) {
  if (action.skipped) {
    final reason = action.skipReason?.trim();
    return (
      word: 'Skipped',
      why: reason == null || reason.isEmpty ? null : humanizeCamelCase(reason),
    );
  }
  if (action.success) return (word: 'Done', why: null);
  return (word: 'Failed', why: action.errorMessage?.trim());
}

/// A distance as the detail page says it, whole kilometres: `5,120 km`.
String tracearrDistanceWord(double km) {
  final whole = km.round();
  final digits = whole.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return withUnit('${whole < 0 ? '-' : ''}$grouped', 'km');
}

/// The time between two streams, to the minute: `1 h 35 min`.
String tracearrElapsedWord(Duration elapsed) => formatTimeSpan(elapsed);

/// `3 streams at once, the limit is 2`: the concurrent-streams rule in a
/// sentence. Pure numbers, nothing of where anyone is.
String tracearrConcurrentWord(TracearrConcurrentStreams rule) =>
    '${countLabel(rule.count, 'stream')} at once, the limit is ${rule.limit}';
