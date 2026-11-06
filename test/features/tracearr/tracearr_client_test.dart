import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_image.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';

import '../../test_helpers/capturing_http_adapter.dart';
import '../../test_helpers/fixtures.dart';

const _key = 'trr_pub_exampleexampleexampleexampleexampleexample1';

/// A client whose socket is stubbed but whose headers, paths and query strings
/// are entirely its own.
TracearrClient _client(
  HttpClientAdapter adapter, {
  String baseUrl = 'https://tracearr.test',
  String apiKey = _key,
  Map<String, String> accessHeaders = const {},
}) {
  final client = TracearrClient(
    baseUrl: baseUrl,
    apiKey: apiKey,
    accessHeaders: accessHeaders,
  );
  client.dio.httpClientAdapter = adapter;
  addTearDown(client.close);
  return client;
}

String? _header(CapturingHttpAdapter adapter, String name) {
  for (final entry in (adapter.lastHeaders ?? const {}).entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value?.toString();
    }
  }
  return null;
}

/// Answers an event stream in the chunks it is given, with the status and
/// content type asked for, and records the request.
class _EventStreamAdapter implements HttpClientAdapter {
  _EventStreamAdapter(
    this.chunks, {
    this.contentType = 'text/event-stream',
    this.statusCode = 200,
  });

  final List<List<int>> chunks;
  final String contentType;
  final int statusCode;
  RequestOptions? lastRequest;
  bool cancelled = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    final controller = StreamController<Uint8List>(
      onCancel: () => cancelled = true,
    );
    scheduleMicrotask(() async {
      for (final chunk in chunks) {
        controller.add(Uint8List.fromList(chunk));
        await Future<void>.delayed(Duration.zero);
      }
      await controller.close();
    });
    return ResponseBody(
      controller.stream,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }
}

