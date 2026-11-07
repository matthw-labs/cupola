import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

import '../../test_helpers/settings_scope.dart';

/// The one table the Stream surfaces read a media server's providers from.
void main() {
  group('streamBackendOf', () {
    test('every media server has a backend, and no two share one', () {
      final sessions = <Object>{};
      for (final service in mediaServers) {
        final backend = streamBackendOf(service);
        expect(sessions.add(backend.sessions), isTrue, reason: service.name);
      }
    });

    test('Jellyfin and Plex answer through their own named providers', () {
      // Tests override these by name, and an override must reach the families
      // that collapse onto them.
      final jellyfin = streamBackendOf(ServiceKey.jellyfin);
      expect(jellyfin.sessions, same(jellyfinSessionsProvider));
      expect(jellyfin.libraries, same(jellyfinLibrariesProvider));
      expect(jellyfin.lensClient, same(jellyfinServerProvider));
      expect(jellyfin.item('a'), jellyfinItemProvider('a'));
      expect(jellyfin.children('a'), jellyfinItemChildrenProvider('a'));
      expect(jellyfin.clientFor('c'), jellyfinClientForProvider('c'));

      final plex = streamBackendOf(ServiceKey.plex);
      expect(plex.sessions, same(plexSessionsProvider));
      expect(plex.libraries, same(plexLibrariesProvider));
      expect(plex.lensClient, same(plexServerProvider));
      expect(plex.item('a'), plexItemProvider('a'));
      expect(plex.children('a'), plexChildrenProvider('a'));
      expect(plex.clientFor('c'), plexClientForProvider('c'));
    });

    test('a service that is no media server fails and names itself', () {
      for (final service in ServiceKey.values.where((s) => !s.isMediaServer)) {
        expect(
          () => streamBackendOf(service),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              contains(service.name),
            ),
          ),
          reason: service.name,
        );
      }
    });

    test('the sessions family asked for a service that is no media server '
        'fails, and is never answered by Plex', () async {
      final container = ProviderContainer(
        overrides: [
          ...await settingsScopeOverrides(),
          // What Plex would answer with, were it handed the question.
          plexSessionsProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);
      final key = (service: ServiceKey.radarr, instanceId: '');
      container.listen(streamSessionsForProvider(key), (_, _) {});
      await expectLater(
        container.read(streamSessionsForProvider(key).future),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
