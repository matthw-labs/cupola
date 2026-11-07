import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/settings/data/connection_providers.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/core/providers/provider_retry.dart';

/// Plex client bound to the current settings.
///
/// Throws if Plex is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.plex)` before reading. The throw is
/// a `ServiceNotConfigured`, which `AsyncValueWidget` answers with
/// `NotConfiguredPlaceholder` instead of an error.
///
/// Follows the **lens**. It used to read the flat `plexUrl`/`plexToken`
/// projections, which are always the *first* connection, so a second Plex could
/// be configured and never read.
///
/// `plexClientId` deliberately stays off the lens and is **shared by every Plex
/// connection**: it identifies this *install*, not any one server, so two
/// servers each see one device for this app. Minting a per-connection id is what
/// would litter the user's admin panel with a second device row, which is why
/// [SettingsModel.plexClientId] is not on `ServiceInstance` and why
/// `SettingsService` mints it exactly once.
///
/// `watchTransport` rather than a bare watch of the whole `SettingsModel`, for
/// the same reason `jellyfinClientProvider` does it: this provider closes a live
/// `Dio` in `onDispose`, so any rebuild kills in-flight requests and cascades an
/// invalidation through every Stream surface. Watching the whole settings object
/// meant a theme-mode toggle did that.
final plexClientProvider = _plex.lens;

final plexClientForProvider = _plex.forConnection;

final _plex = ConnectionProviders<PlexClient>.transport(
  ServiceKey.plex,
  create: (ref, transport) {
    final clientId = ref.watch(
      currentSettingsProvider.select((s) => s.plexClientId),
    );
    return PlexClient(
      url: transport.url,
      token: transport.apiKey,
      clientIdentifier: clientId,
      pinnedCertFingerprint: transport.pin,
      accessHeaders: transport.access.headers(),
      onlyAtHome: transport.onlyAtHomeOf(ServiceKey.plex),
    );
  },
  close: (client) => client.close(),
);

/// The same client, seen through the interface the Stream surfaces are written
/// against.
///
/// The Jellyfin side has always had this; Plex was missing it, which meant a
/// screen meant to serve both servers had to name one of them. Nothing above the
/// data layer should know which media server it is talking to: that is the whole
/// reason `StreamServerClient` exists.
final plexServerProvider = Provider<StreamServerClient>((ref) {
  return ref.watch(plexClientProvider);
});

/// `GET /`: friendly name, version, and the Plex Pass flag that decides whether
/// a "stop stream" affordance is offered at all.
final plexCapabilitiesProvider = FutureProvider<PlexServerCapabilities>((
  ref,
) async {
  return ref.watch(plexClientProvider).getCapabilities();
  // No automatic retry, for the reason [jellyfinLibrariesProvider] gives: the
  // default one holds the future through ten backing-off attempts, so a dark
  // Plex is a spinner rather than an unreachable band with a Retry on it.
}, retry: noProviderRetry);

/// The capability sheet of one named Plex connection.
///
/// The lens's is [plexCapabilitiesProvider], so the service's own pages and
/// Activity share one answer; another connection is asked on its own, because
/// Plex Pass and the owner's scope are per server.
final plexCapabilitiesForProvider =
    FutureProvider.family<PlexServerCapabilities, String>((
      ref,
      instanceId,
    ) async {
      final lens = ref.watch(activeInstanceProvider(ServiceKey.plex))?.id ?? '';
      if (instanceId.isEmpty || instanceId == lens) {
        return ref.watch(plexCapabilitiesProvider.future);
      }
      return ref.watch(plexClientForProvider(instanceId)).getCapabilities();
    }, retry: noProviderRetry);

