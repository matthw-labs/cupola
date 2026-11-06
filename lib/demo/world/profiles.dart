/// The configuration profiles of the config inventory (P1–P7, P9 and the P2
/// variants), and P8 behind Cloudflare Access, as values a test pumps
/// (`pumpWithProfile`, in `test/test_helpers/profiles/`) and the demo serves.
///
/// See `README.md` beside this file for what each profile is for.
library;

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'package:cupola/demo/world/config_profile.dart';
import 'package:cupola/demo/world/fakes/media_fakes.dart';
import 'package:cupola/demo/world/world.dart';

export 'package:cupola/demo/world/config_profile.dart';
export 'package:cupola/demo/world/fakes/infra_fakes.dart' show TrueNasRpcFault;
export 'package:cupola/demo/world/fakes/plex_tv_fake.dart'
    show PlexPin, PlexTvFake, plexTvHost;
export 'package:cupola/demo/world/fakes/seerr_sessions.dart'
    show
        SeerrQuickConnectCode,
        SeerrServerState,
        SeerrSession,
        seerrQuickConnectLifetime,
        seerrSessionLifetime;
export 'package:cupola/demo/world/profile_network.dart';
export 'package:cupola/demo/world/world.dart';

ProfileConnection _api(
  String id,
  ServiceKey service,
  String url, {
  String label = '',
  String viewerId = '',
  ConnectionBehaviour behaviour = ConnectionBehaviour.answers,
  bool homeOnly = false,
}) => ProfileConnection(
  ServiceInstance(
    id: id,
    service: service,
    label: label,
    url: url,
    credential: worldKey(id),
    viewerId: viewerId,
  ),
  behaviour: behaviour,
  homeOnly: homeOnly,
);

ProfileConnection _login(
  String id,
  ServiceKey service,
  String url, {
  ConnectionBehaviour behaviour = ConnectionBehaviour.answers,
  bool homeOnly = false,
}) => ProfileConnection(
  ServiceInstance(
    id: id,
    service: service,
    url: url,
    username: 'admin',
    credential: worldKey(id),
  ),
  behaviour: behaviour,
  homeOnly: homeOnly,
);

/// The world's connections, one of each, in the brief's order.
abstract final class WorldConnections {
  static final seerr = _api(WorldIds.seerr, ServiceKey.seerr, WorldHosts.seerr);
  static final jellyfin = _api(
    WorldIds.jellyfin,
    ServiceKey.jellyfin,
    WorldHosts.jellyfin,
    viewerId: JellyfinFake.operatorId,
  );
  static final radarr = _api(
    WorldIds.radarr,
    ServiceKey.radarr,
    WorldHosts.radarr,
  );
  static final radarr4k = _api(
    WorldIds.radarr4k,
    ServiceKey.radarr,
    WorldHosts.radarr4k,
    label: '4K',
  );
  static final sonarr = _api(
    WorldIds.sonarr,
    ServiceKey.sonarr,
    WorldHosts.sonarr,
  );
  static final sonarrAnime = _api(
    WorldIds.sonarrAnime,
    ServiceKey.sonarr,
    WorldHosts.sonarrAnime,
    label: 'Anime',
  );
  static final lidarr = _api(
    WorldIds.lidarr,
    ServiceKey.lidarr,
    WorldHosts.lidarr,
  );
  static final bazarr = _api(
    WorldIds.bazarr,
    ServiceKey.bazarr,
    WorldHosts.bazarr,
  );
  static final prowlarr = _api(
    WorldIds.prowlarr,
    ServiceKey.prowlarr,
    WorldHosts.prowlarr,
  );
  static final qbittorrent = _login(
    WorldIds.qbittorrent,
    ServiceKey.qbittorrent,
    WorldHosts.qbittorrent,
  );
  static final sabnzbd = _api(
    WorldIds.sabnzbd,
    ServiceKey.sabnzbd,
    WorldHosts.sabnzbd,
  );
  static final truenas = _api(
    WorldIds.truenas,
    ServiceKey.truenas,
    WorldHosts.truenas,
  );
  static final dockge = _login(
    WorldIds.dockge,
    ServiceKey.dockge,
    WorldHosts.dockge,
  );
  static final plex = _api(WorldIds.plex, ServiceKey.plex, WorldHosts.plex);

