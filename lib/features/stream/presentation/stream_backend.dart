import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// The providers one media server answers through, named once.
///
/// The Stream surfaces read "the lens's own answer, or this connection's" for
/// a client, its libraries, its sessions, an item and an item's children. That
/// read used to be spelled `isJellyfin ? jellyfinXProvider : plexXProvider`
/// five times over, with Plex as the silent else, so a third media server
/// would have been handed Plex's providers without a single error. A site now
/// asks [streamBackendOf] and gets the pair for the service it holds, or an
/// error that names the service.
///
/// Every field is an **existing** named provider (`jellyfinSessionsProvider`,
/// `plexServerProvider`, ...), never a new one built here: tests override those
/// by name, and an override has to reach the family that collapses onto them.
typedef StreamBackend = ({
  /// The lens's client, through the interface the Stream surfaces share.
  Provider<StreamServerClient> lensClient,

  /// The client of one named connection (`ConnectionProviders.forConnection`).
  ProviderListenable<StreamServerClient> Function(String instanceId) clientFor,

  /// What is playing on the lens's connection.
  FutureProvider<List<StreamSession>> sessions,

  /// The libraries of the lens's connection.
  FutureProvider<List<StreamLibrary>> libraries,

  /// One item of the lens's connection.
  FutureProvider<StreamItem?> Function(String itemId) item,

  /// What is inside one item of the lens's connection.
  FutureProvider<List<StreamItem>> Function(String itemId) children,
});

final StreamBackend _jellyfinBackend = (
  lensClient: jellyfinServerProvider,
  clientFor: (id) => jellyfinClientForProvider(id),
  sessions: jellyfinSessionsProvider,
  libraries: jellyfinLibrariesProvider,
  item: (id) => jellyfinItemProvider(id),
  children: (id) => jellyfinItemChildrenProvider(id),
);

final StreamBackend _plexBackend = (
  lensClient: plexServerProvider,
  clientFor: (id) => plexClientForProvider(id),
  sessions: plexSessionsProvider,
  libraries: plexLibrariesProvider,
  item: (id) => plexItemProvider(id),
  children: (id) => plexChildrenProvider(id),
);

/// The backend of [service], a media server.
///
/// Throws [UnsupportedError] naming the service for anything that is not one,
/// so a service that shares the Stream band without holding libraries (it
/// answers [ServiceKeyExtension.isMediaServer] with false) fails where it is
/// asked for a media server's providers instead of reading another server's.
/// A media server that has no arm here fails the same way, and the guard test
/// over [mediaServers] is what names it before a user does.
StreamBackend streamBackendOf(ServiceKey service) {
  if (!service.isMediaServer) {
    throw UnsupportedError('${service.name} is not a media server');
  }
  return switch (service) {
    ServiceKey.jellyfin => _jellyfinBackend,
    ServiceKey.plex => _plexBackend,
    _ => throw UnsupportedError('${service.name} has no stream backend'),
  };
}
