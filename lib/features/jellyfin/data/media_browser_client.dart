import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/jellyfin/data/media_browser_dialect.dart';
import 'package:cupola/features/jellyfin/data/media_browser_isolate.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_item_mapper.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_library_page.dart';
import 'package:cupola/features/stream/domain/models/stream_search_group.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// The [StreamServerClient] of the MediaBrowser family: Jellyfin and its
/// ancestor Emby, told apart by the [MediaBrowserDialect] it is given.
///
/// Everything the two servers share lives here (the paging, the item mapping,
/// the viewer rules, the failure handling) and the dialect is asked only at the
/// sites where they differ. A server's own class (`JellyfinClient`) is a thin
/// subclass that picks the dialect, so no caller names a dialect and the
/// constructor every caller and test already uses stays what it was.
///
/// What follows was written for Jellyfin, and holds for both unless the
/// dialect says otherwise.
///
/// ## The privilege model, which decides the shape of this whole file
///
/// A Jellyfin API key authenticates as `role=Administrator` with `IsApiKey=true`
/// and **no user attached**: the `UserId` claim is the empty GUID. So the key
/// passes every admin policy (it can read `/Sessions`, `/Users`,
/// `/Library/VirtualFolders`, and stop a playback) while having no idea who "I"
/// am. Every user-scoped question (what did I not finish, what is next up, what
/// have I not played) therefore has to name a user explicitly, and the
/// endpoints that need one 404 rather than defaulting when it is missing.
///
/// That is why [viewerId] threads through the browse methods and why
/// `settings.jellyfinUserId` is a first-class setting rather than an optional
/// nicety. It is also the asymmetry the Stream contract was built around: a Plex
/// token *is* a user and cannot impersonate, an API key is nobody and must.
///
/// ## Why playback control needs no capability gate
///
/// The credential slot holds **either** of two kinds, and both work. Jellyfin
/// matches a token against user sessions first and API keys second, so an
/// API key authenticates as Administrator with no user, while a user's
/// `AccessToken` from `POST /Users/AuthenticateByName`, which is what the
/// testlab bootstrap stores, authenticates as that user, with that user's
/// policy.
///
/// Even so, **no session control Cupola draws can be refused.** Pause, resume,
/// message and stop go through `SessionManager.AssertCanControl`, a no-op up to
/// 10.11.x; from 12.0 it allows an API key, a session with no user or the
/// caller's own session, and otherwise wants
/// `Policy.EnableRemoteControlOfOtherUsers`. But `GET /Sessions` without
/// `controllableByUserId` (which is how [getSessions] asks) hands a
/// non-administrator only its own sessions plus sessions with no user: exactly
/// the ones it may control. A control on screen is a control the credential
/// may use, on every version, so Jellyfin carries no write gate, no banner and
/// no dimmed session control (`ServiceKey.hasScopedCredential` is false).
///
/// What a non-administrator token *does* lose is reads: `/Users`, `/Devices`,
/// `/ScheduledTasks` and `/Library/VirtualFolders` are elevated. That is a read scope, answered by
/// [getCredentialKind] from `GET /Users/Me`, and drawn as an "administrator
/// only" placeholder rather than an error.
///
/// Do not probe with `GET /Auth/Keys`: it would answer, but its body carries
/// every key's token.
///
/// ## Units
///
/// Four of them, all in `jellyfin_units.dart`; nothing in this file divides by a
/// magic constant.
class MediaBrowserClient implements StreamServerClient {
  /// [userId] is the household member whose watch state the per-viewer lenses
  /// read by default (`settings.jellyfinUserId`); a per-call `viewerId` overrides
  /// it.
  ///
  /// [clientName], [deviceName], [deviceId] and [appVersion] only decorate the
  /// `Authorization` header. Jellyfin requires none of them functionally, and
  /// they exist so the server's Dashboard → Devices list names Cupola instead of
  /// showing an anonymous row.
  MediaBrowserClient({
    required MediaBrowserDialect dialect,
    required String baseUrl,
    required String apiKey,
    String userId = '',
    String clientName = kJellyfinClientName,
    String? deviceName,
    String? deviceId,
    String appVersion = kJellyfinClientVersion,
    String? pinnedCertFingerprint,
    Map<String, String> accessHeaders = const {},
    ServiceKey? onlyAtHome,
  }) : _dialect = dialect,
       _baseUrl = UrlUtils.normalizeBaseUrl(baseUrl),
       _accessHeaders = accessHeaders,
       _token = apiKey.trim(),
       _userId = userId.trim(),
       _device = (
         client: clientName,
         device: deviceName ?? defaultJellyfinDeviceName(),
         deviceId: deviceId ?? defaultJellyfinDeviceId(deviceName),
         version: appVersion,
       ) {
    final interceptors = _dialect.interceptors(
      token: _token,
      proxyHoldsAuthorization: _proxyHoldsAuthorization,
    );
    // `ApiClient.authenticatedBy` rather than a bespoke `Dio`: it carries the
    // shared timeouts and, decisively, `SameOriginRedirectInterceptor`. Without
    // that interceptor a single 302 from a misconfigured reverse proxy would
    // replay the `Authorization` header (a full-privilege admin key) to a host
    // the user never configured.
    _api = ApiClient.authenticatedBy(
      baseUrl: _apiBase,
      headers: _serviceHeaders,
      pinnedCertFingerprint: pinnedCertFingerprint,
      accessHeaders: accessHeaders,
      onlyAtHome: onlyAtHome,
      interceptors: interceptors.isEmpty ? null : (_) => interceptors,
    );
  }

  final MediaBrowserDialect _dialect;

  /// The address the connection is saved as, without the dialect's base path:
  /// what an error names and a probe is checked against.
  final String _baseUrl;

  /// The address requests and artwork are built from: [_baseUrl] under the
  /// dialect's base path. Left alone when there is no address, so an empty one
  /// stays empty and fails where it always did.
  late final String _apiBase = _baseUrl.isEmpty
      ? _baseUrl
      : '$_baseUrl${_dialect.basePath}';

  /// What the connection presents to a gateway in front of the server, on
  /// every request and every poster.
  final Map<String, String> _accessHeaders;

