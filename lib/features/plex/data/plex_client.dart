import 'dart:convert';
import 'dart:isolate';

import 'package:cupola/core/app_identity.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/plex/domain/models/plex_item_mapper.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_library_page.dart';
import 'package:cupola/features/stream/domain/models/stream_search_group.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Identifies Cupola to the user's server. Plex shows this in
/// Settings → Authorized Devices, so it is a name a stranger has to recognise as
/// theirs.
const String kPlexProduct = kAppName;

/// Sent as `X-Plex-Version`.
///
/// It used to track `pubspec.yaml`'s `version:` *by hand*, and by the time
/// anyone looked it said 0.8.0 against a pubspec at 1.0.0; so every Plex
/// server in the world had Cupola filed under a version it stopped being two
/// releases ago. It now reads [kAppVersion], which is the one const the app
/// prints for itself and which a test measures against the pubspec.
///
/// The reasoning that made this a const in the first place still holds: the
/// project takes no new dependencies, and `package_info_plus` would be one.
const String kPlexProductVersion = kAppVersion;

/// Sent as `X-Plex-Device-Name`, i.e. the row label in Authorized Devices.
const String kPlexDeviceName = kAppName;

/// The reason attached to a terminate call.
///
/// Plex forwards this string to the player, where the viewer sees it as the
/// explanation for their stream stopping. It is therefore an API payload rather
/// than app chrome, which is why it lives here and not in a widget.
const String kPlexTerminationReason = 'Stopped from Cupola';

/// Poster aspect used when asking Plex's photo transcoder to resize.
///
/// [StreamServerClient.imageFor] offers a width only, and `/photo/:/transcode`
/// requires both dimensions. With `minSize=1` Plex fits the image inside the box
/// preserving its own aspect, so this is a bounding height rather than a crop:
/// 2:3 is the poster ratio every library in the app already lays out to.
const double _kPosterHeightRatio = 3 / 2;

/// Default page size for a library browse.
const int kPlexLibraryPageSize = 50;

/// Rows per hub for `/hubs/search`.
///
/// **Per hub, not in total**: Plex's own default is 3, which is too few to tell
/// "one match" from "the band was truncated", and a search that returns six
/// bands of 12 is still a page a person reads rather than pages.
const int kPlexSearchHubLimit = 12;

/// What the token's owner is called when Plex will not say.
///
/// `myPlexUsername` is absent on a server that has never been claimed through
/// plex.tv, and there is no other endpoint that names the account a token
/// belongs to.
const String kPlexOwnerFallbackName = 'This account';

/// What an unwrapped, band-less hub response is called.
///
/// Reached only on the builds that answer a hub request with a bare `Metadata`
/// array. There is no server-given title to print, and an empty string would
/// draw a nameless pill.
const String kPlexUngroupedHubLabel = 'Results';

/// Plex's own type ids for `/library/sections/{id}/all?type=`.
const int _kPlexTypeMovie = 1;
const int _kPlexTypeShow = 2;
const int _kPlexTypeArtist = 8;

/// Plex's non-standard "token expired" status, alongside the ordinary 401.
const int _kPlexTokenExpiredStatus = 498;

/// What the user has to fix when a reply is not JSON.
///
/// Plex answers XML unless `Accept: application/json` reaches it, so naming XML
/// is the whole point of the message: the two things the user can act on are the
/// address and whatever sits between here and it rewriting the header. Shared so
/// the two places that detect it: a body `jsonDecode` refuses, and a body Dio's
/// own transformer refused before this file ever saw it. Say the same thing.
/// The third case, a body that visibly starts with `<`, gets its own wording
/// because there the XML is not a guess.
const String kPlexNotJsonMessage =
    'The server did not answer JSON. Plex serves XML unless the Accept header '
    'reaches it, so check that the address points at Plex Media Server and that '
    'nothing between here and it rewrites Accept.';

/// Row count above which a `Metadata` array is mapped off the main isolate.
///
/// Below it the isolate spawn costs more than the mapping does: a season of
/// episodes or a hub row is a handful of objects, while a `titleSort` page of a
/// film library is hundreds, each with nested `Media`/`Part`/`Stream` arrays.
const int _kIsolateMappingThreshold = 50;

/// Error thrown by [PlexClient].
///
/// Carries [reason] so onboarding can distinguish an unreachable box from a
/// rejected token, and [tokenIssue] so it can distinguish *which* token problem:
/// a 401 asks for a fresh paste, whereas a JWT can never be made to work here at
/// all and the user needs different advice.
class PlexException implements Exception, HasFailureReason, HasFailureCause {
  const PlexException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
    this.tokenIssue = PlexTokenIssue.none,
    this.cause,
  });

  /// The failure this wraps, when it wraps one: what it knew (which gateway
  /// answered, for one) survives the wrapping.
  final Object? cause;

  @override
  Object? get failureCause => cause;

  final String message;

  @override
  final ServiceFailureReason reason;

  final PlexTokenIssue tokenIssue;

  @override
  String toString() => 'PlexException: $message';
}

/// Plex Media Server client.
///
/// **Never contacts plex.tv.** Every capability below is served by the box the
/// user pasted an address for: `/identity` for reachability, `/` for the
/// capability sheet, `/status/sessions` for live playback, `/library/*` for the
/// collection. That constraint is what shapes the two visible asymmetries with
/// Jellyfin: [getViewers] returns exactly one person, and [verifyCredential]
/// refuses a JWT outright instead of refreshing it, because both would
/// otherwise require a plex.tv round trip.
///
/// Transport is [ApiClient.authenticatedBy] rather than a bespoke `Dio`, which
/// is not a stylistic choice: it carries `SameOriginRedirectInterceptor`, and
/// without it a single 302 from a misconfigured reverse proxy would replay the
/// user's `X-Plex-Token` to a host they never configured.
class PlexClient implements StreamServerClient {
  PlexClient({
    required String url,
    required String token,
    required String clientIdentifier,
    String product = kPlexProduct,
    String productVersion = kPlexProductVersion,
    String? platform,
    String deviceName = kPlexDeviceName,
    String? pinnedCertFingerprint,
    Map<String, String> accessHeaders = const {},
    ServiceKey? onlyAtHome,
  }) : baseUrl = UrlUtils.normalizeBaseUrl(url),
       _accessHeaders = accessHeaders,
       _token = token.trim(),
       _clientIdentifier = clientIdentifier.trim(),
       _product = product,
       _productVersion = productVersion,
       _platform = platform ?? _defaultPlatform(),
       _deviceName = deviceName {
    _api = ApiClient.authenticatedBy(
      baseUrl: baseUrl,
      headers: _headers(),
      pinnedCertFingerprint: pinnedCertFingerprint,
      accessHeaders: accessHeaders,
      onlyAtHome: onlyAtHome,
    );
  }

  final String baseUrl;

  /// What the connection presents to a gateway in front of Plex, on every
  /// request and every poster.
  final Map<String, String> _accessHeaders;
  final String _token;
  final String _clientIdentifier;
  final String _product;
  final String _productVersion;
  final String _platform;
  final String _deviceName;

