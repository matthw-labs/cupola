import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/presentation/media_browser_providers.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

export 'package:cupola/features/jellyfin/presentation/media_browser_providers.dart';

/// Jellyfin's set. Every `jellyfin*Provider` below is a field of it, under the
/// name callers and tests override it by.
final jellyfinProviders = MediaBrowserProviders<JellyfinClient>(
  ServiceKey.jellyfin,
  create: (transport, viewerId) => JellyfinClient(
    baseUrl: transport.url,
    apiKey: transport.apiKey,
    userId: viewerId,
    pinnedCertFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
    onlyAtHome: transport.onlyAtHomeOf(ServiceKey.jellyfin),
  ),
);

/// The providers of a MediaBrowser [service], for a widget written once for
/// every server of the family (the Users, Devices, Tasks and Activity tabs,
/// the viewer picker). Throws for a service that is not one: a widget that
/// asks has been handed the wrong key, and an answer about some other server
/// would be worse than the throw.
MediaBrowserProviders<MediaBrowserClient> mediaBrowserProvidersOf(
  ServiceKey service,
) => switch (service) {
  ServiceKey.jellyfin => jellyfinProviders,
  ServiceKey.emby => embyProviders,
  _ => throw ArgumentError.value(
    service,
    'service',
    'is not a MediaBrowser server',
  ),
};

/// Jellyfin client bound to the current settings.
///
/// Throws if Jellyfin is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.jellyfin)` before reading. The throw
/// is a `ServiceNotConfigured`, which `AsyncValueWidget` answers with
/// `NotConfiguredPlaceholder` instead of an error.
///
/// Follows the **lens**, like every other service's client. It used to read the
/// flat `jellyfinUrl`/`jellyfinApiKey`/`jellyfinUserId` projections, which are
/// always the *first* connection, so a second Jellyfin could be configured,
/// probed and counted and never once read.
///
/// The chosen viewer is read here rather than passed per call, so picking a
/// different household member rebuilds this provider and invalidates every
/// dependent lens. That is why nothing downstream is keyed by viewer: the viewer
/// is part of *which client you are talking to*, not part of a query's identity.
/// It comes off the resolved instance for the same reason the address does:
/// two servers have two user tables.
///
/// `watchTransport`, not a bare `watch` of the whole `SettingsModel`, and that is
/// a correctness point rather than a micro-optimisation: this provider closes a
/// live `Dio` in `onDispose`, so rebuilding it cancels every in-flight Stream
/// request and invalidates every surface downstream. Watching the whole object
/// made a theme-mode toggle do exactly that.
final jellyfinClientProvider = jellyfinProviders.client.lens;

final jellyfinClientForProvider = jellyfinProviders.client.forConnection;

/// The same client, seen through the interface the Stream surfaces are written
/// against.
///
/// Widgets should depend on this one: nothing above the data layer has any
/// business knowing whether it is talking to Jellyfin or Plex, and a screen that
/// takes the interface can be reused for both, which is the entire point of
/// having it. `cancelToken` now lives on `StreamServerClient` itself, so even the
/// cancellable per-item fetches below go through here; the concrete provider
/// stays public only for the Jellyfin-specific extras (`getViewers` filtering,
/// the raw item mapper) that genuinely have no cross-server meaning.
final jellyfinServerProvider = jellyfinProviders.server;

/// Everything playing right now, most expensive first.
///
/// Not polled from here: the dashboard owns its own refresh cadence the way
/// `torrentDetailPollingProvider` does, and a timer buried in a data provider
/// would keep firing behind a screen nobody is looking at.
final jellyfinSessionsProvider = jellyfinProviders.sessions;

/// The libraries this server exposes.
///
/// `retry: noProviderRetry` from here down, for the reason
/// [jellyfinSessionsProvider] gives one step above: the default retry re-runs a
/// failed build ten times behind an exponential backoff and holds the future
/// until it has, so a server that has gone dark is a spinner for the better
/// part of a minute before any surface can say "unreachable" and offer the
/// Retry it already draws. (The "not configured" throw never needed the flag;
/// it reaches a watcher as a `ProviderException`, which `defaultRetry`
/// declines on its own.)
final jellyfinLibrariesProvider = jellyfinProviders.libraries;

