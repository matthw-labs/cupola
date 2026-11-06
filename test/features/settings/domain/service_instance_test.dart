import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The storage keys every service already uses, copied verbatim from
/// `_serviceStorageKeys` in `settings_service.dart`.
///
/// Duplicated here on purpose: that map is private, and this is a tripwire
/// rather than a mirror. Its whole job is to fail when the two drift, because
/// the drift that matters is silent and unrecoverable: a credential written
/// under one key and looked for under another is a credential the user has to
/// go and paste again, and they will not be told why.
const _onDisk = <ServiceKey, ({String url, String secret, String? username})>{
  ServiceKey.seerr: (
    url: 'seerr_url',
    secret: 'secure_seerr_api_key',
    username: null,
  ),
  ServiceKey.radarr: (
    url: 'radarr_url',
    secret: 'secure_radarr_api_key',
    username: null,
  ),
  ServiceKey.sonarr: (
    url: 'sonarr_url',
    secret: 'secure_sonarr_api_key',
    username: null,
  ),
  ServiceKey.lidarr: (
    url: 'lidarr_url',
    secret: 'secure_lidarr_api_key',
    username: null,
  ),
  ServiceKey.qbittorrent: (
    url: 'qbittorrent_url',
    secret: 'secure_qbittorrent_password',
    username: 'qbittorrent_username',
  ),
  ServiceKey.transmission: (
    url: 'transmission_url',
    secret: 'secure_transmission_password',
    username: 'transmission_username',
  ),
  ServiceKey.nginxProxyManager: (
    url: 'npm_url',
    secret: 'secure_npm_password',
    username: 'npm_username',
  ),
  ServiceKey.bazarr: (
    url: 'bazarr_url',
    secret: 'secure_bazarr_api_key',
    username: null,
  ),
  ServiceKey.truenas: (
    url: 'truenas_url',
    secret: 'secure_truenas_api_key',
    username: null,
  ),
  ServiceKey.dockge: (
    url: 'dockge_url',
    secret: 'secure_dockge_password',
    username: 'dockge_username',
  ),
  ServiceKey.prowlarr: (
    url: 'prowlarr_url',
    secret: 'secure_prowlarr_api_key',
    username: null,
  ),
  ServiceKey.readarr: (
    url: 'readarr_url',
    secret: 'secure_readarr_api_key',
    username: null,
  ),
  ServiceKey.sabnzbd: (
    url: 'sabnzbd_url',
    secret: 'secure_sabnzbd_api_key',
    username: null,
  ),
  ServiceKey.nzbget: (
    url: 'nzbget_url',
    secret: 'secure_nzbget_password',
    username: 'nzbget_username',
  ),
  ServiceKey.unraid: (
    url: 'unraid_url',
    secret: 'secure_unraid_api_key',
    username: null,
  ),
  ServiceKey.jellyfin: (
    url: 'jellyfin_url',
    secret: 'secure_jellyfin_api_key',
    username: null,
  ),
  ServiceKey.plex: (
    url: 'plex_url',
    secret: 'secure_plex_token',
    username: null,
  ),
  ServiceKey.emby: (
    url: 'emby_url',
    secret: 'secure_emby_api_key',
    username: null,
  ),
};

ServiceInstance _primary(ServiceKey service) => ServiceInstance(
  id: ServiceInstance.primaryIdFor(service),
  service: service,
);

