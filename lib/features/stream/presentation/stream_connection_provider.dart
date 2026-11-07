import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/services/presentation/connection_in_view.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

/// The connection a media server page was asked to read, from its route's
/// `?i=`.
///
/// Empty is the service's active connection: an old link, a deep link, a page
/// opened from somewhere that does not know a connection. A value that names
/// no connection of [service] (removed since the link was made, or another
/// service's) is empty too, so a stale link opens on the active connection
/// rather than on an error about a connection that no longer exists.
String streamInstanceFor(
  SettingsModel settings,
  ServiceKey service,
  String? requested,
) => namedConnectionOf(settings, service, requested);

/// The connection a media server page reads, for a widget's build.
///
/// Two inputs and an order between them, which is the page's to choose:
///
///  * [requested], the page's own `?i=`;
///  * the connection the visit to [service] has in view ([ConnectionInView]:
///    what a link opened the service on, or what the lens sheet last chose).
///
/// A page that is **one connection's** (a library, an item) is [pinned], the
/// default: its own `?i=` leads, because it says whose library or item this
/// is, and the visit decides only for a page that names none. A tab's root is
/// not: the `?i=` it carries is the location it was opened from, which a tab
/// restores as it was left, query included. That link was read by the visit
/// when it arrived, so the visit leads and a connection chosen in the lens
/// sheet since is not undone by switching back to the tab. Neither: the
/// lens, empty.
String streamInstanceOf(
  WidgetRef ref,
  ServiceKey service,
  String? requested, {
  bool pinned = true,
}) => _streamInstance(
  ref.watch(currentSettingsProvider),
  service,
  requested,
  ConnectionInView.maybeOf(ref.context, service)?.instanceId,
  pinned,
);

/// [streamInstanceOf] for an event handler or a fetch: the same answer, read
/// once and without registering a dependency.
String streamInstanceNow(
  WidgetRef ref,
  ServiceKey service,
  String? requested, {
  bool pinned = true,
}) => _streamInstance(
  ref.read(currentSettingsProvider),
  service,
  requested,
  ConnectionInView.maybeOf(ref.context, service, listen: false)?.instanceId,
  pinned,
);

String _streamInstance(
  SettingsModel settings,
  ServiceKey service,
  String? requested,
  String? inView,
  bool pinned,
) {
  final named = streamInstanceFor(settings, service, requested);
  final visit = streamInstanceFor(settings, service, inView);
  final order = pinned ? [named, visit] : [visit, named];
  return order.firstWhere((id) => id.isNotEmpty, orElse: () => '');
}

/// The id of the connection [instanceId] stands for: itself, or the lens's
/// when it is empty. For what needs a connection to name, such as the form
/// that edits it. Empty only when the service has no connection at all.
String streamConnectionIdOf(
  WidgetRef ref,
  ServiceKey service,
  String instanceId,
) => instanceId.isNotEmpty
    ? instanceId
    : ref.watch(activeInstanceProvider(service))?.id ?? '';

/// A media server's client for one named connection; empty is the active one.
///
/// The active connection's own id collapses onto the service's lens client
/// ([StreamBackend.lensClient]: `jellyfinServerProvider`, `plexServerProvider`),
/// so a page opened without `?i=` and one opened with the active connection's
/// id read one client, and an override of either still reaches both. Every
/// other connection takes its own client, which takes its address, access and
/// certificate pin from that connection's route (`watchTransport`).
final streamClientForProvider =
    Provider.family<StreamServerClient, StreamConnection>((ref, key) {
      final backend = streamBackendOf(key.service);
      final lens = ref.watch(activeInstanceProvider(key.service))?.id ?? '';
      if (key.instanceId.isEmpty || key.instanceId == lens) {
        return ref.watch(backend.lensClient);
      }
      return ref.watch(backend.clientFor(key.instanceId));
    });

