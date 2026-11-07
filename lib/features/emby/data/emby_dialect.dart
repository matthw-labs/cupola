import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/jellyfin/data/media_browser_dialect.dart';
import 'package:cupola/features/jellyfin/data/media_browser_isolate.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_item_mapper.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// Emby 4.10, as measured on a real server (`test/fixtures/emby/` holds what it
/// answered), where it parts from Jellyfin.
///
/// Emby is the older of the two and Jellyfin is a fork of it, so most routes
/// are the same. What differs is what this class says, and each member names
/// the measurement it stands on, because the first reading of Emby's API (its
/// OpenAPI file) was wrong in several places a server then corrected:
///
///  * every route sits under `/emby`; the root answers too, but `/emby` is
///    what the API documents and what Emby's own clients send;
///  * the credential is `X-Emby-Token`, always. `Authorization` stays free for
///    a proxy in front, as it does on Jellyfin when a proxy holds it;
///  * an API key has no user, and there is no `/Users/Me` (it answers 500);
///  * item ids are short numbers (`"15"`), not GUIDs;
///  * a `SortBy` the server does not know is a **500**, not an ignored
///    parameter, so no word is sent that was not measured.
class EmbyDialect implements MediaBrowserDialect {
  /// [now] is how a quiet session is told from a live one; a test passes its
  /// own so a captured answer does not age.
  const EmbyDialect({DateTime Function() now = DateTime.now}) : _now = now;

  final DateTime Function() _now;

  /// How many users one `/Users/Query` is asked for. The route pages, and a
  /// household is tens; this is a ceiling a server never meets, so the
  /// viewer picker never needs a second page.
  static const int usersLimit = 1000;

  /// What `/Items?Ids=` is asked for when there is no viewer to read the item
  /// as: that route returns the thin list shape unless told, and the item page
  /// needs the synopsis, the ids that name its title and the file's streams.
  static const String _rawItemFields =
      'PrimaryImageAspectRatio,Overview,ProviderIds,ProductionYear,'
      'MediaSources,MediaStreams';

  @override
  ServiceKey get service => ServiceKey.emby;

  @override
  String get basePath => '/emby';

  /// Only the token. Emby reads `X-Emby-Token` on every route, so there is
  /// nothing to hand `Authorization` and nothing a proxy's password could
  /// collide with ([proxyHoldsAuthorization] changes nothing).
  @override
  Map<String, String> serviceHeaders({
    required String token,
    required MediaBrowserDevice device,
    required bool proxyHoldsAuthorization,
  }) => {'X-Emby-Token': token};

  @override
  List<Interceptor> interceptors({
    required String token,
    required bool proxyHoldsAuthorization,
  }) => const <Interceptor>[];

  /// Emby sends no `ProductName` and a `LocalAddresses` list; see
  /// [identifyProbeAnswer]. A Jellyfin on the address names itself and is
  /// refused, and so is a web page that decoded to something.
  @override
  bool isThisServer(Map<String, dynamic> publicInfo) =>
      identifyProbeAnswer(ServiceKey.emby, publicInfo) is ProbeMatches &&
      JellyfinPublicSystemInfo.fromJson(publicInfo).isJellyfin;

  /// Nothing to ask: `/Sessions` takes no activity window, so the window is
  /// applied to the answer ([liveSessions]).
  @override
  Map<String, dynamic> sessionsQuery() => const {};

  /// A client that has not reported in for [JellyfinDialect.activeWithinSeconds]
  /// is gone, the window Jellyfin is asked for.
  ///
  /// `/Sessions` lists every client that has ever connected and not been
  /// reaped, so without this a phone that watched last Tuesday is a live row
  /// for as long as it sits there with its last item. A session whose date is
  /// missing or unreadable is kept: dropping what cannot be dated would hide a
  /// stream that is playing.
  @override
  Object? liveSessions(Object? raw) {
    if (raw is! List) return raw;
    final cutoff = _now().toUtc().subtract(
      const Duration(seconds: JellyfinDialect.activeWithinSeconds),
    );
    return [
      for (final session in raw)
        if (_isLive(session, cutoff)) session,
    ];
  }

