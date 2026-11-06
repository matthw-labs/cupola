import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';

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

/// The history types a person can filter by, in the order they are offered.
/// `unknown` is the server's word for what it could not tell and is not a
/// thing to ask for.
const List<TracearrHistoryMediaType> tracearrHistoryTypes = [
  TracearrHistoryMediaType.movie,
  TracearrHistoryMediaType.episode,
  TracearrHistoryMediaType.track,
  TracearrHistoryMediaType.live,
  TracearrHistoryMediaType.photo,
  TracearrHistoryMediaType.trailer,
];

/// A history type as the person says it: `Movies`, `Episodes`, `TV`.
String tracearrHistoryTypeWord(TracearrHistoryMediaType type) => switch (type) {
  TracearrHistoryMediaType.movie => 'Movies',
  TracearrHistoryMediaType.episode => 'Episodes',
  TracearrHistoryMediaType.track => 'Tracks',
  TracearrHistoryMediaType.live => 'TV',
  TracearrHistoryMediaType.photo => 'Photos',
  TracearrHistoryMediaType.trailer => 'Trailers',
  TracearrHistoryMediaType.unknown => 'Other',
};

/// A server as a list of servers names it: its own name, else its kind.
String tracearrServerLabel(TracearrServer server) {
  final name = server.name.trim();
  return name.isNotEmpty
      ? name
      : tracearrServerTypeWord(server.type) ?? 'Unnamed server';
}

/// A reason the server gives for transcoding, in words. Some servers name it
/// as an identifier (`VideoCodecNotSupported`); that is split into
/// `Video codec not supported`. Anything else is the server's own sentence,
/// kept as it came.
String tracearrReasonWords(String reason) {
  final text = reason.trim();
  if (!RegExp(r'^[A-Za-z]+$').hasMatch(text) ||
      !RegExp(r'[a-z][A-Z]').hasMatch(text)) {
    return text;
  }
  final words = text
      .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
      .split(' ');
  return [
    words.first,
    for (final word in words.skip(1)) word.toLowerCase(),
  ].join(' ');
}

/// The first reason a stream transcodes, in words, or null when it does not
/// or the server named none. A row speaks one sentence, so it gives one; the
/// detail lists them all.
String? tracearrTranscodeReason(TracearrQuality quality) {
  if (!quality.isTranscode) return null;
  final reasons = quality.transcode?.reasons ?? const <String>[];
  return reasons.isEmpty ? null : tracearrReasonWords(reasons.first);
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

/// The page a row opens, when the ids on it identify the title: a movie by its
/// TMDB id, a series by its own ids (TMDB's, else TheTVDB's). Null for
/// everything else.
///
/// An episode's ids on a Tracearr row are the episode's, not the series':
/// the row names the series by Tracearr's own id, which Cupola cannot open a
/// page by. So an episode, a track or a title with no external id is a row
/// that is only read, never a door that leads to the wrong title or nowhere.
MediaKey? tracearrMediaKeyOf(TracearrMedia media) {
  final tmdb = media.ids.tmdb;
  final tvdb = media.ids.tvdb;
  return switch (media.type) {
    TracearrMediaType.movie when tmdb != null && tmdb > 0 => MediaKey.movie(
      tmdb,
    ),
    TracearrMediaType.show when tmdb != null && tmdb > 0 => MediaKey.tv(tmdb),
    TracearrMediaType.show when tvdb != null && tvdb > 0 => MediaKey.tvdb(tvdb),
    _ => null,
  };
}
