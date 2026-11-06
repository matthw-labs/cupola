/// How Cupola reaches Tracearr as its owner: the one place an owner client is
/// built ([TracearrOwnerClient.forReach]), the sign-ins that earn its bearer,
/// and the two writes only the owner's session may make.
///
/// Two credentials, two jobs. The public key (`TracearrClient`) reads
/// everything and is always there; this is the second one, optional, for
/// `PATCH` and `DELETE /api/v1/violations/:id`, which the public API has no
/// route for. They never share a client, so the owner's bearer cannot travel
/// on a read and the key cannot be mistaken for a session.
///
/// Read from Tracearr 3.1.4 (server source, read only) and measured on a
/// throwaway container:
///
/// - Better Auth lives at `/api/v1/auth`. Sign-in (`/sign-in/email`,
///   `/sign-in/username`) answers the bearer in the `set-auth-token` response
///   header, and works with no `Origin` header: a foreign one is a 403, so
///   the sign-ins never send one. The one POST that carries a cookie is
///   different: Better Auth refuses any POST with a `Cookie` and no `Origin`
///   (403 `MISSING_OR_NULL_ORIGIN`), so `/plex/check-pin` sends the origin of
///   the address this client dials, which is what Tracearr checks it against.
/// - `GET /api/v1/auth/me` says who it is and their role. Both writes are
///   `requireOwner` routes: an administrator is a 403, and a member is a 404
///   (`reply.notFound()`), which a route that does not exist answers too. The
///   two are told apart by the answer's own words, and the role is checked at
///   sign-in so a member never holds a session here.
/// - A session lasts 30 days and Better Auth moves its end 30 days past any
///   request once it is a day old (`session.updateAge`), so reading
///   `get-session` once a day keeps it alive: [session].
/// - Plex: Tracearr itself makes the PIN (`/plex/initiate`) and answers
///   `/plex/check-pin`, binding the PIN to the browser with the `plex_pin`
///   cookie, which this client keeps for the one sign-in and sends back.
///
/// A token, a cookie or a password is never put in a log, in [toString] or in
/// a failure's text. Outcomes are values, not exceptions, for everything the
/// server can say about a write.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_violation_owner.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';

const String _auth = '/api/v1/auth';

/// The response header Better Auth's bearer plugin answers a sign-in with.
const String _tokenHeader = 'set-auth-token';

/// The session cookie's suffix, read only when the header is missing: its
/// value is the same signed token, URL-encoded.
const String _sessionCookieSuffix = 'session_token';

/// The cookie that binds a Plex PIN to the client that asked for it.
const String _plexPinCookie = 'plex_pin';

/// The only hosts a Plex page may open at. Tracearr names the page, and a
/// Tracearr that sent anyone anywhere else would be asking Cupola to open a
/// phishing page.
const Set<String> _plexHosts = {'app.plex.tv', 'plex.tv'};

/// What Tracearr's own origin guard says of a request whose `Origin` is not the
/// host it was dialed at (measured on 3.1.4).
const String _notFromTracearr = 'This request did not come from Tracearr.';

/// How long signing out waits for Tracearr: a server that does not answer lets
/// the session go by itself after 30 days.
const Duration kTracearrSignOutPatience = Duration(seconds: 5);

/// What a client tells the app about the session beyond one request. Carries no
/// secret.
@immutable
class TracearrOwnerEvents {
  const TracearrOwnerEvents({this.onSessionEnded});

  /// Tracearr no longer knows the session: a request was refused as unsigned.
  final void Function()? onSessionEnded;
}

/// The ways Tracearr says an owner may sign in (`GET /api/v1/setup/status`,
/// which needs no key).
@immutable
class TracearrOwnerWays {
  const TracearrOwnerWays({
    required this.local,
    required this.plex,
    required this.oidc,
    this.needsSetup = false,
  });

  /// A name or an email and a password.
  final bool local;

  /// The owner's Plex account.
  final bool plex;

  /// Single sign-on, which redirects through the server and which Cupola
  /// cannot complete.
  final bool oidc;

  /// Tracearr has no owner yet: nothing here may create one.
  final bool needsSetup;

  /// Single sign-on is the only way in: the one case worth saying so.
  bool get oidcOnly => oidc && !local && !plex;

  /// Nothing Cupola can use is on.
  bool get none => !local && !plex;