  static bool _isLive(Object? session, DateTime cutoff) {
    if (session is! Map) return true;
    final raw = session['LastActivityDate'];
    final at = raw is String ? DateTime.tryParse(raw) : null;
    return at == null || !at.toUtc().isBefore(cutoff);
  }

  /// Emby's `ProductionYear` is left out of a list unless asked for, where
  /// Jellyfin always sends it; a poster without its year is a worse poster.
  /// `UserDataLastPlayedDate` is the same story, measured on 4.10.2: a list
  /// read leaves `UserData.LastPlayedDate` out unless it is named, and without
  /// the date "Recently watched" drops every row and reads empty.
  @override
  String get browseFields =>
      'PrimaryImageAspectRatio,Overview,ProviderIds,ProductionYear,'
      'UserDataLastPlayedDate';

  /// `GET /Users/Query`, which pages: `{Items, TotalRecordCount}`. (`/Users`
  /// answers a bare list too, but it is the deprecated spelling.)
  @override
  Future<List<JellyfinUserDto>> users(ApiClient api) async {
    final response = await api.get(
      '/Users/Query',
      queryParameters: const {'limit': usersLimit},
    );
    return mapInIsolate(_itemsOf(response.data), jellyfinUsersFromJson);
  }

  /// There is no `/Users/Me` to ask, so the kind is read from what the token
  /// may do: `/Users/Query` answers an API key and an administrator's token,
  /// and refuses a household member's with a 403. A key and an administrator
  /// read the same on this server, so both are
  /// [JellyfinCredentialKind.administrator]; anything that is not an answer
  /// or a 403 is [JellyfinCredentialKind.unknown], so a failure never
  /// withholds a tab that might have worked.
  @override
  Future<JellyfinCredentialKind> credentialKind(ApiClient api) async {
    try {
      final response = await api.get(
        '/Users/Query',
        queryParameters: const {'limit': 1},
      );
      final code = response.statusCode ?? 0;
      return code >= 200 && code < 300
          ? JellyfinCredentialKind.administrator
          : JellyfinCredentialKind.unknown;
    } on DioException catch (e) {
      // A 403 from a gateway in front of Emby is not Emby's refusal, so it
      // says nothing about the token.
      return e.response?.statusCode == 403 && e.error is! AccessGatewayAnswer
          ? JellyfinCredentialKind.user
          : JellyfinCredentialKind.unknown;
    } catch (_) {
      return JellyfinCredentialKind.unknown;
    }
  }

  /// A token that cannot list users cannot say who it is either, so the one
  /// person it can be is the viewer the connection already holds, read by id
  /// (`GET /Users/{id}`).
  ///
  /// When none is held, the token is asked who it is through `/Sessions`: a
  /// member's token lists her own sessions (with `UserId`) beside the key
  /// sessions that have no user. Exactly one distinct user there is her; none
  /// or several is nobody offered, because guessing would show someone else's
  /// shelves.
  @override
  Future<List<StreamViewer>> tokenUserAsViewer(
    ApiClient api,
    String userId,
  ) async {
    var id = userId;
    if (id.isEmpty) {
      final sessions = await api.get('/Sessions');
      final data = sessions.data;
      final ids = <String>{
        if (data is List)
          for (final session in data.whereType<Map>())
            if (session['UserId'] is String &&
                (session['UserId'] as String).isNotEmpty)
              session['UserId'] as String,
      };
      if (ids.length != 1) return const [];
      id = ids.single;
    }
    final response = await api.get('/Users/$id');
    final data = response.data;
    if (data is! Map) return const [];
    final user = JellyfinUserDto.fromJson(data.cast<String, dynamic>());
    if (user.isDisabled || user.id.isEmpty) return const [];
    return [user.toStreamViewer()];
  }

