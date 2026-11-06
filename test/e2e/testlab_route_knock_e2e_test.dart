@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/host_reach.dart';
import 'package:cupola/features/settings/data/route_knock.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The route probe's knock table against the macOS laboratory: every service
/// answers its knock with no key, and no service answers another's.
///
/// Needs the lab up (`test/e2e/testlab/bootstrap.sh`); no credentials, which
/// is the point.
void main() {
  const lab = <ServiceKey, String>{
    ServiceKey.seerr: 'http://127.0.0.1:5055',
    ServiceKey.radarr: 'http://127.0.0.1:7878',
    ServiceKey.sonarr: 'http://127.0.0.1:8989',
    ServiceKey.lidarr: 'http://127.0.0.1:8686',
    ServiceKey.readarr: 'http://127.0.0.1:8787',
    ServiceKey.prowlarr: 'http://127.0.0.1:9696',
    ServiceKey.bazarr: 'http://127.0.0.1:6767',
    ServiceKey.qbittorrent: 'http://127.0.0.1:8080',
    ServiceKey.transmission: 'http://127.0.0.1:9091',
    ServiceKey.sabnzbd: 'http://127.0.0.1:8082',
    ServiceKey.nzbget: 'http://127.0.0.1:6789',
    ServiceKey.jellyfin: 'http://127.0.0.1:8096',
    ServiceKey.emby: 'http://127.0.0.1:8097',
    ServiceKey.plex: 'http://127.0.0.1:32400',
    ServiceKey.nginxProxyManager: 'http://127.0.0.1:8181',
    ServiceKey.dockge: 'http://127.0.0.1:5001',
    ServiceKey.unraid: 'http://127.0.0.1:8480',
    ServiceKey.truenas: 'https://127.0.0.1:8460',
  };

  Future<bool> knock(ServiceKey service, String url) => knockAt(
    service,
    (url: url, access: const NoAccess(), pin: null),
    timeout: const Duration(seconds: 3),
    hostReach: tcpHostReach,
  );

  test('every service answers its own knock, with no key', () async {
    expect(lab.keys.toSet(), ServiceKey.values.toSet());
    for (final MapEntry(key: service, value: url) in lab.entries) {
      expect(await knock(service, url), isTrue, reason: '$service at $url');
    }
  });

  test('no service with an answer of its own answers another\'s', () async {
    // Unraid's knock takes any answer and TrueNAS's any open port, so
    // only the services whose answer names them are crossed.
    final named = {
      for (final MapEntry(:key, :value) in lab.entries)
        if (key != ServiceKey.unraid && key != ServiceKey.truenas) key: value,
    };
    for (final service in named.keys) {
      for (final MapEntry(key: other, value: url) in named.entries) {
        if (other == service) continue;
        // The arrs and Bazarr share their ping, by design of the arrs: a
        // knock proves an arr is there, the key proves which.
        if (_pings.contains(service) && _pings.contains(other)) continue;
        expect(
          await knock(service, url),
          isFalse,
          reason: '$service knocked at $other\'s $url',
        );
      }
    }
  });

  test('a port nobody listens on is not an answer', () async {
    expect(await knock(ServiceKey.radarr, 'http://127.0.0.1:1'), isFalse);
  });
}

const _pings = {
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.readarr,
  ServiceKey.prowlarr,
  ServiceKey.bazarr,
};