  /// The ways [json] names, or null when it is not Tracearr's answer.
  static TracearrOwnerWays? fromJson(Object? json) {
    final body = asTracearrJson(json);
    final methods = asTracearrJson(body?['authMethods']);
    if (body == null || methods == null) return null;
    return TracearrOwnerWays(
      local: methods.flag('local') ?? false,
      plex: methods.flag('plex') ?? false,
      oidc: methods.flag('oidc') ?? false,
      needsSetup: body.flag('needsSetup') ?? false,
    );
  }
}

/// Who a session belongs to, from `/auth/me`: the name and the role. The email
/// comes in the same answer and is not read.
@immutable
class TracearrOwnerIdentity {
  const TracearrOwnerIdentity({required this.name, required this.isOwner});

  final String name;

  /// Whether the role is `owner`: the only one whose writes these are.
  final bool isOwner;
}

/// What `get-session` said of a session.
@immutable
class TracearrSessionRead {
  const TracearrSessionRead({required this.alive, this.expiresAt});

  /// Tracearr still knows the session. Reading it is what renewed it.
  final bool alive;

  final DateTime? expiresAt;
}

/// A Plex PIN Tracearr made, waiting for the owner to approve it.
class TracearrPlexPin {
  const TracearrPlexPin._({
    required this.authUrl,
    required String handle,
    required String cookie,
  }) : _handle = handle,
       _cookie = cookie;

  /// The page the owner approves it at: always `https://app.plex.tv`.
  final Uri authUrl;
  final String _handle;
  final String _cookie;

  @override
  String toString() => 'TracearrPlexPin';
}

/// What checking a Plex PIN found.
sealed class TracearrPlexCheck {
  const TracearrPlexCheck();
}

/// Nobody approved it yet.
final class TracearrPlexWaiting extends TracearrPlexCheck {
  const TracearrPlexWaiting();
}

/// Tracearr no longer knows the PIN: it was approved elsewhere or it lapsed.
final class TracearrPlexExpired extends TracearrPlexCheck {
  const TracearrPlexExpired();
}

/// Approved: Tracearr signed the owner in and handed back a session.
final class TracearrPlexSignedIn extends TracearrPlexCheck {
  const TracearrPlexSignedIn(this.token);

  /// Secret.
  final String token;

  @override
  String toString() => 'TracearrPlexSignedIn';
}

/// Why Tracearr refused a sign-in.
enum TracearrSignInRefusal {
  /// The name, email or password is not right.
  wrongPassword,

  /// The account may not sign in here, or this way is off.
  notAllowed,

  /// Too many tries: Tracearr rate-limits sign-in.
  tooManyTries,

  /// Tracearr has no owner yet, and a Plex sign-in would create one. Cupola
  /// never finishes that.
  notSetUp,
}

/// A sign-in Tracearr refused. [TracearrSignInRefusal] says why and nothing
/// more.
class TracearrSignInRefused implements Exception {
  const TracearrSignInRefused(this.refusal);

  final TracearrSignInRefusal refusal;

  @override
  String toString() => 'TracearrSignInRefused(${refusal.name})';
}

/// The session signed in is not the owner's: a member's or an administrator's.
/// Refused with `Only the owner can acknowledge`.
class TracearrNotOwner implements Exception {
  const TracearrNotOwner();

  @override
  String toString() => 'TracearrNotOwner';
}

/// The owner's session is over. [ServiceFailureReason.sessionEnded]: blue, and
/// the remedy is signing in again, never a fault.
class TracearrOwnerSessionEnded implements Exception, HasFailureReason {
  const TracearrOwnerSessionEnded();

  @override
  ServiceFailureReason get reason => ServiceFailureReason.sessionEnded;

  @override
  String toString() => 'TracearrOwnerSessionEnded';
}

/// Tracearr said something this build does not read (a sign-in with no bearer,
/// a PIN page that is not Plex's). Carries no body: it may hold a session.
class TracearrAnswerUnread implements Exception, HasFailureReason {
  const TracearrAnswerUnread(this.what);

  final String what;

  @override
  ServiceFailureReason get reason => ServiceFailureReason.invalidResponse;

  @override
  String toString() => 'TracearrAnswerUnread($what)';
}

/// [TracearrOwnerClient.forReach] as a value a test can replace: the sign-in
/// and the keeper build their clients through the provider that holds it.
typedef TracearrOwnerClientFactory =
    TracearrOwnerClient Function({
      required ConnectionReach reach,
      String token,
      TracearrOwnerEvents events,
      ServiceKey? onlyAtHome,
    });