  /// `GET /Items/{id}` is a **404** on Emby, so the item is read by the
  /// route that has it.
  ///
  /// With a viewer, `/Users/{viewer}/Items/{id}`: the whole item with that
  /// person's `UserData`. Without one, `/Items?Ids={id}`, which needs no user
  /// but answers the thin list shape, so the fields the page reads are asked
  /// for by name; the answer is the one element of `Items`.
  @override
  Future<Map<String, dynamic>?> rawItem(
    ApiClient api,
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    final viewer = viewerId ?? '';
    if (viewer.isNotEmpty) {
      final response = await api.get(
        '/Users/$viewer/Items/$itemId',
        cancelToken: cancelToken,
      );
      final data = response.data;
      return data is Map ? data.cast<String, dynamic>() : null;
    }
    final response = await api.get(
      '/Items',
      queryParameters: {'ids': itemId, 'fields': _rawItemFields},
      cancelToken: cancelToken,
    );
    final items = _itemsOf(response.data);
    final first = items is List && items.isNotEmpty ? items.first : null;
    return first is Map ? first.cast<String, dynamic>() : null;
  }

  /// `/Users/{userId}/Items/Resume`: the user is in the path, and the route
  /// takes neither a `userId` query nor `excludeActiveSessions`, so what a
  /// person is watching this minute stays in their own row until the session
  /// ends.
  @override
  MediaBrowserRequest resume({
    required String userId,
    required int limit,
    required String fields,
    String? parentId,
    int? startIndex,
    String? mediaTypes,
  }) => (
    path: '/Users/$userId/Items/Resume',
    query: {
      'parentId': ?parentId,
      'startIndex': ?startIndex,
      'limit': limit,
      'fields': fields,
      'enableUserData': true,
      'mediaTypes': ?mediaTypes,
    },
  );

  /// `/Shows/NextUp` as on Jellyfin, without `enableRewatching`, which Emby
  /// does not have: its next-up never resurfaces a finished series anyway.
  @override
  MediaBrowserRequest nextUp({
    required String userId,
    required int limit,
    required String fields,
    String? parentId,
    int startIndex = 0,
  }) => (
    path: '/Shows/NextUp',
    query: {
      'userId': userId,
      'parentId': ?parentId,
      'startIndex': startIndex,
      'limit': limit,
      'fields': fields,
      'enableUserData': true,
    },
  );

  /// `/Search/Hints` answers `[]` on Emby 4.10 even where items match, so the
  /// search is the item query with a `searchTerm`.
  ///
  /// The types are named in `includeItemTypes` (this route honours the filter,
  /// unlike the hints) and each hit keeps the `Type` it arrived under, which
  /// is what the bands are cut on. **People are not searched**: they live
  /// behind another route, and the band stays on the strip, empty, as it
  /// does for a Jellyfin with no one by that name.
  @override
  Future<List<MediaBrowserSearchHit>> search(
    ApiClient api, {
    required String term,
    required int limit,
    CancelToken? cancelToken,
  }) async {
    final response = await api.get(
      '/Items',
      queryParameters: {
        'searchTerm': term,
        'recursive': true,
        'includeItemTypes': 'Movie,Series,Episode,MusicAlbum,Book',
        'limit': limit,
        'fields': 'PrimaryImageAspectRatio,ProductionYear',
      },
      cancelToken: cancelToken,
    );
    final items = _itemsOf(response.data);
    if (items is! List) return const [];
    return [
      for (final item in items.whereType<Map>())
        (
          type: item['Type']?.toString() ?? '',
          item: jellyfinStreamItemFromJson(item.cast<String, dynamic>()),
        ),
    ];
  }

  /// `GET /Library/VirtualFolders/Query`: `{Items, TotalRecordCount}`, the
  /// same folders as the bare-list route.
  @override
  Future<List<JellyfinVirtualFolder>> virtualFolders(ApiClient api) async {
    final response = await api.get('/Library/VirtualFolders/Query');
    return jellyfinVirtualFoldersFromJson(_itemsOf(response.data));
  }

  /// Null: Emby answers a series' episodes in aired order already, and a
  /// `SortBy` it does not know (`AiredEpisodeOrder` is Jellyfin's) is a 500.
  @override
  String? get episodeSortBy => null;

  /// The rows of a `{Items, TotalRecordCount}` envelope, or [data] itself when
  /// it is already the bare list a proxy that unwraps single-key objects
  /// would send.
  static Object? _itemsOf(Object? data) => data is Map ? data['Items'] : data;
}
