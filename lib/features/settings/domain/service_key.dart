import 'package:flutter/material.dart';

import 'package:cupola/core/service_glyphs.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_version.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

enum ServiceKey {
  seerr,
  radarr,
  sonarr,
  lidarr,
  qbittorrent,
  transmission,
  bazarr,
  truenas,
  dockge,
  prowlarr,
  readarr,
  sabnzbd,
  nzbget,
  unraid,
  nginxProxyManager,
  jellyfin,
  plex,
  emby,
  tracearr,
}

/// High-level grouping used to organise services across the app.
///
/// Cupola started as a media companion but is growing into a homelab hub, so
/// services are grouped by the kind of job they do. This enum is the single
/// source of truth for that grouping: the Home dashboard, Settings and the
/// onboarding flow all read from it, so a new service only needs a [domain]
/// assignment in one place.
enum ServiceDomain {
  media(label: 'Media'),
  downloads(label: 'Downloads'),

  /// Media servers: the only services in the app that know about *people*.
  ///
  /// Every other domain answers questions about objects: is this film owned,
  /// grabbed, subtitled, on disk. A media server is the only source of
  /// subject-and-time state: who is watching, where they stopped, what is next
  /// for them, what nobody has played. That is why this is its own domain and
  /// not more Media, and it is the guard against re-rendering Radarr's library
  /// under a second name.
  ///
  /// Ordered between [downloads] and [infrastructure] deliberately: the bands
  /// then read as the pipeline they are: catalogue, acquire, watch, and the box
  /// it all runs on.
  stream(label: 'Stream'),
  infrastructure(label: 'Infrastructure');

  const ServiceDomain({required this.label});

  final String label;

  /// The configured services belonging to this domain, in declaration order.
  List<ServiceKey> get services =>
      ServiceKey.values.where((s) => s.domain == this).toList(growable: false);
}

extension ServiceKeyExtension on ServiceKey {
  /// Which [ServiceDomain] this service belongs to. See [ServiceDomain].
  ServiceDomain get domain => switch (this) {
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.bazarr ||
    ServiceKey.readarr => ServiceDomain.media,
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget => ServiceDomain.downloads,
    ServiceKey.jellyfin ||
    ServiceKey.plex ||
    ServiceKey.emby ||
    ServiceKey.tracearr => ServiceDomain.stream,
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.unraid ||
    // A reverse proxy is not a download client that happens to run on the
    // box: it is the box's front door. Every other service in the app is
    // usually reached *through* it, which is exactly why it belongs beside
    // the NAS and the container manager rather than anywhere else.
    ServiceKey.nginxProxyManager => ServiceDomain.infrastructure,
  };

  /// Whether tapping this service opens a full multi-screen console (with its
  /// own inner navigation) rather than a single detail screen. Heavy services
  /// like TrueNAS and Dockge are effectively sub-apps.
  bool get isFullConsole =>
      this == ServiceKey.truenas || this == ServiceKey.dockge;

  /// The name where a half-width tile has room for about a dozen letters:
  /// the Stack's cells. The full [title] everywhere else, and always for a
  /// screen reader, which has no width to run out of.
  String get shortTitle => switch (this) {
    ServiceKey.nginxProxyManager => 'Proxy Manager',
    _ => title,
  };

  String get title => switch (this) {
    ServiceKey.seerr => 'Seerr',
    ServiceKey.radarr => 'Radarr',
    ServiceKey.sonarr => 'Sonarr',
    ServiceKey.lidarr => 'Lidarr',
    ServiceKey.qbittorrent => 'qBittorrent',
    ServiceKey.transmission => 'Transmission',
    ServiceKey.nginxProxyManager => 'Nginx Proxy Manager',
    ServiceKey.bazarr => 'Bazarr',
    ServiceKey.truenas => 'TrueNAS',
    ServiceKey.dockge => 'Dockge',
    ServiceKey.prowlarr => 'Prowlarr',
    ServiceKey.readarr => 'Readarr',
    ServiceKey.sabnzbd => 'SABnzbd',
    ServiceKey.nzbget => 'NZBGet',
    ServiceKey.unraid => 'Unraid',
    ServiceKey.jellyfin => 'Jellyfin',
    ServiceKey.plex => 'Plex',
    ServiceKey.emby => 'Emby',
    ServiceKey.tracearr => 'Tracearr',
  };

  /// What the service is for, in a word or two: the line under "Set up X"
  /// where someone choosing where to start reads the list by role.
  String get role => switch (this) {
    ServiceKey.seerr => 'Requests',
    ServiceKey.radarr => 'Movies',
    ServiceKey.sonarr => 'Series',
    ServiceKey.lidarr => 'Music',
    ServiceKey.bazarr => 'Subtitles',
    ServiceKey.readarr => 'Books\u00A0· no longer maintained upstream',
    ServiceKey.prowlarr => 'Indexers',
    ServiceKey.qbittorrent || ServiceKey.transmission => 'Torrent client',
    ServiceKey.sabnzbd || ServiceKey.nzbget => 'Usenet client',
    ServiceKey.jellyfin || ServiceKey.plex || ServiceKey.emby => 'Streaming',
    // It watches the media servers rather than serving media: the word is the
    // one Tracearr uses of itself.
    ServiceKey.tracearr => 'Monitoring',
    ServiceKey.truenas || ServiceKey.unraid => 'Server',
    ServiceKey.dockge => 'Containers',
    ServiceKey.nginxProxyManager => 'Reverse proxy',
  };

