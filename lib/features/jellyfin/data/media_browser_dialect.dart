import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/jellyfin/data/media_browser_isolate.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_item_mapper.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// A route and the query to send it: what a dialect hands back when the only
/// thing that differs between two servers is where a read goes and what it
/// carries, and the client keeps the paging, the mapping and the failure
/// handling.
typedef MediaBrowserRequest = ({String path, Map<String, dynamic> query});

/// One search hit, already a [StreamItem], with the raw `Type` it arrived
/// under.
///
/// The type travels beside the item because `StreamItemKind` folds `Person`,
/// `Book`, `MusicArtist` and `BoxSet` all onto `other`: the search bands are
/// cut on the raw word, which is gone once an item is mapped.
typedef MediaBrowserSearchHit = ({String type, StreamItem item});

/// The four labels that name this install to the server's device list.
///
/// Resolved once by the client, so a dialect that has no use for them (an API
/// key behind `X-Emby-Token` registers no device) simply ignores them.
typedef MediaBrowserDevice = ({
  String client,
  String device,
  String deviceId,
  String version,
});

/// What differs between two servers of the MediaBrowser family (Jellyfin and
/// its ancestor Emby), and nothing else.
///
/// Jellyfin forked from Emby, so the two share the item model, the session
/// model, the paging envelope and most routes. The client in
/// `media_browser_client.dart` owns everything they share and asks the dialect
/// at the few sites where they part: the base path, how the credential
/// travels, six reads that live at different routes (or in a different shape),
/// and a handful of parameters one server rejects or ignores.
///
/// Kept small on purpose. A member is here because a server answered
/// differently, never because a future server might; a dialect that grows a
/// knob nobody can test is a second client in disguise.
abstract interface class MediaBrowserDialect {
  /// Which service this dialect speaks for: the identity a probe is checked
  /// against, and the name a failure is drawn under.
  ServiceKey get service;

  /// The path every route sits under, `''` or `'/emby'`, added to the address
  /// for requests and for artwork alike (the two are built apart, so a client
  /// that prefixed only one would serve its posters from the wrong place and
  /// say nothing).
  String get basePath;

  /// The headers that sign this client in.
  ///
  /// [proxyHoldsAuthorization] is whether the connection's access already uses
  /// `Authorization` for a gateway in front of the server, in which case the
  /// credential has to travel elsewhere.
  Map<String, String> serviceHeaders({
    required String token,
    required MediaBrowserDevice device,
    required bool proxyHoldsAuthorization,
  });

  /// Interceptors this server wants on the API client, none by default.
  List<Interceptor> interceptors({
    required String token,
    required bool proxyHoldsAuthorization,
  });

  /// Whether the body of `GET /System/Info/Public` came from this server and
  /// not from something else answering at the address.
  bool isThisServer(Map<String, dynamic> publicInfo);

  /// The query of `GET /Sessions`: how a server is told to leave out clients
  /// that have gone quiet.
  Map<String, dynamic> sessionsQuery();

  /// The raw `/Sessions` list, narrowed to the clients that are still there.
  ///
  /// For a server that cannot be told to leave the quiet ones out
  /// ([sessionsQuery] is the way when it can): it answers every client that
  /// has ever connected and not been reaped, and the window is ours to apply.
  /// A server that already did returns [raw] as it came.
  Object? liveSessions(Object? raw);

  /// The `fields` every browse read asks for, a comma list.
  ///
  /// `PrimaryImageAspectRatio` lets a poster reserve its box, `Overview` is
  /// what an item detail opens with and `ProviderIds` sends a tile to its
  /// title's page. A server that leaves a field out unless asked (Emby's
  /// `ProductionYear`, which Jellyfin always sends) adds it here.
  String get browseFields;

  /// Every user of the server, parsed. Throws like the read it stands for: an
  /// empty list is a server that answered with no users.
  Future<List<JellyfinUserDto>> users(ApiClient api);

  /// Which credential kind the slot holds. Never throws: a probe that did not
  /// answer is [JellyfinCredentialKind.unknown].
  Future<JellyfinCredentialKind> credentialKind(ApiClient api);