  late final ApiClient _api;

  /// Section id → kind, filled by [getLibraries].
  ///
  /// A lens has to know whether a section holds films or shows before it can be
  /// expressed as a filter: `unwatched=1` is the movie form and
  /// `show.unwatchedLeaves=1` the show form, and sending the wrong one returns
  /// the whole library instead of an error. Caching the answer keeps a browse
  /// from re-reading `/library/sections` on every page.
  final Map<String, StreamLibraryKind> _sectionKinds = {};

  /// Lets a test attach a stubbed transport while leaving the header building,
  /// the part most worth asserting on, under test.
  @visibleForTesting
  ApiClient get api => _api;

  /// The client-identity headers Plex expects on **every** request.
  ///
  /// `X-Plex-Client-Identifier` is the one that matters operationally: Plex
  /// registers a new device row per distinct value, so it comes from persisted
  /// settings rather than being minted here. `Accept: application/json` is
  /// supplied by [ApiClient] and is mandatory: the API answers XML by default,
  /// and every parse in this file would fail on it.
  Map<String, String> _headers() {
    return {
      // Omitted rather than sent empty when there is no token yet, so an
      // onboarding reachability probe against `/identity` is a clean
      // unauthenticated request instead of one carrying a blank credential.
      if (_token.isNotEmpty) 'X-Plex-Token': _asciiHeader(_token),
      'X-Plex-Client-Identifier': _asciiHeader(_clientIdentifier),
      'X-Plex-Product': _asciiHeader(_product),
      'X-Plex-Version': _asciiHeader(_productVersion),
      'X-Plex-Platform': _asciiHeader(_platform),
      'X-Plex-Device-Name': _asciiHeader(_deviceName),
    };
  }

  /// Headers that authenticate an artwork request.
  ///
  /// The token stays in a header so it never reaches `CachedNetworkImage`'s
  /// cache key, which is the resolved URL: a token in the query string would be
  /// written to the on-disk cache index and invalidate every cached poster the
  /// day the user rotates it.
  Map<String, String> get _imageHeaders => {
    ..._accessHeaders,
    if (_token.isNotEmpty) 'X-Plex-Token': _asciiHeader(_token),
    'X-Plex-Client-Identifier': _asciiHeader(_clientIdentifier),
  };

