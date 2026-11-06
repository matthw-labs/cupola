import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';

/// What `JellyfinDialect` pins, site by site: the routes, headers and queries
/// the shared client asks of it. `jellyfin_client_test.dart` pins the client
/// through the dialect from the outside; this one pins the dialect from the
/// inside, so the day a second dialect lands, a change to Jellyfin's wire
/// format shows up here and not as a mystery in a screen test.

const _dialect = JellyfinDialect();
const _device = (
  client: 'Cupola',
  device: 'macos',
  deviceId: 'DEVICE-ID-1',
  version: '0.8.0',
);
const _token = 'SECRET-KEY';
const _viewerId = '8c4f2a1e9b7d4c3a8f5e2d1c9b8a7f6e';
const _itemId = '3ca7ff1e0d9b4e2f8a6c5b4d3e2f1a09';

/// An API client over a stubbed socket, as the shared client builds one.
ApiClient _api(
  CapturingHttpAdapter adapter, {
  List<Interceptor>? interceptors,
}) {
  final api = ApiClient.authenticatedBy(
    baseUrl: 'https://jf.test',
    headers: const {},
    interceptors: interceptors == null ? null : (_) => interceptors,
  );
  api.dio.httpClientAdapter = adapter;
  addTearDown(api.close);
  return api;
}

/// A dialect that differs from Jellyfin's in the two ways the shared client
/// must honour without knowing which dialect it holds: a base path, and no
/// episode sort.
class _PrefixedDialect extends JellyfinDialect {
  const _PrefixedDialect();

  @override
  String get basePath => '/emby';

  @override
  String? get episodeSortBy => null;
}

