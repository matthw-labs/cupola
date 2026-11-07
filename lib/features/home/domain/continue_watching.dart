/// The words of the Home's Continue watching: what somebody started and did
/// not finish, how far in, and how long is left.
library;

import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// What a row is called: an episode's series, a movie's own title.
String resumeTitle(StreamItem item) {
  if (item.kind != StreamItemKind.episode) return item.title;
  final subtitle = item.subtitle;
  final series = subtitle == null ? '' : splitParts(subtitle).first.trim();
  return series.isEmpty || episodeCodePattern.hasMatch(series)
      ? item.title
      : series;
}

/// The line under it: `S2 E3 · The Second Cycle` for an episode, the year
/// for a movie, nothing when neither is known.
String resumeDetail(StreamItem item) {
  if (item.kind == StreamItemKind.episode) {
    final code =
        formatArrEpisodeCode(item.seasonNumber, item.episodeNumber) ??
        episodeCodePattern.stringMatch(item.subtitle ?? '');
    return [?code, item.title].join(dotSeparator);
  }
  return item.year == null ? '' : '${item.year}';
}

/// `5 min left`, from the runtime and where it stopped; null when the server
/// did not say one of the two.
String? resumeLeft(StreamItem item) {
  final runtime = item.runtimeMs;
  final offset = item.resumeOffsetMs;
  if (runtime == null || offset == null || offset >= runtime) return null;
  return '${formatTimeSpan(Duration(milliseconds: runtime - offset))} left';
}
