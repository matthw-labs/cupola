import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';

class QueueRetryException implements Exception {
  const QueueRetryException(this.message);

  final String message;
}

class QueueRetrySearchFailed extends QueueRetryException {
  const QueueRetrySearchFailed(this.cause)
    : super(
        'The release was blocklisted and its files were kept. '
        'Open the movie or episode to start a search.',
      );

  final Object cause;
}

/// Blocklist one tracked download and search only for the media it contains.
/// Sonarr and Radarr keep any partial files. Other Arr apps use their existing
/// failure handling.
Future<void> retryQueueDownload(
  ArrActivityMixin service,
  int queueId, {
  String? expectedDownloadId,
}) async {
  const noTarget = QueueRetryException(
    'The download could not be matched to a movie or episode. Refresh the '
    'queue before retrying.',
  );
  if (queueId <= 0) throw noTarget;
  if (service is! SonarrService && service is! RadarrService) {
    await service.removeFromQueue(
      queueId,
      removeFromClient: true,
      blocklist: true,
    );
    return;
  }

  final page = await service.getQueuePage();
  if (page.cutShort) throw noTarget;
  final records = page.recordMaps;
  final selected = records
      .where((row) => intOrNull(row['id']) == queueId)
      .firstOrNull;
  if (selected == null) throw noTarget;
  final downloadId = stringOrNull(selected['downloadId'])?.toLowerCase();
  if (expectedDownloadId != null &&
      expectedDownloadId.toLowerCase() != downloadId) {
    throw noTarget;
  }

  final Future<void> Function() search;
  if (service is SonarrService) {
    final episodeIds = {
      for (final row in records)
        if (identical(selected, row) ||
            (downloadId != null &&
                downloadId == stringOrNull(row['downloadId'])?.toLowerCase()))
          intOrNull(row['episodeId']),
    };
    if (episodeIds.any((id) => id == null || id <= 0)) throw noTarget;
    final ids = episodeIds.whereType<int>().toList()..sort();
    search = () => service.searchEpisodes(ids);
  } else if (service is RadarrService) {
    final movieId = intOrNull(selected['movieId']);
    if (movieId == null || movieId <= 0) throw noTarget;
    search = () => service.searchMovie(movieId);
  } else {
    throw noTarget;
  }

  await service.removeFromQueue(
    queueId,
    removeFromClient: false,
    blocklist: true,
    skipRedownload: true,
  );
  try {
    await search();
  } catch (error) {
    throw QueueRetrySearchFailed(error);
  }
}