void main() {
  group('identity', () {
    test('speaks for Jellyfin, from the root', () {
      expect(_dialect.service, ServiceKey.jellyfin);
      expect(_dialect.basePath, isEmpty);
    });

    test('a body with a Version came from a Jellyfin', () {
      expect(_dialect.isThisServer({'Version': '10.11.0'}), isTrue);
      expect(_dialect.isThisServer({'ServerName': 'x'}), isFalse);
      expect(_dialect.isThisServer(const {}), isFalse);
    });
  });

  group('credential', () {
    test('travels as the MediaBrowser Authorization header', () {
      final headers = _dialect.serviceHeaders(
        token: _token,
        device: _device,
        proxyHoldsAuthorization: false,
      );
      expect(headers, {
        'Authorization':
            'MediaBrowser Token="SECRET-KEY", Client="Cupola", '
            'Device="macos", DeviceId="DEVICE-ID-1", Version="0.8.0"',
      });
    });

    test('moves to X-Emby-Token when a proxy holds Authorization', () {
      final headers = _dialect.serviceHeaders(
        token: _token,
        device: _device,
        proxyHoldsAuthorization: true,
      );
      expect(headers, {'X-Emby-Token': _token});
    });

    test('adds no interceptor unless a proxy holds Authorization', () {
      expect(
        _dialect.interceptors(token: _token, proxyHoldsAuthorization: false),
        isEmpty,
      );
    });

    test('adds the token as ApiKey to every request behind a proxy', () async {
      final interceptors = _dialect.interceptors(
        token: _token,
        proxyHoldsAuthorization: true,
      );
      expect(interceptors, hasLength(1));

      final adapter = CapturingHttpAdapter(response: <String, dynamic>{});
      await _api(
        adapter,
        interceptors: interceptors,
      ).get('/System/Info', queryParameters: {'limit': 1});
      expect(adapter.lastUri!.queryParameters, {
        'limit': '1',
        'ApiKey': _token,
      });
    });
  });

  group('sessions', () {
    test('asks for the clients active in the last three minutes', () {
      expect(_dialect.sessionsQuery(), {'activeWithinSeconds': 180});
      expect(JellyfinDialect.activeWithinSeconds, 180);
    });
  });

  group('what the server did not do for us', () {
    test('Jellyfin applies the window itself, so the list is as it came', () {
      final raw = [
        {'Id': 'a', 'LastActivityDate': '2001-01-01T00:00:00Z'},
      ];
      expect(identical(_dialect.liveSessions(raw), raw), isTrue);
    });

    test('Jellyfin always sends the year, so none is asked for', () {
      expect(
        _dialect.browseFields,
        'PrimaryImageAspectRatio,Overview,ProviderIds',
      );
    });
  });

  group('users', () {
    test('lists GET /Users as a bare array', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/users.json'),
      );
      final users = await _dialect.users(_api(adapter));

      expect(adapter.lastUri!.path, '/Users');
      expect(adapter.lastUri!.hasQuery, isFalse);
      expect(users.map((user) => user.name), [
        'matt',
        'flatmate',
        'old-tablet',
      ]);
    });

    test('a refusal throws, it is not an empty list', () async {
      final adapter = CapturingHttpAdapter(response: const {}, statusCode: 403);
      expect(_dialect.users(_api(adapter)), throwsA(isA<DioException>()));
    });
  });

  group('credential kind (GET /Users/Me)', () {
    test('a 400 with no body is an API key', () async {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 400);
      final kind = await _dialect.credentialKind(_api(adapter));

      expect(adapter.lastUri!.path, '/Users/Me');
      expect(kind, JellyfinCredentialKind.apiKey);
    });

    test('a user answers with the policy that decides', () async {
      final admin = CapturingHttpAdapter(
        response: (jsonFixtureList('jellyfin/users.json').first),
      );
      expect(
        await _dialect.credentialKind(_api(admin)),
        JellyfinCredentialKind.administrator,
      );
      final member = CapturingHttpAdapter(
        response: (jsonFixtureList('jellyfin/users.json')[1]),
      );
      expect(
        await _dialect.credentialKind(_api(member)),
        JellyfinCredentialKind.user,
      );
    });

    test('anything else withholds nothing', () async {
      final adapter = CapturingHttpAdapter(response: '', statusCode: 401);
      expect(
        await _dialect.credentialKind(_api(adapter)),
        JellyfinCredentialKind.unknown,
      );
    });
  });

  group('the token user as the one viewer', () {
    test('reads GET /Users/Me', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/users.json')[1],
      );
      final viewers = await _dialect.tokenUserAsViewer(_api(adapter), '');

      expect(adapter.lastUri!.path, '/Users/Me');
      expect(viewers.map((viewer) => viewer.name), ['flatmate']);
    });

    test('a disabled user is nobody', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/users.json')[2],
      );
      expect(await _dialect.tokenUserAsViewer(_api(adapter), ''), isEmpty);
    });
  });

  group('one item by id', () {
    test('is GET /Items/{id} with the viewer, and no fields', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/item_movie.json'),
      );
      final item = await _dialect.rawItem(
        _api(adapter),
        _itemId,
        viewerId: _viewerId,
      );

      expect(adapter.lastUri!.path, '/Items/$_itemId');
      expect(adapter.lastUri!.queryParameters, {'userId': _viewerId});
      expect(item?['Id'], isNotNull);
    });

    test('without a viewer it sends no query at all', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/item_movie.json'),
      );
      await _dialect.rawItem(_api(adapter), _itemId);

      expect(adapter.lastUri!.path, '/Items/$_itemId');
      expect(adapter.lastUri!.hasQuery, isFalse);
    });

    test('a body that is not an object is no item', () async {
      final adapter = CapturingHttpAdapter(response: const <dynamic>[]);
      expect(await _dialect.rawItem(_api(adapter), _itemId), isNull);
    });
  });

  group('continue watching', () {
    test('a library is /UserItems/Resume with the viewer in the query', () {
      final request = _dialect.resume(
        userId: _viewerId,
        parentId: 'LIB',
        startIndex: 50,
        limit: 25,
        fields: 'F',
      );

      expect(request.path, '/UserItems/Resume');
      expect(request.query, {
        'userId': _viewerId,
        'parentId': 'LIB',
        'startIndex': 50,
        'limit': 25,
        'fields': 'F',
        'enableUserData': true,
        'excludeActiveSessions': true,
      });
      // The order is the wire order: a change here is a change in the URL.
      expect(request.query.keys.toList(), [
        'userId',
        'parentId',
        'startIndex',
        'limit',
        'fields',
        'enableUserData',
        'excludeActiveSessions',
      ]);
    });

    test('the whole server names no library and asks for video', () {
      final request = _dialect.resume(
        userId: _viewerId,
        limit: 12,
        fields: 'F',
        mediaTypes: 'Video',
      );

      expect(request.path, '/UserItems/Resume');
      expect(request.query.keys.toList(), [
        'userId',
        'limit',
        'fields',
        'enableUserData',
        'excludeActiveSessions',
        'mediaTypes',
      ]);
      expect(request.query['mediaTypes'], 'Video');
    });
  });

  group('next up', () {
    test('is /Shows/NextUp and never resurfaces a finished series', () {
      final request = _dialect.nextUp(
        userId: _viewerId,
        parentId: 'LIB',
        startIndex: 0,
        limit: 50,
        fields: 'F',
      );

      expect(request.path, '/Shows/NextUp');
      expect(request.query, {
        'userId': _viewerId,
        'parentId': 'LIB',
        'startIndex': 0,
        'limit': 50,
        'fields': 'F',
        'enableUserData': true,
        'enableRewatching': false,
      });
    });
  });

  group('search', () {
    test('is GET /Search/Hints, by flag and not by item type', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/search_hints.json'),
      );
      await _dialect.search(_api(adapter), term: 'inter', limit: 40);

      expect(adapter.lastUri!.path, '/Search/Hints');
      expect(adapter.lastUri!.queryParameters, {
        'searchTerm': 'inter',
        'limit': '40',
        'includeMedia': 'true',
        'includePeople': 'true',
        'includeStudios': 'false',
        'includeArtists': 'false',
      });
    });

    test('hands back each hit mapped, under the raw type it came in', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/search_hints.json'),
      );
      final hits = await _dialect.search(_api(adapter), term: 'x', limit: 40);

      expect(hits.map((hit) => hit.type), [
        'Movie',
        'Series',
        'Episode',
        'Person',
        'BoxSet',
      ]);
      expect(hits.first.item.title, 'Interstellar');
      expect(hits.first.item.kind, StreamItemKind.movie);
      // `Person` maps onto `other`: only the raw type tells it from a book.
      expect(hits[3].item.kind, StreamItemKind.other);
    });

    test('a bare array, the reverse proxy shape, is read too', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('jellyfin/search_hints.json')['SearchHints'],
      );
      final hits = await _dialect.search(_api(adapter), term: 'x', limit: 40);
      expect(hits, hasLength(5));
    });

    test('an object with no hints is no hits', () async {
      final adapter = CapturingHttpAdapter(response: {'Unexpected': true});
      expect(
        await _dialect.search(_api(adapter), term: 'x', limit: 1),
        isEmpty,
      );
    });

    test('a page that is not JSON throws, it is not no hits', () async {
      final adapter = CapturingHttpAdapter(response: 'not json');
      expect(
        _dialect.search(_api(adapter), term: 'x', limit: 1),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('libraries', () {
    test('are GET /Library/VirtualFolders as a bare array', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureList('jellyfin/virtual_folders.json'),
      );
      final folders = await _dialect.virtualFolders(_api(adapter));

      expect(adapter.lastUri!.path, '/Library/VirtualFolders');
      expect(adapter.lastUri!.hasQuery, isFalse);
      expect(folders, isNotEmpty);
      expect(folders.first.name, 'Films');
    });
  });

  group('episodes', () {
    test('are sorted in aired order', () {
      expect(_dialect.episodeSortBy, 'AiredEpisodeOrder');
    });
  });

  group('the client under a dialect with a base path', () {
    MediaBrowserClient client(
      CapturingHttpAdapter adapter, {
      MediaBrowserDialect dialect = const _PrefixedDialect(),
    }) {
      final client = MediaBrowserClient(
        dialect: dialect,
        baseUrl: 'https://jf.test',
        apiKey: _token,
        userId: _viewerId,
        deviceName: 'macos',
        deviceId: 'DEVICE-ID-1',
      );
      client.dio.httpClientAdapter = adapter;
      addTearDown(client.close);
      return client;
    }

    test('sends every request under it', () async {
      final adapter = CapturingHttpAdapter(response: const <dynamic>[]);
      await client(adapter).getUsers();

      expect(adapter.lastUri!.path, '/emby/Users');
    });

    test('builds artwork under it too, with the credential in a header', () {
      final source = client(
        CapturingHttpAdapter(),
      ).imageFor('/Items/$_itemId/Images/Primary?tag=abc', width: 300);

      final uri = Uri.parse(source!.url);
      expect(uri.path, '/emby/Items/$_itemId/Images/Primary');
      expect(uri.queryParameters, {'tag': 'abc', 'maxWidth': '300'});
      expect(source.url, isNot(contains(_token)));
      expect(source.headers?['Authorization'], startsWith('MediaBrowser '));
    });

    test('a bare id is completed under it', () {
      final source = client(CapturingHttpAdapter()).imageFor(_itemId);
      expect(
        Uri.parse(source!.url).path,
        '/emby/Items/$_itemId/Images/Primary',
      );
    });

    test('drops the episode sort a dialect says its server rejects', () async {
      final adapter = CapturingHttpAdapter(
        response: {'Items': const <dynamic>[], 'TotalRecordCount': 0},
      );
      await client(adapter).getEpisodes('SERIES');

      expect(adapter.lastUri!.path, '/emby/Shows/SERIES/Episodes');
      expect(adapter.lastUri!.queryParameters.containsKey('sortBy'), isFalse);
    });

    test('Jellyfin keeps the sort, and the root', () async {
      final adapter = CapturingHttpAdapter(
        response: {'Items': const <dynamic>[], 'TotalRecordCount': 0},
      );
      await client(
        adapter,
        dialect: const JellyfinDialect(),
      ).getEpisodes('SERIES');

      expect(adapter.lastUri!.path, '/Shows/SERIES/Episodes');
      expect(adapter.lastUri!.queryParameters['sortBy'], 'AiredEpisodeOrder');
    });
  });
}