  /// The user the token belongs to, as the one viewer it can read as, for a
  /// token that is refused [users]. Empty for a user the server answers as
  /// disabled or without an id; a failure throws, like the list it stands in
  /// for.
  ///
  /// [userId] is the viewer the connection already holds, for a server whose
  /// token cannot say who it is (Emby has no `/Users/Me`): that one is read
  /// by id, and nobody is answered when none is held.
  Future<List<StreamViewer>> tokenUserAsViewer(ApiClient api, String userId);

  /// One item, raw, by id. [viewerId] is the user whose `UserData` rides on it,
  /// or null for the bare item.
  Future<Map<String, dynamic>?> rawItem(
    ApiClient api,
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  });

  /// What [userId] started and did not finish: one library when [parentId] is
  /// named, the whole server when it is not.
  MediaBrowserRequest resume({
    required String userId,
    required int limit,
    required String fields,
    String? parentId,
    int? startIndex,
    String? mediaTypes,
  });

  /// What [userId] watches next, in one library.
  MediaBrowserRequest nextUp({
    required String userId,
    required String parentId,
    required int startIndex,
    required int limit,
    required String fields,
  });

  /// The library search for [term], at most [limit] hits across every type,
  /// in the server's relevance order.
  Future<List<MediaBrowserSearchHit>> search(
    ApiClient api, {
    required String term,
    required int limit,
    CancelToken? cancelToken,
  });

  /// The libraries, as the server lists them, parsed.
  Future<List<JellyfinVirtualFolder>> virtualFolders(ApiClient api);

  /// The `sortBy` that puts a series' episodes in aired order, or null when
  /// the server already answers in that order and rejects the word.
  String? get episodeSortBy;
}

/// Jellyfin, as Cupola has always spoken to it.
///
/// Every member here is the behaviour the client had before the dialect was
/// split out, byte for byte on the wire; the dialect test pins each route.
class JellyfinDialect implements MediaBrowserDialect {
  const JellyfinDialect();

  /// How far back a client counts as "active".
  ///
  /// `/Sessions` otherwise includes every client that has ever connected and
  /// not been reaped, so a phone that watched something last Tuesday shows up
  /// as a live row. Three minutes is long enough to survive a paused stream's
  /// keep-alive gap and short enough that a closed app disappears promptly.
  static const int activeWithinSeconds = 180;

  @override
  ServiceKey get service => ServiceKey.jellyfin;

  @override
  String get basePath => '';

  /// `Authorization: MediaBrowser …` as a rule. When the connection's access
  /// holds `Authorization` for a proxy in front (its password), the token
  /// travels in `X-Emby-Token` instead, and `Authorization` is left to the
  /// proxy. Recent servers no longer read that header (legacy authorization
  /// is off by default: Jellyfin 12.1 answers it with 401), so the API
  /// requests also carry the token as the `ApiKey` parameter
  /// ([interceptors]), the one form left besides `Authorization`. Automatic:
  /// the user never sees a clash.
  @override
  Map<String, String> serviceHeaders({
    required String token,
    required MediaBrowserDevice device,
    required bool proxyHoldsAuthorization,
  }) => proxyHoldsAuthorization
      ? {'X-Emby-Token': token}
      : {
          'Authorization': buildJellyfinAuthorizationHeader(
            token: token,
            client: device.client,
            device: device.device,
            deviceId: device.deviceId,
            version: device.version,
          ),
        };

  @override
  List<Interceptor> interceptors({
    required String token,
    required bool proxyHoldsAuthorization,
  }) => proxyHoldsAuthorization
      ? [_JellyfinApiKeyQuery(token)]
      : const <Interceptor>[];

  /// A reverse proxy landing page happily returns 200 with a body that decodes
  /// to something; without this check the version probe would report success
  /// on an address that has no Jellyfin behind it at all. An Emby on the
  /// port is no better (it answers the same route), and says so in the
  /// shape of its answer ([identifyProbeAnswer]).
  @override
  bool isThisServer(Map<String, dynamic> publicInfo) =>
      identifyProbeAnswer(ServiceKey.jellyfin, publicInfo) is ProbeMatches &&
      JellyfinPublicSystemInfo.fromJson(publicInfo).isJellyfin;

