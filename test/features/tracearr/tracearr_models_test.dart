import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_image.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_version.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';

import '../../test_helpers/fixtures.dart';

const _plexId = '5b1f3c2e-8a40-4d57-9b6e-0c1a2f3d4e51';
const _annaId = '7a3e91c4-5d28-4b6f-8e10-2f4a6c8d0b13';

void main() {
  group('servers and health', () {
    test('servers read their status, reason and version', () {
      final servers = TracearrServers.fromJson(
        jsonFixture('tracearr/servers.json'),
      );

      expect(servers.tracearrVersion, 'v3.1.4');
      expect(servers.version, const TracearrVersion(3, 1, 4));
      expect(servers.servers.map((s) => s.type), [
        TracearrServerType.plex,
        TracearrServerType.emby,
        TracearrServerType.jellyfin,
      ]);
      final plex = servers.servers[0];
      expect(plex.id, _plexId);
      expect(plex.isUp, isTrue);
      expect(plex.activeStreams, 1);
      expect(plex.version, '1.42.2.10156');
      expect(plex.reason, isNull);

      final jellyfin = servers.servers[2];
      expect(jellyfin.status, TracearrServerStatus.down);
      expect(jellyfin.reason, TracearrServerReason.unauthorized);
      expect(jellyfin.isUnauthorized, isTrue);
      expect(jellyfin.version, isNull);
    });

    test('health names the version with its leading v', () {
      final health = TracearrHealth.fromJson(
        jsonFixture('tracearr/health.json'),
      );

      expect(health.isOk, isTrue);
      expect(health.version, 'v3.1.4');
      expect(health.parsedVersion, const TracearrVersion(3, 1, 4));
      expect(health.timestamp, DateTime.utc(2026, 11, 6, 10, 15));
      expect(health.servers, hasLength(3));
      expect(health.servers[2].online, isFalse);
      expect(health.servers[1].type, TracearrServerType.emby);
    });

    test('a body that is not an object is a wrong answer', () {
      expect(
        () => TracearrServers.fromJson(<Object?>[]),
        throwsFormatException,
      );
      expect(() => TracearrHealth.fromJson('<html>'), throwsFormatException);
      expect(() => TracearrToday.fromJson(null), throwsFormatException);
    });

    test('a server without an id is dropped, not the list', () {
      final servers = TracearrServers.fromJson({
        'data': [
          {'server_name': 'No id'},
          {'server_id': 'abc', 'server_name': 'Good'},
        ],
        'tracearr_version': 'v3.1.4',
      });

      expect(servers.servers.map((s) => s.id), ['abc']);
    });
  });

  group('streams', () {
    final streams = TracearrStreams.fromJson(
      jsonFixture('tracearr/streams.json'),
    );

    test('a transcode on Plex carries source against output', () {
      final stream = streams.streams[0];

      expect(stream.server.type, TracearrServerType.plex);
      expect(stream.server.name, 'Plex Living Room');
      expect(stream.state, TracearrStreamState.playing);
      expect(stream.media.type, TracearrMediaType.movie);
      expect(stream.media.title, 'The Lantern Keeper');
      expect(stream.media.year, 2021);
      expect(stream.media.ids.tmdb, 603);
      expect(stream.media.ids.imdb, 'tt0000001');
      expect(stream.media.ids.ratingKey, '4410');
      expect(stream.media.ids.hasExternalId, isTrue);
      expect(stream.media.genres, ['Drama', 'Fantasy']);
      expect(stream.media.duration, const Duration(milliseconds: 7080000));
      expect(stream.progress, closeTo(0.3686, 0.0001));
      expect(stream.startedAt, DateTime.utc(2026, 11, 6, 9, 42, 10));

      expect(stream.person.name, 'Anna');
      expect(stream.person.id, isNull, reason: 'a live row has no user id');
      expect(stream.person.avatarUrl, startsWith('/api/v1/images/proxy?'));
      expect(stream.media.posterUrl, startsWith('/api/v1/images/proxy?'));
      expect(stream.device.name, 'Living Room TV');
      expect(stream.device.platform, 'webOS');

      final quality = stream.quality;
      expect(quality.isTranscode, isTrue);
      expect(quality.videoDecision, TracearrDecision.transcode);
      expect(quality.audioDecision, TracearrDecision.copy);
      expect(quality.isDirectPlay, isFalse);
      expect(quality.isDirectStream, isFalse);
      expect(quality.bitrate, 8200);
      expect(quality.resolution, '1080p');
      expect(quality.source.videoCodec, 'hevc');
      expect(quality.source.videoCodecDisplay, 'HEVC');
      expect(quality.source.width, 3840);
      expect(quality.source.height, 2160);
      expect(quality.source.isHdr, isTrue);
      expect(quality.source.colorDepth, 10);
      expect(quality.source.audioChannels, 6);
      expect(quality.source.channelLayout, '5.1');
      expect(quality.output.videoCodec, 'h264');
      expect(quality.output.width, 1920);
      expect(quality.output.height, 1080);
      expect(quality.output.isHdr, isFalse);
      expect(quality.output.audioChannels, 6);
      expect(quality.transcode?.reasons, [
        'Video codec not supported',
        'Video resolution above the client limit',
      ]);
      expect(quality.transcode?.hwDecoding, 'videotoolbox');
      expect(quality.transcode?.usesHardware, isTrue);
      expect(quality.transcode?.speed, 1.4);
      expect(quality.transcode?.throttled, isFalse);
      expect(quality.transcode?.containerDecision, TracearrDecision.transcode);
      expect(quality.subtitle?.decision, 'burn');
      expect(quality.subtitle?.language, 'ita');
    });

    test('a direct play on Emby is paused and an episode', () {
      final stream = streams.streams[1];

      expect(stream.server.type, TracearrServerType.emby);
      expect(stream.state, TracearrStreamState.paused);
      expect(stream.isPaused, isTrue);
      expect(stream.media.type, TracearrMediaType.episode);
      expect(stream.media.showTitle, 'Harbor Lights');
      expect(stream.media.seasonNumber, 2);
      expect(stream.media.episodeNumber, 5);
      expect(stream.media.ids.tvdb, 81189);
      expect(stream.media.ids.showMediaId, isNotNull);
      expect(stream.person.avatarUrl, isNull);
      expect(stream.quality.isTranscode, isFalse);
      expect(stream.quality.isDirectPlay, isTrue);
      expect(stream.quality.transcode?.reasons, isEmpty);
      expect(stream.quality.subtitle?.decision, isNull);
    });

    test('the summary is kept as Tracearr formats it', () {
      expect(streams.summary.total, 2);
      expect(streams.summary.transcodes, 1);
      expect(streams.summary.directPlays, 1);
      expect(streams.summary.totalBitrate, '11.7 Mbps');
      expect(streams.byServer, hasLength(2));
      expect(streams.byServer[0].serverName, 'Plex Living Room');
      expect(streams.byServer[0].transcodes, 1);
      expect(streams.byServer[1].totalBitrate, '3.5 Mbps');
    });

    test('an idle install keeps the em dash bitrate as data', () {
      final idle = TracearrStreams.fromJson(
        jsonFixture('tracearr/streams_idle.json'),
      );

      expect(idle.streams, isEmpty);
      expect(idle.summary.total, 0);
      expect(idle.summary.totalBitrate, '—');
      expect(idle.byServer, isEmpty);
    });

    test('a body with no summary counts its own rows', () {
      final bare = TracearrStreams.fromJson({
        'data': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      });

      expect(bare.summary.total, 2);
      expect(bare.summary.totalBitrate, isNull);
    });

    test('progress is null without a duration and clamped with one', () {
      expect(const TracearrStream(id: 'x').progress, isNull);
      final over = TracearrStream.fromJson({
        'id': 'x',
        'duration_ms': 1000,
        'progress_ms': 5000,
      });
      expect(over.progress, 1.0);
    });
  });

  group('history', () {
    final page = TracearrPage.fromJson(
      jsonFixture('tracearr/history_page.json'),
      TracearrHistoryEntry.fromJson,
    );

    test('rows carry the viewing, the person and the cursor', () {
      expect(page.items, hasLength(3));
      expect(page.nextCursor, isNotNull);
      expect(page.hasMore, isTrue);
      expect(page.pageSize, 3);
      expect(page.dropped, 0);

      final movie = page.items[0];
      expect(movie.state, TracearrStreamState.stopped);
      expect(movie.watched, isTrue);
      expect(movie.isFinished, isTrue);
      expect(movie.percentComplete, 97.3);
      expect(movie.segmentCount, 1);
      expect(movie.referenceId, isNotNull);
      expect(movie.server.type, TracearrServerType.plex);
      expect(movie.person.id, _annaId);
      expect(movie.person.serverUserId, isNotNull);
      expect(movie.person.name, 'Anna');
      expect(movie.person.avatarUrl, startsWith('/api/v1/images/proxy?'));
      expect(movie.media.ids.tmdb, 603);
      expect(movie.quality.isTranscode, isTrue);
      expect(movie.startedAt, DateTime.utc(2026, 11, 5, 20));
      expect(movie.stoppedAt, DateTime.utc(2026, 11, 5, 21, 58));

      final episode = page.items[1];
      expect(episode.watched, isFalse);
      expect(episode.media.type, TracearrMediaType.episode);
      expect(episode.device.player, 'Chrome');
      expect(episode.server.type, TracearrServerType.emby);
    });

    test('a viewing still going has no stop time', () {
      final track = page.items[2];

      expect(track.state, TracearrStreamState.playing);
      expect(track.stoppedAt, isNull);
      expect(track.isFinished, isFalse);
      expect(track.media.type, TracearrMediaType.track);
      expect(track.media.artist, 'The Quiet Docks');
      expect(track.media.album, 'Slack Water');
      expect(track.media.trackNumber, 3);
      expect(track.media.discNumber, 1);
    });

    test('the last page has no cursor', () {
      final last = TracearrPage.fromJson(
        jsonFixture('tracearr/history_last_page.json'),
        TracearrHistoryEntry.fromJson,
      );

      expect(last.items, hasLength(1));
      expect(last.nextCursor, isNull);
      expect(last.hasMore, isFalse);
    });
  });

  group('people', () {
    final users = TracearrPage.fromJson(
      jsonFixture('tracearr/users.json'),
      TracearrUser.fromJson,
    );

    test('a person has accounts on several servers', () {
      final anna = users.items[0];

      expect(anna.id, _annaId);
      expect(anna.displayName, 'Anna');
      expect(anna.accounts, hasLength(3));
      expect(anna.activeAccounts, hasLength(2));
      expect(anna.isRemoved, isFalse);
      expect(anna.accounts.map((a) => a.serverType), [
        TracearrServerType.plex,
        TracearrServerType.emby,
        TracearrServerType.jellyfin,
      ]);
      expect(
        anna.accounts[1].externalUserId,
        '4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c',
      );
      expect(anna.accounts[2].isRemoved, isTrue);
      expect(anna.plexAccountId, '1000001');
    });

    test('with no name given, the username shows', () {
      final luca = users.items[1];

      expect(luca.identityName, isNull);
      expect(luca.displayName, 'luca');
      expect(luca.email, isNull);
    });

    test('a person whose every account is removed is removed', () {
      final gone = TracearrUser.fromJson({
        'id': 'u',
        'accounts': [
          {'server_id': 's', 'removed_at': '2026-01-01T00:00:00Z'},
        ],
      });

      expect(gone.isRemoved, isTrue);
      expect(TracearrUser.fromJson({'id': 'u'}).isRemoved, isFalse);
    });

    test('stats read three windows and the genres', () {
      final stats = TracearrUserStats.fromJson(
        jsonFixture('tracearr/user_stats.json'),
      );

      expect(stats.userId, _annaId);
      expect(stats.last7.plays, 9);
      expect(stats.last7.watchTime, const Duration(hours: 6));
      expect(stats.last30.plays, 38);
      expect(stats.allTime.plays, 412);
      expect(stats.allTime.watchTime, const Duration(hours: 336));
      expect(stats.topGenres.map((g) => g.genre), [
        'Drama',
        'Fantasy',
        'Crime',
      ]);
      expect(stats.topGenres.first.plays, 120);
    });

    test('stats with no windows read as zeros', () {
      final stats = TracearrUserStats.fromJson(const <String, Object?>{});

      expect(stats.last7.plays, 0);
      expect(stats.allTime.watchTime, Duration.zero);
      expect(stats.topGenres, isEmpty);
    });
  });

  group('violations', () {
    final page = TracearrPage.fromJson(
      jsonFixture('tracearr/violations.json'),
      TracearrViolation.fromJson,
    );

    test('rows carry severity, rule, server and person', () {
      expect(page.items, hasLength(3));
      final travel = page.items[0];

      expect(travel.severity, TracearrSeverity.high);
      expect(travel.rule.name, 'Impossible travel');
      expect(travel.server.type, TracearrServerType.plex);
      expect(travel.person.name, 'anna');
      expect(travel.createdAt, DateTime.utc(2026, 11, 6, 8, 30));
      expect(travel.isAcknowledged, isFalse);
      expect(travel.sessionId, isNotNull);
      expect(travel.actions, isEmpty, reason: 'a list row carries no actions');
      expect(page.items[1].isAcknowledged, isTrue);
      expect(page.items[1].severity, TracearrSeverity.warning);
      expect(page.items[2].severity, TracearrSeverity.low);
    });

    test('impossible travel reads two places, a distance and a time', () {
      final travel = page.items[0].impossibleTravel;

      expect(travel, isNotNull);
      expect(travel!.from?.label, 'Valmora, North Reach, Nordavia');
      expect(travel.to?.city, 'Port Aster');
      expect(travel.to?.label, 'Port Aster, Eastmark, Eastmark');
      expect(travel.distanceKm, 5120.4);
      expect(travel.elapsed, const Duration(minutes: 95));
      expect(page.items[0].concurrentStreams, isNull);
    });

    test('concurrent streams read the count and the limit', () {
      final concurrent = page.items[1].concurrentStreams;

      expect(concurrent, isNotNull);
      expect(concurrent!.count, 4);
      expect(concurrent.limit, 2);
      expect(page.items[1].impossibleTravel, isNull);
    });

    test('a rule we do not know reads as nothing typed', () {
      final unknown = page.items[2];

      expect(unknown.rule.name, 'Night owl');
      expect(unknown.impossibleTravel, isNull);
      expect(unknown.concurrentStreams, isNull);
    });

    test('readers accept camel case and other time units', () {
      TracearrViolation violation(Map<String, Object?> data) =>
          TracearrViolation.fromJson({'id': 'v', 'data': data});

      final hours = violation({
        'distanceKm': 800,
        'timeDiffHours': 1.5,
        'previousLocation': {'city': 'A'},
        'currentLocation': {'city': 'B'},
      }).impossibleTravel;
      expect(hours?.elapsed, const Duration(minutes: 90));
      expect(hours?.from?.city, 'A');
      expect(hours?.to?.city, 'B');

      final flat = violation({
        'distance': 10,
        'fromCity': 'A',
        'toCity': 'B',
      }).impossibleTravel;
      expect(flat?.from?.label, 'A');
      expect(flat?.elapsed, isNull);

      final camel = violation({
        'streamCount': 3,
        'maxStreams': 1,
      }).concurrentStreams;
      expect(camel?.count, 3);
      expect(camel?.limit, 1);
    });

    test('a distance alone, or a count alone, is not a known rule', () {
      TracearrViolation violation(Map<String, Object?> data) =>
          TracearrViolation.fromJson({'id': 'v', 'data': data});

      expect(violation({'distance': 10}).impossibleTravel, isNull);
      expect(violation({'count': 3}).concurrentStreams, isNull);
      expect(
        violation({
          'from': 'a string, not a place',
          'distance': 3,
        }).impossibleTravel,
        isNull,
        reason: 'a bare string could as well be an address',
      );
      expect(violation(const {}).impossibleTravel, isNull);
      expect(
        TracearrViolation.fromJson({
          'id': 'v',
          'data': 'oops',
        }).concurrentStreams,
        isNull,
      );
    });

    test('the single read carries the actions, and a failure is a fault', () {
      final detail = TracearrViolation.fromJson(
        jsonFixtureMap('tracearr/violation_detail.json'),
      );

      expect(detail.actions, hasLength(3));
      expect(detail.actions.map((a) => a.type), [
        'notify',
        'terminate_stream',
        'notify_admins',
      ]);
      expect(detail.actions.map((a) => a.failed), [false, true, false]);
      expect(detail.actions[1].errorMessage, 'Plex Living Room did not answer');
      expect(detail.actions[2].skipped, isTrue);
      expect(detail.actions[2].skipReason, 'cooldown');
      expect(detail.hasFailedAction, isTrue);
      expect(detail.impossibleTravel, isNotNull);
    });
  });

  group('titles', () {
    test('watchers of a movie', () {
      final watchers = TracearrMediaWatchers.fromJson(
        jsonFixture('tracearr/watchers_movie.json'),
      );

      expect(watchers.mediaType, TracearrMediaType.movie);
      expect(watchers.window, TracearrWindow.allTime);
      expect(watchers.watchers, hasLength(2));
      final anna = watchers.watchers[0];
      expect(anna.displayName, 'Anna');
      expect(anna.plays, 2);
      expect(anna.completionPct, 97.3);
      expect(anna.lastWatchedDay, DateTime(2026, 11, 5));
      expect(anna.distinctEpisodesWatched, isNull);
      expect(anna.watchTime, const Duration(milliseconds: 14160000));
      expect(watchers.watchers[1].displayName, 'luca');
      expect(watchers.lastWatchedDay, DateTime(2026, 11, 5));
    });

    test('watchers of a series count distinct episodes', () {
      final watchers = TracearrMediaWatchers.fromJson(
        jsonFixture('tracearr/watchers_series.json'),
      );

      expect(watchers.mediaType, TracearrMediaType.show);
      expect(watchers.window, TracearrWindow.last30);
      expect(watchers.watchers.single.distinctEpisodesWatched, 7);
      expect(watchers.watchers.single.plays, 9);
    });

    test('nobody watching is an empty list, not an error', () {
      final none = TracearrMediaWatchers.fromJson({
        'media_id': 'm',
        'media_type': 'movie',
        'window': 'all_time',
        'watchers': <Object?>[],
      });

      expect(none.watchers, isEmpty);
      expect(none.lastWatchedDay, isNull);
    });

    test('references are built the way the path wants them', () {
      expect(TracearrMediaRef.movieTmdb(603).value, 'movie:tmdb:603');
      expect(TracearrMediaRef.showTvdb(81189).value, 'show:tvdb:81189');
      expect(TracearrMediaRef.showTmdb(1396).value, 'show:tmdb:1396');
      expect(const TracearrMediaRef.id('abc').value, 'abc');
      expect(const TracearrMediaRef.raw('x:y').value, 'x:y');
    });

    test('top media and today', () {
      final top = TracearrPage.fromJson(
        jsonFixture('tracearr/top_media.json'),
        TracearrTopMedia.fromJson,
      );
      final today = TracearrToday.fromJson(jsonFixture('tracearr/today.json'));

      expect(top.items.single.title, 'The Lantern Keeper');
      expect(top.items.single.plays, 3);
      expect(top.items.single.uniqueUsers, 2);
      expect(top.items.single.tmdbId, 603);
      expect(today.todayPlays, 14);
      expect(today.activeUsersToday, 4);
      expect(today.alertsLast24h, 3);
      expect(today.watchTimeHours, 11.5);
      expect(today.watchTime, const Duration(hours: 11, minutes: 30));
    });
  });

  group('unknown values never crash', () {
    test('an unseen enum word is an explicit unknown', () {
      final stream = TracearrStream.fromJson({
        'id': 's',
        'server_type': 'kodi',
        'state': 'buffering',
        'media_type': 'podcast',
        'video_decision': 'upscale',
        'audio_decision': 'directplay',
      });

      expect(stream.server.type, TracearrServerType.unknown);
      expect(stream.state, TracearrStreamState.unknown);
      expect(stream.media.type, TracearrMediaType.unknown);
      expect(stream.quality.videoDecision, TracearrDecision.unknown);
      expect(stream.quality.audioDecision, TracearrDecision.directPlay);
    });

    test('an absent decision stays null, an unseen one is unknown', () {
      expect(TracearrDecision.fromWire(null), isNull);
      expect(TracearrDecision.fromWire('copy'), TracearrDecision.copy);
      expect(TracearrServerReason.fromWire(null), isNull);
      expect(
        TracearrServerReason.fromWire('tls'),
        TracearrServerReason.unknown,
      );
      expect(
        TracearrServerStatus.fromWire('maintenance'),
        TracearrServerStatus.unknown,
      );
      expect(TracearrWindow.fromWire('last_90'), TracearrWindow.unknown);
      expect(TracearrWindow.fromWire('last_7'), TracearrWindow.last7);
    });

    test('an unseen severity ranks below every known one', () {
      final violation = TracearrViolation.fromJson({
        'id': 'v',
        'severity': 'critical',
      });

      expect(violation.severity, TracearrSeverity.unknown);
      expect(violation.severity.wire, isNull);
      expect(TracearrSeverity.values.where((s) => s.rank < 1), [
        TracearrSeverity.unknown,
      ]);
      expect(
        TracearrSeverity.high.rank,
        greaterThan(TracearrSeverity.low.rank),
      );
    });
  });

  group('bad rows', () {
    test('a row that cannot be read is dropped, not the page', () {
      final page = TracearrPage.fromJson({
        'data': [
          {'id': 'good-1'},
          'not an object',
          {'title': 'no id at all'},
          {'id': 42},
          {'id': 'good-2', 'progress_ms': 'soon', 'media_title': 7},
          null,
        ],
        'meta': {'nextCursor': 'c2', 'pageSize': 6},
      }, TracearrStream.fromJson);

      expect(page.items.map((s) => s.id), ['good-1', 'good-2']);
      expect(page.dropped, 4);
      expect(page.nextCursor, 'c2', reason: 'the cursor still moves on');
      final odd = page.items[1];
      expect(odd.progressMs, 0);
      expect(odd.media.title, '');
    });

    test('a page of nothing but bad rows is not an empty page', () {
      final page = TracearrPage.fromJson({
        'data': ['x', 'y'],
        'meta': {'nextCursor': 'next', 'pageSize': 2},
      }, TracearrStream.fromJson);

      expect(page.items, isEmpty);
      expect(page.dropped, 2);
      expect(page.hasMore, isTrue);
    });

    test('a page with no data or no meta reads empty', () {
      final page = TracearrPage.fromJson(
        const <String, Object?>{},
        TracearrStream.fromJson,
      );

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.pageSize, isNull);
    });

    test('a page that is not an object is a wrong answer', () {
      expect(
        () => TracearrPage.fromJson(<Object?>[1], TracearrStream.fromJson),
        throwsFormatException,
      );
      expect(
        () => TracearrPage.fromJson('<html>', TracearrStream.fromJson),
        throwsFormatException,
      );
    });

    test('every field is optional but the id', () {
      final stream = TracearrStream.fromJson({'id': 'only'});
      final entry = TracearrHistoryEntry.fromJson({'id': 'only'});
      final violation = TracearrViolation.fromJson({'id': 'only'});

      expect(stream.state, TracearrStreamState.unknown);
      expect(stream.startedAt, isNull);
      expect(stream.person.name, '');
      expect(stream.quality.source.videoCodec, isNull);
      expect(entry.watched, isFalse);
      expect(entry.segmentCount, 1);
      expect(entry.person.id, isNull);
      expect(violation.severity, TracearrSeverity.unknown);
      expect(violation.actions, isEmpty);
      expect(violation.server.id, '');
    });

    test('null where an object is expected reads as absent', () {
      final stream = TracearrStream.fromJson({
        'id': 's',
        'source_video_details': null,
        'transcode_info': null,
        'subtitle_info': 'none',
        'genres': null,
      });

      expect(stream.quality.transcode, isNull);
      expect(stream.quality.subtitle, isNull);
      expect(stream.media.genres, isEmpty);
    });

    test('numbers arrive as integers or as whole doubles', () {
      final stream = TracearrStream.fromJson({
        'id': 's',
        'progress_ms': 1500.0,
        'duration_ms': 3000,
        'bitrate': 8200.0,
        'stream_video_details': {'width': 1920.0, 'bitrate': 7999.6},
      });

      expect(stream.progressMs, 1500);
      expect(stream.progress, 0.5);
      expect(stream.quality.bitrate, 8200);
      expect(stream.quality.output.width, 1920);
      expect(stream.quality.output.videoBitrate, 8000);
    });
  });

  group('a stream moved by progress', () {
    test('keeps everything but the moving parts', () {
      final original = TracearrStreams.fromJson(
        jsonFixture('tracearr/streams.json'),
      ).streams[1];

      final moved = original.withProgress(
        state: TracearrStreamState.playing,
        progressMs: 915000,
        bitrate: 3600,
      );

      expect(moved.id, original.id);
      expect(moved.state, TracearrStreamState.playing);
      expect(moved.progressMs, 915000);
      expect(moved.quality.bitrate, 3600);
      expect(moved.quality.resolution, original.quality.resolution);
      expect(moved.media.title, original.media.title);
      expect(moved.person, same(original.person));
    });
  });

  group('versions', () {
    test('the v of Tracearr is accepted and not required', () {
      expect(
        TracearrVersion.tryParse('v3.1.4'),
        const TracearrVersion(3, 1, 4),
      );
      expect(TracearrVersion.tryParse('3.1.4'), const TracearrVersion(3, 1, 4));
      expect(
        TracearrVersion.tryParse(' V3.1.4 '),
        const TracearrVersion(3, 1, 4),
      );
      expect(TracearrVersion.tryParse('v3.1'), const TracearrVersion(3, 1, 0));
    });

    test('anything else is null', () {
      for (final bad in ['', 'latest', 'v3', 'v3.x.1', '3.1.4.5', null]) {
        expect(TracearrVersion.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('they compare by number, not by text', () {
      TracearrVersion v(String text) => TracearrVersion.tryParse(text)!;

      expect(v('v3.10.0') > v('v3.9.0'), isTrue);
      expect(v('v3.1.4') >= v('v3.1.4'), isTrue);
      expect(v('v3.1.4') < v('v3.2.0'), isTrue);
      expect(v('v4.0.0') > v('v3.99.99'), isTrue);
      expect(v('v3.1.4') == v('3.1.4'), isTrue);
      expect(v('v3.1.4').hashCode, v('3.1.4').hashCode);
      expect([v('v3.10.0'), v('v3.2.0'), v('v3.9.1')]..sort(), [
        v('v3.2.0'),
        v('v3.9.1'),
        v('v3.10.0'),
      ]);
    });

    test('a pre-release sorts below its release', () {
      TracearrVersion v(String text) => TracearrVersion.tryParse(text)!;

      expect(v('v3.2.0-beta.1').isPreRelease, isTrue);
      expect(v('v3.2.0-beta.1') < v('v3.2.0'), isTrue);
      expect(v('v3.2.0-beta.1') > v('v3.1.9'), isTrue);
      expect(v('v3.2.0-beta.1') < v('v3.2.0-beta.2'), isTrue);
    });

    test('it prints without the v, for a remedy', () {
      expect(const TracearrVersion(3, 1, 4).toString(), '3.1.4');
      expect(TracearrVersion.tryParse('v3.2.0-rc.1').toString(), '3.2.0-rc.1');
    });
  });

  group('image addresses', () {
    final home = Uri.parse('http://192.168.1.20:3000');

    test('a relative path joins the base the caller gives', () {
      final uri = resolveTracearrImage(
        '/api/v1/images/proxy?server=abc&url=%2Fitems%2F1&width=300',
        home,
      );

      expect(uri.toString(), startsWith('http://192.168.1.20:3000/api/v1/'));
      expect(uri!.path, '/api/v1/images/proxy');
      expect(uri.queryParameters, {
        'server': 'abc',
        'url': '/items/1',
        'width': '300',
      });
    });

    test('the base path survives, for a Tracearr behind a prefix', () {
      final uri = resolveTracearrImage(
        '/api/v1/images/proxy?x=1',
        Uri.parse('https://media.example.test/tracearr/'),
      );

      expect(
        uri.toString(),
        'https://media.example.test/tracearr/api/v1/images/proxy?x=1',
      );
    });

    test('the base query is not carried over', () {
      final uri = resolveTracearrImage(
        '/img',
        Uri.parse('https://t.example.test/?token=secret'),
      );

      expect(uri.toString(), 'https://t.example.test/img');
    });

    test('an absolute or empty address is null', () {
      expect(
        resolveTracearrImage('https://elsewhere.test/a.png', home),
        isNull,
      );
      expect(resolveTracearrImage('//elsewhere.test/a.png', home), isNull);
      expect(resolveTracearrImage('', home), isNull);
      expect(resolveTracearrImage('   ', home), isNull);
      expect(resolveTracearrImage(null, home), isNull);
    });

    test('a path with no leading slash still joins', () {
      expect(
        resolveTracearrImage('api/v1/images/proxy', home).toString(),
        'http://192.168.1.20:3000/api/v1/images/proxy',
      );
    });
  });

  group('json reads', () {
    test('rows skip what is not an object', () {
      final read = tracearrRows<String>([
        {'a': 'x'},
        1,
        'two',
        null,
      ], (json) => json.requiredText('a'));

      expect(read.rows, ['x']);
      expect(read.dropped, 3);
    });

    test('rows of a non-list are none', () {
      expect(tracearrRows<String>('x', (json) => '').rows, isEmpty);
      expect(tracearrRows<String>(null, (json) => '').dropped, 0);
    });

    test('a map with odd keys is not an object', () {
      expect(asTracearrJson({1: 'a'}), isNull);
      expect(asTracearrJson({'a': 1}), {'a': 1});
      expect(asTracearrJson(<dynamic, dynamic>{'a': 1}), {'a': 1});
    });

    test('blank strings and non-finite numbers read as absent', () {
      final json = <String, Object?>{
        'a': '   ',
        'b': double.nan,
        'c': double.infinity,
        'd': 'x',
      };

      expect(json.text('a'), isNull);
      expect(json.number('b'), isNull);
      expect(json.integer('c'), isNull);
      expect(json.text('d'), 'x');
      expect(json.time('d'), isNull);
    });
  });
}
