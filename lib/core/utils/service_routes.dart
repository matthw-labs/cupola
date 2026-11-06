import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/discover_index.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class ServiceRoutes {
  ServiceRoutes._();

  /// The first tab: the Home of modules.
  static const home = '/home';

  /// Edit Home, from the foot of the Home: its modules reordered and hidden.
  static const homeEdit = '$home/edit';

  /// The way in, outside the shell: the Welcome, then Connect and Found.
  /// Reachable at any time ("Revisit onboarding", the Home at zero), so the
  /// router never sends anyone away from it.
  static const welcome = '/welcome';

  /// Connect, without the Welcome before it: the Home at zero's
  /// "Set up a service", which is already past the claim.
  static const welcomeConnect = '$welcome/connect';

  /// The household member's way in: where their Seerr is, then their own
  /// account on it. The Welcome's and the Home at zero's "I have a Seerr
  /// account".
  static const welcomeSignIn = '$welcome/sign-in';

  /// Copying another device: how to get its code, then what it holds. Where
  /// a `cupola://pair` link lands once the router has taken it off the
  /// location, and the Welcome's and Connections' "Copy from another device".
  static const welcomePair = '$welcome/pair';

  /// Where the way in lived before the Welcome. Rewrites onto [welcome].
  static const legacyOnboarding = '/onboarding';

  /// The Stack tab, and the prefix every service's room hangs off: one
  /// service is a *service home* at `/stack/{key}`. TrueNAS keeps the word
  /// "dashboard" for its own console section because the app does not rename
  /// another product's furniture.
  static const stack = '/stack';

  /// The requester's own requests: her third tab.
  static const requests = '/requests';

  /// Where the stack lived while it was the first tab, called Dashboard.
  /// Every path under it rewrites onto [stack] in one hop; see the redirect
  /// in `router.dart`, because a notification, a bookmark or a restored
  /// session from before the move must not 404.
  static const legacyDashboard = '/dashboard';

  /// Where the app lived before Dashboard. Every path under it still
  /// resolves, onto [stack], for the same reason.
  static const legacyServices = '/services';

  static const seerr = '$stack/seerr';
  static const radarr = '$stack/radarr';
  static const sonarr = '$stack/sonarr';
  static const lidarr = '$stack/lidarr';
  static const qbittorrent = '$stack/qbittorrent';
  static const bazarr = '$stack/bazarr';
  static const truenas = '$stack/truenas';
  static const dockge = '$stack/dockge';
  static const prowlarr = '$stack/prowlarr';
  static const readarr = '$stack/readarr';
  static const sabnzbd = '$stack/sabnzbd';
  static const nzbget = '$stack/nzbget';
  static const unraid = '$stack/unraid';
  static const jellyfin = '$stack/jellyfin';
  static const plex = '$stack/plex';
  static const emby = '$stack/emby';
  static const tracearr = '$stack/tracearr';

  /// The two the file was missing. Both services shipped with their callers
  /// building `'/services/transmission'` and `'/services/npm'` by hand, which
  /// is how a single source of truth stops being one, and `npm` is precisely
  /// the segment that is *not* derivable from the enum name, so a hand-built
  /// path is a spelling nobody checks.
  static const transmission = '$stack/transmission';
  static const nginxProxyManager = '$stack/npm';

  /// The home of any service, by key.
  ///
  /// Every call site that wanted this built the path by hand instead, because
  /// there was nothing to call. Going through [ServiceKey.routeParam] keeps the
  /// one irregular segment (Nginx Proxy Manager's `npm`) spelled in exactly
  /// one place.
  static String forService(ServiceKey service) =>
      '$stack/${service.routeParam}';

  // ── The media servers, under the tab model ────────────────────────────────
  //
  // Literals, like every other service's, and tied to their tabs by a test: an
  // enum instance's field is not a compile-time constant in Dart and these have
  // to stay `const`, so nothing the analyzer sees ties a spelling to
  // `ServiceTab.segment`.
  //
  // Jellyfin and Plex share one screen family and **not** one bar, which is why
  // the two blocks below are spelled out separately rather than factored into a
  // shared shape: the surfaces are written against `StreamServerClient` and take
  // the service as a parameter, but the tabs come from what each API can answer
  // (Jellyfin has users, devices and scheduled tasks, Plex has an on-deck hub,
  // its own activities and playlists), and a shared spelling would have to
  // invent a name one of them does not use.
  //
  // Both route shapes stay uniform in the way the arrs are not: a Jellyfin
  // `BaseItemDto` and a Plex `Metadata` describe a movie, a series, a season and
  // an episode with the same fields, so **one** recursive item route covers the
  // whole tree where Radarr, Sonarr and Lidarr each needed their own screen.
  static const jellyfinOverview = '$jellyfin/overview';

  /// The Libraries tab's root, **and** the base of one library's browse under
  /// it; one constant because they are one address, the way
  /// [bazarrSeriesBase] is.
  ///
  /// This one **moved**: the browse was `/dashboard/jellyfin/library/:id`, a
  /// sibling of nothing, and the tab's segment is the plural the bar draws. The
  /// old spelling still resolves; `router.dart` keeps a childless tail for it.
  static const jellyfinLibraries = '$jellyfin/libraries';

  /// The item, inside the Libraries tab's branch: the same move Radarr's film
  /// made into Library, and for the same two reasons: a detail pushed *inside*
  /// its tab survives a switch away from the service, and the poster it flew
  /// from is still under it on one Navigator, so the Hero still flies.
  ///
  /// Declared under `libraries/` and not beside it, which is also what makes
  /// the literal-before-parameter order in `router.dart` load-bearing: `item`
  /// competes with the library browse's `:id` in the same branch.
  static const jellyfinItemBase = '$jellyfinLibraries/item';

  static const jellyfinUsers = '$jellyfin/users';
  static const jellyfinDevices = '$jellyfin/devices';
  static const jellyfinTasks = '$jellyfin/tasks';
  static const jellyfinActivity = '$jellyfin/activity';

  // Emby is Jellyfin's ancestor and keeps its bar, spelled out here for the same
  // reason as the two above: a literal each, so the constants stay `const`.
  static const embyOverview = '$emby/overview';
  static const embyLibraries = '$emby/libraries';
  static const embyItemBase = '$embyLibraries/item';
  static const embyUsers = '$emby/users';
  static const embyDevices = '$emby/devices';
  static const embyTasks = '$emby/tasks';
  static const embyActivity = '$emby/activity';

  // Tracearr watches the media servers and is not one: no libraries, no item
  // tree, five tabs of its own. A literal each, tied to the tab segments by a
  // test, for the reason the blocks above are.
  static const tracearrOverview = '$tracearr/overview';
  static const tracearrLive = '$tracearr/live';
  static const tracearrHistory = '$tracearr/history';
  static const tracearrUsers = '$tracearr/users';
  static const tracearrViolations = '$tracearr/violations';

  /// A person's page, opened from the page at [from], under the tab [from] is
  /// in so Back returns to the row it was opened from, as a title's page does
  /// (`mediaMountFor`): `/stack/tracearr/users/:id` from the Users tab (the
  /// spelling a deep link uses), `/stack/tracearr/<tab>/person/:id` from any
  /// other tab of Tracearr, and the Users spelling from anywhere else.
  ///
  /// The id is Tracearr's own, one segment, so a link resolves from the path
  /// alone.
  static String tracearrPerson(String id, {required String from}) {
    final encoded = Uri.encodeComponent(id);
    return switch (Uri.parse(from).pathSegments) {
      ['stack', 'tracearr', final tab, ...]
          when const {
            'overview',
            'live',
            'history',
            'violations',
          }.contains(tab) =>
        '$tracearr/$tab/person/$encoded',
      _ => '$tracearrUsers/$encoded',
    };
  }

  /// Tracearr's Violations tab narrowed to one person, by `?user=` (their
  /// Tracearr id). A tab that does not read the narrowing opens unnarrowed,
  /// which is the whole of what it would have shown.
  static String tracearrViolationsOf(String userId) =>
      '$tracearrViolations?user=${Uri.encodeQueryComponent(userId)}';

  static const plexOverview = '$plex/overview';

  /// The same two roles [jellyfinLibraries] carries, and the same move: the
  /// browse was `/dashboard/plex/library/:id` and a childless tail keeps that
  /// spelling resolving.
  static const plexLibraries = '$plex/libraries';
  static const plexItemBase = '$plexLibraries/item';

  /// `on-deck`, hyphenated, because that is how Plex writes it and the app does
  /// not rename another product's furniture: `ServiceTab.onDeck.segment` is
  /// the one tab segment that is not simply its enum name.
  static const plexOnDeck = '$plex/on-deck';
  static const plexActivities = '$plex/activities';
  static const plexDevices = '$plex/devices';
  static const plexPlaylists = '$plex/playlists';

  /// One library's browse route, e.g.
  /// `/dashboard/jellyfin/libraries/f137a2dd`.
  ///
  /// The id travels as a path segment and the display name as a query parameter,
  /// following [discoverGenre]: a deep link has to resolve from the path alone, but
  /// a caller that already knows the name can spare the destination a fetch
  /// before its first frame.
  ///
  /// [instanceId] names the connection the library is on (`?i=`), and only when
  /// given: without it the page reads the service's active connection, which is
  /// what an old link or a deep link means.
  static String jellyfinLibrary(
    String id, {
    String? title,
    String? instanceId,
  }) => _streamLibrary(jellyfinLibraries, id, title, instanceId);
  static String plexLibrary(String id, {String? title, String? instanceId}) =>
      _streamLibrary(plexLibraries, id, title, instanceId);
  static String embyLibrary(String id, {String? title, String? instanceId}) =>
      _streamLibrary(embyLibraries, id, title, instanceId);

  static String _streamLibrary(
    String base,
    String id,
    String? title,
    String? instanceId,
  ) {
    final name = title?.trim() ?? '';
    return _withQuery('$base/$id', {
      'title': name.isEmpty ? null : name,
      'i': instanceId,
    });
  }

  /// One item at any depth of the tree: film, show, season or episode.
  ///
  /// Jellyfin ids are GUIDs, an Emby id is a short number and a Plex
  /// `ratingKey` is documented as an opaque string that only *often* looks
  /// numeric, so none of them can go through
  /// `RouteUtils.safeIntParam`. Both are single path segments containing no `/`,
  /// which is why this stays a path route rather than taking
  /// [truenasDataset]'s query-parameter escape hatch.
  ///
  /// [instanceId] is the connection the item is on (`?i=`), appended only when
  /// given. The path alone still resolves, on the service's active connection.
  static String jellyfinItem(String id, {String? instanceId}) =>
      _withQuery('$jellyfinItemBase/$id', {'i': instanceId});
  static String plexItem(String id, {String? instanceId}) =>
      _withQuery('$plexItemBase/$id', {'i': instanceId});
  static String embyItem(String id, {String? instanceId}) =>
      _withQuery('$embyItemBase/$id', {'i': instanceId});

  /// [jellyfinLibrary], [plexLibrary] or [embyLibrary], by [service].
  static String streamLibrary(
    ServiceKey service,
    String id, {
    String? title,
    String? instanceId,
  }) => switch (service) {
    ServiceKey.jellyfin => jellyfinLibrary(
      id,
      title: title,
      instanceId: instanceId,
    ),
    ServiceKey.plex => plexLibrary(id, title: title, instanceId: instanceId),
    ServiceKey.emby => embyLibrary(id, title: title, instanceId: instanceId),
    _ => throw _notAMediaServer(service),
  };

  /// [jellyfinItem], [plexItem] or [embyItem], by [service].
  static String streamItem(
    ServiceKey service,
    String id, {
    String? instanceId,
  }) => switch (service) {
    ServiceKey.jellyfin => jellyfinItem(id, instanceId: instanceId),
    ServiceKey.plex => plexItem(id, instanceId: instanceId),
    ServiceKey.emby => embyItem(id, instanceId: instanceId),
    _ => throw _notAMediaServer(service),
  };

  /// A media server's page of playbacks, on connection [instanceId] when
  /// given (`?i=`), else on the active one.
  static String streamActivity(ServiceKey service, {String? instanceId}) =>
      _withQuery(
        switch (service) {
          ServiceKey.jellyfin => jellyfinActivity,
          ServiceKey.plex => plexActivities,
          ServiceKey.emby => embyActivity,
          _ => throw _notAMediaServer(service),
        },
        {'i': instanceId},
      );

  /// The error a media server route is asked for [service] with, which names
  /// it: the other arm of a ternary would have silently routed it to Plex.
  static ArgumentError _notAMediaServer(ServiceKey service) =>
      ArgumentError.value(service.name, 'service', 'has no media server route');

  // ── TrueNAS sections ──────────────────────────────────────────────────────
  static const truenasDashboard = '$truenas/dashboard';
  static const truenasStorage = '$truenas/storage';
  static const truenasPoolBase = '$truenasStorage/pool';
  static const truenasDatasets = '$truenas/datasets';
  static const truenasDatasetDetail = '$truenasDatasets/detail';
  static const truenasShares = '$truenas/shares';
  static const truenasDataProtection = '$truenas/data-protection';
  static const truenasContainers = '$truenas/containers';
  static const truenasContainerBase = '$truenasContainers/instance';
  static const truenasVms = '$truenas/vms';
  static const truenasVmBase = '$truenasVms/instance';
  static const truenasApps = '$truenas/apps';
  static const truenasAppBase = '$truenasApps/app';
  static const truenasReporting = '$truenas/reporting';
  static const truenasSystem = '$truenas/system';

  /// Pool detail, e.g. `/services/truenas/storage/pool/tank`.
  static String truenasPool(String name) => '$truenasPoolBase/$name';

  /// Dataset detail. ZFS ids contain `/`, so the id travels as a query
  /// parameter rather than a path segment.
  static String truenasDataset(String id) =>
      _withQuery(truenasDatasetDetail, {'id': id});

  /// Container/VM instance detail (Incus instance name is a single segment).
  static String truenasContainer(String id) => '$truenasContainerBase/$id';
  static String truenasVm(String id) => '$truenasVmBase/$id';

  /// Installed app detail by app name.
  static String truenasApp(String name) => '$truenasAppBase/$name';

  /// A System sub-section, e.g. `/services/truenas/system/network`.
  static String truenasSystemSection(String section) =>
      '$truenasSystem/$section';

  // ── Seerr, under the tab model ────────────────────────────────────────────
  //
  // Literals for the reason the \*arr block gives below: an enum instance's
  // field is not a compile-time constant in Dart and these have to stay
  // `const`, so nothing the analyzer sees ties a spelling to its tab. A test
  // does.
  //
  // Seerr carried more pre-tab link shapes than any other service: three
  // see-alls, a genre tree, two media details, a person and a collection, and
  // **every one of them moved under `discover/`**, because Discover is the tab
  // that owns them: each is reached by tapping a row of the Discover page, and
  // a page pushed inside its own tab's branch survives a switch away from Seerr
  // and keeps its Hero flight. The old spellings still resolve; `router.dart`
  // keeps one childless redirect tail per shape.
  static const seerrOverview = '$seerr/overview';

  /// Unchanged by the migration, and that is the point: the all-requests list
  /// was already a page at `/dashboard/seerr/requests`, which is exactly where
  /// the Requests tab's root mounts, so every link that ever pointed at it
  /// still points at it, this time at a tab rather than at a pushed page.
  static const seerrRequests = '$seerr/requests';
  static const seerrIssues = '$seerr/issues';
  static const seerrUsers = '$seerr/users';

  // ── Discover, the app's catalogue tab ────────────────────────────────────
  //
  // Discover was the fourth tab of Seerr's room; it is a tab of the app now,
  // because the catalogue is where a title is found, not a corner of one
  // service. Every link Seerr's room ever made still resolves: `router.dart`
  // rewrites each old spelling here in one hop.
  /// A catalogue page of the Discover tab, from its question: every door of
  /// the atrium and every "See all" lands on one. Each resolves from the
  /// path alone (`catalogQueryFor`); the name rides as `title` only where no
  /// curated list or Seerr list holds it.
  ///
  /// `/discover/all/movie`, `/discover/trending?window=day`,
  /// `/discover/upcoming/tv`, `/discover/genre/movie/16?title=Animation`,
  /// `/discover/network/213`, `/discover/studio/41077`,
  /// `/discover/keyword/movie/4379`, `/discover/language/tv/ko`,
  /// `/discover/decade/movie/1990`. The order and the filters are the
  /// page's own and travel with nothing.
  static String discoverCatalog(CatalogQuery query) {
    final kind = query.kind.mediaType;
    return switch (query.base) {
      CatalogBase.all => '$discover/all/$kind',
      CatalogBase.trending => _withQuery('$discover/trending', {
        'window': query.window == TrendingWindow.day
            ? TrendingWindow.day.param
            : null,
      }),
      CatalogBase.upcoming => '$discover/upcoming/$kind',
      CatalogBase.genre => _withQuery('$discover/genre/$kind/${query.id}', {
        'title': query.name,
      }),
      CatalogBase.network => '$discover/network/${query.id}',
      CatalogBase.studio => '$discover/studio/${query.id}',
      CatalogBase.keyword => _withQuery('$discover/keyword/$kind/${query.id}', {
        'title': query.name,
      }),
      CatalogBase.language => '$discover/language/$kind/${query.code}',
      CatalogBase.decade => '$discover/decade/$kind/${query.id}',
    };
  }

  // ── The \*arr family, under the tab model ─────────────────────────────────
  //
  // Spelled as literals rather than composed from `ServiceTab.segment`: an enum
  // instance's field is not a compile-time constant in Dart and these have to
  // stay `const`. A test ties each one to its tab so the two cannot drift.
  //
  // The four share a bar exactly, so they share these spellings exactly: a user
  // who has learned where Radarr's library lives has learned where Sonarr's
  // does, and a reader comparing two of these blocks should find nothing to
  // compare.
  static const radarrOverview = '$radarr/overview';
  static const radarrLibrary = '$radarr/library';

  /// The film, inside the Library tab's branch.
  static const radarrMovieBase = '$radarrLibrary/movie';

  static const sonarrOverview = '$sonarr/overview';
  static const sonarrLibrary = '$sonarr/library';

  /// The show, inside the Library tab's branch: the same move as the film and
  /// for the same reason: a detail pushed *inside* its tab survives a switch
  /// away from Sonarr and keeps its Hero flight, because the list it flew from
  /// and the page it flew to share one Navigator.
  static const sonarrSeriesBase = '$sonarrLibrary/series';

  static const lidarrOverview = '$lidarr/overview';
  static const lidarrLibrary = '$lidarr/library';

  /// The artist, inside the Library tab's branch. The tab is drawn as one
  /// segmented view of Artists and Albums (decision 24), but an album has no
  /// route of its own to give: `getAllAlbums()` does not exist on
  /// `LidarrService`, so there is one record type here and not two.
  static const lidarrArtistBase = '$lidarrLibrary/artist';

  // ── The download clients, under the tab model ────────────────────────────
  //
  // Literals for the reason the \*arr block gives: an enum instance's field is
  // not a compile-time constant in Dart and these have to stay `const`, so
  // nothing the analyzer sees ties a spelling to its tab. A test does, one per
  // service.
  //
  // The four do **not** share a bar the way the four \*arr do; qBittorrent has
  // RSS where Transmission has Labels and Session, and the two Usenet clients
  // carry History; so there is no shared list to factor out here. What they do
  // share is the shape: Overview first, the queue that was the whole service
  // second, and the job detail pushed inside that Queue branch.
  static const qbittorrentOverview = '$qbittorrent/overview';
  static const qbittorrentQueue = '$qbittorrent/queue';
  static const qbittorrentRss = '$qbittorrent/rss';

  /// The torrent, inside the Queue tab's branch.
  ///
  /// It used to hang off the service root, which was the only place it could
  /// hang from when the service was one page. Inside the branch it survives a
  /// switch away from qBittorrent and back, and the row it was pushed from is
  /// still under it on the same Navigator.
  static const qbittorrentTorrentBase = '$qbittorrentQueue/torrent';

  /// Transmission has no detail route to move, and that absence is the shape
  /// rather than an omission: the torrent list is expandable rows and there has
  /// never been a page to push, so Queue is a leaf branch.
  static const transmissionOverview = '$transmission/overview';
  static const transmissionQueue = '$transmission/queue';
  static const transmissionLabels = '$transmission/labels';
  static const transmissionSession = '$transmission/session';

  /// SABnzbd and NZBGet both keep a History tab, and neither has a job detail:
  /// a queue slot and a history slot are each one row that expands, so both
  /// Queue branches are leaves like Transmission's.
  static const sabnzbdOverview = '$sabnzbd/overview';
  static const sabnzbdQueue = '$sabnzbd/queue';
  static const sabnzbdHistory = '$sabnzbd/history';
  static const sabnzbdServers = '$sabnzbd/servers';

  /// NZBGet carries the widest bar of the four: five tabs, because the daemon
  /// keeps its feeds and its log as first-class things the other three do not
  /// have.
  static const nzbgetOverview = '$nzbget/overview';
  static const nzbgetQueue = '$nzbget/queue';
  static const nzbgetHistory = '$nzbget/history';
  static const nzbgetFeeds = '$nzbget/feeds';
  static const nzbgetMessages = '$nzbget/messages';

  // ── Bazarr, under the tab model ───────────────────────────────────────────
  //
  // Literals, like every other service's, and tied to their tabs by a test.
  //
  // Bazarr is the one service whose bar names the record types themselves:
  // Series and Movies, where the \*arr say Library; so the detail spelling is
  // `<tab>/:id` and not `<tab>/<record>/:id`: `series/series/42` would be a
  // stutter nobody would type. `bazarrSeriesBase` therefore needed no change at
  // all, which is the happiest case of the migration: every link that ever
  // pointed at a Bazarr series still points at it, now at a page inside the
  // Series tab's branch rather than at a sibling of the tabs.
  static const bazarrOverview = '$bazarr/overview';
  static const bazarrWanted = '$bazarr/wanted';
  static const bazarrHistory = '$bazarr/history';
  static const bazarrProviders = '$bazarr/providers';

  /// The Series tab's root, **and** the base of the series detail under it:
  /// one constant because they are one address. Unchanged by the migration,
  /// which is the happiest case it had: every link that ever pointed at a
  /// Bazarr series still points at it, now at a page inside the Series tab's
  /// branch rather than at a sibling of the tabs.
  ///
  /// There is no `bazarrSeries` constant beside it because [bazarrSeries] is
  /// already the function that builds one.
  static const bazarrSeriesBase = '$bazarr/series';

  /// The Movies tab's root, and the base of the film detail under it. This one
  /// **did** move: it was `/dashboard/bazarr/movie/:id`, singular, a sibling of
  /// nothing. The old spelling still resolves; `router.dart` keeps a childless
  /// tail for it.
  static const bazarrMovieBase = '$bazarr/movies';

  // ── Prowlarr, under the tab model ─────────────────────────────────────────
  //
  // Literals, like every other service's, and tied to their tabs by a test.
  //
  // `library` became `indexers`, which is what the bar calls it and what the
  // page always was: a list of indexers under a heading that said Library
  // because every other service's list did. The old spelling still resolves;
  // `router.dart` keeps a childless tail for it.
  static const prowlarrOverview = '$prowlarr/overview';
  static const prowlarrIndexers = '$prowlarr/indexers';
  static const prowlarrHistory = '$prowlarr/history';
  static const prowlarrStats = '$prowlarr/stats';

  /// The indexer, inside the Indexers tab's branch: the same move the film
  /// made into Radarr's Library, and for the same reasons: a detail pushed
  /// *inside* its tab survives a switch away from Prowlarr, and the row it was
  /// pushed from is still under it on one Navigator.
  static const prowlarrIndexerBase = '$prowlarrIndexers/indexer';

  /// Prowlarr's own Settings, which is **not** a tab (decision 26): Apps,
  /// download clients, notifications and indexer proxies are sections of one
  /// field-driven page, and a fifth bar entry for a configuration screen is a
  /// bar entry nobody opens twice. It stays a page pushed from the service, so
  /// it hangs off the service node beside the shell rather than inside a
  /// branch; no one tab owns it.
  static const prowlarrSettings = '$prowlarr/settings';
  static const prowlarrSyncProfiles = '$prowlarrSettings/sync-profiles';
  static const prowlarrTags = '$prowlarrSettings/tags';

  /// Indexer detail, e.g. `/dashboard/prowlarr/indexers/indexer/3`.
  static String prowlarrIndexer(int id) => '$prowlarrIndexerBase/$id';

  /// One of the field-driven settings sections, e.g.
  /// `/dashboard/prowlarr/settings/apps`.
  static String prowlarrSettingsSection(ProwlarrProviderKind kind) =>
      '$prowlarrSettings/${kind.routeSegment}';

  // ── Readarr, under the tab model ──────────────────────────────────────────
  //
  // Literals, like the other three arrs, and tied to their tabs by a test.
  // `readarrLibrary` predates the model and needed no change: the author list
  // was already a page at `/dashboard/readarr/library`, which is exactly where
  // the Library tab's root mounts; so every link that ever pointed at it still
  // points at it, this time at a tab rather than at a pushed page.
  static const readarrOverview = '$readarr/overview';
  static const readarrLibrary = '$readarr/library';

  /// An author's page, pushed over the Library tab.
  static const readarrAuthorBase = '$readarrLibrary/author';

  // ── The infrastructure three, under the tab model ─────────────────────────
  //
  // Literals, like every other service's, and tied to their tabs by a test: an
  // enum instance's field is not a compile-time constant in Dart and these have
  // to stay `const`, so nothing the analyzer sees ties a spelling to
  // `ServiceTab.segment`. An earlier attempt at composing one shipped a path
  // containing a literal dollar sign that no analyzer could see.
  //
  // Three services with nothing else in common: a Compose manager, a NAS and a
  // reverse proxy; so there is no shared shape to factor out here and the
  // blocks below are spelled out one at a time. What they did share was being
  // **one page each**: every route below that is not a tab root used to hang off
  // the service root, because a one-page service had nowhere else to hang it.
  static const dockgeOverview = '$dockge/overview';
  static const dockgeStacks = '$dockge/stacks';
  static const dockgeTerminal = '$dockge/terminal';

  /// The stack, inside the Stacks tab's branch: the move Radarr's film made
  /// into Library, and for the same two reasons: a detail pushed *inside* its
  /// tab survives a switch away from Dockge and back, and the row it was pushed
  /// from is still under it on one Navigator.
  ///
  /// It was `/dashboard/dockge/stack/:name`, a sibling of nothing. The old
  /// spelling still resolves; `router.dart` keeps a childless tail for it, and
  /// a second one for the editor a segment deeper.
  static const dockgeStackBase = '$dockgeStacks/stack';

  /// The new-stack editor, inside the same branch and for the same reason: it
  /// is reached by the New button in the Stacks list's own header, so Stacks is
  /// the tab that owns it. It was `/dashboard/dockge/new`.
  static const dockgeNewStack = '$dockgeStacks/new';

  /// Stack detail, e.g. `/dashboard/dockge/stacks/stack/immich`.
  static String dockgeStack(String name) => '$dockgeStackBase/$name';

  /// Compose editor for a stack, e.g.
  /// `/dashboard/dockge/stacks/stack/immich/edit`.
  static String dockgeStackEdit(String name) => '$dockgeStackBase/$name/edit';

  /// Unraid's six, and not one of them moved: the service shipped exactly one
  /// path (its bare root), so there is no pre-tab spelling to keep resolving
  /// beyond that root, the way Transmission had none.
  static const unraidOverview = '$unraid/overview';
  static const unraidArray = '$unraid/array';
  static const unraidDocker = '$unraid/docker';
  static const unraidVms = '$unraid/vms';
  static const unraidNotifications = '$unraid/notifications';
  static const unraidShares = '$unraid/shares';

  /// Nginx Proxy Manager's five. Spelled `npm…` rather than
  /// `nginxProxyManager…` because that is what the whole feature is called:
  /// `NpmScreen`, `npmClientProvider`, `lib/features/npm/`, while
  /// [nginxProxyManager] keeps the product's full name because it is the one
  /// constant that *names the service*.
  ///
  /// Three of the five segments are hyphenated where the label has a space, and
  /// that is `ServiceTab.segment`'s job rather than a spelling invented here.
  /// Like Unraid, NPM shipped one path and there is nothing to forward.
  static const npmOverview = '$nginxProxyManager/overview';
  static const npmProxyHosts = '$nginxProxyManager/proxy-hosts';
  static const npmCertificates = '$nginxProxyManager/certificates';
  static const npmAccessLists = '$nginxProxyManager/access-lists';
  static const npmAuditLog = '$nginxProxyManager/audit-log';

  /// One proxy host's custom Nginx block, a child of the Proxy hosts tab,
  /// e.g. `/stack/npm/proxy-hosts/4/advanced`.
  static String npmAdvanced(int hostId) => '$npmProxyHosts/$hostId/advanced';

  /// ## `i`: which connection a detail page belongs to
  ///
  /// Every detail route below takes an optional `?i=<instanceId>`. Absent, the
  /// shape every link in the app had before there could be two of a service:
  /// means "whichever one this service is being read through", so nothing that
  /// does not care has to say anything.
  ///
  /// A **query** rather than a path segment, and the difference is a hundred
  /// lines: `state.uri` is the whole URI at every level of nesting, so a nested
  /// route reads it without being told, while `pathParameters` is a map
  /// accumulated down the tree and a new segment would have to be declared on
  /// every one of the descendants under it. It is also not `extra`: go_router
  /// replaces a non-JSON-encodable extra with null, silently, when it
  /// serialises the match list for state restoration: a vector that survives
  /// normal use and evaporates when the OS kills the app is the worst of the
  /// three options.
  static String radarrMovie(int id, {String? heroTag, String? instanceId}) {
    return _withQuery('$radarrMovieBase/$id', {
      'heroTag': heroTag,
      'i': instanceId,
    });
  }

  static String sonarrSeries(int id, {String? heroTag, String? instanceId}) {
    return _withQuery('$sonarrSeriesBase/$id', {
      'heroTag': heroTag,
      'i': instanceId,
    });
  }

  static String lidarrArtist(int id, {String? heroTag, String? instanceId}) {
    return _withQuery('$lidarrArtistBase/$id', {
      'heroTag': heroTag,
      'i': instanceId,
    });
  }

  static String readarrAuthor(int id, {String? heroTag, String? instanceId}) {
    return _withQuery('$readarrAuthorBase/$id', {
      'heroTag': heroTag,
      'i': instanceId,
    });
  }

  static String qbittorrentTorrent(String hash) {
    return '$qbittorrentTorrentBase/$hash';
  }

  /// No `i` on the two Bazarr routes, and that is the honest shape rather than
  /// an omission: a Bazarr row's id is a **third** server's (`radarrId` /
  /// `sonarrSeriesId`), so the connection that matters at the destination is an
  /// arr's, which nothing on the row knows. They briefly took an `instanceId`
  /// that no caller passed and no route read.
  static String bazarrSeries(int sonarrSeriesId, {String? heroTag}) {
    return _withQuery('$bazarrSeriesBase/$sonarrSeriesId', {
      'heroTag': heroTag,
    });
  }

  static String bazarrMovie(int radarrId, {String? heroTag}) {
    return _withQuery('$bazarrMovieBase/$radarrId', {'heroTag': heroTag});
  }

  /// The two top-level tabs a title can be opened from besides the Dashboard.
  static const activity = '/activity';

  /// Activity's other three views, each at its own address (All is
  /// [activity]): what is downloading and waits its turn, the household's
  /// requests, and the last seven days.
  static const activityDownloads = '$activity/downloads';
  static const activityRequests = '$activity/requests';
  static const activityHistory = '$activity/history';

  /// Every arr's blocklist in one, from the foot of History.
  static const activityNeedsYouSegment = 'needs-you';
  static const activityNeedsYou = '$activity/$activityNeedsYouSegment';
  static const activityBlocklistSegment = 'blocklist';
  static const activityBlocklist = '$activity/$activityBlocklistSegment';

  /// The requests of one Seerr connection, or of every one when
  /// [instanceId] is null.
  static String activityRequestsOf(String? instanceId) =>
      _withQuery(activityRequests, {'i': instanceId});

  /// One download's page: [instanceId] the connection it was read from
  /// (its \*arr's, or its client's when no \*arr asked for it), [key] the
  /// client's id for the transfer (`downloadPageKey`).
  static const activityDownloadSegment = 'download';
  static const activityDownloadPath = '$activity/$activityDownloadSegment';
  static String activityDownload({
    required String instanceId,
    required String key,
  }) => _withQuery(activityDownloadPath, {'i': instanceId, 'id': key});
  static const discover = '/discover';

  /// The calendar of everything the household's arrs date in the next
  /// thirty days, which the atrium's band opens.
  static const discoverCalendar = '$discover/calendar';

  /// An index of the atrium, on its own page (`DiscoverIndexPage`).
  static String discoverIndex(DiscoverIndex index) =>
      '$discover/browse/${index.name}';

  /// ## The one page a title has
  ///
  /// A title's page hangs off every branch that opens titles, at the title's
  /// own location (`MediaKey.location`, `/media/movie/653`): the Dashboard,
  /// Activity, Discover, and every tab of the services in [mediaMountServices].
  /// One page mounted many times rather than one route at the root, for the
  /// two reasons the arr details moved inside Library: the poster's Hero flies
  /// only when the tile it left and the page it lands on share one Navigator,
  /// and a tab left and come back to still shows the title.
  ///
  /// The root mounts it once more, for the pages that sit above the tabs
  /// (the import flow): a page pushed into a tab from one of those would open
  /// underneath it.
  static const mediaMountServices = {
    ServiceKey.seerr,
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.jellyfin,
    ServiceKey.plex,
    ServiceKey.emby,
    // Its Live and History rows open the title they are about.
    ServiceKey.tracearr,
  };

  /// Where a title opened from [path] lands: under the service tab [path] is
  /// in when that service mounts titles, else under its top-level tab, else
  /// at the root. [path] is a location the app is at, never a redirecting
  /// one.
  static String mediaMountFor(String path) =>
      switch (Uri.parse(path).pathSegments) {
        ['stack', final service, final tab, ...]
            when mediaMountServices.any((s) => s.routeParam == service) =>
          '$stack/$service/$tab',
        ['stack', ...] => stack,
        ['home', ...] => home,
        ['activity', ...] => activity,
        ['discover', ...] => discover,
        ['requests', ...] => requests,
        _ => '',
      };

  /// The page of [key], opened from the page at [from]. [focus] is the
  /// connection it was opened from (`?i=`, above): that copy leads when it
  /// needs something. [season] is the season of a series the episodes open
  /// on (`?season=`; 0 is the specials): a season or an episode opened from a
  /// media server lands on its own, and a link without it opens where the
  /// page would on its own. [heroTag] lets the poster fly, and [posterUrl]
  /// stands in for it until the page has read who the title is.
  static String media(
    MediaKey key, {
    required String from,
    String? focus,
    int? season,
    String? heroTag,
    String? posterUrl,
  }) => _withQuery('${mediaMountFor(from)}${key.location}', {
    'i': focus,
    'season': season == null || season < 0 ? null : '$season',
    'heroTag': heroTag,
    'posterUrl': posterUrl,
  });

  /// The page of [key] for a caller with no page of its own to open it
  /// from (a row built by a provider): the root form, which
  /// [mounted] moves under the tab it is opened from.
  static String mediaRoot(
    MediaKey key, {
    String? focus,
    int? season,
    String? heroTag,
    String? posterUrl,
  }) => media(
    key,
    from: '',
    focus: focus,
    season: season,
    heroTag: heroTag,
    posterUrl: posterUrl,
  );

  /// The season a title's location asks its episodes to open on
  /// (`?season=`, [media]): a whole number from 0, else null. A link that
  /// names no season, or one that is not a number, asks for none.
  static int? mediaSeasonOf(Uri location) {
    final season = int.tryParse(location.queryParameters['season'] ?? '');
    return season == null || season < 0 ? null : season;
  }

  /// A person's page, opened from the page at [from]: hung under the same
  /// mount a title opened there would be, so a cast member tapped on a title
  /// in Activity opens in Activity, and Back returns to the title.
  static String person(
    int id, {
    required String from,
    String? heroTag,
    String? posterUrl,
  }) => _withQuery('${mediaMountFor(from)}/media/person/$id', {
    'heroTag': heroTag,
    'posterUrl': posterUrl,
  });

  /// A collection's page, opened from the page at [from], under the same
  /// mount as [person].
  static String collection(int id, {required String from, String? heroTag}) =>
      _withQuery('${mediaMountFor(from)}/media/collection/$id', {
        'heroTag': heroTag,
      });

  /// [location] as it is opened from the page at [from]: a title's page in
  /// root form ([mediaRoot]) moves under the mount [from] is in; anything
  /// else stays as it is.
  static String mounted(String location, {required String from}) =>
      location.startsWith('/media/')
      ? '${mediaMountFor(from)}$location'
      : location;

  /// App settings, and the per-service page under it.
  ///
  /// Three widgets were interpolating the per-service settings path by hand:
  /// the not-configured leaf, the cross-service toast and the capability
  /// toast, which is exactly the kind of string that survives a route rename
  /// by silently 404ing in the one state nobody screenshots.
  static const settings = '/settings';
  static const settingsConnections = '$settings/connections';

  /// The code another device copies this one's connections from: Settings'
  /// "Set up another device".
  static const settingsAnotherDevice = '$settings/another-device';

  /// The requester's account: who she is signed in as on a Seerr, signing
  /// out and back in, and removing the server. [instanceId] picks the
  /// connection when she asks more than one; empty, the first.
  static const settingsAccount = '$settings/account';
  static const settingsCertificates = '$settings/certificates';
  static const settingsBackgroundSearch = '$settings/background-search';

  static String settingsAccountFor({String instanceId = ''}) =>
      _withQuery(settingsAccount, {'i': instanceId});

  /// Edit Home again, from Settings: the same page, whose way back is
  /// Settings.
  static const settingsHome = '$settings/home';

  /// Where the fix lives for a service that is not set up, or whose credential
  /// is too narrow: its own settings page, where its setup note is printed.
  static String settingsFor(ServiceKey service) =>
      '$settings/service/${service.routeParam}';

  /// Where every `Set up X` goes: the service's own setup form.
  ///
  /// One destination for one verb. The matrix cell and the not-set-up leaf
  /// sent the user to the connections list, a cross-service control's toast
  /// to the form, and Streaming's empty state to the Dashboard: three places
  /// for the same tap. Every surface that says `Set up X` (the lexicon's
  /// `Lexicon.setUp`) navigates here, and nowhere else.
  static String setUp(ServiceKey service) => settingsFor(service);

  /// The form for a connection of [service], filled in from what the
  /// connection [sourceId] (a Seerr or a Prowlarr) says of the server it
  /// calls [name]. Only names travel: the form asks the source for the rest.
  ///
  /// [alongside] when the service has a connection already: the form adds a
  /// second one, and asks for the name that tells the two apart.
  static String addFound(
    ServiceKey service, {
    required String sourceId,
    required String name,
    required bool alongside,
  }) => _withQuery(settingsFor(service), {
    'new': alongside ? '1' : null,
    'from': sourceId,
    'known': name,
  });

  /// The form to add a connection of [service] at [address]: the remedy of an
  /// address that turned out to be another service's (`Set up Emby`).
  ///
  /// Always a **new** connection, never an edit: the service may already have
  /// one, and writing this address over it would be silent corruption. Only
  /// the address travels in the location; the key never does, and a gateway's
  /// access, which is secret, rides beside the push as its `extra`.
  static String addAt(ServiceKey service, {required String address}) =>
      _withQuery(settingsFor(service), {'new': '1', 'url': address});

  /// The settings form of one saved connection of [service], where a
  /// too-narrow credential is replaced.
  ///
  /// Not [settingsFor]: a service can have two connections, and the fix for a
  /// read-only key on the second one has to land on the second one's form
  /// rather than on the first, which is fine. An empty [connectionId] collapses
  /// to [settingsFor].
  ///
  /// [access] opens the form on its Access row with that choice made, for a
  /// gateway's remedy (`Add a service token` lands on Cloudflare Access).
  static String settingsForConnection(
    ServiceKey service,
    String connectionId, {
    AccessKind? access,
    bool away = false,
  }) => _withQuery(settingsFor(service), {
    'i': connectionId,
    'access': access?.name,
    'away': away ? '1' : null,
  });

  static String _withQuery(String path, Map<String, String?> queryParameters) {
    final values = {
      for (final entry in queryParameters.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          entry.key: entry.value!,
    };

    if (values.isEmpty) {
      return path;
    }

    return Uri(path: path, queryParameters: values).toString();
  }
}
