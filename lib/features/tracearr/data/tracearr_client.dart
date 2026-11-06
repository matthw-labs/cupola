import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/answer_guard.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/list_mapping.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_version.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';

/// The largest page the API accepts for most reads.
const int kTracearrMaxPageSize = 100;

/// The largest page of `top-media`, which the API lets run far longer.
const int kTracearrMaxTopPageSize = 1000;

/// A page with more rows than this is mapped off the UI isolate when it did
/// not already go through the transport's own mapping. A streams row alone
/// carries sixty fields.
const int kTracearrIsolateMapThreshold = 100;

/// How much of a 200 that is not an event stream is read to recognise what
/// answered. A sign-in page shows its form well inside it.
const int kTracearrEventsProbeBytes = 8 * 1024;

/// How long that read waits for the page to say enough. A page that stalls
/// under [kTracearrEventsProbeBytes] and keeps the connection open must not
/// hold the caller: what arrived by then is what is read.
const Duration kTracearrEventsProbeTimeout = Duration(seconds: 3);

const String _v1 = '/api/v1/public';
const String _v2 = '/api/v2/public';

/// How a history read is narrowed. Every filter is applied by the server: we
/// never filter a downloaded page, because a page that filters to nothing would
/// read as "no history" while older pages hold plenty.
final class TracearrHistoryFilter {
  const TracearrHistoryFilter({
    this.userId,
    this.serverId,
    this.mediaId,
    this.ratingKey,
    this.mediaType,
    this.watched,
    this.since,
    this.until,
  });

  /// Tracearr's user id (a person across servers).
  final String? userId;
  final String? serverId;
  final String? mediaId;

  /// The media server's own item id.
  final String? ratingKey;

  /// What the history route filters on. Its own enum: it takes `trailer` and
  /// `unknown` but answers 400 to `show`, which only top-media takes.
  final TracearrHistoryMediaType? mediaType;

  /// True for what counts as watched, false for what does not; null for both.
  final bool? watched;

  final DateTime? since;
  final DateTime? until;

  Map<String, Object> toQuery() => {
    'user_id': ?userId,
    'server_id': ?serverId,
    'media_id': ?mediaId,
    'rating_key': ?ratingKey,
    'media_type': ?mediaType?.name,
    'watched': ?watched,
    'since': ?since?.toUtc().toIso8601String(),
    'until': ?until?.toUtc().toIso8601String(),
  };
}

/// How a violations read is narrowed.
final class TracearrViolationFilter {
  const TracearrViolationFilter({
    this.serverId,
    this.userId,
    this.severity,
    this.acknowledged,
    this.since,
    this.until,
  });

  /// The ones nobody has looked at.
  const TracearrViolationFilter.unseen({
    this.serverId,
    this.userId,
    this.severity,
    this.since,
    this.until,
  }) : acknowledged = false;

  final String? serverId;
  final String? userId;
  final TracearrSeverity? severity;

  /// False for the unseen, true for the acknowledged, null for both.
  final bool? acknowledged;

  final DateTime? since;
  final DateTime? until;

  Map<String, Object> toQuery() => {
    'server_id': ?serverId,
    'user_id': ?userId,
    'severity': ?severity?.wire,
    'acknowledged': ?acknowledged,
    'since': ?since?.toUtc().toIso8601String(),
    'until': ?until?.toUtc().toIso8601String(),
  };
}

/// The outcome of asking Tracearr to end a stream.
sealed class TracearrTerminateResult {
  const TracearrTerminateResult();
}

/// Tracearr ended the stream.
final class TracearrTerminated extends TracearrTerminateResult {
  const TracearrTerminated({this.message, this.logId});

  final String? message;
  final String? logId;
}

/// This Tracearr has no such route: an older install. The control must not
/// exist, which is not the same as the call having failed.
///
/// Only a 405, or Fastify's unmatched-route 404 (`{"error":"Not Found"}` with
/// no `statusCode`), says so. A 404 the route itself sends for a missing
/// session is [TracearrTerminateStreamGone].
final class TracearrTerminateRouteAbsent extends TracearrTerminateResult {
  const TracearrTerminateRouteAbsent();
}

/// The route exists and no such stream is running any more (it stopped between
/// the list and the tap). Not a failure: there is nothing left to end.
final class TracearrTerminateStreamGone extends TracearrTerminateResult {
  const TracearrTerminateStreamGone();
}

/// The route exists and the stream was not ended (the server could not reach
/// the media server, or refused).
final class TracearrTerminateFailed extends TracearrTerminateResult {
  const TracearrTerminateFailed({this.statusCode, this.message});

