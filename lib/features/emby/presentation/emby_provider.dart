import 'package:cupola/features/emby/data/emby_client.dart';
import 'package:cupola/features/jellyfin/presentation/media_browser_providers.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Emby's set of providers: the same ones Jellyfin has, built from one
/// [MediaBrowserProviders] with Emby's client.
///
/// Every `emby*Provider` below is a field of it, under the name callers and
/// tests override it by, exactly as `jellyfin_provider.dart` does for Jellyfin.
/// This is the one place an Emby client is constructed, so the transport's
/// pin, access headers and `onlyAtHome` reach it here.
final embyProviders = MediaBrowserProviders<EmbyClient>(
  ServiceKey.emby,
  create: (transport, viewerId) => EmbyClient(
    baseUrl: transport.url,
    apiKey: transport.apiKey,
    userId: viewerId,
    pinnedCertFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
    onlyAtHome: transport.onlyAtHomeOf(ServiceKey.emby),
  ),
);

/// The Emby client bound to the lens connection. See `jellyfinClientProvider`
/// for why the viewer is part of *which client you are talking to*.
final embyClientProvider = embyProviders.client.lens;

final embyClientForProvider = embyProviders.client.forConnection;

/// The lens's client, through the interface the Stream surfaces share.
final embyServerProvider = embyProviders.server;

/// Everything playing right now, most expensive first. Not polled from here.
final embySessionsProvider = embyProviders.sessions;

/// The libraries this server exposes.
final embyLibrariesProvider = embyProviders.libraries;

/// The server's own id, per connection: what an app needs to open an item.
final embyServerIdProvider = embyProviders.serverId;

/// The users of one named connection, for the viewer picker.
final embyViewersForProvider = embyProviders.viewersFor;

/// One item at any depth, by id.
final embyItemProvider = embyProviders.item;

/// The children of a series, season or album.
final embyItemChildrenProvider = embyProviders.itemChildren;

/// The libraries with the transport failure preserved, for the figures.
final embyStrictLibrariesProvider = embyProviders.strictLibraries;

/// Which credential kind the lens connection's slot holds.
final embyCredentialKindProvider = embyProviders.credentialKind;

/// [embyCredentialKindProvider], for one named connection.
final embyCredentialKindForProvider = embyProviders.credentialKindFor;

/// Whether the elevated reads are known to be out of reach for the lens.
final embyLacksAdministratorProvider = embyProviders.lacksAdministrator;

/// [embyLacksAdministratorProvider], for one named connection.
final embyLacksAdministratorForProvider = embyProviders.lacksAdministratorFor;

final embyUsersProvider = embyProviders.users;

final embyDevicesProvider = embyProviders.devices;

final embyTasksProvider = embyProviders.tasks;

final embyUsersForProvider = embyProviders.usersFor;

final embyDevicesForProvider = embyProviders.devicesFor;

final embyTasksForProvider = embyProviders.tasksFor;
