import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

Object? _fixture(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync());

const _page = '<!DOCTYPE html><html><body>Welcome to nginx!</body></html>';

/// What each service's own probe answers, from the fixtures where there is
/// one and from the shape its client parses where there is not.
final Map<ServiceKey, Object?> _genuine = {
  ServiceKey.radarr: {'appName': 'Radarr', 'version': '5.26.2.10099'},
  ServiceKey.sonarr: {'appName': 'Sonarr', 'version': '4.0.15.2941'},
  ServiceKey.lidarr: {'appName': 'Lidarr', 'version': '2.13.3.4711'},
  ServiceKey.readarr: {'appName': 'Readarr', 'version': '0.4.18.2805'},
  ServiceKey.prowlarr: {'appName': 'Prowlarr', 'version': '2.0.5.5160'},
  ServiceKey.seerr: {'version': '2.7.3', 'commitTag': 'v2.7.3'},
  ServiceKey.bazarr: {
    'data': {'bazarr_version': '1.5.1'},
  },
  ServiceKey.jellyfin: _fixture('jellyfin/system_info_public.json'),
  ServiceKey.plex: _fixture('plex/identity.json'),
  ServiceKey.emby: _fixture('emby/system_info_public.json'),
  ServiceKey.tracearr: _fixture('tracearr/real_health.json'),
  ServiceKey.sabnzbd: _fixture('sabnzbd/version.json'),
  ServiceKey.qbittorrent: 'v5.1.2',
  ServiceKey.nginxProxyManager: {
    'status': 'OK',
    'setup': true,
    'version': {'major': 2, 'minor': 12, 'revision': 6},
  },
  ServiceKey.nzbget: _fixture('nzbget/version.json'),
  ServiceKey.transmission: {
    'arguments': {'version': '4.0.6'},
    'result': 'success',
  },
  ServiceKey.unraid: {
    'data': {
      'info': {
        'os': {'release': '7.1.4'},
      },
    },
  },
  ServiceKey.truenas: {'version': 'TrueNAS-SCALE-25.04.2'},
  ServiceKey.dockge: '1.5.0',
};