  final int? statusCode;
  final String? message;
}

/// The public API v2 Cupola reads is not on this Tracearr: it is older than
/// [kTracearrMinVersion].
///
/// Carries the version it named and no more: nothing here is a secret, and the
/// sentence tells the person what to install.
class TracearrTooOld implements Exception, HasFailureReason, HasFailureDetail {
  const TracearrTooOld(this.found);

  final TracearrVersion found;

  /// An answer Cupola cannot use as it is, which a newer Tracearr fixes, so
  /// Retry stays beside it.
  @override
  ServiceFailureReason get reason => ServiceFailureReason.invalidResponse;

  @override
  String get failureDetail =>
      'Tracearr $found is older than the public API Cupola reads. Install '
      'Tracearr $kTracearrMinVersion or newer.';

  @override
  String toString() => 'TracearrTooOld($found)';
}

/// Tracearr's public API, read with the `trr_pub_` key.
///
/// Built over [ApiClient.authenticatedBy] like the media-server clients: it
/// carries the shared timeouts and the redirect guard that stops the key being
/// replayed to a host the user never configured. The key travels as
/// `Authorization: Bearer`, so a proxy password cannot share the connection
/// (the access headers must not hold an `Authorization`), as with Nginx Proxy
/// Manager.
///
/// Reads are v2 where v2 has them. v1 serves only what v2 lacks: the health
/// read that names the version, today's figures, and ending a stream.
///
/// Reads throw on a transport failure and on a body that is not what the route
/// answers ([FormatException]); a 404 on a single item reads as null. Rows we
/// cannot read are dropped, never the page.
class TracearrClient {
  /// [baseUrl] is the address the connection's reach gave (home or away), and
  /// [accessHeaders] and [pinnedCertFingerprint] come from the same reach:
  /// never the saved address.
  TracearrClient({
    required String baseUrl,
    required String apiKey,
    String? pinnedCertFingerprint,
    Map<String, String> accessHeaders = const {},
    ServiceKey? onlyAtHome,
  }) : _authorization = 'Bearer ${apiKey.trim()}',
       _accessHeaders = Map.unmodifiable(accessHeaders) {
    _api = ApiClient.authenticatedBy(
      baseUrl: baseUrl,
      headers: {'Authorization': _authorization},
      pinnedCertFingerprint: pinnedCertFingerprint,
      accessHeaders: accessHeaders,
      onlyAtHome: onlyAtHome,
    );
  }

  late final ApiClient _api;
  final String _authorization;
  final Map<String, String> _accessHeaders;

  /// What a poster or an avatar asks Tracearr's image proxy with: the key and
  /// the address's access, in headers. Never in the address, which is what the
  /// image cache names the file by.
  Map<String, String> get imageHeaders => {
    ..._accessHeaders,
    'Authorization': _authorization,
  };

  /// The transport, so a test can stub the socket while the client still
  /// builds its own headers and URLs.
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  Dio get dio => _api.dio;

  /// The address the client reads, for resolving the relative image paths the
  /// models keep (see `resolveTracearrImage`).
  Uri get baseUri => Uri.parse(_api.baseUrl);

  void close({bool force = false}) => _api.close(force: force);

  /// The one read that names the version (`v3.1.4`, with its `v`).
  Future<TracearrHealth> getHealth() async {
    final response = await _api.get('$_v1/health');
    return TracearrHealth.fromJson(response.data);
  }

  /// The connection test and the probe's read: [getHealth] with the key, who
  /// answered, and whether this Tracearr has the API v2 Cupola reads.
  ///
  /// A 401 throws, the key refused. A body that is not Tracearr's own, or a
  /// web page, throws as a wrong answer ([requireProbeIdentity]). A version
  /// below [kTracearrMin] throws [TracearrTooOld]; one it does not name, or
  /// that does not parse, is let through, since a server that accepted the key
  /// and spoke in Tracearr's shape is not worth refusing on a field we cannot
  /// read.
  Future<TracearrHealth> checkCredentialAndVersion() async {
    final response = await _api.get('$_v1/health');
    requireProbeIdentity(ServiceKey.tracearr, response.data, url: _api.baseUrl);
    final health = TracearrHealth.fromJson(response.data);
    final version = health.parsedVersion;
    if (version != null && version < kTracearrMin) {
      throw TracearrTooOld(version);
    }
    return health;
  }