  /// What a service knows of the others, for the two that know most of a
  /// stack: Seerr has its Radarr and Sonarr with their keys, Prowlarr has
  /// the arrs' addresses and hides their keys. Null for every other service,
  /// which is set up on its own.
  String? get knowsOthers => switch (this) {
    ServiceKey.seerr => 'Knows your Radarr and Sonarr, keys included',
    ServiceKey.prowlarr =>
      "Knows your arrs' addresses\u00A0· you add their keys",
    _ => null,
  };

  /// The service's own mark, from `ServiceGlyphs`.
  ///
  /// A category glyph named what a service *does*: a download arrow, a play
  /// button, and three download clients and two media servers came out as
  /// the same picture told apart only by colour. Each service now carries its
  /// own mark: the project's logo reduced to one filled shape (Simple Icons'
  /// where one exists, drawn from the official logo where it does not).
  ///
  /// Three are deliberately not logos. TrueNAS limits fair use of its marks to
  /// text and Unraid forbids its logo inside a third-party interface, so both
  /// draw the kind of machine instead: a drive rack, a hard disk. Plex allows
  /// its chevron only unaltered and, per its brand guide, only with written
  /// permission; until that exists it is a film strip, never a play symbol,
  /// which its guidelines also rule out.
  IconData get icon => switch (this) {
    ServiceKey.seerr => ServiceGlyphs.seerr,
    ServiceKey.radarr => ServiceGlyphs.radarr,
    ServiceKey.sonarr => ServiceGlyphs.sonarr,
    ServiceKey.lidarr => ServiceGlyphs.lidarr,
    ServiceKey.qbittorrent => ServiceGlyphs.qbittorrent,
    ServiceKey.transmission => ServiceGlyphs.transmission,
    ServiceKey.nginxProxyManager => ServiceGlyphs.nginxProxyManager,
    ServiceKey.bazarr => ServiceGlyphs.bazarr,
    ServiceKey.truenas => ServiceGlyphs.truenas,
    ServiceKey.dockge => ServiceGlyphs.dockge,
    ServiceKey.prowlarr => ServiceGlyphs.prowlarr,
    ServiceKey.readarr => ServiceGlyphs.readarr,
    ServiceKey.sabnzbd => ServiceGlyphs.sabnzbd,
    ServiceKey.nzbget => ServiceGlyphs.nzbget,
    ServiceKey.unraid => ServiceGlyphs.unraid,
    ServiceKey.jellyfin => ServiceGlyphs.jellyfin,
    ServiceKey.plex => ServiceGlyphs.plex,
    ServiceKey.emby => ServiceGlyphs.emby,
    ServiceKey.tracearr => ServiceGlyphs.tracearr,
  };

  /// What the interface paints for this service: the neutral lamp, the same
  /// for every service.
  ///
  /// The room is monochrome (principle 3 of the brand book: colour is information). Colour
  /// reaches a pixel from the content (a title's light), and from the five
  /// status tones, and from nothing else, so a service's mark in a list, its
  /// tab, its room and its buttons carry no hue of their own: the identity is
  /// the mark's shape and the name. Measured against the tones, Radarr,
  /// SABnzbd, Plex and Unraid fall within 16° of the fault amber, Transmission
  /// and Readarr within 19° of red and NZBGet 2° from green, which is why the
  /// accents left the interface rather than being walked further apart.
  ///
  /// **This getter is the switch.** Every surface that used to be tinted by a
  /// service (a room's light, a glow, a tinted chip, a walked label) reads
  /// it, so it hands them all the lamp: a light where it is painted as light,
  /// and, through `ServiceTheme.onTint`, the room's ink where it is asked to
  /// carry a label. The brand colour survives as data in [brandAccent].
  Color get accent => AppColors.lamp;

  /// The service's brand colour, as registry data.
  ///
  /// **Not paint.** Nothing in the interface is coloured by it (see [accent]);
  /// `test/core/theme/monochrome_accent_test.dart` keeps it that way by
  /// allowing it to be read only where a colour is the information itself.
  Color get brandAccent => switch (this) {
    ServiceKey.seerr => AppColors.seerr,
    ServiceKey.radarr => AppColors.radarr,
    ServiceKey.sonarr => AppColors.sonarr,
    ServiceKey.lidarr => AppColors.lidarr,
    ServiceKey.qbittorrent => AppColors.qbittorrent,
    ServiceKey.transmission => AppColors.transmission,
    ServiceKey.nginxProxyManager => AppColors.nginxProxyManager,
    ServiceKey.bazarr => AppColors.bazarr,
    ServiceKey.truenas => AppColors.truenas,
    ServiceKey.dockge => AppColors.dockge,
    ServiceKey.prowlarr => AppColors.prowlarr,
    ServiceKey.readarr => AppColors.readarr,
    ServiceKey.sabnzbd => AppColors.sabnzbd,
    ServiceKey.nzbget => AppColors.nzbget,
    ServiceKey.unraid => AppColors.unraid,
    ServiceKey.jellyfin => AppColors.jellyfin,
    ServiceKey.plex => AppColors.plex,
    ServiceKey.emby => AppColors.emby,
    ServiceKey.tracearr => AppColors.tracearr,
  };