  /// Emby on `tower`, World B's media server: the household's titles again,
  /// watched through the operator.
  static final emby = _api(
    WorldIds.emby,
    ServiceKey.emby,
    WorldHosts.emby,
    viewerId: EmbyFake.operatorId,
  );
  static final transmission = _login(
    WorldIds.transmission,
    ServiceKey.transmission,
    WorldHosts.transmission,
  );

  /// The cabin's Jellyfin, named by the user: in no profile, for a test that
  /// adds it with `ConfigProfile.withConnection` beside the unnamed one at
  /// home: two of a media server, one of them nobody named.
  static final jellyfinCabin = _api(
    WorldIds.jellyfinCabin,
    ServiceKey.jellyfin,
    WorldHosts.jellyfinCabin,
    label: 'Cabin',
    viewerId: JellyfinFake.operatorId,
  );

  /// The cabin's Plex, named by the user: in no profile, for a test that adds
  /// it beside the unnamed one at home: two of the other media server.
  static final plexCabin = _api(
    WorldIds.plexCabin,
    ServiceKey.plex,
    WorldHosts.plexCabin,
    label: 'Cabin',
  );

  /// The cabin's Seerr, named by the user: in no profile, for a test that
  /// adds it beside the unnamed one at home: two Seerr, each answering for
  /// its own requests.
  static final seerrCabin = _api(
    WorldIds.seerrCabin,
    ServiceKey.seerr,
    WorldHosts.seerrCabin,
    label: 'Cabin',
  );

  /// A second Lidarr, for the vinyl rips: in no profile, for a test that
  /// adds it. It numbers its artists from one like the first, so the same id
  /// names a different artist on each.
  static final lidarrVinyl = _api(
    WorldIds.lidarrVinyl,
    ServiceKey.lidarr,
    WorldHosts.lidarrVinyl,
    label: 'Vinyl',
  );

  /// Sara's Seerr, outside the household, where the operator has an account
  /// of his own with REQUEST only: P9's second Seerr. Labelled with her name.
  static final seerrFriend = _api(
    WorldIds.seerrFriend,
    ServiceKey.seerr,
    WorldHosts.seerrFriend,
    label: WorldPeople.friend,
  ).withSeerrAccount(WorldSeerrUsers.operatorAtFriend);

  /// A second Prowlarr, on `tower`, named by the user: in no profile, for a
  /// test that adds it beside the first. It numbers its indexers from one
  /// like the first, so the same id names an indexer on each.
  static final prowlarrTower = _api(
    WorldIds.prowlarrTower,
    ServiceKey.prowlarr,
    WorldHosts.prowlarrTower,
    label: 'Tower',
  );

  /// A second Dockge, on `tower`, named by the user: in no profile. It runs
  /// the same three stacks as the first, `immich` exited on each.
  static final dockgeTower = ProfileConnection(
    ServiceInstance(
      id: WorldIds.dockgeTower,
      service: ServiceKey.dockge,
      url: WorldHosts.dockgeTower,
      label: 'Tower',
      username: 'admin',
      credential: worldKey(WorldIds.dockgeTower),
    ),
  );

  /// A second Nginx Proxy Manager, on `nas`, named by the user: in no
  /// profile, for a test that adds it beside World B's.
  static final npmNas = ProfileConnection(
    ServiceInstance(
      id: WorldIds.npmNas,
      service: ServiceKey.nginxProxyManager,
      url: WorldHosts.npmNas,
      label: 'Home',
      username: 'admin',
      credential: worldKey(WorldIds.npmNas),
    ),
  );

  // World B, on `tower`: in no profile, for a test that adds one with
  // `ConfigProfile.withConnection`: the NPM and Unraid read-only cases.
  static final readarr = _api(
    'readarr',
    ServiceKey.readarr,
    WorldHosts.readarr,
  );
  static final nzbget = _login('nzbget', ServiceKey.nzbget, WorldHosts.nzbget);
  static final unraid = _api('unraid', ServiceKey.unraid, WorldHosts.unraid);
  static final npm = _login(
    'npm',
    ServiceKey.nginxProxyManager,
    WorldHosts.npm,
  );
}

