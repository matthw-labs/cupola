import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/route_knock.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/real_network.dart';

KnockAnswer _answer(
  int status,
  String body, {
  Map<String, List<String>> headers = const {},
}) => (status: status, headers: headers, body: body);

bool _answers(ServiceKey service, KnockAnswer answer) =>
    knockPlanOf(service, 'http://nas.lan:1234')!.answers(answer);

/// A captive portal's page, or a gateway's sign-in, answered in a service's
/// place: never the service.
final _portal = _answer(
  200,
  '<html><body><form action="/login">Hotel Wi-Fi</form></body></html>',
);

void main() {
  useRealNetwork();

  group('what proves the service, as the lab answers', () {
    test('an arr and Bazarr: a key-less ping that says OK', () {
      for (final service in [
        ServiceKey.radarr,
        ServiceKey.sonarr,
        ServiceKey.lidarr,
        ServiceKey.readarr,
        ServiceKey.prowlarr,
        ServiceKey.bazarr,
      ]) {
        expect(_answers(service, _answer(200, '{"status": "OK"}')), isTrue);
        expect(_answers(service, _answer(401, '{"status": "OK"}')), isFalse);
      }
    });

    test('Seerr, Jellyfin, Plex, SABnzbd, Nginx Proxy Manager', () {
      expect(
        _answers(
          ServiceKey.seerr,
          _answer(200, '{"version":"3.4.1","commitTag":"69f73a6f"}'),
        ),
        isTrue,
      );
      expect(
        _answers(
          ServiceKey.jellyfin,
          _answer(
            200,
            '{"ServerName":"Lab","Version":"10.10.7",'
            '"ProductName":"Jellyfin Server","Id":"abc"}',
          ),
        ),
        isTrue,
      );
      expect(
        _answers(
          ServiceKey.plex,
          _answer(200, '{"MediaContainer":{"size":0,"claimed":true}}'),
        ),
        isTrue,
      );
      expect(
        _answers(
          ServiceKey.plex,
          _answer(200, '<?xml version="1.0"?><MediaContainer size="0"/>'),
        ),
        isTrue,
      );
      expect(
        _answers(ServiceKey.sabnzbd, _answer(200, '{"version":"5.1.3"}')),
        isTrue,
      );
      expect(
        _answers(
          ServiceKey.nginxProxyManager,
          _answer(200, '{"status":"OK","version":{"major":2}}'),
        ),
        isTrue,
      );
    });

    test(
      'Emby and Jellyfin answer one route and are told apart by its body',
      () {
        // Recorded from real servers: Emby 4.10 sends no `ProductName` and a
        // `LocalAddresses` list; Jellyfin sends `ProductName` and a single
        // `LocalAddress`. The Jellyfin plan knocks at the root, the Emby plan
        // under `/emby`, and neither takes the other's answer.
        final emby = File(
          'test/fixtures/emby/system_info_public.json',
        ).readAsStringSync();
        final jellyfin = File(
          'test/fixtures/jellyfin/system_info_public.json',
        ).readAsStringSync();

        expect(
          knockPlanOf(ServiceKey.emby, 'http://nas.lan:8096')!.path,
          '/emby/System/Info/Public',
        );
        expect(_answers(ServiceKey.emby, _answer(200, emby)), isTrue);
        expect(_answers(ServiceKey.emby, _answer(200, jellyfin)), isFalse);
        expect(_answers(ServiceKey.jellyfin, _answer(200, jellyfin)), isTrue);
        expect(_answers(ServiceKey.jellyfin, _answer(200, emby)), isFalse);
        expect(_answers(ServiceKey.emby, _answer(401, emby)), isFalse);
      },
    );

    test('Tracearr: a degraded or maintenance health still answers', () {
      for (final body in [
        '{"status":"maintenance","mode":"maintenance","db":true,"redis":false}',
        '{"status":"degraded","db":false,"redis":true}',
      ]) {
        expect(_answers(ServiceKey.tracearr, _answer(200, body)), isTrue);
      }
      expect(
        _answers(ServiceKey.tracearr, _answer(200, '{"status":"ok"}')),
        isFalse,
      );
    });

    test('qBittorrent: its version, or Forbidden to a caller signed out', () {
      expect(_answers(ServiceKey.qbittorrent, _answer(200, 'v5.0.4')), isTrue);
      expect(
        _answers(ServiceKey.qbittorrent, _answer(403, 'Forbidden')),
        isTrue,
      );
      expect(
        _answers(ServiceKey.qbittorrent, _answer(403, '<html>no</html>')),
        isFalse,
      );
    });

    test('Transmission: its session id, or its own realm', () {
      expect(
        _answers(
          ServiceKey.transmission,
          _answer(
            409,
            '',
            headers: {
              'x-transmission-session-id': ['abc'],
            },
          ),
        ),
        isTrue,
      );
      expect(
        _answers(
          ServiceKey.transmission,
          _answer(
            401,
            '<h1>401: Unauthorized</h1>',
            headers: {
              'www-authenticate': ['Basic realm="Transmission"'],
            },
          ),
        ),
        isTrue,
      );
      expect(
        _answers(ServiceKey.transmission, _answer(401, 'Unauthorized')),
        isFalse,
      );
    });

    test('Transmission is knocked at the endpoint its client resolves', () {
      expect(
        knockPlanOf(ServiceKey.transmission, 'http://nas.lan:9091')!.path,
        'http://nas.lan:9091/transmission/rpc',
      );
      expect(
        knockPlanOf(ServiceKey.transmission, 'https://nas.lan/tr')!.path,
        'https://nas.lan/tr/rpc',
      );
    });

    test('NZBGet: its own realm', () {
      expect(
        _answers(
          ServiceKey.nzbget,
          _answer(
            401,
            '',
            headers: {
              'www-authenticate': ['Basic realm="NZBGet"'],
            },
          ),
        ),
        isTrue,
      );
    });

    test('Dockge: its own page names it', () {
      expect(
        _answers(
          ServiceKey.dockge,
          _answer(200, '<!DOCTYPE html><html><head><title>Dockge</title>'),
        ),
        isTrue,
      );
    });

    test('Dockge: another Socket.IO server is not Dockge', () {
      // Tracearr opens the same polling session without signing in, and its
      // page names Tracearr: neither answer may read as Dockge.
      expect(
        _answers(
          ServiceKey.dockge,
          _answer(
            200,
            '0{"sid":"fog1","upgrades":["websocket"],"pingInterval":25000}',
          ),
        ),
        isFalse,
      );
      expect(
        _answers(
          ServiceKey.dockge,
          _answer(200, '<!DOCTYPE html><html><head><title>Tracearr</title>'),
        ),
        isFalse,
      );
    });

    test('TrueNAS is knocked by opening a connection to its port', () {
      expect(knockPlanOf(ServiceKey.truenas, 'https://nas.lan'), isNull);
    });

    test('a captive portal or a sign-in page is no service but Unraid', () {
      for (final service in ServiceKey.values) {
        final plan = knockPlanOf(service, 'http://nas.lan:1234');
        if (plan == null) continue;
        expect(
          plan.answers(_portal),
          service == ServiceKey.unraid,
          reason: '$service',
        );
      }
    });
  });

  group('who may receive the access layer after a challenge', () {
    test('a host TLS has authenticated', () {
      expect(
        mayCarryAccessAfterChallenge(Uri.parse('https://radarr.example.com')),
        isTrue,
      );
      expect(
        mayCarryAccessAfterChallenge(Uri.parse('https://192.168.1.10:7878')),
        isTrue,
      );
    });

    test('never a cleartext address, at home or away', () {
      expect(
        mayCarryAccessAfterChallenge(Uri.parse('http://192.168.1.10:7878')),
        isFalse,
      );
      expect(
        mayCarryAccessAfterChallenge(Uri.parse('http://radarr.example.com')),
        isFalse,
      );
    });
  });

  group('a knock on a server', () {
    late HttpServer server;
    late List<HttpHeaders> received;
    late FutureOr<void> Function(HttpRequest request) handle;

    setUp(() async {
      received = [];
      handle = (request) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"status": "OK"}');
      };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        received.add(request.headers);
        await handle(request);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
    });

    String url() => 'http://127.0.0.1:${server.port}';

    Future<bool> knock({
      ConnectionAccess access = const NoAccess(),
      Duration timeout = const Duration(seconds: 2),
    }) => knockAt(
      ServiceKey.radarr,
      (url: url(), access: access, pin: null),
      timeout: timeout,
      hostReach: (_) async => false,
    );

    test('answered as the service is true', () async {
      expect(await knock(), isTrue);
    });

    test(
      'sends no key and no access to a server that answered directly',
      () async {
        await knock(
          access: const CustomHeaders([
            (name: 'X-Proxy-Key', value: 'gateway-value'),
          ]),
        );

        final headers = received.single;
        expect(headers.value('x-api-key'), isNull);
        expect(headers.value('authorization'), isNull);
        expect(headers.value('x-proxy-key'), isNull);
      },
    );

    test(
      'a challenge over http never gets the access: the host is unproved',
      () async {
        var calls = 0;
        handle = (request) {
          calls++;
          if (request.headers.value('x-proxy-key') == null) {
            request.response
              ..statusCode = 401
              ..headers.set('www-authenticate', 'Basic realm="gateway"');
            return;
          }
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write('{"status": "OK"}');
        };

        expect(
          await knock(
            access: const CustomHeaders([
              (name: 'X-Proxy-Key', value: 'gateway-value'),
            ]),
          ),
          isFalse,
        );
        expect(calls, 1);
        expect(received.single.value('x-proxy-key'), isNull);
      },
    );

    test('a redirect is not the service', () async {
      handle = (request) {
        request.response
          ..statusCode = 302
          ..headers.set('location', 'http://portal.example/login');
      };

      expect(await knock(), isFalse);
    });

    test('a foreign redirect never gets the access on a retry', () async {
      var calls = 0;
      handle = (request) {
        calls++;
        request.response
          ..statusCode = 302
          ..headers.set('location', 'http://portal.example/login');
      };

      expect(
        await knock(
          access: const CustomHeaders([
            (name: 'X-Proxy-Key', value: 'gateway-value'),
          ]),
        ),
        isFalse,
      );
      expect(calls, 1);
    });

    test('a server that never answers is false within the time', () async {
      final never = Completer<void>();
      addTearDown(never.complete);
      handle = (_) => never.future;

      final watch = Stopwatch()..start();
      expect(await knock(timeout: const Duration(milliseconds: 300)), isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('nothing listening is false', () async {
      final port = server.port;
      await server.close(force: true);

      expect(
        await knockAt(
          ServiceKey.radarr,
          (url: 'http://127.0.0.1:$port', access: const NoAccess(), pin: null),
          timeout: const Duration(seconds: 1),
          hostReach: (_) async => false,
        ),
        isFalse,
      );
    });
  });
}