  @override
  Map<String, dynamic> sessionsQuery() => {
    'activeWithinSeconds': activeWithinSeconds,
  };

  /// The server applied the window ([sessionsQuery]).
  @override
  Object? liveSessions(Object? raw) => raw;

  @override
  String get browseFields => 'PrimaryImageAspectRatio,Overview,ProviderIds';

  @override
  Future<List<JellyfinUserDto>> users(ApiClient api) async {
    final response = await api.get('/Users');
    return mapInIsolate(response.data, jellyfinUsersFromJson);
  }

  /// From `GET /Users/Me`.
  ///
  /// An API key has no user, and Jellyfin answers **400** with no body (the
  /// user id is empty, unchanged from 10.8 to master); that means
  /// Administrator. A user token gets 200 and its `UserDto`, whose
  /// `Policy.IsAdministrator` decides. Anything else (a transport error, a
  /// 401) is [JellyfinCredentialKind.unknown], so a failure never withholds a
  /// tab that might have worked.
  @override
  Future<JellyfinCredentialKind> credentialKind(ApiClient api) async {
    try {
      final response = await api.get('/Users/Me');
      final data = response.data;
      if (data is! Map) return JellyfinCredentialKind.unknown;
      final user = JellyfinUserDto.fromJson(data.cast<String, dynamic>());
      return user.isAdministrator
          ? JellyfinCredentialKind.administrator
          : JellyfinCredentialKind.user;
    } on DioException catch (e) {
      return e.response?.statusCode == 400
          ? JellyfinCredentialKind.apiKey
          : JellyfinCredentialKind.unknown;
    } catch (_) {
      return JellyfinCredentialKind.unknown;
    }
  }

  @override
  Future<List<StreamViewer>> tokenUserAsViewer(
    ApiClient api,
    String userId,
  ) async {
    final response = await api.get('/Users/Me');
    final data = response.data;
    if (data is! Map) return const [];
    final user = JellyfinUserDto.fromJson(data.cast<String, dynamic>());
    if (user.isDisabled || user.id.isEmpty) return const [];
    return [user.toStreamViewer()];
  }

  /// `userId` is optional on `GET /Items/{itemId}`: it is a `Guid?`, and
  /// omitting it costs the `UserData` block (played flag, resume point) and
  /// nothing else. `fields` is ignored by this endpoint, which always returns
  /// the full DTO including MediaSources, MediaStreams and People, so none is
  /// sent.
  @override
  Future<Map<String, dynamic>?> rawItem(
    ApiClient api,
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    final response = await api.get(
      '/Items/$itemId',
      queryParameters: {'userId': ?viewerId},
      cancelToken: cancelToken,
    );
    final data = response.data;
    return data is Map ? data.cast<String, dynamic>() : null;
  }

  /// `/UserItems/Resume` replaces the deprecated
  /// `/Users/{userId}/Items/Resume` and is always sorted by DatePlayed desc,
  /// so no sort parameters are sent. `excludeActiveSessions` keeps the item
  /// somebody is watching *right now* out of their own continue-watching row,
  /// where it would be a duplicate of the session board.
  @override
  MediaBrowserRequest resume({
    required String userId,
    required int limit,
    required String fields,
    String? parentId,
    int? startIndex,
    String? mediaTypes,
  }) => (
    path: '/UserItems/Resume',
    query: {
      'userId': userId,
      'parentId': ?parentId,
      'startIndex': ?startIndex,
      'limit': limit,
      'fields': fields,
      'enableUserData': true,
      'excludeActiveSessions': true,
      'mediaTypes': ?mediaTypes,
    },
  );

  @override
  MediaBrowserRequest nextUp({
    required String userId,
    required String parentId,
    required int startIndex,
    required int limit,
    required String fields,
  }) => (
    path: '/Shows/NextUp',
    query: {
      'userId': userId,
      'parentId': parentId,
      'startIndex': startIndex,
      'limit': limit,
      'fields': fields,
      'enableUserData': true,
      // Default anyway, but explicit: "next up" must not resurface a series
      // the viewer already finished.
      'enableRewatching': false,
    },
  );