SeerrKnownServer _knows(
  int seerrId,
  ServiceKey service,
  String name,
  String connectionId,
  String url, {
  bool is4k = false,
  bool isDefault = false,
}) => SeerrKnownServer(
  seerrId: seerrId,
  service: service,
  name: name,
  url: url,
  apiKey: worldKey(connectionId),
  containerUrl: WorldContainers.of(connectionId),
  is4k: is4k,
  isDefault: isDefault,
  activeProfileName: is4k ? 'Ultra-HD' : 'HD-1080p',
  activeDirectory: switch ((service, is4k, name.contains('Anime'))) {
    (ServiceKey.radarr, true, _) => '/mnt/tank/media/films-4k',
    (ServiceKey.radarr, false, _) => '/mnt/tank/media/films',
    (_, _, true) => '/mnt/tank/media/anime',
    _ => '/mnt/tank/media/series',
  },
);

/// The three self-signed origins of the brief: TrueNAS, Dockge, Radarr 4K.
final Map<String, String> _worldPins = {
  for (final (url, fill) in const [
    (WorldHosts.truenas, 'a'),
    (WorldHosts.dockge, 'b'),
    (WorldHosts.radarr4k, 'c'),
  ])
    UrlUtils.certOrigin(url)!: fill * 64,
};

abstract final class Profiles {
  /// P1: Full household (Matt, operator). The canvas default: twelve
  /// connections, all answering, Radarr and Radarr 4K side by side.
  static final p1 = ConfigProfile(
    id: 'P1',
    title: 'Full household',
    summary:
        'Seerr, Jellyfin, Radarr, Radarr 4K, Sonarr, Lidarr, Bazarr, Prowlarr, '
        'qBittorrent, SABnzbd, TrueNAS and Dockge, all answering. Plex, '
        'Readarr, Transmission, NZBGet, Unraid and NPM not set up.',
    cases: const {
      ConfigCase.severalInstances,
      ConfigCase.notSetUp,
      ConfigCase.matchNotVerified,
    },
    connections: [
      WorldConnections.seerr,
      WorldConnections.jellyfin,
      WorldConnections.radarr,
      WorldConnections.radarr4k,
      WorldConnections.sonarr,
      WorldConnections.lidarr,
      WorldConnections.bazarr,
      WorldConnections.prowlarr,
      WorldConnections.qbittorrent,
      WorldConnections.sabnzbd,
      WorldConnections.truenas,
      WorldConnections.dockge,
    ],
    seerrKnows: [
      _knows(
        0,
        ServiceKey.radarr,
        'Radarr',
        WorldIds.radarr,
        WorldHosts.radarr,
        isDefault: true,
      ),
      _knows(
        1,
        ServiceKey.radarr,
        'Radarr 4K',
        WorldIds.radarr4k,
        WorldHosts.radarr4k,
        is4k: true,
        isDefault: true,
      ),
      _knows(
        0,
        ServiceKey.sonarr,
        'Sonarr',
        WorldIds.sonarr,
        WorldHosts.sonarr,
        isDefault: true,
      ),
    ],
    // Case f: Jellyfin filed Elephants Dream under another TMDB id.
    unverifiedMatches: const {'elephantsDream'},
    trustedCertificates: _worldPins,
  );

  /// P2: Requester (Anna): her Seerr connection only, signed in with her
  /// own local account (REQUEST, 32).
  ///
  /// The network answers her account as Seerr does: `/auth/local` with her
  /// email and password, a session cookie, `/auth/me` as her, her own
  /// requests only, and 403 on the operator's routes. The connection carries
  /// her account and its saved session, no key, so the app reaches the server
  /// as her; see `ProfileConnection.seerrAccount`.
  static final p2 = ConfigProfile(
    id: 'P2',
    title: 'Requester',
    summary:
        "Anna's Seerr, nothing else, signed in with her own local account "
        '(REQUEST only).',
    cases: const {ConfigCase.notAllowed, ConfigCase.didNotAnswer},
    connections: [
      WorldConnections.seerr.withSeerrAccount(WorldSeerrUsers.annaLocal),
    ],
    seerrRequester: WorldSeerrUsers.annaLocal,
  );