/// The libraries of one named connection of a media server; empty is the
/// active one.
///
/// The lens's own connection collapses onto the service's libraries provider
/// ([StreamBackend.libraries]), so the Overview, the Libraries tab and anything
/// an override of it reaches read one answer. Every other connection asks its
/// own client. `retry: noProviderRetry`, like the providers it derives from: a
/// dark server is a Retry, not a spinner held through ten attempts.
final streamLibrariesForProvider =
    FutureProvider.family<List<StreamLibrary>, StreamConnection>((
      ref,
      key,
    ) async {
      final backend = streamBackendOf(key.service);
      final lens = ref.watch(activeInstanceProvider(key.service))?.id ?? '';
      if (key.instanceId.isEmpty || key.instanceId == lens) {
        return ref.watch(backend.libraries.future);
      }
      final client = ref.watch(backend.clientFor(key.instanceId));
      return client.getLibraries();
    }, retry: noProviderRetry);

/// One item on one connection, and where it is looked up.
typedef StreamItemKey = ({
  ServiceKey service,
  String instanceId,
  String itemId,
});

/// One item at any depth, read from the connection [StreamItemKey.instanceId]
/// names, the active one when empty.
final streamItemForProvider = FutureProvider.autoDispose
    .family<StreamItem?, StreamItemKey>((ref, key) {
      final backend = streamBackendOf(key.service);
      final lens = ref.watch(activeInstanceProvider(key.service))?.id ?? '';
      if (key.instanceId.isEmpty || key.instanceId == lens) {
        return ref.watch(backend.item(key.itemId).future);
      }
      final client = ref.watch(
        streamClientForProvider((
          service: key.service,
          instanceId: key.instanceId,
        )),
      );
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return client.getItem(key.itemId, cancelToken: cancelToken);
    }, retry: noProviderRetry);

/// How many titles one library holds, in the unit it browses in, on the
/// connection [StreamItemKey.instanceId] names ([StreamItemKey.itemId] is the
/// library's id). Null when the server did not say: never a count of nothing.
final streamLibraryItemCountProvider = FutureProvider.autoDispose
    .family<int?, StreamItemKey>((ref, key) {
      final client = ref.watch(
        streamClientForProvider((
          service: key.service,
          instanceId: key.instanceId,
        )),
      );
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return client.getLibraryItemCount(key.itemId, cancelToken: cancelToken);
    }, retry: noProviderRetry);

/// What is inside one item (seasons, episodes, tracks), read like
/// [streamItemForProvider].
final streamChildrenForProvider = FutureProvider.autoDispose
    .family<List<StreamItem>, StreamItemKey>((ref, key) {
      final backend = streamBackendOf(key.service);
      final lens = ref.watch(activeInstanceProvider(key.service))?.id ?? '';
      if (key.instanceId.isEmpty || key.instanceId == lens) {
        return ref.watch(backend.children(key.itemId).future);
      }
      final client = ref.watch(
        streamClientForProvider((
          service: key.service,
          instanceId: key.instanceId,
        )),
      );
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return client.getChildren(key.itemId, cancelToken: cancelToken);
    }, retry: noProviderRetry);

/// Re-reads the playbacks of one connection: its own read and, when it is the
/// active one, the cache the service's other pages share.
void refreshStreamSessions(
  WidgetRef ref,
  ServiceKey service,
  String instanceId,
) {
  ref.invalidate(
    streamSessionsForProvider((service: service, instanceId: instanceId)),
  );
  ref.invalidate(streamBackendOf(service).sessions);
}

/// Asks again for one item: its own read and the active connection's cache
/// it collapses onto.
void refreshStreamItem(WidgetRef ref, StreamItemKey key) {
  ref.invalidate(streamItemForProvider(key));
  ref.invalidate(streamBackendOf(key.service).item(key.itemId));
}

/// Asks again for what is inside one item, like [refreshStreamItem].
void refreshStreamChildren(WidgetRef ref, StreamItemKey key) {
  ref.invalidate(streamChildrenForProvider(key));
  ref.invalidate(streamBackendOf(key.service).children(key.itemId));
}