/// Whether a playback on one Plex connection is offered a Stop: the one gate
/// every surface that draws Stop reads. Empty id is the lens.
///
/// Plex puts termination behind Plex Pass and answers a server without it
/// with a 401 that has nothing to do with the token, so a server that says it
/// has no Plex Pass gets no Stop: a control with no way to make it work. It
/// is [PlexServerCapabilities.canTerminateSessions] and nothing else, which
/// treats silence as available. Two populations depend on that: a session
/// drawn before the sheet has answered (a control that appears a beat later
/// reads as a glitch on a live list) and a build that never sends
/// `myPlexSubscription` (it would never get one). An unanswered sheet keeps
/// the control too, and a refused stop explains itself.
final plexStopOfferedProvider = Provider.family<bool, String>((
  ref,
  instanceId,
) {
  final capabilities = ref.watch(plexCapabilitiesForProvider(instanceId)).value;
  return capabilities?.canTerminateSessions ?? true;
});

/// Everything playing right now, most expensive first.
///
/// Not self-polling: the Stream board owns its own refresh cadence, and a timer
/// here would keep hitting `/status/sessions` while the user is three screens
/// away. `ref.invalidate(plexSessionsProvider)` is the refresh.
final plexSessionsProvider = FutureProvider<List<StreamSession>>((ref) async {
  return ref.watch(plexClientProvider).getSessions();
  // No automatic retry, for the reason [jellyfinSessionsProvider] gives.
}, retry: noProviderRetry);

/// The libraries ("sections") this server exposes.
final plexLibrariesProvider = FutureProvider<List<StreamLibrary>>((ref) async {
  return ref.watch(plexClientProvider).getLibraries();
}, retry: noProviderRetry);

/// One item at any depth: film, show, season, episode, album or track.
final plexItemProvider = FutureProvider.autoDispose.family<StreamItem?, String>(
  (ref, ratingKey) async {
    return ref.watch(plexClientProvider).getItem(ratingKey);
  },
  retry: noProviderRetry,
);

/// The children of a show, season or album.
final plexChildrenProvider = FutureProvider.autoDispose
    .family<List<StreamItem>, String>((ref, ratingKey) async {
      return ref.watch(plexClientProvider).getChildren(ratingKey);
    }, retry: noProviderRetry);

/// The libraries with the transport failure preserved, for the surfaces that
/// state a **figure** rather than draw a board (the KPI rail).
///
/// Written when `getLibraries()` still answered an unreachable server with
/// `const []`, wrong for a counter, where `0 libraries` is a claim nobody
/// made. A provider rather than a call the KPI layer makes on the client: it
/// caches, invalidates with everything else, and can be overridden by name.
/// The sessions had a twin of this too; it went once both reads threw, because
/// two caches of one sessions read let the figure and Now playing disagree.
final plexStrictLibrariesProvider = FutureProvider<List<StreamLibrary>>(
  (ref) => ref.watch(plexClientProvider).getLibrariesOrThrow(),
  retry: noProviderRetry,
);

final plexDevicesProvider = FutureProvider<List<PlexDevice>>((ref) async {
  return ref.watch(plexClientProvider).getDevices();
}, retry: noProviderRetry);

final plexPlaylistsProvider = FutureProvider<List<PlexPlaylist>>((ref) async {
  return ref.watch(plexClientProvider).getPlaylists();
}, retry: noProviderRetry);

/// [plexDevicesProvider] for one named connection; empty is the lens. The
/// lens's own id collapses onto the plain provider, so an override of either
/// still reaches both.
final plexDevicesForProvider = FutureProvider.family<List<PlexDevice>, String>((
  ref,
  instanceId,
) async {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.plex))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(plexDevicesProvider.future);
  }
  return ref.watch(plexClientForProvider(instanceId)).getDevices();
}, retry: noProviderRetry);

/// [plexPlaylistsProvider] for one named connection; empty is the lens. See
/// [plexOnDeckTabForProvider].
final plexPlaylistsForProvider =
    FutureProvider.family<List<PlexPlaylist>, String>((ref, instanceId) async {
      final lens = ref.watch(activeInstanceProvider(ServiceKey.plex))?.id ?? '';
      if (instanceId.isEmpty || instanceId == lens) {
        return ref.watch(plexPlaylistsProvider.future);
      }
      return ref.watch(plexClientForProvider(instanceId)).getPlaylists();
    }, retry: noProviderRetry);