void main() {
  group('credentials', () {
    test('the key goes as a Bearer token and nothing else', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/servers.json'),
      );

      await _client(adapter).getServers();

      expect(_header(adapter, 'authorization'), 'Bearer $_key');
      expect(_header(adapter, 'x-api-key'), isNull);
      expect(_header(adapter, 'x-emby-token'), isNull);
    });

    test(
      'the key is trimmed, so a pasted newline does not poison it',
      () async {
        final adapter = CapturingHttpAdapter(response: const {'data': []});

        await _client(adapter, apiKey: '  $_key\n').getServers();

        expect(_header(adapter, 'authorization'), 'Bearer $_key');
      },
    );

    test('the access headers of the connection go along', () async {
      final adapter = CapturingHttpAdapter(response: const {'data': []});

      await _client(
        adapter,
        accessHeaders: const {
          'CF-Access-Client-Id': 'id.example',
          'CF-Access-Client-Secret': 'secret.example',
        },
      ).getServers();

      expect(_header(adapter, 'cf-access-client-id'), 'id.example');
      expect(_header(adapter, 'cf-access-client-secret'), 'secret.example');
      expect(_header(adapter, 'authorization'), 'Bearer $_key');
    });

    test('an Authorization the access carries never replaces the key', () async {
      // The connection must not offer a proxy password for Tracearr, but if one
      // slipped through, the service's own header wins and the key survives.
      final adapter = CapturingHttpAdapter(response: const {'data': []});

      await _client(
        adapter,
        accessHeaders: const {'Authorization': 'Basic cHJveHk6cHc='},
      ).getServers();

      expect(_header(adapter, 'authorization'), 'Bearer $_key');
    });

    test('the base address keeps its prefix and gets a scheme', () async {
      final adapter = CapturingHttpAdapter(response: const {'data': []});
      final client = _client(adapter, baseUrl: 'media.example.test/tracearr/');

      await client.getServers();

      expect(
        adapter.lastUri.toString(),
        'https://media.example.test/tracearr/api/v2/public/servers',
      );
      expect(client.baseUri.toString(), 'https://media.example.test/tracearr');
      expect(
        resolveTracearrImage(
          '/api/v1/images/proxy?x=1',
          client.baseUri,
        ).toString(),
        'https://media.example.test/tracearr/api/v1/images/proxy?x=1',
      );
    });
  });

  group('reads', () {
    test('health is v1 and names the version', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/health.json'),
      );

      final health = await _client(adapter).getHealth();

      expect(adapter.lastUri!.path, '/api/v1/public/health');
      expect(health.version, 'v3.1.4');
      expect(health.servers, hasLength(3));
    });

    test('servers are v2', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/servers.json'),
      );

      final servers = await _client(adapter).getServers();

      expect(adapter.lastUri!.path, '/api/v2/public/servers');
      expect(adapter.lastRequest!.method, 'GET');
      expect(servers.servers, hasLength(3));
    });

    test('streams ask for the summary, and for a server when told', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/streams.json'),
      );
      final client = _client(adapter);

      final streams = await client.getStreams();
      expect(adapter.lastUri!.path, '/api/v2/public/streams');
      expect(adapter.lastUri!.queryParameters, {'summary': 'true'});
      expect(streams.streams, hasLength(2));
      expect(streams.summary.total, 2);

      await client.getStreams(serverId: 'srv-1');
      expect(adapter.lastUri!.queryParameters, {
        'summary': 'true',
        'server_id': 'srv-1',
      });
    });

    test('today is v1 with camel-case parameters', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/today.json'),
      );

      final today = await _client(
        adapter,
      ).getToday(serverId: 'srv-1', timezone: 'Europe/Rome');

      expect(adapter.lastUri!.path, '/api/v1/public/stats/today');
      expect(adapter.lastUri!.queryParameters, {
        'serverId': 'srv-1',
        'timezone': 'Europe/Rome',
      });
      expect(today.todayPlays, 14);
    });

    test('history pages by cursor and clamps the page size', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/history_page.json'),
      );
      final client = _client(adapter);

      final first = await client.getHistory();
      expect(adapter.lastUri!.path, '/api/v2/public/history');
      expect(adapter.lastUri!.queryParameters, {'pageSize': '25'});
      expect(first.items, hasLength(3));
      expect(first.nextCursor, isNotNull);

      await client.getHistory(cursor: first.nextCursor, pageSize: 500);
      expect(adapter.lastUri!.queryParameters, {
        'cursor': first.nextCursor,
        'pageSize': '100',
      });

      await client.getHistory(pageSize: 0);
      expect(adapter.lastUri!.queryParameters['pageSize'], '1');
    });

    test('history filters are the server\'s to apply', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/history_page.json'),
      );

      await _client(adapter).getHistory(
        filter: TracearrHistoryFilter(
          userId: 'user-1',
          serverId: 'srv-1',
          mediaType: TracearrHistoryMediaType.episode,
          watched: true,
          since: DateTime.utc(2026, 10, 1),
          until: DateTime.utc(2026, 11, 1, 12, 30),
        ),
      );

      expect(adapter.lastUri!.queryParameters, {
        'pageSize': '25',
        'user_id': 'user-1',
        'server_id': 'srv-1',
        'media_type': 'episode',
        'watched': 'true',
        'since': '2026-10-01T00:00:00.000Z',
        'until': '2026-11-01T12:30:00.000Z',
      });
    });

    test('violations: the unseen ones, by severity, since a day', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/violations.json'),
      );

      final page = await _client(adapter).getViolations(
        filter: TracearrViolationFilter.unseen(
          severity: TracearrSeverity.high,
          since: DateTime.utc(2026, 11, 5),
        ),
      );

      expect(adapter.lastUri!.path, '/api/v2/public/violations');
      expect(adapter.lastUri!.queryParameters, {
        'pageSize': '25',
        'severity': 'high',
        'acknowledged': 'false',
        'since': '2026-11-05T00:00:00.000Z',
      });
      expect(page.items, hasLength(3));
      expect(page.items.first.impossibleTravel, isNotNull);
    });

    test('violations with no filter send no filter', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/violations.json'),
      );

      await _client(adapter).getViolations(cursor: 'c1', pageSize: 10);

      expect(adapter.lastUri!.queryParameters, {
        'cursor': 'c1',
        'pageSize': '10',
      });
    });

    test('one violation carries its actions', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/violation_detail.json'),
      );

      final violation = await _client(adapter).getViolation('v-1');

      expect(adapter.lastUri!.path, '/api/v2/public/violations/v-1');
      expect(violation!.actions, hasLength(3));
      expect(violation.hasFailedAction, isTrue);
    });

    test('users page by cursor and leave the removed out by default', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/users.json'),
      );
      final client = _client(adapter);

      final page = await client.getUsers();
      expect(adapter.lastUri!.path, '/api/v2/public/users');
      expect(adapter.lastUri!.queryParameters, {'pageSize': '25'});
      expect(page.items, hasLength(2));

      await client.getUsers(includeRemoved: true, cursor: 'c2');
      expect(adapter.lastUri!.queryParameters, {
        'cursor': 'c2',
        'pageSize': '25',
        'include_removed': 'true',
      });
    });

    test('a person and their stats', () async {
      final adapter = CapturingHttpAdapter(
        byPath: {
          '/stats': jsonFixture('tracearr/user_stats.json'),
          '/users/': jsonFixture('tracearr/users.json')['data'][0],
        },
      );
      final client = _client(adapter);

      final stats = await client.getUserStats('u-1');
      expect(adapter.lastUri!.path, '/api/v2/public/users/u-1/stats');
      expect(stats!.allTime.plays, 412);

      final user = await client.getUser('u-1');
      expect(adapter.lastUri!.path, '/api/v2/public/users/u-1');
      expect(user!.accounts, hasLength(3));
    });

    test('watchers: the reference goes in the path with its colons', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/watchers_movie.json'),
      );

      final watchers = await _client(adapter).getWatchers(
        TracearrMediaRef.movieTmdb(603),
        window: TracearrWindow.last7,
        serverId: 'srv-1',
      );

      expect(
        adapter.lastUri!.path,
        '/api/v2/public/media/movie:tmdb:603/watchers',
      );
      expect(adapter.lastUri!.queryParameters, {
        'window': 'last_7',
        'server_id': 'srv-1',
      });
      expect(watchers!.watchers, hasLength(2));
    });

    test('a reference with odd characters is encoded as a segment', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/watchers_movie.json'),
      );

      await _client(
        adapter,
      ).getWatchers(const TracearrMediaRef.raw('movie/../x y:1'));

      expect(adapter.lastUri!.path, contains('/media/movie%2F..%2Fx%20y:1/'));
    });

    test('top media wants a media type and stays in range', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixture('tracearr/top_media.json'),
      );

      final page = await _client(adapter).getTopMedia(
        mediaType: TracearrTopMediaType.movie,
        days: 7,
        sort: TracearrTopSort.watchTime,
        pageSize: 5000,
      );

      expect(adapter.lastUri!.path, '/api/v2/public/top-media');
      expect(adapter.lastUri!.queryParameters, {
        'media_type': 'movie',
        'days': '7',
        'sort': 'watch_time',
        'pageSize': '1000',
      });
      expect(page.items.single.title, 'The Lantern Keeper');
    });
  });

  group('media type filters', () {
    test('history sends every type it accepts, and none else exists', () async {
      expect(TracearrHistoryMediaType.values.map((t) => t.name), [
        'movie',
        'episode',
        'track',
        'live',
        'photo',
        'trailer',
        'unknown',
      ]);
      for (final type in TracearrHistoryMediaType.values) {
        final adapter = CapturingHttpAdapter(response: const {'data': []});

        await _client(
          adapter,
        ).getHistory(filter: TracearrHistoryFilter(mediaType: type));

        expect(adapter.lastUri!.queryParameters['media_type'], type.name);
      }
    });

    test('top media accepts exactly movie and show', () async {
      expect(TracearrTopMediaType.values.map((t) => t.name), ['movie', 'show']);
      final adapter = CapturingHttpAdapter(response: const {'data': []});

      await _client(adapter).getTopMedia(mediaType: TracearrTopMediaType.show);

      expect(adapter.lastUri!.queryParameters['media_type'], 'show');
    });
  });

  group('answers that are not found, or not Tracearr', () {
    test('a 404 on a single item reads as null', () async {
      final adapter = CapturingHttpAdapter(
        statusCode: 404,
        response: const {
          'statusCode': 404,
          'error': 'NotFoundError',
          'message': 'Media not found',
        },
      );
      final client = _client(adapter);

      expect(await client.getUser('x'), isNull);
      expect(await client.getUserStats('x'), isNull);
      expect(await client.getViolation('x'), isNull);
      expect(await client.getWatchers(TracearrMediaRef.movieTmdb(1)), isNull);
    });

    test('any other failure on a single item is not swallowed', () async {
      for (final status in [401, 403, 500, 502]) {
        final adapter = CapturingHttpAdapter(
          statusCode: status,
          response: const {'error': 'no'},
        );

        await expectLater(
          _client(adapter).getViolation('x'),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              status,
            ),
          ),
          reason: '$status',
        );
      }
    });

    test('a refused key throws on a list', () async {
      final adapter = CapturingHttpAdapter(
        statusCode: 401,
        response: const {
          'statusCode': 401,
          'error': 'UnauthorizedError',
          'message': 'Missing or invalid Authorization header',
        },
      );

      await expectLater(
        _client(adapter).getStreams(),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            401,
          ),
        ),
      );
    });

    test(
      'a body that is not what the route answers is a wrong answer',
      () async {
        final adapter = CapturingHttpAdapter(response: const [1, 2, 3]);
        final client = _client(adapter);

        await expectLater(client.getServers(), throwsFormatException);
        await expectLater(client.getHealth(), throwsFormatException);
        await expectLater(client.getHistory(), throwsFormatException);
        await expectLater(client.getStreams(), throwsFormatException);
      },
    );

    test('a page with a bad row still answers', () async {
      final body = jsonFixtureMap('tracearr/history_page.json');
      (body['data'] as List).insert(1, 'garbage');
      (body['data'] as List).insert(0, {'no': 'id'});
      final adapter = CapturingHttpAdapter(response: body);

      final page = await _client(adapter).getHistory();

      expect(page.items, hasLength(3));
      expect(page.dropped, 2);
      expect(page.nextCursor, isNotNull);
    });
  });

  group('big pages', () {
    test(
      'a page of many rows maps off the UI isolate and reads whole',
      () async {
        final streams = jsonFixtureMap('tracearr/streams.json');
        final rows = (streams['data'] as List).cast<Map<String, dynamic>>();
        final big = {
          ...streams,
          'data': [
            for (var i = 0; i < 160; i++) {...rows[i % 2], 'id': 'stream-$i'},
          ],
        };
        expect(jsonEncode(big).length, greaterThan(50 * 1024));
        final adapter = CapturingHttpAdapter(response: big);

        final result = await _client(adapter).getStreams();

        expect(result.streams, hasLength(160));
        expect(result.streams.last.id, 'stream-159');
        expect(result.streams[1].media.showTitle, 'Harbor Lights');
      },
    );
  });

  group('terminate', () {
    test('posts to v1 with an empty object when there is no reason', () async {
      final adapter = CapturingHttpAdapter(
        response: const {
          'success': true,
          'terminationLogId': 'log-1',
          'message': 'Stream terminated',
        },
      );

      final result = await _client(adapter).terminate('stream-1');

      expect(adapter.lastRequest!.method, 'POST');
      expect(
        adapter.lastUri!.path,
        '/api/v1/public/streams/stream-1/terminate',
      );
      expect(adapter.lastBody, <String, Object?>{});
      expect(result, isA<TracearrTerminated>());
      expect((result as TracearrTerminated).logId, 'log-1');
      expect(result.message, 'Stream terminated');
    });

    test('carries the message for the person watching', () async {
      final adapter = CapturingHttpAdapter(
        response: const {'success': true, 'terminationLogId': 'l'},
      );

      await _client(
        adapter,
      ).terminate('stream-1', reason: '  Bedtime, please  ');

      expect(adapter.lastBody, {'reason': 'Bedtime, please'});
    });

    test('a blank reason is no reason', () async {
      final adapter = CapturingHttpAdapter(response: const {'success': true});

      await _client(adapter).terminate('stream-1', reason: '   ');

      expect(adapter.lastBody, <String, Object?>{});
    });

    test('a missing route is a 405, or Fastify unmatched-route 404', () async {
      final bodies = <int, Object?>{
        405: const {'message': 'Method Not Allowed'},
        // Measured on a real 3.1.4 for a route that does not exist.
        404: const {'error': 'Not Found'},
      };
      for (final MapEntry(:key, :value) in bodies.entries) {
        final adapter = CapturingHttpAdapter(statusCode: key, response: value);

        final result = await _client(adapter).terminate('x');

        expect(result, isA<TracearrTerminateRouteAbsent>(), reason: '$key');
      }
    });

    test('a session that is gone is not an absent route', () async {
      // Measured: the route exists and says the stream is not running.
      final adapter = CapturingHttpAdapter(
        statusCode: 404,
        response: const {
          'statusCode': 404,
          'error': 'NotFoundError',
          'message': 'Session not found',
        },
      );

      final result = await _client(adapter).terminate('x');

      expect(result, isA<TracearrTerminateStreamGone>());
    });

    test('any other 404 is a failure, never an absent route', () async {
      for (final body in <Object?>[
        const {'statusCode': 404, 'error': 'NotFoundError', 'message': 'Gone'},
        const {'message': 'Route POST:/x not found'},
        const <String, Object?>{},
      ]) {
        final adapter = CapturingHttpAdapter(statusCode: 404, response: body);

        final result = await _client(adapter).terminate('x');

        expect(result, isA<TracearrTerminateFailed>(), reason: '$body');
        expect((result as TracearrTerminateFailed).statusCode, 404);
      }
    });

    test('a refusal by the server is a failure with its message', () async {
      final adapter = CapturingHttpAdapter(
        statusCode: 500,
        response: const {
          'success': false,
          'error': 'Plex Living Room did not answer',
          'terminationLogId': 'log-2',
        },
      );

      final result = await _client(adapter).terminate('x');

      expect(result, isA<TracearrTerminateFailed>());
      final failed = result as TracearrTerminateFailed;
      expect(failed.statusCode, 500);
      expect(failed.message, 'Plex Living Room did not answer');
    });

    test('a refused key is a failure, not an absent route', () async {
      final adapter = CapturingHttpAdapter(
        statusCode: 401,
        response: const {'message': 'Missing or invalid Authorization header'},
      );

      final result = await _client(adapter).terminate('x');

      expect(result, isA<TracearrTerminateFailed>());
      expect((result as TracearrTerminateFailed).statusCode, 401);
    });

    test('a success false in a 200 is a failure', () async {
      final adapter = CapturingHttpAdapter(
        response: const {'success': false, 'error': 'Nothing to stop'},
      );

      final result = await _client(adapter).terminate('x');

      expect(result, isA<TracearrTerminateFailed>());
      expect((result as TracearrTerminateFailed).message, 'Nothing to stop');
    });

    test('the id is encoded as one path segment', () async {
      final adapter = CapturingHttpAdapter(response: const {'success': true});

      await _client(adapter).terminate('a/b');

      expect(adapter.lastUri!.path, '/api/v1/public/streams/a%2Fb/terminate');
    });
  });

  group('live events', () {
    List<int> bytes(String text) => utf8.encode(text);

    test('opens the stream with the right headers and path', () async {
      final adapter = _EventStreamAdapter([bytes('data: {}\n\n')]);

      await _client(adapter)
          .events(
            types: ['stream.started', 'violation.created'],
            serverId: 's1',
          )
          .toList();

      final request = adapter.lastRequest!;
      expect(request.path, contains('/api/v2/public/events'));
      expect(request.uri.queryParameters, {
        'types': 'stream.started,violation.created',
        'server_id': 's1',
      });
      expect(request.responseType, ResponseType.stream);
      expect(request.receiveTimeout, Duration.zero);
      expect(request.headers['Accept'], 'text/event-stream');
      expect(request.headers['Authorization'], 'Bearer $_key');
    });

    test('yields typed events across chunks cut anywhere', () async {
      final text = StringBuffer()
        ..write('retry: 4000\n\n')
        ..write(
          'event: ready\ndata: {"type":"ready","at":"2026-11-06T10:00:00Z","data":{}}\n\n',
        )
        ..write(': keep-alive\n\n')
        ..write('event: nothing.we.know\ndata: {}\n\n')
        ..write(
          'event: stream.progress\ndata: {"type":"stream.progress","data":{"id":"s","progress_ms":9}}\n\n',
        );
      final all = bytes(text.toString());
      final chunks = [
        for (var i = 0; i < all.length; i += 7)
          all.sublist(i, i + 7 > all.length ? all.length : i + 7),
      ];
      final adapter = _EventStreamAdapter(chunks);
      final retries = <Duration>[];

      final events = await _client(
        adapter,
      ).events(onRetry: retries.add).toList();

      expect(events, hasLength(2));
      expect(events[0], isA<TracearrReady>());
      expect(events[1], isA<TracearrStreamProgress>());
      expect((events[1] as TracearrStreamProgress).progressMs, 9);
      expect(retries, [const Duration(seconds: 4)]);
    });

    test('with no filters it sends no query', () async {
      final adapter = _EventStreamAdapter(const []);

      await _client(adapter).events().toList();

      expect(adapter.lastRequest!.uri.queryParameters, isEmpty);
    });

    test(
      'a sign-in page answering 200 is a gateway, as on JSON routes',
      () async {
        final adapter = _EventStreamAdapter([
          bytes(
            '<html><body><form method="post">'
            '<input type="password" name="pw"></form></body></html>',
          ),
        ], contentType: 'text/html; charset=utf-8');

        await expectLater(
          _client(adapter).events().toList(),
          throwsA(
            isA<DioException>().having(
              (e) => e.error,
              'error',
              isA<AccessGatewayAnswer>().having(
                (a) => a.kind,
                'kind',
                AccessGatewayKind.signInPage,
              ),
            ),
          ),
        );
        await pumpEventQueue();
        expect(adapter.cancelled, isTrue);
      },
    );

    test(
      'any other answer that is not an event stream is unexpected',
      () async {
        final adapter = _EventStreamAdapter([
          bytes('<html>Welcome</html>'),
        ], contentType: 'text/html');

        await expectLater(
          _client(adapter).events().toList(),
          throwsA(
            isA<DioException>().having(
              (e) => e.error,
              'error',
              isA<UnexpectedAnswer>().having((a) => a.status, 'status', 200),
            ),
          ),
        );
      },
    );

    test('the probe of a page is bounded to 8 KB', () async {
      final page = '<html>${'x' * 40000}<input type="password"></html>';
      final adapter = _EventStreamAdapter([
        for (var i = 0; i < page.length; i += 1000)
          bytes(
            page.substring(i, i + 1000 > page.length ? page.length : i + 1000),
          ),
      ], contentType: 'text/html');

      // The password field sits past the 8 KB read, so it is not recognised
      // as a sign-in page: proof that the read stopped where it said.
      final failure = await _client(adapter)
          .events()
          .toList()
          .then<DioException?>((_) => null, onError: (e) => e as DioException);

      expect(failure!.error, isA<UnexpectedAnswer>());
      final read = (failure.response!.data as String).length;
      expect(read, greaterThanOrEqualTo(kTracearrEventsProbeBytes));
      expect(read, lessThan(kTracearrEventsProbeBytes + 1000));
    });

    test('a refusal throws before any event', () async {
      final adapter = _EventStreamAdapter(
        [bytes('{"error":"no"}')],
        contentType: 'application/json',
        statusCode: 401,
      );

      await expectLater(
        _client(adapter).events().toList(),
        throwsA(isA<DioException>()),
      );
    });

    test('cancelling the subscription closes the connection', () async {
      final adapter = _EventStreamAdapter([
        bytes('data: {"type":"ready","data":{}}\n\n'),
        bytes('data: {"type":"ready","data":{}}\n\n'),
        bytes('data: {"type":"ready","data":{}}\n\n'),
      ]);

      final first = await _client(adapter).events().first;

      expect(first, isA<TracearrReady>());
      await pumpEventQueue();
      expect(adapter.cancelled, isTrue);
    });

    test('the stream ends when the connection does', () async {
      final adapter = _EventStreamAdapter([
        bytes('event: ready\ndata: {"type":"ready","data":{}}\n\n'),
      ]);

      final events = await _client(adapter).events().toList();

      expect(events, hasLength(1));
    });
  });
}