  /// P2-J, Anna through Jellyfin: her Seerr account is the Jellyfin user
  /// Seerr imported, signed in with her Jellyfin username and password
  /// (`/auth/jellyfin`). The server is Seerr 3.5.0, so Jellyfin Quick
  /// Connect is there too.
  static final p2ViaJellyfin = ConfigProfile(
    id: 'P2-J',
    title: 'Requester through Jellyfin',
    summary:
        "Anna's Seerr (3.5.0, on Jellyfin), signed in with her Jellyfin "
        'account.',
    cases: const {ConfigCase.notAllowed, ConfigCase.didNotAnswer},
    connections: [
      WorldConnections.seerr
          .withSeerrAccount(WorldSeerrUsers.annaJellyfin)
          .withSeerrRelease(SeerrRelease.seerr),
    ],
    seerrRequester: WorldSeerrUsers.annaJellyfin,
  );

  /// P2-P, Anna through Plex: a Seerr set up with Plex (`mediaServerType`
  /// 1), and her Plex account, signed in through plex.tv's PIN and
  /// `/auth/plex`. Cupola has no Plex connection.
  static final p2ViaPlex = ConfigProfile(
    id: 'P2-P',
    title: 'Requester through Plex',
    summary:
        "Anna's Seerr, set up with Plex, signed in with her Plex account "
        'through plex.tv.',
    cases: const {ConfigCase.notAllowed, ConfigCase.didNotAnswer},
    connections: [
      WorldConnections.seerr
          .withSeerrAccount(WorldSeerrUsers.annaPlex)
          .withSeerrMediaServer(SeerrMediaServer.plex),
    ],
    seerrRequester: WorldSeerrUsers.annaPlex,
  );

  /// P2+J, Anna with her own Jellyfin sign-in: a non-admin user's token in
  /// the Jellyfin slot, answering as [ConnectionBehaviour.readOnly] (no admin
  /// reads, only her own sessions).
  static final p2WithJellyfin = ConfigProfile(
    id: 'P2+J',
    title: 'Requester with Jellyfin',
    summary: "P2 plus Anna's own, non-admin Jellyfin sign-in.",
    cases: const {ConfigCase.notAllowed, ConfigCase.didNotAnswer},
    connections: [
      p2.connections.single,
      ProfileConnection(
        WorldConnections.jellyfin.instance.copyWith(
          viewerId: JellyfinFake.annaId,
        ),
        behaviour: ConnectionBehaviour.readOnly,
      ),
    ],
    seerrRequester: p2.seerrRequester,
  );

  /// P3, First day (J-HomeFresh): Radarr, Sonarr, Seerr. No download client,
  /// no media server, no Bazarr, no Prowlarr.
  static final p3 = ConfigProfile(
    id: 'P3',
    title: 'First day',
    summary: 'Radarr, Sonarr and Seerr only.',
    cases: const {ConfigCase.notSetUp},
    connections: [
      WorldConnections.radarr,
      WorldConnections.sonarr,
      WorldConnections.seerr,
    ],
    seerrKnows: [
      _knows(
        0,
        ServiceKey.radarr,
        'Radarr',
        WorldIds.radarr,
        WorldHosts.radarr,
        isDefault: true,
      ),
      _knows(
        0,
        ServiceKey.sonarr,
        'Sonarr',
        WorldIds.sonarr,
        WorldHosts.sonarr,
        isDefault: true,
      ),
    ],
  );

  /// P4: Arr stack without Seerr, Bazarr or a media server, and two
  /// different download clients.
  static final p4 = ConfigProfile(
    id: 'P4',
    title: 'Arr stack without Seerr',
    summary:
        'Radarr, Sonarr, Lidarr, Prowlarr, qBittorrent and Transmission. No '
        'Seerr, Bazarr or media server.',
    cases: const {ConfigCase.notSetUp},
    connections: [
      WorldConnections.radarr,
      WorldConnections.sonarr,
      WorldConnections.lidarr,
      WorldConnections.prowlarr,
      WorldConnections.qbittorrent,
      WorldConnections.transmission,
    ],
  );

  /// P5: Sonarr and Radarr known only through Seerr. Cupola has Seerr and
  /// Jellyfin, and Seerr's settings name a Radarr and a Sonarr that answer at
  /// their addresses but have no connection in Cupola.
  static final p5 = ConfigProfile(
    id: 'P5',
    title: 'Arrs only through Seerr',
    summary:
        'Seerr and Jellyfin. Seerr knows a Radarr and a Sonarr Cupola has no '
        'connection to.',
    cases: const {ConfigCase.knownThroughAnother, ConfigCase.notSetUp},
    connections: [WorldConnections.seerr, WorldConnections.jellyfin],
    seerrKnows: [
      _knows(
        0,
        ServiceKey.radarr,
        'Radarr',
        WorldIds.radarr,
        WorldHosts.radarr,
        isDefault: true,
      ),
      _knows(
        0,
        ServiceKey.sonarr,
        'Sonarr',
        WorldIds.sonarr,
        WorldHosts.sonarr,
        isDefault: true,
      ),
    ],
  );

