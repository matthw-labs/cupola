/// What every tab of a media server reads, for one named connection.
///
/// A visit that has a connection in view reads it on every tab, so each read a
/// tab makes has a family keyed by connection. Two properties hold for all of
/// them: the lens's own connection (and the empty id) collapse onto the plain
/// provider, so an override of either reaches both and the pages that read the
/// lens share one answer; and every other connection asks its own client, and
/// a dark one fails at once, with no backoff held in front of the failure.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'package:cupola/features/stream/presentation/stream_watching.dart';

import '../../test_helpers/profiles/profiles.dart';

final _twoJellyfin = Profiles.p1.withConnection(WorldConnections.jellyfinCabin);
final _twoPlex = Profiles.p1
    .withConnection(WorldConnections.plex)
    .withConnection(WorldConnections.plexCabin);

/// One read: the plain provider's override, the family's read for a
/// connection, and the path the connection's own server is asked at.
class _Read {
  _Read(
    this.name, {
    required this.marker,
    required this.overridePlain,
    required this.family,
    required this.path,
  });

  final String name;

  /// What the plain provider is overridden to answer: the same instance must
  /// come back from the family for the lens.
  final Object marker;
  final Override Function(Object marker) overridePlain;
  final Future<Object> Function(ProviderContainer container, String instanceId)
  family;

  /// What the connection's own server is asked for.
  final String path;
}