  /// Whether this service authenticates with a single API key rather than a
  /// username and password.
  ///
  /// **The one place the app decides that.** Persistence, the settings form and
  /// the verifier all read this rather than re-deriving "is it one of these
  /// three": the three-way check used to be spelled out in five files, so the
  /// next credential-authenticated service could be added to four of them and
  /// leave storage and the UI disagreeing about which fields even exist.
  ///
  /// Written as an exhaustive `switch` on purpose: a `!=` chain would silently
  /// class a newly added service as API-key authenticated, whereas this makes
  /// the compiler ask.
  bool get usesApiKey => switch (this) {
    ServiceKey.qbittorrent ||
    ServiceKey.dockge ||
    ServiceKey.nzbget ||
    // HTTP Basic, straight from `rpc-username`/`rpc-password`. Transmission
    // mints no key of any kind.
    ServiceKey.transmission ||
    // Nginx Proxy Manager has **no long-lived API key at all**: the only
    // credential it accepts is the account's own email and password, which
    // `POST /api/tokens` exchanges for a short-lived bearer token. That is a
    // property of the server, not a shortcut taken here; see [setupNote]
    // for what it means for the user.
    ServiceKey.nginxProxyManager => false,
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.unraid ||
    ServiceKey.jellyfin ||
    ServiceKey.plex ||
    ServiceKey.emby ||
    ServiceKey.tracearr => true,
  };

  /// Whether the library this service serves has to be entered through a chosen
  /// person, so the settings screen offers a viewer picker once it connects.
  ///
  /// True for Jellyfin and Emby, and structurally rather than by preference: a
  /// MediaBrowser API key authenticates as an administrator with **no user
  /// attached**, so every user-scoped question (resume positions, next up,
  /// unplayed) needs a `userId` supplied explicitly. Plex is excluded because
  /// its token *is* its user and `/library/*` accepts no impersonation
  /// parameter. A Plex library has exactly one perspective. Expressed as a
  /// capability so the shared settings screen inserts the control the same way
  /// it decides on `SearchHeadroomCard.appliesTo`, rather than naming a
  /// `ServiceKey` inline.
  bool get needsViewerSelection => speaksMediaBrowser;

  /// A media server: it holds libraries and items, says who is playing, and
  /// a `StreamServerClient` reaches it.
  ///
  /// What [ServiceDomain.stream] used to mean in code before the domain held
  /// anything else: the Stream band is a grouping, this is a capability. A
  /// site that reads libraries, items, sessions or a server's own player asks
  /// this, never the domain, so a service that joins the band without being a
  /// media server is never handed a media server's providers.
  ///
  /// An exhaustive switch, so the next service declares what it is.
  bool get isMediaServer => switch (this) {
    ServiceKey.jellyfin || ServiceKey.plex || ServiceKey.emby => true,
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget ||
    ServiceKey.unraid ||
    ServiceKey.nginxProxyManager ||
    ServiceKey.tracearr => false,
  };

  /// Says who is playing now: its answer becomes rows of Now playing,
  /// Watching now, a room's figure and its light, and the Stack's counts.
  ///
  /// Every media server does; a service that only watches media servers may
  /// too, without being one ([isMediaServer] stays false for it).
  bool get givesSessions => isMediaServer;

  /// Speaks the MediaBrowser API (Emby, and Jellyfin, which forked it): an API key with no
  /// user behind it (so [needsViewerSelection]), sessions that take Pause and
  /// a message besides Stop, and a server-wide admin console.
  bool get speaksMediaBrowser =>
      this == ServiceKey.jellyfin || this == ServiceKey.emby;

  /// Whether listing the libraries is an administrator's read: Jellyfin
  /// refuses `/Library/VirtualFolders` to a household member's token. Emby
  /// answers its `/Library/VirtualFolders/Query` to any signed-in user
  /// (measured on 4.10.2: a member's token gets the list, and a 403 on Users,
  /// Devices and Tasks), so there a member's Libraries is a list, not a note
  /// that she needs an administrator.
  bool get librariesNeedAdministrator => this == ServiceKey.jellyfin;

  /// Its shell mounts `ConnectionInViewScope`, so the page header names the
  /// connection the visit has in view and the shell's lens strip stays quiet
  /// at a tab's root (a second chip would read the location instead and could
  /// disagree).
  ///
  /// The Stream band's shells all do, which is why the strip asked the domain
  /// before this had a name. It is the band's, not [isMediaServer]'s: a
  /// service in the band whose shell does not mount the scope is excluded
  /// here, in this getter, never at the strip.
  bool get mountsConnectionInView => domain == ServiceDomain.stream;