  /// P6, two of a kind (Plex instead of Jellyfin): two Radarr, two Sonarr,
  /// Seerr with a default, a second standard (the archive, which Cupola has
  /// no connection for) and a 4K Radarr, Bazarr following Radarr only, a
  /// shared (non-owner) Plex token, qBittorrent and SABnzbd.
  static final p6 = ConfigProfile(
    id: 'P6',
    title: 'Two of a kind, Plex',
    summary:
        'Radarr + Radarr 4K, Sonarr + Sonarr Anime, Seerr (default, archive '
        'and 4K), '
        'Bazarr on Radarr only, a non-owner Plex, qBittorrent and SABnzbd.',
    cases: const {
      ConfigCase.severalInstances,
      ConfigCase.matchNotVerified,
      ConfigCase.notAllowed,
    },
    connections: [
      WorldConnections.seerr,
      WorldConnections.plex.withBehaviour(ConnectionBehaviour.readOnly),
      WorldConnections.radarr,
      WorldConnections.radarr4k,
      WorldConnections.sonarr,
      WorldConnections.sonarrAnime,
      WorldConnections.bazarr,
      WorldConnections.qbittorrent,
      WorldConnections.sabnzbd,
    ],
    seerrKnows: [
      _knows(
        0,
        ServiceKey.radarr,
        'Radarr',
        WorldIds.radarr,
        WorldHosts.radarr,
        isDefault: true,
      ),
      _knows(
        1,
        ServiceKey.radarr,
        'Radarr 4K',
        WorldIds.radarr4k,
        WorldHosts.radarr4k,
        is4k: true,
        isDefault: true,
      ),
      SeerrKnownServer(
        seerrId: 2,
        service: ServiceKey.radarr,
        name: 'Radarr Archive',
        url: WorldHosts.radarrArchive,
        apiKey: worldKey('radarr-archive'),
        activeProfileId: 3,
        activeProfileName: 'SD-720p',
        activeDirectory: '/mnt/tank/media/archive',
        rootFolders: const [
          (path: '/mnt/tank/media/archive', freeSpace: 3100000000000),
        ],
      ),
      _knows(
        0,
        ServiceKey.sonarr,
        'Sonarr',
        WorldIds.sonarr,
        WorldHosts.sonarr,
        isDefault: true,
      ),
      _knows(
        1,
        ServiceKey.sonarr,
        'Sonarr Anime',
        WorldIds.sonarrAnime,
        WorldHosts.sonarrAnime,
      ),
    ],
    unverifiedMatches: const {'elephantsDream'},
    bazarrFollows: const {ServiceKey.radarr},
    trustedCertificates: {UrlUtils.certOrigin(WorldHosts.radarr4k)!: 'c' * 64},
  );

  /// P7: Full household, degraded and away. P1 away from home, Jellyfin and
  /// Bazarr not answering, five services home-only, qBittorrent refusing the
  /// sign-in, TrueNAS on a read-only key.
  static final p7 = ConfigProfile(
    id: 'P7',
    title: 'Full household, degraded and away',
    summary:
        'P1 away from home. Jellyfin and Bazarr do not answer; Lidarr, '
        'Prowlarr, SABnzbd, TrueNAS and Dockge are home-only; qBittorrent '
        'refuses the sign-in; the TrueNAS key is read-only.',
    cases: const {
      ConfigCase.didNotAnswer,
      ConfigCase.notAllowed,
      ConfigCase.severalInstances,
      ConfigCase.notSetUp,
    },
    place: NetworkPlace.away,
    connections: [
      for (final c in p1.connections)
        switch (c.id) {
          WorldIds.jellyfin ||
          WorldIds.bazarr => c.withBehaviour(ConnectionBehaviour.didNotAnswer),
          WorldIds.qbittorrent => c.withBehaviour(
            ConnectionBehaviour.refusesKey,
          ),
          WorldIds.truenas =>
            c.withBehaviour(ConnectionBehaviour.readOnly).withHomeOnly(true),
          WorldIds.lidarr ||
          WorldIds.prowlarr ||
          WorldIds.sabnzbd ||
          WorldIds.dockge => c.withHomeOnly(true),
          _ => c,
        },
    ],
    seerrKnows: p1.seerrKnows,
    unverifiedMatches: p1.unverifiedMatches,
    trustedCertificates: _worldPins,
  );

