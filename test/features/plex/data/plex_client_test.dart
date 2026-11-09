import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/domain/models/plex_item_mapper.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/domain/models/plex_transcode_session.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_library_page.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';

const _kUrl = 'https://plex.local:32400';
const _kToken = 'sX7pQ2mK9vTb3nR8wLdY';
const _kClientId = 'f1e2d3c4-b5a6-4798-8a9b-0c1d2e3f4a5b';

PlexClient _client(
  HttpClientAdapter adapter, {
  String token = _kToken,
  String url = _kUrl,
  String clientId = _kClientId,
}) {
  final client = PlexClient(
    url: url,
    token: token,
    clientIdentifier: clientId,
    // Pinned so the assertion on `X-Plex-Platform` does not depend on which
    // machine the suite runs on.
    platform: 'macOS',
  );
  client.api.dio.httpClientAdapter = adapter;
  addTearDown(client.close);
  return client;
}

/// One canned reply, matched by path substring.
class _Route {
  const _Route(
    this.path, {
    this.status = 200,
    this.body,
    this.contentType = 'application/json; charset=utf-8',
  });

  final String path;
  final int status;
  final Object? body;
  final String contentType;
}

/// Serves a canned body, status *and* content type per path, which
/// [CapturingHttpAdapter] cannot do: the terminate paths hinge on a 401 from
/// one endpoint and a 200 from another within a single call, and the XML case
/// hinges on the content type.
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.routes);

  final List<_Route> routes;

  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final route = routes.firstWhere(
      (r) => options.uri.path.contains(r.path),
      orElse: () => const _Route('', status: 404),
    );
    final body = route.body;
    return ResponseBody.fromString(
      body == null ? '' : (body is String ? body : jsonEncode(body)),
      route.status,
      headers: {
        Headers.contentTypeHeader: [route.contentType],
      },
    );
  }
}

/// The first `Metadata` element of a `/status/sessions` fixture.
Map<String, dynamic> _firstSessionJson(String fixture) {
  final container = jsonFixtureMap(fixture)['MediaContainer'] as Map;
  return (container['Metadata'] as List).first as Map<String, dynamic>;
}

/// A synthetic library page of [count] films, wrapped in a real paging envelope.
///
/// Generated rather than a fixture on purpose: the point of the call site is the
/// *row count* (enough to cross `PlexClient`'s isolate threshold), and sixty
/// hand-written films would bury that in noise. The shape of each row is the one
/// `library_movies_page.json` records.
Map<String, dynamic> _generatedMoviePage(int count, {int? totalSize}) {
  return {
    'MediaContainer': {
      'size': count,
      'totalSize': ?totalSize,
      'offset': 0,
      'allowSync': true,
      'identifier': 'com.plexapp.plugins.library',
      'librarySectionID': 1,
      'librarySectionTitle': 'Movies',
      'viewGroup': 'movie',
      'Metadata': List.generate(count, (i) {
        final key = '${30000 + i}';
        return {
          'addedAt': 1700000000 + i,
          'art': '/library/metadata/$key/art/1747000000',
          'duration': 5400000 + i * 1000,
          'guid': 'plex://movie/5d776825961905001eb9$key',
          'key': '/library/metadata/$key',
          'librarySectionID': 1,
          'librarySectionKey': '/library/sections/1',
          'librarySectionTitle': 'Movies',
          'ratingKey': key,
          'summary': 'Row $i of a generated page.',
          'thumb': '/library/metadata/$key/thumb/1747000000',
          'title': 'Generated Film ${i.toString().padLeft(3, '0')}',
          'titleSort': 'Generated Film ${i.toString().padLeft(3, '0')}',
          'type': 'movie',
          'updatedAt': 1747000000,
          if (i.isEven) 'viewCount': 1,
          'year': 1980 + (i % 40),
          'Media': [
            {
              'audioCodec': 'eac3',
              'bitrate': 9000 + i,
              'container': 'mkv',
              'duration': 5400000 + i * 1000,
              'height': 1080,
              'id': '${70000 + i}',
              'videoCodec': 'h264',
              'videoResolution': '1080',
              'width': 1920,
            },
          ],
        };
      }),
    },
  };
}

/// A transport that always fails the way an unreachable host does.
class _FailingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'No route to host',
    );
  }
}