  /// The port this service listens on out of the box.
  ///
  /// Offered as a one-tap suggestion next to the address field, alongside the
  /// host carried over from the service configured before it. On a home lab one
  /// box usually runs everything on different ports, so between the two most
  /// services become a tap plus a pasted key. A suggestion only: a service
  /// behind a reverse proxy is reached on 443 with a path, and nothing here
  /// overwrites an address the user has already typed.
  int get defaultPort => switch (this) {
    ServiceKey.seerr => 5055,
    ServiceKey.radarr => 7878,
    ServiceKey.sonarr => 8989,
    ServiceKey.lidarr => 8686,
    ServiceKey.readarr => 8787,
    ServiceKey.prowlarr => 9696,
    ServiceKey.bazarr => 6767,
    ServiceKey.qbittorrent || ServiceKey.sabnzbd => 8080,
    ServiceKey.nzbget => 6789,
    ServiceKey.transmission => 9091,
    // 81, not 80 or 443. Those two are the proxy *doing its job*: the
    // hostnames it fronts. The admin interface, which is the only thing
    // carrying an API, listens separately.
    ServiceKey.nginxProxyManager => 81,
    ServiceKey.jellyfin || ServiceKey.emby => 8096,
    ServiceKey.plex => 32400,
    // The port its container image publishes.
    ServiceKey.tracearr => 3000,
    ServiceKey.dockge => 5001,
    // Both ship a TLS web UI on the standard port.
    ServiceKey.truenas || ServiceKey.unraid => 443,
  };

  /// What the credential is called in this service's own vocabulary.
  ///
  /// Plex calls its own credential a token, and the field has said so since the
  /// integration shipped; everything else keeps the wording the settings form
  /// already used, so moving the string into the registry changes where it lives
  /// and not what it says.
  String get credentialLabel =>
      this == ServiceKey.plex ? 'Plex token' : 'API key';

  /// The header this service's own client carries the credential in, when it
  /// carries it in one: the header a custom access header of the same name
  /// duplicates, which the Access row offers to move into the credential
  /// field. Null for a service whose credential travels another way (a query
  /// string, a login, a WebSocket call) or is a sign-in pair.
  ///
  /// Jellyfin's is `X-Emby-Token`: its client sends the token there whenever
  /// the connection's access holds `Authorization` for a proxy. Emby's is the
  /// same header, always: it has no other.
  ///
  /// Exhaustive, like [usesApiKey], so a new service has to answer.
  String? get credentialHeader => switch (this) {
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.bazarr ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.unraid => 'X-Api-Key',
    ServiceKey.plex => 'X-Plex-Token',
    ServiceKey.jellyfin || ServiceKey.emby => 'X-Emby-Token',
    ServiceKey.sabnzbd ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.nzbget ||
    ServiceKey.nginxProxyManager ||
    // Its key travels as `Authorization: Bearer`, which `ownHeaders` holds.
    ServiceKey.tracearr => null,
  };

  /// Every header this service's own client sets, lower-cased: its
  /// credential's ([credentialHeader]) and the ones its protocol needs. An
  /// access header by one of these names would never be sent, because the
  /// service's own header wins (`guardedDio`), so the Access row refuses it.
  ///
  /// `Authorization` is here for the four services that sign in with it
  /// (NZBGet and Transmission with Basic, Nginx Proxy Manager and Tracearr with
  /// a bearer token) and not for Jellyfin, whose token moves to `X-Emby-Token` and
  /// leaves `Authorization` to the proxy.
  Set<String> get ownHeaders => switch (this) {
    ServiceKey.plex => const {
      'x-plex-token',
      'x-plex-client-identifier',
      'x-plex-product',
      'x-plex-version',
      'x-plex-platform',
      'x-plex-device-name',
    },
    ServiceKey.transmission => const {
      'authorization',
      'x-transmission-session-id',
    },
    ServiceKey.nzbget ||
    ServiceKey.nginxProxyManager ||
    ServiceKey.tracearr => const {'authorization'},
    ServiceKey.qbittorrent => const {'referer', 'origin'},
    _ => {?credentialHeader?.toLowerCase()},
  };

  /// Whether the Access row offers a proxy's password for this service: not
  /// for the services that sign in with `Authorization` themselves, where a
  /// proxy's Basic password has nowhere to travel.
  bool get offersProxyPassword => !ownHeaders.contains('authorization');

  /// Why the Access row has no Password for this service, in one line, or
  /// null when it has one.
  String? get proxyPasswordUnavailable => offersProxyPassword
      ? null
      : "$title signs in with its own Authorization header, so a proxy "
            "password cannot travel with it.";

