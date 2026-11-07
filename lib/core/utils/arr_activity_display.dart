import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';

/// [parts] trimmed, the empty ones left out, joined by [separator].
///
/// With [distinct], a part that says what an earlier one already said (the
/// same words, ignoring case) is left out: a player and a product that a
/// client names alike read once.
String joinDisplayParts(
  Iterable<String?> parts, {
  String separator = dotSeparator,
  bool distinct = false,
}) {
  final kept = parts
      .whereType<String>()
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  if (!distinct) return kept.join(separator);
  final seen = <String>{};
  return kept.where((part) => seen.add(part.toLowerCase())).join(separator);
}

List<String> extractArrStatusMessages(dynamic rawMessages) {
  if (rawMessages is! List || rawMessages.isEmpty) return const [];

  final messages = <String>[];
  for (final entry in rawMessages) {
    final map = mapOrNull(entry);
    if (map == null) {
      final text = stringOrNull(entry);
      if (text != null) messages.add(text);
      continue;
    }

    final title = stringOrNull(map['title']);
    final nestedMessages = map['messages'];
    if (nestedMessages is List && nestedMessages.isNotEmpty) {
      for (final nested in nestedMessages) {
        final body = stringOrNull(nested);
        if (body != null) {
          messages.add(title == null ? body : '$title: $body');
        }
      }
      continue;
    }

    final text = stringOrNull(map['message'] ?? map['text'] ?? map['title']);
    if (text != null) messages.add(text);
  }

  return messages;
}

String? arrReleaseTitle(Map<String, dynamic> item) {
  return stringOrNull(item['title'] ?? item['sourceTitle']);
}

String? arrMovieTitle(Map<String, dynamic> item, {bool includeYear = false}) {
  final movie = mapOrNull(item['movie']);
  final title = stringOrNull(movie?['title']);
  final year = intOrNull(movie?['year'] ?? item['year']);
  if (title == null) return null;
  if (!includeYear || year == null) return title;
  return '$title ($year)';
}

String? arrSeriesTitle(Map<String, dynamic> item) {
  return stringOrNull(
    mapOrNull(item['series'])?['title'] ?? item['seriesTitle'],
  );
}

String? arrEpisodeTitle(Map<String, dynamic> item) {
  return stringOrNull(
    mapOrNull(item['episode'])?['title'] ?? item['episodeTitle'],
  );
}

String? arrEpisodeCode(Map<String, dynamic> item) {
  final episode = mapOrNull(item['episode']);
  return formatArrEpisodeCode(
    intOrNull(episode?['seasonNumber'] ?? item['seasonNumber']),
    intOrNull(episode?['episodeNumber'] ?? item['episodeNumber']),
  );
}

String? arrArtistName(Map<String, dynamic> item) {
  return stringOrNull(mapOrNull(item['artist'])?['artistName']);
}

String? arrAlbumTitle(Map<String, dynamic> item) {
  return stringOrNull(mapOrNull(item['album'])?['title']);
}

String? arrBookTitle(Map<String, dynamic> item) {
  return stringOrNull(mapOrNull(item['book'])?['title']);
}

String? arrAuthorName(Map<String, dynamic> item) {
  return stringOrNull(mapOrNull(item['author'])?['authorName']);
}

/// The name of the thing an \*arr queue, history or blocklist record is about.
///
/// One lookup per fork, in the order the app's call sites want them: the
/// subject of the record first, the person or group behind it as the fallback.
///
/// **The book and author arms are not optional extras.** Readarr files its
/// records against `book` and `author` and against nothing else, so while they
/// were missing every one of the other four lookups missed and this function
/// answered null for *every* Readarr record. Its callers all fall back to
/// [arrReleaseTitle] on null, which is the raw release string; so a Readarr
/// queue row on the Dashboard read `Orbital.2023.RETAIL.EPUB-XYZ` while the
/// row beside it from Radarr read `Dune`. One arm fixed every call site, and
/// `readarr_overview_provider.dart` carries a local `readarrRecordTitle` whose
/// doc comment names this gap as the reason it exists.
String? arrPrimaryMediaTitle(
  Map<String, dynamic> item, {
  bool includeMovieYear = false,
}) {
  return arrMovieTitle(item, includeYear: includeMovieYear) ??
      arrSeriesTitle(item) ??
      arrAlbumTitle(item) ??
      // Book before author for the same reason album comes before artist: the
      // book is what the record is about, and "Import failed · Samantha
      // Harvey" names the wrong noun.
      arrBookTitle(item) ??
      arrArtistName(item) ??
      arrAuthorName(item);
}

/// How badly an \*arr queue record is doing, as the service itself reports it.
///
/// `trackedDownloadStatus` carries three values and this layer used to collapse
/// two of them into a single `bool`: a record the service marked `error` came out
/// identical to one marked `warning`, so a definite failure and a passing notice
/// were the same colour and the same weight on screen. [StatusTone] has had
/// distinct `warning` and `error` all along: the information existed upstream
/// and was thrown away in the middle.
enum ArrQueueSeverity { ok, warning, error }

/// Reads the severity an \*arr reported for a queue record.
///
/// Note that a non-empty `statusMessages` counts as a warning even when
/// `trackedDownloadStatus` is absent or `ok`. That is deliberate and matches the
/// \*arr web UI: on the queue endpoint those messages are the mechanism by which
/// a service says something needs looking at ("Unable to Import Automatically"
/// is the canonical one), unlike on history where they can be incidental.
ArrQueueSeverity arrQueueSeverity(Map<String, dynamic> item) {
  final trackedStatus = stringOrNull(
    item['trackedDownloadStatus'],
  )?.toLowerCase();

  if (trackedStatus == 'error') return ArrQueueSeverity.error;
  if (trackedStatus == 'warning' ||
      extractArrStatusMessages(item['statusMessages']).isNotEmpty) {
    return ArrQueueSeverity.warning;
  }
  return ArrQueueSeverity.ok;
}

bool arrQueueHasWarning(Map<String, dynamic> item) {
  return arrQueueSeverity(item) != ArrQueueSeverity.ok;
}

String? arrQueueWarningMessage(Map<String, dynamic> item) {
  final messages = extractArrStatusMessages(item['statusMessages']);
  if (messages.isNotEmpty) return messages.first;
  return arrQueueHasWarning(item) ? 'Warning' : null;
}