void main() {
  group('headers on the wire', () {
    test(
      'every request carries the Plex client identity and JSON Accept',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('plex/sessions_idle.json'),
        );
        await _client(adapter).getSessions();

        final headers = adapter.lastHeaders!;
        expect(headers['X-Plex-Token'], _kToken);
        // Persisted per install: a value regenerated per launch would register a
        // new device row on the user's server every time the app opened.
        expect(headers['X-Plex-Client-Identifier'], _kClientId);
        expect(headers['X-Plex-Product'], 'Cupola');
        expect(headers['X-Plex-Version'], kPlexProductVersion);
        expect(headers['X-Plex-Platform'], 'macOS');
        expect(headers['X-Plex-Device-Name'], 'Cupola');
        // Mandatory: the API answers XML without it and every parse here would
        // fail. Supplied by ApiClient, asserted so nothing quietly overrides it.
        expect(headers['Accept'], 'application/json');
      },
    );

    test('a non-ASCII or CR/LF-bearing value cannot reach the wire', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/sessions_idle.json'),
      );
      final client = PlexClient(
        url: _kUrl,
        token: _kToken,
        clientIdentifier: _kClientId,
        platform: 'macOS',
        deviceName: "Matt's Mac\r\nX-Injected: yes",
      );
      client.api.dio.httpClientAdapter = adapter;
      addTearDown(client.close);

      await client.getSessions();

      expect(
        adapter.lastHeaders!['X-Plex-Device-Name'],
        "Matt's MacX-Injected: yes",
      );
      expect(adapter.lastHeaders!.containsKey('X-Injected'), isFalse);
    });

    test('the credential travels in the header and never in a URL', () async {
      // Plex accepts `?X-Plex-Token=` too, and every third-party client uses it.
      // This asserts the whole surface refuses to: a token in a query string is
      // written to reverse-proxy access logs and, for artwork, into
      // CachedNetworkImage's on-disk cache index.
      final adapter = _RoutingAdapter([
        _Route(
          '',
          body: const {
            'MediaContainer': {'size': 0},
          },
        ),
      ]);
      final client = _client(adapter);

      await client.probeVersion();
      await client.getSessions();
      await client.getLibraries();
      await client.getItem('20418');
      await client.getChildren('41000');
      await client.getContinueWatching();
      await client.search('inter');
      await client.stopSession('u7k2m9x4qp1zvb3n');

      expect(adapter.requests, hasLength(8));
      for (final request in adapter.requests) {
        expect(request.uri.toString(), isNot(contains(_kToken)));
        expect(request.headers['X-Plex-Token'], _kToken);
      }
    });

    test('no token yet means no X-Plex-Token header at all', () async {
      // Onboarding probes reachability before the user has pasted anything; a
      // blank credential header would be sent as an empty rejected token.
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/identity.json'),
      );
      final client = _client(adapter, token: '');

      expect(await client.probeVersion(), '1.40.2.8395-c67dce28e');
      expect(adapter.lastHeaders!.containsKey('X-Plex-Token'), isFalse);
    });
  });

  group('probe and credential', () {
    test('probeVersion reads the version off /identity', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/identity.json'),
      );
      final client = _client(adapter);

      expect(await client.probeVersion(), '1.40.2.8395-c67dce28e');
      expect(adapter.lastUri!.path, '/identity');
    });

    test('verifyCredential accepts a 200 from /', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/capabilities.json'),
      );
      final client = _client(adapter);

      expect(await client.verifyCredential(), isTrue);
      expect(adapter.lastUri!.path, '/');
    });

    test('a 401 is a refused token, not an unreachable server', () async {
      final adapter = _RoutingAdapter([_Route('/', status: 401, body: null)]);
      expect(await _client(adapter).verifyCredential(), isFalse);
    });

    test('a JWT is refused before it is ever sent', () async {
      // plex.tv JSON Web Tokens last seven days and can only be refreshed by
      // plex.tv, which this client never calls, so it is a dead end, not a
      // delay, and saying so beats a week of working software.
      final adapter = _RoutingAdapter([_Route('/', status: 200, body: null)]);
      final client = _client(
        adapter,
        token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0In0.sig',
      );

      await expectLater(
        client.verifyCredential(),
        throwsA(
          isA<PlexException>()
              .having(
                (e) => e.tokenIssue,
                'tokenIssue',
                PlexTokenIssue.jsonWebToken,
              )
              .having(
                (e) => e.reason,
                'reason',
                ServiceFailureReason.unauthorized,
              )
              .having((e) => e.message, 'message', contains('device token')),
        ),
      );
      // Nothing was attempted: the verdict is offline.
      expect(adapter.requests, isEmpty);
    });

    test('a JWT also blocks the write actions', () async {
      final adapter = _RoutingAdapter([_Route('/', status: 200, body: null)]);
      final client = _client(adapter, token: 'eyJhbGciOiJIUzI1NiJ9.e30.x');

      await expectLater(
        client.stopSession('u7k2m9x4qp1zvb3n'),
        throwsA(isA<PlexException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('a 498 is the same verdict as a 401', () async {
      // Plex's non-standard "token expired". Same remedy as a 401 (re-paste),
      // and specifically *not* a reason to go asking plex.tv for a refresh.
      final adapter = _RoutingAdapter([_Route('/', status: 498, body: null)]);
      expect(await _client(adapter).verifyCredential(), isFalse);
    });

    test(
      'XML labelled as JSON is reported as a configuration problem',
      () async {
        // A reverse proxy that rewrites Accept but keeps the JSON content type:
        // Dio's own transformer fails before the client can see the leading `<`,
        // so the message has to be named from the DioException instead.
        final adapter = CapturingHttpAdapter(
          response: '<?xml version="1.0"?><MediaContainer size="0" />',
        );
        await expectLater(
          _client(adapter).verifyCredential(),
          throwsA(
            isA<PlexException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  ServiceFailureReason.notFound,
                )
                .having((e) => e.message, 'message', contains('XML')),
          ),
        );
      },
    );

    test('XML served as XML is named as XML, and reads still degrade', () async {
      // The API's default when `Accept: application/json` never arrives. Dio
      // hands a `text/xml` body through as a string, so this is the branch that
      // sees the leading `<`, the one the mislabelled case above cannot reach.
      final adapter = _RoutingAdapter([
        _Route(
          '/',
          body:
              '<?xml version="1.0" encoding="UTF-8"?>\n'
              '<MediaContainer size="0" friendlyName="basement-nas" '
              'machineIdentifier="9c8b7a6d" version="1.40.2.8395-c67dce28e" />',
          contentType: 'text/xml;charset=utf-8',
        ),
      ]);

      await expectLater(
        _client(adapter).verifyCredential(),
        throwsA(
          isA<PlexException>()
              .having((e) => e.reason, 'reason', ServiceFailureReason.notFound)
              .having((e) => e.message, 'message', contains('XML'))
              .having((e) => e.message, 'message', contains('Accept')),
        ),
      );
      // A slot read meets the same body and degrades; the sessions board read
      // says it could not read.
      await expectLater(
        _client(adapter).getSessions(),
        throwsA(isA<PlexException>()),
      );
      expect(await _client(adapter).probeVersion(), isNull);
    });

    test('capabilities expose the Plex Pass gate', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/capabilities.json'),
      );
      final capabilities = await _client(adapter).getCapabilities();

      expect(capabilities.friendlyName, 'basement-nas');
      expect(capabilities.myPlexUsername, 'matt');
      expect(capabilities.myPlexSubscription, isTrue);
      expect(capabilities.canTerminateSessions, isTrue);
      expect(capabilities.transcoderActiveVideoSessions, 1);
    });
  });

  group('sessions', () {
    test('an idle server has no Metadata key at all', () async {
      // Plex sends `{"size": 0}` with the key absent, not an empty array, the
      // way Jellyfin does. A naive cast to List throws here.
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/sessions_idle.json'),
      );
      expect(await _client(adapter).getSessions(), isEmpty);
    });

    test('a direct play carries no transcode reasons', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/sessions_direct_play.json'),
      );
      final sessions = await _client(adapter).getSessions();

      expect(adapter.lastUri!.path, '/status/sessions');
      expect(sessions, hasLength(1));

      final session = sessions.single;
      // The nested `Session.id`, never `sessionKey` (417) and never
      // `Player.machineIdentifier`: both 404 when substituted.
      expect(session.id, 'u7k2m9x4qp1zvb3n');
      expect(session.userName, 'matt');
      expect(session.title, 'Interstellar');
      expect(session.subtitle, '2014');
      expect(session.deviceLabel, 'Infuse\u00A0· Apple TV');
      expect(session.posterPath, '/library/metadata/20418/thumb/1748102400');
      // No TranscodeSession at all is the only signal Plex gives for a direct
      // play; there is no field that says so.
      expect(session.playMethod, StreamPlayMethod.directPlay);
      expect(session.transcodeReasons, isEmpty);
      expect(session.needsAttention, isFalse);
      expect(session.isPaused, isFalse);
    });

    test('a session names its title by the show for an episode, by the '
        'movie for a movie, and by nothing for a track', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/sessions_mixed.json'),
      );
      final sessions = await _client(adapter).getSessions();

      expect({
        for (final session in sessions) session.title: session.titleId,
      }, containsPair('Interstellar', '20418'));
      expect(
        sessions.map((session) => session.titleId),
        containsAll(['20418', '20991', '41000', null]),
      );
    });

    test('a transcode explains itself in prose', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/sessions_transcode.json'),
      );
      final session = (await _client(adapter).getSessions()).single;

      expect(session.playMethod, StreamPlayMethod.transcode);
      expect(session.needsAttention, isTrue);
      expect(session.transcodeReasons, [
        'video HEVC → H.264',
        'audio TrueHD → AAC',
        'subtitle burn-in',
        'software encode, hardware not used',
        'falling behind at 0.8× realtime',
      ]);
      expect(
        session.transcodeReasonLabel,
        'video HEVC → H.264\u00A0· audio TrueHD → AAC\u00A0· subtitle burn-in\u00A0· '
        'software encode, hardware not used\u00A0· falling behind at 0.8× realtime',
      );

      // An episode leads with the series and carries the episode below it.
      expect(session.title, 'Severance');
      expect(session.subtitle, 'S1\u00A0E4\u00A0· The You You Are');
      // The series poster reads better than an episode still at grid size.
      expect(session.posterPath, '/library/metadata/41000/thumb/1718220000');
      expect(session.deviceLabel, 'Plex Web\u00A0· Windows');
    });

    test('the board is ordered most expensive first', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/sessions_mixed.json'),
      );
      final sessions = await _client(adapter).getSessions();

      expect(sessions.map((s) => s.playMethod).toList(), [
        StreamPlayMethod.transcode,
        StreamPlayMethod.directStream,
        StreamPlayMethod.directPlay,
        StreamPlayMethod.directPlay,
      ]);
      // Within a method, bitrate breaks the tie: the Plexamp session has no
      // `Session` element and falls back to the file's own 15000 kbps.
      expect(sessions[2].title, 'Idioteque');
      expect(sessions[2].bitrate, 15000000);
      expect(sessions[3].title, 'Interstellar');
      expect(sessions[3].bitrate, 4200000);
    });

    test('videoDecision copy is a direct stream, not a transcode', () async {
      final sessions = await _client(
        CapturingHttpAdapter(
          response: jsonFixtureMap('plex/sessions_mixed.json'),
        ),
      ).getSessions();
      final rewrap = sessions.firstWhere(
        (s) => s.playMethod == StreamPlayMethod.directStream,
      );

      expect(rewrap.title, 'Severance');
      expect(rewrap.transcodeReasons, [
        'audio TrueHD → E-AC3',
        'container rewrap to MKV',
      ]);
      expect(rewrap.isPaused, isTrue);
    });

    test('a session with no Session element cannot be stopped', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/sessions_mixed.json'),
      );
      final client = _client(adapter);
      final orphan = (await client.getSessions()).firstWhere(
        (s) => s.title == 'Idioteque',
      );

      expect(orphan.id, isEmpty);
      // Refused locally rather than sent as an empty parameter, which the server
      // answers with a 403 whose documented meaning is about permissions.
      await expectLater(
        client.stopSession(orphan.id),
        throwsA(
          isA<PlexException>().having(
            (e) => e.message,
            'message',
            contains('session id'),
          ),
        ),
      );
    });
  });

  group('transcode session', () {
    test('a direct play has no TranscodeSession to read', () {
      // Absence is the only signal Plex gives for a direct play; there is no
      // field that says so.
      expect(
        PlexTranscodeSession.maybeFrom(
          _firstSessionJson('plex/sessions_direct_play.json'),
        ),
        isNull,
      );
    });

    test('progress is a percentage and duration is milliseconds', () {
      final transcode = PlexTranscodeSession.maybeFrom(
        _firstSessionJson('plex/sessions_transcode.json'),
      )!;

      // 0–100, *not* a 0..1 fraction: fed to a progress bar unscaled this would
      // sit pinned at full for anything past 1%.
      expect(transcode.progress, 12.5);
      // A unitless multiple of realtime, and the most useful number on the
      // object: below 1.0 the encoder is losing the race with playback.
      expect(transcode.speed, 0.8);
      expect(transcode.durationMs, 3180000);
      expect(transcode.videoDecision, PlexStreamDecision.transcode);
      expect(transcode.audioDecision, PlexStreamDecision.transcode);
      expect(transcode.subtitleDecision, PlexStreamDecision.burn);
      expect(transcode.transcodeHwRequested, isTrue);
      expect(transcode.transcodeHwEncoding, isFalse);
      expect(transcode.playMethod, StreamPlayMethod.transcode);
    });

    test('a healthy throttled transcode is not reported as falling behind', () {
      // Throttling is Plex deliberately slowing an encoder that is comfortably
      // ahead. Naming it would put a non-problem on a board that exists for
      // things the user can act on.
      final metadata =
          (jsonFixtureMap('plex/sessions_mixed.json')['MediaContainer']
                  as Map)['Metadata']
              as List;
      final transcode = PlexTranscodeSession.maybeFrom(
        metadata[1] as Map<String, dynamic>,
      )!;

      expect(transcode.throttled, isTrue);
      expect(transcode.speed, 4.7);
      expect(transcode.reasons, [
        'video HEVC → H.264',
        'audio TrueHD → AAC',
        'hardware encoder',
      ]);
    });

    test('the singletons may arrive as a one-element array', () {
      // Plex writes every child element as an array in JSON, and which builds
      // wrap `TranscodeSession` and which do not is not something to depend on.
      final transcode = PlexTranscodeSession.maybeFrom({
        'TranscodeSession': [
          {
            'key': '/transcode/sessions/abc',
            'videoDecision': 'copy',
            'audioDecision': 'transcode',
            'subtitleDecision': 'copy',
            'sourceAudioCodec': 'truehd',
            'audioCodec': 'aac',
            'container': 'mkv',
          },
        ],
      })!;

      expect(transcode.playMethod, StreamPlayMethod.directStream);
      // Absent booleans are absent, not false-as-a-claim: nothing said about
      // hardware means no hardware verdict is reported either way.
      expect(transcode.transcodeHwRequested, isFalse);
      expect(transcode.transcodeHwEncoding, isFalse);
      expect(transcode.reasons, [
        'audio TrueHD → AAC',
        'container rewrap to MKV',
      ]);
    });
  });

  group('units', () {
    // The single highest-value test in this file: Plex mixes three units on the
    // same object, and every one of them is a plausible-looking wrong answer.
    test('kbps becomes bits per second and is always nominal', () async {
      final session = (await _client(
        CapturingHttpAdapter(
          response: jsonFixtureMap('plex/sessions_transcode.json'),
        ),
      ).getSessions()).single;

      // `Session.bandwidth: 12000` is kilobits per second.
      expect(session.bitrate, 12000000);
      // Always true on Plex: `bandwidth` is a reservation made by the streaming
      // brain and `Media.bitrate` describes the file. Neither is measured
      // egress, so the board may never sum them or call one throughput.
      expect(session.bitrateIsNominal, isTrue);
    });

    test('duration and viewOffset are milliseconds', () async {
      final session = (await _client(
        CapturingHttpAdapter(
          response: jsonFixtureMap('plex/sessions_transcode.json'),
        ),
      ).getSessions()).single;

      // 1_245_000 / 3_180_000: milliseconds throughout, unlike Jellyfin's
      // 100-nanosecond ticks.
      expect(session.progress, closeTo(0.3915, 0.0001));
    });

    test('runtime stays in milliseconds on an item', () async {
      final item = await _client(
        CapturingHttpAdapter(
          response: jsonFixtureMap('plex/metadata_movie.json'),
        ),
      ).getItem('20418');

      expect(item!.runtimeMs, 9114000);
      expect(item.resumeOffsetMs, 2278500);
      expect(item.resumeProgress, closeTo(0.25, 0.001));
      expect(item.isInProgress, isTrue);
    });

    test('scannedAt is epoch seconds, not milliseconds', () async {
      final libraries = await _client(
        CapturingHttpAdapter(
          response: jsonFixtureMap('plex/library_sections.json'),
        ),
      ).getLibraries();

      // 1_723_456_789 seconds. Read as milliseconds this would land in 1970.
      expect(
        libraries.first.lastScannedAt,
        DateTime.fromMillisecondsSinceEpoch(1723456789 * 1000, isUtc: true),
      );
      expect(libraries.first.lastScannedAt!.year, 2024);
    });
  });

  group('libraries', () {
    test('sections map to kinds, ids stay strings', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/library_sections.json'),
      );
      final libraries = await _client(adapter).getLibraries();

      expect(adapter.lastUri!.path, '/library/sections');
      expect(libraries.map((l) => l.id).toList(), ['1', '2', '3', '4']);
      expect(libraries.map((l) => l.kind).toList(), [
        StreamLibraryKind.movies,
        StreamLibraryKind.shows,
        StreamLibraryKind.music,
        StreamLibraryKind.photos,
      ]);
      expect(libraries[1].isRefreshing, isTrue);
      expect(libraries[0].isRefreshing, isFalse);
      // Plex puts no count on a section; it is fetched on request instead.
      expect(libraries[0].itemCount, isNull);
      // The photo section has no scannedAt, so the column stays empty rather
      // than inventing one.
      expect(libraries[3].lastScannedAt, isNull);
    });

    test('the item count costs one request and reads totalSize', () async {
      final adapter = CapturingHttpAdapter(
        byPath: {
          '/library/sections/1/all': jsonFixtureMap(
            'plex/library_movies_page.json',
          ),
          '/library/sections': jsonFixtureMap('plex/library_sections.json'),
        },
      );
      final count = await _client(adapter).getLibraryItemCount('1');

      expect(count, 137);
      // A page of nothing: the cheapest count Plex offers.
      expect(adapter.lastUri!.queryParameters['X-Plex-Container-Size'], '0');
      expect(adapter.lastUri!.queryParameters['type'], '1');
    });
  });

  group('library items', () {
    CapturingHttpAdapter sectionsPlus(Map<String, dynamic> routes) {
      return CapturingHttpAdapter(
        byPath: {
          ...routes,
          // Last, so the more specific `/library/sections/<id>/…` keys win.
          '/library/sections': jsonFixtureMap('plex/library_sections.json'),
        },
      );
    }

    test(
      'the whole library opens in Name order and pages explicitly',
      () async {
        final adapter = sectionsPlus({
          '/library/sections/1/all': jsonFixtureMap(
            'plex/library_movies_page.json',
          ),
        });
        final items = await _client(adapter).getLibraryItems(libraryId: '1');

        final query = adapter.lastUri!.queryParameters;
        expect(adapter.lastUri!.path, '/library/sections/1/all');
        expect(query['type'], '1');
        expect(query['sort'], 'titleSort');
        // Both parameters, always: a start without a size returns the server's
        // default page and a size without a start silently re-reads page one.
        expect(query['X-Plex-Container-Start'], '0');
        expect(query['X-Plex-Container-Size'], '50');

        expect(items.map((i) => i.title).toList(), [
          'Fight Club',
          'Interstellar',
        ]);
        expect(items.first.kind, StreamItemKind.movie);
        expect(items.first.subtitle, '1999');
        // No boolean `watched` exists: viewCount >= 1 is the whole test.
        expect(items.first.isPlayed, isTrue);
        expect(items.first.resumeOffsetMs, isNull);
        expect(items[1].isPlayed, isFalse);
      },
    );

    for (final (sort, expected) in [
      (StreamLibrarySort.name, 'titleSort'),
      (StreamLibrarySort.dateAdded, 'addedAt:desc,titleSort'),
      (StreamLibrarySort.year, 'year:desc,titleSort'),
    ]) {
      test(
        '${sort.name} sorts on $expected, the title breaking ties',
        () async {
          final adapter = sectionsPlus({
            '/library/sections/1/all': jsonFixtureMap(
              'plex/library_movies_page.json',
            ),
          });
          await _client(adapter).getLibraryItems(libraryId: '1', sort: sort);

          expect(adapter.lastUri!.path, '/library/sections/1/all');
          expect(adapter.lastUri!.queryParameters['sort'], expected);
          // A sort alone never narrows the shelf.
          expect(
            adapter.lastUri!.queryParameters.containsKey('unwatched'),
            isFalse,
          );
        },
      );
    }

    test('unplayedOnly uses unwatched=1 for a movie section', () async {
      final adapter = sectionsPlus({
        '/library/sections/1/all': jsonFixtureMap(
          'plex/library_movies_page.json',
        ),
      });
      await _client(
        adapter,
      ).getLibraryItems(libraryId: '1', unplayedOnly: true);

      expect(adapter.lastUri!.queryParameters['unwatched'], '1');
      expect(
        adapter.lastUri!.queryParameters.containsKey('show.unwatchedLeaves'),
        isFalse,
      );
    });

    test(
      'unplayedOnly uses show.unwatchedLeaves=1 for a show section',
      () async {
        // Sending the movie spelling at a show section returns the whole library
        // rather than an error: a silently wrong shelf.
        final adapter = sectionsPlus({
          '/library/sections/2/all': jsonFixtureMap(
            'plex/library_shows_unplayed.json',
          ),
        });
        final items = await _client(
          adapter,
        ).getLibraryItems(libraryId: '2', unplayedOnly: true);

        final query = adapter.lastUri!.queryParameters;
        expect(query['type'], '2');
        expect(query['show.unwatchedLeaves'], '1');
        expect(query.containsKey('unwatched'), isFalse);

        expect(items.first.kind, StreamItemKind.series);
        // leafCount 19 − viewedLeafCount 4.
        expect(items.first.unplayedChildCount, 15);
        expect(items.first.isPlayed, isFalse);
        // The second show omits viewedLeafCount entirely, which means zero: the
        // badge has to appear on exactly the shows nobody has started.
        expect(items[1].unplayedChildCount, 8);
      },
    );

    test('the section kind is cached across pages', () async {
      final adapter = sectionsPlus({
        '/library/sections/1/all': jsonFixtureMap(
          'plex/library_movies_page.json',
        ),
      });
      final client = _client(adapter);

      await client.getLibraryItems(libraryId: '1');
      await client.getLibraryItems(libraryId: '1');

      // sections once, then one page request each.
      expect(adapter.callCount, 3);
    });

    test('next up is the part of continue watching with no position', () async {
      // Plex has no separate endpoint: the continue-watching hub is both at
      // once, and a part-watched item is the one carrying a viewOffset.
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/library_on_deck.json'),
      );
      final client = _client(adapter);

      final continuing = await client.getContinueWatching();
      expect(adapter.lastUri!.path, '/hubs/continueWatching');
      expect(continuing.first.title, 'The You You Are');
      expect(continuing.first.resumeOffsetMs, 1245000);
      expect(continuing.first.subtitle, 'Severance');

      final nextUp = await client.getNextUp(count: 8);
      expect(adapter.lastUri!.path, '/hubs/continueWatching');
      // Asked for twice the count, so dropping the part-watched rows still
      // leaves a full row.
      expect(adapter.lastUri!.queryParameters['count'], '16');
      expect(nextUp.map((i) => i.title).toList(), [
        'Estuary',
        'Hello, Ms. Cobel',
      ]);
      // An explicit `viewOffset: 0` is not a resume point.
      expect(nextUp.last.resumeOffsetMs, isNull);

      expect((await client.getNextUp(count: 1)).map((i) => i.title).toList(), [
        'Estuary',
      ]);
    });

    test('recently added keeps movies and shows, turns a season or an '
        'episode into its show once, and drops music', () async {
      final adapter = CapturingHttpAdapter(
        response: const {
          'MediaContainer': {
            'size': 7,
            'Metadata': [
              {
                'ratingKey': '30001',
                'key': '/library/metadata/30001',
                'title': 'Solaris',
                'type': 'movie',
                'year': 1972,
              },
              {
                'ratingKey': '41002',
                'key': '/library/metadata/41002/children',
                'title': 'Season 2',
                'type': 'season',
                'parentRatingKey': '41000',
                'parentTitle': 'Severance',
                'parentThumb': '/library/metadata/41000/thumb/1718220000',
              },
              {
                'ratingKey': '41123',
                'key': '/library/metadata/41123',
                'title': 'Hello, Ms. Cobel',
                'type': 'episode',
                'grandparentRatingKey': '41000',
                'grandparentTitle': 'Severance',
                'grandparentThumb': '/library/metadata/41000/thumb/1718220000',
              },
              {
                'ratingKey': '50010',
                'key': '/library/metadata/50010',
                'title': 'In Rainbows',
                'type': 'album',
                'parentRatingKey': '50000',
                'parentTitle': 'Radiohead',
              },
              {
                'ratingKey': '50020',
                'key': '/library/metadata/50020',
                'title': 'Nude',
                'type': 'track',
              },
              {
                'ratingKey': '50000',
                'key': '/library/metadata/50000/children',
                'title': 'Radiohead',
                'type': 'artist',
              },
              {
                'ratingKey': '42000',
                'key': '/library/metadata/42000/children',
                'title': 'Andor',
                'type': 'show',
              },
            ],
          },
        },
      );
      final items = await _client(adapter).getRecentlyAdded(count: 10);

      expect(adapter.lastUri!.path, '/library/recentlyAdded');
      expect(adapter.lastUri!.queryParameters['X-Plex-Container-Size'], '30');
      // The season and the episode are the same show: it appears once, at the
      // place of its first row. The album, track and artist are gone.
      expect(items.map((i) => i.title).toList(), [
        'Solaris',
        'Severance',
        'Andor',
      ]);
      expect(items[0].kind, StreamItemKind.movie);
      expect(items[1].kind, StreamItemKind.series);
      expect(items[1].id, '41000');
      expect(items[1].posterPath, '/library/metadata/41000/thumb/1718220000');
    });

    test('recently added stops at the count asked for', () async {
      final adapter = CapturingHttpAdapter(
        response: _generatedMoviePage(5, totalSize: 5),
      );
      final items = await _client(adapter).getRecentlyAdded(count: 2);

      expect(items, hasLength(2));
    });

    test(
      'paging follows the returned totalSize, not the requested size',
      () async {
        // Plex's own guidance: the response "might include a different number of
        // items than requested", so a pager that trusted its own page size would
        // stop early or never stop.
        final first = sectionsPlus({
          '/library/sections/1/all': jsonFixtureMap(
            'plex/library_movies_page.json',
          ),
        });
        final page = (await _client(
          first,
        ).getLibraryItemsPage(libraryId: '1', limit: 50))!;

        expect(first.lastUri!.queryParameters['X-Plex-Container-Size'], '50');
        expect(page.size, 2);
        expect(page.totalSize, 137);
        expect(page.offset, 0);
        expect(page.nextOffset, 2);
        expect(page.hasMore, isTrue);

        final last = sectionsPlus({
          '/library/sections/1/all': jsonFixtureMap(
            'plex/library_movies_last_page.json',
          ),
        });
        final tail = (await _client(
          last,
        ).getLibraryItemsPage(libraryId: '1', startIndex: 136))!;

        expect(tail.offset, 136);
        expect(tail.size, 1);
        expect(tail.nextOffset, 137);
        expect(tail.hasMore, isFalse);
      },
    );

    test('a music section browses artists, at type 8', () async {
      // 8=artist, 9=album, 10=track. Sending 10 here would answer with every
      // track in the library instead of the artists that own them.
      final adapter = sectionsPlus({
        '/library/sections/3/all': jsonFixtureMap(
          'plex/library_music_page.json',
        ),
      });
      final items = await _client(
        adapter,
      ).getLibraryItems(libraryId: '3', unplayedOnly: true);

      final query = adapter.lastUri!.queryParameters;
      expect(query['type'], '8');
      // Neither unwatched spelling applies to a music section, so neither is
      // sent: `unwatched=1` at an artist section is silently ignored and would
      // make the lens a second copy of A–Z.
      expect(query.containsKey('unwatched'), isFalse);
      expect(query.containsKey('show.unwatchedLeaves'), isFalse);

      expect(items.map((i) => i.title).toList(), ['Radiohead', 'Nils Frahm']);
      // `StreamItemKind` has no artist member and the enum's only behavioural
      // consumer is `hasChildren`, so an artist maps to `album` to keep
      // artist → album → track traversable. `other` would dead-end the browse.
      expect(items.first.kind, StreamItemKind.album);
      expect(items.first.kind.hasChildren, isTrue);
      // No leafCount on an artist, so no unplayed badge is invented.
      expect(items.first.unplayedChildCount, isNull);
      expect(items[1].isPlayed, isFalse);
    });

    test('a photo section sends no type at all', () async {
      // Guessing an id for a section kind Plex has no browse type for would
      // filter the section down to nothing; letting the server pick its own
      // primary type returns what the room actually holds.
      final adapter = sectionsPlus({
        '/library/sections/4/all': _generatedMoviePage(0, totalSize: 0),
      });
      await _client(adapter).getLibraryItems(libraryId: '4');

      expect(adapter.lastUri!.path, '/library/sections/4/all');
      expect(adapter.lastUri!.queryParameters.containsKey('type'), isFalse);
      expect(adapter.lastUri!.queryParameters['sort'], 'titleSort');
    });

    test('a page past the isolate threshold still maps every row', () async {
      // 60 rows crosses the threshold, so this is the only test that runs the
      // mapping through `Isolate.run`. It fails loudly if the closure ever drags
      // an unsendable `this` across the boundary, a failure that would
      // otherwise be swallowed by the read path's degrade-to-empty and surface
      // as a library that is mysteriously blank on big sections only.
      final adapter = sectionsPlus({
        '/library/sections/1/all': _generatedMoviePage(60, totalSize: 137),
      });
      final page = (await _client(
        adapter,
      ).getLibraryItemsPage(libraryId: '1', limit: 60))!;

      expect(page.items, hasLength(60));
      expect(page.items.first.title, 'Generated Film 000');
      expect(page.items.last.title, 'Generated Film 059');
      expect(page.items.first.id, '30000');
      expect(page.items.first.runtimeMs, 5400000);
      // Every other row carries `viewCount: 1`; the rest omit it entirely.
      expect(page.items.first.isPlayed, isTrue);
      expect(page.items[1].isPlayed, isFalse);
      expect(page.totalSize, 137);
      expect(page.hasMore, isTrue);
    });

    test('a response with no paging envelope still pages honestly', () async {
      // Older builds and `onDeck` answer without `offset`/`totalSize`. With no
      // total the only honest signal is "the server sent rows", so the pager
      // keeps going until a page comes back empty rather than guessing a total.
      final adapter = sectionsPlus({
        '/library/sections/1/all': const {
          'MediaContainer': {
            'size': 2,
            'identifier': 'com.plexapp.plugins.library',
            'Metadata': [
              {
                'ratingKey': '30001',
                'key': '/library/metadata/30001',
                'title': 'Solaris',
                'type': 'movie',
                'duration': 9900000,
                'thumb': '/library/metadata/30001/thumb/1747000000',
                'year': 1972,
              },
              {
                'ratingKey': '30002',
                'key': '/library/metadata/30002',
                'title': 'Stalker',
                'type': 'movie',
                'duration': 9660000,
                'thumb': '/library/metadata/30002/thumb/1747000000',
                'year': 1979,
              },
            ],
          },
        },
      });
      final page = (await _client(
        adapter,
      ).getLibraryItemsPage(libraryId: '1', startIndex: 12))!;

      // Falls back to what was asked for only because the server said nothing.
      expect(page.offset, 12);
      expect(page.size, 2);
      expect(page.totalSize, isNull);
      expect(page.nextOffset, 14);
      expect(page.hasMore, isTrue);
      // An absent viewCount is unwatched, not unknown, and an absent viewOffset
      // is no resume point rather than a bar pinned at zero.
      expect(page.items.first.isPlayed, isFalse);
      expect(page.items.first.resumeOffsetMs, isNull);
      expect(page.items.first.resumeProgress, isNull);
    });
  });

  group('items and nesting', () {
    test('getItem skips the file check and the agent refresh', () async {
      // A bare GET makes the server stat every file and can kick off an agent
      // refresh, both synchronously: thirty seconds on a spun-down NAS.
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/metadata_movie.json'),
      );
      final item = await _client(adapter).getItem('20418');

      expect(adapter.lastUri!.path, '/library/metadata/20418');
      expect(adapter.lastUri!.queryParameters['checkFiles'], '0');
      expect(adapter.lastUri!.queryParameters['skipRefresh'], '1');

      expect(item!.id, '20418');
      expect(item.id, isA<String>());
      expect(item.title, 'Interstellar');
      expect(item.year, 2014);
      expect(item.posterPath, '/library/metadata/20418/thumb/1748102400');
    });

    test('show → season → episode nests through children', () async {
      final adapter = CapturingHttpAdapter(
        byPath: {
          '/library/metadata/41001/children': jsonFixtureMap(
            'plex/season_children.json',
          ),
          '/library/metadata/41000/children': jsonFixtureMap(
            'plex/show_children.json',
          ),
        },
      );
      final client = _client(adapter);

      final seasons = await client.getChildren('41000');
      expect(adapter.lastUri!.path, '/library/metadata/41000/children');
      expect(seasons.map((s) => s.title).toList(), ['Season 1', 'Season 2']);
      expect(seasons.first.kind, StreamItemKind.season);
      expect(seasons.first.kind.hasChildren, isTrue);
      expect(seasons.first.subtitle, 'Severance');
      // 9 leaves, 4 watched.
      expect(seasons.first.unplayedChildCount, 5);
      expect(seasons.first.isPlayed, isFalse);
      // 10 of 10 watched: the only "watched" a container gets.
      expect(seasons[1].isPlayed, isTrue);
      expect(seasons[1].unplayedChildCount, isNull);

      final episodes = await client.getChildren('41001');
      expect(episodes.map((e) => e.title).toList(), [
        'Good News About Hell',
        'The You You Are',
      ]);
      expect(episodes.first.kind, StreamItemKind.episode);
      expect(episodes.first.kind.hasChildren, isFalse);
      // An episode's subtitle is the series name.
      expect(episodes.first.subtitle, 'Severance');
      expect(episodes.first.isPlayed, isTrue);
      expect(episodes[1].resumeOffsetMs, 1245000);
      expect(episodes[1].isPlayed, isFalse);
    });

    test('children given as Directory read the same as Metadata', () async {
      // Current builds answer `/children` with `Metadata` in JSON, but these are
      // `Directory` elements in the XML the JSON layer was grafted onto and older
      // servers still say so. Reading only one key would show a show with no
      // seasons on exactly the installs least likely to be updated.
      final adapter = CapturingHttpAdapter(
        response: const {
          'MediaContainer': {
            'size': 1,
            'key': '41000',
            'parentTitle': 'Severance',
            'viewGroup': 'season',
            'Directory': [
              {
                'ratingKey': '41001',
                'key': '/library/metadata/41001/children',
                'title': 'Season 1',
                'type': 'season',
                'index': 1,
                'parentTitle': 'Severance',
                'thumb': '/library/metadata/41001/thumb/1718220000',
                'leafCount': 9,
                'viewedLeafCount': 4,
              },
            ],
          },
        },
      );
      final seasons = await _client(adapter).getChildren('41000');

      expect(seasons, hasLength(1));
      expect(seasons.single.title, 'Season 1');
      expect(seasons.single.kind, StreamItemKind.season);
      expect(seasons.single.unplayedChildCount, 5);
    });

    test('getViewers returns exactly one viewer', () async {
      // Structural, not a stub: /library/* takes no impersonation parameter, so
      // every lens answers for the token's owner. Another member's token is only
      // obtainable from plex.tv, which this client never calls.
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/capabilities.json'),
      );
      final viewers = await _client(adapter).getViewers();

      expect(viewers, hasLength(1));
      expect(viewers.single.name, 'matt');
      // `/` rather than `/accounts`, which is admin-only in practice.
      expect(adapter.lastUri!.path, '/');
    });

    test('an unclaimed server does not name the box as a person', () async {
      final capabilities = jsonFixtureMap('plex/capabilities.json');
      final container =
          (capabilities['MediaContainer'] as Map).cast<String, dynamic>()
            ..remove('myPlexUsername')
            ..['friendlyName'] = 'tower';
      final adapter = CapturingHttpAdapter(
        response: {'MediaContainer': container},
      );

      // `friendlyName` is what the owner called the *machine*, so falling back
      // to it invented a household member named "tower". The owner is still the
      // owner when Plex will not name them (decision 16).
      final viewers = await _client(adapter).getViewers();
      expect(viewers.single.name, kPlexOwnerFallbackName);
      expect(viewers.single.name, isNot('tower'));
    });

    test('a viewerId is accepted and has no effect on the request', () async {
      final adapter = CapturingHttpAdapter(
        byPath: {
          '/library/sections/1/all': jsonFixtureMap(
            'plex/library_movies_page.json',
          ),
          '/library/sections': jsonFixtureMap('plex/library_sections.json'),
        },
      );
      await _client(adapter).getLibraryItems(
        libraryId: '1',
        unplayedOnly: true,
        viewerId: 'someone-else',
      );

      final query = adapter.lastUri!.queryParameters;
      expect(query.containsKey('accountID'), isFalse);
      expect(query.values, isNot(contains('someone-else')));
    });
  });

  group('cloud results', () {
    test('provider rows are dropped from a hub', () async {
      // The single most likely way a no-plex.tv client leaks: /hubs mixes cloud
      // results, with absolute plex.tv artwork, into the same array as local
      // ones.
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('plex/hubs_continue_watching.json'),
      );
      final items = await _client(adapter).getContinueWatching();

      expect(items.map((i) => i.title).toList(), ['Interstellar']);
      expect(adapter.lastUri!.queryParameters['count'], '50');
      // Nothing that survived can point off the server.
      for (final item in items) {
        expect(item.posterPath, startsWith('/'));
      }
    });

    test('a hub response with no Hub wrapper is still read', () async {
      // Some builds answer `/hubs/continueWatching` with a bare `Metadata` array
      // rather than wrapping it in a single hub.
      final adapter = CapturingHttpAdapter(
        response: const {
          'MediaContainer': {
            'size': 1,
            'identifier': 'com.plexapp.plugins.library',
            'Metadata': [
              {
                'ratingKey': '20418',
                'key': '/library/metadata/20418',
                'title': 'Interstellar',
                'type': 'movie',
                'duration': 9114000,
                'viewOffset': 2278500,
                'thumb': '/library/metadata/20418/thumb/1748102400',
                'year': 2014,
                'source':
                    'server://9c8b7a6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b/'
                    'com.plexapp.plugins.library',
              },
            ],
          },
        },
      );
      final items = await _client(adapter).getContinueWatching();

      expect(items.map((i) => i.title).toList(), ['Interstellar']);
      expect(items.single.resumeOffsetMs, 2278500);
    });

    test(
      'search drops provider rows and always sets a per-hub limit',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('plex/hubs_search.json'),
        );
        final results = await _client(adapter).search('inter', limit: 12);

        final query = adapter.lastUri!.queryParameters;
        expect(query['query'], 'inter');
        // Per hub, and 3 by default: always sent explicitly.
        expect(query['limit'], '12');
        expect(query['includeExternalMedia'], '0');

        // CHANGED: `search` used to flatten every hub into one list. It now
        // hands back the server's own bands, because Plex has already grouped
        // and ranked them and the page renders that order rather than imposing
        // one. The rows inside a band, and the provider-row rejection, are
        // unchanged.
        expect(results.map((group) => group.label).toList(), [
          'Movies',
          'Shows',
        ]);
        expect(
          results.map((group) => group.items.map((i) => i.title).toList()),
          [
            ['Interstellar'],
            ['Tidelines: Interstitial'],
          ],
        );
      },
    );

    test('a hub keeps the kind it is about, and only when there is one', () {
      // The band's kind is not `plexItemKindFromType`: that one bends `artist`
      // onto `album` so a music browse stays traversable, and folds everything
      // else onto `other`. Neither answer is true of a *band*.
      expect(plexHubKind('movie'), StreamItemKind.movie);
      expect(plexHubKind('show'), StreamItemKind.series);
      expect(plexHubKind('artist'), isNull);
      expect(plexHubKind('actor'), isNull);
      expect(plexHubKind(null), isNull);
    });

    test('an empty hub survives as an empty band', () async {
      final adapter = CapturingHttpAdapter(
        response: {
          'MediaContainer': {
            'Hub': [
              {'type': 'movie', 'title': 'Movies', 'size': 0, 'Metadata': []},
              {'type': 'actor', 'title': 'Actors', 'size': 0},
            ],
          },
        },
      );

      final groups = await _client(adapter).search('inter');

      // The strip draws a zero pill from this. Dropping the hub would turn "no
      // matching film on this server" into "films were never searched", and the
      // two are not the same answer.
      expect(groups.map((group) => group.label).toList(), ['Movies', 'Actors']);
      expect(groups.every((group) => group.isEmpty), isTrue);
      // An Actors hub is about something the shared vocabulary has no word for.
      expect(groups.last.kind, isNull);
    });

    test(
      'a hub with no title is dropped rather than folded into its neighbour',
      () async {
        final adapter = CapturingHttpAdapter(
          response: {
            'MediaContainer': {
              'Hub': [
                {'type': 'movie', 'title': 'Movies', 'Metadata': []},
                {'type': 'tag', 'Metadata': []},
              ],
            },
          },
        );

        // An unlabelled band on a strip of pills would draw a pill that says
        // nothing at all; its rows are not smuggled into the band above it.
        final groups = await _client(adapter).search('inter');
        expect(groups.map((group) => group.label).toList(), ['Movies']);
      },
    );

    test('an empty query never reaches the server', () async {
      final adapter = CapturingHttpAdapter(response: {});
      expect(await _client(adapter).search('   '), isEmpty);
      expect(adapter.callCount, 0);
    });

    test('the rejection rule is three-sided', () {
      // `source` is absent on an ordinary library row, so its absence has to
      // mean "local", which is why an absolute key or thumb must also disqualify.
      expect(
        plexIsServerItem({'ratingKey': '1', 'key': '/library/metadata/1'}),
        isTrue,
      );
      expect(
        plexIsServerItem({
          'ratingKey': '1',
          'source': 'provider://tv.plex.provider.metadata',
        }),
        isFalse,
      );
      expect(
        plexIsServerItem({
          'ratingKey': '1',
          'key': 'https://vod.provider.plex.tv/library/metadata/1',
        }),
        isFalse,
      );
      expect(
        plexIsServerItem({
          'ratingKey': '1',
          'thumb': 'https://metadata-static.plex.tv/a/b/thumb.jpg',
        }),
        isFalse,
      );
    });
  });

  group('artwork', () {
    test('the token stays in a header, never in the URL', () async {
      final source = _client(
        CapturingHttpAdapter(response: {}),
      ).imageFor('/library/metadata/20418/thumb/1748102400');

      expect(source!.url, '$_kUrl/library/metadata/20418/thumb/1748102400');
      expect(source.headers!['X-Plex-Token'], _kToken);
      // A token in the query string becomes CachedNetworkImage's cache key.
      expect(source.url, isNot(contains(_kToken)));
    });

    test(
      'a width goes through the photo transcoder with a relative inner url',
      () async {
        final source = _client(
          CapturingHttpAdapter(response: {}),
        ).imageFor('/library/metadata/20418/thumb/1748102400', width: 300);

        final uri = Uri.parse(source!.url);
        expect(uri.path, '/photo/:/transcode');
        // Relative, so the server resolves it internally under the outer
        // request's own auth and no credential enters a query string. An absolute
        // inner url would need a 48h delegation token, never the user's own.
        expect(
          uri.queryParameters['url'],
          '/library/metadata/20418/thumb/1748102400',
        );
        expect(uri.queryParameters['width'], '300');
        expect(uri.queryParameters['height'], '450');
        expect(uri.queryParameters['upscale'], '0');
        expect(uri.query, isNot(contains('Token')));
        expect(source.headers!['X-Plex-Token'], _kToken);
      },
    );

    test('an absolute artwork path resolves to nothing', () async {
      final client = _client(CapturingHttpAdapter(response: {}));
      expect(
        client.imageFor('https://metadata-static.plex.tv/a/thumb.jpg'),
        isNull,
      );
      expect(client.imageFor(''), isNull);
    });
  });

  group('terminate', () {
    test('sends Session.id as the case-sensitive sessionId', () async {
      final adapter = CapturingHttpAdapter(response: '');
      final client = _client(adapter);

      await client.stopSession('u7k2m9x4qp1zvb3n', reason: 'Dinner time');

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastUri!.path, '/status/sessions/terminate');
      expect(adapter.lastUri!.queryParameters['sessionId'], 'u7k2m9x4qp1zvb3n');
      expect(adapter.lastUri!.queryParameters['reason'], 'Dinner time');
    });

    test(
      'a 401 without Plex Pass blames the subscription, not the token',
      () async {
        // Documented: 401 here means "the server does not have the feature
        // enabled". Reporting it as an expired token sends the user to re-paste a
        // credential that is working.
        final capabilities =
            jsonFixtureMap('plex/capabilities.json')['MediaContainer']
                as Map<String, dynamic>;
        capabilities['myPlexSubscription'] = false;

        final adapter = _RoutingAdapter([
          _Route('/status/sessions/terminate', status: 401, body: null),
          _Route('/', status: 200, body: {'MediaContainer': capabilities}),
        ]);

        await expectLater(
          _client(adapter).stopSession('u7k2m9x4qp1zvb3n'),
          throwsA(
            isA<PlexException>()
                .having((e) => e.message, 'message', contains('Plex Pass'))
                .having((e) => e.tokenIssue, 'tokenIssue', PlexTokenIssue.none),
          ),
        );
      },
    );

    test('a 401 with Plex Pass names the owner token, never clears it', () async {
      final adapter = _RoutingAdapter([
        _Route('/status/sessions/terminate', status: 401, body: null),
        _Route(
          '/',
          status: 200,
          body: jsonFixtureMap('plex/capabilities.json'),
        ),
      ]);

      await expectLater(
        _client(adapter).stopSession('u7k2m9x4qp1zvb3n'),
        throwsA(
          isA<PlexException>()
              // A home or shared user's token reads sessions and is refused
              // this; "the token is not the problem" was wrong for exactly them.
              .having((e) => e.message, 'message', contains('owner'))
              .having(
                (e) => e.message,
                'message',
                isNot(contains('not the problem')),
              )
              .having((e) => e.tokenIssue, 'tokenIssue', PlexTokenIssue.none),
        ),
      );
    });

    test('a 403 is a rejected session id, not a permission problem', () async {
      final adapter = _RoutingAdapter([
        _Route('/status/sessions/terminate', status: 403, body: null),
      ]);

      await expectLater(
        _client(adapter).stopSession('stale-id'),
        throwsA(
          isA<PlexException>()
              .having((e) => e.message, 'message', contains('session id'))
              .having((e) => e.reason, 'reason', ServiceFailureReason.notFound),
        ),
      );
    });
  });

  group('devices and playlists', () {
    test(
      'devices are read from the local server and tokens are discarded',
      () async {
        final adapter = CapturingHttpAdapter(
          response: const {
            'MediaContainer': {
              'Device': [
                {
                  'id': 7,
                  'name': 'Living room',
                  'clientIdentifier': 'client-1',
                  'product': 'Plex for Apple TV',
                  'platform': 'tvOS',
                  'provides': 'player,controller',
                  'createdAt': 1700000000,
                  'lastSeenAt': 1700003600,
                  'token': 'must-not-escape',
                },
              ],
            },
          },
        );

        final devices = await _client(adapter).getDevices();

        expect(adapter.lastUri!.path, '/devices');
        expect(devices.single.name, 'Living room');
        expect(devices.single.provides, ['player', 'controller']);
        expect(
          devices.single.lastSeenAt,
          DateTime.utc(2023, 11, 14, 23, 13, 20),
        );
      },
    );

    test('playlists preserve unknown counts as null', () async {
      final adapter = CapturingHttpAdapter(
        response: const {
          'MediaContainer': {
            'Metadata': [
              {
                'ratingKey': '55',
                'title': 'Friday night',
                'playlistType': 'video',
                'smart': 1,
                'duration': 7200000,
                'addedAt': 1700000000,
              },
            ],
          },
        },
      );

      final playlists = await _client(adapter).getPlaylists();

      expect(adapter.lastUri!.path, '/playlists');
      expect(playlists.single.title, 'Friday night');
      expect(playlists.single.smart, isTrue);
      expect(playlists.single.itemCount, isNull);
      expect(playlists.single.durationMs, 7200000);
    });

    test(
      'device and playlist failures remain visible to their providers',
      () async {
        final client = _client(_FailingAdapter());

        await expectLater(client.getDevices(), throwsA(isA<PlexException>()));
        await expectLater(client.getPlaylists(), throwsA(isA<PlexException>()));
      },
    );
  });

  group('remote failure', () {
    test('slot reads degrade, board reads and writes surface', () async {
      final client = _client(_FailingAdapter());

      expect(await client.probeVersion(), isNull);
      expect(await client.getIdentity(), isNull);
      // A whole surface each: Now playing, the shelf, On deck, the Server
      // section, an item's contents, a search lane, so a dark server is a
      // failure there, never "Nobody is watching", "Nothing part-watched",
      // "The server did not describe itself", "Nothing inside" or 0 results.
      await expectLater(
        client.getCapabilities(),
        throwsA(isA<PlexException>()),
      );
      await expectLater(client.getViewers(), throwsA(isA<PlexException>()));
      await expectLater(
        client.getChildren('41000'),
        throwsA(isA<PlexException>()),
      );
      await expectLater(client.search('inter'), throwsA(isA<PlexException>()));
      await expectLater(client.getSessions(), throwsA(isA<PlexException>()));
      await expectLater(client.getLibraries(), throwsA(isA<PlexException>()));
      await expectLater(
        client.getContinueWatching(),
        throwsA(isA<PlexException>()),
      );
      await expectLater(
        client.getSessionsOrThrow(),
        throwsA(isA<PlexException>()),
      );
      await expectLater(
        client.getLibrariesOrThrow(),
        throwsA(isA<PlexException>()),
      );
      expect(await client.getItem('20418'), isNull);
      expect(await client.getLibraryItemCount('1'), isNull);

      // Null, not an empty page: an empty page is a claim about the library
      // and this is a claim about the request.
      expect(await client.getLibraryItemsPage(libraryId: '1'), isNull);
      expect(
        (await client.getLibraryPage(libraryId: '1')).outcome,
        StreamPageOutcome.failed,
      );

      // Mutating actions report, so the UI can say what happened.
      await expectLater(
        client.stopSession('u7k2m9x4qp1zvb3n'),
        throwsA(
          isA<PlexException>().having(
            (e) => e.reason,
            'reason',
            ServiceFailureReason.unreachable,
          ),
        ),
      );
    });

    test(
      'a bad address that answers 200 with the wrong body is named',
      () async {
        final adapter = CapturingHttpAdapter(response: {'nope': true});
        await expectLater(
          _client(adapter).verifyCredential(),
          throwsA(
            isA<PlexException>().having(
              (e) => e.reason,
              'reason',
              ServiceFailureReason.notFound,
            ),
          ),
        );
        // And the sessions read says it could not read, rather than "nobody".
        await expectLater(
          _client(adapter).getSessions(),
          throwsA(isA<PlexException>()),
        );
      },
    );

    test('a request can be cancelled', () async {
      final token = CancelToken();
      final client = _client(CapturingHttpAdapter(response: {}));
      token.cancel('navigated away');

      await expectLater(
        client.getSessions(cancelToken: token),
        throwsA(isA<PlexException>()),
      );
      await expectLater(
        client.search('inter', cancelToken: token),
        throwsA(isA<PlexException>()),
      );
    });
  });
  group('getTitleKey', () {
    Map<String, dynamic> container(String type) => {
      'MediaContainer': {
        'size': 1,
        'Metadata': [
          {
            'ratingKey': '41000',
            'key': '/library/metadata/41000',
            'title': 'Sintel',
            'type': type,
            'Guid': [
              {'id': 'tmdb://45745'},
            ],
          },
        ],
      },
    };

    test('a movie names its page, read with its guids', () async {
      final adapter = CapturingHttpAdapter(response: container('movie'));
      expect(
        await _client(adapter).getTitleKey('41000'),
        const MediaKey.movie(45745),
      );
      expect(adapter.lastUri!.queryParameters['includeGuids'], '1');
    });

    test('an episode names no page: a session names its show', () async {
      final adapter = CapturingHttpAdapter(response: container('episode'));
      expect(await _client(adapter).getTitleKey('41000'), isNull);
    });
  });

  group('getSeriesKey', () {
    Map<String, dynamic> container(Map<String, dynamic> show) => {
      'MediaContainer': {
        'size': 1,
        'Metadata': [show],
      },
    };

    Map<String, dynamic> show(
      String ratingKey, {
      String type = 'show',
      List<String> guids = const [],
    }) => {
      'ratingKey': ratingKey,
      'key': '/library/metadata/$ratingKey',
      'title': 'Severance',
      'type': type,
      if (guids.isNotEmpty)
        'Guid': [
          for (final id in guids) {'id': id},
        ],
    };

    test('reads the show\'s own item with its guids, and names its page by '
        'TMDB\'s', () async {
      final adapter = CapturingHttpAdapter(
        response: container(
          show(
            '41000',
            guids: ['imdb://tt11280740', 'tmdb://95396', 'tvdb://371980'],
          ),
        ),
      );

      final key = await _client(adapter).getSeriesKey('41000');

      expect(key, const MediaKey.tv(95396));
      expect(adapter.callCount, 1);
      expect(adapter.lastUri!.path, '/library/metadata/41000');
      final query = adapter.lastUri!.queryParameters;
      // `Guid[]` only arrives when asked for; and the two flags that keep the
      // server from touching the files.
      expect(query['includeGuids'], '1');
      expect(query['checkFiles'], '0');
      expect(query['skipRefresh'], '1');
    });

    test('TVDB\'s when the server holds no TMDB id', () async {
      final adapter = CapturingHttpAdapter(
        response: container(show('41000', guids: ['tvdb://371980'])),
      );

      expect(
        await _client(adapter).getSeriesKey('41000'),
        const MediaKey.tvdb(371980),
      );
    });

    test('a show on a legacy agent is named by the agent\'s id', () async {
      final adapter = CapturingHttpAdapter(
        response: container({
          ...show('41000'),
          'guid': 'com.plexapp.agents.thetvdb://371980?lang=en',
        }),
      );

      expect(
        await _client(adapter).getSeriesKey('41000'),
        const MediaKey.tvdb(371980),
      );
    });

    test('no ids, no page', () async {
      final adapter = CapturingHttpAdapter(
        response: container(show('41000', guids: ['plex://show/5d9c08'])),
      );

      expect(await _client(adapter).getSeriesKey('41000'), isNull);
    });

    test('anything but the show asked for names no page', () async {
      final adapter = CapturingHttpAdapter(
        response: container(show('41000', guids: ['tmdb://95396'])),
      );
      // Another item answered, and a season in the show's place.
      expect(await _client(adapter).getSeriesKey('41999'), isNull);
      adapter.response = container(
        show('41000', type: 'season', guids: ['tmdb://95396']),
      );
      expect(await _client(adapter).getSeriesKey('41000'), isNull);
    });

    test('a server that did not answer names none, and says nothing', () async {
      final adapter = CapturingHttpAdapter(response: const {}, statusCode: 500);

      expect(await _client(adapter).getSeriesKey('41000'), isNull);
    });

    test('a request ended before it was answered names none', () async {
      final adapter = CapturingHttpAdapter(
        response: container(show('41000', guids: ['tmdb://95396'])),
      );
      final token = CancelToken()..cancel();

      expect(
        await _client(adapter).getSeriesKey('41000', cancelToken: token),
        isNull,
      );
      expect(adapter.callCount, 0);
    });
  });

  group('lookupByExternalId through the matcher', () {
    test(
      'an external id is turned into Plex\'s own guid, then found by it',
      () async {
        final adapter = _MatcherAdapter(
          matches: {'tmdb-603': 'plex://movie/5d776827880197001ec90904'},
          byPlexGuid: {'plex://movie/5d776827880197001ec90904': _matrixRow()},
        );

        final lookup = await _client(
          adapter,
        ).lookupByExternalId(tmdbId: '603', kind: StreamItemKind.movie);

        expect(lookup.outcome, StreamLookupOutcome.found);
        expect(lookup.item?.id, '2');
        final asked = adapter.pathed('/matches').single.uri.queryParameters;
        expect(asked['title'], 'tmdb-603');
        expect(asked['agent'], 'tv.plex.agents.movie');
        expect(
          adapter.pathed('/library/all').single.uri.queryParameters['guid'],
          'plex://movie/5d776827880197001ec90904',
        );
      },
    );

    test(
      'a title found without its Media reads its picture from the item',
      () async {
        final adapter = _MatcherAdapter(
          matches: {'tmdb-603': 'plex://movie/5d776827880197001ec90904'},
          byPlexGuid: {'plex://movie/5d776827880197001ec90904': _matrixRow()},
          metadata: {
            '2': {
              ..._matrixRow()..remove('Guid'),
              'Media': [
                {'width': 3840, 'height': 2160, 'videoResolution': '4k'},
              ],
            },
          },
        );

        final lookup = await _client(
          adapter,
        ).lookupByExternalId(tmdbId: '603', kind: StreamItemKind.movie);

        expect(lookup.outcome, StreamLookupOutcome.found);
        expect(lookup.item?.video?.resolution, '2160p');
        // The ids the match was verified by stay: the item read sends none.
        expect(lookup.item?.externalIds.tmdb, '603');
        expect(adapter.pathed('/library/metadata/2'), hasLength(1));
      },
    );

    test('Plex\'s own guid with no rows is not in the library', () async {
      final adapter = _MatcherAdapter(
        matches: {'tmdb-603': 'plex://movie/5d776827880197001ec90904'},
      );

      final lookup = await _client(
        adapter,
      ).lookupByExternalId(tmdbId: '603', kind: StreamItemKind.movie);

      expect(lookup.outcome, StreamLookupOutcome.notInLibrary);
    });

    test('a server with no library of the kind holds nothing', () async {
      final adapter = _MatcherAdapter(showSection: false);

      final lookup = await _client(
        adapter,
      ).lookupByExternalId(tvdbId: '81189', kind: StreamItemKind.series);

      expect(lookup.outcome, StreamLookupOutcome.notInLibrary);
      expect(adapter.pathed('/matches'), isEmpty);
    });

    test('a matcher that fails falls back to the direct probe, whose silence '
        'proves nothing', () async {
      final adapter = _MatcherAdapter(matchesStatus: 500);

      final lookup = await _client(
        adapter,
      ).lookupByExternalId(tmdbId: '603', kind: StreamItemKind.movie);

      expect(lookup.outcome, StreamLookupOutcome.notVerified);
      expect(
        adapter.pathed('/library/all').single.uri.queryParameters['guid'],
        'tmdb://603',
      );
    });

    test('libraries on the old agents are probed directly, and an empty '
        'answer is no claim', () async {
      final lookup = await _client(
        _GuidAdapter(const {}),
      ).lookupByExternalId(tmdbId: '603', kind: StreamItemKind.movie);

      expect(lookup.outcome, StreamLookupOutcome.notVerified);
    });

    test('the sections, the anchor and the guid are asked once', () async {
      final adapter = _MatcherAdapter(
        matches: {'tmdb-603': 'plex://movie/5d776827880197001ec90904'},
        byPlexGuid: {'plex://movie/5d776827880197001ec90904': _matrixRow()},
      );
      final client = _client(adapter);

      for (var i = 0; i < 2; i++) {
        await client.lookupByExternalId(
          tmdbId: '603',
          kind: StreamItemKind.movie,
        );
      }

      expect(adapter.pathed('/library/sections/1/all'), hasLength(1));
      expect(
        adapter.requests.where((r) => r.uri.path.endsWith('/library/sections')),
        hasLength(1),
      );
      expect(adapter.pathed('/matches'), hasLength(1));
      expect(adapter.pathed('/library/all'), hasLength(2));
    });
  });

  group('plexExternalIds', () {
    test('Guid[] first, the legacy attribute only for what it lacks', () {
      expect(
        plexExternalIds({
          'guid': 'com.plexapp.agents.imdb://tt0133093?lang=en',
          'Guid': [
            {'id': 'tmdb://603'},
            {'id': 'plex://movie/5d776825880197001ec967c9'},
          ],
        }),
        const StreamExternalIds(tmdb: '603', imdb: 'tt0133093'),
      );
    });

    test('an episode on the TVDB agent does not claim its series\' id', () {
      // `thetvdb://81189/1/1` names the SERIES 81189; recording it would let
      // the episode answer a Sonarr lookup for the show.
      expect(
        plexExternalIds({
          'guid': 'com.plexapp.agents.thetvdb://81189/1/1?lang=en',
        }),
        StreamExternalIds.none,
      );
    });
  });
}

