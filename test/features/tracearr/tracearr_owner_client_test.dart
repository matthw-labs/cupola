import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_violation_owner.dart';

import '../../test_helpers/fake_tracearr_owner.dart';

const _password = 'a-pretend-password';
const _violation = '9b1f6c2a-3d4e-4f50-8a61-7c8d9e0f1a2b';

/// The owner's client over a Tracearr that answers as the 3.1.4 container
/// measured: address, access and pin from the reach it is given, the bearer in
/// the header, one constructor.
void main() {
  late FakeTracearr server;
  final closers = <TracearrOwnerClient>[];

  TracearrOwnerClient client({
    String token = '',
    TracearrOwnerEvents events = const TracearrOwnerEvents(),
    ConnectionAccess access = const NoAccess(),
    String url = 'https://tracearr.test',
  }) {
    final built = server.factory(
      reach: (url: url, access: access, pin: null),
      token: token,
      events: events,
    );
    closers.add(built);
    return built;
  }

  setUp(() {
    server = FakeTracearr()
      ..addAccount('anna@example.test', password: _password, name: 'anna')
      ..addAccount('anna', password: _password, name: 'anna')
      ..addAccount(
        'ben',
        password: _password,
        role: FakeTracearrRole.member,
        name: 'ben',
      )
      ..addAccount(
        'cleo',
        password: _password,
        role: FakeTracearrRole.admin,
        name: 'cleo',
      )
      ..violations.add(_violation);
  });

  tearDown(() {
    for (final built in closers) {
      built.close();
    }
    closers.clear();
  });

  group('the ways in', () {
    test('are read from setup/status, which needs no credential', () async {
      server
        ..plex = true
        ..oidc = true;

      final ways = await client().readWays();

      expect([ways.local, ways.plex, ways.oidc], [true, true, true]);
      expect(ways.oidcOnly, isFalse);
      final sent = server.requests.single;
      expect(sent.uri.path, '/api/v1/setup/status');
      expect(sent.headers.containsKey('authorization'), isFalse);
    });

    test('single sign-on alone is the one way Cupola cannot use', () async {
      server
        ..local = false
        ..oidc = true;
      final ways = await client().readWays();
      expect(ways.oidcOnly, isTrue);
      expect(ways.none, isTrue);
    });

    test(
      'an answer that is not Tracearr\'s is refused, not guessed at',
      () async {
        final stub = server.factory(
          reach: (
            url: 'https://tracearr.test',
            access: const NoAccess(),
            pin: null,
          ),
        );
        closers.add(stub);
        stub.dio.httpClientAdapter = _Says(200, '{"hello":"world"}');
        await expectLater(
          stub.readWays(),
          throwsA(isA<TracearrAnswerUnread>()),
        );
      },
    );
  });

  group('signing in', () {
    test(
      'by email goes to sign-in/email and the bearer is the header',
      () async {
        final token = await client().signIn(
          login: 'anna@example.test',
          password: _password,
        );

        expect(token, isNotEmpty);
        final sent = server.to('POST', '/sign-in/email').single;
        expect(sent.body, {
          'email': 'anna@example.test',
          'password': _password,
        });
        // The origin check of a browser has no business here: a foreign one is
        // a 403, and a native app sends none.
        expect(sent.headers.containsKey('origin'), isFalse);
        expect(sent.headers.containsKey('cookie'), isFalse);
        expect(server.sessions.containsKey(token), isTrue);
      },
    );

    test('by name goes to sign-in/username', () async {
      await client().signIn(login: ' anna ', password: _password);
      expect(server.to('POST', '/sign-in/username').single.body, {
        'username': 'anna',
        'password': _password,
      });
      expect(server.to('POST', '/sign-in/email'), isEmpty);
    });

    test(
      'a Tracearr that leaves the header out is read from the cookie',
      () async {
        server.bearerOnlyInCookie = true;
        final token = await client().signIn(
          login: 'anna@example.test',
          password: _password,
        );
        expect(server.sessions.containsKey(token), isTrue);
      },
    );

    test('a wrong password is the one refusal that says so', () async {
      await expectLater(
        client().signIn(login: 'anna@example.test', password: 'nope-nope'),
        throwsA(
          isA<TracearrSignInRefused>().having(
            (e) => e.refusal,
            'refusal',
            TracearrSignInRefusal.wrongPassword,
          ),
        ),
      );
    });

    test('a 403 is an account that may not, a 429 too many tries', () async {
      server.signInSays = (status: 403, body: {'code': 'MEMBER_LOGIN_REFUSED'});
      await expectLater(
        client().signIn(login: 'anna', password: _password),
        throwsA(
          isA<TracearrSignInRefused>().having(
            (e) => e.refusal,
            'refusal',
            TracearrSignInRefusal.notAllowed,
          ),
        ),
      );
      server.signInSays = (status: 429, body: {'message': 'slow down'});
      await expectLater(
        client().signIn(login: 'anna', password: _password),
        throwsA(
          isA<TracearrSignInRefused>().having(
            (e) => e.refusal,
            'refusal',
            TracearrSignInRefusal.tooManyTries,
          ),
        ),
      );
    });

    test('a 403 for the origin check is not the account\'s doing', () async {
      server.signInSays = (status: 403, body: {'code': 'INVALID_ORIGIN'});
      await expectLater(
        client().signIn(login: 'anna', password: _password),
        throwsA(isA<DioException>()),
      );
    });

    test(
      'a sign-in with no session in it is refused, not saved empty',
      () async {
        server.signInSays = (status: 200, body: <String, Object?>{});
        await expectLater(
          client().signIn(login: 'anna', password: _password),
          throwsA(isA<TracearrAnswerUnread>()),
        );
      },
    );

    test('neither the password nor the token reaches a toString', () async {
      final token = await client().signIn(login: 'anna', password: _password);
      final owner = client(token: token);
      final text = [
        owner,
        const TracearrSignInRefused(TracearrSignInRefusal.wrongPassword),
      ].join(' ');
      expect(text, isNot(contains(token)));
      expect(text, isNot(contains(_password)));
      expect(
        const TracearrPlexSignedIn('secret-token').toString(),
        isNot(contains('secret')),
      );
    });
  });

  group('who the session is', () {
    test('the owner is told by the role of /auth/me', () async {
      final token = server.mint('anna');
      final who = await client(token: token).whoAmI();
      expect((who.name, who.isOwner), ('anna', true));
      expect(
        server.to('GET', '/auth/me').single.headers['authorization'],
        'Bearer $token',
      );
    });

    test('a member and an administrator are not', () async {
      for (final login in ['ben', 'cleo']) {
        final who = await client(token: server.mint(login)).whoAmI();
        expect(who.isOwner, isFalse, reason: login);
      }
    });

    test(
      'a session Tracearr does not know is an ended one, not a fault',
      () async {
        var ended = 0;
        final owner = client(
          token: 'unknown.sig',
          events: TracearrOwnerEvents(onSessionEnded: () => ended++),
        );
        await expectLater(
          owner.whoAmI(),
          throwsA(
            isA<TracearrOwnerSessionEnded>().having(
              (e) => e.reason,
              'reason',
              ServiceFailureReason.sessionEnded,
            ),
          ),
        );
        expect(ended, 1);
      },
    );

    test('get-session says when it ends, and null says it is over', () async {
      final live = await client(token: server.mint('anna')).session();
      expect(live.alive, isTrue);
      expect(live.expiresAt, DateTime.utc(2099));
      final over = await client(token: 'unknown.sig').session();
      expect(over.alive, isFalse);
    });

    test('a gateway\'s 401 is not Tracearr ending the session', () async {
      final stub = client(token: 'held.sig');
      stub.dio.httpClientAdapter = _Says(
        401,
        '<html>sign in</html>',
        contentType: 'text/html',
        headers: {
          'www-authenticate': ['Basic realm="proxy"'],
        },
      );
      await expectLater(
        stub.session(),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<AccessGatewayAnswer>(),
          ),
        ),
      );
    });

    test(
      'an answer that is not Better Auth\'s says nothing of the session',
      () async {
        for (final body in ['{"hello":"world"}', '{"session":null}', '[]']) {
          final stub = client(token: 'held.sig');
          stub.dio.httpClientAdapter = _Says(200, body);
          await expectLater(
            stub.session(),
            throwsA(isA<TracearrAnswerUnread>()),
            reason: body,
          );
        }
        final none = client(token: 'held.sig');
        none.dio.httpClientAdapter = _Says(200, 'null');
        expect((await none.session()).alive, isFalse);
      },
    );

    test('signing out ends the session at Tracearr too', () async {
      final token = server.mint('anna');
      await client(token: token).signOut();
      expect(server.sessions.containsKey(token), isFalse);
    });
  });

  group('the two writes', () {
    test('Acknowledge is a PATCH on the violation with the bearer', () async {
      final token = server.mint('anna');

      final outcome = await client(token: token).acknowledge(_violation);

      expect(outcome, TracearrOwnerOutcome.done);
      final sent = server.to('PATCH', '/violations/$_violation').single;
      expect(sent.headers['authorization'], 'Bearer $token');
      // An empty object, since a JSON content type with no body is a 400.
      expect(sent.body, <String, Object?>{});
      expect(server.acknowledged, {_violation});
    });

    test('Dismiss is a DELETE on the violation with the bearer', () async {
      final token = server.mint('anna');

      final outcome = await client(token: token).dismiss(_violation);

      expect(outcome, TracearrOwnerOutcome.done);
      expect(
        server
            .to('DELETE', '/violations/$_violation')
            .single
            .headers['authorization'],
        'Bearer $token',
      );
      expect(server.dismissed, {_violation});
    });

    test('the gateway\'s access travels with the write', () async {
      final owner = client(
        token: server.mint('anna'),
        access: const CustomHeaders([(name: 'X-Gateway', value: 'pass')]),
      );
      await owner.acknowledge(_violation);
      expect(server.requests.single.headers['x-gateway'], 'pass');
    });

    test(
      'a violation Tracearr no longer has is gone, never a failure',
      () async {
        final owner = client(token: server.mint('anna'));
        expect(await owner.acknowledge('0000'), TracearrOwnerOutcome.gone);
        expect(await owner.dismiss('0000'), TracearrOwnerOutcome.gone);
      },
    );

    test(
      'an ended session is signed out, once, and sends nothing after',
      () async {
        var ended = 0;
        final owner = client(
          token: 'unknown.sig',
          events: TracearrOwnerEvents(onSessionEnded: () => ended++),
        );
        expect(
          await owner.acknowledge(_violation),
          TracearrOwnerOutcome.signedOut,
        );
        expect(await owner.dismiss(_violation), TracearrOwnerOutcome.signedOut);
        expect(ended, 1);
        expect(server.requests, hasLength(1));
      },
    );

    test('with no session nothing is sent at all', () async {
      expect(
        await client().acknowledge(_violation),
        TracearrOwnerOutcome.signedOut,
      );
      expect(server.requests, isEmpty);
    });

    test('an administrator is not the owner, said by a 403', () async {
      final owner = client(token: server.mint('cleo'));
      expect(
        await owner.acknowledge(_violation),
        TracearrOwnerOutcome.notOwner,
      );
    });

    test(
      'a member is not the owner either, though Tracearr says 404',
      () async {
        // The owner-only guard hides the route from a member with the plain
        // `Not Found`, which must not read as a route that does not exist.
        final owner = client(token: server.mint('ben'));
        expect(await owner.dismiss(_violation), TracearrOwnerOutcome.notOwner);
      },
    );

    test(
      'a route that is not there is unavailable, and so is a changed one',
      () async {
        server.writesAbsent = true;
        final owner = client(token: server.mint('anna'));
        expect(
          await owner.acknowledge(_violation),
          TracearrOwnerOutcome.unavailable,
        );
        expect(
          await owner.dismiss(_violation),
          TracearrOwnerOutcome.unavailable,
        );

        server
          ..writesAbsent = false
          ..writesSay = (status: 200, body: {'ok': true});
        expect(
          await owner.acknowledge(_violation),
          TracearrOwnerOutcome.unavailable,
        );

        for (final status in [400, 405, 501]) {
          server.writesSay = (status: status, body: {'message': 'no'});
          expect(
            await owner.acknowledge(_violation),
            TracearrOwnerOutcome.unavailable,
            reason: '$status',
          );
        }
      },
    );

    test('anything else the server says is a failure to try again', () async {
      final owner = client(token: server.mint('anna'));
      for (final status in [429, 500, 502]) {
        server.writesSay = (status: status, body: {'message': 'busy'});
        expect(
          await owner.dismiss(_violation),
          TracearrOwnerOutcome.failed,
          reason: '$status',
        );
      }
    });
  });

  group('Plex', () {
    setUp(() => server.plex = true);

    test(
      'Tracearr makes the PIN, so the page is Plex\'s and the cookie binds it',
      () async {
        final pin = await client().startPlex();

        expect(pin.authUrl.host, 'app.plex.tv');
        expect(pin.authUrl.scheme, 'https');
        expect(server.to('POST', '/plex/initiate'), hasLength(1));
        // The only requests are Tracearr's: nothing here talks to plex.tv.
        expect(
          server.requests.every((r) => r.uri.host == 'tracearr.test'),
          isTrue,
        );
      },
    );

    test('a page that is not Plex\'s is never handed on', () async {
      final stub = server.factory(
        reach: (
          url: 'https://tracearr.test',
          access: const NoAccess(),
          pin: null,
        ),
      );
      closers.add(stub);
      // A hostile Tracearr's authUrl, through the fake's own answer.
      stub.dio.httpClientAdapter = _Says(
        200,
        '{"handle":"h","authUrl":"https://app.plex.tv.evil.example/auth"}',
        cookie: 'better-auth.plex_pin=b; Path=/',
      );
      await expectLater(stub.startPlex(), throwsA(isA<TracearrAnswerUnread>()));
    });

    test('checking sends the cookie that binds the PIN, and waits', () async {
      final owner = client();
      final pin = await owner.startPlex();

      final waiting = await owner.checkPlex(pin);

      expect(waiting, isA<TracearrPlexWaiting>());
      final sent = server.to('POST', '/plex/check-pin').single;
      expect(sent.body, {'handle': 'handle-1'});
      expect(sent.headers['cookie'], startsWith('better-auth.plex_pin='));
    });

    test('the check carries the origin of the address it dials, and no sign-in '
        'does', () async {
      server.addAccount('plexowner', password: 'x');
      final owner = client(url: 'http://tracearr.test:8443');
      final pin = await owner.startPlex();
      server.approvePlex();

      await owner.checkPlex(pin);
      await client(
        url: 'http://tracearr.test:8443',
      ).signIn(login: 'anna', password: _password);

      // Better Auth refuses a cookie with no origin, and Tracearr one that is
      // not the host dialed: neither the Plex page's nor the default port.
      expect(
        server.to('POST', '/plex/check-pin').single.headers['origin'],
        'http://tracearr.test:8443',
      );
      expect(
        server.to('POST', '/sign-in/username').single.headers,
        isNot(contains('origin')),
      );
    });

    test(
      'a refusal of the origin is the connection\'s, not the account\'s',
      () async {
        for (final says in [
          {
            'code': 'MISSING_OR_NULL_ORIGIN',
            'message': 'Missing or null Origin',
          },
          {
            'error': 'Forbidden',
            'message': 'This request did not come from Tracearr.',
          },
        ]) {
          final stub = client();
          stub.dio.httpClientAdapter = _Says(403, jsonEncode(says));
          await expectLater(
            stub.checkPlex(await client().startPlex()),
            throwsA(isA<DioException>()),
            reason: '$says',
          );
          server.signInSays = (status: 403, body: says);
          await expectLater(
            client().signIn(login: 'anna', password: _password),
            throwsA(isA<DioException>()),
            reason: '$says',
          );
        }
      },
    );

    test('approved, it answers the bearer of an owner session', () async {
      server
        ..addAccount('plexowner', password: 'x')
        ..approvePlex();
      final owner = client();
      final pin = await owner.startPlex();
      server.approvePlex();

      final check = await owner.checkPlex(pin);

      expect(check, isA<TracearrPlexSignedIn>());
      final token = (check as TracearrPlexSignedIn).token;
      expect(server.sessions.containsKey(token), isTrue);
    });

    test('a PIN Tracearr no longer knows has expired', () async {
      final owner = client();
      final pin = await owner.startPlex();
      server.plexPinGone = true;
      expect(await owner.checkPlex(pin), isA<TracearrPlexExpired>());
    });

    test('a Tracearr with no owner never has one created from here', () async {
      final owner = client();
      final pin = await owner.startPlex();
      server
        ..needsSetup = true
        ..approvePlex();
      await expectLater(
        owner.checkPlex(pin),
        throwsA(
          isA<TracearrSignInRefused>().having(
            (e) => e.refusal,
            'refusal',
            TracearrSignInRefusal.notSetUp,
          ),
        ),
      );
    });

    test('Plex sign-in turned off is a refusal, not a hang', () async {
      final owner = client();
      final pin = await owner.startPlex();
      server.plex = false;
      await expectLater(
        owner.checkPlex(pin),
        throwsA(isA<TracearrSignInRefused>()),
      );
    });
  });
}

/// A server that answers every request with one status and body.
class _Says implements HttpClientAdapter {
  _Says(
    this.status,
    this.body, {
    this.cookie,
    this.contentType = 'application/json',
    this.headers = const {},
  });

  final int status;
  final String body;
  final String? cookie;
  final String contentType;
  final Map<String, List<String>> headers;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [contentType],
      'set-cookie': ?(cookie == null ? null : [cookie!]),
      ...headers,
    },
  );
}