void main() {
  group('the first instance keeps the keys already on disk', () {
    test('the table covers every service, so nothing escapes the tripwire', () {
      expect(_onDisk.keys.toSet(), ServiceKey.values.toSet());
    });

    for (final service in ServiceKey.values) {
      test('${service.name}: url, secret and username all reproduce', () {
        final expected = _onDisk[service]!;
        final instance = _primary(service);

        expect(instance.urlStorageKey, expected.url);
        expect(instance.credentialStorageKey, expected.secret);

        // The username key is only read for the services that have one, but it
        // has to be right for those: NZBGet already shipped once with a
        // username that persisted correctly and was rendered by no screen.
        if (expected.username != null) {
          expect(instance.usernameStorageKey, expected.username);
        }
      });
    }

    test('Jellyfin keeps the viewer key it already writes', () {
      expect(
        _primary(ServiceKey.jellyfin).viewerIdStorageKey,
        'jellyfin_user_id',
      );
    });

    test('Emby files its viewer where the storage table says', () {
      expect(_primary(ServiceKey.emby).viewerIdStorageKey, 'emby_user_id');
    });

    test('a second instance never lands on the first one\'s keys', () {
      final first = _primary(ServiceKey.radarr);
      final second = ServiceInstance(
        id: ServiceInstance.mintId(ServiceKey.radarr, [first.id]),
        service: ServiceKey.radarr,
        label: '4K',
      );

      expect(second.id, isNot(first.id));
      expect(second.urlStorageKey, isNot(first.urlStorageKey));
      expect(second.credentialStorageKey, isNot(first.credentialStorageKey));
      expect(second.credentialStorageKey, startsWith('secure_radarr-'));
      expect(second.credentialStorageKey, endsWith('_api_key'));
    });
  });

  group('mintId', () {
    test('hands out the primary id first', () {
      for (final service in ServiceKey.values) {
        expect(ServiceInstance.mintId(service, const []), service.routeParam);
      }
    });

    test('suffixes once the primary is taken, and never collides', () {
      final taken = <String>{ServiceInstance.primaryIdFor(ServiceKey.radarr)};
      final rng = Random(7);

      for (var i = 0; i < 50; i++) {
        final id = ServiceInstance.mintId(
          ServiceKey.radarr,
          taken,
          random: rng,
        );
        expect(taken.contains(id), isFalse, reason: 'collided on round $i');
        expect(id, startsWith('radarr-'));
        taken.add(id);
      }
      expect(taken, hasLength(51));
    });

    test('a second service is unaffected by the first one being taken', () {
      final taken = [ServiceInstance.primaryIdFor(ServiceKey.radarr)];
      expect(ServiceInstance.mintId(ServiceKey.sonarr, taken), 'sonarr');
    });
  });

  group('isPrimarySlot', () {
    test('is true only for the id that predates the multi-instance model', () {
      expect(_primary(ServiceKey.radarr).isPrimarySlot, isTrue);
      expect(
        const ServiceInstance(
          id: 'radarr-a1b2c3d',
          service: ServiceKey.radarr,
        ).isPrimarySlot,
        isFalse,
      );
    });

    test('follows routeParam, not the enum name, for the one that differs', () {
      // `nginxProxyManager` is the only camelCase enum name, and `npm_*` is
      // what is on disk. Deriving from `name` here would orphan the key.
      final npm = _primary(ServiceKey.nginxProxyManager);
      expect(npm.id, 'npm');
      expect(npm.isPrimarySlot, isTrue);
    });
  });

  group('isConfigured', () {
    test('an API-key service needs both halves', () {
      const bare = ServiceInstance(
        id: 'radarr',
        service: ServiceKey.radarr,
        url: 'http://nas:7878',
      );
      expect(bare.isConfigured, isFalse);
      expect(bare.copyWith(credential: 'k').isConfigured, isTrue);
    });

    test('a credential service is configured on the address alone', () {
      // Legitimately unauthenticated behind a reverse proxy.
      const qb = ServiceInstance(
        id: 'qbittorrent',
        service: ServiceKey.qbittorrent,
        url: 'http://nas:8080',
      );
      expect(qb.isConfigured, isTrue);
    });

    test('an empty address is never configured, whatever the auth', () {
      for (final service in ServiceKey.values) {
        expect(
          ServiceInstance(
            id: ServiceInstance.primaryIdFor(service),
            service: service,
            credential: 'k',
          ).isConfigured,
          isFalse,
          reason: '${service.name} claimed to be configured with no address',
        );
      }
    });
  });

  group('displayTitle', () {
    test('is the bare service name while there is only one', () {
      expect(_primary(ServiceKey.radarr).displayTitle, 'Radarr');
    });

    test('joins the label once there is one to tell apart', () {
      expect(
        _primary(ServiceKey.radarr).copyWith(label: '4K').displayTitle,
        'Radarr\u00A0· 4K',
      );
    });
  });

  group('credentialStorageSuffix', () {
    test('matches how the service names its own secret', () {
      expect(ServiceKey.plex.credentialStorageSuffix, 'token');
      expect(ServiceKey.qbittorrent.credentialStorageSuffix, 'password');
      expect(ServiceKey.radarr.credentialStorageSuffix, 'api_key');
    });

    test('every credential-authenticated service files a password', () {
      for (final service in ServiceKey.values.where((s) => !s.usesApiKey)) {
        expect(
          service.credentialStorageSuffix,
          'password',
          reason: '${service.name} authenticates on a pair',
        );
      }
    });

    test('is one of the three words already on disk, and nothing else', () {
      for (final service in ServiceKey.values) {
        expect(
          service.credentialStorageSuffix,
          anyOf('api_key', 'password', 'token'),
          reason: '${service.name} invented a fourth filing word',
        );
      }
    });
  });

  test('copyWith cannot change identity', () {
    final original = _primary(ServiceKey.radarr).copyWith(url: 'http://a');
    final edited = original.copyWith(url: 'http://b', label: '4K');

    expect(edited.id, original.id);
    expect(edited.service, original.service);
    expect(edited.url, 'http://b');
    expect(edited.label, '4K');
  });
}
