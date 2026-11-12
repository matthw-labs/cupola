import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

/// Resolves the badge status for a Sonarr series.
///
/// [queueUnknown] as in `radarrMovieStatus`: `!snapshot.isWhole`, so a series
/// whose queue could not be read never reads `Missing` for want of an entry.
MediaStatusInfo sonarrSeriesStatus(
  SonarrSeries series, {
  ArrQueueEntry? queueEntry,
  bool queueUnknown = false,
}) {
  return mediaStatusFromQueue(
    availability: sonarrSeriesAvailability(series),
    monitored: series.monitored,
    queueEntry: queueEntry,
    queueUnknown: queueUnknown,
  );
}

MediaAvailability sonarrSeriesAvailability(SonarrSeries series) {
  if (series.status.toLowerCase() == 'deleted') {
    return MediaAvailability.deleted;
  }

  // Both figures or neither: a missing `episodeCount` read as `0` made a series
  // with no files "Not released", a claim about the schedule from no data.
  final files = series.episodeFileCount;
  final aired = series.episodeCount;
  if (series.statistics == null || files == null || aired == null) {
    return MediaAvailability.unknown;
  }

  // `episodeCount` counts aired, monitored episodes, so a continuing series
  // that holds everything broadcast so far is `available` rather than being
  // stuck at `partial` forever.
  if (aired <= 0) {
    return files > 0
        ? MediaAvailability.available
        : MediaAvailability.unavailable;
  }

  return availabilityFromCounts(fileCount: files, totalCount: aired);
}

/// Resolves the status of one episode.
///
/// [queueEntry] is the episode's record in the queue
/// (`SonarrQueueSnapshots.byEpisode`): an episode being downloaded reads
/// downloading, never `Missing`. [queueUnknown] as in [sonarrSeriesStatus]:
/// with the queue unread, an aired episode with no file may be on its way,
/// and reads unknown rather than `Missing`.
///
/// [now] is injectable so the unaired case is testable without freezing the
/// clock; it defaults to the wall clock.
MediaStatusInfo sonarrEpisodeStatus(
  SonarrEpisode episode, {
  DateTime? now,
  ArrQueueEntry? queueEntry,
  bool queueUnknown = false,
}) {
  return mediaStatusFromQueue(
    availability: sonarrEpisodeAvailability(episode, now: now),
    monitored: episode.monitored,
    queueEntry: queueEntry,
    queueUnknown: queueUnknown,
  );
}

MediaAvailability sonarrEpisodeAvailability(
  SonarrEpisode episode, {
  DateTime? now,
}) {
  if (episode.hasFile) return MediaAvailability.available;
  // Not yet broadcast: nothing is wrong and nothing is expected, so this is
  // "Not released" rather than the red "Missing" every future episode of a
  // continuing series used to draw.
  // With no date at all (Sonarr's `TBA`) it is not on the way to Wanted
  // either: Sonarr leaves it out, and so does this.
  if (!episode.hasAiredAt(now ?? DateTime.now())) {
    return MediaAvailability.unavailable;
  }

  return MediaAvailability.missing;
}