  final String _token;

  final MediaBrowserDevice _device;

  /// The headers that sign this client in, as the dialect spells them.
  late final Map<String, String> _serviceHeaders = _dialect.serviceHeaders(
    token: _token,
    device: _device,
    proxyHoldsAuthorization: _proxyHoldsAuthorization,
  );

  bool get _proxyHoldsAuthorization =>
      _accessHeaders.keys.any((name) => name.toLowerCase() == 'authorization');

  final String _userId;
  late final ApiClient _api;

  /// Requested on every browse call.
  ///
  /// `PrimaryImageAspectRatio` lets a poster reserve its box before the bytes
  /// arrive; `Overview` is what an item detail opens with, and asking for it here
  /// means a tap on a grid tile can render text immediately instead of waiting
  /// for `/Items/{id}`. `ProviderIds` is what sends a movie's tile to the
  /// movie's own page (`MediaKey.ofStreamItem`).
  String get _browseFields => _dialect.browseFields;

  /// Lets a test swap in a stubbed transport, exactly as the per-service clients
  /// do with an injected `Dio`, and lets it assert on the real request this
  /// client builds, headers included.
  ///
  /// Propagating [ApiClient]'s own test seam rather than taking a `Dio` in the
  /// constructor: an injected transport would come pre-built with whatever headers
  /// the *test* chose, and then "the `Authorization` header is exactly right on
  /// the wire" would only ever be asserting about the test's own string. This
  /// getter keeps header construction where it belongs and still stubs the socket.
  /// Marked `@visibleForTesting` in turn, so nothing in `lib/` can reach through
  /// it either.
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  Dio get dio => _api.dio;

  /// `CollectionType`-derived kinds, cached from [getLibraries].
  ///
  /// Used to constrain a browse to the item type a library is *about*:
  /// `recursive=true` is required to see items rather than folders, but on a TV
  /// library it also returns every season and every episode, so an A–Z page would
  /// interleave 12 series with 400 episodes. Populated lazily on a deep link
  /// (where the library list was never loaded) so
  /// `/services/jellyfin/library/<id>` still resolves from the path alone.
  final Map<String, StreamLibraryKind> _libraryKinds = {};

  /// The in-flight (or completed) lazy library lookup, so several lenses opening
  /// at once share one request instead of each firing its own.
  Future<List<StreamLibrary>>? _libraryKindLookup;

  @override
  Future<String?> probeVersion() async {
    try {
      // The credential-free endpoint on purpose: "the box is down" and "the
      // token is wrong" must not arrive as the same error. It can also answer 503
      // with a `Retry-After` while the server is still starting, which lands in
      // the catch below as "no version yet" rather than as a hard failure.
      final response = await _api.get('/System/Info/Public');
      final data = response.data;
      if (data is! Map) return null;
      final body = data.cast<String, dynamic>();
      return _dialect.isThisServer(body)
          ? JellyfinPublicSystemInfo.fromJson(body).version
          : null;
    } catch (_) {
      return null;
    }
  }

  /// The server's own id, read from the anonymous endpoint: what a Jellyfin app
  /// needs to open an item on it. Null when the server does not say.
  Future<String?> publicServerId() async {
    try {
      final response = await _api.get('/System/Info/Public');
      final data = response.data;
      if (data is! Map) return null;
      return JellyfinPublicSystemInfo.fromJson(data.cast<String, dynamic>()).id;
    } catch (_) {
      return null;
    }
  }

  /// The Dashboard's probe: proves the credential, and names the version.
  ///
  /// [probeVersion] reads the anonymous endpoint, so a Jellyfin with a wrong
  /// token read as answering. `/System/Info` is its authenticated twin and
  /// carries the same `Version`. A **403** is a valid token without the
  /// administrator's reads (a narrower credential, not a fault), so it still
  /// answers, and the version comes from the public endpoint. A 401 throws:
  /// the server answered and refused the token.
  ///
  /// Who answered is checked on the way ([requireProbeIdentity]): an Emby on
  /// the port of a Jellyfin, or a web page at the address, is not the server
  /// this client speaks for.
  Future<String?> checkCredentialAndVersion() async {
    try {
      final response = await _api.get('/System/Info');
      requireProbeIdentity(_dialect.service, response.data, url: _baseUrl);
      return _versionOf(response.data);
    } on DioException catch (error) {
      // A 403 from Jellyfin itself is a narrower token; one from something
      // in front of it is not Jellyfin's answer at all.
      if (error.response?.statusCode == 403 &&
          error.error is! AccessGatewayAnswer) {
        return probeVersion();
      }
      rethrow;
    }
  }

