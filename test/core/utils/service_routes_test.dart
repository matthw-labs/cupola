import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('ServiceRoutes', () {
    test('the capability fix lands on that connection, not the first', () {
      // A read-only key on the second TrueNAS is fixed on the second TrueNAS's
      // form. The router already reads `?i=` for the settings form.
      expect(
        ServiceRoutes.settingsForConnection(ServiceKey.truenas, 'truenas-2a'),
        '/settings/service/truenas?i=truenas-2a',
      );
      // No connection id collapses to the service's own page.
      expect(
        ServiceRoutes.settingsForConnection(ServiceKey.truenas, ''),
        ServiceRoutes.settingsFor(ServiceKey.truenas),
      );
    });

    test('every registered service has a home route, and it interpolates', () {
      // Exhaustive over the registry, so a service added later cannot ship
      // without one. It also catches the specific way this helper can be
      // broken and still analyses clean: an escaped dollar in the literal
      // makes the helper return the interpolation as text, which no type
      // checks and no analyzer rule sees.
      for (final service in ServiceKey.values) {
        final route = ServiceRoutes.forService(service);
        expect(route, startsWith('${ServiceRoutes.stack}/'));
        expect(route, isNot(contains(r'$')));
        expect(route, isNot(contains('{')));
        expect(route, endsWith('/${service.routeParam}'));
      }
    });

    test('the tabs have a root each, and the old ones are named as old', () {
      expect(ServiceRoutes.home, '/home');
      expect(ServiceRoutes.stack, '/stack');
      expect(ServiceRoutes.requests, '/requests');
      // Where the stack lived: the redirect rewrites these, nothing builds them.
      expect(ServiceRoutes.legacyDashboard, '/dashboard');
      expect(ServiceRoutes.legacyServices, '/services');
    });

    test('the two that used to be built by hand are constants now', () {
      expect(
        ServiceRoutes.transmission,
        ServiceRoutes.forService(ServiceKey.transmission),
      );
      // The one segment that is not the enum name.
      expect(ServiceRoutes.nginxProxyManager, '/stack/npm');
      expect(
        ServiceRoutes.nginxProxyManager,
        ServiceRoutes.forService(ServiceKey.nginxProxyManager),
      );
    });

    test('builds Radarr detail routes with optional hero tag', () {
      // The film moved under `library/`: it is a page inside the Library tab's
      // branch now, not a sibling of the tabs. Every link in the app is built
      // here, so this constant is what put it there.
      expect(ServiceRoutes.radarrMovie(42), '/stack/radarr/library/movie/42');
      expect(
        ServiceRoutes.radarrMovie(42, heroTag: 'movie hero'),
        '/stack/radarr/library/movie/42?heroTag=movie+hero',
      );
    });

    test('the Radarr tab roots are spelled by the tabs they mount', () {
      // Both are written as literals in `ServiceRoutes` because an enum
      // instance's field is not a compile-time constant in Dart and these have
      // to stay `const`, so nothing the analyzer sees ties the URL spelling to
      // the tab. This does, and the film hangs off the second one, which means
      // a drift there moves every detail link in the app with it.
      expect(
        ServiceRoutes.radarrOverview,
        '${ServiceRoutes.radarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.radarrLibrary,
        '${ServiceRoutes.radarr}/${ServiceTab.library.segment}',
      );
      expect(
        ServiceRoutes.radarrMovieBase,
        startsWith('${ServiceRoutes.radarrLibrary}/'),
      );
    });

    test('builds Sonarr and Lidarr detail routes', () {
      // The show moved under `library/` with the film, and for the same
      // reason: it is a page inside the Library tab's branch now, not a
      // sibling of the tabs.
      expect(
        ServiceRoutes.sonarrSeries(7, heroTag: 'series_7'),
        '/stack/sonarr/library/series/7?heroTag=series_7',
      );
      expect(
        ServiceRoutes.lidarrArtist(9, heroTag: 'artist_9'),
        '/stack/lidarr/library/artist/9?heroTag=artist_9',
      );
    });

    test('the Sonarr tab roots are spelled by the tabs they mount', () {
      // Same tie as Radarr's, and it has to be its own case rather than a loop
      // over the four: these are `const` literals precisely because an enum
      // instance's field is not a compile-time constant, so there is nothing
      // to iterate that would not defeat the point.
      expect(
        ServiceRoutes.sonarrOverview,
        '${ServiceRoutes.sonarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.sonarrLibrary,
        '${ServiceRoutes.sonarr}/${ServiceTab.library.segment}',
      );
      expect(
        ServiceRoutes.sonarrSeriesBase,
        startsWith('${ServiceRoutes.sonarrLibrary}/'),
      );
    });

    test('the Lidarr tab roots are spelled by the tabs they mount', () {
      expect(
        ServiceRoutes.lidarrOverview,
        '${ServiceRoutes.lidarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.lidarrLibrary,
        '${ServiceRoutes.lidarr}/${ServiceTab.library.segment}',
      );
      expect(
        ServiceRoutes.lidarrArtistBase,
        startsWith('${ServiceRoutes.lidarrLibrary}/'),
      );
    });

    test('the Readarr tab roots are spelled by the tabs they mount', () {
      expect(
        ServiceRoutes.readarrOverview,
        '${ServiceRoutes.readarr}/${ServiceTab.overview.segment}',
      );
      // Unchanged by the migration, and that is the assertion: the author list
      // was already at this address as a pushed page, so every link that ever
      // pointed at it still resolves, now to the Library tab.
      expect(ServiceRoutes.readarrLibrary, '/stack/readarr/library');
      expect(
        ServiceRoutes.readarrLibrary,
        '${ServiceRoutes.readarr}/${ServiceTab.library.segment}',
      );
    });

    test('the qBittorrent tab roots are spelled by the tabs they mount', () {
      // Same tie as the four \*arr, and it has to be its own case for the same
      // reason: these are `const` literals precisely because an enum instance's
      // field is not a compile-time constant, so there is nothing to iterate
      // that would not defeat the point.
      expect(
        ServiceRoutes.qbittorrentOverview,
        '${ServiceRoutes.qbittorrent}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.qbittorrentQueue,
        '${ServiceRoutes.qbittorrent}/${ServiceTab.queue.segment}',
      );
      expect(
        ServiceRoutes.qbittorrentRss,
        '${ServiceRoutes.qbittorrent}/${ServiceTab.rss.segment}',
      );
    });

    test('the torrent detail hangs off the Queue tab', () {
      // It used to be `/dashboard/qbittorrent/torrent/<hash>`, a sibling of
      // nothing. Every link to a torrent in the app is built by this helper:
      // the list row and the Dashboard's activity readout, so this constant is
      // what moved them all inside the branch at once.
      expect(
        ServiceRoutes.qbittorrentTorrentBase,
        startsWith('${ServiceRoutes.qbittorrentQueue}/'),
      );
      expect(
        ServiceRoutes.qbittorrentTorrent('abc123'),
        '/stack/qbittorrent/queue/torrent/abc123',
      );
    });

    test('the Transmission tab roots are spelled by the tabs they mount', () {
      // Four literals, and no detail constant under any of them: the torrent
      // list expands rows in place, so Queue is a leaf and there has never been
      // a page to push from it.
      expect(
        ServiceRoutes.transmissionOverview,
        '${ServiceRoutes.transmission}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.transmissionQueue,
        '${ServiceRoutes.transmission}/${ServiceTab.queue.segment}',
      );
      expect(
        ServiceRoutes.transmissionLabels,
        '${ServiceRoutes.transmission}/${ServiceTab.labels.segment}',
      );
      expect(
        ServiceRoutes.transmissionSession,
        '${ServiceRoutes.transmission}/${ServiceTab.session.segment}',
      );
    });

    test('the SABnzbd tab roots are spelled by the tabs they mount', () {
      expect(
        ServiceRoutes.sabnzbdOverview,
        '${ServiceRoutes.sabnzbd}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.sabnzbdQueue,
        '${ServiceRoutes.sabnzbd}/${ServiceTab.queue.segment}',
      );
      expect(
        ServiceRoutes.sabnzbdHistory,
        '${ServiceRoutes.sabnzbd}/${ServiceTab.history.segment}',
      );
      expect(
        ServiceRoutes.sabnzbdServers,
        '${ServiceRoutes.sabnzbd}/${ServiceTab.servers.segment}',
      );
    });

    test('the NZBGet tab roots are spelled by the tabs they mount', () {
      // Five, the widest bar of the four download clients, and the one where a
      // hand-kept list is most likely to drift from the table that draws it.
      expect(
        ServiceRoutes.nzbgetOverview,
        '${ServiceRoutes.nzbget}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.nzbgetQueue,
        '${ServiceRoutes.nzbget}/${ServiceTab.queue.segment}',
      );
      expect(
        ServiceRoutes.nzbgetHistory,
        '${ServiceRoutes.nzbget}/${ServiceTab.history.segment}',
      );
      expect(
        ServiceRoutes.nzbgetFeeds,
        '${ServiceRoutes.nzbget}/${ServiceTab.feeds.segment}',
      );
      expect(
        ServiceRoutes.nzbgetMessages,
        '${ServiceRoutes.nzbget}/${ServiceTab.messages.segment}',
      );
    });

    test('the Seerr tab roots are spelled by the tabs they mount', () {
      // The same tie the four \*arr and the four download clients carry, and it
      // has to be its own case for the same reason: these are `const` literals
      // precisely because an enum instance's field is not a compile-time
      // constant, so there is nothing to iterate that would not defeat the
      // point.
      expect(
        ServiceRoutes.seerrOverview,
        '${ServiceRoutes.seerr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.seerrRequests,
        '${ServiceRoutes.seerr}/${ServiceTab.requests.segment}',
      );
      expect(
        ServiceRoutes.seerrIssues,
        '${ServiceRoutes.seerr}/${ServiceTab.issues.segment}',
      );
      expect(
        ServiceRoutes.seerrUsers,
        '${ServiceRoutes.seerr}/${ServiceTab.users.segment}',
      );
      // Requests did not move, and that is the assertion: the all-requests list
      // was already at this address as a pushed page, so every link that ever
      // pointed at it still resolves, now to a tab.
      expect(ServiceRoutes.seerrRequests, '/stack/seerr/requests');
    });

    test('every catalogue page hangs off the Discover tab', () {
      // Discover was Seerr's fourth tab; it is the app's own now, and every
      // door and see-all of it builds its path here.
      final paths = {
        const CatalogQuery.all(CatalogKind.movie): '/discover/all/movie',
        const CatalogQuery.trending(): '/discover/trending',
        const CatalogQuery.trending(window: TrendingWindow.day):
            '/discover/trending?window=day',
        const CatalogQuery.upcoming(CatalogKind.tv): '/discover/upcoming/tv',
        const CatalogQuery.genre(CatalogKind.tv, 16, 'Animation'):
            '/discover/genre/tv/16?title=Animation',
        const CatalogQuery.network(213, 'Netflix'): '/discover/network/213',
        const CatalogQuery.studio(41077, 'A24'): '/discover/studio/41077',
        const CatalogQuery.keyword(CatalogKind.movie, 4379, 'Time travel'):
            '/discover/keyword/movie/4379?title=Time+travel',
        const CatalogQuery.language(CatalogKind.tv, 'ko', 'Korean'):
            '/discover/language/tv/ko',
        const CatalogQuery.decade(CatalogKind.movie, 1990):
            '/discover/decade/movie/1990',
      };
      for (final MapEntry(key: query, value: path) in paths.entries) {
        expect(ServiceRoutes.discoverCatalog(query), path);
      }
    });

    test(
      'the order and the filters are the page\'s own, never the path\'s',
      () {
        const query = CatalogQuery.genre(CatalogKind.movie, 16, 'Animation');
        expect(
          ServiceRoutes.discoverCatalog(
            query
                .withSort(CatalogSort.topRated)
                .withRated(true)
                .withDecade(1990),
          ),
          ServiceRoutes.discoverCatalog(query),
        );
      },
    );

    test('a person and a collection hang beside the title they came from', () {
      // The same mount a title opened there would take: a cast member tapped
      // on a title in Activity opens in Activity, and Back returns to it.
      expect(
        ServiceRoutes.person(287, from: '/activity/media/movie/653'),
        '/activity/media/person/287',
      );
      expect(
        ServiceRoutes.collection(10, from: '/discover/media/movie/653'),
        '/discover/media/collection/10',
      );
      expect(
        ServiceRoutes.person(
          287,
          from: '${ServiceRoutes.seerrRequests}/media/tv/1399',
          heroTag: 'cast_287',
        ),
        '/stack/seerr/requests/media/person/287?heroTag=cast_287',
      );
    });

    test('exposes the Bazarr service root', () {
      expect(ServiceRoutes.bazarr, '/stack/bazarr');
    });

    test('the Bazarr tab roots are spelled by the tabs they mount', () {
      // Six literals, the widest bar in the app, tied one by one for the reason
      // every other service's are: an enum instance's field is not a
      // compile-time constant, so nothing the analyzer sees holds these to the
      // table that draws them.
      expect(
        ServiceRoutes.bazarrOverview,
        '${ServiceRoutes.bazarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.bazarrWanted,
        '${ServiceRoutes.bazarr}/${ServiceTab.wanted.segment}',
      );
      expect(
        ServiceRoutes.bazarrSeriesBase,
        '${ServiceRoutes.bazarr}/${ServiceTab.series.segment}',
      );
      expect(
        ServiceRoutes.bazarrMovieBase,
        '${ServiceRoutes.bazarr}/${ServiceTab.movies.segment}',
      );
      expect(
        ServiceRoutes.bazarrHistory,
        '${ServiceRoutes.bazarr}/${ServiceTab.history.segment}',
      );
      expect(
        ServiceRoutes.bazarrProviders,
        '${ServiceRoutes.bazarr}/${ServiceTab.providers.segment}',
      );
    });

    test('the Bazarr details hang off the tabs that own them', () {
      // Bazarr is the one service whose bar names the record types, so the
      // detail is `<tab>/:id` rather than `<tab>/<record>/:id`. The series link
      // is byte-for-byte what it always was; the film's moved from the singular
      // `movie/`, and every link to one in the app is built here.
      expect(ServiceRoutes.bazarrSeries(7), '/stack/bazarr/series/7');
      expect(
        ServiceRoutes.bazarrSeries(7, heroTag: 'ignored'),
        '/stack/bazarr/series/7?heroTag=ignored',
      );
      expect(ServiceRoutes.bazarrMovie(12), '/stack/bazarr/movies/12');
    });

    test('the Prowlarr tab roots are spelled by the tabs they mount', () {
      // `library` became `indexers`: the word the bar uses and the word the
      // page always meant. The literal is tied to the tab here because nothing
      // the analyzer sees ties them.
      expect(ServiceRoutes.prowlarr, '/stack/prowlarr');
      expect(
        ServiceRoutes.prowlarrOverview,
        '${ServiceRoutes.prowlarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.prowlarrIndexers,
        '${ServiceRoutes.prowlarr}/${ServiceTab.indexers.segment}',
      );
      expect(
        ServiceRoutes.prowlarrHistory,
        '${ServiceRoutes.prowlarr}/${ServiceTab.history.segment}',
      );
      expect(
        ServiceRoutes.prowlarrStats,
        '${ServiceRoutes.prowlarr}/${ServiceTab.stats.segment}',
      );
    });

    test('the indexer detail hangs off the Indexers tab', () {
      // Every link to an indexer in the app is built by this helper, so this
      // constant is what moved them all inside the branch at once.
      expect(
        ServiceRoutes.prowlarrIndexerBase,
        startsWith('${ServiceRoutes.prowlarrIndexers}/'),
      );
      expect(
        ServiceRoutes.prowlarrIndexer(3),
        '/stack/prowlarr/indexers/indexer/3',
      );
    });

    test('the Jellyfin tab roots are spelled by the tabs they mount', () {
      // Six literals tied to the six tabs the bar draws. Jellyfin and Plex
      // share a screen family and not a bar, so the two services need two
      // cases: a loop over both would assert a shape that is only accidentally
      // the same and would keep passing if one bar changed.
      expect(
        ServiceRoutes.jellyfinOverview,
        '${ServiceRoutes.jellyfin}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.jellyfinLibraries,
        '${ServiceRoutes.jellyfin}/${ServiceTab.libraries.segment}',
      );
      expect(
        ServiceRoutes.jellyfinUsers,
        '${ServiceRoutes.jellyfin}/${ServiceTab.users.segment}',
      );
      expect(
        ServiceRoutes.jellyfinDevices,
        '${ServiceRoutes.jellyfin}/${ServiceTab.devices.segment}',
      );
      expect(
        ServiceRoutes.jellyfinTasks,
        '${ServiceRoutes.jellyfin}/${ServiceTab.tasks.segment}',
      );
      expect(
        ServiceRoutes.jellyfinActivity,
        '${ServiceRoutes.jellyfin}/${ServiceTab.activity.segment}',
      );
    });

    test('the Plex tab roots are spelled by the tabs they mount', () {
      expect(
        ServiceRoutes.plexOverview,
        '${ServiceRoutes.plex}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.plexLibraries,
        '${ServiceRoutes.plex}/${ServiceTab.libraries.segment}',
      );
      // The one tab segment that is not simply its enum name: Plex writes it
      // "On Deck", so the URL is hyphenated rather than camel-cased away.
      expect(ServiceRoutes.plexOnDeck, '/stack/plex/on-deck');
      expect(
        ServiceRoutes.plexOnDeck,
        '${ServiceRoutes.plex}/${ServiceTab.onDeck.segment}',
      );
      expect(
        ServiceRoutes.plexActivities,
        '${ServiceRoutes.plex}/${ServiceTab.activities.segment}',
      );
      expect(
        ServiceRoutes.plexDevices,
        '${ServiceRoutes.plex}/${ServiceTab.devices.segment}',
      );
      expect(
        ServiceRoutes.plexPlaylists,
        '${ServiceRoutes.plex}/${ServiceTab.playlists.segment}',
      );
    });

    test('both media server details hang off the Libraries tab', () {
      // Every link to a library or an item is built by these four helpers: the
      // library row, the poster tile, the global search result and the
      // availability slot on a Radarr or Sonarr detail, so these constants are
      // what moved them all inside the branch at once. The browse's own base
      // *is* the tab root, the way Bazarr's Series tab is also its series base.
      expect(
        ServiceRoutes.jellyfinLibrary('f137a2dd'),
        '/stack/jellyfin/libraries/f137a2dd',
      );
      expect(
        ServiceRoutes.jellyfinLibrary('f137a2dd', title: 'Films'),
        '/stack/jellyfin/libraries/f137a2dd?title=Films',
      );
      expect(
        ServiceRoutes.jellyfinItemBase,
        startsWith('${ServiceRoutes.jellyfinLibraries}/'),
      );
      expect(
        ServiceRoutes.jellyfinItem('abc-123'),
        '/stack/jellyfin/libraries/item/abc-123',
      );

      expect(
        ServiceRoutes.plexLibrary('3', title: 'TV Shows'),
        '/stack/plex/libraries/3?title=TV+Shows',
      );
      expect(
        ServiceRoutes.plexItemBase,
        startsWith('${ServiceRoutes.plexLibraries}/'),
      );
      expect(ServiceRoutes.plexItem('9421'), '/stack/plex/libraries/item/9421');
    });

    test('a media server page names its connection only when given one', () {
      // `?i=` is what lets a page read one connection without moving the
      // lens; absent, the page reads the active one, which is what every old
      // link and deep link means.
      expect(
        ServiceRoutes.jellyfinItem('abc-123', instanceId: 'cabin'),
        '/stack/jellyfin/libraries/item/abc-123?i=cabin',
      );
      expect(
        ServiceRoutes.streamItem(ServiceKey.plex, '9421', instanceId: 'plex-2'),
        '/stack/plex/libraries/item/9421?i=plex-2',
      );
      expect(
        ServiceRoutes.streamItem(ServiceKey.plex, '9421', instanceId: ''),
        ServiceRoutes.plexItem('9421'),
      );
      expect(
        ServiceRoutes.plexLibrary('3', title: 'TV Shows', instanceId: 'plex-2'),
        '/stack/plex/libraries/3?title=TV+Shows&i=plex-2',
      );
      expect(
        ServiceRoutes.jellyfinLibrary('f137a2dd', instanceId: 'cabin'),
        '/stack/jellyfin/libraries/f137a2dd?i=cabin',
      );
      expect(
        ServiceRoutes.streamActivity(ServiceKey.jellyfin, instanceId: 'cabin'),
        '${ServiceRoutes.jellyfinActivity}?i=cabin',
      );
      expect(
        ServiceRoutes.streamActivity(ServiceKey.plex),
        ServiceRoutes.plexActivities,
      );
    });

    group('a media server\'s routes, asked by capability', () {
      // Each media server must land under its own prefix: the ternaries these
      // replaced sent every one that was not Jellyfin (or not Plex) to the
      // other's pages.
      for (final service in mediaServers) {
        test('${service.name}: item, library and playbacks are its own', () {
          final base = ServiceRoutes.forService(service);
          expect(
            ServiceRoutes.streamItem(service, 'x1', instanceId: 'i2'),
            startsWith('$base/libraries/item/x1'),
          );
          expect(
            ServiceRoutes.streamItem(service, 'x1', instanceId: 'i2'),
            endsWith('?i=i2'),
          );
          expect(
            ServiceRoutes.streamLibrary(service, '7', instanceId: 'i2'),
            startsWith('$base/libraries/7'),
          );
          expect(
            ServiceRoutes.streamActivity(service, instanceId: 'i2'),
            allOf(startsWith('$base/'), endsWith('?i=i2')),
          );
        });
      }

      test('a service that is no media server is refused by name, never '
          'routed to Plex or Jellyfin', () {
        for (final service in ServiceKey.values.where(
          (s) => !s.isMediaServer,
        )) {
          final named = throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'message',
              contains(service.name),
            ),
          );
          expect(
            () => ServiceRoutes.streamItem(service, 'x1'),
            named,
            reason: service.name,
          );
          expect(
            () => ServiceRoutes.streamLibrary(service, '7'),
            named,
            reason: service.name,
          );
          expect(
            () => ServiceRoutes.streamActivity(service),
            named,
            reason: service.name,
          );
        }
      });
    });

    test('the Dockge tab roots are spelled by the tabs they mount', () {
      // The same tie every other service carries, and it has to be its own
      // case for the same reason: these are `const` literals precisely because
      // an enum instance's field is not a compile-time constant, so there is
      // nothing to iterate that would not defeat the point.
      expect(
        ServiceRoutes.dockgeOverview,
        '${ServiceRoutes.dockge}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.dockgeStacks,
        '${ServiceRoutes.dockge}/${ServiceTab.stacks.segment}',
      );
      expect(
        ServiceRoutes.dockgeTerminal,
        '${ServiceRoutes.dockge}/${ServiceTab.terminal.segment}',
      );
    });

    test('the whole stack tree hangs off the Stacks tab', () {
      // Three routes that used to hang off the service root, because a
      // one-page service had nowhere else to hang them. All three are reached
      // from the Stacks list and nowhere else, so a drift here moves every
      // stack link in the app out of the branch that owns it.
      expect(
        ServiceRoutes.dockgeStackBase,
        startsWith('${ServiceRoutes.dockgeStacks}/'),
      );
      expect(
        ServiceRoutes.dockgeStack('immich'),
        '/stack/dockge/stacks/stack/immich',
      );
      expect(
        ServiceRoutes.dockgeStackEdit('immich'),
        '/stack/dockge/stacks/stack/immich/edit',
      );
      expect(ServiceRoutes.dockgeNewStack, '${ServiceRoutes.dockgeStacks}/new');
    });

    test('the Unraid tab roots are spelled by the tabs they mount', () {
      // Six, and not one of them moved: the service shipped exactly one path:
      // its bare root, so this table is the whole of Unraid's URL surface.
      expect(
        ServiceRoutes.unraidOverview,
        '${ServiceRoutes.unraid}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.unraidArray,
        '${ServiceRoutes.unraid}/${ServiceTab.array.segment}',
      );
      expect(
        ServiceRoutes.unraidDocker,
        '${ServiceRoutes.unraid}/${ServiceTab.docker.segment}',
      );
      expect(
        ServiceRoutes.unraidVms,
        '${ServiceRoutes.unraid}/${ServiceTab.vms.segment}',
      );
      expect(
        ServiceRoutes.unraidNotifications,
        '${ServiceRoutes.unraid}/${ServiceTab.notifications.segment}',
      );
      expect(
        ServiceRoutes.unraidShares,
        '${ServiceRoutes.unraid}/${ServiceTab.shares.segment}',
      );
      // `vms` and not `vMs`: the segment is the tab's, and the breadcrumb that
      // title-cased whatever it found is exactly what `ServiceTab` exists to
      // stop.
      expect(ServiceRoutes.unraidVms, '/stack/unraid/vms');
    });

    test('the NPM tab roots are spelled by the tabs they mount', () {
      // Five, three of them hyphenated where the label has a space. The
      // spelling is `ServiceTab.segment`'s and not one invented here, which is
      // the half of this case that a hand-written literal can silently lose:
      // `proxyHosts` would resolve to nothing and read as a 404 on a tab the
      // bar still draws.
      expect(
        ServiceRoutes.npmOverview,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.npmProxyHosts,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.proxyHosts.segment}',
      );
      expect(
        ServiceRoutes.npmCertificates,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.certificates.segment}',
      );
      expect(
        ServiceRoutes.npmAccessLists,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.accessLists.segment}',
      );
      expect(
        ServiceRoutes.npmAuditLog,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.auditLog.segment}',
      );
      // Written out once, because two irregularities meet here: the service
      // segment is `npm` rather than the enum name, and three tab segments are
      // hyphenated.
      expect(ServiceRoutes.npmProxyHosts, '/stack/npm/proxy-hosts');
      expect(ServiceRoutes.npmAccessLists, '/stack/npm/access-lists');
      expect(ServiceRoutes.npmAuditLog, '/stack/npm/audit-log');
    });

    test('every tab of the three infrastructure services has a constant', () {
      // The other half of the tie above: those cases prove each constant is
      // spelled by a tab, this one proves no tab was left without one. A bar
      // entry with no route constant is a link nobody can build.
      const routes = {
        ServiceKey.dockge: [
          ServiceRoutes.dockgeOverview,
          ServiceRoutes.dockgeStacks,
          ServiceRoutes.dockgeTerminal,
        ],
        ServiceKey.unraid: [
          ServiceRoutes.unraidOverview,
          ServiceRoutes.unraidArray,
          ServiceRoutes.unraidDocker,
          ServiceRoutes.unraidVms,
          ServiceRoutes.unraidNotifications,
          ServiceRoutes.unraidShares,
        ],
        ServiceKey.nginxProxyManager: [
          ServiceRoutes.npmOverview,
          ServiceRoutes.npmProxyHosts,
          ServiceRoutes.npmCertificates,
          ServiceRoutes.npmAccessLists,
          ServiceRoutes.npmAuditLog,
        ],
      };

      for (final entry in routes.entries) {
        final tabs = tabsFor(entry.key)!;
        expect(entry.value, hasLength(tabs.length), reason: entry.key.name);
        for (var i = 0; i < tabs.length; i++) {
          expect(
            entry.value[i],
            '${ServiceRoutes.forService(entry.key)}/${tabs[i].segment}',
            reason: '${entry.key.name} tab ${tabs[i].name}',
          );
        }
      }
    });

    test('Prowlarr settings is not a tab and did not move', () {
      // Decision 26: the four field-driven sections are one page, not a fifth
      // bar entry. It stays a page pushed from the service, at the address it
      // always had, so every link into it still resolves.
      expect(ServiceRoutes.prowlarrSettings, '/stack/prowlarr/settings');
      expect(
        ServiceTab.fromSegment('settings'),
        isNull,
        reason: 'settings must not become a tab segment by accident',
      );
    });

    group('a title opens where it was opened from', () {
      const film = MediaKey.movie(653);

      test('under the service tab, for a service that mounts titles', () {
        expect(
          ServiceRoutes.media(film, from: ServiceRoutes.radarrLibrary),
          '/stack/radarr/library/media/movie/653',
        );
        // Deeper in the tab, the tab: one Navigator, so the poster flies.
        expect(
          ServiceRoutes.media(
            film,
            from: '${ServiceRoutes.seerrRequests}/media/person/42',
          ),
          '/stack/seerr/requests/media/movie/653',
        );
        // From a title's page, its own mount: More like this stays put.
        expect(
          ServiceRoutes.media(
            const MediaKey.tv(1399),
            from: '/stack/jellyfin/libraries/media/movie/653',
          ),
          '/stack/jellyfin/libraries/media/tv/1399',
        );
      });

      test('under the top-level tab otherwise', () {
        expect(
          ServiceRoutes.media(film, from: ServiceRoutes.stack),
          '/stack/media/movie/653',
        );
        expect(
          ServiceRoutes.media(film, from: ServiceRoutes.bazarrWanted),
          '/stack/media/movie/653',
          reason: 'Bazarr keeps its own pages and mounts no titles',
        );
        expect(
          ServiceRoutes.media(film, from: '/stack/media/movie/1'),
          '/stack/media/movie/653',
        );
        // The Home and the requester's Requests open titles in place too:
        // each is a tab with a navigator of its own, so a title opened there
        // hangs under it and Back returns to the page it came from.
        expect(
          ServiceRoutes.media(film, from: ServiceRoutes.home),
          '/home/media/movie/653',
        );
        expect(
          ServiceRoutes.media(film, from: '/home/media/movie/1'),
          '/home/media/movie/653',
        );
        expect(
          ServiceRoutes.media(film, from: ServiceRoutes.requests),
          '/requests/media/movie/653',
        );
        expect(
          ServiceRoutes.media(film, from: ServiceRoutes.activity),
          '/activity/media/movie/653',
        );
        expect(
          ServiceRoutes.media(film, from: '/activity/media/movie/1'),
          '/activity/media/movie/653',
        );
        // Each of Activity's views, a request list's connection and the
        // blocklist included, is the Activity tab: the title opens under it,
        // and Back returns to the view.
        for (final view in [
          ServiceRoutes.activityDownloads,
          ServiceRoutes.activityRequests,
          '${ServiceRoutes.activityRequests}?i=seerr-cabin',
          ServiceRoutes.activityHistory,
          ServiceRoutes.activityNeedsYou,
          ServiceRoutes.activityBlocklist,
        ]) {
          expect(
            ServiceRoutes.media(film, from: view),
            '/activity/media/movie/653',
            reason: view,
          );
        }
        expect(
          ServiceRoutes.media(film, from: ServiceRoutes.discover),
          '/discover/media/movie/653',
        );
        expect(
          ServiceRoutes.media(film, from: '/discover/media/person/287'),
          '/discover/media/movie/653',
          reason: 'a title opened from a person stays in the tab',
        );
      });

      test('at the root from a page above the tabs', () {
        // A title's own page at the root sits over the tabs: pushed into
        // one, the title would open underneath it. (`/activity/movies` was
        // such a page once; it redirects now, and any `/activity/...` is the
        // Activity tab.)
        expect(
          ServiceRoutes.media(film, from: '/media/movie/1'),
          '/media/movie/653',
        );
        expect(
          ServiceRoutes.media(film, from: '/import/browse'),
          '/media/movie/653',
        );
      });

      test('with its connection, its tile and Sonarr v3\'s key', () {
        expect(
          ServiceRoutes.media(
            const MediaKey.tvdb(300001),
            from: ServiceRoutes.sonarrLibrary,
            focus: 'sonarr-4k',
            heroTag: 'series_7',
            posterUrl: 'https://image.tmdb.org/t/p/w300/a b.jpg',
          ),
          '/stack/sonarr/library/media/tv/tvdb/300001'
          '?i=sonarr-4k&heroTag=series_7'
          '&posterUrl=https%3A%2F%2Fimage.tmdb.org%2Ft%2Fp%2Fw300%2Fa+b.jpg',
        );
      });

      test('on a season of a series, when it names one', () {
        const series = MediaKey.tv(1399);
        expect(
          ServiceRoutes.media(
            series,
            from: ServiceRoutes.jellyfinLibraries,
            focus: 'jellyfin',
            season: 2,
          ),
          '/stack/jellyfin/libraries/media/tv/1399?i=jellyfin&season=2',
        );
        expect(
          ServiceRoutes.mediaRoot(series, focus: 'plex', season: 0),
          '/media/tv/1399?i=plex&season=0',
          reason: 'the specials are season 0, and a season all the same',
        );
        // No season, or one nobody numbers that way: the link of old.
        expect(
          ServiceRoutes.media(series, from: ServiceRoutes.jellyfinLibraries),
          '/stack/jellyfin/libraries/media/tv/1399',
        );
        expect(
          ServiceRoutes.media(
            series,
            from: ServiceRoutes.jellyfinLibraries,
            season: -1,
          ),
          '/stack/jellyfin/libraries/media/tv/1399',
        );
      });

      test('the season a location asks for is a whole number from 0', () {
        int? asked(String location) =>
            ServiceRoutes.mediaSeasonOf(Uri.parse(location));
        expect(asked('/media/tv/1399?season=3'), 3);
        expect(asked('/media/tv/1399?i=plex&season=0'), 0);
        expect(asked('/media/tv/1399'), isNull);
        expect(asked('/media/tv/1399?season='), isNull);
        expect(asked('/media/tv/1399?season=two'), isNull);
        expect(asked('/media/tv/1399?season=-1'), isNull);
        expect(asked('/media/tv/1399?season=1.5'), isNull);
      });
    });
  });
}