  /// Whether one saved credential of this service can carry a narrower scope
  /// than the service's own writes in Cupola need: the services that get a
  /// capability probe, a banner and dimmed writes.
  ///
  /// Exhaustive, like [usesApiKey], so a new service has to answer.
  bool get hasScopedCredential => switch (this) {
    // An Unraid key carries roles and per-resource actions; a TrueNAS key
    // carries its user's roles; an NPM account carries a role and a
    // per-resource permission map. All three can read and not write. A Plex
    // token is a person's: a shared account's reads the libraries and is
    // refused who is watching, which only the owner's sees
    // (`plex_capability.dart`).
    ServiceKey.unraid ||
    ServiceKey.truenas ||
    ServiceKey.nginxProxyManager ||
    ServiceKey.plex => true,
    // Jellyfin's slot can hold a non-admin user's token, but a non-admin is
    // only ever shown sessions it may control, so no write Cupola draws can be
    // refused (see `jellyfin_client.dart`). What it loses are reads, a read
    // scope `jellyfin_provider.dart` answers.
    ServiceKey.jellyfin || ServiceKey.emby => false,
    // The public key reads everything and is the only credential the
    // connection needs; the owner's session, when it comes, is a second
    // credential with its own job, not a narrower scope of this one.
    ServiceKey.tracearr => false,
    // One key compared for equality, or one account with no role: nothing to
    // be narrower than. SABnzbd's NZB key and NZBGet's add-only user are
    // narrower, but they cannot *read* either, which makes them a connection
    // failure rather than a read-only scope.
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.bazarr ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget ||
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.dockge => false,
  };

  /// What the capability copy calls this service's credential: an NPM login is
  /// an *account* with a role, everything else here hands out a *key*.
  ///
  /// One getter so no banner, hint or toast picks the noun for itself.
  String get capabilityCredentialNoun => switch (this) {
    ServiceKey.nginxProxyManager => 'account',
    // What Plex and the connection form call it.
    ServiceKey.plex => 'token',
    _ => 'key',
  };

  /// The verb that fixes a credential too narrow for a write. NPM hands out a
  /// role on an account, not a key, and "Update the key" would send the user
  /// looking for a field that does not exist.
  String get capabilityFixLabel => this == ServiceKey.nginxProxyManager
      ? 'Change account'
      : 'Update the key';

  /// The word this service's secret is filed under in secure storage.
  ///
  /// The tail of `ServiceInstance.credentialStorageKey`, and the reason that
  /// key comes out byte-identical to the one an existing install already wrote:
  /// the suffix was never uniform. Three services' worth of vocabulary is
  /// already on disk: an arr files an `api_key`, qBittorrent a `password`,
  /// and Plex a `token`, so this states it rather than flattening it and orphaning
  /// every stored secret.
  ///
  /// Not [credentialLabel] lowercased: that string is UI copy and may be
  /// reworded, while this one names bytes on disk and may not. They are allowed
  /// to drift, and keeping them apart is what makes that safe.
  ///
  /// Exhaustive on purpose, for the same reason [usesApiKey] is: a `!=` chain
  /// would silently file a newly added service under `api_key` and lose its
  /// secret the first time someone noticed.
  String get credentialStorageSuffix => switch (this) {
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.nginxProxyManager ||
    ServiceKey.dockge ||
    ServiceKey.nzbget => 'password',
    ServiceKey.plex => 'token',
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.unraid ||
    ServiceKey.jellyfin ||
    ServiceKey.emby ||
    ServiceKey.tracearr => 'api_key',
  };

  /// Whether this service may hold more than one instance.
  ///
  /// Whether the global search runs a **leg per connection** for this service.
  ///
  /// Narrower than [supportsMultipleInstances], and the difference is the tap
  /// rather than the query. Every service now reads through the lens, so moving
  /// it changes what any screen shows; a *section per connection*, though, is
  /// only honest if the row under it opens the server that listed it, which
  /// needs two things: a way to build
  /// a client for a named connection, and a detail route that carries and
  /// honours one. The three arrs have both. Seerr's detail path is the Discover
  /// feature, whose thirty-odd reads all resolve through the lens; Bazarr's ids
  /// are a *third* server's (`radarrId` / `sonarrSeriesId`), so its row does not
  /// even land on a Bazarr page. Both therefore search the lens and get one
  /// section, unlabelled, which is what they did before, rather than two
  /// sections with identical contents under two different names.
  ///
  /// Not contradicted by /activity fanning Seerr out over its connections: a
  /// request row opens the *requests list*, which carries `?i=` and honours it,
  /// not a Discover media page. The line here is drawn by the destination, and
  /// Seerr's search destination is still the lens-bound one.
  bool get searchesPerConnection => switch (this) {
    ServiceKey.radarr || ServiceKey.sonarr || ServiceKey.lidarr => true,
    _ => false,
  };

  /// What the *non-secret* half of a credential pair is called.
  ///
  /// The sibling of [credentialLabel], and it exists for one service: Nginx
  /// Proxy Manager authenticates on an account's **email**, and its
  /// `POST /api/tokens` rejects a bare username outright. Labelling that field
  /// "Username" would be an invitation to fail the login and then blame the
  /// password. Every other credential service really does want a username.
  String get usernameLabel =>
      this == ServiceKey.nginxProxyManager ? 'Email' : 'Username';

