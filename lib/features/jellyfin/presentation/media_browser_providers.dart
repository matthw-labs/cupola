import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/jellyfin/data/media_browser_client.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/settings/data/connection_providers.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// Every provider a MediaBrowser server (Jellyfin, and Emby beside it) has,
/// built once from the service and the way its client is constructed.
///
/// A set per service rather than a copy of this file per service: the
/// providers are ~300 lines of lens, family and collapse rules that must stay
/// identical, and two hand-kept copies drift. Each service declares its set
/// once and aliases every field under the name callers and tests already use
/// (`final jellyfinSessionsProvider = jellyfinProviders.sessions;`), because
/// the identity of a provider is the key of its overrides and of its cache:
/// the set is built **once**, never by a getter, and never as a family keyed
/// by [ServiceKey], which would break `overrideWith` on the plain names.
///
/// The `For` families collapse onto their lens provider when the connection
/// is the empty id or the one the lens is on, so an override of either still
/// reaches both and the app keeps one live `Dio` per connection.
class MediaBrowserProviders<C extends MediaBrowserClient> {
  /// [create] is the one place a service's client is constructed, which is
  /// where ADR-6 wants it: it must hand the client the transport's pin, access
  /// headers and `onlyAtHome` (`test/core/network/access_headers_guard_test.dart`
  /// and `route_reach_guard_test.dart` read it there). [viewerId] is the
  /// household member chosen on this connection, or empty.
  MediaBrowserProviders(
    this.service, {
    required C Function(ServiceTransport transport, String viewerId) create,
  }) : _create = create;

  /// The service these providers belong to.
  final ServiceKey service;

  final C Function(ServiceTransport transport, String viewerId) _create;

  /// The client of the lens, and of a named connection.
  late final ConnectionProviders<C> client = ConnectionProviders<C>.transport(
    service,
    create: (ref, transport) {
      // The viewer is read from the **instance**, not from
      // `settings.jellyfinUserId`: that projection is the first
      // connection's, so following the lens without this would have every
      // user-scoped query on the second server carry a user id from the
      // first server's user table, an id that does not exist there.
      final viewerId = ref.watch(
        currentSettingsProvider.select(
          (s) => s.instanceById(transport.instanceId)?.viewerId ?? '',
        ),
      );
      return _create(transport, viewerId);
    },
    close: (client) => client.close(),
  );

  /// The lens's client, seen through the interface the Stream surfaces are
  /// written against.
  late final Provider<StreamServerClient> server = Provider<StreamServerClient>(
    (ref) => ref.watch(client.lens),
  );

  late final FutureProvider<List<StreamSession>> sessions = FutureProvider(
    (ref) async => ref.watch(server).getSessions(),
    // `noProviderRetry`, because `streamActivityProvider` awaits this inside a
    // `try` written to carry on without a dark server, and it walks the media
    // servers one at a time, so ten backing-off retries here are spent before
    // Plex is even asked. See [noProviderRetry].
    retry: noProviderRetry,
  );

  late final FutureProvider<List<StreamLibrary>> libraries = FutureProvider(
    (ref) async => ref.watch(server).getLibraries(),
    retry: noProviderRetry,
  );

  late final strictLibraries = FutureProvider<List<StreamLibrary>>(
    (ref) => ref.watch(client.lens).getLibrariesOrThrow(),
    retry: noProviderRetry,
  );

  late final serverId = FutureProvider.autoDispose.family<String?, String>(
    (ref, instanceId) async =>
        ref.watch(client.forConnection(instanceId)).publicServerId(),
    retry: noProviderRetry,
  );

  late final viewersFor = FutureProvider.family<List<StreamViewer>, String>(
    (ref, instanceId) async =>
        ref.watch(client.forConnection(instanceId)).getViewers(),
    retry: noProviderRetry,
  );

  late final item = FutureProvider.autoDispose.family<StreamItem?, String>((
    ref,
    itemId,
  ) async {
    final stream = ref.watch(server);
    final cancelToken = CancelToken();
    ref.onDispose(cancelToken.cancel);
    return stream.getItem(itemId, cancelToken: cancelToken);
  }, retry: noProviderRetry);

  late final itemChildren = FutureProvider.autoDispose
      .family<List<StreamItem>, String>((ref, itemId) async {
        final stream = ref.watch(server);
        final cancelToken = CancelToken();
        ref.onDispose(cancelToken.cancel);
        return stream.getChildren(itemId, cancelToken: cancelToken);
      }, retry: noProviderRetry);

  late final FutureProvider<JellyfinCredentialKind> credentialKind =
      FutureProvider(
        (ref) => ref.watch(client.lens).getCredentialKind(),
        retry: noProviderRetry,
      );

  late final credentialKindFor =
      FutureProvider.family<JellyfinCredentialKind, String>((
        ref,
        instanceId,
      ) async {
        final lens = ref.watch(activeInstanceProvider(service))?.id ?? '';
        if (instanceId.isEmpty || instanceId == lens) {
          return ref.watch(credentialKind.future);
        }
        return ref.watch(client.forConnection(instanceId)).getCredentialKind();
      }, retry: noProviderRetry);

  late final Provider<bool> lacksAdministrator = Provider<bool>(
    (ref) =>
        ref.watch(credentialKind).asData?.value.lacksAdministrator ?? false,
  );

  late final lacksAdministratorFor = Provider.family<bool, String>((
    ref,
    instanceId,
  ) {
    final lens = ref.watch(activeInstanceProvider(service))?.id ?? '';
    if (instanceId.isEmpty || instanceId == lens) {
      return ref.watch(lacksAdministrator);
    }
    return ref
            .watch(credentialKindFor(instanceId))
            .asData
            ?.value
            .lacksAdministrator ??
        false;
  });

  late final FutureProvider<List<JellyfinUserDto>> users = FutureProvider(
    (ref) async => ref.watch(client.lens).getUsers(),
    retry: noProviderRetry,
  );

  late final FutureProvider<List<JellyfinDevice>> devices = FutureProvider(
    (ref) async => ref.watch(client.lens).getDevices(),
    retry: noProviderRetry,
  );

  late final FutureProvider<List<JellyfinScheduledTask>> tasks = FutureProvider(
    (ref) async => ref.watch(client.lens).getScheduledTasks(),
    retry: noProviderRetry,
  );

  late final usersFor = FutureProvider.family<List<JellyfinUserDto>, String>((
    ref,
    instanceId,
  ) async {
    final lens = ref.watch(activeInstanceProvider(service))?.id ?? '';
    if (instanceId.isEmpty || instanceId == lens) {
      return ref.watch(users.future);
    }
    return ref.watch(client.forConnection(instanceId)).getUsers();
  }, retry: noProviderRetry);

  late final devicesFor = FutureProvider.family<List<JellyfinDevice>, String>((
    ref,
    instanceId,
  ) async {
    final lens = ref.watch(activeInstanceProvider(service))?.id ?? '';
    if (instanceId.isEmpty || instanceId == lens) {
      return ref.watch(devices.future);
    }
    return ref.watch(client.forConnection(instanceId)).getDevices();
  }, retry: noProviderRetry);

  late final tasksFor =
      FutureProvider.family<List<JellyfinScheduledTask>, String>((
        ref,
        instanceId,
      ) async {
        final lens = ref.watch(activeInstanceProvider(service))?.id ?? '';
        if (instanceId.isEmpty || instanceId == lens) {
          return ref.watch(tasks.future);
        }
        return ref.watch(client.forConnection(instanceId)).getScheduledTasks();
      }, retry: noProviderRetry);
}