/// Tracearr as its owner.
///
/// Built by [forReach] and nowhere else
/// (`test/features/tracearr/tracearr_owner_client_guard_test.dart`): the
/// address, the gateway's access and the pinned certificate are the
/// connection's route's (`reachOf`), and a client built from the saved
/// address works at home and fails away from it. [token] is empty for the
/// sign-in methods, which send none, and the bearer for everything else.
class TracearrOwnerClient implements TracearrViolationOwner {
  TracearrOwnerClient._(this._api, this._token, this._events);

  /// The one constructor. [reach] is where the connection answers now, with
  /// that address's access and pin; [token] is the owner's bearer, or empty
  /// to sign in; [onlyAtHome] is `transport.onlyAtHomeOf(tracearr)` where the
  /// client is built off a transport.
  ///
  /// The bearer is an `Authorization` header, so a proxy password cannot share
  /// the connection (an access header named `Authorization` loses to it), as
  /// with the public key.
  factory TracearrOwnerClient.forReach({
    required ConnectionReach reach,
    String token = '',
    TracearrOwnerEvents events = const TracearrOwnerEvents(),
    ServiceKey? onlyAtHome,
  }) {
    final bearer = token.trim();
    return TracearrOwnerClient._(
      ApiClient.authenticatedBy(
        baseUrl: reach.url,
        headers: {if (bearer.isNotEmpty) 'Authorization': 'Bearer $bearer'},
        pinnedCertFingerprint: reach.pin,
        accessHeaders: reach.access.headers(),
        onlyAtHome: onlyAtHome,
      ),
      bearer,
      events,
    );
  }

  final ApiClient _api;
  final String _token;
  final TracearrOwnerEvents _events;
  bool _ended = false;

  /// The transport. The cookie that binds a Plex PIN rides on one request
  /// alone, which `ApiClient`'s verbs have no headers for; a test stubs the
  /// socket here while the client still builds its own headers and URLs.
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  Dio get dio => _api.dio;

  void close({bool force = false}) => _api.close(force: force);

  /// The origin of the address this client dials (`https://host[:port]`, the
  /// default port left out, no path), or null when that address has none.
  ///
  /// Better Auth refuses a POST that carries a cookie and no `Origin`, and
  /// Tracearr's own guard refuses an `Origin` that is not the host it was
  /// dialed at: so it is the dialed address's, never the Plex page's.
  String? get _dialedOrigin {
    final base = Uri.tryParse(dio.options.baseUrl);
    if (base == null || !base.hasAuthority || base.host.isEmpty) return null;
    if (base.scheme != 'http' && base.scheme != 'https') return null;
    return base.origin;
  }

  // === Before anyone signs in ==============================================

  /// The ways in this Tracearr has (`GET /api/v1/setup/status`, no key). Throws
  /// when what answered is not Tracearr's.
  Future<TracearrOwnerWays> readWays() async {
    final response = await _api.get('/api/v1/setup/status');
    final ways = TracearrOwnerWays.fromJson(response.data);
    if (ways == null) {
      throw const TracearrAnswerUnread('the ways to sign in');
    }
    return ways;
  }

  /// Signs in with a name or an email and a password and answers the bearer.
  ///
  /// An `@` is an email (`/sign-in/email`), anything else a username
  /// (`/sign-in/username`). The password goes in this one body and nowhere
  /// else; the token is read from the `set-auth-token` header and never
  /// logged. Throws [TracearrSignInRefused] for what Tracearr can say about
  /// the attempt.
  Future<String> signIn({
    required String login,
    required String password,
  }) async {
    final typed = login.trim();
    final byEmail = typed.contains('@');
    try {
      final response = await _api.post(
        byEmail ? '$_auth/sign-in/email' : '$_auth/sign-in/username',
        data: {(byEmail ? 'email' : 'username'): typed, 'password': password},
      );
      return _bearerOf(response);
    } on DioException catch (error) {
      throw _refusalOf(error) ?? error;
    }
  }

  // === Plex ================================================================

  /// Asks Tracearr for a Plex PIN (`POST /plex/initiate`). Tracearr makes it,
  /// so plex.tv never hears from Cupola, and answers the page to open and the
  /// `plex_pin` cookie that binds the PIN to this client.
  Future<TracearrPlexPin> startPlex() async {
    final response = await _api.post('$_auth/plex/initiate', data: const {});
    final body = asTracearrJson(response.data);
    final handle = body?.text('handle');
    final page = Uri.tryParse(body?.text('authUrl') ?? '');
    if (handle == null ||
        page == null ||
        page.scheme != 'https' ||
        !_plexHosts.contains(page.host.toLowerCase())) {
      throw const TracearrAnswerUnread('the Plex page');
    }
    final cookie = _setCookiesOf(response).entries
        .where((entry) => entry.key.endsWith(_plexPinCookie))
        .map((entry) => '${entry.key}=${entry.value}')
        .firstOrNull;
    if (cookie == null) throw const TracearrAnswerUnread('the Plex pin');
    return TracearrPlexPin._(authUrl: page, handle: handle, cookie: cookie);
  }