  /// Where the credential lives inside *this service's* own interface.
  ///
  /// A breadcrumb rather than prose, shown under the field it explains. Null for
  /// the services that authenticate with the web-UI login the user already
  /// knows, since there is nothing to go and find.
  String? get credentialPath => switch (this) {
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.readarr ||
    ServiceKey.prowlarr ||
    ServiceKey.bazarr ||
    ServiceKey.seerr => 'Settings → General → API Key',
    ServiceKey.sabnzbd => 'Config → General → API Key',
    ServiceKey.jellyfin => 'Dashboard → Advanced → API Keys',
    ServiceKey.emby => 'Settings → Advanced → API Keys',
    ServiceKey.tracearr => 'Settings → Data & API → API',
    ServiceKey.truenas => 'Credentials → API Keys',
    ServiceKey.unraid => 'Settings → Management Access → API Keys',
    ServiceKey.plex => 'any item → Get Info → View XML → copy X-Plex-Token',
    // Web-UI login: the user already has these.
    ServiceKey.qbittorrent ||
    ServiceKey.dockge ||
    ServiceKey.nzbget ||
    ServiceKey.transmission ||
    ServiceKey.nginxProxyManager => null,
  };

  /// Setup guidance shown above the address field, for the services where the
  /// API needs turning on first or the project itself carries a caveat worth
  /// stating before anything is typed.
  ///
  /// Registry data rather than an if-chain inside the shared settings screen,
  /// for the same reason [credentialLabel], [credentialPath] and [defaultPort]
  /// live here: everything a service *says about itself* belongs next to the
  /// rest of its description, so adding a service is one entry rather than a
  /// hunt through the screens that render it. Null for the majority, which need
  /// nothing said.
  String? get setupNote => switch (this) {
    ServiceKey.truenas =>
      'Requires TrueNAS SCALE $kTrueNasMinVersion or newer. Create an '
          'API key under Credentials → Local Users, and use the https:// '
          'address of the web UI.',
    ServiceKey.unraid =>
      'Unraid 7.2 and later have the API built in; on an older release, '
          'install the Unraid Connect plugin first. Then create an API key '
          'under Settings → Management Access → API Keys.',
    // Readarr development stopped upstream. Saying so here is the honest
    // thing: the integration works against the last released API, but the
    // user should know they are pointing at a project that will not receive
    // fixes.
    ServiceKey.readarr =>
      'Readarr development has stopped upstream. Cupola targets its '
          'last released API, so existing instances keep working, but expect '
          'no new server-side fixes.',
    ServiceKey.jellyfin =>
      'Create an API key under Dashboard → Advanced → API Keys. The '
          'key authenticates as an administrator but carries no user of its '
          'own, so pick whose watch state to read below once the connection '
          'works.',
    // Naming the *kind* of token matters more than naming the place. Plex has
    // two, and the modern one is a dead end here: a JWT expires after seven
    // days and can only be refreshed through plex.tv, which this connection
    // never calls. Saying so up front beats a week of working software.
    // Emby's own wording: the gear opens "Settings" and the key is made with
    // "New API Key". Like Jellyfin's, it is an administrator's and has no user.
    ServiceKey.emby =>
      'Create an API key under Settings → Advanced → API Keys with New '
          'API Key. The key authenticates as an administrator but carries no '
          'user of its own, so pick whose watch state to read below once the '
          'connection works.',
    // The public key is the one credential, and it is Tracearr's to show: it
    // sits in the API card with a Generate Key button when none exists yet.
    ServiceKey.tracearr =>
      'Requires Tracearr $kTracearrMinVersion or newer. Copy the API key under '
          'Settings → Data & API → API, or press Generate Key if there is none '
          'yet. It begins trr_pub_ and only reads, which is all this '
          'connection does.',
    ServiceKey.plex =>
      'Open any item in Plex Web, choose Get Info → View XML, and copy '
          'the X-Plex-Token from the address bar. This connection talks to '
          'your Plex server alone, so it needs a long-lived device token, not '
          'a temporary one beginning "eyJ" that only plex.tv can renew.',
    // The single most common reason a Transmission daemon is reachable in a
    // browser and not from a phone, and it is worth saying before the address
    // is typed rather than after a mystifying 403.
    ServiceKey.transmission =>
      'Use the same username and password the Transmission web '
          'interface asks for, and check that this device is allowed: '
          '`rpc-whitelist` defaults to 127.0.0.1 only, so a phone on the same '
          'network is refused until the range is widened. Note that '
          'Transmission has one all-or-nothing credential and it can set the '
          'script it runs when a download finishes, treat it as a login to '
          'the machine itself, and do not reuse a password from anywhere '
          'else.',
    // Says the uncomfortable thing plainly, because the user cannot choose
    // otherwise and deserves to know what they are handing over.
    ServiceKey.nginxProxyManager =>
      'Nginx Proxy Manager issues no API key. The only credential it '
          'accepts is an account login, which Cupola exchanges for a '
          'short-lived token it keeps in memory and never writes to disk. '
          'Create a dedicated user for Cupola rather than using your admin '
          'account, and point this at the admin interface (port 81 by '
          'default), not at a hostname the proxy serves.',
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.qbittorrent ||
    ServiceKey.bazarr ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget => null,
  };