/// The server's own id, per connection: what a Jellyfin app needs to open an
/// item on it. Null while the server does not say.
final jellyfinServerIdProvider = jellyfinProviders.serverId;

/// The same list, from one named connection.
///
/// What the settings picker reads: it is filling in a viewer for the connection
/// whose form is on screen, and a user id is only meaningful against the server
/// that issued it. Empty id means the lens, which is what every caller meant
/// before Jellyfin could have two.
final jellyfinViewersForProvider = jellyfinProviders.viewersFor;

/// One item at any depth, by id.
///
/// Resolves from the id alone so `ServiceRoutes.jellyfinItem` works as a deep
/// link; `state.extra` stays preload/Hero data only.
///
/// `autoDispose` for two reasons: every item ever opened would otherwise be
/// retained forever, and the cancellation would never fire.
final jellyfinItemProvider = jellyfinProviders.item;

/// The children of a series, season or album: seasons, episodes or tracks.
///
/// Empty for a leaf item, which the client answers without a request.
final jellyfinItemChildrenProvider = jellyfinProviders.itemChildren;

/// The libraries with the transport failure preserved, for the surfaces that
/// state a **figure** rather than draw a board (the KPI rail).
///
/// Written when `getLibraries()` still answered an unreachable server with
/// `const []`, wrong for a counter, where `0 libraries` is a claim nobody
/// made. A provider rather than a call the KPI layer makes on the client: it
/// caches, invalidates with everything else, and can be overridden by name.
/// The sessions had a twin of this too; it went once both reads threw, because
/// two caches of one sessions read let the figure and Now playing disagree.
final jellyfinStrictLibrariesProvider = jellyfinProviders.strictLibraries;

/// Which credential kind the lens connection's slot holds. Never fails: an
/// unanswered probe is [JellyfinCredentialKind.unknown].
///
/// `noProviderRetry`, because the tabs that read it wait on it before they
/// decide between their list and the administrator placeholder.
final jellyfinCredentialKindProvider = jellyfinProviders.credentialKind;

/// Which credential kind one named connection's slot holds.
///
/// A credential is a connection's, not the service's: the Jellyfin at home
/// can hold an API key while the one at the cabin holds a household member's
/// token, and the surfaces that read every connection (Activity, the
/// figures) have to ask each one. The lens's own id, and the empty id,
/// collapse onto [jellyfinCredentialKindProvider], so the lens's pages and
/// those surfaces share one `/Users/Me`.
///
/// Not part of the capability layer, on purpose: that layer describes the
/// writes a credential may make, and a non-administrator loses reads.
final jellyfinCredentialKindForProvider = jellyfinProviders.credentialKindFor;

/// Whether the elevated reads are known to be out of reach for the lens
/// connection. False while the probe is out and when it did not answer, so a
/// healthy administrator never sees the placeholder flash.
final jellyfinLacksAdministratorProvider = jellyfinProviders.lacksAdministrator;

/// [jellyfinLacksAdministratorProvider], for one named connection. Same rule:
/// false until `/Users/Me` has said the token is a non-administrator's.
///
/// The lens's own id, and the empty id, collapse onto the plain provider, so
/// an override of either still reaches both.
final jellyfinLacksAdministratorForProvider =
    jellyfinProviders.lacksAdministratorFor;

final jellyfinUsersProvider = jellyfinProviders.users;

final jellyfinDevicesProvider = jellyfinProviders.devices;

final jellyfinTasksProvider = jellyfinProviders.tasks;

/// [jellyfinUsersProvider] for one named connection; empty is the lens.
///
/// A visit that has a connection in view reads that connection's users on
/// every tab. The lens's own id collapses onto the plain provider, so an
/// override of either still reaches both, and so do the pages that read the
/// lens. `retry: noProviderRetry` for the reason the plain one carries it.
final jellyfinUsersForProvider = jellyfinProviders.usersFor;

/// [jellyfinDevicesProvider] for one named connection; empty is the lens. See
/// [jellyfinUsersForProvider].
final jellyfinDevicesForProvider = jellyfinProviders.devicesFor;

/// [jellyfinTasksProvider] for one named connection; empty is the lens. See
/// [jellyfinUsersForProvider].
final jellyfinTasksForProvider = jellyfinProviders.tasksFor;