void main() {
  group('Jellyfin', () {
    final reads = <_Read>[
      _Read(
        'users',
        marker: <JellyfinUserDto>[],
        overridePlain: (marker) => jellyfinUsersProvider.overrideWith(
          (ref) async => marker as List<JellyfinUserDto>,
        ),
        family: (c, id) => c.read(jellyfinUsersForProvider(id).future),
        path: '/Users',
      ),
      _Read(
        'devices',
        marker: <JellyfinDevice>[],
        overridePlain: (marker) => jellyfinDevicesProvider.overrideWith(
          (ref) async => marker as List<JellyfinDevice>,
        ),
        family: (c, id) => c.read(jellyfinDevicesForProvider(id).future),
        path: '/Devices',
      ),
      _Read(
        'tasks',
        marker: <JellyfinScheduledTask>[],
        overridePlain: (marker) => jellyfinTasksProvider.overrideWith(
          (ref) async => marker as List<JellyfinScheduledTask>,
        ),
        family: (c, id) => c.read(jellyfinTasksForProvider(id).future),
        path: '/ScheduledTasks',
      ),
      _Read(
        'libraries',
        marker: <StreamLibrary>[],
        overridePlain: (marker) => jellyfinLibrariesProvider.overrideWith(
          (ref) async => marker as List<StreamLibrary>,
        ),
        family: (c, id) => c.read(
          streamLibrariesForProvider((
            service: ServiceKey.jellyfin,
            instanceId: id,
          )).future,
        ),
        path: '/Library/VirtualFolders',
      ),
    ];

    for (final read in reads) {
      test('${read.name}: the lens and the empty id are the plain provider\'s '
          'answer, the cabin is asked for its own', () async {
        final harness = await ProfileHarness.start(
          _twoJellyfin,
          overrides: [read.overridePlain(read.marker)],
        );
        final container = harness.container();

        expect(await read.family(container, ''), same(read.marker));
        expect(
          await read.family(container, WorldIds.jellyfin),
          same(read.marker),
        );
        expect(harness.network.requestsTo(WorldIds.jellyfin), isEmpty);

        await read.family(container, WorldIds.jellyfinCabin);
        expect(
          harness.network.requestsTo(WorldIds.jellyfinCabin).map((r) => r.path),
          contains(read.path),
        );
      });

      test('${read.name}: a dark connection fails at once', () async {
        final harness = await ProfileHarness.start(
          _twoJellyfin.withBehaviour(
            WorldIds.jellyfinCabin,
            ConnectionBehaviour.didNotAnswer,
          ),
        );
        // The app's own retry policy: a read that carried no
        // `noProviderRetry` would sit behind its backoff and time out here.
        final container = harness.container();

        await expectLater(
          read
              .family(container, WorldIds.jellyfinCabin)
              .timeout(const Duration(milliseconds: 500)),
          throwsA(isNot(isA<TimeoutException>())),
        );
      });
    }

    test('whether the credential is an administrator\'s is the connection\'s, '
        'and the lens collapses onto the plain answer', () async {
      final harness = await ProfileHarness.start(
        _twoJellyfin.withBehaviour(
          WorldIds.jellyfinCabin,
          ConnectionBehaviour.readOnly,
        ),
        overrides: [
          jellyfinLacksAdministratorProvider.overrideWithValue(false),
        ],
      );
      final container = harness.container();

      // The cabin's token is a household member's; home's is the plain
      // provider's, overridden.
      expect(
        container.read(jellyfinLacksAdministratorForProvider('')),
        isFalse,
      );
      expect(
        container.read(
          jellyfinLacksAdministratorForProvider(WorldIds.jellyfin),
        ),
        isFalse,
      );
      container.listen(
        jellyfinLacksAdministratorForProvider(WorldIds.jellyfinCabin),
        (_, _) {},
      );
      await container.read(
        jellyfinCredentialKindForProvider(WorldIds.jellyfinCabin).future,
      );
      expect(
        container.read(
          jellyfinLacksAdministratorForProvider(WorldIds.jellyfinCabin),
        ),
        isTrue,
      );
    });
  });

  group('Plex', () {
    final reads = <_Read>[
      _Read(
        'devices',
        marker: <PlexDevice>[],
        overridePlain: (marker) => plexDevicesProvider.overrideWith(
          (ref) async => marker as List<PlexDevice>,
        ),
        family: (c, id) => c.read(plexDevicesForProvider(id).future),
        path: '/devices',
      ),
      _Read(
        'playlists',
        marker: <PlexPlaylist>[],
        overridePlain: (marker) => plexPlaylistsProvider.overrideWith(
          (ref) async => marker as List<PlexPlaylist>,
        ),
        family: (c, id) => c.read(plexPlaylistsForProvider(id).future),
        path: '/playlists',
      ),
      _Read(
        'libraries',
        marker: <StreamLibrary>[],
        overridePlain: (marker) => plexLibrariesProvider.overrideWith(
          (ref) async => marker as List<StreamLibrary>,
        ),
        family: (c, id) => c.read(
          streamLibrariesForProvider((
            service: ServiceKey.plex,
            instanceId: id,
          )).future,
        ),
        path: '/library/sections',
      ),
    ];

    for (final read in reads) {
      test('${read.name}: the lens and the empty id are the plain provider\'s '
          'answer, the cabin is asked for its own', () async {
        final harness = await ProfileHarness.start(
          _twoPlex,
          overrides: [read.overridePlain(read.marker)],
        );
        final container = harness.container();
        expect(await read.family(container, ''), same(read.marker));
        expect(await read.family(container, WorldIds.plex), same(read.marker));
        expect(harness.network.requestsTo(WorldIds.plex), isEmpty);

        await read.family(container, WorldIds.plexCabin);
        expect(
          harness.network.requestsTo(WorldIds.plexCabin).map((r) => r.path),
          contains(read.path),
        );
      });

      test('${read.name}: a dark connection fails at once', () async {
        final harness = await ProfileHarness.start(
          _twoPlex.withBehaviour(
            WorldIds.plexCabin,
            ConnectionBehaviour.didNotAnswer,
          ),
        );
        final container = harness.container();
        await expectLater(
          read
              .family(container, WorldIds.plexCabin)
              .timeout(const Duration(milliseconds: 500)),
          throwsA(isNot(isA<TimeoutException>())),
        );
      });
    }

    test('on deck and what was added are asked of the connection named, '
        'and a dark one fails at once', () async {
      final harness = await ProfileHarness.start(_twoPlex);
      final container = harness.container();
      for (final shelf in streamWatchingShelvesOf(ServiceKey.plex)) {
        final key = (
          service: ServiceKey.plex,
          instanceId: WorldIds.plexCabin,
          shelf: shelf,
        );
        container.listen(streamWatchingProvider(key), (_, _) {});
        await container.read(streamWatchingProvider(key).future);
      }
      expect(
        harness.network.requestsTo(WorldIds.plexCabin).map((r) => r.path),
        containsAll(['/hubs/continueWatching', '/library/recentlyAdded']),
      );
      expect(harness.network.requestsTo(WorldIds.plex), isEmpty);

      final dark = await ProfileHarness.start(
        _twoPlex.withBehaviour(
          WorldIds.plexCabin,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      final darkContainer = dark.container();
      final key = (
        service: ServiceKey.plex,
        instanceId: WorldIds.plexCabin,
        shelf: StreamWatchingShelf.continueWatching,
      );
      darkContainer.listen(streamWatchingProvider(key), (_, _) {});
      await expectLater(
        darkContainer
            .read(streamWatchingProvider(key).future)
            .timeout(const Duration(milliseconds: 500)),
        throwsA(isNot(isA<TimeoutException>())),
      );
    });
  });
}