  /// The same caveats as [setupNote], said in the onboarding walk's voice: a
  /// sentence or two under the fields, for the services where something has to
  /// be true before the connection is worth testing.
  ///
  /// A second getter rather than a reuse of [setupNote] because the walk says
  /// less on purpose: its address field already prints the default port and
  /// its credential field the breadcrumb, so what is left to say is the caveat
  /// itself. It lives here for the reason [setupNote] does: what a service says
  /// about itself belongs beside the rest of its description, so a new service
  /// is one entry in this file rather than a hunt through the screens that
  /// render it. The walk used to carry its own copy of this list, and TrueNAS
  /// was missing from it. The version requirement was stated in Settings and
  /// nowhere in the flow that actually asks for the address.
  String? get walkNote => switch (this) {
    // Said before the test, not after: an older TrueNAS can connect and then
    // leave whole sections empty, which reads as a broken app rather than an
    // unsupported server.
    ServiceKey.truenas =>
      'Cupola supports TrueNAS SCALE $kTrueNasMinVersion or newer. An older '
          'release may connect and still leave whole sections empty.',
    ServiceKey.readarr =>
      'Readarr development has stopped upstream. Existing instances keep '
          'working against its last released API, but expect no new '
          'server-side fixes.',
    ServiceKey.unraid =>
      'Before Unraid 7.2 the API comes with the Unraid Connect plugin, and '
          'the endpoint stays silent without it.',
    ServiceKey.jellyfin =>
      'The key signs in as an administrator but carries no user of its '
          'own, so pick whose watch state to read in Settings afterwards.',
    ServiceKey.emby =>
      'The key signs in as an administrator but carries no user of its '
          'own, so pick whose watch state to read in Settings afterwards.',
    ServiceKey.tracearr =>
      'It needs Tracearr $kTracearrMinVersion or newer, and the key begins '
          'trr_pub_.',
    ServiceKey.plex =>
      'It must be a long-lived device token: one beginning "eyJ" expires '
          'in 7 days and Cupola cannot renew it without contacting plex.tv.',
    // Transmission's one all-or-nothing credential and its `rpc-whitelist`
    // default are both reasons a daemon that works in a browser refuses a
    // phone, so they are worth a line here too.
    ServiceKey.transmission =>
      'Use the same login the Transmission web interface asks for, and widen '
          '`rpc-whitelist`, it defaults to 127.0.0.1, so this device is '
          'refused until it is listed.',
    ServiceKey.nginxProxyManager =>
      'Point this at the admin interface (port 81 by default), not at a '
          'hostname the proxy serves, and use a dedicated account rather than '
          'your admin one.',
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.qbittorrent ||
    ServiceKey.bazarr ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget => null,
  };

  bool get supportsManualImport {
    return this == ServiceKey.radarr ||
        this == ServiceKey.sonarr ||
        this == ServiceKey.lidarr;
  }

  String get apiVersion => switch (this) {
    ServiceKey.seerr || ServiceKey.lidarr || ServiceKey.readarr => 'v1',
    ServiceKey.radarr || ServiceKey.sonarr => 'v3',
    ServiceKey.qbittorrent => 'WebUI',
    ServiceKey.transmission => 'RPC',
    ServiceKey.nginxProxyManager => 'API',
    ServiceKey.bazarr => 'v1',
    ServiceKey.truenas => 'v25',
    ServiceKey.dockge => 'Socket.IO',
    ServiceKey.prowlarr => 'v1',
    ServiceKey.sabnzbd => 'API',
    ServiceKey.nzbget => 'JSON-RPC',
    ServiceKey.unraid => 'GraphQL',
    ServiceKey.jellyfin => 'v10',
    ServiceKey.plex => 'v1',
    ServiceKey.emby => 'v4',
    ServiceKey.tracearr => 'v2',
  };

