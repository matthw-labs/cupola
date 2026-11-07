import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_version.dart';

/// The two media servers do not authenticate the way every other service does,
/// and verifying them through the shared `ApiClient` was therefore a check that
/// could not fail: `/System/Info/Public` and `/identity` are both anonymous, and
/// neither server reads the `X-Api-Key` header that client sends. Any non-empty
/// string came back 2xx, the tile went green, and every real call then 401ed.
///
/// These cases drive the real clients over a stubbed HTTP stack rather than a
/// stubbed `Dio`, because the client is built inside `diagnoseCredentials` from
/// the values under test, which is exactly the wiring worth asserting on.
void main() {
  group('Jellyfin verification', () {
    test('a rejected key is unauthorized, not a green connection', () async {
      // The shape of the bug: the anonymous endpoint answers perfectly well
      // while the credential is refused.
      final server = _FakeServer({
        '/System/Info': _Reply(401),
        '/System/Info/Public': _Reply(200, body: '{"Version":"10.9.11"}'),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.jellyfin,
          url: 'https://jelly.local:8096',
          apiKey: 'not-a-real-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.unauthorized);
    });

    test('the key travels in the header Jellyfin actually reads', () async {
      final server = _FakeServer({
        '/System/Info': _Reply(200, body: '{"Version":"10.9.11"}'),
      });

      await server.run(
        () => diagnoseCredentials(
          ServiceKey.jellyfin,
          url: 'https://jelly.local:8096',
          apiKey: 'jf-key',
        ),
      );

      final request = server.requestFor('/System/Info')!;
      expect(request.headers['authorization'], contains('MediaBrowser'));
      expect(request.headers['authorization'], contains('Token="jf-key"'));
      // `X-Api-Key` is what the shared client sends and what Jellyfin ignores.
      expect(request.headers.containsKey('x-api-key'), isFalse);
    });

    test('an accepted key connects', () async {
      final server = _FakeServer({
        '/System/Info': _Reply(200, body: '{"Version":"10.9.11"}'),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.jellyfin,
          url: 'https://jelly.local:8096',
          apiKey: 'jf-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.connected);
    });

    test('an accepted key names the version the server reports', () async {
      // The test connection used to say "connected" and nothing else, where the
      // Dashboard's probe names `Version`. Jellyfin spells it with a capital.
      final server = _FakeServer({
        '/System/Info': _Reply(200, body: '{"Version":"10.9.11"}'),
        '/System/Info/Public': _Reply(
          200,
          body: '{"Version":"10.9.11","ServerName":"Home"}',
        ),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.jellyfin,
          url: 'https://jelly.local:8096',
          apiKey: 'jf-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.connected);
      expect(diagnosis.serverVersion, '10.9.11');
    });

    test(
      'a household member\'s token connects, with the public version',
      () async {
        // A 403 from `/System/Info` is a valid token without the administrator's
        // reads: still connected, and the version comes from the anonymous read.
        final server = _FakeServer({
          '/System/Info': _Reply(403),
          '/System/Info/Public': _Reply(200, body: '{"Version":"10.10.3"}'),
        });

        final diagnosis = await server.run(
          () => diagnoseCredentials(
            ServiceKey.jellyfin,
            url: 'https://jelly.local:8096',
            apiKey: 'member-token',
          ),
        );

        expect(diagnosis.status, ServiceConnectionStatus.connected);
        expect(diagnosis.serverVersion, '10.10.3');
      },
    );

    test(
      'a version that cannot be read does not unsettle the verdict',
      () async {
        // Neither read names a version: the authenticated one says none and
        // the anonymous one is down.
        final server = _FakeServer({
          '/System/Info': _Reply(200, body: '{"ServerName":"Home"}'),
          '/System/Info/Public': _Reply(503),
        });

        final diagnosis = await server.run(
          () => diagnoseCredentials(
            ServiceKey.jellyfin,
            url: 'https://jelly.local:8096',
            apiKey: 'jf-key',
          ),
        );

        expect(diagnosis.status, ServiceConnectionStatus.connected);
        expect(diagnosis.serverVersion, isNull);
      },
    );

    test('a server that is not answering is not blamed on the key', () async {
      // Everything fails, credential-free endpoint included, so "the key was
      // rejected" would send the user to rotate a key that was never involved.
      final server = _FakeServer({
        '/System/Info': _Reply(503),
        '/System/Info/Public': _Reply(503),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.jellyfin,
          url: 'https://jelly.local:8096',
          apiKey: 'jf-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.serverError);
      expect(diagnosis.reason, isNot(ServiceFailureReason.unauthorized));
    });

    test('an empty address or key is not configured, not a failure', () async {
      expect(
        (await diagnoseCredentials(
          ServiceKey.jellyfin,
          url: '',
          apiKey: 'jf-key',
        )).status,
        ServiceConnectionStatus.notConfigured,
      );
      expect(
        (await diagnoseCredentials(
          ServiceKey.jellyfin,
          url: 'https://jelly.local:8096',
          apiKey: '   ',
        )).status,
        ServiceConnectionStatus.notConfigured,
      );
    });
  });

  group('Emby verification', () {
    // Emby answers every route under `/emby` and reads its key from
    // `X-Emby-Token`. Its public info is anonymous like Jellyfin's, so the
    // same trap applies: a wrong key must never read as a connection.
    const info =
        '{"LocalAddresses":[],"RemoteAddresses":[],"ServerName":"Emby",'
        '"Version":"4.10.2.0","Id":"a88212fc366d449c8bbe2a34a9e4a91b"}';

    test('a rejected key is unauthorized, not a green connection', () async {
      final server = _FakeServer({
        '/emby/System/Info': _Reply(401),
        '/emby/System/Info/Public': _Reply(200, body: info),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.emby,
          url: 'http://emby.local:8096',
          apiKey: 'not-a-real-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.unauthorized);
    });

    test('the key travels in X-Emby-Token and nowhere else', () async {
      final server = _FakeServer({
        '/emby/System/Info': _Reply(200, body: info),
      });

      await server.run(
        () => diagnoseCredentials(
          ServiceKey.emby,
          url: 'http://emby.local:8096',
          apiKey: 'emby-key',
        ),
      );

      final request = server.requestFor('/emby/System/Info')!;
      expect(request.headers['x-emby-token'], 'emby-key');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers.containsKey('x-api-key'), isFalse);
      expect(request.uri.toString(), isNot(contains('emby-key')));
    });

    test('an accepted key connects and names the version', () async {
      final server = _FakeServer({
        '/emby/System/Info': _Reply(200, body: info),
        '/emby/System/Info/Public': _Reply(200, body: info),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.emby,
          url: 'http://emby.local:8096',
          apiKey: 'emby-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.connected);
      expect(diagnosis.serverVersion, '4.10.2.0');
    });

    test(
      'a household member\'s token connects, with the public version',
      () async {
        final server = _FakeServer({
          '/emby/System/Info': _Reply(403),
          '/emby/System/Info/Public': _Reply(200, body: info),
        });

        final diagnosis = await server.run(
          () => diagnoseCredentials(
            ServiceKey.emby,
            url: 'http://emby.local:8096',
            apiKey: 'member-token',
          ),
        );

        expect(diagnosis.status, ServiceConnectionStatus.connected);
        expect(diagnosis.serverVersion, '4.10.2.0');
      },
    );

    test(
      'a Jellyfin answering the legacy /emby routes is not an Emby',
      () async {
        const jellyfin =
            '{"LocalAddress":"http://192.168.1.24:8096","ServerName":"basement",'
            '"Version":"10.11.11","ProductName":"Jellyfin Server",'
            '"Id":"9f2c1b7e4a3d4f0e8b6c5a1d2e3f4a5b"}';
        final server = _FakeServer({
          '/emby/System/Info': _Reply(200, body: jellyfin),
          '/emby/System/Info/Public': _Reply(200, body: jellyfin),
        });

        final diagnosis = await server.run(
          () => diagnoseCredentials(
            ServiceKey.emby,
            url: 'http://emby.local:8096',
            apiKey: 'emby-key',
          ),
        );

        expect(diagnosis.status, ServiceConnectionStatus.disconnected);
        expect(diagnosis.reason, ServiceFailureReason.notFound);
        expect(diagnosis.answered, ServiceKey.jellyfin);
      },
    );

    test('a server that is not answering is not blamed on the key', () async {
      final server = _FakeServer({
        '/emby/System/Info': _Reply(503),
        '/emby/System/Info/Public': _Reply(503),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.emby,
          url: 'http://emby.local:8096',
          apiKey: 'emby-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.serverError);
    });

    test('an empty address or key is not configured, not a failure', () async {
      expect(
        (await diagnoseCredentials(
          ServiceKey.emby,
          url: '',
          apiKey: 'emby-key',
        )).status,
        ServiceConnectionStatus.notConfigured,
      );
      expect(
        (await diagnoseCredentials(
          ServiceKey.emby,
          url: 'http://emby.local:8096',
          apiKey: '   ',
        )).status,
        ServiceConnectionStatus.notConfigured,
      );
    });
  });

  group('Plex verification', () {
    test('a rejected token is unauthorized, not a green connection', () async {
      final server = _FakeServer({
        '/': _Reply(401),
        '/identity': _Reply(
          200,
          body: '{"MediaContainer":{"version":"1.40.2"}}',
        ),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.plex,
          url: 'https://plex.local:32400',
          apiKey: 'not-a-real-token',
          clientIdentifier: 'test-client-id',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.unauthorized);
    });

    test('the token travels as X-Plex-Token', () async {
      final server = _FakeServer({
        '/': _Reply(200, body: '{"MediaContainer":{"version":"1.40.2"}}'),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.plex,
          url: 'https://plex.local:32400',
          apiKey: 'plex-device-token',
          clientIdentifier: 'test-client-id',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.connected);
      final request = server.requestFor('/')!;
      expect(request.headers['x-plex-token'], 'plex-device-token');
      // Read from settings rather than minted per check: Plex registers a new
      // device row for every distinct identifier it sees.
      expect(request.headers['x-plex-client-identifier'], 'test-client-id');
      expect(request.headers.containsKey('x-api-key'), isFalse);
    });

    test('a plex.tv JSON Web Token is refused before it is sent', () async {
      // No HTTP at all: the client refuses to send a token that expires in seven
      // days and can only be refreshed by plex.tv, which this client never calls.
      // Through the old shared-client path this reached `/identity`, answered
      // 200, and reported a connection that had a week to live.
      final diagnosis = await diagnoseCredentials(
        ServiceKey.plex,
        url: 'https://plex.local:32400',
        apiKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIn0.sig',
        clientIdentifier: 'test-client-id',
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.unauthorized);
    });
  });

  group('the API-key services still verify through the shared client', () {
    test(
      'Seerr verifies the API key against an authenticated endpoint',
      () async {
        final server = _FakeServer({
          '/api/v1/request': _Reply(
            200,
            body: '{"pageInfo":{"results":0},"results":[]}',
          ),
          // Then who answered, as the Dashboard's probe reads it.
          '/api/v1/status': _Reply(
            200,
            body: '{"version":"2.7.3","commitTag":"v2.7.3"}',
          ),
        });

        final diagnosis = await server.run(
          () => diagnoseCredentials(
            ServiceKey.seerr,
            url: 'https://seerr.local:5055',
            apiKey: 'seerr-key',
          ),
        );

        expect(diagnosis.status, ServiceConnectionStatus.connected);
        final request = server.requestFor('/api/v1/request')!;
        expect(request.headers['x-api-key'], 'seerr-key');
        expect(request.uri.queryParameters['take'], '1');
        expect(request.uri.queryParameters['filter'], 'all');
      },
    );

    test('Seerr rejects a wrong API key instead of reporting green', () async {
      final server = _FakeServer({'/api/v1/request': _Reply(403)});

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.seerr,
          url: 'https://seerr.local:5055',
          apiKey: 'wrong',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.unauthorized);
    });

    test('Radarr sends X-Api-Key to its status endpoint', () async {
      final server = _FakeServer({
        '/api/v3/system/status': _Reply(200, body: '{"version":"5.0.0"}'),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.radarr,
          url: 'https://radarr.local:7878',
          apiKey: 'radarr-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.connected);
      expect(
        server.requestFor('/api/v3/system/status')!.headers['x-api-key'],
        'radarr-key',
      );
    });

    test('a rejected API key is still reported as unauthorized', () async {
      final server = _FakeServer({'/api/v3/system/status': _Reply(401)});

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.radarr,
          url: 'https://radarr.local:7878',
          apiKey: 'wrong',
        ),
      );

      expect(diagnosis.reason, ServiceFailureReason.unauthorized);
    });
  });

  // A failure that has already reached its own verdict says so verbatim.
  //
  // `SameOriginRedirectInterceptor` refuses a redirect that would replay
  // `X-Api-Key` to a host the user never configured, and it knows *which* host:
  // information "Could not verify the instance" throws away. The detail channel
  // carries that sentence to the two surfaces that report a connection test, and
  // both read it through the same accessor so they cannot word it differently.
  group('a refused redirect explains itself', () {
    test('the refusal reaches the verdict verbatim', () async {
      final server = _FakeServer({
        '/api/v3/system/status': _Reply(
          302,
          location: 'https://phisher.example/api/v3/system/status',
        ),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.radarr,
          url: 'https://radarr.local:7878',
          apiKey: 'radarr-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      // Not `unknown`: that reaches the user as "Could not verify the
      // instance. Double-check the address and credentials", which is advice
      // for a problem they do not have. Not `notFound` either: the address may
      // be exactly right and the proxy in front of it wrong.
      expect(diagnosis.reason, ServiceFailureReason.redirected);
      expect(diagnosis.detail, isNotNull);
      expect(diagnosis.messageFor(ServiceKey.radarr), diagnosis.detail);
      expect(diagnosis.detail, contains('phisher.example'));

      // And the credential was never replayed to the redirect target.
      expect(
        server.requests.map((r) => r.uri.host),
        everyElement('radarr.local'),
      );
    });

    test('an ordinary failure keeps the reason-derived sentence', () async {
      final server = _FakeServer({'/api/v3/system/status': _Reply(401)});

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.radarr,
          url: 'https://radarr.local:7878',
          apiKey: 'wrong',
        ),
      );

      expect(diagnosis.detail, isNull);
      expect(
        diagnosis.messageFor(ServiceKey.radarr),
        connectionFailureMessage(ServiceKey.radarr, diagnosis.reason),
      );
    });

    test('trusting a certificate does not drop the detail', () {
      // `withCertificateProbe` rebuilds the diagnosis, and forgetting to carry
      // the detail there would lose the sentence on exactly the path that
      // re-reports a failure after a trust decision.
      const refusal = RedirectRefused('sent somewhere else');
      final diagnosis = ServiceDiagnosis.failed(refusal);

      expect(
        diagnosis.withCertificateProbe(null).detail,
        'sent somewhere else',
      );
    });
  });

  group('certProbeWorthwhile', () {
    // A response, any response, proves the TLS handshake completed, so
    // there is no untrusted certificate left to discover. A refused redirect
    // is a response; while it classified as `unknown` it fell into the
    // catch-all and cost every user a pointless probe round trip.
    test('anything the server answered rules the certificate out', () {
      for (final reason in const [
        ServiceFailureReason.unauthorized,
        ServiceFailureReason.notFound,
        ServiceFailureReason.redirected,
        ServiceFailureReason.serverError,
      ]) {
        expect(certProbeWorthwhile(reason), isFalse, reason: '$reason');
      }
    });

    test('a failure a certificate could explain still probes', () {
      for (final reason in const [
        ServiceFailureReason.tls,
        ServiceFailureReason.unreachable,
        ServiceFailureReason.timeout,
        ServiceFailureReason.unknown,
        null,
      ]) {
        expect(certProbeWorthwhile(reason), isTrue, reason: '$reason');
      }
    });

    test('what the probe found becomes the reason', () {
      const silent = ServiceDiagnosis(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.unreachable,
      );
      final plain = silent
          .ofConnection('qb')
          .withFinding(const PlainHttpPort());
      expect(plain.reason, ServiceFailureReason.plainHttp);
      expect(plain.connectionId, 'qb');
      expect(plain.certificateProbe, isNull);

      const probe = (
        certificate: ServerCertificate(
          fingerprint: 'ab',
          subject: 'CN=nas',
          issuer: 'CN=nas',
        ),
        rotated: false,
      );
      final offered = const ServiceDiagnosis(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.noSecureConnection,
      ).withFinding(const UntrustedCertificate(probe));
      expect(offered.reason, ServiceFailureReason.tls);
      expect(offered.certificateProbe, probe);

      expect(silent.withFinding(null), same(silent));
    });

    test('a port that answered in plain http sent no certificate to find', () {
      expect(certProbeWorthwhile(ServiceFailureReason.plainHttp), isFalse);
      expect(localNetworkCouldExplain(ServiceFailureReason.plainHttp), isFalse);
    });
  });

  group('worstDiagnosis', () {
    // The kernel of the per-service fold. `diagnoseService` probes every
    // configured connection and hands the results here, so a Connections row
    // that prints "2 connections" cannot report the state of one of them.
    test('one unreachable connection is never hidden behind a healthy one', () {
      expect(
        worstDiagnosis(const [
          ServiceDiagnosis(ServiceConnectionStatus.connected),
          ServiceDiagnosis(
            ServiceConnectionStatus.disconnected,
            ServiceFailureReason.unreachable,
          ),
        ]).status,
        ServiceConnectionStatus.disconnected,
      );
    });

    test('the reason travels with the state, so the row can name it', () {
      expect(
        worstDiagnosis(const [
          ServiceDiagnosis(ServiceConnectionStatus.connected),
          ServiceDiagnosis(
            ServiceConnectionStatus.disconnected,
            ServiceFailureReason.unauthorized,
          ),
        ]).reason,
        ServiceFailureReason.unauthorized,
      );
    });

    test('all healthy stays healthy', () {
      expect(
        worstDiagnosis(const [
          ServiceDiagnosis(ServiceConnectionStatus.connected),
          ServiceDiagnosis(ServiceConnectionStatus.connected),
        ]).status,
        ServiceConnectionStatus.connected,
      );
    });

    test('a connection still checking outranks one that answered', () {
      // Otherwise a row settles on "Connected" while a sibling is mid-probe and
      // then flips to red a second later.
      expect(
        worstDiagnosis(const [
          ServiceDiagnosis(ServiceConnectionStatus.connected),
          ServiceDiagnosis.checking(),
        ]).status,
        ServiceConnectionStatus.checking,
      );
    });
  });

  group('connectionFailureMessage', () {
    test('a redirect gets its own advice, not the generic shrug', () {
      final redirected = connectionFailureMessage(
        ServiceKey.radarr,
        ServiceFailureReason.redirected,
      );

      expect(
        redirected,
        isNot(connectionFailureMessage(ServiceKey.radarr, null)),
        reason: 'the whole point is not saying "double-check the credentials"',
      );
      expect(
        redirected,
        isNot(
          connectionFailureMessage(
            ServiceKey.radarr,
            ServiceFailureReason.notFound,
          ),
        ),
      );
      expect(redirected, contains('redirect'));
      expect(redirected, contains('Radarr'));
    });

    test('a port in plain http names the https port; TrueNAS has no http '
        'way out', () {
      final truenas = connectionFailureMessage(
        ServiceKey.truenas,
        ServiceFailureReason.plainHttp,
      );
      expect(truenas, contains('HTTPS port'));
      expect(truenas, contains('443'));
      expect(truenas, isNot(contains('http://')));

      final radarr = connectionFailureMessage(
        ServiceKey.radarr,
        ServiceFailureReason.plainHttp,
      );
      expect(radarr, contains('plain http, not https'));
      expect(radarr, contains('http:// for an address used only at home'));
      expect(radarr, isNot(contains('certificate')));
    });

    test('every reason has a sentence, and no two collide', () {
      final messages = {
        for (final reason in ServiceFailureReason.values)
          reason: connectionFailureMessage(ServiceKey.sonarr, reason),
      };

      expect(messages.values.every((m) => m.isNotEmpty), isTrue);
      expect(
        messages.values.toSet(),
        hasLength(ServiceFailureReason.values.length),
        reason: 'a duplicated sentence means a reason nobody can act on',
      );
    });
  });

  group('Tracearr verification', () {
    // `/health` is Tracearr's keyless route and proves an address, never a key,
    // so the test reads the public API's own health with the key: a refused key
    // is a 401 there, and the version it names is the one the minimum is
    // checked against.
    final health = File(
      'test/fixtures/tracearr/real_health.json',
    ).readAsStringSync();
    const refused =
        '{"statusCode":401,"error":"UnauthorizedError",'
        '"message":"Missing or invalid Authorization header"}';
    const healthPath = '/api/v1/public/health';

    test('a refused key is unauthorized, not a green connection', () async {
      final server = _FakeServer({
        '/health': _Reply(200, body: '{"status":"ok","db":true,"redis":true}'),
        healthPath: _Reply(401, body: refused),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.tracearr,
          url: 'http://tracearr.local:3000',
          apiKey: 'trr_pub_not-a-real-key',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.unauthorized);
    });

    test('the key travels as a bearer token and nowhere else', () async {
      final server = _FakeServer({healthPath: _Reply(200, body: health)});

      await server.run(
        () => diagnoseCredentials(
          ServiceKey.tracearr,
          url: 'http://tracearr.local:3000',
          apiKey: 'trr_pub_abc',
        ),
      );

      final request = server.requestFor(healthPath)!;
      expect(request.headers['authorization'], 'Bearer trr_pub_abc');
      expect(request.headers.containsKey('x-api-key'), isFalse);
      expect(request.uri.toString(), isNot(contains('trr_pub_abc')));
    });

    test('an accepted key connects and names the version', () async {
      final server = _FakeServer({healthPath: _Reply(200, body: health)});

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.tracearr,
          url: 'http://tracearr.local:3000',
          apiKey: 'trr_pub_abc',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.connected);
      // Without the `v` Tracearr spells it with, as every other service's.
      expect(diagnosis.serverVersion, '3.1.4');
    });

    test(
      'a Tracearr older than the public API v2 says which to install',
      () async {
        final server = _FakeServer({
          healthPath: _Reply(
            200,
            body: health.replaceFirst('v3.1.4', 'v2.6.3'),
          ),
        });

        final diagnosis = await server.run(
          () => diagnoseCredentials(
            ServiceKey.tracearr,
            url: 'http://tracearr.local:3000',
            apiKey: 'trr_pub_abc',
          ),
        );

        expect(diagnosis.status, ServiceConnectionStatus.disconnected);
        expect(diagnosis.reason, ServiceFailureReason.invalidResponse);
        expect(diagnosis.detail, contains('2.6.3'));
        expect(diagnosis.detail, contains(kTracearrMinVersion));
        // Not a key problem and not an address problem: the remedy is upgrading,
        // and Retry stays for after it.
        expect(failureRetryHelps(diagnosis.reason!), isTrue);
      },
    );

    test('the minimum itself connects', () async {
      final server = _FakeServer({
        healthPath: _Reply(
          200,
          body: health.replaceFirst('v3.1.4', 'v$kTracearrMinVersion'),
        ),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.tracearr,
          url: 'http://tracearr.local:3000',
          apiKey: 'trr_pub_abc',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.connected);
    });

    test('a web page at the address is not Tracearr', () async {
      final server = _FakeServer({
        healthPath: _Reply(
          200,
          body: '<!doctype html><html><body>Welcome to nginx!</body></html>',
        ),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.tracearr,
          url: 'http://tracearr.local:3000',
          apiKey: 'trr_pub_abc',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      // The stubbed stack labels every answer as JSON, so the page reads as
      // an answer nobody can read rather than as a page; either way it is
      // the address that is wrong, never the key.
      expect(
        diagnosis.reason,
        anyOf(
          ServiceFailureReason.notFound,
          ServiceFailureReason.invalidResponse,
        ),
      );
    });

    test('another service answering at the address is not Tracearr', () async {
      final server = _FakeServer({
        healthPath: _Reply(200, body: '{"status":"OK","version":{"major":2}}'),
      });

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.tracearr,
          url: 'http://tracearr.local:3000',
          apiKey: 'trr_pub_abc',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.notFound);
    });

    test('no key, nothing asked', () async {
      final server = _FakeServer({healthPath: _Reply(200, body: health)});

      final diagnosis = await server.run(
        () => diagnoseCredentials(
          ServiceKey.tracearr,
          url: 'http://tracearr.local:3000',
        ),
      );

      expect(diagnosis.status, ServiceConnectionStatus.notConfigured);
      expect(server.requests, isEmpty);
    });
  });
}

// ─── A stubbed HTTP stack ─────────────────────────────────────────────────────
//
// `flutter_test` installs its own `HttpOverrides` that answers 400 to
// everything, which cannot express "this endpoint is fine and that one refuses
// the credential", the exact distinction under test here. The clients build
// their own `Dio` inside `diagnoseCredentials`, so there is no adapter to inject
// either; overriding at the `HttpClient` layer is what remains, and it has the
// advantage of exercising the real header building end to end.

class _Reply {
  const _Reply(this.status, {this.body = '{}', this.location});

  final int status;
  final String body;

  /// Set to answer with a `Location` header, so a redirect can be driven
  /// through the real `SameOriginRedirectInterceptor` rather than simulated.
  final String? location;
}

class _RecordedRequest {
  _RecordedRequest(this.method, this.uri, this.headers);

  final String method;
  final Uri uri;

  /// Lowercased header names, as `HttpHeaders` normalises them.
  final Map<String, String> headers;
}

class _FakeServer {
  _FakeServer(this.replies);

  /// Path → canned reply. A path with no entry answers 404, which is what an
  /// address pointing at the wrong service would do.
  final Map<String, _Reply> replies;

  final List<_RecordedRequest> requests = [];

  _RecordedRequest? requestFor(String path) {
    for (final request in requests) {
      if (request.uri.path == path) return request;
    }
    return null;
  }

  /// Runs [body] with this server installed as the process HTTP stack.
  Future<T> run<T>(Future<T> Function() body) {
    return HttpOverrides.runZoned(body, createHttpClient: (_) => _Client(this));
  }
}

class _Client implements HttpClient {
  _Client(this.server);

  final _FakeServer server;

  // Declared as fields rather than left to `noSuchMethod`, because these are
  // *set* on a freshly built client, by Dio (`idleTimeout`) and by its adapter
  // (`connectionTimeout`), and a missing setter throws before any request is
  // made, which surfaces as an ordinary connection failure and makes the fake
  // look like a real refusal.
  @override
  Duration? connectionTimeout;

  // The observed adapter installs a connection factory on every client so it
  // can count the bytes a socket delivers. A fake that does not declare the
  // setter throws before the request exists, which would read as a refusal.
  @override
  dynamic connectionFactory;

  @override
  Duration idleTimeout = const Duration(seconds: 3);

  @override
  bool autoUncompress = true;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(method, url, server);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // ignore: avoid_print
    print('FAKE CLIENT MISS: ${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

class _Request implements HttpClientRequest {
  _Request(this.method, this.uri, this.server);

  @override
  final String method;

  @override
  final Uri uri;

  final _FakeServer server;

  @override
  final HttpHeaders headers = _Headers();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  void add(List<int> data) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async {
    server.requests.add(
      _RecordedRequest(method, uri, (headers as _Headers).values),
    );
    final reply = server.replies[uri.path] ?? const _Reply(404);
    return _Response(reply);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = '$value';
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    values.forEach((name, value) => action(name, [value]));
  }

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.reply);

  final _Reply reply;

  @override
  int get statusCode => reply.status;

  @override
  String get reasonPhrase => '';

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  X509Certificate? get certificate => null;

  @override
  int get contentLength => reply.body.length;

  @override
  HttpHeaders get headers {
    final headers = _Headers()..set('content-type', 'application/json');
    final location = reply.location;
    if (location != null) headers.set('location', location);
    return headers;
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<Uint8List>.value(
      Uint8List.fromList(utf8.encode(reply.body)),
    ).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