  /// Strips everything outside printable ASCII from a header value.
  ///
  /// Two reasons, both real. `dart:io` writes header values as Latin-1 and
  /// throws on anything it cannot encode, so a non-ASCII device name would turn
  /// every request into a `FormatException` rather than a connection error. And
  /// dropping CR/LF closes header injection on the two values that come from
  /// outside this file: the pasted token and the persisted client id.
  static String _asciiHeader(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x20 && rune <= 0x7e) buffer.writeCharCode(rune);
    }
    return buffer.toString().trim();
  }

  /// What Plex should call this platform in Authorized Devices.
  static String _defaultPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  /// Fetches [path] and returns its `MediaContainer`.
  ///
  /// Every Plex response is wrapped in one, including the ones that carry only
  /// attributes (`/identity`, `/`), so unwrapping in one place is what keeps the
  /// twelve call sites below from each re-deciding what a malformed reply means.
  Future<Map<String, dynamic>> _container(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _api.get(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );
      return _mediaContainer(response.data);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  static Map<String, dynamic> _mediaContainer(dynamic raw) {
    var decoded = raw;
    if (decoded is String) {
      final text = decoded.trimLeft();
      if (text.startsWith('<')) throw _xmlAnswer;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw const PlexException(
          kPlexNotJsonMessage,
          reason: ServiceFailureReason.notFound,
        );
      }
    }
    if (decoded is Map) {
      final container = decoded['MediaContainer'];
      if (container is Map) return container.cast<String, dynamic>();
    }
    throw const PlexException(
      'The Plex API did not answer at this address.',
      reason: ServiceFailureReason.notFound,
    );
  }

  /// Plex serves XML unless `Accept: application/json` is honoured. An
  /// answer that starts with `<` means either the header was stripped in
  /// transit (a reverse proxy that rewrites Accept) or the address points at
  /// something that is not a Plex server. Both are configuration problems, and
  /// saying so beats the `FormatException` a bare `jsonDecode` would raise.
  static const _xmlAnswer = PlexException(
    'The server answered XML instead of JSON. Check that the address '
    'points at Plex and that nothing between here and it rewrites the '
    'Accept header.',
    reason: ServiceFailureReason.notFound,
  );

  PlexException _mapDioError(DioException error) {
    final status = error.response?.statusCode;
    // Something in front of Plex answered: its 401 says nothing about the
    // token, which Plex never saw.
    if (error.error is AccessGatewayAnswer) {
      return PlexException(
        error.message ?? 'Plex request failed',
        reason: ServiceFailureReason.accessGateway,
        cause: error,
      );
    }
    // An answer that is not JSON. The shared client's answer guard raises it
    // for a body that does not decode (`UnexpectedAnswer`), and Dio's
    // transformer for one labelled `application/json` that does not parse:
    // either way the Plex API is not what answered, which is this client's
    // `notFound`, with the XML sentence when the body starts like markup.
    final unexpected = error.error;
    if (unexpected is UnexpectedAnswer) {
      final text = unexpected.bodyPrefix?.trimLeft() ?? '';
      return text.startsWith('<')
          ? _xmlAnswer
          : const PlexException(
              kPlexNotJsonMessage,
              reason: ServiceFailureReason.notFound,
            );
    }
    if (error.error is FormatException) {
      return const PlexException(
        kPlexNotJsonMessage,
        reason: ServiceFailureReason.notFound,
      );
    }
    if (status == 401 || status == _kPlexTokenExpiredStatus) {
      return const PlexException(
        'Plex rejected the token. Copy a fresh X-Plex-Token from the server '
        'and paste it again.',
        reason: ServiceFailureReason.unauthorized,
        tokenIssue: PlexTokenIssue.rejected,
      );
    }
    return PlexException(
      error.message ?? 'Plex request failed',
      reason: classifyConnectionFailure(error),
      cause: error,
    );
  }

  /// Refuses to send a token that cannot work, before it is sent.
  ///
  /// A plex.tv JWT authenticates for seven days and is refreshable only through
  /// plex.tv, which this client will not call. Letting it through would buy a
  /// week of working software followed by a failure the user has no way to read.
  void _assertUsableToken() {
    if (inspectPlexToken(_token) == PlexTokenIssue.jsonWebToken) {
      throw const PlexException(
        'That is a temporary plex.tv sign-in token: it expires in seven days, '
        'and only plex.tv can renew it. Paste a device token from your server '
        'instead.',
        reason: ServiceFailureReason.unauthorized,
        tokenIssue: PlexTokenIssue.jsonWebToken,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Reachability and credential
  // ---------------------------------------------------------------------------

  /// `GET /identity`, the only Plex endpoint that needs no credential.
  ///
  /// Using it means "the box is down" and "the token is wrong" can never arrive
  /// as the same error: this answers 200 for a valid address regardless of the
  /// token, so a null here is always about reachability.
  @override
  Future<String?> probeVersion() async {
    try {
      return (await getIdentity())?.version;
    } catch (_) {
      return null;
    }
  }

  Future<PlexServerIdentity?> getIdentity() async {
    try {
      return PlexServerIdentity.fromMediaContainer(
        await _container('/identity'),
      );
    } catch (_) {
      return null;
    }
  }

  /// The Dashboard's probe: proves the token, and names the version.
  ///
  /// [probeVersion] reads `/identity`, which answers anyone, so a Plex with a
  /// wrong token read as answering while every screen behind it failed.
  /// `GET /` is the cheapest authenticated read: it 401s on a bad token:
  /// thrown as unauthorized, and carries the version.
  Future<String?> checkCredentialAndVersion() async {
    _assertUsableToken();
    return PlexServerCapabilities.fromMediaContainer(
      await _container('/'),
    ).version;
  }

  /// Whether the token is accepted, via `GET /`, which 401s on a bad one.
  ///
  /// Returns false only for an actual refusal. A timeout or a DNS failure
  /// rethrows, because answering "the credential is wrong" to an unreachable
  /// host is how a user ends up rotating a token that was never the problem.
  @override
  Future<bool> verifyCredential() async {
    _assertUsableToken();
    if (_token.isEmpty) return false;
    try {
      await _container('/');
      return true;
    } on PlexException catch (e) {
      if (e.tokenIssue == PlexTokenIssue.rejected) return false;
      rethrow;
    }
  }

  /// `GET /`: friendly name, version, and the Plex Pass flag that decides
  /// whether stopping a stream is even offered.
  ///
  /// Throws on a remote failure. It used to answer null for any failure, and
  /// the Overview's Server section read a Plex that did not answer as one
  /// that "did not describe itself", and [getViewers] as a server with nobody
  /// on it.
  Future<PlexServerCapabilities> getCapabilities() async {
    return PlexServerCapabilities.fromMediaContainer(await _container('/'));
  }

  // ---------------------------------------------------------------------------
  // Sessions
  // ---------------------------------------------------------------------------

  /// `GET /status/sessions`, most expensive first.
  ///
  /// Mapped on the main isolate on purpose, unlike the library lists below: a
  /// server with thirty concurrent streams is extraordinary, and spawning an
  /// isolate to map a dozen objects costs more than the map.
  ///
  /// Throws on a remote failure, like [getSessionsOrThrow], which it now is:
  /// answering a dark server with `const []` drew "Nobody is watching right
  /// now" about a server nobody could ask.
  @override
  Future<List<StreamSession>> getSessions({CancelToken? cancelToken}) =>
      getSessionsOrThrow(cancelToken: cancelToken);

  /// The session read with its transport or parse failure preserved.
  ///
  /// The name predates [getSessions] surfacing its own failure; the KPI and
  /// reachability readers still call it by this one. `0 streams` is a real
  /// answer only when `/status/sessions` answered with no active sessions.
  Future<List<StreamSession>> getSessionsOrThrow({
    CancelToken? cancelToken,
  }) async {
    final container = await _container(
      '/status/sessions',
      cancelToken: cancelToken,
    );
    // An idle Plex server sends `{"size": 0}` with **no `Metadata` key at
    // all**, not an empty array, the way Jellyfin does. `container['Metadata']
    // as List` throws here, and this is the single most common shape trap in
    // the API because the happy path never exercises it.
    final metadata = container['Metadata'];
    if (metadata is! List) return const [];

    final sessions = metadata
        .whereType<Map>()
        .map((raw) => plexSessionFromJson(raw.cast<String, dynamic>()))
        .nonNulls
        .toList();

    // Cost order, so the session actually charging the box for something is at
    // the top. Bitrate breaks ties within a method.
    sessions.sort((a, b) {
      final byMethod = b.playMethod.index.compareTo(a.playMethod.index);
      if (byMethod != 0) return byMethod;
      return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });
    return sessions;
  }

  /// `POST /status/sessions/terminate`.
  ///
  /// [sessionId] must be the nested `Session.id`. `sessionKey` and
  /// `Player.machineIdentifier` sit on the same object and both produce a 404,
  /// which is why [plexSessionFromJson] reads only the first.
  ///
  /// A write action, so failures surface, and they are surfaced *specifically*,
  /// because Plex's two error codes here mean the opposite of what they usually
  /// do: 401 documents "the server does not have the feature enabled" (a Plex
  /// Pass gate, not a bad token) and 403 documents "sessionId is empty" (not a
  /// permission problem). Reporting either as "your token expired" would send the
  /// user to re-paste a credential that is working.
  @override
  Future<void> stopSession(
    String sessionId, {
    String reason = kPlexTerminationReason,
  }) async {
    _assertUsableToken();

    final id = sessionId.trim();
    if (id.isEmpty) {
      // A `/status/sessions` entry with no nested `Session` element has no id,
      // so there is nothing to terminate. Caught here rather than sent as an
      // empty parameter, which the server answers with a 403 whose message is
      // about permissions.
      throw const PlexException(
        'Plex did not give this stream a session id, so it cannot be stopped '
        'from here.',
        reason: ServiceFailureReason.notFound,
      );
    }

    try {
      // `sessionId` is case-sensitive with a capital I; Dio percent-encodes the
      // reason.
      await _api.post(
        '/status/sessions/terminate',
        queryParameters: {'sessionId': id, 'reason': reason},
      );
    } on DioException catch (e) {
      throw await _mapTerminateError(e);
    }
  }

  Future<PlexException> _mapTerminateError(DioException error) async {
    if (error.error is AccessGatewayAnswer) return _mapDioError(error);
    final status = error.response?.statusCode;
    if (status == 401) {
      // The session list just answered with this same token, so it reads,
      // but a 401 here has more than one cause and the reply does not say
      // which. Termination needs Plex Pass on the server *and* the server
      // owner's token: a home, managed or shared user's token reads sessions
      // and is refused this (community-reported; Plex does not document it).
      // Ask the server about the one cause it can confirm, and never claim the
      // token is fine, because for a non-owner it is exactly the problem.
      // Only a cause the server can confirm: a sheet that does not answer
      // now leaves the general refusal below.
      PlexServerCapabilities? capabilities;
      try {
        capabilities = await getCapabilities();
      } catch (_) {
        capabilities = null;
      }
      if (capabilities?.myPlexSubscription == false) {
        return const PlexException(
          'Stopping a stream is a Plex Pass feature, and this server does not '
          'have one.',
          reason: ServiceFailureReason.unauthorized,
        );
      }
      return const PlexException(
        'Plex refused to stop this stream. Only the server owner\'s token can '
        'stop streams; a home or shared user\'s token can see them but not '
        'stop them.',
        reason: ServiceFailureReason.unauthorized,
      );
    }
    if (status == 403) {
      return const PlexException(
        'The server did not accept that session id. Refresh the list and '
        'retry.',
        reason: ServiceFailureReason.notFound,
      );
    }
    return _mapDioError(error);
  }

  // ---------------------------------------------------------------------------
  // Libraries
  // ---------------------------------------------------------------------------

  /// `GET /library/sections`.
  ///
  /// Populates [_sectionKinds] as a side effect, which is what lets a lens be
  /// built later without a second round trip.
  ///
  /// Throws on a remote failure, like [getLibrariesOrThrow], which it now is.
  @override
  Future<List<StreamLibrary>> getLibraries({CancelToken? cancelToken}) =>
      getLibrariesOrThrow(cancelToken: cancelToken);

  /// The library read with its transport or parse failure preserved, so an
  /// unreachable server cannot become `Libraries 0`. The name predates
  /// [getLibraries] surfacing its own failure.
  Future<List<StreamLibrary>> getLibrariesOrThrow({
    CancelToken? cancelToken,
  }) async {
    final container = await _container(
      '/library/sections',
      cancelToken: cancelToken,
    );
    final directories = container['Directory'];
    if (directories is! List) return const [];

    final libraries = <StreamLibrary>[];
    for (final raw in directories.whereType<Map>()) {
      final library = plexLibraryFromJson(raw.cast<String, dynamic>());
      if (library == null) continue;
      _sectionKinds[library.id] = library.kind;
      libraries.add(library);
    }
    return libraries;
  }

  /// How many items a section holds, without downloading any of them.
  ///
  /// `X-Plex-Container-Size=0` returns a page of nothing alongside the
  /// `totalSize`, the cheapest count Plex offers. Kept off [getLibraries]
  /// deliberately: doing it there would turn one request into one-per-section on
  /// every dashboard load, which is why `StreamLibrary.itemCount` arrives null
  /// and this is opt-in. Nothing in `lib/` called it until the pushed Libraries
  /// page existed to pay for it, one card at a time (decision 21).
  @override
  Future<int?> getLibraryItemCount(
    String libraryId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final kind = await _sectionKind(libraryId);
      final type = _primaryTypeFor(kind);
      final container = await _container(
        '/library/sections/${_pathSegment(libraryId)}/all',
        queryParameters: {
          'type': ?type,
          'X-Plex-Container-Start': 0,
          'X-Plex-Container-Size': 0,
        },
        cancelToken: cancelToken,
      );
      return plexInt(container['totalSize']) ?? plexInt(container['size']);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Library items
  // ---------------------------------------------------------------------------

  /// One page of a library under one lens.
  ///
  /// [viewerId] is accepted to satisfy [StreamServerClient] and then **ignored**,
  /// and the reason is structural rather than an omission: on Plex the token *is*
  /// the user. `/library/*` has no `accountID` and no impersonation parameter, so
  /// `viewCount`, `viewOffset`, `unwatched` and `onDeck` can only ever describe
  /// the token's owner. The only way to read another household member's state is
  /// to hold their token, and tokens are obtainable only from plex.tv. See
  /// [getViewers].
  @override
  Future<StreamLibraryPage> getLibraryPage({
    required String libraryId,
    StreamLibrarySort sort = StreamLibrarySort.name,
    bool unplayedOnly = false,
    String? viewerId,
    int startIndex = 0,
    int limit = kPlexLibraryPageSize,
    CancelToken? cancelToken,
  }) async {
    final page = await getLibraryItemsPage(
      libraryId: libraryId,
      sort: sort,
      unplayedOnly: unplayedOnly,
      startIndex: startIndex,
      limit: limit,
      cancelToken: cancelToken,
    );
    if (page == null) {
      return StreamLibraryPage.failed(startIndex: startIndex);
    }
    return StreamLibraryPage(
      items: page.items,
      // The server's own accounting, which is the whole reason [PlexPage]
      // exists: the on-deck lenses drop rows *after* the container is counted,
      // so a page that kept nothing still has to advance the offset instead of
      // ending the list.
      nextStartIndex: page.nextOffset,
      hasMore: page.hasMore,
    );
  }

  /// One page of a library with Plex's paging envelope, or **null** when the
  /// request failed.
  ///
  /// The extra return value is not decoration. Plex's guidance is that a
  /// response "might include a different number of items than requested", so a
  /// pager has to advance by `MediaContainer.offset + size` and stop at
  /// `totalSize` rather than by the page size it asked for. Returning only a
  /// `List`, as the shared interface must, since Jellyfin reports its totals
  /// differently: throws exactly the numbers a pager needs away.
  ///
  /// Null rather than `PlexPage.empty()` on failure, because an empty page and
  /// a failed request are the two things a browse must never conflate: see
  /// [StreamLibraryPage].
  Future<PlexPage<StreamItem>?> getLibraryItemsPage({
    required String libraryId,
    StreamLibrarySort sort = StreamLibrarySort.name,
    bool unplayedOnly = false,
    int startIndex = 0,
    int limit = kPlexLibraryPageSize,
    CancelToken? cancelToken,
  }) async {
    try {
      final kind = await _sectionKind(libraryId);
      final request = _shelfRequest(libraryId, sort, kind, unplayedOnly);

      final container = await _container(
        request.path,
        queryParameters: {
          ...request.query,
          // Both parameters, always. Plex accepts them as headers or query args
          // and honours neither half on its own: a start without a size returns
          // the server's default page, and a size without a start silently
          // re-reads page one.
          'X-Plex-Container-Start': startIndex,
          'X-Plex-Container-Size': limit,
          // The item's own ids, which send a movie's tile to the movie's own
          // page (`MediaKey.ofStreamItem`).
          'includeGuids': 1,
        },
        cancelToken: cancelToken,
      );

      return await _pageFromContainer(container, startIndex);
    } catch (_) {
      return null;
    }
  }

  /// `GET /library/metadata/{ratingKey}`.
  ///
  /// `checkFiles=0` and `skipRefresh=1` are not micro-optimisations: a bare GET
  /// here makes the server stat every file in the item and can kick off an agent
  /// refresh, both synchronously, which on a spun-down NAS turns opening a detail
  /// page into a thirty-second wait and a disk spin-up.
  @override
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    try {
      final container = await _container(
        '/library/metadata/${_pathSegment(itemId)}',
        queryParameters: {'checkFiles': 0, 'skipRefresh': 1},
        cancelToken: cancelToken,
      );
      final metadata = container['Metadata'];
      if (metadata is! List) return null;
      final first = metadata.whereType<Map>().firstOrNull;
      if (first == null) return null;
      return plexItemFromJson(first.cast<String, dynamic>());
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
      final container = await _container(
        '/library/metadata/${_pathSegment(id)}',
        // `Guid[]` is only sent when asked for. The same two flags as
        // [getItem]: no stat of the files, no agent refresh.
        queryParameters: {'includeGuids': 1, 'checkFiles': 0, 'skipRefresh': 1},
        cancelToken: cancelToken,
      );
      final metadata = container['Metadata'];
      final first = metadata is List
          ? metadata.whereType<Map>().firstOrNull
          : null;
      if (first == null) return null;
      final item = plexItemFromJson(first.cast<String, dynamic>());
      // Only the item itself names its page.
      return item == null || item.id != id.trim() || !kinds.contains(item.kind)
          ? null
          : MediaKey.ofStreamItem(item);
    } catch (_) {
      return null;
    }
  }

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
    // The ids the arr offered, cheapest first: TMDB is what Radarr carries and
    // what Plex's Movie agent writes.
    final guids = <String>[
      if (tmdbId != null && tmdbId.isNotEmpty) 'tmdb://$tmdbId',
      if (tvdbId != null && tvdbId.isNotEmpty) 'tvdb://$tvdbId',
      if (imdbId != null && imdbId.isNotEmpty) 'imdb://$imdbId',
    ];
    final query = StreamExternalQuery(
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      imdbId: imdbId,
      kind: kind,
      title: title,
      year: year,
    );

    // A hit is only a hit once the item's own `Guid[]` agrees: see
    // `stream_external_match.dart`. A server that does not honour `?guid=`
    // answers 200 with the whole library rather than an error, and a server that
    // does can still hand back a film for a show's TMDB number, so neither the
    // status nor the first row is evidence.
    // Nothing to ask by, so nothing to verify: no claim either way.
    if (guids.isEmpty) return const StreamExternalLookup.notVerified();

    // Plex filters `?guid=` on an item's own guid (`plex://movie/…`), never on
    // its `Guid[]` entries: a current server answers `?guid=tmdb://603` with no
    // rows from a library that holds The Matrix. So an external id is first
    // turned into Plex's own guid by the server's matcher, the one its Fix
    // Match dialog asks, and the library is filtered on that. Only this answer
    // can say a title is not in the library.
    switch (await _resolvePlexGuid(guids, kind, cancelToken)) {
      case _PlexGuidResolved(:final guid):
        final container = await _container(
          '/library/all',
          queryParameters: {
            'guid': guid,
            'includeGuids': 1,
            'X-Plex-Container-Start': 0,
            'X-Plex-Container-Size': _kExternalMatchCandidates,
          },
          cancelToken: cancelToken,
        );
        final items = await _itemsFromAsync(container['Metadata']);
        final match = bestStreamExternalMatch(items, query);
        if (match != null) return StreamExternalLookup.found(match);
        return items.isEmpty
            ? const StreamExternalLookup.notInLibrary()
            : const StreamExternalLookup.notVerified();
      case _PlexGuidNoLibrary():
        // No library of this kind at all: nothing to find it in.
        return const StreamExternalLookup.notInLibrary();
      case _PlexGuidUnresolved():
        // The matcher could not be asked (every library of the kind on an old
        // agent, or the server unable to reach Plex's metadata): the direct
        // probe below, whose empty answer proves nothing.
        break;
    }

    StreamItem? best;
    var bestScore = -1;
    // Whether any round answered at all: when none did, the failure is the
    // answer.
    var answered = false;
    Object? lastFailure;
    for (final guid in guids) {
      try {
        final container = await _container(
          '/library/all',
          queryParameters: {
            'guid': guid,
            // Without this the response omits Guid entries and a row could
            // only be checked by its title.
            'includeGuids': 1,
            // Bounded, because a server that ignores `?guid=` answers with the
            // whole library, and none of it would be verified anyway. A real
            // answer is one to three rows.
            'X-Plex-Container-Start': 0,
            'X-Plex-Container-Size': _kExternalMatchCandidates,
          },
          cancelToken: cancelToken,
        );
        final items = await _itemsFromAsync(container['Metadata']);
        answered = true;
        final match = bestStreamExternalMatch(items, query);
        if (match == null) continue;
        final score = streamExternalMatchScore(match, query) ?? -1;
        // Confirmed by every id the arr offered: nothing a further round trip
        // could find would be better supported.
        if (score >= query.idCount) return StreamExternalLookup.found(match);
        if (score > bestScore) {
          best = match;
          bestScore = score;
        }
      } catch (error) {
        // An unanswered id is not evidence against the title; try the next.
        lastFailure = error;
        continue;
      }
    }
    final verified = best;
    if (verified != null) return StreamExternalLookup.found(verified);
    // No round answered: that is the answer, and it is not "not there".
    final failure = lastFailure;
    if (!answered && failure != null) throw failure;
    // Answered, and found nothing it could verify: a current server answers
    // an external id with no rows whether or not it holds the title, so this
    // is no claim either way.
    return const StreamExternalLookup.notVerified();
  }

  /// How many rows one `?guid=` probe reads: see [lookupByExternalId].
  static const int _kExternalMatchCandidates = 10;

  /// The item each section type's matcher asks through, by type (`movie`,
  /// `show`); see [_matchAnchor].
  final Map<String, Future<_PlexMatchAnchor>> _matchAnchors = {};

  /// An external guid on a section type (`movie|tmdb://603`) → Plex's own
  /// (`plex://movie/…`), as the matcher answered: a title keeps its guid.
  final Map<String, String> _plexGuids = {};

  /// Plex's own guid for the first of [guids] its matcher knows, on the
  /// section types [kind] can be in.
  ///
  /// The matcher (`/library/metadata/{id}/matches`, `title=tmdb-603`) answers
  /// only through an item of a section the same kind of agent manages: asked
  /// through a film, the series agent finds no show. It asks Plex's metadata
  /// service, which the server reaches and this device never does.
  Future<_PlexGuidResolution> _resolvePlexGuid(
    List<String> guids,
    StreamItemKind? kind,
    CancelToken? cancelToken,
  ) async {
    final types = switch (kind) {
      StreamItemKind.movie => const ['movie'],
      StreamItemKind.series => const ['show'],
      _ => const ['movie', 'show'],
    };
    var anySection = false;
    for (final type in types) {
      final _PlexMatchAnchor anchor;
      try {
        anchor = await _matchAnchor(type, cancelToken);
      } catch (_) {
        return const _PlexGuidUnresolved();
      }
      anySection = anySection || anchor.hasSection;
      final ratingKey = anchor.ratingKey;
      final agent = anchor.agent;
      if (ratingKey == null || agent == null) continue;
      for (final external in guids) {
        final key = '$type|$external';
        final known = _plexGuids[key];
        if (known != null) return _PlexGuidResolved(known);
        try {
          final container = await _container(
            '/library/metadata/${_pathSegment(ratingKey)}/matches',
            queryParameters: {
              'manual': 1,
              'title': external.replaceFirst('://', '-'),
              'agent': agent,
            },
            cancelToken: cancelToken,
          );
          final results = container['SearchResult'];
          final guid = results is List
              ? results
                    .whereType<Map>()
                    .map((result) => result['guid'])
                    .whereType<String>()
                    .where((guid) => guid.startsWith('plex://'))
                    .firstOrNull
              : null;
          if (guid == null) continue;
          _plexGuids[key] = guid;
          return _PlexGuidResolved(guid);
        } catch (_) {
          // The server could not ask Plex's metadata service: try the next id,
          // then the direct probe.
          continue;
        }
      }
    }
    return anySection
        ? const _PlexGuidUnresolved()
        : const _PlexGuidNoLibrary();
  }

  /// The server's sections, read once for the matcher; a failed read is not
  /// kept.
  Future<List<Map<dynamic, dynamic>>>? _matchSections;

  /// Whether a section of [type] exists, and the first item of the first one a
  /// current Plex agent (`tv.plex.agents.*`) manages, with that agent. Kept
  /// for the client's life; a failed read is not kept.
  Future<_PlexMatchAnchor> _matchAnchor(String type, CancelToken? cancelToken) {
    final pending = _matchAnchors[type] ??= () async {
      final all = await (_matchSections ??= () async {
        final container = await _container(
          '/library/sections',
          cancelToken: cancelToken,
        );
        final directories = container['Directory'];
        return [if (directories is List) ...directories.whereType<Map>()];
      }());
      final sections = [
        for (final section in all)
          if (section['type'] == type) section,
      ];
      for (final section in sections) {
        final agent = section['agent'];
        final key = section['key'];
        if (agent is! String || !agent.startsWith('tv.plex.agents.')) continue;
        if (key == null) continue;
        final page = await _container(
          '/library/sections/${_pathSegment('$key')}/all',
          queryParameters: {
            'X-Plex-Container-Start': 0,
            'X-Plex-Container-Size': 1,
          },
          cancelToken: cancelToken,
        );
        final first = (page['Metadata'] as List?)?.whereType<Map>().firstOrNull;
        final ratingKey = first?['ratingKey'];
        if (ratingKey == null) continue;
        return (hasSection: true, ratingKey: '$ratingKey', agent: agent);
      }
      return (hasSection: sections.isNotEmpty, ratingKey: null, agent: null);
    }();
    pending.catchError((Object _) {
      _matchAnchors.remove(type);
      _matchSections = null;
      return (hasSection: false, ratingKey: null, agent: null);
    });
    return pending;
  }

  /// `GET /library/metadata/{ratingKey}/children`: show → seasons, season →
  /// episodes, album → tracks.
  ///
  /// Reads `Metadata` and falls back to `Directory`: current builds return
  /// seasons as `Metadata` in JSON, but the same elements are `Directory` in the
  /// XML the JSON layer was grafted onto, and older servers still say so.
  @override
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    // Not caught: a read that failed throws, so the item's Contents say the
    // server did not answer, with a Retry, rather than "Nothing inside".
    final container = await _container(
      '/library/metadata/${_pathSegment(itemId)}/children',
      cancelToken: cancelToken,
    );
    return _itemsFrom(container['Metadata'] ?? container['Directory']);
  }

  /// `GET /library/metadata/{ratingKey}/allLeaves`: every episode of a show,
  /// in order, with the token owner's watch state ([getViewers]).
  @override
  Future<List<StreamItem>> getEpisodes(
    String seriesId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async {
    // Not caught: see [getChildren].
    final container = await _container(
      '/library/metadata/${_pathSegment(seriesId)}/allLeaves',
      cancelToken: cancelToken,
    );
    return _itemsFrom(container['Metadata']);
  }

  /// The household members whose watch state can be read: exactly one, always.
  ///
  /// This is not a stub. `GET /accounts` would list every Plex Home user, and
  /// offering them as pickable viewers would be a lie: `/library/*` takes no
  /// impersonation parameter, so every lens would still answer for the token's
  /// owner while the UI claimed otherwise. Reading another member's state
  /// requires their token, and tokens come only from plex.tv, which this client
  /// never calls. So the one honest list is the owner alone, which is also why
  /// `StreamLibraryLens.isPerViewer` hides the viewer chip on Plex instead of
  /// showing a list of one.
  ///
  /// `GET /` rather than `/accounts` on purpose: `/accounts` is admin-only in
  /// practice, so a non-admin token would get nothing at all from it, while `/`
  /// answers for any valid token.
  ///
  /// Throws on a remote failure, like Jellyfin's: an empty list would be a
  /// server that answered with nobody on it.
  /// Each film and series section by `lastViewedAt`, the latest across them
  /// first. A series is watched when an episode of it is, which Plex says on
  /// the show itself. Only items Plex says were viewed count: the sort alone
  /// puts the never watched after them, not out.
  @override
  Future<List<StreamWatched>> getRecentlyWatched({
    String? viewerId,
    int limit = 5,
    CancelToken? cancelToken,
  }) async {
    try {
      final sections = [
        for (final library in await getLibrariesOrThrow(
          cancelToken: cancelToken,
        ))
          if (library.kind == StreamLibraryKind.movies ||
              library.kind == StreamLibraryKind.shows)
            library,
      ];
      final answers = await Future.wait([
        for (final section in sections)
          _container(
            '/library/sections/${_pathSegment(section.id)}/all',
            queryParameters: {
              'type': ?_primaryTypeFor(section.kind),
              'sort': 'lastViewedAt:desc',
              'includeGuids': 1,
              'X-Plex-Container-Start': 0,
              'X-Plex-Container-Size': limit,
            },
            cancelToken: cancelToken,
          ),
      ]);
      final result = <StreamWatched>[];
      for (final container in answers) {
        final metadata = container['Metadata'];
        if (metadata is! List) continue;
        for (final raw in metadata.whereType<Map>()) {
          final json = raw.cast<String, dynamic>();
          final at = plexEpochSeconds(json['lastViewedAt']);
          final item = at == null ? null : plexItemFromJson(json);
          if (item != null) result.add((item: item, playedAt: at!));
        }
      }
      result.sort((a, b) => b.playedAt.compareTo(a.playedAt));
      return result.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<StreamViewer>> getViewers() async {
    final capabilities = await getCapabilities();
    // **`friendlyName` is not a fallback here, and used to be one.**
    // `friendlyName` is what the owner called the *box*: "tower", "basement
    // NAS". So a server not linked to plex.tv produced a viewer named after a
    // machine, which reads as a household member who does not exist. Decision 16
    // is that no Plex surface may claim a viewer it cannot name; an unnamed
    // owner is still the owner, so the entry stays and says so.
    final name = capabilities.myPlexUsername ?? kPlexOwnerFallbackName;
    // 'me' rather than an account id: there is no endpoint that says which
    // account a token belongs to, and the value is never sent anywhere: every
    // read is already scoped to this token.
    return [StreamViewer(id: 'me', name: name)];
  }

  // ---------------------------------------------------------------------------
  // Hubs
  // ---------------------------------------------------------------------------

  /// `GET /hubs/continueWatching`: in-progress playback across every library.
  ///
  /// Hub responses are where a no-plex.tv client leaks: Plex mixes *provider*
  /// rows into the same arrays as local ones, with absolute plex.tv keys and
  /// artwork. [plexItemFromJson] drops them at the parse boundary.
  ///
  /// Throws on a remote failure. The rail and the On deck tab are this one
  /// request and nothing else, so a swallowed failure drew "Nothing
  /// part-watched" about a server that never answered.
  @override
  Future<List<StreamItem>> getContinueWatching({
    int count = kPlexLibraryPageSize,
    CancelToken? cancelToken,
  }) async {
    final container = await _container(
      '/hubs/continueWatching',
      queryParameters: {'count': count, 'includeGuids': 1},
      cancelToken: cancelToken,
    );
    return _itemsFromHubs(container);
  }

  /// The next-up half of the on deck: what has no position yet (the next
  /// episode of a series in progress). Plex keeps both halves in one hub.
  @override
  Future<List<StreamItem>> getNextUp({
    required int count,
    CancelToken? cancelToken,
  }) async {
    final onDeck = await getContinueWatching(
      count: count * 2,
      cancelToken: cancelToken,
    );
    return onDeck
        .where((item) => (item.resumeOffsetMs ?? 0) == 0)
        .take(count)
        .toList(growable: false);
  }

  /// `GET /library/recentlyAdded`: movies, and series by what was added to
  /// them, each once. Plex answers with the rows it added (a season, an
  /// episode, an album), so a season or an episode is drawn as its series and
  /// music is left out: this is what there is to watch.
  @override
  Future<List<StreamItem>> getRecentlyAdded({
    required int count,
    CancelToken? cancelToken,
  }) async {
    final container = await _container(
      '/library/recentlyAdded',
      queryParameters: {
        'X-Plex-Container-Start': 0,
        'X-Plex-Container-Size': count * 3,
        'includeGuids': 1,
      },
      cancelToken: cancelToken,
    );
    final rows = container['Metadata'];
    if (rows is! List) return const [];
    final seen = <String>{};
    final items = <StreamItem>[];
    for (final raw in rows.whereType<Map>()) {
      final row = raw.cast<String, dynamic>();
      final shown = switch (row['type']) {
        'movie' || 'show' => row,
        'season' => {
          'type': 'show',
          'ratingKey': row['parentRatingKey'],
          'key': '/library/metadata/${row['parentRatingKey']}/children',
          'title': row['parentTitle'],
          'thumb': row['parentThumb'] ?? row['thumb'],
          'art': row['art'],
          'year': row['parentYear'],
          'addedAt': row['addedAt'],
        },
        'episode' => {
          'type': 'show',
          'ratingKey': row['grandparentRatingKey'],
          'key': '/library/metadata/${row['grandparentRatingKey']}/children',
          'title': row['grandparentTitle'],
          'thumb': row['grandparentThumb'] ?? row['thumb'],
          'art': row['grandparentArt'] ?? row['art'],
          'addedAt': row['addedAt'],
        },
        _ => null,
      };
      final key = shown?['ratingKey']?.toString();
      if (shown == null || key == null || key.isEmpty) continue;
      if (!seen.add(key)) continue;
      final item = plexItemFromJson(shown);
      if (item != null) items.add(item);
      if (items.length == count) break;
    }
    return items;
  }

  /// Devices registered on this Plex Media Server (`com.plexapp.system.devices`).
  /// Tokens returned by the endpoint are intentionally discarded by
  /// [PlexDevice]; a read-only inventory has no reason to retain credentials.
  Future<List<PlexDevice>> getDevices() async {
    final container = await _container('/devices');
    return plexDevicesFromJson(container['Device']);
  }

  /// Regular and smart playlists owned by the token's user.
  Future<List<PlexPlaylist>> getPlaylists() async {
    final container = await _container('/playlists');
    return plexPlaylistsFromJson(container['Metadata']);
  }

  /// `GET /hubs/search`: the library search, in the server's own bands.
  ///
  /// **The hubs are the answer and are handed back whole.** Plex has already
  /// grouped the hits and ranked both the hubs and the rows inside them, using a
  /// relevance model this client cannot reproduce; flattening that, which is
  /// what this method used to do: threw away the grouping and then left the
  /// page with a flat list it had no way to band. The order is rendered as
  /// given, and an empty hub survives as an empty group so the strip can draw
  /// its zero pill (see [StreamSearchGroup]).
  ///
  /// Every hit here is the **owner's** own: the token is one user, so no result
  /// may carry another viewer's watch mark (decision 16). Nothing extra is done
  /// to enforce that: `/hubs/search` simply has no other perspective to offer.
  ///
  /// `limit` is per hub and Plex's own default is 3, so it is always sent
  /// explicitly. `includeExternalMedia=0` asks Plex to leave its catalogue out.
  /// Belt to [plexIsServerItem]'s braces, since the parameter is advisory and
  /// the provider rows still arrive on some builds.
  @override
  Future<List<StreamSearchGroup>> search(
    String query, {
    int? limit,
    CancelToken? cancelToken,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    // Not caught: see `JellyfinClient.search`.
    final container = await _container(
      '/hubs/search',
      queryParameters: {
        'query': term,
        'limit': limit ?? kPlexSearchHubLimit,
        'includeExternalMedia': 0,
        'includeGuids': 1,
      },
      cancelToken: cancelToken,
    );
    return _groupsFromHubs(container);
  }

  // ---------------------------------------------------------------------------
  // Artwork
  // ---------------------------------------------------------------------------

  /// Resolves a relative Plex artwork key.
  ///
  /// Without [width] the key is served directly and the credential travels in a
  /// header. With one, the request goes through `/photo/:/transcode`, because
  /// Plex resizes an image far more cheaply than shipping a 2000px poster to
  /// Flutter to scale down.
  ///
  /// The proxy's inner `url=` parameter is the part that needs care: Plex's own
  /// documentation says that if that URL needs a token, the token has to be a
  /// query parameter on it: a header cannot reach it. This client only ever
  /// passes a **relative** inner url, which the server resolves internally under
  /// the outer request's own authentication, so no token enters a query string.
  /// If an absolute inner url were ever required, the correct credential for it
  /// is a delegation token (`POST /security/token?type=delegation&scope=all`,
  /// valid 48 hours and destroyed on server restart) and never the user's own.
  @override
  StreamImageSource? imageFor(String posterPath, {int? width}) {
    // Rejecting anything non-relative is what stops a cloud artwork URL that
    // slipped through parsing from being fetched from plex.tv.
    final key = plexArtworkKey(posterPath);
    if (key == null || baseUrl.isEmpty) return null;

    if (width == null || width <= 0) {
      return (url: UrlUtils.buildUrl(baseUrl, key), headers: _imageHeaders);
    }

    final target = Uri.parse(UrlUtils.buildUrl(baseUrl, '/photo/:/transcode'))
        .replace(
          queryParameters: {
            'url': key,
            'width': '$width',
            'height': '${(width * _kPosterHeightRatio).round()}',
            // Fit inside the box, never enlarge a small source.
            'minSize': '1',
            'upscale': '0',
          },
        );
    return (url: target.toString(), headers: _imageHeaders);
  }

  @override
  void close() => _api.close();

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Percent-encodes an opaque id for use in a path.
  ///
  /// `ratingKey` and a section `key` are documented as opaque strings that only
  /// usually look numeric, so neither may be interpolated raw.
  static String _pathSegment(String value) => Uri.encodeComponent(value.trim());

  Future<StreamLibraryKind?> _sectionKind(String libraryId) async {
    final cached = _sectionKinds[libraryId];
    if (cached != null) return cached;
    // A join, not a surface: an unknown kind only costs the browse its type
    // filter, so a failed lookup degrades here even though `getLibraries`
    // throws.
    try {
      await getLibraries();
    } catch (_) {
      return null;
    }
    return _sectionKinds[libraryId];
  }

  static int? _primaryTypeFor(StreamLibraryKind? kind) {
    switch (kind) {
      case StreamLibraryKind.movies:
        return _kPlexTypeMovie;
      case StreamLibraryKind.shows:
        return _kPlexTypeShow;
      case StreamLibraryKind.music:
        return _kPlexTypeArtist;
      // Photo and unknown sections: let the server return the section's own
      // primary type rather than guessing an id for it.
      case StreamLibraryKind.photos:
      case StreamLibraryKind.other:
      case null:
        return null;
    }
  }

  /// A library's whole shelf, in [sort] order and, with [unplayedOnly], what
  /// the token's user has not finished. Measured on Plex: `addedAt:desc` and
  /// `year:desc`, each with `titleSort` breaking ties.
  ({String path, Map<String, dynamic> query}) _shelfRequest(
    String libraryId,
    StreamLibrarySort sort,
    StreamLibraryKind? kind,
    bool unplayedOnly,
  ) {
    final section = '/library/sections/${_pathSegment(libraryId)}';
    return (
      path: '$section/all',
      query: {
        'type': ?_primaryTypeFor(kind),
        // The filter is spelled differently per section type, and sending the
        // wrong spelling returns the *whole* library rather than an error: a
        // silently wrong shelf. A show is unplayed when it has unwatched
        // leaves, not when the show object itself is unwatched.
        if (unplayedOnly && kind == StreamLibraryKind.shows)
          'show.unwatchedLeaves': 1
        else if (unplayedOnly && kind == StreamLibraryKind.movies)
          'unwatched': 1,
        'sort': switch (sort) {
          StreamLibrarySort.name => 'titleSort',
          StreamLibrarySort.dateAdded => 'addedAt:desc,titleSort',
          StreamLibrarySort.year => 'year:desc,titleSort',
        },
      },
    );
  }

  Future<PlexPage<StreamItem>> _pageFromContainer(
    Map<String, dynamic> container,
    int requestedStart,
  ) async {
    final items = await _itemsFromAsync(container['Metadata']);
    return PlexPage<StreamItem>(
      items: items,
      // Trust the server's echo over what was asked for; only fall back to the
      // request when the response omits it.
      offset: plexInt(container['offset']) ?? requestedStart,
      size: plexInt(container['size']) ?? items.length,
      totalSize: plexInt(container['totalSize']),
    );
  }

  /// Maps a `Metadata` array, off the main isolate once it is worth it.
  ///
  /// **`static` is load-bearing.** The mapping entry point is a top-level pure
  /// function and the closure captures only the decoded list, but a closure
  /// written inside an *instance* method can drag `this` into its context, and
  /// `this` holds an `ApiClient`, which is not sendable. `Isolate.run` would then
  /// throw at the boundary, and because every read path here degrades on error
  /// the failure would surface as a silently empty library rather than as a
  /// crash. Being static makes that unrepresentable.
  static Future<List<StreamItem>> _itemsFromAsync(dynamic raw) async {
    if (raw is! List || raw.isEmpty) return const [];
    if (raw.length < _kIsolateMappingThreshold) {
      return plexItemsFromMetadata(raw);
    }
    return Isolate.run(() => plexItemsFromMetadata(raw));
  }

  List<StreamItem> _itemsFrom(dynamic raw) {
    if (raw is! List) return const [];
    return plexItemsFromMetadata(raw);
  }

  /// Flattens `Hub[] → Metadata[]`, keeping hub order.
  ///
  /// For the surfaces that genuinely want one list: Continue watching is one
  /// hub's worth of rows however the server wrapped it. A *search* must not come
  /// through here: see [_groupsFromHubs].
  List<StreamItem> _itemsFromHubs(Map<String, dynamic> container) {
    final hubs = container['Hub'];
    if (hubs is! List) {
      // `/hubs/continueWatching` answers with a bare `Metadata` array on some
      // builds instead of wrapping it in a single hub.
      return _itemsFrom(container['Metadata']);
    }
    final items = <StreamItem>[];
    for (final hub in hubs.whereType<Map>()) {
      items.addAll(_itemsFrom(hub['Metadata']));
    }
    return items;
  }

  /// `Hub[]` kept as bands, in the order the server ranked them.
  ///
  /// The hub's own `title` is what the band prints. Deriving a word from the
  /// hub's `type` instead would quietly rename the server's own vocabulary: a
  /// Plex hub is titled "Movies", "Shows", "Episodes", "Actors" by the server
  /// that owns the library, and a localised server titles them in its language.
  ///
  /// An empty hub is **kept**. That is the difference between "this server holds
  /// no matching episode" and "episodes were never searched", and it is the only
  /// thing that lets the strip draw a zero pill honestly.
  List<StreamSearchGroup> _groupsFromHubs(Map<String, dynamic> container) {
    final hubs = container['Hub'];
    if (hubs is! List) {
      // The unwrapped shape carries no band at all, so there is nothing to
      // group by and one unnamed band is the honest reading.
      final items = _itemsFrom(container['Metadata']);
      if (items.isEmpty) return const [];
      return [
        StreamSearchGroup(
          label: kPlexUngroupedHubLabel,
          kind: null,
          items: items,
        ),
      ];
    }

    final groups = <StreamSearchGroup>[];
    for (final hub in hubs.whereType<Map>()) {
      final map = hub.cast<String, dynamic>();
      final title = plexString(map['title']);
      // A hub with no title is one this client cannot label, and an unlabelled
      // band on a strip of pills is worse than its rows being absent: the pill
      // would say nothing at all. Its rows are not smuggled into a neighbour.
      if (title == null || title.isEmpty) continue;
      groups.add(
        StreamSearchGroup(
          label: title,
          kind: plexHubKind(map['type']),
          items: _itemsFrom(map['Metadata']),
        ),
      );
    }
    return groups;
  }
}

/// A lens resolved to a request: where to ask, what to ask for, and what to keep.
/// See [PlexClient._matchAnchor].
typedef _PlexMatchAnchor = ({
  bool hasSection,
  String? ratingKey,
  String? agent,
});

/// What [PlexClient._resolvePlexGuid] found.
sealed class _PlexGuidResolution {
  const _PlexGuidResolution();
}

/// Plex's own guid for the title.
final class _PlexGuidResolved extends _PlexGuidResolution {
  const _PlexGuidResolved(this.guid);

  final String guid;
}

/// No library of the kind on the server.
final class _PlexGuidNoLibrary extends _PlexGuidResolution {
  const _PlexGuidNoLibrary();
}

/// The matcher could not say.
final class _PlexGuidUnresolved extends _PlexGuidResolution {
  const _PlexGuidUnresolved();
}