  /// The endpoint used to prove a service is answering.
  ///
  /// Empty for the services that verify over something other than REST:
  /// TrueNAS (WebSocket JSON-RPC), Dockge (Socket.IO), SABnzbd (query-string
  /// API), NZBGet (JSON-RPC) and Unraid (GraphQL), each handled by its own
  /// branch in the version loader and in the credential verifier.
  ///
  /// Jellyfin's, Emby's and Plex's entries are **reachability probes, not
  /// credential checks**: all are anonymous endpoints, and no server reads the
  /// `X-Api-Key` header the shared `ApiClient` sends, so a 2xx here says nothing
  /// at all about the pasted credential. That is why those three verify through
  /// their own clients first and only fall back to this table to explain a
  /// refusal (see `diagnoseCredentials`) and why the Dashboard's probe
  /// never reads this table for them at all.
  String get statusEndpoint => switch (this) {
    ServiceKey.seerr => '/api/v1/status',
    ServiceKey.radarr || ServiceKey.sonarr => '/api/v3/system/status',
    ServiceKey.lidarr => '/api/v1/system/status',
    ServiceKey.qbittorrent => '/api/v2/app/version',
    ServiceKey.bazarr => '/api/system/status',
    ServiceKey.prowlarr => '/api/v1/system/status',
    ServiceKey.readarr => '/api/v1/system/status',
    // Both media-server probes are deliberately the *unauthenticated* ones, so
    // reachability separates cleanly from credentials: a 200 here with a 401
    // elsewhere means "the box is up, the token is wrong", which is the single
    // most common Stream misconfiguration and the one a generic timeout hides.
    ServiceKey.jellyfin => '/System/Info/Public',
    ServiceKey.plex => '/identity',
    // Emby answers the same anonymous route under its `/emby` base path.
    ServiceKey.emby => '/emby/System/Info/Public',
    // Tracearr's keyless health route: it names the product and no version, so
    // like the media servers' it proves an address, never a key. The key and
    // the version are read by its own branches (`/api/v1/public/health`).
    ServiceKey.tracearr => '/health',
    // Transmission (RPC envelope + session-id handshake) and Nginx Proxy
    // Manager (token exchange) join this group for the same reason: no plain
    // GET can separate "reachable" from "authenticated" for either.
    //
    // Handled over the RPC envelope in _loadVersion; the endpoint is a POST
    // with a session-id handshake, not a GET.
    ServiceKey.transmission ||
    // Handled in _loadVersion, which reads the unauthenticated `GET /api/`
    // through the client so the token exchange is not paid for a version
    // string.
    ServiceKey.nginxProxyManager ||
    // Handled over WebSocket in _loadVersion; no REST endpoint.
    ServiceKey.truenas ||
    // Handled over Socket.IO in _loadVersion; no REST endpoint.
    ServiceKey.dockge ||
    // Handled over the query-string API in _loadVersion; no REST endpoint.
    ServiceKey.sabnzbd ||
    // Handled over JSON-RPC in _loadVersion; no REST endpoint.
    ServiceKey.nzbget ||
    // Handled over GraphQL in _loadVersion; no REST endpoint.
    ServiceKey.unraid => '',
  };

  String get itemLabel => switch (this) {
    ServiceKey.seerr => 'requests',
    ServiceKey.radarr => 'movies',
    ServiceKey.sonarr => 'series',
    ServiceKey.lidarr => 'artists',
    ServiceKey.qbittorrent || ServiceKey.transmission => 'torrents',
    // The hostnames it fronts. Not "hosts" on its own: a homelab already
    // calls the physical boxes that, and this counts neither of them.
    ServiceKey.nginxProxyManager => 'proxy hosts',
    ServiceKey.bazarr => 'subtitles',
    ServiceKey.truenas => 'pools',
    ServiceKey.dockge => 'stacks',
    ServiceKey.prowlarr => 'indexers',
    ServiceKey.readarr => 'authors',
    ServiceKey.sabnzbd => 'downloads',
    ServiceKey.nzbget => 'downloads',
    ServiceKey.unraid => 'containers',
    // The top-level thing you enumerate on a media server. Not "movies":
    // a single Jellyfin or Plex instance mixes films, shows and music, and
    // naming one of them would both misdescribe the server and read as a
    // duplicate of Radarr's or Sonarr's own label.
    ServiceKey.jellyfin || ServiceKey.plex || ServiceKey.emby => 'libraries',
    // What it watches over: the media servers it monitors.
    ServiceKey.tracearr => 'servers',
  };

  String get routeParam => switch (this) {
    ServiceKey.seerr => 'seerr',
    // The only service whose enum name is camelCase, and a URL is the one
    // place that shows. Every other route segment is the lowercase name the
    // user would type, so this one is spelled out rather than derived.
    ServiceKey.nginxProxyManager => 'npm',
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget ||
    ServiceKey.unraid ||
    ServiceKey.jellyfin ||
    ServiceKey.plex ||
    ServiceKey.emby ||
    ServiceKey.tracearr => name,
  };

  String? extractHost(String? url) {
    final value = url?.trim() ?? '';
    if (value.isEmpty) return null;
    final parseableValue = value.contains('://') ? value : 'http://$value';

    try {
      final uri = Uri.parse(parseableValue);
      if (uri.host.isNotEmpty) {
        return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      }

      return uri.path.isEmpty ? null : uri.path;
    } catch (_) {
      return null;
    }
  }
}

/// The media servers, in registry order ([ServiceKeyExtension.isMediaServer]).
///
/// The one list a site walks when it means "every media server": never a
/// literal `[ServiceKey.jellyfin, ServiceKey.plex]`, which a new media server
/// would silently miss.
final List<ServiceKey> mediaServers = List.unmodifiable(
  ServiceKey.values.where((s) => s.isMediaServer),
);

/// The services that say who is playing now, in registry order
/// ([ServiceKeyExtension.givesSessions]).
final List<ServiceKey> sessionServices = List.unmodifiable(
  ServiceKey.values.where((s) => s.givesSessions),
);
