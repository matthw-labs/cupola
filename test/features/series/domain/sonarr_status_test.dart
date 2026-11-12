import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';

import '../../../test_helpers/model_builders.dart';

void main() {
  group('sonarrSeriesAvailability', () {
    test('all aired episodes on disk is available', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            statistics: const {'episodeCount': 10, 'episodeFileCount': 10},
          ),
        ),
        MediaAvailability.available,
      );
    });

    test('a continuing series holding every aired episode is available', () {
      // `episodeCount` counts aired, monitored episodes; a running show must
      // not be stuck at `partial` forever just because more will air later.
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            status: 'continuing',
            statistics: const {
              'episodeCount': 8,
              'totalEpisodeCount': 20,
              'episodeFileCount': 8,
            },
          ),
        ),
        MediaAvailability.available,
      );
    });

    test('some aired episodes on disk is partial', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            statistics: const {'episodeCount': 10, 'episodeFileCount': 4},
          ),
        ),
        MediaAvailability.partial,
      );
    });

    test('no episodes on disk is missing', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            statistics: const {'episodeCount': 10, 'episodeFileCount': 0},
          ),
        ),
        MediaAvailability.missing,
      );
    });

    test('nothing aired yet is unavailable, not missing', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            status: 'upcoming',
            statistics: const {
              'episodeCount': 0,
              'totalEpisodeCount': 10,
              'episodeFileCount': 0,
            },
          ),
        ),
        MediaAvailability.unavailable,
      );
    });

    test('absent statistics is unknown rather than missing', () {
      expect(
        sonarrSeriesAvailability(buildSeries()),
        MediaAvailability.unknown,
      );
    });

    test('a missing episode count is unknown, not "Not released"', () {
      // Read as `0`, a series with no files was "nothing aired yet": a claim
      // about the schedule from a figure Sonarr never sent.
      expect(
        sonarrSeriesAvailability(
          buildSeries(statistics: const {'episodeFileCount': 0}),
        ),
        MediaAvailability.unknown,
      );
    });

    test('deleted outranks the counts', () {
      expect(
        sonarrSeriesAvailability(
          buildSeries(
            status: 'deleted',
            statistics: const {'episodeCount': 10, 'episodeFileCount': 10},
          ),
        ),
        MediaAvailability.deleted,
      );
    });
  });

  group('sonarrSeriesStatus', () {
    test('a series in the queue never reads Missing', () {
      final status = sonarrSeriesStatus(
        buildSeries(
          statistics: const {'episodeCount': 10, 'episodeFileCount': 0},
        ),
        queueEntry: const ArrQueueEntry(
          pipeline: MediaPipeline.downloading,
          progress: 0.3,
        ),
      );

      expect(status.label, 'Downloading');
      expect(status.availability, MediaAvailability.missing);
    });

    test('a partially available series in the queue reports the download', () {
      final status = sonarrSeriesStatus(
        buildSeries(
          statistics: const {'episodeCount': 10, 'episodeFileCount': 4},
        ),
        queueEntry: const ArrQueueEntry(pipeline: MediaPipeline.importPending),
      );

      expect(status.label, 'Waiting to import');
      expect(status.availability, MediaAvailability.partial);
    });
  });

  group('SonarrSeries statistics getters', () {
    test('reads the counts Sonarr exposes', () {
      final series = buildSeries(
        statistics: const {
          'episodeCount': 8,
          'totalEpisodeCount': 20,
          'episodeFileCount': 5,
        },
      );

      expect(series.episodeCount, 8);
      expect(series.totalEpisodeCount, 20);
      expect(series.episodeFileCount, 5);
      expect(series.hasFiles, isTrue);
    });

    test('absent statistics yields nulls, not zeros', () {
      final series = buildSeries();

      expect(series.episodeCount, isNull);
      expect(series.episodeFileCount, isNull);
      expect(series.hasFiles, isFalse);
    });
  });

  group('sonarrEpisodeStatus', () {
    test('a file on disk is available', () {
      final status = sonarrEpisodeStatus(buildEpisode(hasFile: true));

      expect(status.availability, MediaAvailability.available);
      expect(status.tone, StatusTone.success);
    });

    test('an aired episode with no file is missing', () {
      final status = sonarrEpisodeStatus(
        _episode(hasFile: false, airDateUtc: '2011-04-17T00:00:00Z'),
        now: DateTime.utc(2026, 1, 1),
      );

      expect(status.availability, MediaAvailability.missing);
      expect(status.label, 'Missing');
    });

    test('an unaired episode is Not released, never Missing', () {
      final status = sonarrEpisodeStatus(
        _episode(hasFile: false, airDateUtc: '2999-01-01T00:00:00Z'),
        now: DateTime.utc(2026, 1, 1),
      );

      expect(status.availability, MediaAvailability.unavailable);
      expect(status.label, 'Not released');
      expect(status.tone, StatusTone.neutral);
    });

    // Issue #13: Sonarr's `TBA` sends no date, and its Wanted leaves the
    // episode out. Reading "no date" as "aired" made every one `Missing`.
    test('an episode with no air date and no file is never Missing', () {
      final status = sonarrEpisodeStatus(
        _episode(hasFile: false),
        now: DateTime.utc(2026, 1, 1),
      );

      expect(status.availability, isNot(MediaAvailability.missing));
      expect(status.label, isNot('Missing'));
    });

    test('a queue entry wins over the availability axis', () {
      final status = sonarrEpisodeStatus(
        _episode(hasFile: false),
        now: DateTime.utc(2026, 1, 1),
        queueEntry: ArrQueueEntry.fromQueueItem(const {
          'status': 'downloading',
          'size': 100,
          'sizeleft': 25,
        }),
      );

      expect(status.pipeline, MediaPipeline.downloading);
      expect(status.progressPercent, 75);
    });
  });
}

SonarrEpisode _episode({bool hasFile = false, String? airDateUtc}) {
  return SonarrEpisode(
    id: 1,
    seasonNumber: 1,
    episodeNumber: 1,
    title: 'Episode',
    hasFile: hasFile,
    monitored: true,
    airDateUtc: airDateUtc,
  );
}
