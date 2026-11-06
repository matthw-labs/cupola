/// What the registry, the router, the settings and the probes say of Tracearr:
/// the nineteenth service, in the Stream band and not a media server, whose
/// key is a bearer token and whose room has five tabs of its own.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/data/route_knock.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_version.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';

import '../../test_helpers/capturing_http_adapter.dart';
import '../../test_helpers/fake_secure_settings_store.dart';

KnockAnswer _answer(int status, String body) =>
    (status: status, headers: const {}, body: body);

bool _knocks(KnockAnswer answer) =>
    knockPlanOf(ServiceKey.tracearr, 'http://tower.lan:3000')!.answers(answer);

String _fixture(String name) =>
    File('test/fixtures/tracearr/$name').readAsStringSync();

void main() {
  group('the registry', () {
    const service = ServiceKey.tracearr;

    test('is the nineteenth, in the Stream band, and not a media server', () {
      expect(service.index, 18);
      expect(ServiceKey.values.last, service);
      expect(service.domain, ServiceDomain.stream);
      expect(service.isMediaServer, isFalse);
      expect(service.speaksMediaBrowser, isFalse);
      expect(service.givesSessions, isFalse);
      expect(service.title, 'Tracearr');
      expect(service.role, 'Monitoring');
      expect(service.routeParam, 'tracearr');
      expect(service.defaultPort, 3000);
      expect(service.itemLabel, 'servers');
      expect(service.apiVersion, 'v2');
    });

    test('signs in with a bearer key, so no proxy password can travel', () {
      expect(service.usesApiKey, isTrue);
      expect(service.credentialHeader, isNull);
      expect(service.ownHeaders, contains('authorization'));
      expect(service.offersProxyPassword, isFalse);
      expect(accessKindsFor(service), isNot(contains(AccessKind.password)));
      expect(service.hasScopedCredential, isFalse);
    });

    test('says where the key is and what it needs, in Tracearr\'s words', () {
      expect(service.credentialPath, 'Settings → Data & API → API');
      expect(service.setupNote, contains('Generate Key'));
      expect(service.setupNote, contains('trr_pub_'));
      expect(service.setupNote, contains(kTracearrMinVersion));
      expect(service.walkNote, contains(kTracearrMinVersion));
      // The keyless route proves an address and never a key; the connection
      // test and the probe have branches of their own.
      expect(service.statusEndpoint, '/health');
    });

    test('its minimum is the first release with violations, servers and '
        'events in the public API v2', () {
      expect(kTracearrMinVersion, '2.7.0');
      expect(kTracearrMin, TracearrVersion.tryParse('v2.7.0'));
      expect(TracearrVersion.tryParse('v2.6.3')! < kTracearrMin, isTrue);
      expect(TracearrVersion.tryParse('v3.1.4')! >= kTracearrMin, isTrue);
    });

    test('has five tabs of its own, with the shared two reused by name', () {
      expect(serviceTabs[service], [
        ServiceTab.overview,
        ServiceTab.live,
        ServiceTab.history,
        ServiceTab.users,
        ServiceTab.violations,
      ]);
      expect(
        [for (final tab in serviceTabs[service]!) tab.label],
        ['Overview', 'Live', 'History', 'Users', 'Violations'],
      );
    });

    test('its route constants are the tab segments under its own root', () {
      expect(ServiceRoutes.tracearr, '/stack/tracearr');
      expect(ServiceRoutes.tracearr, ServiceRoutes.forService(service));
      for (final (route, tab) in [
        (ServiceRoutes.tracearrOverview, ServiceTab.overview),
        (ServiceRoutes.tracearrLive, ServiceTab.live),
        (ServiceRoutes.tracearrHistory, ServiceTab.history),
        (ServiceRoutes.tracearrUsers, ServiceTab.users),
        (ServiceRoutes.tracearrViolations, ServiceTab.violations),
      ]) {
        expect(route, '${ServiceRoutes.tracearr}/${tab.segment}');
      }
      // A title opened from Live or History lands under the tab it came from.
      expect(ServiceRoutes.mediaMountServices, contains(service));
      expect(
        ServiceRoutes.mediaMountFor('/stack/tracearr/live'),
        '/stack/tracearr/live',
      );
    });
  });

  group('a requester never sees it', () {
    final requester = (
      service: ServiceKey.seerr,
      seerr: SeerrGrant.account(permissions: SeerrPermission.request.value),
    );

    test('its connection makes the app the operator\'s', () {
      expect(
        audienceOf([requester, (service: ServiceKey.tracearr, seerr: null)]),
        Audience.operator,
      );
      expect(
        audienceOf([(service: ServiceKey.tracearr, seerr: null), requester]),
        Audience.operator,
      );
    });

    test('and the requester\'s surfaces may not name it', () {
      const gate = RoleGate(audience: Audience.requester);
      expect(gate.namesService(ServiceKey.tracearr), isFalse);
      expect(
        const RoleGate.operator().namesService(ServiceKey.tracearr),
        isTrue,
      );
    });
  });

  group('settings', () {
    late SharedPreferences prefs;
    late FakeSecureSettingsStore secureStore;
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secureStore = FakeSecureSettingsStore();
      service = SettingsService(prefs, secureStore);
    });

    test('the address and the key persist where the registry says, and a '
        'start with it saved does not crash', () async {
      var settings = await service.loadSettings();
      settings = settings.copyWithService(
        ServiceKey.tracearr,
        url: 'http://tower.lan:3000',
        apiKey: 'trr_pub_secretsecretsecret',
      );
      await service.saveSettings(settings);

      expect(prefs.getString('tracearr_url'), 'http://tower.lan:3000');
      expect(
        await secureStore.read(key: 'secure_tracearr_api_key'),
        'trr_pub_secretsecretsecret',
      );
      // The key is not in the preferences, which are not secret.
      expect(
        prefs.getKeys().map(prefs.get).whereType<String>(),
        isNot(contains('trr_pub_secretsecretsecret')),
      );

      final reloaded = await service.loadSettings();
      final tracearr = reloaded.primaryOf(ServiceKey.tracearr)!;
      expect(tracearr.url, 'http://tower.lan:3000');
      expect(tracearr.credential, 'trr_pub_secretsecretsecret');
      expect(tracearr.id, 'tracearr');
      expect(reloaded.isServiceConfigured(ServiceKey.tracearr), isTrue);
      // No viewer: the public key reads everything, as nobody.
      expect(tracearr.viewerId, isEmpty);
    });
  });

  group('who answers', () {
    test('the keyless knock takes Tracearr\'s own health and nothing else', () {
      final plan = knockPlanOf(ServiceKey.tracearr, 'http://tower.lan:3000')!;
      expect(plan.path, '/health');
      expect(
        _knocks(_answer(200, _fixture('real_health_keyless.json'))),
        isTrue,
      );
      // The public health with a version is Tracearr's too.
      expect(_knocks(_answer(200, _fixture('real_health.json'))), isTrue);
      // A refusal, a bare status, and every other service's `OK` are not.
      expect(
        _knocks(_answer(401, _fixture('real_health_keyless.json'))),
        isFalse,
      );
      expect(_knocks(_answer(200, '{"status":"ok"}')), isFalse);
      expect(_knocks(_answer(200, '{"status":"OK","version":"1"}')), isFalse);
      expect(
        _knocks(
          _answer(200, '<html><body><form>Hotel Wi-Fi</form></body></html>'),
        ),
        isFalse,
      );
      expect(_knocks(_answer(200, 'Healthy')), isFalse);
    });

    test('its two health answers are Tracearr, and the rest is not', () {
      Object? json(String name) => _fixtureJson(name);
      for (final name in ['real_health_keyless.json', 'real_health.json']) {
        expect(
          identifyProbeAnswer(ServiceKey.tracearr, json(name)),
          ProbeIdentity.matches,
          reason: name,
        );
      }
      for (final body in <Object?>[
        {'status': 'ok'},
        {'status': 'OK', 'version': 'v1'},
        {'version': 'v3.1.4'},
        {'db': true, 'redis': true},
        'v3.1.4',
        [1],
      ]) {
        expect(
          identifyProbeAnswer(ServiceKey.tracearr, body),
          ProbeIdentity.notThisService,
          reason: '$body',
        );
      }
      expect(conventionalBasePath(ServiceKey.tracearr), 'tracearr');
    });

    test('and the page the owner opens it at, never a secret, is the key '
        'in no address', () {
      expect(
        knockPlanOf(ServiceKey.tracearr, 'http://tower.lan:3000')!.query,
        isEmpty,
      );
    });
  });

  group('the connection test of the client', () {
    TracearrClient client(CapturingHttpAdapter adapter) => TracearrClient(
      baseUrl: 'https://tracearr.test',
      apiKey: 'trr_pub_neverprintmeneverprintmeneverprintme00001',
    )..dio.httpClientAdapter = adapter;

    test('a Tracearr at the minimum is accepted, and below it throws the '
        'version to install', () async {
      final health = _fixtureJson('real_health.json')! as Map;
      final ok = client(
        CapturingHttpAdapter(response: {...health, 'version': 'v2.7.0'}),
      );
      addTearDown(ok.close);
      expect((await ok.checkCredentialAndVersion()).version, 'v2.7.0');

      final old = client(
        CapturingHttpAdapter(response: {...health, 'version': 'v2.6.3'}),
      );
      addTearDown(old.close);
      await expectLater(
        old.checkCredentialAndVersion(),
        throwsA(
          isA<TracearrTooOld>()
              .having((e) => e.found.toString(), 'found', '2.6.3')
              .having((e) => e.failureDetail, 'detail', contains('2.7.0'))
              .having(
                (e) => classifyConnectionFailure(e),
                'reason',
                ServiceFailureReason.invalidResponse,
              ),
        ),
      );
    });

    test(
      'a refused key is a 401 the caller classifies as unauthorized',
      () async {
        final refused = client(
          CapturingHttpAdapter(
            statusCode: 401,
            response: const {
              'statusCode': 401,
              'error': 'UnauthorizedError',
              'message': 'Missing or invalid Authorization header',
            },
          ),
        );
        addTearDown(refused.close);

        await expectLater(
          refused.checkCredentialAndVersion(),
          throwsA(
            isA<DioException>().having(
              (e) => classifyConnectionFailure(e),
              'reason',
              ServiceFailureReason.unauthorized,
            ),
          ),
        );
      },
    );

    test(
      'another service\'s answer is a wrong address, never a connection',
      () async {
        final wrong = client(
          CapturingHttpAdapter(
            response: const {'status': 'OK', 'version': 'v1'},
          ),
        );
        addTearDown(wrong.close);

        await expectLater(
          wrong.checkCredentialAndVersion(),
          throwsA(
            isA<WrongServiceAnswer>().having(
              (e) => e.reason,
              'reason',
              ServiceFailureReason.notFound,
            ),
          ),
        );
      },
    );

    test('a poster is asked for with the key in a header and never in the '
        'address', () {
      final c = client(CapturingHttpAdapter());
      addTearDown(c.close);
      expect(c.imageHeaders['Authorization'], startsWith('Bearer '));
      expect(c.baseUri.toString(), isNot(contains('trr_pub_')));
    });
  });

  group('the words a row says', () {
    test('severity in words, and a dash for one nobody could read', () {
      expect(tracearrSeverityWord(TracearrSeverity.low), 'Low');
      expect(tracearrSeverityWord(TracearrSeverity.warning), 'Warning');
      expect(tracearrSeverityWord(TracearrSeverity.high), 'High');
      expect(tracearrSeverityWord(TracearrSeverity.unknown), '—');
    });

    test('a movie with a TMDB id is a door, and nothing else is', () {
      expect(
        tracearrMediaKeyOf(
          const TracearrMedia(
            type: TracearrMediaType.movie,
            ids: TracearrMediaIds(tmdb: 603),
          ),
        )?.location,
        const MediaKey.movie(603).location,
      );
      for (final media in const [
        TracearrMedia(type: TracearrMediaType.movie),
        TracearrMedia(
          type: TracearrMediaType.episode,
          ids: TracearrMediaIds(tmdb: 603),
        ),
        TracearrMedia(
          type: TracearrMediaType.track,
          ids: TracearrMediaIds(tmdb: 603),
        ),
      ]) {
        expect(tracearrMediaKeyOf(media), isNull, reason: media.type.name);
      }
    });

    test('a series is a door by its TMDB id, else its TheTVDB id, and only a '
        'series with one', () {
      MediaKey? key(TracearrMediaIdentity series) =>
          tracearrSeriesKeyOf(series);

      expect(
        key(
          const TracearrMediaIdentity(
            type: TracearrMediaType.show,
            tmdb: 1399,
            tvdb: 121361,
          ),
        )?.location,
        const MediaKey.tv(1399).location,
      );
      expect(
        key(
          const TracearrMediaIdentity(type: TracearrMediaType.show, tvdb: 5),
        )?.location,
        const MediaKey.tvdb(5).location,
      );
      expect(
        key(const TracearrMediaIdentity(type: TracearrMediaType.show)),
        isNull,
      );
      expect(
        key(
          const TracearrMediaIdentity(type: TracearrMediaType.movie, tmdb: 603),
        ),
        isNull,
        reason: 'a movie is not the series of an episode',
      );
    });

    test('an episode reads by its show and its code', () {
      expect(
        tracearrMediaTitleOf(
          const TracearrMedia(
            type: TracearrMediaType.episode,
            showTitle: 'Night Shift',
            seasonNumber: 1,
            episodeNumber: 2,
            title: 'Rounds',
          ),
        ),
        'Night Shift\u00A0· S1 E2',
      );
    });
  });
}

Object? _fixtureJson(String name) => jsonDecode(_fixture(name));