  /// The servers Tracearr watches, with their state.
  Future<TracearrServers> getServers() async {
    final response = await _api.get('$_v2/servers');
    return TracearrServers.fromJson(response.data);
  }

  /// The live streams with their summary, for every server or one.
  Future<TracearrStreams> getStreams({String? serverId}) {
    return _readMapped(
      '$_v2/streams',
      query: {'summary': true, 'server_id': ?serverId},
      parse: _parseStreams,
    );
  }

  /// Today's figures. [timezone] is an IANA name (`Europe/Rome`): without it
  /// Tracearr cuts the day at UTC midnight.
  Future<TracearrToday> getToday({String? serverId, String? timezone}) async {
    final response = await _api.get(
      '$_v1/stats/today',
      queryParameters: {'serverId': ?serverId, 'timezone': ?timezone},
    );
    return TracearrToday.fromJson(response.data);
  }

  /// One page of history, newest first. Start with no [cursor] and pass back
  /// the page's `nextCursor` until it is null.
  Future<TracearrPage<TracearrHistoryEntry>> getHistory({
    String? cursor,
    int pageSize = 25,
    TracearrHistoryFilter filter = const TracearrHistoryFilter(),
  }) {
    return _readMapped(
      '$_v2/history',
      query: {..._paging(cursor, pageSize), ...filter.toQuery()},
      parse: _parseHistory,
    );
  }

  Future<TracearrPage<TracearrUser>> getUsers({
    String? cursor,
    int pageSize = 25,
    bool includeRemoved = false,
  }) {
    return _readMapped(
      '$_v2/users',
      query: {
        ..._paging(cursor, pageSize),
        if (includeRemoved) 'include_removed': true,
      },
      parse: _parseUsers,
    );
  }

  /// A person, or null when Tracearr does not know the id.
  Future<TracearrUser?> getUser(String id) async {
    final json = await _readOrNull('$_v2/users/${Uri.encodeComponent(id)}');
    if (json == null) return null;
    return TracearrUser.fromJson(asTracearrJson(json) ?? const {});
  }

  /// A person's 7, 30 and all-time figures and favourite genres, or null when
  /// Tracearr does not know the id.
  Future<TracearrUserStats?> getUserStats(String id) async {
    final json = await _readOrNull(
      '$_v2/users/${Uri.encodeComponent(id)}/stats',
    );
    return json == null ? null : TracearrUserStats.fromJson(json);
  }

  Future<TracearrPage<TracearrViolation>> getViolations({
    String? cursor,
    int pageSize = 25,
    TracearrViolationFilter filter = const TracearrViolationFilter(),
  }) {
    return _readMapped(
      '$_v2/violations',
      query: {..._paging(cursor, pageSize), ...filter.toQuery()},
      parse: _parseViolations,
    );
  }

  /// One violation with the actions Tracearr took, or null when it is gone.
  Future<TracearrViolation?> getViolation(String id) async {
    final json = await _readOrNull(
      '$_v2/violations/${Uri.encodeComponent(id)}',
    );
    final row = asTracearrJson(json);
    return row == null ? null : TracearrViolation.fromJson(row);
  }

  /// Who watched a title, or null when Tracearr does not know it.
  ///
  /// A null is an answer only for "unknown to Tracearr"; it says nothing about
  /// whether anyone watched. A caller must not turn it into "nobody has".
  Future<TracearrMediaWatchers?> getWatchers(
    TracearrMediaRef ref, {
    TracearrWindow window = TracearrWindow.allTime,
    String? serverId,
  }) async {
    final json = await _readOrNull(
      '$_v2/media/${_refPath(ref)}/watchers',
      query: {
        if (window != TracearrWindow.unknown) 'window': window.wire,
        'server_id': ?serverId,
      },
    );
    return json == null ? null : TracearrMediaWatchers.fromJson(json);
  }

  /// The most watched titles of the last [days] days. [mediaType] is required
  /// by the API and takes only what [TracearrTopMediaType] holds: any other
  /// word is a 400, so it cannot be expressed.
  Future<TracearrPage<TracearrTopMedia>> getTopMedia({
    required TracearrTopMediaType mediaType,
    int days = 30,
    TracearrTopSort sort = TracearrTopSort.plays,
    String? serverId,
    String? cursor,
    int pageSize = 100,
  }) {
    return _readMapped(
      '$_v2/top-media',
      query: {
        'media_type': mediaType.name,
        'days': days.clamp(1, 365),
        'sort': sort.wire,
        'server_id': ?serverId,
        'cursor': ?cursor,
        'pageSize': pageSize.clamp(1, kTracearrMaxTopPageSize),
      },
      parse: _parseTopMedia,
    );
  }

