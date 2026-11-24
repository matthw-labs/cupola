import 'package:cupola/features/activity/data/queue_retry.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_helpers/fake_api_client.dart';

Map<String, dynamic> _page(List<Map<String, dynamic>> records) => {
  'totalRecords': records.length,
  'records': records,
};

const _preserveAndBlocklist = {
  'removeFromClient': false,
  'blocklist': true,
  'skipRedownload': true,
};

void main() {
  test(
    'Sonarr preserves the failed release and searches only its episodes',
    () async {
      final client = FakeApiClient()
        ..getResponseData = _page([
          {'id': 50, 'downloadId': 'ABC', 'episodeId': 3, 'seriesId': 101},
          {'id': 51, 'downloadId': 'abc', 'episodeId': 2, 'seriesId': 101},
          {'id': 52, 'downloadId': 'other', 'episodeId': 4, 'seriesId': 101},
        ]);

      await retryQueueDownload(
        SonarrService(client),
        50,
        expectedDownloadId: 'abc',
      );

      expect(client.lastDeletePath, '/api/v3/queue/50');
      expect(client.lastDeleteQueryParameters, _preserveAndBlocklist);
      expect(client.lastPostPath, '/api/v3/command');
      expect(client.lastPostData, {
        'name': 'EpisodeSearch',
        'episodeIds': [2, 3],
      });
      expect(client.postCallCount, 1);
    },
  );

  test('Lidarr still uses the original queue retry request', () async {
    final client = FakeApiClient();

    await retryQueueDownload(LidarrService(client), 50);

    expect(client.lastDeleteQueryParameters, {
      'removeFromClient': true,
      'blocklist': true,
    });
    expect(client.getCallCount, 0);
    expect(client.postCallCount, 0);
  });

  test('Radarr searches only the selected movie', () async {
    final client = FakeApiClient()
      ..getResponseData = _page([
        {'id': 50, 'movieId': 7},
        {'id': 51, 'movieId': 19},
      ]);

    await retryQueueDownload(RadarrService(client), 50);

    expect(client.lastDeleteQueryParameters, _preserveAndBlocklist);
    expect(client.lastPostData, {
      'name': 'MoviesSearch',
      'movieIds': [7],
    });
  });

  test('a stale or unmatchable job causes no write', () async {
    final client = FakeApiClient()
      ..getResponseData = _page([
        {'id': 50, 'downloadId': 'current', 'seriesId': 101},
      ]);
    final sonarr = SonarrService(client);

    await expectLater(
      retryQueueDownload(sonarr, 50, expectedDownloadId: 'stale'),
      throwsA(isA<QueueRetryException>()),
    );
    await expectLater(
      retryQueueDownload(sonarr, 50),
      throwsA(isA<QueueRetryException>()),
    );
    expect(client.deleteCallCount, 0);
    expect(client.postCallCount, 0);
  });

  test('failed blocklisting does not start a search', () async {
    final blocked = Exception('blocklist denied');
    final client = FakeApiClient()
      ..getResponseData = _page([
        {'id': 50, 'movieId': 7},
      ])
      ..deleteException = blocked;

    await expectLater(
      retryQueueDownload(RadarrService(client), 50),
      throwsA(same(blocked)),
    );
    expect(client.postCallCount, 0);
  });

  test('reports partial success separately if the search fails', () async {
    final denied = Exception('search denied');
    final client = FakeApiClient()
      ..getResponseData = _page([
        {'id': 50, 'movieId': 7},
      ])
      ..postException = denied;

    await expectLater(
      retryQueueDownload(RadarrService(client), 50),
      throwsA(
        isA<QueueRetrySearchFailed>().having(
          (error) => error.cause,
          'cause',
          denied,
        ),
      ),
    );
    expect(client.deleteCallCount, 1);
    expect(client.postCallCount, 1);
    expect(client.lastDeleteQueryParameters, _preserveAndBlocklist);
  });
}