void main() {
  group('identifyProbeAnswer', () {
    test('every service recognises its own answer', () {
      expect(_genuine.keys, containsAll(ServiceKey.values));
      for (final service in ServiceKey.values) {
        expect(
          identifyProbeAnswer(service, _genuine[service]),
          ProbeIdentity.matches,
          reason: service.title,
        );
      }
    });

    test('a web page is not the service, for every service that reads one', () {
      for (final service in ServiceKey.values) {
        if (service == ServiceKey.truenas || service == ServiceKey.dockge) {
          continue;
        }
        expect(
          identifyProbeAnswer(service, _page),
          ProbeIdentity.notThisService,
          reason: service.title,
        );
      }
    });

    test('TrueNAS and Dockge are proven by their handshake', () {
      for (final body in [null, _page, const <String, Object?>{}]) {
        expect(
          identifyProbeAnswer(ServiceKey.truenas, body),
          ProbeIdentity.matches,
        );
        expect(
          identifyProbeAnswer(ServiceKey.dockge, body),
          ProbeIdentity.matches,
        );
      }
    });

    test('an arr on another arr\'s port is that arr', () {
      final identity = identifyProbeAnswer(
        ServiceKey.radarr,
        _genuine[ServiceKey.sonarr],
      );

      expect(identity, isA<ProbeOtherService>());
      expect((identity as ProbeOtherService).service, ServiceKey.sonarr);
      // Named by appName whatever the address was for.
      expect(
        identifyProbeAnswer(ServiceKey.bazarr, {
          'appName': 'Prowlarr',
          'version': '2.0.5',
        }),
        _otherService(ServiceKey.prowlarr),
      );
    });

    test('an arr nobody knows is not this service', () {
      expect(
        identifyProbeAnswer(ServiceKey.radarr, {
          'appName': 'Whisparr',
          'version': '2.0.0',
        }),
        ProbeIdentity.notThisService,
      );
    });

    test('the name compares without case', () {
      expect(
        identifyProbeAnswer(ServiceKey.radarr, {'appName': 'radarr'}),
        ProbeIdentity.matches,
      );
    });

    test('a field merely absent gets the benefit of the doubt', () {
      final olderBuilds = <ServiceKey, Object?>{
        ServiceKey.radarr: {'version': '3.2.2'},
        ServiceKey.seerr: {'version': '1.33.2'},
        ServiceKey.bazarr: {'data': <String, Object?>{}},
        ServiceKey.jellyfin: {'Version': '10.8.13', 'Id': 'abc'},
        ServiceKey.plex: {'MediaContainer': <String, Object?>{}},
        ServiceKey.qbittorrent: '',
        ServiceKey.nginxProxyManager: {'status': 'OK'},
      };
      for (final MapEntry(key: service, value: body) in olderBuilds.entries) {
        expect(
          identifyProbeAnswer(service, body),
          ProbeIdentity.matches,
          reason: service.title,
        );
      }
    });

    test('a body that is not the service\'s shape is not the service', () {
      final strangers = <(ServiceKey, Object?)>[
        (ServiceKey.radarr, {'status': 'ok'}),
        (ServiceKey.radarr, [1, 2, 3]),
        (ServiceKey.seerr, {'message': 'Not Found'}),
        (ServiceKey.bazarr, {'version': '1.0'}),
        (ServiceKey.plex, {'version': '1.40'}),
        (ServiceKey.sabnzbd, {'queue': <String, Object?>{}}),
        (ServiceKey.qbittorrent, 'Welcome'),
        (ServiceKey.nginxProxyManager, {'message': 'Hello'}),
        (ServiceKey.nzbget, {'jsonrpc': '2.0'}),
        (ServiceKey.transmission, {'arguments': <String, Object?>{}}),
        (ServiceKey.unraid, {'message': 'Not Found'}),
      ];
      for (final (service, body) in strangers) {
        expect(
          identifyProbeAnswer(service, body),
          ProbeIdentity.notThisService,
          reason: service.title,
        );
      }
    });
  });

  group('Jellyfin and Emby, which answer the same route', () {
    // Jellyfin forked Emby, and `/System/Info/Public` of the two looks alike.
    // Jellyfin sends a `ProductName` and a single `LocalAddress`; Emby 4.10
    // sends no `ProductName` (the spec of it assumed one) and a
    // `LocalAddresses` list. Both bodies are recorded from real servers.
    final emby = _fixture('emby/system_info_public.json');
    final embyInfo = _fixture('emby/system_info.json');
    final jellyfin = _fixture('jellyfin/system_info_public.json');

    test('an Emby on a Jellyfin\'s address is named as Emby', () {
      expect(
        identifyProbeAnswer(ServiceKey.jellyfin, emby),
        _otherService(ServiceKey.emby),
      );
      expect(
        identifyProbeAnswer(ServiceKey.jellyfin, embyInfo),
        _otherService(ServiceKey.emby),
      );
    });

    test('a Jellyfin on an Emby\'s address is named as Jellyfin', () {
      expect(
        identifyProbeAnswer(ServiceKey.emby, jellyfin),
        _otherService(ServiceKey.jellyfin),
      );
    });

    test('each recognises its own, public info and full info alike', () {
      expect(identifyProbeAnswer(ServiceKey.emby, emby), ProbeIdentity.matches);
      expect(
        identifyProbeAnswer(ServiceKey.emby, embyInfo),
        ProbeIdentity.matches,
      );
      expect(
        identifyProbeAnswer(ServiceKey.jellyfin, jellyfin),
        ProbeIdentity.matches,
      );
    });

    test('an empty LocalAddresses list is still the proof', () {
      // A server with no address of its own to advertise: the common case,
      // and the one the lab's Emby is.
      expect(
        identifyProbeAnswer(ServiceKey.jellyfin, {
          'LocalAddresses': <String>[],
          'Version': '4.10.2.0',
        }),
        _otherService(ServiceKey.emby),
      );
    });

    test('a product name, when there is one, decides', () {
      expect(
        identifyProbeAnswer(ServiceKey.emby, {
          'ProductName': 'Emby Server',
          'Version': '4.8.0',
        }),
        ProbeIdentity.matches,
      );
      expect(
        identifyProbeAnswer(ServiceKey.jellyfin, {
          'ProductName': 'Emby Server',
          'Version': '4.8.0',
        }),
        _otherService(ServiceKey.emby),
      );
      expect(
        identifyProbeAnswer(ServiceKey.emby, {
          'ProductName': 'Jellyfin Server',
          'Version': '10.11.0',
        }),
        _otherService(ServiceKey.jellyfin),
      );
      // Named, and not either: not this.
      expect(
        identifyProbeAnswer(ServiceKey.emby, {'ProductName': 'Plex Media'}),
        ProbeIdentity.notThisService,
      );
      expect(
        identifyProbeAnswer(ServiceKey.jellyfin, {'ProductName': 'Plex Media'}),
        ProbeIdentity.notThisService,
      );
    });

    test('a Jellyfin that names no product is told by its own fields', () {
      // An older Jellyfin: no `ProductName`, but its single `LocalAddress`.
      expect(
        identifyProbeAnswer(ServiceKey.emby, {
          'LocalAddress': 'http://192.0.2.24:8096',
          'Version': '10.8.13',
          'Id': 'abc',
        }),
        _otherService(ServiceKey.jellyfin),
      );
    });

    test(
      'a body that is ambiguous gets the benefit of the doubt, both ways',
      () {
        // Nothing in it says which: never fail a genuine server over a field a
        // build or a proxy left out. Each service accepts it.
        const bare = {'Version': '10.8.13', 'Id': 'abc'};
        expect(
          identifyProbeAnswer(ServiceKey.jellyfin, bare),
          ProbeIdentity.matches,
        );
        expect(
          identifyProbeAnswer(ServiceKey.emby, bare),
          ProbeIdentity.matches,
        );
      },
    );

    test('a body with neither shape is neither server', () {
      for (final body in <Object?>[
        {'status': 'ok'},
        {'LocalAddresses': 'not a list', 'message': 'hi'},
        _page,
        [1, 2],
      ]) {
        expect(
          identifyProbeAnswer(ServiceKey.emby, body),
          ProbeIdentity.notThisService,
          reason: '$body',
        );
        expect(
          identifyProbeAnswer(ServiceKey.jellyfin, body),
          ProbeIdentity.notThisService,
          reason: '$body',
        );
      }
    });

    test('the sentence names who answered, as for any other service', () {
      expect(
        connectionFailureDetail(
          WrongServiceAnswer(
            ServiceKey.jellyfin,
            const ProbeIdentity.otherService(ServiceKey.emby),
            url: 'http://nas.home.arpa:8096',
          ),
        ),
        'Emby answered at nas.home.arpa:8096, not Jellyfin.',
      );
      expect(
        connectionFailureDetail(
          WrongServiceAnswer(
            ServiceKey.emby,
            const ProbeIdentity.otherService(ServiceKey.jellyfin),
            url: 'http://nas.home.arpa:8096',
          ),
        ),
        'Jellyfin answered at nas.home.arpa:8096, not Emby.',
      );
    });

    test('Emby\'s /emby is the API\'s prefix, not a path to suggest', () {
      expect(conventionalBasePath(ServiceKey.emby), isNull);
    });
  });

  group('Tracearr health, whatever state it is in', () {
    test('a maintenance or degraded answer is still Tracearr', () {
      for (final body in <Object?>[
        {
          'status': 'maintenance',
          'mode': 'maintenance',
          'db': true,
          'redis': false,
        },
        {'status': 'degraded', 'db': false, 'redis': true, 'timescale': {}},
      ]) {
        expect(
          identifyProbeAnswer(ServiceKey.tracearr, body),
          ProbeIdentity.matches,
          reason: '$body',
        );
      }
    });

    test('a bare status, ok or not, is not Tracearr', () {
      for (final body in <Object?>[
        {'status': 'ok'},
        {'status': 'degraded'},
        {'status': 'maintenance', 'mode': 'maintenance'},
      ]) {
        expect(
          identifyProbeAnswer(ServiceKey.tracearr, body),
          ProbeIdentity.notThisService,
          reason: '$body',
        );
      }
    });

    test('the authenticated shape still needs ok and a version', () {
      expect(
        identifyProbeAnswer(ServiceKey.tracearr, {
          'status': 'ok',
          'version': '1.4.0',
        }),
        ProbeIdentity.matches,
      );
      expect(
        identifyProbeAnswer(ServiceKey.tracearr, {
          'status': 'degraded',
          'version': '1.4.0',
        }),
        ProbeIdentity.notThisService,
      );
    });
  });

  group('WrongServiceAnswer', () {
    test('another service says who answered where', () {
      final error = WrongServiceAnswer(
        ServiceKey.radarr,
        const ProbeIdentity.otherService(ServiceKey.sonarr),
        url: 'http://nas.home.arpa:7878',
      );

      expect(error.reason, ServiceFailureReason.notFound);
      expect(classifyConnectionFailure(error), ServiceFailureReason.notFound);
      expect(
        connectionFailureDetail(error),
        'Sonarr answered at nas.home.arpa:7878, not Radarr.',
      );
      expect(failureRemedy(ServiceFailureReason.notFound), 'Check the address');
    });

    test('something else, with the path hint when the address has none', () {
      expect(
        WrongServiceAnswer(
          ServiceKey.radarr,
          ProbeIdentity.notThisService,
          url: 'https://radarr.example.com',
        ).failureDetail,
        "Something answered at radarr.example.com, but it isn't Radarr.\n"
        'If Radarr sits under a path, add it: https://radarr.example.com/radarr',
      );
      expect(
        WrongServiceAnswer(
          ServiceKey.sonarr,
          ProbeIdentity.notThisService,
          url: 'https://example.com/',
        ).failureDetail,
        "Something answered at example.com, but it isn't Sonarr.\n"
        'If Sonarr sits under a path, add it: https://example.com/sonarr',
      );
    });

    test('no path hint when the address already has a path', () {
      expect(
        WrongServiceAnswer(
          ServiceKey.radarr,
          ProbeIdentity.notThisService,
          url: 'https://example.com/movies',
        ).failureDetail,
        "Something answered at example.com, but it isn't Radarr.",
      );
    });

    test('no path hint for a service that is not put under one', () {
      expect(
        WrongServiceAnswer(
          ServiceKey.plex,
          ProbeIdentity.notThisService,
          url: 'http://nas.home.arpa:32400',
        ).failureDetail,
        "Something answered at nas.home.arpa:32400, but it isn't Plex.",
      );
    });

    test('prints no address', () {
      final error = WrongServiceAnswer(
        ServiceKey.radarr,
        ProbeIdentity.notThisService,
        url: 'https://radarr.example.com',
      );

      expect(error.toString(), isNot(contains('example.com')));
    });
  });

  group('a web page in the service\'s place', () {
    test('reads the same wherever it met the request', () {
      final page = UnexpectedAnswer(
        status: 200,
        body: _page,
        host: 'radarr.example.com',
        baseUrl: 'https://radarr.example.com',
      );

      expect(page.reason, ServiceFailureReason.notFound);
      expect(
        webPageSentence(ServiceKey.radarr, page),
        'A web page answered at radarr.example.com instead of Radarr.\n'
        'If Radarr sits under a path, add it: https://radarr.example.com/radarr',
      );
    });

    test('no path hint when the address has a path', () {
      final page = UnexpectedAnswer(
        body: _page,
        host: 'example.com',
        baseUrl: 'https://example.com/movies',
      );

      expect(
        webPageSentence(ServiceKey.radarr, page),
        'A web page answered at example.com instead of Radarr.',
      );
    });

    test('a page read as text is the same answer, not "isn\'t Radarr"', () {
      // qBittorrent and SABnzbd ask for no JSON, so a page reaches their
      // identity check as text.
      expect(
        () => requireProbeIdentity(
          ServiceKey.qbittorrent,
          _page,
          url: 'http://nas.home.arpa:8080',
        ),
        throwsA(
          isA<UnexpectedAnswer>()
              .having((e) => e.isWebPage, 'isWebPage', isTrue)
              .having((e) => e.host, 'host', 'nas.home.arpa:8080'),
        ),
      );
      // Text that is not a page is still not qBittorrent.
      expect(
        () => requireProbeIdentity(
          ServiceKey.qbittorrent,
          'Welcome',
          url: 'http://nas.home.arpa:8080',
        ),
        throwsA(isA<WrongServiceAnswer>()),
      );
    });

    test('a body that is not a page and does not decode stays unreadable', () {
      expect(
        UnexpectedAnswer(status: 200, body: '{"records": [').reason,
        ServiceFailureReason.invalidResponse,
      );
    });
  });
}

/// An [identifyProbeAnswer] result naming [service].
Matcher _otherService(ServiceKey service) => isA<ProbeOtherService>().having(
  (identity) => identity.service,
  'service',
  service,
);