  /// Ends a stream. [reason] is shown to the person watching, when the media
  /// server supports a message.
  ///
  /// An older Tracearr has no such route: that answers
  /// [TracearrTerminateRouteAbsent] so the screen can leave the control out.
  /// A stream that already ended answers [TracearrTerminateStreamGone], and
  /// any other refusal [TracearrTerminateFailed]; telling the three apart is
  /// the point, because a lost key or a dead media server must not remove the
  /// control. A transport failure, or a gateway answering in Tracearr's place,
  /// throws.
  Future<TracearrTerminateResult> terminate(String id, {String? reason}) async {
    final message = reason?.trim() ?? '';
    try {
      final response = await _api.post(
        '$_v1/streams/${Uri.encodeComponent(id)}/terminate',
        // A JSON content type with no body is a 400 on Tracearr's side, so an
        // empty object goes out when there is no reason.
        data: {if (message.isNotEmpty) 'reason': message},
      );
      final json = asTracearrJson(response.data);
      if (json?.flag('success') == false) {
        return TracearrTerminateFailed(
          statusCode: response.statusCode,
          message: json?.text('error'),
        );
      }
      return TracearrTerminated(
        message: json?.text('message'),
        logId: json?.text('terminationLogId'),
      );
    } on DioException catch (error) {
      if (error.error is AccessGatewayAnswer) rethrow;
      final status = error.response?.statusCode;
      if (status == null) rethrow;
      final body = asTracearrJson(error.response?.data);
      if (status == 405 || (status == 404 && _isUnmatchedRoute(body))) {
        return const TracearrTerminateRouteAbsent();
      }
      if (status == 404 && _isSessionGone(body)) {
        return const TracearrTerminateStreamGone();
      }
      return TracearrTerminateFailed(
        statusCode: status,
        message: body?.text('error') ?? body?.text('message'),
      );
    }
  }

  /// The live event stream (`GET /api/v2/public/events`), as typed events.
  ///
  /// There is no reconnection here, and no event announces a break: the stream
  /// ends when the connection does, or fails with the transport's error, and
  /// the caller decides when and how to open another. [types] narrows the
  /// kinds the server sends (comma separated on the wire). [onRetry] hears the
  /// `retry:` hint the server sends. Cancelling the subscription, or
  /// [cancelToken], closes the connection.
  ///
  /// A 200 that is not an event stream is read for at most
  /// [kTracearrEventsProbeBytes] and failed the way a JSON route fails: a
  /// proxy's sign-in page is an [AccessGatewayAnswer], anything else an
  /// [UnexpectedAnswer], both inside a [DioException]. The guard that does this
  /// on JSON routes never sees a streamed body, so it is repeated here.
  Stream<TracearrEvent> events({
    List<String>? types,
    String? serverId,
    CancelToken? cancelToken,
    void Function(Duration retry)? onRetry,
  }) async* {
    // Dio's response stream does not pass a cancelled listener on to the
    // socket: only a cancel token closes the connection (measured on a real
    // socket, `tracearr_events_transport_test.dart`). So the connection is
    // ours to close whenever this generator ends, however it ends.
    final token = CancelToken();
    if (cancelToken != null) {
      unawaited(cancelToken.whenCancel.then((e) => token.cancel(e.error)));
    }
    try {
      final response = await _api.getStream(
        '$_v2/events',
        queryParameters: {
          if (types != null && types.isNotEmpty) 'types': types.join(','),
          'server_id': ?serverId,
        },
        headers: {'Accept': 'text/event-stream'},
        cancelToken: token,
      );
      final body = response.data;
      if (body == null) return;
      final contentType = response.headers.value(Headers.contentTypeHeader);
      if (contentType != null && !contentType.contains('text/event-stream')) {
        throw await _notAnEventStream(response, body);
      }
      await for (final frame in sseFrames(body.stream, onRetry: onRetry)) {
        final event = tracearrEventFrom(frame);
        if (event != null) yield event;
      }
    } finally {
      if (!token.isCancelled) token.cancel('The event stream was closed.');
    }
  }