  /// `GET /Search/Hints`.
  ///
  /// **Why the type set is not sent as `includeItemTypes`.** This endpoint
  /// gates people, studios and artists behind their own boolean flags rather
  /// than through the type filter, so naming `Person` in `includeItemTypes`
  /// quietly returns nothing instead of failing. Asking for media and people
  /// by flag and grouping the answer in the client is the only spelling that
  /// returns both.
  @override
  Future<List<MediaBrowserSearchHit>> search(
    ApiClient api, {
    required String term,
    required int limit,
    CancelToken? cancelToken,
  }) async {
    final response = await api.get(
      '/Search/Hints',
      queryParameters: {
        'searchTerm': term,
        'limit': limit,
        'includeMedia': true,
        'includePeople': true,
        // Left off on purpose: a studio or an artist row opens nothing in this
        // app, and a hit that cannot be tapped is noise in a five-row answer.
        'includeStudios': false,
        'includeArtists': false,
      },
      cancelToken: cancelToken,
    );
    final data = response.data;
    // `SearchHints` on every build; the bare array is the reverse-proxy shape
    // the item pager already tolerates.
    final raw = data is Map ? data['SearchHints'] : data;
    if (raw is! List) return const [];
    return [
      for (final hint in raw.whereType<Map>())
        (
          type: hint['Type']?.toString() ?? '',
          item: jellyfinSearchHintFromJson(hint.cast<String, dynamic>()),
        ),
    ];
  }

  @override
  Future<List<JellyfinVirtualFolder>> virtualFolders(ApiClient api) async {
    final response = await api.get('/Library/VirtualFolders');
    return jellyfinVirtualFoldersFromJson(response.data);
  }

  /// A single value, not a CSV, unlike `/Items`. Aired order is what an
  /// episode list means; `SortName` would order "Episode 10" before
  /// "Episode 2".
  @override
  String? get episodeSortBy => 'AiredEpisodeOrder';
}

/// Builds the only non-deprecated Jellyfin auth header in 10.11.
///
/// ```
/// Authorization: MediaBrowser Token="…", Client="Cupola", Device="macos",
///                DeviceId="…", Version="0.8.0"
/// ```
///
/// `AuthorizationContext` parses the scheme word case-insensitively, then splits
/// on commas into `Key="Value"` pairs. Three details are load-bearing:
///
///  * the keys are **case-sensitive** (`token=` is not read);
///  * the values **must** be double-quoted;
///  * the values are **URL-decoded** by the server, so any comma or quote inside
///    one has to be percent-encoded: an unencoded comma in a client name would
///    otherwise split the pair and silently drop the credential that follows it.
///
/// Only `Token` is functionally required; the rest is what makes the server's
/// device list legible.
String buildJellyfinAuthorizationHeader({
  required String token,
  required String client,
  required String device,
  required String deviceId,
  required String version,
}) {
  final pairs = <String, String>{
    'Token': token,
    'Client': client,
    'Device': device,
    'DeviceId': deviceId,
    'Version': version,
  };
  final encoded = pairs.entries
      .where((entry) => entry.value.isNotEmpty)
      // `Uri.encodeComponent` escapes `,` as `%2C` and `"` as `%22`, which is
      // exactly what the server's `UrlDecode` on each value expects back.
      .map((entry) => '${entry.key}="${Uri.encodeComponent(entry.value)}"')
      .join(', ');
  return 'MediaBrowser $encoded';
}

/// Adds the token as the `ApiKey` parameter to every API request, for a
/// connection whose proxy holds `Authorization` (see
/// [JellyfinDialect.serviceHeaders]). Only the API client carries it: artwork
/// keeps the token out of its URLs, which become the image cache's file
/// names, and Jellyfin serves images without it.
class _JellyfinApiKeyQuery extends Interceptor {
  _JellyfinApiKeyQuery(this._token);

  final String _token;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.queryParameters = {...options.queryParameters, 'ApiKey': _token};
    handler.next(options);
  }
}
