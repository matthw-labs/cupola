import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:cupola/features/tracearr/data/tracearr_owner_client.dart';

/// One request the fake Tracearr heard.
typedef FakeTracearrRequest = ({
  String method,
  Uri uri,
  Map<String, String> headers,
  Object? body,
});

/// How a person's account on the fake Tracearr is told.
enum FakeTracearrRole { owner, admin, member }

/// A Tracearr 3.1.4 as the throwaway container measured it, for the owner's
/// sign-in and the two writes, over a stubbed socket.
///
/// What it answers is what the real one answered: the bearer in the
/// `set-auth-token` header, `{"code":"INVALID_EMAIL_OR_PASSWORD"}` with a 401,
/// a 403 for a foreign `Origin`, `/auth/me` with the role, `get-session` as
/// `null` for a session it does not know, the two owner-only writes (an
/// administrator a 403, a member a 404 that says `Not Found`, an unknown
/// violation a 404 that says `Violation not found`), Fastify's unmatched route
/// as `{"error":"Not Found"}`, and the Plex PIN that Tracearr itself makes and
/// binds with the `plex_pin` cookie. A POST that carries a cookie and no
/// `Origin` is Better Auth's 403 `MISSING_OR_NULL_ORIGIN`, and an `Origin` that
/// is not the host it was dialed at is Tracearr's own 403 (`This request did
/// not come from Tracearr.`), as measured: the sign-ins send no cookie, so no
/// `Origin` either.
///
/// Passwords and tokens are only ever compared here, never printed.
class FakeTracearr implements HttpClientAdapter {
  FakeTracearr({
    this.local = true,
    this.plex = false,
    this.oidc = false,
    this.needsSetup = false,
  });

  bool local;
  bool plex;
  bool oidc;
  bool needsSetup;

  /// `login -> password`, for a login that is an email or a username.
  final passwords = <String, String>{};
  final roles = <String, FakeTracearrRole>{};
  final names = <String, String>{};

  /// A violation that exists: what a write on it does.
  final violations = <String>{};
  final acknowledged = <String>{};
  final dismissed = <String>{};

  /// While set, `get-session` waits for it before it answers: a read still in
  /// flight while something else happens.
  Completer<void>? holdSessionRead;

  /// A proxy's password prompt in front of Tracearr answers every request: a
  /// 401 with `WWW-Authenticate: Basic`, which is not Tracearr's doing.
  bool gatewayAnswers = false;

  /// Nothing answers: every request fails as a connection that never opened.
  bool down = false;

  /// The writes this Tracearr does not have a route for: an older install.
  bool writesAbsent = false;

  /// Answers every write with this status and body, whatever it is.
  ({int status, Object? body})? writesSay;

  /// The sessions it knows: token to the login that holds it.
  final sessions = <String, String>{};

  /// What the next sign-in says before it looks at the password, when set.
  ({int status, Map<String, Object?> body})? signInSays;

  /// Whether the next sign-in leaves out the `set-auth-token` header and sets
  /// the session cookie instead.
  bool bearerOnlyInCookie = false;

  /// The login the Plex PIN signs in once [approvePlex] is called, with its
  /// role through [roles].
  String plexLogin = 'plexowner';
  bool _plexApproved = false;
  bool plexPinGone = false;
  int _tokens = 0;
  String? _plexBinding;

  final requests = <FakeTracearrRequest>[];

  /// What sign-in would do to a session of [login].
  void addAccount(
    String login, {
    required String password,
    FakeTracearrRole role = FakeTracearrRole.owner,
    String? name,
  }) {
    passwords[login] = password;
    roles[login] = role;
    names[login] = name ?? login;
  }

  void approvePlex() => _plexApproved = true;

  /// A bearer for [login], as if it had signed in: what a saved session is.
  String mint(String login) {
    final token = 'tok-${++_tokens}.sig';
    sessions[token] = login;
    return token;
  }

  /// [TracearrOwnerClient.forReach] with its socket on this server: the factory
  /// a test hands the sign-in, the keeper and the violation page.
  TracearrOwnerClientFactory get factory =>
      ({
        required reach,
        String token = '',
        TracearrOwnerEvents events = const TracearrOwnerEvents(),
        onlyAtHome,
      }) {
        final client = TracearrOwnerClient.forReach(
          reach: reach,
          token: token,
          events: events,
          onlyAtHome: onlyAtHome,
        );
        client.dio.httpClientAdapter = this;
        return client;
      };