/// Answers `/library/all` per `?guid=` value, and records every request. The
/// join probes one id at a time, so which ids were tried is the behaviour.
/// A film section and a show section on the agents before Plex's current
/// ones, whose items the matcher cannot be asked through.
const _legacySections = {
  'MediaContainer': {
    'size': 2,
    'Directory': [
      {
        'key': '1',
        'type': 'movie',
        'agent': 'com.plexapp.agents.themoviedb',
        'title': 'Movies',
      },
      {
        'key': '2',
        'type': 'show',
        'agent': 'com.plexapp.agents.thetvdb',
        'title': 'TV Shows',
      },
    ],
  },
};

/// Answers `?guid=` probes from [byGuid], over [_legacySections].
class _GuidAdapter implements HttpClientAdapter {
  _GuidAdapter(this.byGuid);

  final Map<String, Object> byGuid;

  final List<RequestOptions> requests = [];

  /// The direct `?guid=` probes, without the read of the sections.
  List<RequestOptions> get probes => [
    for (final request in requests)
      if (request.uri.queryParameters.containsKey('guid')) request,
  ];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = options.uri.path.endsWith('/library/sections')
        ? _legacySections
        : byGuid[options.uri.queryParameters['guid']] ??
              const {
                'MediaContainer': {'size': 0},
              };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}

