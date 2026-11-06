import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';

import '../../test_helpers/capturing_http_adapter.dart';
import '../../test_helpers/fixtures.dart';

/// What a live Tracearr 3.1.4 watching an Emby actually answered, sanitised
/// (people renamed, no addresses). The invented fixtures beside them cover
/// what this one lacks: transcodes, Plex, violations.
const _real = 'tracearr/real_';

TracearrClient _client(CapturingHttpAdapter adapter) {
  final client = TracearrClient(
    baseUrl: 'https://tracearr.test',
    apiKey: 'trr_pub_exampleexampleexampleexampleexampleexample1',
  );
  client.dio.httpClientAdapter = adapter;
  addTearDown(client.close);
  return client;
}

CapturingHttpAdapter _answering(String name) =>
    CapturingHttpAdapter(response: jsonFixture('$_real$name.json'));

void main() {
  const embyId = '5d81be5e-a172-4cba-9ed8-3f16e054e83f';
  const annaId = '9d7d8f7d-0e17-4f3a-a169-bbc545d802c2';

  test('health lists the Emby with its camelCase fields', () async {
    final health = await _client(_answering('health')).getHealth();

    expect(health.isOk, isTrue);
    expect(health.version, 'v3.1.4');
    expect(health.timestamp, isNotNull);
    final server = health.servers.single;
    expect(server.id, embyId);
    expect(server.type, TracearrServerType.emby);
    expect(server.online, isTrue);
    expect(server.activeStreams, 2);
  });

  test('servers: up, no reason, no version of its own', () async {
    final servers = await _client(_answering('servers')).getServers();

    expect(servers.tracearrVersion, 'v3.1.4');
    final server = servers.servers.single;
    expect(server.name, 'Casa Emby');
    expect(server.status, TracearrServerStatus.up);
    expect(server.reason, isNull);
    expect(server.version, isNull);
    expect(server.activeStreams, 2);
  });

  test('live streams: two direct plays with the formatted bitrate', () async {
    final streams = await _client(_answering('streams_live')).getStreams();

    expect(streams.dropped, 0);
    expect(streams.streams, hasLength(2));
    expect(streams.summary.total, 2);
    expect(streams.summary.directPlays, 2);
    expect(streams.summary.totalBitrate, '379 kbps');
    expect(streams.byServer.single.serverId, embyId);
    final bunny = streams.streams.first;
    expect(bunny.state, TracearrStreamState.playing);
    expect(bunny.person.name, 'Anna');
    expect(bunny.media.type, TracearrMediaType.movie);
    expect(bunny.media.durationMs, 120021);
    expect(bunny.media.ids.libraryId, '3');
    expect(bunny.quality.videoDecision, TracearrDecision.directPlay);
    expect(bunny.quality.audioDecision, TracearrDecision.directPlay);
    expect(bunny.quality.isDirectPlay, isTrue);
    expect(bunny.quality.bitrate, 372);
    expect(bunny.quality.resolution, '1080p');
    expect(bunny.quality.source.width, 1920);
    expect(bunny.quality.source.frameRate, '1');
    expect(bunny.quality.source.level, '40');
    expect(bunny.quality.source.colorDepth, 8);
    expect(bunny.quality.source.dynamicRange, 'SDR');
    expect(bunny.quality.source.channelLayout, 'stereo');
    expect(bunny.quality.output.videoCodec, 'H264');
    expect(bunny.quality.transcode, isNull);
    expect(bunny.device.product, 'Emby Web');
    expect(bunny.startedAt, isNotNull);
  });

  test('no streams: the idle answer keeps its em dash as data', () async {
    final streams = await _client(_answering('streams_idle')).getStreams();

    expect(streams.streams, isEmpty);
    expect(streams.summary.total, 0);
    expect(streams.summary.totalBitrate, '—');
    expect(streams.byServer, isEmpty);
  });

  test('today and the v1 camelCase counters', () async {
    final today = await _client(_answering('today')).getToday();

    expect(today.activeStreams, 2);
    expect(today.todayPlays, 1);
    expect(today.todaySessions, 2);
    expect(today.watchTimeHours, 0);
    expect(today.activeUsersToday, 1);
  });

  test('history: the quoted bigints are read, not dropped', () async {
    final page = await _client(_answering('history')).getHistory();

    expect(page.dropped, 0);
    expect(page.items, hasLength(2));
    expect(page.hasMore, isFalse);
    expect(page.pageSize, 25);
    final row = page.items.first;
    expect(row.state, TracearrStreamState.stopped);
    expect(row.progressMs, 270000);
    expect(row.totalDurationMs, 2000);
    expect(row.percentComplete, 100);
    expect(row.watched, isTrue);
    expect(row.segmentCount, 1);
    expect(row.stoppedAt, isNotNull);
    expect(row.referenceId, row.id);
    expect(row.person.id, annaId);
    expect(row.person.name, 'Anna');
    expect(row.media.durationMs, 62000);
    expect(row.media.ids.mediaId, '13925ec5-c7a3-42ef-9cb9-38118462c8de');
    expect(row.quality.source.profile, 'Constrained Baseline');
    expect(row.quality.source.sampleRate, 48000);
    expect(row.device.device, 'Infuse');
    // The lab's own numbers: the second viewing quotes its bigints too.
    expect(page.items.last.progressMs, 290000);
    expect(page.items.last.totalDurationMs, 120021);
  });

  test('the same page for a person reads the same', () async {
    final page = await _client(_answering('user_history')).getHistory();

    expect(page.items.first.progressMs, 270000);
  });

  test('users and one user: accounts with the media server ids', () async {
    final page = await _client(_answering('users')).getUsers();

    expect(page.items.map((u) => u.username), ['Anna', 'Luca']);
    expect(page.items.first.identityName, isNull);
    expect(
      page.items.first.activeAccounts.single.serverType,
      TracearrServerType.emby,
    );
    expect(
      page.items.first.accounts.single.externalUserId,
      'ce18a8c31c4f49f291677ac853d0fb12',
    );
    final user = await _client(_answering('user')).getUser(annaId);
    expect(user!.accounts.single.serverId, embyId);
    expect(user.isRemoved, isFalse);
  });

  test('user stats: windows with no top genres', () async {
    final stats = await _client(_answering('user_stats')).getUserStats(annaId);

    expect(stats!.userId, annaId);
    expect(stats.allTime.plays, 1);
    expect(stats.last30.plays, 1);
    expect(stats.last7.plays, 1);
    expect(stats.topGenres, isEmpty);
  });

  test('top media: movies with no external ids', () async {
    final page = await _client(
      _answering('top_media'),
    ).getTopMedia(mediaType: TracearrTopMediaType.movie);

    expect(page.pageSize, 100);
    expect(page.items.map((t) => t.title), ['Big Buck Bunny', 'The Matrix']);
    expect(page.items.first.mediaType, TracearrMediaType.movie);
    expect(page.items.first.tmdbId, isNull);
    expect(page.items.first.watchTimeMs, 180021);
    expect(page.items.first.uniqueUsers, 1);
    expect(page.items.first.lastWatchedDay, DateTime.parse('2026-11-06'));
  });

  test('watchers of a title by its Tracearr id', () async {
    final watchers = await _client(_answering('watchers_by_id')).getWatchers(
      const TracearrMediaRef.id('13925ec5-c7a3-42ef-9cb9-38118462c8de'),
    );

    expect(watchers!.mediaType, TracearrMediaType.movie);
    expect(watchers.window, TracearrWindow.allTime);
    final watcher = watchers.watchers.single;
    expect(watcher.username, 'Anna');
    expect(watcher.userId, annaId);
    expect(watcher.plays, 1);
    expect(watcher.watchTimeMs, 62000);
    expect(watcher.completionPct, 100);
    expect(watcher.distinctEpisodesWatched, isNull);
    expect(watchers.lastWatchedDay, DateTime.parse('2026-11-06'));
  });

  test('an unknown TMDB ref is a 404 that reads as null', () async {
    final adapter = CapturingHttpAdapter(
      statusCode: 404,
      response: const {
        'statusCode': 404,
        'error': 'NotFoundError',
        'message': 'Not Found',
      },
    );

    final watchers = await _client(
      adapter,
    ).getWatchers(TracearrMediaRef.movieTmdb(603));

    expect(watchers, isNull);
  });

  group('the event stream as captured', () {
    late String text;

    setUpAll(() {
      text = File('test/fixtures/tracearr/real_events.sse').readAsStringSync();
    });

    Future<List<SseFrame>> frames(int chunkSize) async {
      final bytes = utf8.encode(text);
      final chunks = [
        for (var i = 0; i < bytes.length; i += chunkSize)
          bytes.sublist(
            i,
            i + chunkSize > bytes.length ? bytes.length : i + chunkSize,
          ),
      ];
      return sseFrames(Stream.fromIterable(chunks)).toList();
    }

    test('retry comes first, then ready, then full rows and ticks', () async {
      final retries = <Duration>[];
      final all = await sseFrames(
        Stream.value(utf8.encode(text)),
        onRetry: retries.add,
      ).toList();

      expect(retries, [const Duration(seconds: 5)]);
      expect(all.first.event, 'ready');
      expect(all.map((f) => f.event).toSet(), {
        'ready',
        'stream.updated',
        'stream.progress',
      });
      final events = [for (final frame in all) ?tracearrEventFrom(frame)];
      expect(events, hasLength(all.length));
      expect(events.first, isA<TracearrReady>());
      expect(events.first.at, isNotNull);
      final updated = events.whereType<TracearrStreamUpdated>().first;
      expect(updated.stream.media.title, 'Big Buck Bunny');
      expect(updated.stream.state, TracearrStreamState.playing);
      expect(updated.stream.progressMs, 55009);
      expect(updated.stream.quality.bitrate, 372);
      final tick = events.whereType<TracearrStreamProgress>().first;
      expect(tick.progressMs, 55009);
      expect(tick.state, TracearrStreamState.playing);
      expect(tick.applyTo(updated.stream).progressMs, 55009);
    });

    test('chunks cut anywhere give the same frames', () async {
      final whole = await frames(1 << 20);

      for (final size in [1, 7, 4096]) {
        final cut = await frames(size);
        expect(
          cut.map((f) => f.data),
          whole.map((f) => f.data),
          reason: '$size',
        );
      }
    });
  });
}