  /// Asks whether the owner approved [pin] (`POST /plex/check-pin`), sending
  /// the cookie that binds it. Throws [TracearrSignInRefused] when this Plex
  /// account may not sign in, or would create an owner.
  Future<TracearrPlexCheck> checkPlex(TracearrPlexPin pin) async {
    final Response response;
    try {
      response = await dio.post<dynamic>(
        '$_auth/plex/check-pin',
        data: {'handle': pin._handle},
        options: Options(
          headers: {'Cookie': pin._cookie, 'Origin': ?_dialedOrigin},
        ),
      );
    } on DioException catch (error) {
      throw _refusalOf(error) ?? error;
    }
    final body = asTracearrJson(response.data);
    if (body?.flag('expired') == true) return const TracearrPlexExpired();
    if (body?.flag('authorized') != true) return const TracearrPlexWaiting();
    // A server with no owner yet would create one from this PIN: never here.
    if (body?.flag('needsServerSelection') == true) {
      throw const TracearrSignInRefused(TracearrSignInRefusal.notSetUp);
    }
    return TracearrPlexSignedIn(_bearerOf(response));
  }

  // === The session =========================================================

  /// Who the session belongs to (`GET /api/v1/auth/me`) and their role.
  Future<TracearrOwnerIdentity> whoAmI() async {
    final body = asTracearrJson(await _read('$_auth/me'));
    if (body == null) throw const TracearrAnswerUnread('who this is');
    final name = body.text('username') ?? '';
    return TracearrOwnerIdentity(
      name: name,
      isOwner: body.text('role') == 'owner',
    );
  }

  /// Reads the session (`GET /api/v1/auth/get-session`). Better Auth moves its
  /// end 30 days past this request once the session is a day old, which is
  /// what keeps a used session alive. `alive` is false when Tracearr answered
  /// that it knows no such session.
  Future<TracearrSessionRead> session() async {
    final Response response;
    try {
      response = await _api.get('$_auth/get-session');
    } on DioException catch (error) {
      // A gateway's 401 (an expired Access token, a proxy's password prompt)
      // says nothing about Tracearr's session.
      if (error.response?.statusCode == 401 &&
          error.error is! AccessGatewayAnswer) {
        return const TracearrSessionRead(alive: false);
      }
      rethrow;
    }
    final data = response.data;
    // Better Auth answers a session it does not know with a bare JSON `null`.
    // Anything else that is not its `{session, user}` is not its answer (a
    // proxy's page, another service), and says nothing about the session.
    if (data == null) return const TracearrSessionRead(alive: false);
    final session = asTracearrJson(asTracearrJson(data)?['session']);
    if (session == null) throw const TracearrAnswerUnread('the session');
    final expires = session.text('expiresAt');
    return TracearrSessionRead(
      alive: true,
      expiresAt: expires == null ? null : DateTime.tryParse(expires),
    );
  }

  /// Signs the session out of Tracearr (`POST /sign-out`), so it ends there
  /// too rather than 30 days after it was last used. Bounded and quiet.
  Future<void> signOut() async {
    if (_token.isEmpty) return;
    try {
      await _api
          .post('$_auth/sign-out', data: const {})
          .timeout(kTracearrSignOutPatience);
    } catch (_) {
      // The session is forgotten here either way.
    }
  }

  // === The two writes ======================================================

  @override
  Future<TracearrOwnerOutcome> acknowledge(String violationId) =>
      _write('PATCH', violationId);

  @override
  Future<TracearrOwnerOutcome> dismiss(String violationId) =>
      _write('DELETE', violationId);

  Future<TracearrOwnerOutcome> _write(String method, String id) async {
    if (_token.isEmpty || _ended) return TracearrOwnerOutcome.signedOut;
    final path = '/api/v1/violations/${Uri.encodeComponent(id)}';
    try {
      // A JSON content type with no body is a 400 on Tracearr's side, so an
      // empty object goes out, as it does on stopping a stream.
      final response = method == 'PATCH'
          ? await _api.patch(path, data: const {})
          : await _api.delete(path, data: const {});
      return _wrote(response.data);
    } on DioException catch (error) {
      if (error.error is AccessGatewayAnswer) {
        return TracearrOwnerOutcome.failed;
      }
      final status = error.response?.statusCode;
      if (status == null) return TracearrOwnerOutcome.failed;
      return _refused(status, error.response?.data);
    } catch (_) {
      return TracearrOwnerOutcome.failed;
    }
  }