/// The rows of one page, for the tests about the request a sort sends and
/// the rows it maps; what an empty or failed page says is
/// [StreamLibraryPage]'s, tested on [PlexClient.getLibraryPage].
extension on PlexClient {
  Future<List<StreamItem>> getLibraryItems({
    required String libraryId,
    StreamLibrarySort sort = StreamLibrarySort.name,
    bool unplayedOnly = false,
    String? viewerId,
    int startIndex = 0,
    int limit = kPlexLibraryPageSize,
  }) async => (await getLibraryPage(
    libraryId: libraryId,
    sort: sort,
    unplayedOnly: unplayedOnly,
    viewerId: viewerId,
    startIndex: startIndex,
    limit: limit,
  )).items;
}

/// The Matrix as `/library/all?guid=plex://…&includeGuids=1` returns it.
Map<String, dynamic> _matrixRow() => {
  'ratingKey': '2',
  'key': '/library/metadata/2',
  'guid': 'plex://movie/5d776827880197001ec90904',
  'title': 'The Matrix',
  'type': 'movie',
  'year': 1999,
  'Guid': [
    {'id': 'imdb://tt0133093'},
    {'id': 'tmdb://603'},
  ],
};

/// A server on Plex's current agents: a film section whose first item is
/// `10`, a show section (empty unless [showItem]), a matcher answering
/// [matches] by its `title=` (with [matchesStatus]), and the library filtered
/// by Plex's own guid from [byPlexGuid].
class _MatcherAdapter implements HttpClientAdapter {
  _MatcherAdapter({
    this.matches = const {},
    this.byPlexGuid = const {},
    this.matchesStatus = 200,
    this.showSection = true,
    this.metadata = const {},
  });

