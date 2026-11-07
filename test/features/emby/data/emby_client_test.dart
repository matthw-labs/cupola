import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/emby/data/emby_client.dart';
import 'package:cupola/features/emby/data/emby_dialect.dart';
import 'package:cupola/features/jellyfin/data/media_browser_client.dart';
import 'package:cupola/features/jellyfin/data/media_browser_dialect.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';

/// Ids from the fixtures, recorded from a real Emby 4.10.2: item ids are short
/// numbers, user ids are 32 hex digits.
const _movieId = '13';
const _seriesId = '16';
const _viewerId = 'ce18a8c31c4f49f291677ac853d0fb12';
const _adminId = 'be67dc243fb0464eba6565434ac08870';
const _token = 'SECRET-KEY';

/// A moment 15 seconds after the live session in `sessions_active.json` last
/// reported (`2026-11-06T12:32:41Z`), so that session is inside the window.
final _justAfter = DateTime.utc(2026, 11, 6, 12, 32, 56);

/// An hour later: the same sessions, long since gone quiet.
final _anHourLater = DateTime.utc(2026, 11, 6, 13, 40);

EmbyClient _client(
  CapturingHttpAdapter adapter, {
  String userId = _viewerId,
  Map<String, String> accessHeaders = const {},
  DateTime? now,
}) {
  final client = EmbyClient(
    baseUrl: 'https://emby.test',
    apiKey: _token,
    userId: userId,
    accessHeaders: accessHeaders,
    now: () => now ?? _justAfter,
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

/// A 403 the way a household member's token gets one from the server itself.
CapturingHttpAdapter _refused() =>
    CapturingHttpAdapter(response: '', statusCode: 403);

void main() {
  group('the wire', () {
    test('every route sits under /emby', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/system_info_public.json'),
      );
      await _client(adapter).probeVersion();

      expect(
        adapter.lastUri!.toString(),
        startsWith('https://emby.test/emby/'),
      );
      expect(adapter.lastUri!.path, '/emby/System/Info/Public');
    });

    test('the key is X-Emby-Token, and Authorization is never sent', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('emby/sessions_active.json'),
      );
      await _client(adapter).getSessions();

      expect(_header(adapter, 'X-Emby-Token'), _token);
      expect(_header(adapter, 'Authorization'), isNull);
    });

    test('a proxy that holds Authorization changes nothing', () async {
      // The reason the token is never in `Authorization`: the connection's own
      // access can keep it for a gateway, and no `ApiKey` parameter is needed
      // to make room.
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('emby/sessions_active.json'),
      );
      await _client(
        adapter,
        accessHeaders: const {'Authorization': 'Basic cHJveHk6cHc='},
      ).getSessions();

      expect(_header(adapter, 'X-Emby-Token'), _token);
      expect(_header(adapter, 'Authorization'), 'Basic cHJveHk6cHc=');
      expect(adapter.lastUri!.queryParameters.containsKey('ApiKey'), isFalse);
    });

    test('the token stays out of every URL', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('emby/sessions_active.json'),
      );
      await _client(adapter).getSessions();

      expect(adapter.lastUri.toString(), isNot(contains(_token)));
    });
  });

  group('who is at the address', () {
    test(
      'probeVersion reads the anonymous route and names the version',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('emby/system_info_public.json'),
        );

        expect(await _client(adapter).probeVersion(), '4.10.2.0');
      },
    );

    test('a Jellyfin on the address is not an Emby', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/system_info_public.json'),
      );

      expect(await _client(adapter).probeVersion(), isNull);
    });

    test('a page that decodes to something is not an Emby', () async {
      final adapter = CapturingHttpAdapter(response: const {'app': 'nginx'});

      expect(await _client(adapter).probeVersion(), isNull);
    });

    test(
      'the credential check reads /System/Info and checks who answered',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('emby/system_info.json'),
        );

        expect(await _client(adapter).checkCredentialAndVersion(), '4.10.2.0');
        expect(adapter.lastUri!.path, '/emby/System/Info');
      },
    );

    test('a Jellyfin answering the credential check is named as one', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/system_info_public.json'),
      );

      await expectLater(
        _client(adapter).checkCredentialAndVersion(),
        throwsA(
          isA<WrongServiceAnswer>().having(
            (e) => e.answered,
            'answered',
            ServiceKey.jellyfin,
          ),
        ),
      );
    });

    test('a wrong key is refused, never read as answering', () async {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 401);

      expect(await _client(adapter).verifyCredential(), isFalse);
      await expectLater(
        _client(adapter).checkCredentialAndVersion(),
        throwsA(isA<DioException>()),
      );
    });

    test('a household member\'s token is valid, and narrower', () async {
      expect(await _client(_refused()).verifyCredential(), isTrue);
    });

    test('the server id is the one the public route names', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/system_info_public.json'),
      );

      expect(
        await _client(adapter).publicServerId(),
        'a88212fc366d449c8bbe2a34a9e4a91b',
      );
    });
  });

  group('which credential the slot holds', () {
    test('an answer from /Users/Query is an administrator\'s', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/users_query.json'),
      );

      expect(
        await _client(adapter).getCredentialKind(),
        JellyfinCredentialKind.administrator,
      );
      expect(adapter.lastUri!.path, '/emby/Users/Query');
      expect(adapter.lastUri!.queryParameters['limit'], '1');
    });

    test('a 403 is a household member\'s token', () async {
      final kind = await _client(_refused()).getCredentialKind();

      expect(kind, JellyfinCredentialKind.user);
      expect(kind.lacksAdministrator, isTrue);
    });

    test('a gateway\'s 403 is not the member\'s refusal', () async {
      final client = _client(_refused());
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 403),
              error: const AccessGatewayAnswer(
                kind: AccessGatewayKind.cloudflareAccess,
                credentialsSent: false,
                gatewayHost: 'team.cloudflareaccess.com',
                serviceHost: 'emby.test',
              ),
            ),
          ),
        ),
      );

      expect(await client.getCredentialKind(), JellyfinCredentialKind.unknown);
    });

    test('anything else withholds nothing', () async {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 500);

      final kind = await _client(adapter).getCredentialKind();

      expect(kind, JellyfinCredentialKind.unknown);
      expect(kind.lacksAdministrator, isFalse);
    });
  });

  group('sessions', () {
    test('asks for no window and keeps only what is playing', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('emby/sessions_active.json'),
      );
      final sessions = await _client(adapter).getSessions();

      expect(adapter.lastUri!.path, '/emby/Sessions');
      expect(adapter.lastUri!.hasQuery, isFalse);
      // The API key's own row is in the answer, with nothing playing.
      expect(sessions, hasLength(1));
      expect(sessions.single.title, 'The Matrix');
      expect(sessions.single.userName, 'anna');
    });

    test('a session that has gone quiet for three minutes is gone', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('emby/sessions_active.json'),
      );

      expect(await _client(adapter, now: _anHourLater).getSessions(), isEmpty);
    });

    test('the window is the one Jellyfin is asked for', () {
      final raw = [
        {'Id': 'live', 'LastActivityDate': '2026-11-06T12:30:00Z'},
        {'Id': 'quiet', 'LastActivityDate': '2026-11-06T12:00:00Z'},
        {'Id': 'undated'},
        {'Id': 'garbled', 'LastActivityDate': 'yesterday'},
      ];
      final at = DateTime.utc(2026, 11, 6, 12, 32, 59);
      final kept = EmbyDialect(now: () => at).liveSessions(raw)! as List;

      // 179 seconds is in; 33 minutes is out; a date that cannot be read is
      // kept, because dropping it could hide a stream that is playing.
      expect(kept.map((s) => (s as Map)['Id']), ['live', 'undated', 'garbled']);
      expect(JellyfinDialect.activeWithinSeconds, 180);
      expect(const EmbyDialect().liveSessions('not a list'), 'not a list');
    });

    test(
      'pause, unpause and a message use the shared routes under /emby',
      () async {
        final adapter = CapturingHttpAdapter(response: '', statusCode: 204);
        final client = _client(adapter);

        await client.pauseSession('abc');
        expect(adapter.lastUri!.path, '/emby/Sessions/abc/Playing/Pause');
        await client.unpauseSession('abc');
        expect(adapter.lastUri!.path, '/emby/Sessions/abc/Playing/Unpause');
        await client.stopSession('abc');
        expect(adapter.lastUri!.path, '/emby/Sessions/abc/Playing/Stop');

        await client.sendMessage('abc', text: 'Dinner in ten');
        expect(adapter.lastUri!.path, '/emby/Sessions/abc/Message');
        expect((adapter.lastBody as Map)['Text'], 'Dinner in ten');
      },
    );
  });

  group('libraries', () {
    test(
      'come from /Library/VirtualFolders/Query, envelope unwrapped',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('emby/virtual_folders_query.json'),
        );
        final libraries = await _client(adapter).getLibraries();

        expect(adapter.lastUri!.path, '/emby/Library/VirtualFolders/Query');
        expect(libraries.map((l) => l.name), ['Movies', 'Shows']);
        expect(libraries.map((l) => l.id), ['3', '5']);
        expect(libraries.map((l) => l.kind), [
          StreamLibraryKind.movies,
          StreamLibraryKind.shows,
        ]);
      },
    );

    test('a bare list from a proxy that unwraps is read too', () async {
      final adapter = CapturingHttpAdapter(
        response: (jsonFixtureMap('emby/virtual_folders_query.json'))['Items'],
      );

      expect(await _client(adapter).getLibraries(), hasLength(2));
    });
  });

  group('users', () {
    test('come from /Users/Query with a limit, envelope unwrapped', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/users_query.json'),
      );
      final viewers = await _client(adapter).getViewers();

      expect(adapter.lastUri!.path, '/emby/Users/Query');
      expect(adapter.lastUri!.queryParameters['limit'], '1000');
      expect(viewers.map((v) => v.name), ['admin', 'anna']);
      expect(viewers.map((v) => v.id), [_adminId, _viewerId]);
    });

    test('the administration read keeps its policy fields', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/users_query.json'),
      );
      final users = await _client(adapter).getUsers();

      expect(users.first.isAdministrator, isTrue);
      expect(users.last.isAdministrator, isFalse);
      expect(users.last.lastActivityAt, isNotNull);
    });

    test(
      'a token refused the list is the viewer the connection holds',
      () async {
        final anna =
            (jsonFixtureMap('emby/users_query.json')['Items'] as List).last;
        // `/Users/Query` is refused, then the user is read by id.
        final client = _client(
          _RoutedAdapter({
            '/emby/Users/Query': (statusCode: 403, body: ''),
            '/emby/Users/$_viewerId': (statusCode: 200, body: anna),
          }),
        );

        final viewers = await client.getViewers();

        expect(viewers.map((v) => v.name), ['anna']);
        expect(viewers.single.id, _viewerId);
      },
    );

    test('and with none held, the token\'s own sessions name her', () async {
      final anna =
          (jsonFixtureMap('emby/users_query.json')['Items'] as List).last;
      // A member's `/Sessions` lists her own sessions beside key sessions
      // that have no user (measured on 4.10.2).
      final client = _client(
        _RoutedAdapter({
          '/emby/Users/Query': (statusCode: 403, body: ''),
          '/emby/Sessions': (
            statusCode: 200,
            body: [
              {'Id': 's1', 'UserId': _viewerId, 'UserName': 'anna'},
              {'Id': 's2', 'UserId': _viewerId, 'UserName': 'anna'},
              {'Id': 's3', 'Client': 'Cupola'},
            ],
          ),
          '/emby/Users/$_viewerId': (statusCode: 200, body: anna),
        }),
        userId: '',
      );

      final viewers = await client.getViewers();

      expect(viewers.map((v) => v.name), ['anna']);
      expect(viewers.single.id, _viewerId);
    });

    test('and nobody when the sessions name no one or several', () async {
      Future<List<Object?>> viewersFor(
        List<Map<String, Object?>> sessions,
      ) async {
        final client = _client(
          _RoutedAdapter({
            '/emby/Users/Query': (statusCode: 403, body: ''),
            '/emby/Sessions': (statusCode: 200, body: sessions),
          }),
          userId: '',
        );
        return client.getViewers();
      }

      expect(await viewersFor([]), isEmpty);
      expect(
        await viewersFor([
          {'Id': 's3', 'Client': 'Cupola'},
        ]),
        isEmpty,
      );
      expect(
        await viewersFor([
          {'Id': 's1', 'UserId': _viewerId},
          {'Id': 's2', 'UserId': _adminId},
        ]),
        isEmpty,
      );
    });
  });

  group('one item', () {
    test(
      'with a viewer: the user\'s own route, watch state included',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('emby/item_movie.json'),
        );
        final item = await _client(adapter).getItem(_movieId);

        expect(adapter.lastUri!.path, '/emby/Users/$_viewerId/Items/$_movieId');
        expect(item!.title, 'The Matrix');
        expect(item.kind, StreamItemKind.movie);
        expect(item.year, 1999);
      },
    );

    test('without one: /Items?Ids= with the fields the page reads', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/items_by_ids.json'),
      );
      final item = await _client(adapter, userId: '').getItem(_movieId);

      // `/Items/{id}` is a 404 on Emby, which is why neither route is it.
      expect(adapter.lastUri!.path, '/emby/Items');
      final query = adapter.lastUri!.queryParameters;
      expect(query['ids'], _movieId);
      expect(query['fields'], contains('MediaSources'));
      expect(query['fields'], contains('MediaStreams'));
      expect(query['fields'], contains('Overview'));
      expect(query['fields'], contains('ProviderIds'));
      expect(query.containsKey('userId'), isFalse);
      expect(item!.title, 'The Matrix');
    });

    test('an id the server does not know is nothing', () async {
      final adapter = CapturingHttpAdapter(
        response: const {'Items': <Object?>[], 'TotalRecordCount': 0},
      );

      expect(await _client(adapter, userId: '').getItem('999'), isNull);
    });
  });

  group('browsing', () {
    test(
      'a library asks for the year, which Emby leaves out unless asked',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('emby/items_movies_page.json'),
        );
        final page = await _client(adapter).getLibraryPage(libraryId: '3');

        expect(adapter.lastUri!.path, '/emby/Items');
        expect(
          adapter.lastUri!.queryParameters['fields'],
          contains('ProductionYear'),
        );
        expect(page.items, isNotEmpty);
        expect(page.items.first.title, 'Big Buck Bunny');
      },
    );

    for (final (sort, sortBy, sortOrder) in [
      (StreamLibrarySort.name, 'SortName', 'Ascending'),
      (
        StreamLibrarySort.dateAdded,
        'DateCreated,SortName',
        'Descending,Ascending',
      ),
      (
        StreamLibrarySort.year,
        'ProductionYear,SortName',
        'Descending,Ascending',
      ),
    ]) {
      test('${sort.name} sorts by $sortBy under /emby/Items', () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('emby/items_movies_page.json'),
        );
        await _client(
          adapter,
          userId: '',
        ).getLibraryPage(libraryId: '3', sort: sort);

        expect(adapter.lastUri!.path, '/emby/Items');
        final query = adapter.lastUri!.queryParameters;
        expect(query['parentId'], '3');
        expect(query['sortBy'], sortBy);
        expect(query['sortOrder'], sortOrder);
        // The whole shelf needs no viewer.
        expect(query.containsKey('userId'), isFalse);
        expect(query.containsKey('isPlayed'), isFalse);
      });
    }

    test('unplayedOnly adds isPlayed=false for the viewer', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/items_movies_page.json'),
      );
      await _client(adapter).getLibraryPage(libraryId: '3', unplayedOnly: true);

      expect(adapter.lastUri!.path, '/emby/Items');
      final query = adapter.lastUri!.queryParameters;
      expect(query['isPlayed'], 'false');
      expect(query['userId'], _viewerId);
    });

    test('unplayedOnly with nobody chosen asks for one', () async {
      final adapter = CapturingHttpAdapter(response: const {});
      final page = await _client(
        adapter,
        userId: '',
      ).getLibraryPage(libraryId: '3', unplayedOnly: true);

      expect(page.needsViewer, isTrue);
      expect(adapter.callCount, 0);
    });

    test(
      'continue watching is /Users/{id}/Items/Resume, with the user in the path',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('emby/resume_items.json'),
        );
        final items = await _client(adapter).getContinueWatching();

        expect(adapter.lastUri!.path, '/emby/Users/$_viewerId/Items/Resume');
        final query = adapter.lastUri!.queryParameters;
        // Neither is a parameter of this route.
        expect(query.containsKey('userId'), isFalse);
        expect(query.containsKey('excludeActiveSessions'), isFalse);
        expect(query['mediaTypes'], 'Video');
        expect(items.single.title, 'Big Buck Bunny');
        expect(items.single.resumeOffsetMs, 40000);
      },
    );

    test('next up is /Shows/NextUp across the server, without the '
        'rewatching switch', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/next_up.json'),
      );
      final items = await _client(adapter).getNextUp(count: 8);

      expect(adapter.lastUri!.path, '/emby/Shows/NextUp');
      final query = adapter.lastUri!.queryParameters;
      expect(query['userId'], _viewerId);
      expect(query.containsKey('parentId'), isFalse);
      expect(query['limit'], '8');
      expect(query.containsKey('enableRewatching'), isFalse);
      expect(items, isEmpty);
    });

    test('next up with nobody chosen throws and asks nothing', () async {
      final adapter = CapturingHttpAdapter(response: const {});
      await expectLater(
        _client(adapter, userId: '').getNextUp(count: 8),
        throwsA(isA<JellyfinViewerRequired>()),
      );
      expect(adapter.callCount, 0);
    });

    test('recently added is the newest content of movies and series, '
        'with no viewer', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/items_movies_page.json'),
      );
      final items = await _client(
        adapter,
        userId: '',
      ).getRecentlyAdded(count: 12);

      expect(adapter.lastUri!.path, '/emby/Items');
      final query = adapter.lastUri!.queryParameters;
      expect(query['recursive'], 'true');
      expect(query['includeItemTypes'], 'Movie,Series');
      expect(query['sortBy'], 'DateLastContentAdded,SortName');
      expect(query['sortOrder'], 'Descending,Ascending');
      expect(query['limit'], '12');
      expect(query.containsKey('userId'), isFalse);
      expect(items.first.title, 'Big Buck Bunny');
    });
  });

  group('recently watched', () {
    test(
      'asks for the played date, which a list read leaves out unless named',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('emby/items_played.json'),
        );

        final watched = await _client(adapter).getRecentlyWatched();

        expect(
          adapter.lastUri!.queryParameters['fields'],
          contains('UserDataLastPlayedDate'),
        );
        expect(
          [for (final w in watched) w.item.title],
          ['The Matrix', 'Fight Club'],
        );
        expect(watched.first.playedAt, DateTime.utc(2026, 11, 5, 20, 15));
      },
    );
  });

  group('episodes', () {
    test('are never sorted by a word Emby answers with a 500', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/episodes.json'),
      );
      final episodes = await _client(adapter).getEpisodes(_seriesId);

      expect(adapter.lastUri!.path, '/emby/Shows/$_seriesId/Episodes');
      expect(adapter.lastUri!.queryParameters.containsKey('sortBy'), isFalse);
      expect(adapter.lastUri.toString(), isNot(contains('AiredEpisodeOrder')));
      expect(episodes, hasLength(2));
    });

    test(
      'a series lists its seasons, and no request carries the word',
      () async {
        final adapter = CapturingHttpAdapter(
          response: '',
          byPath: {
            '/Users/$_viewerId/Items/$_seriesId': jsonFixtureMap(
              'emby/item_series.json',
            ),
            '/Shows/$_seriesId/Seasons': jsonFixtureMap('emby/seasons.json'),
          },
        );
        final seasons = await _client(adapter).getChildren(_seriesId);

        expect(seasons.single.title, 'Season 1');
        expect(adapter.lastUri!.path, '/emby/Shows/$_seriesId/Seasons');
      },
    );
  });

  group('search', () {
    test(
      'is the item query with a search term, typed by what answered',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('emby/items_search.json'),
        );
        final groups = await _client(adapter).search('matrix');

        expect(adapter.lastUri!.path, '/emby/Items');
        final query = adapter.lastUri!.queryParameters;
        expect(query['searchTerm'], 'matrix');
        expect(query['recursive'], 'true');
        expect(
          query['includeItemTypes'],
          'Movie,Series,Episode,MusicAlbum,Book',
        );
        expect(groups.map((g) => g.label).take(6).toList(), [
          'Movies',
          'Shows',
          'Episodes',
          'Albums',
          'Books',
          'People',
        ]);
        expect(groups.first.items.single.title, 'The Matrix');
        expect(groups.skip(1).every((g) => g.items.isEmpty), isTrue);
      },
    );
  });

  group('lookups by external id', () {
    test('ask /Items by provider id, under /emby', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/items_movies_page.json'),
      );
      await _client(
        adapter,
      ).lookupByExternalId(tmdbId: '603', kind: StreamItemKind.movie);

      expect(adapter.lastUri!.path, '/emby/Items');
      expect(
        adapter.lastUri!.queryParameters['anyProviderIdEquals'],
        'tmdb.603',
      );
    });
  });

  group('artwork', () {
    test('is addressed under /emby, with the key in a header', () {
      final source = _client(
        CapturingHttpAdapter(response: const {}),
      ).imageFor('/Items/$_movieId/Images/Primary?tag=abc123', width: 400);

      expect(
        source!.url,
        'https://emby.test/emby/Items/$_movieId/Images/Primary'
        '?tag=abc123&maxWidth=400',
      );
      expect(source.url, isNot(contains(_token)));
      expect(source.headers, {'X-Emby-Token': _token});
    });

    test('a bare id is that item\'s primary image, under /emby too', () {
      final source = _client(
        CapturingHttpAdapter(response: const {}),
      ).imageFor(_movieId);

      expect(
        source!.url,
        'https://emby.test/emby/Items/$_movieId/Images/Primary',
      );
    });

    test('an absolute URL is handed back without the key', () {
      final source = _client(
        CapturingHttpAdapter(response: const {}),
      ).imageFor('https://images.example.com/poster.jpg');

      expect(source!.headers, isNull);
    });
  });

  group('administration surfaces', () {
    test('devices come from the paged /Devices envelope', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('emby/devices.json'),
      );
      final devices = await _client(adapter).getDevices();

      expect(adapter.lastUri!.path, '/emby/Devices');
      expect(devices.map((d) => d.name), contains('Living room'));
    });

    test('scheduled tasks come from /ScheduledTasks', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('emby/scheduled_tasks.json'),
      );
      final tasks = await _client(adapter).getScheduledTasks();

      expect(adapter.lastUri!.path, '/emby/ScheduledTasks');
      expect(tasks, isNotEmpty);
    });
  });

  group('the dialect', () {
    const dialect = EmbyDialect();

    test('speaks for Emby from /emby', () {
      expect(dialect.service, ServiceKey.emby);
      expect(dialect.basePath, '/emby');
      expect(dialect.episodeSortBy, isNull);
      expect(dialect.sessionsQuery(), isEmpty);
    });

    test('recognises a real Emby and nothing else', () {
      expect(
        dialect.isThisServer(jsonFixtureMap('emby/system_info_public.json')),
        isTrue,
      );
      expect(
        dialect.isThisServer(jsonFixtureMap('emby/system_info.json')),
        isTrue,
      );
      expect(
        dialect.isThisServer(
          jsonFixtureMap('jellyfin/system_info_public.json'),
        ),
        isFalse,
      );
      expect(dialect.isThisServer(const {}), isFalse);
      expect(
        identifyProbeAnswer(
          ServiceKey.emby,
          jsonFixtureMap('emby/system_info_public.json'),
        ),
        ProbeIdentity.matches,
      );
    });
  });
}

typedef _Answer = ({int statusCode, Object? body});

/// A transport that answers by exact request path, for the one read that
/// needs two different answers in a row.
class _RoutedAdapter extends CapturingHttpAdapter {
  _RoutedAdapter(this.routes);

  final Map<String, _Answer> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final answer = routes[options.uri.path];
    statusCode = answer?.statusCode ?? 404;
    response = answer?.body ?? '';
    byPath = null;
    return super.fetch(options, requestStream, cancelFuture);
  }
}