  Iterable<FakeTracearrRequest> to(String method, String pathEnd) =>
      requests.where((r) => r.method == method && r.uri.path.endsWith(pathEnd));

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (requestStream != null) {
      final raw = utf8.decode(
        (await requestStream.toList()).expand((c) => c).toList(),
      );
      body = raw.isEmpty ? null : jsonDecode(raw);
    }
    final headers = {
      for (final entry in options.headers.entries)
        entry.key.toLowerCase(): '${entry.value}',
    };
    requests.add((
      method: options.method,
      uri: options.uri,
      headers: headers,
      body: body,
    ));
    if (down) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'nothing answers',
      );
    }
    if (gatewayAnswers) {
      return ResponseBody.fromString(
        '<html>password required</html>',
        401,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
          'www-authenticate': ['Basic realm="proxy"'],
        },
      );
    }
    if (options.uri.path.endsWith('/auth/get-session')) {
      await holdSessionRead?.future;
    }
    final origin = _originCheck(options, headers);
    if (origin != null) return origin;
    return _answer(options.method, options.uri.path, headers, body);
  }

  /// Better Auth's origin check on a POST that carries a cookie, and
  /// Tracearr's own against the dialed host: null when the request passes.
  ResponseBody? _originCheck(
    RequestOptions options,
    Map<String, String> headers,
  ) {
    if (options.method != 'POST' || !headers.containsKey('cookie')) return null;
    final origin = headers['origin'];
    if (origin == null || origin.isEmpty) {
      return _json(403, {
        'message': 'Missing or null Origin',
        'code': 'MISSING_OR_NULL_ORIGIN',
      });
    }
    if (origin != options.uri.origin) {
      return _json(403, {
        'error': 'Forbidden',
        'message': 'This request did not come from Tracearr.',
      });
    }
    return null;
  }

  ResponseBody _json(
    int status,
    Object? body, {
    Map<String, List<String>> headers = const {},
  }) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      ...headers,
    },
  );

  String? _holder(Map<String, String> headers) {
    final bearer = headers['authorization'];
    if (bearer == null || !bearer.startsWith('Bearer ')) return null;
    return sessions[bearer.substring(7)];
  }

  ResponseBody _answer(
    String method,
    String path,
    Map<String, String> headers,
    Object? body,
  ) {
    const base = '/api/v1';
    if (path == '$base/setup/status') {
      return _json(200, {
        'needsSetup': needsSetup,
        'authMethods': {
          'local': local,
          'plex': plex,
          'oidc': oidc,
          'oidcProviderName': null,
          'member': false,
        },
      });
    }
    if (path == '$base/auth/sign-in/email' ||
        path == '$base/auth/sign-in/username') {
      return _signIn(path.endsWith('email'), headers, body);
    }
    if (path == '$base/auth/plex/initiate') {
      _plexBinding = 'binding-${++_tokens}';
      _plexApproved = false;
      return _json(
        200,
        {
          'handle': 'handle-1',
          'authUrl': 'https://app.plex.tv/auth#?clientID=abc&code=xyz',
        },
        headers: {
          'set-cookie': [
            'better-auth.plex_pin=$_plexBinding; Max-Age=900; Path=/; HttpOnly; SameSite=Lax',
          ],
        },
      );
    }
    if (path == '$base/auth/plex/check-pin') return _checkPin(headers);
    if (path == '$base/auth/me') {
      final login = _holder(headers);
      if (login == null) return _unsigned();
      return _json(200, {
        'userId': 'u-1',
        'username': names[login],
        'email': '$login@example.test',
        'role': roles[login]!.name,
      });
    }
    if (path == '$base/auth/get-session') {
      final login = _holder(headers);
      if (login == null) return _json(200, null);
      return _json(200, {
        'session': {'expiresAt': '2099-01-01T00:00:00.000Z'},
        'user': {'role': roles[login]!.name},
      });
    }
    if (path == '$base/auth/sign-out') {
      final bearer = headers['authorization'];
      if (bearer != null && bearer.startsWith('Bearer ')) {
        sessions.remove(bearer.substring(7));
      }
      return _json(200, {'success': true});
    }
    final violation = RegExp('^$base/violations/([^/]+)\$').firstMatch(path);
    if (violation != null && (method == 'PATCH' || method == 'DELETE')) {
      return _write(method, violation.group(1)!, headers);
    }
    return _json(404, {'error': 'Not Found'});
  }

  ResponseBody _unsigned() => _json(401, {
    'statusCode': 401,
    'error': 'UnauthorizedError',
    'message': 'Invalid or expired token',
  });

  ResponseBody _signIn(
    bool byEmail,
    Map<String, String> headers,
    Object? body,
  ) {
    // A browser's own origin check: the app sends none, and a foreign one is
    // a 403 on the real thing.
    if (headers.containsKey('origin')) {
      return _json(403, {
        'code': 'INVALID_ORIGIN',
        'message': 'Invalid origin',
      });
    }
    if (signInSays case final says?) {
      return _json(says.status, says.body);
    }
    final sent = body is Map ? body : const {};
    final login = '${sent[byEmail ? 'email' : 'username']}';
    final ok = passwords[login] != null && passwords[login] == sent['password'];
    if (!ok) {
      return _json(401, {
        'message': byEmail
            ? 'Invalid email or password'
            : 'Invalid username or password',
        'code': byEmail
            ? 'INVALID_EMAIL_OR_PASSWORD'
            : 'INVALID_USERNAME_OR_PASSWORD',
      });
    }
    final token = mint(login);
    return _json(
      200,
      {
        'redirect': false,
        'token': token.split('.').first,
        'user': {'role': roles[login]!.name},
      },
      headers: {
        if (!bearerOnlyInCookie) 'set-auth-token': [token],
        'set-cookie': [
          'better-auth.session_token=${Uri.encodeComponent(token)}; Max-Age=2592000; Path=/; HttpOnly; SameSite=Lax',
        ],
      },
    );
  }

  ResponseBody _checkPin(Map<String, String> headers) {
    if (!plex) {
      return _json(403, {
        'code': 'MEMBER_LOGIN_REFUSED',
        'message': 'Sign-in is not available for this account.',
      });
    }
    final cookie = headers['cookie'] ?? '';
    if (plexPinGone ||
        _plexBinding == null ||
        !cookie.contains(_plexBinding!)) {
      return _json(200, {'authorized': false, 'expired': true});
    }
    if (!_plexApproved) {
      return _json(200, {
        'authorized': false,
        'message': 'PIN not yet authorized',
      });
    }
    if (needsSetup) {
      return _json(200, {
        'authorized': true,
        'needsServerSelection': true,
        'servers': <Object>[],
        'tempToken': 't',
      });
    }
    final token = mint(plexLogin);
    return _json(
      200,
      {
        'authorized': true,
        'user': {'id': 'u-1', 'username': plexLogin},
      },
      headers: {
        'set-auth-token': [token],
      },
    );
  }

  ResponseBody _write(String method, String id, Map<String, String> headers) {
    if (writesAbsent) return _json(404, {'error': 'Not Found'});
    if (writesSay case final says?) return _json(says.status, says.body);
    final login = _holder(headers);
    if (login == null) return _unsigned();
    switch (roles[login]!) {
      case FakeTracearrRole.member:
        return _json(404, {
          'statusCode': 404,
          'error': 'Not Found',
          'message': 'Not Found',
        });
      case FakeTracearrRole.admin:
        return _json(403, {
          'statusCode': 403,
          'error': 'ForbiddenError',
          'message': 'Owner access required',
        });
      case FakeTracearrRole.owner:
        break;
    }
    if (!violations.contains(id) || dismissed.contains(id)) {
      return _json(404, {
        'statusCode': 404,
        'error': 'NotFoundError',
        'message': 'Violation not found',
      });
    }
    if (method == 'PATCH') {
      acknowledged.add(id);
      return _json(200, {
        'success': true,
        'acknowledgedAt': '2026-11-06T12:00:00.000Z',
      });
    }
    dismissed.add(id);
    return _json(200, {'success': true});
  }
}