  static String? _versionOf(Object? data) {
    if (data is! Map) return null;
    // Jellyfin spells it `Version`; the shared probe read `version` and so
    // never showed one.
    final version = data['Version'] ?? data['version'];
    final text = version?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  @override
  Future<bool> verifyCredential() async {
    try {
      // The authenticated twin of the public probe: 401 means the token is
      // absent or wrong, and a caller that wants to tell an unreachable host
      // apart pairs this with [probeVersion].
      final response = await _api.get('/System/Info');
      final code = response.statusCode ?? 0;
      return code >= 200 && code < 300;
    } on DioException catch (error) {
      // A 403 from Jellyfin itself is a household member's token: valid, and
      // narrower than an administrator's. It plays, browses and controls its
      // own sessions, so it is accepted, as [checkCredentialAndVersion]
      // accepts it for the Dashboard; the reads it cannot make say so where
      // they are drawn. A 403 from something in front of Jellyfin is not
      // Jellyfin's answer.
      return error.response?.statusCode == 403 &&
          error.error is! AccessGatewayAnswer;
    } catch (_) {
      return false;
    }
  }

  /// Throws on a remote failure, like [getSessionsOrThrow], which it now is.
  ///
  /// It used to answer a dark server with `const []`, on the theory that a
  /// dead server is a quiet empty board. It is not: the board said "Nobody is
  /// watching right now" about a server nobody could ask, and Activity's
  /// offline note, which exists to name the dark server, never fired.
  @override
  Future<List<StreamSession>> getSessions() => getSessionsOrThrow();

  /// The session read with its transport failure preserved.
  ///
  /// The name predates [getSessions] surfacing its own failure; the KPI and
  /// reachability readers still call it by this one. `0 streams` is a real
  /// answer only when `/Sessions` answered with no active sessions.
  Future<List<StreamSession>> getSessionsOrThrow() async {
    final response = await _api.get(
      '/Sessions',
      queryParameters: _dialect.sessionsQuery(),
    );
    return mapInIsolate(
      _dialect.liveSessions(response.data),
      jellyfinStreamSessionsFromJson,
    );
  }

  @override
  Future<void> stopSession(String sessionId) async {
    // A write action, so the error surfaces: the UI needs to say "the stop did
    // not go through". Note the 204 means *dispatched*, not stopped: the client
    // may ignore the command, which is why callers re-read [getSessions] instead
    // of trusting this returning normally.
    await _api.post('/Sessions/$sessionId/Playing/Stop');
  }

  /// Ask the player to pause, or to pick up again.
  ///
  /// `POST /Sessions/{id}/Playing/Pause` and `/Unpause` are *remote control*
  /// commands: Jellyfin relays them over the WebSocket it already holds open to
  /// that client, and a client that is not listening (a browser tab, an old
  /// Infuse build) simply never acts on the 204. So this is dispatch, not
  /// control, exactly like [stopSession]: the caller re-reads [getSessions]
  /// rather than flipping [StreamSession.isPaused] optimistically.
  ///
  /// **Plex has no counterpart reachable from here**, which is why the board
  /// draws pause on Jellyfin alone: Plex's `/player/playback/*` routes address
  /// the client directly on its own LAN address, not through the server.
  Future<void> pauseSession(String sessionId) async {
    await _api.post('/Sessions/$sessionId/Playing/Pause');
  }

  /// The other half of [pauseSession].
  Future<void> unpauseSession(String sessionId) async {
    await _api.post('/Sessions/$sessionId/Playing/Unpause');
  }

  /// Put a line of text on someone's screen.
  ///
  /// `POST /Sessions/{id}/Message`, whose body is a `MessageCommand`: `Text` is
  /// required, `Header` is the title the client draws above it, and `TimeoutMs`
  /// is how long the toast stays. Sent as milliseconds because that is the
  /// field's unit: the one Jellyfin write in this file that is not in ticks.
  ///
  /// The same dispatch caveat as [pauseSession]: the client decides whether it
  /// has anywhere to draw a message, and several have nowhere.
  Future<void> sendMessage(
    String sessionId, {
    required String text,
    String header = kJellyfinMessageHeader,
    int timeoutMs = kJellyfinMessageTimeoutMs,
  }) async {
    await _api.post(
      '/Sessions/$sessionId/Message',
      data: {'Text': text, 'Header': header, 'TimeoutMs': timeoutMs},
    );
  }

  /// Throws on a remote failure, like [getLibrariesOrThrow], which it now is.
  ///
  /// A swallowed failure made a dark server read "No libraries yet".
  @override
  Future<List<StreamLibrary>> getLibraries() => getLibrariesOrThrow();

  /// The library read with its transport or parse failure preserved, so an
  /// unreachable server cannot become `Libraries 0`. The name predates
  /// [getLibraries] surfacing its own failure.
  Future<List<StreamLibrary>> getLibrariesOrThrow() async {
    final folders = await _dialect.virtualFolders(_api);
    final libraries = <StreamLibrary>[];
    for (final folder in folders) {
      // A library with no `ItemId` cannot be browsed or rescanned: there is
      // nothing to pass as `parentId`, so listing it would only offer a dead
      // end. This happens on a folder added to the config but never scanned.
      if (folder.itemId.isEmpty) continue;
      final library = folder.toStreamLibrary();
      _libraryKinds[library.id] = library.kind;
      libraries.add(library);
    }
    return libraries;
  }

  @override
  Future<StreamLibraryPage> getLibraryPage({
    required String libraryId,
    StreamLibrarySort sort = StreamLibrarySort.name,
    bool unplayedOnly = false,
    String? viewerId,
    int startIndex = 0,
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final userId = _resolveViewerId(viewerId);
    // Unplayed is a watch state, user-scoped end to end, and the API key has
    // no user of its own. Saying so is the point: an empty page here is what
    // made the browse claim a library was empty when nobody had been picked.
    // The whole shelf is the same for everyone and needs no viewer.
    if (userId == null && unplayedOnly) {
      return const StreamLibraryPage.viewerRequired();
    }

    try {
      // `/Items` takes `includeItemTypes`, so the library's kind is needed.
      await _ensureLibraryKind(libraryId);
      final page = await _fetchItemsPage('/Items', {
        ..._itemsBaseQuery(libraryId, userId, startIndex, limit),
        if (unplayedOnly) 'isPlayed': false,
        ..._sortQuery(sort),
      }, cancelToken: cancelToken);
      return page.toLibraryPage(startIndex);
    } catch (_) {
      return StreamLibraryPage.failed(startIndex: startIndex);
    }
  }

  /// How many items a library holds, without downloading any of them.
  ///
  /// `limit=0` still returns the `BaseItemDtoQueryResult` envelope, so
  /// `TotalRecordCount` arrives with an empty `Items` array: the cheapest count
  /// Jellyfin offers, and the reason `VirtualFolderInfo` carrying none is
  /// survivable.
  ///
  /// **Counted in the library's own unit** (`_includeItemTypesFor`), so a TV
  /// library answers in series rather than in the several thousand episodes
  /// `recursive=true` would otherwise sweep up. Whatever the browse lists is
  /// what the count counts; anything else would put two numbers on one card that
  /// disagree.
  ///
  /// Deliberately **not** folded into [getLibraries]: six libraries would become
  /// six extra round trips on every dashboard load, which is exactly the cost
  /// decision 21 moved off the Overview and onto the pushed Libraries page. It
  /// is opt-in, one call per card, and a card renders complete without it.
  @override
  Future<int?> getLibraryItemCount(
    String libraryId, {
    CancelToken? cancelToken,
  }) async {
    try {
      await _ensureLibraryKind(libraryId);
      final response = await _api.get(
        '/Items',
        queryParameters: {
          'parentId': libraryId,
          'recursive': true,
          'limit': 0,
          'includeItemTypes': ?_includeItemTypesFor(libraryId),
          // No `userId`: a count is the same count for everyone, and asking for
          // `UserData` on a zero-row page only costs the server a join.
          'enableImages': false,
          'enableUserData': false,
        },
        cancelToken: cancelToken,
      );
      final data = response.data;
      return data is Map ? intOrNull(data['TotalRecordCount']) : null;
    } catch (_) {
      return null;
    }
  }

  /// What the household member [viewerId] (else the configured one) started
  /// and did not finish, across every library of the server, the most
  /// recently played first: `/UserItems/Resume` with no `parentId`.
  ///
  /// Throws [JellyfinViewerRequired] when nobody is chosen: the endpoint is
  /// user-scoped and the API key has no user, so an empty list would claim
  /// nothing is in progress. Throws on a remote failure too, for the reason
  /// Plex's `getContinueWatching` does. What somebody is playing right now
  /// stays out (`excludeActiveSessions`): Now playing has it.
  @override
  Future<List<StreamItem>> getContinueWatching({
    String? viewerId,
    int count = 12,
    CancelToken? cancelToken,
  }) async {
    final userId = _resolveViewerId(viewerId);
    if (userId == null) throw const JellyfinViewerRequired();
    final request = _dialect.resume(
      userId: userId,
      limit: count,
      fields: _browseFields,
      mediaTypes: 'Video',
    );
    final page = await _fetchItemsPage(
      request.path,
      request.query,
      cancelToken: cancelToken,
    );
    return page.items;
  }

  /// [sort] as Jellyfin's and Emby's `/Items` take it, the name breaking ties.
  /// Measured on both servers (an Emby that does not know a `SortBy` answers
  /// 500): `DateCreated` and `ProductionYear` descending, each with
  /// `SortName` ascending after it.
  static Map<String, String> _sortQuery(StreamLibrarySort sort) =>
      switch (sort) {
        StreamLibrarySort.name => {
          'sortBy': 'SortName',
          'sortOrder': 'Ascending',
        },
        StreamLibrarySort.dateAdded => {
          'sortBy': 'DateCreated,SortName',
          'sortOrder': 'Descending,Ascending',
        },
        StreamLibrarySort.year => {
          'sortBy': 'ProductionYear,SortName',
          'sortOrder': 'Descending,Ascending',
        },
      };

  @override
  Future<List<StreamItem>> getNextUp({
    required int count,
    CancelToken? cancelToken,
  }) async {
    final userId = _resolveViewerId(null);
    if (userId == null) throw const JellyfinViewerRequired();
    final request = _dialect.nextUp(
      userId: userId,
      limit: count,
      fields: _browseFields,
    );
    final page = await _fetchItemsPage(
      request.path,
      request.query,
      cancelToken: cancelToken,
    );
    return page.items;
  }

  /// Movies and series, across the libraries, by `DateLastContentAdded`: a
  /// series stands at the date of its newest episode, so a new episode of an
  /// old show is news. Measured on Jellyfin and Emby. No viewer: what was
  /// added is the same for everyone.
  @override
  Future<List<StreamItem>> getRecentlyAdded({
    required int count,
    CancelToken? cancelToken,
  }) async {
    final page = await _fetchItemsPage('/Items', {
      'recursive': true,
      'includeItemTypes': 'Movie,Series',
      'sortBy': 'DateLastContentAdded,SortName',
      'sortOrder': 'Descending,Ascending',
      'startIndex': 0,
      'limit': count,
      'fields': _browseFields,
      'enableImages': true,
    }, cancelToken: cancelToken);
    return page.items;
  }

  /// The library search, typed and grouped. The dialect asks the server and
  /// hands back mapped hits; the grouping is shared.
  ///
  /// The bands in [kJellyfinSearchBands] are emitted **even when empty**, in
  /// their declared order, because the strip has to say what was searched and
  /// not only what answered. See [StreamSearchGroup]. Anything Jellyfin returns
  /// that none of them claims (a `MusicArtist`, a `BoxSet`) falls into a
  /// trailing band that appears only when it has something, since nobody asked
  /// for it by name.
  ///
  /// [limit] is the total across every band, not per band, and the hints arrive
  /// in the server's own relevance order; grouping preserves it within each.
  @override
  Future<List<StreamSearchGroup>> search(
    String query, {
    int? limit,
    CancelToken? cancelToken,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];

    // Not caught: a search that failed throws, with what it failed with, so
    // the lane says who did not answer or what refused, in its own tone. It
    // used to come back as no groups, which the lane could only call a request
    // that did not complete, amber, for a server that was switched off.
    final hits = await _dialect.search(
      _api,
      term: term,
      limit: limit ?? kJellyfinSearchLimit,
      cancelToken: cancelToken,
    );

    // **Bucketed on the raw `Type`, and that is not an optimisation.**
    // `StreamItemKind` folds `Person`, `Book`, `MusicArtist` and `BoxSet` all
    // onto `other`, so grouping by the mapped kind would merge People and Books
    // into one band: two of the six the design names separately. `Type` is the
    // only place that distinction still exists, which is why a hit carries it.
    final byType = <String, List<StreamItem>>{};
    for (final hit in hits) {
      (byType[hit.type] ??= <StreamItem>[]).add(hit.item);
    }

    final groups = <StreamSearchGroup>[
      for (final band in kJellyfinSearchBands)
        StreamSearchGroup(
          label: band.label,
          kind: band.kind,
          items: byType.remove(band.type) ?? const [],
        ),
    ];
    // Whatever the six named bands did not claim. No zero pill, because it was
    // never a question the strip asked.
    final remainder = byType.values
        .expand((items) => items)
        .toList(growable: false);
    if (remainder.isNotEmpty) {
      groups.add(
        StreamSearchGroup(
          label: kJellyfinSearchOtherBandLabel,
          kind: null,
          items: remainder,
        ),
      );
    }
    return groups;
  }

  @override
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    // A viewer is optional here: omitting it costs the `UserData` block
    // (played flag, resume point) and nothing else. Refusing to call at all
    // without one is what made a deep link into
    // `/services/jellyfin/item/<id>` render "Not on the server" on an install
    // where the item plainly was, before the household member had been chosen
    // in settings.
    final userId = _resolveViewerId(viewerId);
    try {
      final item = await _fetchRawItem(
        itemId,
        userId,
        cancelToken: cancelToken,
      );
      return item == null ? null : jellyfinStreamItemFromJson(item);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<MediaKey?> getSeriesKey(String seriesId, {CancelToken? cancelToken}) =>
      _keyOf(seriesId, const {StreamItemKind.series}, cancelToken: cancelToken);

  @override
  Future<MediaKey?> getTitleKey(String titleId, {CancelToken? cancelToken}) =>
      _keyOf(titleId, const {
        StreamItemKind.movie,
        StreamItemKind.series,
      }, cancelToken: cancelToken);

  /// The page the item [id] has, when it is one of [kinds].
  Future<MediaKey?> _keyOf(
    String id,
    Set<StreamItemKind> kinds, {
    CancelToken? cancelToken,
  }) async {
    try {
      final items = await _fetchItems('/Items', {
        'ids': id,
        // The ids are all this read is for: no artwork, no synopsis.
        'fields': 'ProviderIds',
        'userId': ?_resolveViewerId(null),
      }, cancelToken: cancelToken);
      // A server that ignored `ids` answers with the start of its library:
      // only the item itself names its page.
      final named = items.where(
        (item) => _sameId(item.id, id) && kinds.contains(item.kind),
      );
      return named.isEmpty ? null : MediaKey.ofStreamItem(named.first);
    } catch (_) {
      return null;
    }
  }

  /// Whether two spellings name one item: Jellyfin writes an id with or
  /// without dashes, in either case.
  static bool _sameId(String a, String b) =>
      a.replaceAll('-', '').toLowerCase() ==
      b.replaceAll('-', '').toLowerCase();

  @override
  Future<StreamExternalLookup> lookupByExternalId({
    String? tmdbId,
    String? tvdbId,
    String? imdbId,
    StreamItemKind? kind,
    String? title,
    int? year,
    CancelToken? cancelToken,
  }) async {
    // `anyProviderIdEquals` takes `provider.value` pairs; passing several is an
    // OR, which is what we want: an arr may know a film by TMDB and a series by
    // TVDB, and either identifies the same thing here.
    final pairs = <String>[
      if (tmdbId != null && tmdbId.isNotEmpty) 'tmdb.$tmdbId',
      if (tvdbId != null && tvdbId.isNotEmpty) 'tvdb.$tvdbId',
      if (imdbId != null && imdbId.isNotEmpty) 'imdb.$imdbId',
    ];
    // Nothing to ask by, so nothing to verify: no claim either way.
    if (pairs.isEmpty) return const StreamExternalLookup.notVerified();
    final query = StreamExternalQuery(
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      imdbId: imdbId,
      kind: kind,
      title: title,
      year: year,
    );

    // A viewer is a bonus here, not a precondition. Without one `/Items` still
    // answers "is this in the library", which is the media server's own fact and
    // the one the availability slot needs to exist; what is lost is the watch
    // state, so the slot reads "Ready to watch" rather than "34 min in". Bailing
    // out without a viewer made the slot Plex-only in practice.
    final userId = _resolveViewerId(null);

    // Not caught: a server that did not answer is not a library without the
    // title, and the caller says which it was.
    final items = await _fetchItems('/Items', {
      'recursive': true,
      'anyProviderIdEquals': pairs.join(','),
      // Only the two kinds an arr record can be. Without this an episode,
      // which carries TVDB and IMDb ids of its own, in the same namespaces a
      // series uses, is a legitimate hit for a Sonarr lookup.
      'includeItemTypes': switch (kind) {
        StreamItemKind.movie => 'Movie',
        StreamItemKind.series => 'Series',
        _ => 'Movie,Series',
      },
      // Several rows, not one: the filter is an OR, so a film sharing the
      // series' TMDB number is a hit too, and the first row is simply
      // whichever sorted first. The matcher picks among them.
      'limit': _kExternalMatchCandidates,
      // `ProviderIds`, in the browse fields, is what the answer is checked
      // against. Without it the
      // only evidence a row matched is that the server returned it, which is
      // also what a server that ignored `anyProviderIdEquals` does, with the
      // first rows of the whole library.
      // `MediaStreams` for the picture the Media page names: `2160p · HDR10`.
      'fields': '$_browseFields,MediaStreams',
      // `UserData` is omitted from the response entirely unless both are
      // present, so they travel together or not at all.
      'userId': ?userId,
      if (userId != null) 'enableUserData': true,
    }, cancelToken: cancelToken);
    return StreamExternalLookup.of(items, query);
  }

  /// How many rows the checked lookup asks for. A real answer is one to three
  /// (the title, the same title in a second library, a film sharing a TMDB
  /// number); more only arrive when the filter was ignored, and then none of
  /// them is verified anyway.
  static const int _kExternalMatchCandidates = 10;

  @override
  Future<List<StreamItem>> getEpisodes(
    String seriesId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) {
    // Unpaged, like a season's: `/Shows/{id}/Episodes` answers the whole
    // series. Without a viewer the server still lists what it holds; only the
    // watch state goes, which `UserData` carries for a user alone.
    final userId = _resolveViewerId(viewerId);
    // Not caught: see [getChildren].
    return _fetchItems('/Shows/$seriesId/Episodes', {
      'userId': userId,
      'enableUserData': userId != null,
      'fields': _browseFields,
      'sortBy': _dialect.episodeSortBy,
    }, cancelToken: cancelToken);
  }

  @override
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    final userId = _resolveViewerId(viewerId);
    if (userId == null) return const [];

    // Not caught: a read that failed throws, so the item's Contents say the
    // server did not answer, with a Retry, rather than "Nothing inside".
    {
      // The interface takes an id and nothing else, so that a detail route can be
      // reached from a deep link, which means the kind has to be discovered
      // here. It cannot be inferred from the id (every id is a GUID) and the
      // three shapes need three different endpoints, one of which needs an id
      // this method was not given: `/Shows/{seriesId}/Episodes` wants the
      // **series**, even when listing a single season, and a season id does not
      // contain its parent's.
      final item = await _fetchRawItem(
        itemId,
        userId,
        cancelToken: cancelToken,
      );
      if (item == null) return const [];

      final kind = jellyfinItemKind(item['Type']);
      switch (kind) {
        case StreamItemKind.series:
          // Unpaged by design: `/Shows/{id}/Seasons` takes no startIndex or
          // limit. A series has tens of seasons at worst.
          return await _fetchItems('/Shows/$itemId/Seasons', {
            'userId': userId,
            'enableUserData': true,
            'fields': _browseFields,
          }, cancelToken: cancelToken);
        case StreamItemKind.season:
          final seriesId = item['SeriesId']?.toString() ?? '';
          if (seriesId.isEmpty) return const [];
          return await _fetchItems('/Shows/$seriesId/Episodes', {
            'userId': userId,
            'seasonId': itemId,
            'enableUserData': true,
            'fields': _browseFields,
            // Aired order is what an episode list means; see
            // [MediaBrowserDialect.episodeSortBy].
            'sortBy': _dialect.episodeSortBy,
          }, cancelToken: cancelToken);
        case StreamItemKind.album:
          return await _fetchItems('/Items', {
            'userId': userId,
            'parentId': itemId,
            'recursive': false,
            'enableUserData': true,
            'fields': _browseFields,
            // Disc, then track. `SortName` on an album is alphabetical, which is
            // never what a track listing wants.
            'sortBy': 'ParentIndexNumber,IndexNumber,SortName',
            'sortOrder': 'Ascending',
          }, cancelToken: cancelToken);
        case StreamItemKind.movie:
        case StreamItemKind.episode:
        case StreamItemKind.track:
        case StreamItemKind.other:
          // A leaf. No request at all rather than one that returns an empty page.
          return const [];
      }
    }
  }

  /// Throws on a remote failure: an empty list is only ever a server that
  /// answered with no users. Swallowed, a server that was down read "This
  /// server reports no users" in the viewer picker, a claim nobody made.
  /// `/Items` played by the viewer, by `DatePlayed`; an episode is looked up
  /// as its series in one more read of the series it names.
  ///
  /// The order and the played flag are checked on the answer as well as
  /// asked for: a filter a server ignores would otherwise send its whole
  /// library back as what the viewer watched.
  @override
  Future<List<StreamWatched>> getRecentlyWatched({
    String? viewerId,
    int limit = 5,
    CancelToken? cancelToken,
  }) async {
    final userId = _resolveViewerId(viewerId);
    if (userId == null) return const [];
    try {
      final played = await _api.get(
        '/Items',
        queryParameters: {
          'userId': userId,
          'recursive': true,
          'includeItemTypes': 'Movie,Episode',
          'isPlayed': true,
          'sortBy': 'DatePlayed',
          'sortOrder': 'Descending',
          // Several episodes of one series fold into one title.
          'limit': limit * 4,
          'fields': _browseFields,
          'enableUserData': true,
        },
        cancelToken: cancelToken,
      );
      final watched = <(String, Map<String, dynamic>, DateTime)>[];
      for (final raw in _itemsOf(played.data)) {
        final user = raw['UserData'];
        if (user is! Map || user['Played'] != true) continue;
        final at = DateTime.tryParse('${user['LastPlayedDate'] ?? ''}');
        if (at == null) continue;
        final series = raw['Type'] == 'Episode' ? raw['SeriesId'] : null;
        watched.add((series is String ? series : '', raw, at));
      }
      watched.sort((a, b) => b.$3.compareTo(a.$3));

      final seriesIds = {
        for (final (series, _, _) in watched)
          if (series.isNotEmpty) series,
      };
      final seriesById = <String, Map<String, dynamic>>{};
      if (seriesIds.isNotEmpty) {
        final answer = await _api.get(
          '/Items',
          queryParameters: {
            'userId': userId,
            'ids': seriesIds.join(','),
            'fields': _browseFields,
          },
          cancelToken: cancelToken,
        );
        for (final raw in _itemsOf(answer.data)) {
          final id = raw['Id'];
          if (id is String) seriesById[id] = raw;
        }
      }

      final seen = <String>{};
      final result = <StreamWatched>[];
      for (final (series, raw, at) in watched) {
        final title = series.isEmpty ? raw : seriesById[series];
        final id = title?['Id'];
        if (title == null || id is! String || !seen.add(id)) continue;
        result.add((item: jellyfinStreamItemFromJson(title), playedAt: at));
        if (result.length == limit) break;
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  static Iterable<Map<String, dynamic>> _itemsOf(Object? data) sync* {
    final items = data is Map ? data['Items'] : null;
    if (items is! List) return;
    for (final item in items) {
      if (item is Map) yield item.cast<String, dynamic>();
    }
  }

  @override
  Future<List<StreamViewer>> getViewers() async {
    try {
      final users = await _dialect.users(_api);
      return users
          // A disabled account cannot watch anything, so offering it as a lens
          // would only ever produce empty rows. Filtered here rather than with
          // the `isDisabled` query parameter because that filter's polarity
          // changed across 10.x and an empty viewer list is a much worse failure
          // than one extra row.
          .where((user) => !user.isDisabled && user.id.isNotEmpty)
          .map((user) => user.toStreamViewer())
          .toList(growable: false);
    } on DioException catch (error) {
      // The user list is elevated. A household member's token is refused it,
      // and is itself the one person it can read as: listing nobody left that
      // token with "This server reports no users" and no way to choose itself,
      // so every per-viewer lens stayed asking for a viewer. A 403 from
      // something in front of the server is not the server's answer.
      if (error.response?.statusCode == 403 &&
          error.error is! AccessGatewayAnswer) {
        return _dialect.tokenUserAsViewer(_api, _userId);
      }
      rethrow;
    }
  }

  /// Which credential kind the slot holds, as the dialect reads it (Jellyfin
  /// asks `GET /Users/Me`). Never fails: an unanswered probe is
  /// [JellyfinCredentialKind.unknown], so a failure never withholds a tab that
  /// might have worked.
  Future<JellyfinCredentialKind> getCredentialKind() =>
      _dialect.credentialKind(_api);

  /// Household users with policy and last-activity fields intact.
  Future<List<JellyfinUserDto>> getUsers() => _dialect.users(_api);

  /// Authorized devices known by this server.
  ///
  /// `/Devices` is the one administration read that comes back paged, and the
  /// envelope has to come off **here**: `mapInIsolate` answers anything that
  /// is not a `List` with `const []`, so handing it the `Items` map would lose
  /// every row silently. `jellyfinDevicesFromJson` takes the rows.
  Future<List<JellyfinDevice>> getDevices() async {
    final response = await _api.get('/Devices');
    final raw = response.data;
    return mapInIsolate(
      raw is Map ? raw['Items'] : raw,
      jellyfinDevicesFromJson,
    );
  }

  /// Server maintenance jobs and their last execution result.
  Future<List<JellyfinScheduledTask>> getScheduledTasks() async {
    final response = await _api.get('/ScheduledTasks');
    return mapInIsolate(response.data, jellyfinTasksFromJson);
  }

  @override
  StreamImageSource? imageFor(String posterPath, {int? width}) {
    final path = posterPath.trim();
    if (path.isEmpty) return null;

    // A bare id rather than a path: a deep-linked detail screen knows the item
    // but not its artwork tag yet. Untagged, so it is cacheable but not
    // cache-busted: the tagged form from `jellyfinPosterPath` is preferred
    // everywhere it is available.
    final relative = path.contains('/') ? path : '/Items/$path/Images/Primary';

    if (relative.startsWith('http://') || relative.startsWith('https://')) {
      // Already absolute: hand it back without the credential. Jellyfin never
      // produces one of these, and attaching an admin key to a URL that might
      // point anywhere is not a risk worth taking for a poster.
      return (url: relative, headers: null);
    }

    // From the address under the dialect's base path, like every request: the
    // relative paths the mapper writes carry none, so one path serves both
    // servers and a poster that skipped the prefix would 404 without a word.
    final uri = Uri.parse(UrlUtils.buildUrl(_apiBase, relative));
    final query = {
      ...uri.queryParameters,
      if (width != null && width > 0) 'maxWidth': '$width',
    };

    // The credential travels as a header, never in the query string: a token in
    // the URL becomes part of `CachedNetworkImage`'s cache key, which puts it in
    // a file name on disk and in every log line that records the request.
    return (
      url: uri
          .replace(queryParameters: query.isEmpty ? null : query)
          .toString(),
      headers: {..._accessHeaders, ..._serviceHeaders},
    );
  }

  @override
  void close() => _api.close();

  /// Makes sure [libraryId]'s kind is known, fetching the library list once when
  /// it is not.
  ///
  /// The dashboard always lists libraries before a browse opens, so this is a
  /// no-op in the normal flow. It exists for the deep link: a detail route has to
  /// resolve from its path parameters alone, and `/services/jellyfin/library/<id>`
  /// arrives with no prior `getLibraries` call.
  Future<void> _ensureLibraryKind(String libraryId) async {
    if (_libraryKinds.containsKey(libraryId)) return;
    final lookup = _libraryKindLookup ??= getLibraries();
    // A join, not a surface: without the kind the browse goes on unfiltered,
    // so a failed lookup degrades here even though `getLibraries` throws.
    // Caching the failure (or an empty answer) would leave every browse
    // unfiltered for the life of the client, so the next call tries again.
    try {
      final libraries = await lookup;
      if (libraries.isEmpty) _libraryKindLookup = null;
    } catch (_) {
      _libraryKindLookup = null;
    }
  }

  /// Shared `/Items` parameters for the three non-personal lenses.
  Map<String, dynamic> _itemsBaseQuery(
    String libraryId,
    String? userId,
    int startIndex,
    int limit,
  ) {
    final includeItemTypes = _includeItemTypesFor(libraryId);
    return {
      'parentId': libraryId,
      // Without this, `/Items` returns the library's *folders* rather than what
      // is in them.
      'recursive': true,
      'startIndex': startIndex,
      'limit': limit,
      'fields': _browseFields,
      'enableImages': true,
      'includeItemTypes': ?includeItemTypes,
      // `UserData` is omitted from the response entirely unless both of these are
      // present, and without it every item reads as unwatched with no resume
      // point. Passed even on `recentlyAdded`, which does not *need* a viewer, so
      // that the row still shows progress for the configured one.
      'userId': ?userId,
      if (userId != null) 'enableUserData': true,
    };
  }

  /// The item type a library is about, or null when it is unknown or mixed.
  String? _includeItemTypesFor(String libraryId) {
    switch (_libraryKinds[libraryId]) {
      case StreamLibraryKind.movies:
        return 'Movie';
      case StreamLibraryKind.shows:
        // Series, not Episode: a TV library browses as shows. The episodes are
        // reached through [getChildren], two taps deeper.
        return 'Series';
      case StreamLibraryKind.music:
        return 'MusicAlbum';
      case StreamLibraryKind.photos:
      case StreamLibraryKind.other:
      case null:
        // Unknown or genuinely mixed: no filter is better than a wrong one, which
        // would render an empty library.
        return null;
    }
  }

  Future<List<StreamItem>> _fetchItems(
    String path,
    Map<String, dynamic> queryParameters, {
    CancelToken? cancelToken,
  }) async {
    final page = await _fetchItemsPage(
      path,
      queryParameters,
      cancelToken: cancelToken,
    );
    return page.items;
  }

  /// [_fetchItems] with the `BaseItemDtoQueryResult` envelope kept.
  ///
  /// [_JellyfinItemsPage.rows] is the count the *server* sent, before mapping
  /// dropped anything, because that is what a pager has to advance by.
  Future<_JellyfinItemsPage> _fetchItemsPage(
    String path,
    Map<String, dynamic> queryParameters, {
    CancelToken? cancelToken,
  }) async {
    final response = await _api.get(
      path,
      queryParameters: {
        for (final entry in queryParameters.entries)
          if (entry.value != null) entry.key: entry.value,
      },
      cancelToken: cancelToken,
    );
    final data = response.data;
    // Every paged endpoint answers `BaseItemDtoQueryResult`; the unpaged ones
    // (`/Shows/{id}/Seasons`) also wrap their array in `Items`, but a bare array
    // has shown up behind reverse proxies that unwrap single-key objects, so both
    // shapes are accepted.
    final raw = data is Map ? data['Items'] : data;
    return (
      items: await mapInIsolate(raw, jellyfinStreamItemsFromJson),
      rows: raw is List ? raw.length : 0,
      // Absent on the unwrapped shape and on some builds of `/Shows/NextUp`,
      // which is why it is nullable rather than defaulted. See
      // [_JellyfinItemsPage.toLibraryPage].
      total: data is Map ? intOrNull(data['TotalRecordCount']) : null,
    );
  }

  Future<Map<String, dynamic>?> _fetchRawItem(
    String itemId,
    String? userId, {
    CancelToken? cancelToken,
  }) => _dialect.rawItem(
    _api,
    itemId,
    viewerId: userId,
    cancelToken: cancelToken,
  );

  /// The viewer a per-user query should be issued for: the explicit argument,
  /// else the configured household member, else nobody.
  String? _resolveViewerId(String? viewerId) {
    final explicit = viewerId?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return _userId.isEmpty ? null : _userId;
  }
}

/// A `BaseItemDtoQueryResult` reduced to what a pager needs.
///
/// [rows] is the number of elements the *server* sent, which is deliberately not
/// `items.length`: mapping drops anything malformed, and a page whose rows all
/// failed to parse still has to move the offset forward rather than declare the
/// library finished.
typedef _JellyfinItemsPage = ({List<StreamItem> items, int rows, int? total});

extension _JellyfinItemsPageX on _JellyfinItemsPage {
  StreamLibraryPage toLibraryPage(int startIndex) {
    final nextStartIndex = startIndex + rows;
    final total = this.total;
    return StreamLibraryPage(
      items: items,
      nextStartIndex: nextStartIndex,
      // With a `TotalRecordCount` this is arithmetic. Without one (the
      // unwrapped shape, and some builds of `/Shows/NextUp`) the only honest
      // signal is "the server sent rows", so the pager asks once more and stops
      // on the empty answer.
      hasMore: total == null ? rows > 0 : nextStartIndex < total,
    );
  }
}

/// One band of a `/Search/Hints` answer: the word the strip prints, the raw
/// `Type` it collects, and the shared kind when there is one.
///
/// [kind] is null where `StreamItemKind` has no entry: a person and a book are
/// both `other` to the item model, and the bands must not merge because of it.
typedef JellyfinSearchBand = ({
  String label,
  String type,
  StreamItemKind? kind,
});

/// The six bands a Jellyfin search asks for, in the order the page draws them.
///
/// Fixed rather than derived from the answer, because an empty band is itself
/// the result: "Episodes 0" says this server holds no matching episode, which is
/// a different statement from never having looked.
const List<JellyfinSearchBand> kJellyfinSearchBands = [
  (label: 'Movies', type: 'Movie', kind: StreamItemKind.movie),
  (label: 'Shows', type: 'Series', kind: StreamItemKind.series),
  (label: 'Episodes', type: 'Episode', kind: StreamItemKind.episode),
  (label: 'Albums', type: 'MusicAlbum', kind: StreamItemKind.album),
  (label: 'Books', type: 'Book', kind: null),
  (label: 'People', type: 'Person', kind: null),
];

/// Where hits land that none of [kJellyfinSearchBands] claims.
const String kJellyfinSearchOtherBandLabel = 'Other';

/// Total hints one search asks for, across every band.
///
/// Small on purpose: a library search is answered by a person reading five rows,
/// not by a pager. The endpoint's own default is 10 and is not enough to fill
/// six bands.
const int kJellyfinSearchLimit = 40;

/// The title a player draws above a message from Cupola.
const String kJellyfinMessageHeader = kJellyfinClientName;

/// How long a sent message stays on the player's screen.
///
/// Milliseconds: `MessageCommand.TimeoutMs` is the one Jellyfin field in this
/// file that is not in ticks. Eight seconds is long enough to read a sentence
/// over a film and short enough not to sit on top of one.
const int kJellyfinMessageTimeoutMs = 8000;

/// What Jellyfin's Dashboard → Devices list calls this app.
const String kJellyfinClientName = kAppName;

/// Sent as `Version` in the `Authorization` header. Cosmetic: it appears beside
/// the client name in the server's device list, and tracks `pubspec.yaml`.
const String kJellyfinClientVersion = '0.8.0';

/// The `Device` value: which platform this install is.
String defaultJellyfinDeviceName() => Platform.operatingSystem;

/// A `DeviceId` that is stable for the life of the install without storing
/// anything.
///
/// Jellyfin registers a device row per distinct id it sees, so a value
/// regenerated each launch would litter the user's dashboard with a permanent
/// row per app start: the same trap `settings.plexClientId` exists to avoid.
/// Plex needed a persisted random identifier because its id is also an identity;
/// Jellyfin's is only a label, and an API key creates no session against it at
/// all, so deriving it deterministically is enough and costs no settings field
/// (and no `uuid` dependency, which this project does not have).
///
/// Hashed rather than used raw so the value looks like the opaque id the API
/// expects and carries nothing about the host.
String defaultJellyfinDeviceId([String? deviceName]) {
  final seed = 'cupola.jellyfin:${deviceName ?? defaultJellyfinDeviceName()}';
  return sha256.convert(seed.codeUnits).toString().substring(0, 32);
}

/// A user-scoped read asked of a Jellyfin connection whose household member
/// nobody has chosen: the API key sees every user and is none of them.
class JellyfinViewerRequired implements Exception {
  const JellyfinViewerRequired();

  @override
  String toString() => 'Jellyfin needs to know which user you are';
}