  /// `/library/metadata/{ratingKey}` answers, by rating key.
  final Map<String, Map<String, dynamic>> metadata;
  final Map<String, String> matches;
  final Map<String, Map<String, dynamic>> byPlexGuid;
  final int matchesStatus;
  final bool showSection;

  final List<RequestOptions> requests = [];

  List<RequestOptions> pathed(String path) => [
    for (final request in requests)
      if (request.uri.path.endsWith(path)) request,
  ];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    final query = options.uri.queryParameters;
    var status = 200;
    Object body;
    if (path.endsWith('/library/sections')) {
      body = {
        'MediaContainer': {
          'Directory': [
            {'key': '1', 'type': 'movie', 'agent': 'tv.plex.agents.movie'},
            if (showSection)
              {'key': '2', 'type': 'show', 'agent': 'tv.plex.agents.series'},
          ],
        },
      };
    } else if (path.endsWith('/library/sections/1/all')) {
      body = {
        'MediaContainer': {
          'size': 1,
          'Metadata': [
            {'ratingKey': '10', 'type': 'movie', 'title': 'Anchor'},
          ],
        },
      };
    } else if (path.endsWith('/matches')) {
      status = matchesStatus;
      final guid = matches[query['title']];
      body = {
        'MediaContainer': {
          'SearchResult': [
            if (guid != null)
              {'guid': guid, 'name': 'The Matrix', 'year': 1999},
          ],
        },
      };
    } else if (path.contains('/library/metadata/') &&
        !path.endsWith('/matches')) {
      final row = metadata[path.split('/').last];
      body = {
        'MediaContainer': {
          'size': row == null ? 0 : 1,
          'Metadata': [?row],
        },
      };
    } else {
      final row = byPlexGuid[query['guid']];
      body = {
        'MediaContainer': {
          'size': row == null ? 0 : 1,
          'Metadata': [?row],
        },
      };
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}