  /// The failure for a 200 that is no event stream. Reads a bounded prefix and
  /// drops the connection: a page can be of any size, and the stream under it
  /// may never end.
  Future<DioException> _notAnEventStream(
    Response<ResponseBody> response,
    ResponseBody body,
  ) async {
    final prefix = <int>[];
    // Bounded in bytes and in time: a page that dribbles a byte every few
    // milliseconds never goes quiet, so no idle timeout would end this read.
    final enough = Completer<void>();
    void finish() {
      if (!enough.isCompleted) enough.complete();
    }

    final deadline = Timer(kTracearrEventsProbeTimeout, finish);
    final subscription = body.stream.listen(
      (chunk) {
        prefix.addAll(chunk);
        if (prefix.length >= kTracearrEventsProbeBytes) finish();
      },
      onError: (Object _) => finish(),
      onDone: finish,
      cancelOnError: true,
    );
    await enough.future;
    deadline.cancel();
    await subscription.cancel();
    final bytes = prefix.length > kTracearrEventsProbeBytes
        ? prefix.sublist(0, kTracearrEventsProbeBytes)
        : prefix;
    final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
    final request = response.requestOptions;
    final probe = Response<String>(
      requestOptions: request,
      data: text,
      statusCode: response.statusCode,
      headers: response.headers,
    );
    final Object failure =
        signInPageOf(probe) ??
        UnexpectedAnswer(
          status: response.statusCode,
          headers: response.headers.map,
          body: text,
          host: answeringHost(request.uri),
          baseUrl: request.baseUrl,
        );
    return DioException(
      requestOptions: request,
      response: probe,
      type: DioExceptionType.badResponse,
      error: failure,
      message: failure is AccessGatewayAnswer
          ? 'Something in front of the service answered.'
          : 'The answer was not an event stream.',
    );
  }

  /// Fastify's own 404 for a route that is not registered: `error` only, with
  /// no `statusCode`. The route's 404 for a missing session carries both.
  static bool _isUnmatchedRoute(TracearrJson? body) =>
      body != null &&
      !body.containsKey('statusCode') &&
      body.text('error') == 'Not Found';

  static bool _isSessionGone(TracearrJson? body) =>
      body?.text('message')?.trim().toLowerCase() == 'session not found';

  Map<String, Object> _paging(String? cursor, int pageSize) => {
    'cursor': ?cursor,
    'pageSize': pageSize.clamp(1, kTracearrMaxPageSize),
  };

  /// A `ref` as a path segment: percent-encoded, except the colons its own
  /// grammar uses (`movie:tmdb:603`), which are legal there.
  String _refPath(TracearrMediaRef ref) =>
      Uri.encodeComponent(ref.value).replaceAll('%3A', ':');

  /// A read whose body is mapped where it is decoded, so a big page never
  /// costs the UI isolate a frame.
  Future<T> _readMapped<T>(
    String path, {
    required Map<String, Object> query,
    required T Function(Object? body) parse,
  }) async {
    final response = await _api.getMappedList(
      path,
      queryParameters: query,
      mapList: parse,
    );
    final data = response.data;
    if (data is MappedList) return data.value as T;
    return _parseOffTheUiIsolate(parse, data);
  }

  Future<Object?> _readOrNull(String path, {Map<String, Object>? query}) async {
    try {
      final response = await _api.get(path, queryParameters: query);
      return response.data;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404 &&
          error.error is! AccessGatewayAnswer) {
        return null;
      }
      rethrow;
    }
  }

  static TracearrStreams _parseStreams(Object? body) =>
      TracearrStreams.fromJson(body);

  static TracearrPage<TracearrHistoryEntry> _parseHistory(Object? body) =>
      TracearrPage.fromJson(body, TracearrHistoryEntry.fromJson);

  static TracearrPage<TracearrUser> _parseUsers(Object? body) =>
      TracearrPage.fromJson(body, TracearrUser.fromJson);

  static TracearrPage<TracearrViolation> _parseViolations(Object? body) =>
      TracearrPage.fromJson(body, TracearrViolation.fromJson);

  static TracearrPage<TracearrTopMedia> _parseTopMedia(Object? body) =>
      TracearrPage.fromJson(body, TracearrTopMedia.fromJson);
}

/// Parses an already decoded body, in an isolate once it holds enough rows.
///
/// Top-level on purpose: the closure given to `Isolate.run` must capture only
/// sendable values, and one written inside the client would drag the client
/// (and its `Dio`) across the port.
Future<T> _parseOffTheUiIsolate<T>(
  T Function(Object? body) parse,
  Object? body,
) {
  final rows = body is Map ? body['data'] : null;
  if (rows is! List || rows.length <= kTracearrIsolateMapThreshold) {
    return Future.value(parse(body));
  }
  return Isolate.run(() => parse(body));
}