  /// P8: Behind Cloudflare Access. P1 away from home, with Radarr, Sonarr
  /// and Seerr behind one Access team (`cupola-home`). Radarr presents a
  /// service token Access lets through; Sonarr presents none; Seerr presents
  /// one Access knows and no Service Auth policy admits.
  ///
  /// The addresses stay P1's: a connection has one address, so the one it is
  /// reached at away from home is the one Access stands in front of.
  static final p8 = ConfigProfile(
    id: 'P8',
    title: 'Behind Cloudflare Access',
    summary:
        'P1 away from home. Radarr, Sonarr and Seerr are behind Cloudflare '
        'Access: Radarr with a token Access lets through, Sonarr with none, '
        'Seerr with a token no Service Auth policy admits.',
    cases: const {
      ConfigCase.notAllowed,
      ConfigCase.severalInstances,
      ConfigCase.notSetUp,
    },
    place: NetworkPlace.away,
    connections: [
      for (final c in p1.connections)
        switch (c.id) {
          WorldIds.radarr =>
            c
                .withAccess(WorldTokens.radarr.access)
                .withBehaviour(
                  const ConnectionBehaviour.behindCloudflareAccess(
                    serviceToken: WorldTokens.radarr,
                  ),
                ),
          WorldIds.sonarr => c.withBehaviour(
            const ConnectionBehaviour.behindCloudflareAccess(
              serviceToken: WorldTokens.sonarr,
            ),
          ),
          WorldIds.seerr =>
            c
                .withAccess(WorldTokens.seerr.access)
                .withBehaviour(
                  const ConnectionBehaviour.behindCloudflareAccess(
                    serviceToken: WorldTokens.seerr,
                    tokenHasPolicy: false,
                  ),
                ),
          _ => c,
        },
    ],
    seerrKnows: p1.seerrKnows,
    unverifiedMatches: p1.unverifiedMatches,
    trustedCertificates: _worldPins,
  );

  /// P9: Operator with a friend's Seerr. P1, plus Sara's Seerr, where the
  /// operator signs in with an account of his own that may only request.
  /// The household's Seerr answers his key; Sara's answers his account.
  static final p9 = ConfigProfile(
    id: 'P9',
    title: "Full household and a friend's Seerr",
    summary:
        "P1 plus Sara's Seerr, where the operator is a requester with his own "
        'account.',
    cases: const {
      ConfigCase.severalInstances,
      ConfigCase.notSetUp,
      ConfigCase.matchNotVerified,
      ConfigCase.notAllowed,
    },
    connections: [...p1.connections, WorldConnections.seerrFriend],
    seerrKnows: p1.seerrKnows,
    unverifiedMatches: p1.unverifiedMatches,
    trustedCertificates: _worldPins,
  );

  static final all = [
    p1,
    p2,
    p2ViaJellyfin,
    p2ViaPlex,
    p2WithJellyfin,
    p3,
    p4,
    p5,
    p6,
    p7,
    p8,
    p9,
  ];
}

/// The Cloudflare Access service tokens of the world's Access team. P8's
/// Radarr and Seerr are configured with theirs; Sonarr's exists in Access and
/// is configured nowhere, the token a user has yet to paste.
abstract final class WorldTokens {
  static const radarr = (
    id: 'world-radarr.access',
    secret: 'world-radarr-cf-secret',
  );
  static const sonarr = (
    id: 'world-sonarr.access',
    secret: 'world-sonarr-cf-secret',
  );
  static const seerr = (
    id: 'world-seerr.access',
    secret: 'world-seerr-cf-secret',
  );
}

/// A world token as the connection presents it.
extension WorldTokenAccess on ({String id, String secret}) {
  CloudflareServiceToken get access =>
      CloudflareServiceToken(clientId: id, clientSecret: secret);
}