  /// A 2xx that is not `{"success": true}` is a route that changed under us.
  static TracearrOwnerOutcome _wrote(Object? data) =>
      asTracearrJson(data)?.flag('success') == true
      ? TracearrOwnerOutcome.done
      : TracearrOwnerOutcome.unavailable;

  /// What a refused write meant, by the words Tracearr's own routes use. The
  /// order matters: a route that is not there and a member the owner-only
  /// guard hides the route from are both a 404, and only the words differ.
  TracearrOwnerOutcome _refused(int status, Object? data) {
    final body = asTracearrJson(data);
    final message = body?.text('message');
    switch (status) {
      case 401:
        _end();
        return TracearrOwnerOutcome.signedOut;
      case 403:
        return message == 'Owner access required'
            ? TracearrOwnerOutcome.notOwner
            : TracearrOwnerOutcome.failed;
      case 404:
        if (message == 'Violation not found') return TracearrOwnerOutcome.gone;
        // `reply.notFound()`: what the owner-only guard answers a member.
        if (body?.integer('statusCode') == 404 && message == 'Not Found') {
          return TracearrOwnerOutcome.notOwner;
        }
        // Fastify's unmatched route: `{"error":"Not Found"}`, or no JSON.
        return TracearrOwnerOutcome.unavailable;
      case 400 || 405 || 410 || 501:
        return TracearrOwnerOutcome.unavailable;
      default:
        return TracearrOwnerOutcome.failed;
    }
  }

  // === Plumbing ============================================================

  /// A read that turns a refusal as unsigned into [TracearrOwnerSessionEnded].
  Future<Object?> _read(String path) async {
    try {
      return (await _api.get(path)).data;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 &&
          error.error is! AccessGatewayAnswer) {
        _end();
        throw const TracearrOwnerSessionEnded();
      }
      rethrow;
    }
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _events.onSessionEnded?.call();
  }

  /// The bearer Better Auth handed back: the `set-auth-token` header, or, if a
  /// Tracearr ever left it out, the session cookie's value (the same signed
  /// token, URL-encoded).
  String _bearerOf(Response response) {
    final header = response.headers.value(_tokenHeader)?.trim();
    if (header != null && header.isNotEmpty) return header;
    for (final MapEntry(:key, :value) in _setCookiesOf(response).entries) {
      if (key.endsWith(_sessionCookieSuffix) && value.isNotEmpty) {
        return Uri.decodeComponent(value);
      }
    }
    throw const TracearrAnswerUnread('the session');
  }

  /// [error] as what Tracearr said of a sign-in, or null when it said nothing
  /// of the kind (a transport failure, a gateway, a 5xx).
  static TracearrSignInRefused? _refusalOf(DioException error) {
    if (error.error is AccessGatewayAnswer) return null;
    final body = mapOrNull(error.response?.data);
    final code = body?['code'];
    return switch (error.response?.statusCode) {
      401 => const TracearrSignInRefused(TracearrSignInRefusal.wrongPassword),
      // The origin checks are 403s too, and not the account's doing: Better
      // Auth's (a foreign or a missing `Origin`) and Tracearr's own, which
      // answers `{"error":"Forbidden", "message":"This request did not come
      // from Tracearr."}` with no code.
      403
          when code == 'INVALID_ORIGIN' ||
              code == 'MISSING_OR_NULL_ORIGIN' ||
              body?['message'] == _notFromTracearr =>
        null,
      403 => const TracearrSignInRefused(TracearrSignInRefusal.notAllowed),
      429 => const TracearrSignInRefused(TracearrSignInRefusal.tooManyTries),
      _ => null,
    };
  }

  /// The `name=value` of every `Set-Cookie` of [response], by name, the
  /// attributes left behind.
  static Map<String, String> _setCookiesOf(Response response) {
    final cookies = <String, String>{};
    for (final line in response.headers['set-cookie'] ?? const <String>[]) {
      final pair = line.split(';').first;
      final at = pair.indexOf('=');
      if (at <= 0) continue;
      cookies[pair.substring(0, at).trim()] = pair.substring(at + 1).trim();
    }
    return cookies;
  }

  /// Never the bearer.
  @override
  String toString() =>
      'TracearrOwnerClient(${_token.isEmpty ? 'no session' : 'session'})';
}
