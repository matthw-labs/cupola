import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/network/route_poster.dart';
import 'package:cupola/core/platform/secure_screen.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_bar_action.dart';
import 'package:cupola/features/services/presentation/connection_in_view.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/media/presentation/arr_title_opener.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/shell/domain/shell_branches.dart';
import 'package:cupola/features/shell/presentation/branch_transition.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';
import 'package:cupola/features/shell/presentation/unknown_place_screen.dart';
import 'package:cupola/features/discover/presentation/seerr_overview_screen.dart';
import 'package:cupola/features/discover/presentation/seerr_admin_screens.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_blocklist_page.dart';
import 'package:cupola/features/activity/presentation/activity_needs_you_page.dart';
import 'package:cupola/features/activity/presentation/download_page.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/activity/presentation/arr_tab_screen.dart';
import 'package:cupola/features/activity/presentation/arr_calendar_screen.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/series/presentation/sonarr_overview_screen.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/music/presentation/artist_page.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/author_page.dart';
import 'package:cupola/features/music/presentation/lidarr_overview_screen.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/discover_index.dart';
import 'package:cupola/features/discover/domain/seerr_invite.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart'
    show DiscoverIndexPage;
import 'package:cupola/features/discover/presentation/calendar_page.dart';
import 'package:cupola/features/discover/presentation/catalog_page.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_screen.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/settings/presentation/settings_appearance_screen.dart';
import 'package:cupola/features/settings/presentation/settings_hints_screen.dart';
import 'package:cupola/features/outside/domain/outside_link.dart';
import 'package:cupola/features/outside/presentation/settings_notifications_screen.dart';
import 'package:cupola/features/settings/presentation/settings_home_screen.dart';
import 'package:cupola/features/settings/presentation/settings_region_screen.dart';
import 'package:cupola/features/settings/presentation/requester_account_page.dart';
import 'package:cupola/features/settings/presentation/settings_connections_screen.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';
import 'package:cupola/features/settings/presentation/trusted_certificates_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/import/presentation/manual_import_locate_screen.dart';
import 'package:cupola/features/import/presentation/manual_import_progress_screen.dart';
import 'package:cupola/features/import/presentation/blocked_import_review_page.dart';
import 'package:cupola/features/import/presentation/manual_import_review_screen.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/home/presentation/edit_home_page.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/requests/presentation/requests_screen.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/onboarding/presentation/requester_sign_in_screen.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';
import 'package:cupola/features/pairing/presentation/pair_offer_screen.dart';
import 'package:cupola/features/pairing/presentation/pair_receive_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_overview_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/torrent_detail_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_screen.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_library_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_movie_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_overview_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_history_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_providers_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_overview_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_library_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_detail_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_settings_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider_list_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_app_profiles_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_tags_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_stats_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_overview_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_library_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_activity_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_history_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_overview_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_tab_screens.dart';
import 'package:cupola/features/npm/presentation/npm_advanced_config_screen.dart';
import 'package:cupola/features/npm/presentation/npm_overview_screen.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_overview_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_tab_screens.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_overview_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_tab_screens.dart';
import 'package:cupola/features/stream/presentation/stream_libraries_screen.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';
import 'package:cupola/features/stream/presentation/stream_item_screen.dart';
import 'package:cupola/features/stream/presentation/stream_library_screen.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/plex/presentation/plex_tab_screens.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_screen.dart';
import 'package:cupola/features/unraid/presentation/unraid_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_series_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_overview_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_stack_detail_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_stack_edit_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_terminal_screen.dart';
import 'package:cupola/features/truenas/presentation/truenas_hub_screen.dart';
import 'package:cupola/features/truenas/presentation/dashboard/truenas_dashboard_screen.dart';
import 'package:cupola/features/truenas/presentation/storage/truenas_storage_screen.dart';
import 'package:cupola/features/truenas/presentation/storage/truenas_pool_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_datasets_screen.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/shares/truenas_shares_screen.dart';
import 'package:cupola/features/truenas/presentation/data_protection/truenas_data_protection_screen.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_screen.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_apps_screen.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_app_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/reporting/truenas_reporting_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_hub_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_services_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_credentials_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_config_screens.dart';
import 'package:cupola/features/discover/presentation/collection_page.dart';
import 'package:cupola/features/discover/presentation/person_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

const double _serviceHomeTopPadding = kToolbarHeight;

/// Room the service band AND the tab bar take above a tab's content.
///
/// Composed rather than written out: the two bands stack, so a hosted screen
/// inside a tabbed service has to clear both, and a literal here would be a
/// second place for the bar's height to be wrong.
///
/// It does not count the status bar's inset, which the band consumes: a
/// hosted screen with no `SafeArea` adds `MediaQuery.paddingOf(context).top`
/// to it, or its first row starts under the tab bar on a phone.
/// `ServiceListPage` adds it itself, so a screen built on it passes this
/// constant on unchanged.
///
/// Nothing stops a new hosted screen forgetting the inset except
/// `test/features/services/presentation/service_tab_inset_guard_test.dart`,
/// which reads every widget handed this constant here and asks for a case in
/// `service_tab_inset_test.dart` (the screen on a phone with a status bar,
/// its first content below the tab bar), or an excuse with a reason the guard
/// can check.
const double _serviceTabTopPadding =
    _serviceHomeTopPadding + ServiceTabBar.height;

/// The page for a top-level tab: a short fade instead of the platform default.
///
/// Android's default here was [ZoomPageTransitionsBuilder], and on device it
/// was the tab switch's whole stutter: every switch spent 5–8 frames at
/// 30–38ms of raster scaling and cross-fading two full opaque screens: the
/// same cost on every switch, so not shader warm-up. Tabs are siblings, not a
/// hierarchy; a fade is what Material prescribes for top-level destinations,
/// and it costs one blend per frame instead of the Zoom's layered scale.
Page<void> _tabPage(GoRouterState state, Widget child, {LocalKey? key}) =>
    CustomTransitionPage(
      key: key ?? state.pageKey,
      transitionDuration: AppAnimation.durationSm,
      reverseTransitionDuration: AppAnimation.durationSm,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
            child: child,
          ),
      child: child,
    );

/// A route whose page is a plain [RouteUtils.cupertinoPage] around [child].
///
/// Collapses the `pageBuilder: (context, state) => RouteUtils.cupertinoPage(
/// key: state.pageKey, child: ...)` shape that every non-redirecting page
/// route repeats. `state.pageKey` stays the page key, so go_router's page
/// identity is unchanged.
///
/// Routes whose page is *not* plain: the ones that return a redirect page for
/// bad params ([_libraryDetailPage], [_manualImportPage])
/// or that swap between `builder` and `pageBuilder`: they keep their long form.
GoRoute _page(
  String path,
  Widget Function(GoRouterState state) child, {
  GoRouterRedirect? redirect,
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  redirect: redirect,
  routes: routes,
  // Named by its location, so a header above the navigator can tell which
  // page stands beside a tablet's pane (`SidePaneScope.hostNameOf`).
  pageBuilder: (context, state) => RouteUtils.cupertinoPage(
    key: state.pageKey,
    name: state.matchedLocation,
    child: child(state),
  ),
);

/// A row of Settings' list (`SettingsMasterDetail.sections`): beside the list
/// it takes the place of the section before it, with no slide and no back
/// button; without the list it is a [_page] (`SettingsSectionPage`).
GoRoute _section(String path, Widget Function(GoRouterState state) child) =>
    GoRoute(
      path: path,
      pageBuilder: (context, state) => SettingsSectionPage(
        key: state.pageKey,
        name: state.matchedLocation,
        child: child(state),
      ),
    );

/// The one page a title has, at the title's own location (`MediaKey.location`)
/// under a mount. `ServiceRoutes.mediaMountServices` says where it hangs, and
/// why more than once; [prefix] is `/` for the root mount.
///
/// A malformed id falls back to the mount, the tab the page would have been
/// pushed from, like every other detail in this file. `tv/tvdb/:id` comes
/// before `tv/:id` for the reader only: `tv/:id` takes one segment, so it
/// could never complete `tv/tvdb/300001`.
List<GoRoute> _mediaRoutes({String prefix = ''}) => [
  for (final (path, kind, byTvdb) in const [
    ('media/movie/:id', 'movie', false),
    ('media/tv/tvdb/:id', 'tv', true),
    ('media/tv/:id', 'tv', false),
  ])
    GoRoute(
      path: '$prefix$path',
      redirect: (context, state) =>
          MediaKey.parse(kind, state.pathParameters['id']!, byTvdb: byTvdb) ==
              null
          ? _mediaMountOrHome(state.uri.path)
          : null,
      // On a tablet the title is drawn beside the page it was opened from,
      // and its place in this navigator is an empty slot (`MediaSplit`). The
      // root mount is outside the shell, with no pane to draw it in.
      pageBuilder: (context, state) =>
          prefix.isEmpty && MediaSplit.splits(context)
          ? SidePaneSlotPage(key: state.pageKey, name: state.uri.toString())
          : RouteUtils.cupertinoPage(
              key: state.pageKey,
              child: MediaPage(
                mediaKey: MediaKey.parse(
                  kind,
                  state.pathParameters['id']!,
                  byTvdb: byTvdb,
                )!,
                focus: state.uri.queryParameters['i'],
                season: ServiceRoutes.mediaSeasonOf(state.uri),
                heroTag: state.uri.queryParameters['heroTag'],
                // go_router has already decoded it; decoding again would break a
                // poster URL with a literal `%` in it.
                // A deep link can carry any URL here ([RoutePoster]).
                posterUrl: RoutePoster.accept(
                  state.uri.queryParameters['posterUrl'],
                ),
              ),
            ),
    ),
  // The two pages a title links to, hung beside it: a cast member or a
  // collection opened from a title stays in the tab the title is in, and Back
  // returns to the title (`ServiceRoutes.person`, `ServiceRoutes.collection`).
  // On a tablet they are drawn in the pane as a title is.
  _besideTitle(
    '${prefix}media/person/:id',
    (state) => PersonPage(
      personId: RouteUtils.safeIntParam(state, 'id')!,
      heroTag: state.uri.queryParameters['heroTag'],
      initialProfileUrl: RoutePoster.accept(
        state.uri.queryParameters['posterUrl'],
      ),
    ),
    paned: prefix.isEmpty,
  ),
  _besideTitle(
    '${prefix}media/collection/:id',
    (state) => CollectionPage(
      collectionId: RouteUtils.safeIntParam(state, 'id')!,
      heroTag: state.uri.queryParameters['heroTag'],
    ),
    paned: prefix.isEmpty,
  ),
];

/// A page a title links to, at [path] under a mount: [_page], and on a tablet
/// ([paned], every mount but the root) an empty slot whose page the pane
/// beside the list draws (`MediaSplit.pageOf`), as a title's. A malformed id
/// falls back to the mount.
GoRoute _besideTitle(
  String path,
  Widget Function(GoRouterState state) child, {
  required bool paned,
}) => GoRoute(
  path: path,
  redirect: (context, state) => RouteUtils.safeIntParam(state, 'id') == null
      ? _mediaMountOrHome(state.uri.path)
      : null,
  pageBuilder: (context, state) => paned && MediaSplit.splits(context)
      ? SidePaneSlotPage(key: state.pageKey, name: state.uri.toString())
      : RouteUtils.cupertinoPage(
          key: state.pageKey,
          name: state.matchedLocation,
          child: child(state),
        ),
);

/// The mount a title's location hangs off, or the Home for the root one.
String _mediaMountOrHome(String path) =>
    switch (ServiceRoutes.mediaMountFor(path)) {
      '' => ServiceRoutes.home,
      final mount => mount,
    };

/// A service tab that can open a title: [_page] with the title's page hung
/// under it. Every tab of a service in `ServiceRoutes.mediaMountServices` is
/// one, because a title opened anywhere in that service lands under the tab
/// it was opened from (`ServiceRoutes.mediaMountFor`).
GoRoute _titledTab(
  String path,
  Widget Function(GoRouterState state) child, {
  GoRouterRedirect? redirect,
  List<RouteBase> routes = const [],
}) => _page(
  path,
  child,
  redirect: redirect,
  routes: [...routes, ..._mediaRoutes()],
);

Page<void> _libraryDetailPage<T>(
  GoRouterState state, {
  required String heroPrefix,
  required String fallbackLocation,
  required Widget Function(
    int id,
    String heroTag,
    T? initialItem,
    String? instanceId,
  )
  buildChild,
}) {
  final id = RouteUtils.safeIntParam(state, 'id');
  if (id == null) {
    return RouteUtils.redirectPage(
      key: state.pageKey,
      location: fallbackLocation,
    );
  }
  final item = RouteUtils.safeExtra<T>(state);
  final heroTag = state.uri.queryParameters['heroTag'] ?? '${heroPrefix}_$id';
  // Null when the link did not name one, which is every link that predates a
  // service being able to have two: see `ServiceRoutes` for why this rides in
  // the query rather than in a path segment or in `extra`.
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: buildChild(id, heroTag, item, state.uri.queryParameters['i']),
  );
}

String _redirectLegacyManualImport(GoRouterState state) {
  return Uri(
    path: manualImportReviewPath,
    queryParameters: state.uri.queryParameters.isEmpty
        ? null
        : state.uri.queryParameters,
  ).toString();
}

Page<void> _manualImportPage(
  GoRouterState state,
  Widget Function(ServiceKey service, int? targetId, String? instanceId)
  buildChild,
) {
  final service = manualImportServiceFromRoute(
    state.uri.queryParameters['service'],
  );
  if (service == null) {
    return RouteUtils.redirectPage(key: state.pageKey, location: '/activity');
  }

  final targetId = int.tryParse(state.uri.queryParameters['targetId'] ?? '');
  // `?i=` names the connection the wizard is bound to, exactly as
  // `_libraryDetailPage` reads it for the detail routes. It has to be read
  // here or `manualImportLocation`'s whole `instanceId` argument is inert: a
  // failed-import row on a non-lensed connection would open a wizard that
  // re-resolves the service through the lens, browse the wrong server's disk
  // and move the files into the wrong library. Null when the link named none,
  // which is every link that predates a service being able to have two.
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: buildChild(service, targetId, state.uri.queryParameters['i']),
  );
}

/// A tree of link shapes the app no longer draws at, kept so each one lands
/// where its page lives now, in one hop with its query intact.
///
/// Every node is redirect-only, and the children exist for one reason: a
/// redirect cannot run until something matches, so a shape with no route to
/// match would 404 instead of being rewritten. Nothing in this tree builds.
GoRoute _rewriteTree(
  String path,
  List<String> tails,
  String Function(Uri uri) rewrite,
) {
  String? redirect(BuildContext context, GoRouterState state) =>
      rewrite(state.uri);
  return GoRoute(
    path: path,
    redirect: redirect,
    routes: [for (final tail in tails) GoRoute(path: tail, redirect: redirect)],
  );
}

/// A catalogue page of the Discover tab, its question read from the path
/// alone (`catalogQueryFor`); parameters it cannot read go back to the atrium.
GoRoute _catalogPage(String path, CatalogBase base) {
  CatalogQuery? read(GoRouterState state) =>
      catalogQueryFor(base, state.pathParameters, state.uri.queryParameters);
  return _page(
    path,
    (state) => CatalogPage(query: read(state)!),
    redirect: (context, state) =>
        read(state) == null ? ServiceRoutes.discover : null,
  );
}

/// Where Discover used to live: the fourth tab of Seerr's room.
const _seerrDiscover = '${ServiceRoutes.seerr}/discover';

/// Every shape Seerr's room ever linked to under Discover, as tails of the
/// node it hung off. `tv/all` before `tv/:id`: routes match in declaration
/// order, and the other way round `tv/all` is a title whose id is `all`.
const _discoverTails = [
  'movies/all',
  'tv/all',
  'trending/all',
  'genre/:mediaType/:genreId',
  'movie/:id',
  'tv/:id',
  'person/:id',
  'collection/:id',
  'media/movie/:id',
  'media/tv/tvdb/:id',
  'media/tv/:id',
  'media/person/:id',
  'media/collection/:id',
];

/// [uri], a link under [base] in one of the [_discoverTails] shapes, rewritten
/// to the same page in the Discover tab. The bare details Seerr shipped
/// (`movie/603`, `person/287`) are pages hung beside a title now
/// (`media/movie/603`, `media/person/287`).
String _toDiscover(Uri uri, String base) {
  final tail = Uri.parse(uri.path.substring(base.length)).pathSegments;
  final path = switch (tail) {
    [] => ServiceRoutes.discover,
    // The three see-alls are catalogue pages now.
    ['movies', 'all'] => '${ServiceRoutes.discover}/all/movie',
    ['tv', 'all'] => '${ServiceRoutes.discover}/all/tv',
    ['trending', 'all'] => '${ServiceRoutes.discover}/trending',
    // `tv/all` is a see-all, not a series whose id is the word `all`.
    [final kind, final id]
        when id != 'all' &&
            const {'movie', 'tv', 'person', 'collection'}.contains(kind) =>
      '${ServiceRoutes.discover}/media/$kind/$id',
    _ => '${ServiceRoutes.discover}/${tail.join('/')}',
  };
  return _preserveQuery(uri, path);
}

/// A tab's own screen: what the tab bar shows under the band, built from the
/// location so a media server's tab can read the `?i=` of a deep link.
typedef _TabScreen = Widget Function(GoRouterState state);

/// A redirect-only compatibility tail of a service node: one old spelling that
/// lands, with its query intact, on [to].
///
/// **Childless on purpose.** The matcher treats a prefix hit with no complete
/// match as no match at all, so a tail such as `movie/:id` cannot shadow
/// `library/movie/:id` inside the shell. No id validation here: the canonical
/// route inside the branch owns it, and doing it twice is two places to get it
/// wrong.
GoRoute _tail(String path, String Function(GoRouterState state) to) => GoRoute(
  path: path,
  redirect: (context, state) => _preserveQuery(state.uri, to(state)),
);

/// The detail a library tab pushes **inside its own branch**: a title, an
/// artist, an author. Pushing it keeps the branch, so leaving the service for
/// another app tab and coming back returns to the title rather than to the top
/// of the list, and the poster's Hero still flies, because the list it left and
/// the page it lands on share one Navigator.
GoRoute _libraryDetail<T>(
  String path, {
  required String heroPrefix,
  required String fallbackLocation,
  required Widget Function(
    int id,
    String heroTag,
    T? initialItem,
    String? instanceId,
  )
  buildChild,
}) => GoRoute(
  path: path,
  redirect: (context, state) =>
      RouteUtils.safeIntParam(state, 'id') == null ? fallbackLocation : null,
  pageBuilder: (context, state) => _libraryDetailPage<T>(
    state,
    heroPrefix: heroPrefix,
    fallbackLocation: fallbackLocation,
    buildChild: buildChild,
  ),
);

/// A service: one shell, one branch per tab. Every tabbed service is this and
/// differs only in the data it passes.
///
/// **Nested inside the Dashboard branch, not mounted beside it.** Everything
/// the app shell owns (the nav bar, the Portal, the whole desktop chrome)
/// hangs off the page the four-branch shell builds. A sibling shell at root
/// would replace that page, so opening a service would take the app's own
/// navigation away with it.
///
/// The service node itself builds nothing: it is a redirect-only prefix whose
/// entire job is to send the bare service path to Overview. **Its guard is
/// load-bearing.** A route-level redirect fires for every match in the list,
/// descendants included, so an unguarded one here would bounce
/// `/dashboard/radarr/library` back to Overview forever.
///
/// - [roots] is the screen of each tab. Its keys are `tabsFor(service)` and
///   nothing else, because the bar is generated from the same list and taps it
///   by index: a tab with no screen, or a screen for a tab the bar does not
///   have, is a bar and a router disagreeing. That throws while the router is
///   built, in every test that builds one, rather than lighting a tab that
///   shows nothing when somebody taps it. Branch order is `tabsFor` order.
/// - [inside] is what a tab pushes inside its branch (see [_libraryDetail]).
/// - [tails] hang off the service node before the shell: the compatibility
///   spellings ([_tail]) and whatever else is a sibling of the shell rather
///   than a tab.
/// - [scope] wraps the shell's page, above the band and the tab bar.
///
/// Every tab of a service in `ServiceRoutes.mediaMountServices` can open a
/// title ([_titledTab]); the others are plain pages ([_page]).
RouteBase _serviceRoutes(
  ServiceKey service, {
  required Map<ServiceTab, _TabScreen> roots,
  Map<ServiceTab, List<RouteBase>> inside = const {},
  List<RouteBase> tails = const [],
  Widget Function(GoRouterState state, Widget shell)? scope,
}) {
  final tabs = tabsFor(service)!;
  final stray = roots.keys.where((tab) => !tabs.contains(tab));
  if (stray.isNotEmpty) {
    throw UnsupportedError(
      '${service.name} has a screen for ${stray.map((t) => t.name).join(', ')}'
      ' and no such tab on its bar',
    );
  }
  final home = ServiceRoutes.forService(service);
  final tabRoute = ServiceRoutes.mediaMountServices.contains(service)
      ? _titledTab
      : _page;

  GoRoute root(ServiceTab tab) {
    final screen =
        roots[tab] ??
        (throw UnsupportedError(
          'ServiceTab.${tab.name} is on ${service.name}\'s bar with no '
          'branch root',
        ));
    return tabRoute(
      tab.segment,
      (state) =>
          ServiceTabScaffold(service: service, tab: tab, child: screen(state)),
      routes: inside[tab] ?? const [],
    );
  }

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == home
        ? _preserveQuery(state.uri, '$home/${ServiceTab.overview.segment}')
        : null,
    routes: [
      ...tails,
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        // `pageBuilder`, not `builder`: without it the shell's page takes the
        // platform default transition, and the push from the Dashboard into a
        // service would stop matching every other service in the app.
        pageBuilder: (context, state, navigationShell) {
          // The band is drawn above every branch navigator, so a pushed page
          // cannot cover it the way it covers the tab bar. It hides itself
          // instead (`showAppBar`): the page brings its own back control.
          final shell = ServiceHomeScreen(
            service: service,
            trailingAction: serviceBarAction(service),
            showAppBar: isServiceTabRoot(service, state.uri.path),
            child: navigationShell,
          );
          return RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: scope == null ? shell : scope(state, shell),
          );
        },
        branches: [
          for (final tab in tabs)
            StatefulShellBranch(
              navigatorKey: serviceBranchNavigatorKeyFor(service, tab),
              routes: [root(tab)],
            ),
        ],
      ),
    ],
  );
}

/// Seerr.
///
/// What is Seerr's own is the *number* of its compatibility tails. It shipped
/// more link shapes than any other service: three see-alls, a genre tree, two
/// media details, a person and a collection, and every one of them hung off the
/// service root, because the service root **was** the Discover page. Then they
/// hung off its Discover tab; now Discover is a tab of the app, and each old
/// spelling keeps a tail that rewrites to the Discover tab in a single hop,
/// query intact (`_toDiscover`). `requests` needs no tail: the all-requests
/// list was already a page at `/dashboard/seerr/requests`, which is exactly
/// where its tab mounts.
RouteBase _seerrRoutes() => _serviceRoutes(
  ServiceKey.seerr,
  tails: [
    _rewriteTree(
      'discover',
      _discoverTails,
      (uri) => _toDiscover(uri, _seerrDiscover),
    ),
    for (final tail in _discoverTails.where((t) => !t.startsWith('media/')))
      GoRoute(
        path: tail,
        redirect: (context, state) =>
            _toDiscover(state.uri, ServiceRoutes.seerr),
      ),
  ],
  roots: {
    ServiceTab.overview: (state) =>
        const SeerrOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.requests: (state) => const ServiceAllRequestsScreen(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.issues: (state) =>
        const SeerrIssuesScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.users: (state) =>
        const SeerrUsersScreen(topPadding: _serviceTabTopPadding),
  },
);

/// Radarr: the reference shape, and with Sonarr, Lidarr and Readarr the four
/// \*arr on one bar so a user who has learned one has learned the rest. The only
/// per-service facts are the record's name and its screens.
///
/// The tab-less tails are the links the app shipped before the tab model:
/// `media` was the all-list every arr carried (the whole library is a tab now,
/// so it has somewhere real to land), and the record's own spelling is the
/// second hop of every `/services/radarr/movie/42`.
RouteBase _radarrRoutes() => _serviceRoutes(
  ServiceKey.radarr,
  tails: [
    _tail('media', (_) => ServiceRoutes.radarrLibrary),
    _tail(
      'movie/:id',
      (s) => '${ServiceRoutes.radarrMovieBase}/${s.pathParameters['id']}',
    ),
  ],
  roots: {
    ServiceTab.overview: (state) =>
        const RadarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.library: (state) => const MoviesScreen(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.calendar: (state) => const ArrCalendarScreen(
      service: ServiceKey.radarr,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.queue: (state) => const ArrTabScreen(
      serviceType: ServiceType.movies,
      mode: ArrTabMode.queue,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.wanted: (state) => const ArrTabScreen(
      serviceType: ServiceType.movies,
      mode: ArrTabMode.wanted,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.history: (state) => const ArrTabScreen(
      serviceType: ServiceType.movies,
      mode: ArrTabMode.history,
      topPadding: _serviceTabTopPadding,
    ),
  },
  inside: {
    ServiceTab.library: [
      _libraryDetail<RadarrMovie>(
        'movie/:id',
        heroPrefix: 'movie',
        fallbackLocation: ServiceRoutes.radarrLibrary,
        buildChild: (id, heroTag, movie, instanceId) => ArrTitleOpener.radarr(
          movieId: id,
          heroTag: heroTag,
          instanceId: instanceId,
        ),
      ),
    ],
  },
);

/// Sonarr.
RouteBase _sonarrRoutes() => _serviceRoutes(
  ServiceKey.sonarr,
  tails: [
    _tail('media', (_) => ServiceRoutes.sonarrLibrary),
    _tail(
      'series/:id',
      (s) => '${ServiceRoutes.sonarrSeriesBase}/${s.pathParameters['id']}',
    ),
  ],
  roots: {
    ServiceTab.overview: (state) =>
        const SonarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.library: (state) => const SeriesScreen(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.calendar: (state) => const ArrCalendarScreen(
      service: ServiceKey.sonarr,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.queue: (state) => const ArrTabScreen(
      serviceType: ServiceType.series,
      mode: ArrTabMode.queue,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.wanted: (state) => const ArrTabScreen(
      serviceType: ServiceType.series,
      mode: ArrTabMode.wanted,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.history: (state) => const ArrTabScreen(
      serviceType: ServiceType.series,
      mode: ArrTabMode.history,
      topPadding: _serviceTabTopPadding,
    ),
  },
  inside: {
    ServiceTab.library: [
      _libraryDetail<SonarrSeries>(
        'series/:id',
        heroPrefix: 'series',
        fallbackLocation: ServiceRoutes.sonarrLibrary,
        buildChild: (id, heroTag, series, instanceId) => ArrTitleOpener.sonarr(
          seriesId: id,
          heroTag: heroTag,
          instanceId: instanceId,
        ),
      ),
    ],
  },
);

/// Lidarr.
RouteBase _lidarrRoutes() => _serviceRoutes(
  ServiceKey.lidarr,
  tails: [
    _tail('media', (_) => ServiceRoutes.lidarrLibrary),
    _tail(
      'artist/:id',
      (s) => '${ServiceRoutes.lidarrArtistBase}/${s.pathParameters['id']}',
    ),
  ],
  roots: {
    ServiceTab.overview: (state) =>
        const LidarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.library: (state) =>
        const MusicScreen(showAppBar: false, topPadding: _serviceTabTopPadding),
    ServiceTab.calendar: (state) => const ArrCalendarScreen(
      service: ServiceKey.lidarr,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.queue: (state) => const ArrTabScreen(
      serviceType: ServiceType.music,
      mode: ArrTabMode.queue,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.wanted: (state) => const ArrTabScreen(
      serviceType: ServiceType.music,
      mode: ArrTabMode.wanted,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.history: (state) => const ArrTabScreen(
      serviceType: ServiceType.music,
      mode: ArrTabMode.history,
      topPadding: _serviceTabTopPadding,
    ),
  },
  inside: {
    ServiceTab.library: [
      _libraryDetail<LidarrArtist>(
        'artist/:id',
        heroPrefix: 'artist',
        fallbackLocation: ServiceRoutes.lidarrLibrary,
        buildChild: (id, heroTag, artist, instanceId) => ArtistPage(
          artistId: id,
          heroTag: heroTag,
          initialArtist: artist,
          instanceId: instanceId,
        ),
      ),
    ],
  },
);

/// Readarr, the last of the four \*arr.
///
/// It needs no compatibility tails, because the only two paths it ever shipped
/// are the two the model already spells: the bare service root, which the node
/// redirects like the other three, and `/dashboard/readarr/library`, which was
/// the pushed author list and is now the Library tab's root at the same
/// address. Its Library pushes an author's page (`author/:id`), as Lidarr's
/// pushes an artist's.
///
/// Its Overview is the page written against the board, and it draws only the
/// regions the client can fill: the queue's faults, the library's backlog,
/// where the books are filed, what happened today. The two the board asks for
/// and `ReadarrService` cannot answer (`Coming up`, `Recently added`) are left
/// out, and the retired home never drew either of them.
RouteBase _readarrRoutes() => _serviceRoutes(
  ServiceKey.readarr,
  roots: {
    ServiceTab.overview: (state) =>
        const ReadarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.library: (state) => const ReadarrLibraryScreen(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.calendar: (state) => const ArrCalendarScreen(
      service: ServiceKey.readarr,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.queue: (state) => const ReadarrActivityScreen(
      mode: ReadarrActivityMode.queue,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.wanted: (state) => const ReadarrActivityScreen(
      mode: ReadarrActivityMode.wanted,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.history: (state) =>
        const ReadarrHistoryScreen(topPadding: _serviceTabTopPadding),
  },
  inside: {
    ServiceTab.library: [
      _libraryDetail<ReadarrAuthor>(
        'author/:id',
        heroPrefix: 'author',
        fallbackLocation: ServiceRoutes.readarrLibrary,
        buildChild: (id, heroTag, author, instanceId) => AuthorPage(
          authorId: id,
          heroTag: heroTag,
          initialAuthor: author,
          instanceId: instanceId,
        ),
      ),
    ],
  },
);

/// qBittorrent: the first download client on one shell and one bar.
///
/// Two things are qBittorrent's own. The torrent list was the *whole* service,
/// so what the four \*arr call Library this calls Queue and it is where the
/// detail hangs. And the transfer controls stay on the band as a
/// `trailingAction` (`serviceBarAction`): they are alternative-speed-limit and
/// add-torrent, which belong to the connection rather than to any one tab, so
/// the band carries them on all three. `torrent/:hash` is the only shape it
/// ever shipped besides its root.
RouteBase _qbittorrentRoutes() => _serviceRoutes(
  ServiceKey.qbittorrent,
  tails: [
    _tail(
      'torrent/:hash',
      (s) =>
          '${ServiceRoutes.qbittorrentTorrentBase}/${s.pathParameters['hash']}',
    ),
  ],
  roots: {
    ServiceTab.overview: (state) =>
        const QbittorrentOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.queue: (state) =>
        const QbittorrentScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.rss: (state) =>
        const QbittorrentRssScreen(topPadding: _serviceTabTopPadding),
  },
  inside: {
    ServiceTab.queue: [
      _page(
        'torrent/:hash',
        (state) =>
            TorrentDetailScreen(hash: state.pathParameters['hash'] ?? ''),
      ),
    ],
  },
);

/// Bazarr.
///
/// Two things are Bazarr's own. Its bar names the **record types** rather than
/// a Library: Series and Movies are two destinations (decision 22), so the
/// two-tab `BazarrLibraryScreen` split in half and the detail spelling is
/// `<tab>/:id`, which is why the series detail did not have to move at all.
/// And what was the service home is superseded by `BazarrOverviewScreen`.
///
/// `library` was the combined Series/Movies page; it lands on Series rather
/// than on the service root, one bar tap from the other half. Singular `movie`
/// is the pre-tab spelling.
///
/// No `heroTag` on either detail: the Bazarr lead is a figure plate, not a
/// poster, so there is no source counterpart on a Bazarr row to fly from and an
/// orphan flight would fade in from nothing. Both routes still accept the query
/// param: global search builds one for every service uniformly, and nothing
/// reads it.
RouteBase _bazarrRoutes() => _serviceRoutes(
  ServiceKey.bazarr,
  tails: [
    _tail('library', (_) => ServiceRoutes.bazarrSeriesBase),
    _tail(
      'movie/:id',
      (s) => '${ServiceRoutes.bazarrMovieBase}/${s.pathParameters['id']}',
    ),
  ],
  roots: {
    ServiceTab.overview: (state) =>
        const BazarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.wanted: (state) => const BazarrWantedScreen(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.series: (state) => const BazarrLibraryScreen.series(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.movies: (state) => const BazarrLibraryScreen.movies(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.history: (state) =>
        const BazarrHistoryScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.providers: (state) =>
        const BazarrProvidersScreen(topPadding: _serviceTabTopPadding),
  },
  inside: {
    ServiceTab.series: [
      _page(
        ':id',
        (state) => BazarrSeriesDetailScreen(
          sonarrSeriesId: RouteUtils.safeIntParam(state, 'id')!,
          initialWanted: RouteUtils.safeExtra<BazarrWantedItem>(state),
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.bazarrSeriesBase
            : null,
      ),
    ],
    ServiceTab.movies: [
      _page(
        ':id',
        (state) => BazarrMovieDetailScreen(
          radarrId: RouteUtils.safeIntParam(state, 'id')!,
          initialWanted: RouteUtils.safeExtra<BazarrWantedItem>(state),
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.bazarrMovieBase
            : null,
      ),
    ],
  },
);

/// Dockge.
///
/// Two things are Dockge's own.
///
/// **The agent lens is on the band, not on the bar** (decision 41). An agent is
/// not a *place*: it is which Dockge the rows on screen came off, which is what
/// the connection lens means everywhere else in the app. So it rides as the
/// band's `trailingAction` (`serviceBarAction`) exactly as qBittorrent's
/// transfer controls do: above every tab, because it qualifies all of them.
///
/// **The stack tree moved inside Stacks.** The detail, its compose editor and
/// the New button's editor all hung off the service root, because a one-page
/// service had nowhere else to hang them; all three are reached from the Stacks
/// list and none from anywhere else. Each old spelling keeps a childless tail.
/// The editor is declared before the detail it hangs under; neither can match
/// the other's location, but the pair reads as one rule in that order.
RouteBase _dockgeRoutes() => _serviceRoutes(
  ServiceKey.dockge,
  tails: [
    _tail(
      'stack/:name/edit',
      (s) => ServiceRoutes.dockgeStackEdit(s.pathParameters['name']!),
    ),
    _tail(
      'stack/:name',
      (s) => ServiceRoutes.dockgeStack(s.pathParameters['name']!),
    ),
    _tail('new', (_) => ServiceRoutes.dockgeNewStack),
  ],
  roots: {
    ServiceTab.overview: (state) =>
        const DockgeOverviewScreen(topPadding: _serviceTabTopPadding),
    // The list that was the whole service. Its own app bar stays off: the band
    // above draws the title and the lens, and the tab bar sits under it.
    ServiceTab.stacks: (state) =>
        const DockgeScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.terminal: (state) =>
        const DockgeTerminalScreen(topPadding: _serviceTabTopPadding),
  },
  inside: {
    ServiceTab.stacks: [
      // `new` before `stack/:name`, though nothing forces it: both are
      // literal-led, so neither can swallow the other. It is the New button's
      // destination and it reads first.
      _page('new', (state) => const DockgeStackEditScreen()),
      // A blank name falls back to the tab this page was pushed from, not to
      // the app home: the branch is where the user still is. Dockge stack names
      // are free-form strings (a Compose project directory name), so there is
      // no `safeIntParam` to run, and emptiness is the whole of what can be
      // checked.
      _page(
        'stack/:name',
        (state) => DockgeStackDetailScreen(name: state.pathParameters['name']!),
        redirect: _rejectBlankDockgeStackName,
        routes: [
          // No guard of its own: a route-level redirect fires for every
          // match under it, descendants included, so the detail's guard has
          // already run by the time this builds.
          _page(
            'edit',
            (state) =>
                DockgeStackEditScreen(name: state.pathParameters['name']!),
          ),
        ],
      ),
    ],
  },
);

String? _rejectBlankDockgeStackName(
  BuildContext context,
  GoRouterState state,
) => (state.pathParameters['name']?.trim().isEmpty ?? true)
    ? ServiceRoutes.dockgeStacks
    : null;

/// Prowlarr.
///
/// What is Prowlarr's own is **Settings**, which is not a tab (decision 26) and
/// therefore not in the shell. It hangs off the service node beside the
/// `StatefulShellRoute`, exactly where it hung off the service page before:
/// four field-driven sections, an app-profiles page and a tags page that no one
/// tab owns, pushed on the Dashboard branch's navigator as they always were. It
/// keeps its children where a compatibility tail may not, and safely: `settings`
/// is not a tab segment, so there is nothing inside the shell for it to shadow.
RouteBase _prowlarrRoutes() => _serviceRoutes(
  ServiceKey.prowlarr,
  tails: [
    _tail('library', (_) => ServiceRoutes.prowlarrIndexers),
    _tail(
      'indexer/:id',
      (s) => '${ServiceRoutes.prowlarrIndexerBase}/${s.pathParameters['id']}',
    ),
    _page(
      'settings',
      (state) => const ProwlarrSettingsScreen(),
      routes: [
        _page('sync-profiles', (state) => const ProwlarrAppProfilesScreen()),
        _page('tags', (state) => const ProwlarrTagsScreen()),
        // One route for the four field-driven sections; an unknown segment
        // falls back to the hub rather than a blank screen.
        _page(
          ':section',
          (state) => ProwlarrProviderListScreen(
            kind: ProwlarrProviderKind.fromRouteSegment(
              state.pathParameters['section']!,
            )!,
          ),
          redirect: (context, state) =>
              ProwlarrProviderKind.fromRouteSegment(
                    state.pathParameters['section'] ?? '',
                  ) ==
                  null
              ? ServiceRoutes.prowlarrSettings
              : null,
        ),
      ],
    ),
  ],
  roots: {
    ServiceTab.overview: (state) =>
        const ProwlarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.indexers: (state) => const ProwlarrLibraryScreen(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.history: (state) =>
        const ProwlarrHistoryScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.stats: (state) =>
        const ProwlarrStatsScreen(topPadding: _serviceTabTopPadding),
  },
  inside: {
    ServiceTab.indexers: [
      _page(
        'indexer/:id',
        (state) => ProwlarrIndexerDetailScreen(
          indexerId: RouteUtils.safeIntParam(state, 'id')!,
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.prowlarrIndexers
            : null,
      ),
    ],
  },
);

/// SABnzbd. Like Transmission it needs no compatibility tail: a queue slot and
/// a history slot are each one row that expands, so it never had a detail page
/// and its bare root is the only path it ever shipped.
///
/// `SabnzbdScreen` is still the whole queue page: the readouts above it now
/// have their own home on Overview, so Queue takes it unsplit.
RouteBase _sabnzbdRoutes() => _serviceRoutes(
  ServiceKey.sabnzbd,
  roots: {
    ServiceTab.overview: (state) =>
        const SabnzbdOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.queue: (state) => const SabnzbdScreen(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.history: (state) =>
        const SabnzbdHistoryScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.servers: (state) =>
        const SabnzbdServersScreen(topPadding: _serviceTabTopPadding),
  },
);

/// NZBGet. Like Transmission and SABnzbd it needs no compatibility tail: a
/// group is an expanding row, never a pushed page. Its five tabs are the widest
/// bar of the four clients because the daemon keeps feeds and a log as
/// first-class things the others do not have.
///
/// `NzbgetScreen` is still readouts and group list together, so Queue takes it
/// unsplit for the reason SABnzbd's does.
RouteBase _nzbgetRoutes() => _serviceRoutes(
  ServiceKey.nzbget,
  roots: {
    ServiceTab.overview: (state) =>
        const NzbgetOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.queue: (state) => const NzbgetScreen(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.history: (state) =>
        const NzbgetHistoryScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.feeds: (state) =>
        const NzbgetFeedsScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.messages: (state) =>
        const NzbgetMessagesScreen(topPadding: _serviceTabTopPadding),
  },
);

/// Unraid.
///
/// **No compatibility tail at all**, which is Unraid's own difference and the
/// same one Transmission has: the only path it ever shipped is its bare root,
/// because the whole service was one page with no detail to push.
///
/// Every tab has a concrete read surface. Array and Docker retain the original
/// split, while VMs, Notifications and Shares use the corresponding GraphQL
/// documents exposed by `UnraidClient`; write affordances remain gated by the
/// schema capabilities returned by the instance. The screens are honest about
/// fields the contract does not provide (for example SMART history), but no
/// branch is left as an endpoint-blocked route.
RouteBase _unraidRoutes() => _serviceRoutes(
  ServiceKey.unraid,
  roots: {
    ServiceTab.overview: (state) =>
        const UnraidOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.array: (state) =>
        const UnraidScreen.array(topPadding: _serviceTabTopPadding),
    ServiceTab.docker: (state) =>
        const UnraidScreen.docker(topPadding: _serviceTabTopPadding),
    ServiceTab.vms: (state) =>
        const UnraidScreen.vms(topPadding: _serviceTabTopPadding),
    ServiceTab.notifications: (state) =>
        const UnraidScreen.notifications(topPadding: _serviceTabTopPadding),
    ServiceTab.shares: (state) =>
        const UnraidScreen.shares(topPadding: _serviceTabTopPadding),
  },
);

/// Transmission. Its own difference is that it needs **no compatibility tail
/// at all**: the only path it ever shipped is its bare root, because its
/// torrent list expands rows in place and never had a detail page to push.
RouteBase _transmissionRoutes() => _serviceRoutes(
  ServiceKey.transmission,
  roots: {
    ServiceTab.overview: (state) =>
        const TransmissionOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.queue: (state) => const TransmissionScreen(
      showAppBar: false,
      topPadding: _serviceTabTopPadding,
    ),
    ServiceTab.labels: (state) =>
        const TransmissionLabelsScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.session: (state) =>
        const TransmissionSessionScreen(topPadding: _serviceTabTopPadding),
  },
);

/// Nginx Proxy Manager. Like Unraid it needs **no compatibility tail**: the
/// only path it ever shipped is its bare root.
///
/// What is NPM's own is that **becoming a tab changes nothing about who may
/// write.** The per-control gate in `npm_write_gate.dart` travels with each
/// control, and the permission band that explains it is drawn on *both* halves
/// of the split rather than on the tab that has the most controls: Proxy hosts
/// carries the host menu's Enable/Disable, Certificates carries Renew, and
/// splitting a page across a bar must not leave a control on one tab and the
/// sentence explaining why it is attenuated on another.
///
/// Every tab has a concrete read surface. Proxy hosts and Certificates retain
/// the original page sections, while Access lists and Audit log use dedicated
/// `NpmClient` queries. The per-control permission band still travels with the
/// tab that owns the write, so adding read coverage does not weaken mutation
/// gating.
RouteBase _npmRoutes() => _serviceRoutes(
  ServiceKey.nginxProxyManager,
  roots: {
    ServiceTab.overview: (state) =>
        const NpmOverviewScreen(topPadding: _serviceTabTopPadding),
    ServiceTab.proxyHosts: (state) =>
        const NpmScreen.proxyHosts(topPadding: _serviceTabTopPadding),
    ServiceTab.certificates: (state) =>
        const NpmScreen.certificates(topPadding: _serviceTabTopPadding),
    ServiceTab.accessLists: (state) =>
        const NpmScreen.accessLists(topPadding: _serviceTabTopPadding),
    ServiceTab.auditLog: (state) =>
        const NpmScreen.auditLog(topPadding: _serviceTabTopPadding),
  },
  inside: {
    ServiceTab.proxyHosts: [
      // A child, so the URL leaves the tab root and the service header steps
      // aside for the page's own app bar (`isServiceTabRoot`).
      _page(
        ':hostId/advanced',
        (state) => NpmAdvancedConfigScreen(
          hostId: RouteUtils.safeIntParam(state, 'hostId')!,
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'hostId') == null
            ? ServiceRoutes.npmProxyHosts
            : null,
      ),
    ],
  },
);

/// The route spellings of one media server, by key.
///
/// A switch returning the four constants rather than interpolating them from
/// [ServiceKey.routeParam] and [ServiceTab.segment]: the constants have to stay
/// `const`: an enum instance's field is not a compile-time constant in Dart:
/// and an earlier attempt at composing a path here shipped one containing a
/// literal dollar sign that no analyzer could see. The wildcard throws because
/// this file names each media server and one arriving silently is worse than a
/// build that stops.
({String root, String overview, String libraries, String itemBase})
_streamPaths(ServiceKey service) => switch (service) {
  ServiceKey.jellyfin => (
    root: ServiceRoutes.jellyfin,
    overview: ServiceRoutes.jellyfinOverview,
    libraries: ServiceRoutes.jellyfinLibraries,
    itemBase: ServiceRoutes.jellyfinItemBase,
  ),
  ServiceKey.plex => (
    root: ServiceRoutes.plex,
    overview: ServiceRoutes.plexOverview,
    libraries: ServiceRoutes.plexLibraries,
    itemBase: ServiceRoutes.plexItemBase,
  ),
  ServiceKey.emby => (
    root: ServiceRoutes.emby,
    overview: ServiceRoutes.embyOverview,
    libraries: ServiceRoutes.embyLibraries,
    itemBase: ServiceRoutes.embyItemBase,
  ),
  _ => throw UnsupportedError('${service.name} is not a media server'),
};

/// Jellyfin, Plex and Emby: one shell each, one branch per tab, one builder
/// for all.
///
/// **One function for every media server, because the screens are one family.** Every
/// Stream surface is written against `StreamServerClient` and takes the service
/// as a parameter, so there is nothing per-service to fork here. The bars
/// are genuinely different: Jellyfin and Emby have Users, Devices, Tasks and
/// Activity; Plex has On deck, Activities, Devices and Playlists, and that difference
/// lives in `tabsFor`, which this reads. Forking the routes to express it would
/// put the same list in two places and let them drift.
///
/// **What the single page became.** Until now the whole service was
/// `StreamDashboardScreen`: the sessions at the top, the libraries at its foot,
/// and `library/:id` and `item/:id` hanging off the service root because a
/// one-page service had nowhere else to hang them. The libraries are the
/// Libraries tab, and both details moved **inside** the Libraries branch, the
/// move Radarr's movie made into Library, for the same two reasons. The two
/// tab-less tails are spellings the app shipped: `ServiceRoutes.jellyfinItem`
/// built `/dashboard/jellyfin/item/<guid>` for every poster tile, every search
/// result and the availability slot on a Radarr or Sonarr detail.
///
/// **The scope is the visit.** `ConnectionInViewScope` is mounted above the
/// band, the tab bar and every branch, because the shell page lives exactly as
/// long as one stay in the service: popped or replaced, it takes the connection
/// the visit was reading with it, and nothing is left in a global store for the
/// next one. It sees the full location on every navigation inside the service
/// (`?i=` of a deep link or a row that names a connection) and remembers the
/// last valid one, so a tab reached through the bar, whose own location carries
/// none, keeps reading it.
RouteBase _streamRoutes(ServiceKey service) {
  final paths = _streamPaths(service);

  /// Where a malformed id falls back to: the tab the page would have been
  /// pushed from, not the app home. The branch is where the user still is, and
  /// sending them out of the service would be a bigger move than the mistake.
  String? rejectBlankId(BuildContext context, GoRouterState state) =>
      (state.pathParameters['id']?.trim().isEmpty ?? true)
      ? paths.libraries
      : null;

  return _serviceRoutes(
    service,
    scope: (state, shell) => ConnectionInViewScope(
      service: service,
      location: state.uri,
      child: shell,
    ),
    tails: [
      _tail(
        'library/:id',
        (s) => '${paths.libraries}/${s.pathParameters['id']}',
      ),
      _tail('item/:id', (s) => '${paths.itemBase}/${s.pathParameters['id']}'),
    ],
    roots: {
      for (final tab in tabsFor(service)!) tab: _streamRoot(service, tab),
    },
    inside: {
      ServiceTab.libraries: [
        // `item/:id` BEFORE `:id`, and the order is load-bearing: routes match
        // in declaration order, so the other way round
        // `/dashboard/plex/libraries/item/9` would resolve as a library browse
        // whose id is the word `item`.
        //
        // Ids travel as path segments rather than through `_libraryDetail`,
        // whose `RouteUtils.safeIntParam` cannot represent a Jellyfin GUID or a
        // Plex `ratingKey`: both opaque strings that only often look numeric.
        // They are guarded for emptiness rather than dereferenced with `!` or
        // defaulted to `''`.
        _page(
          'item/:id',
          (state) => StreamItemScreen(
            service: service,
            itemId: state.pathParameters['id']!,
            instanceId: state.uri.queryParameters['i'],
          ),
          redirect: rejectBlankId,
        ),
        // One library, browsed. The display name rides in `?title=` so a caller
        // that already knows it spares the destination a fetch, but a cold deep
        // link resolves from the path alone.
        _page(
          ':id',
          (state) => StreamLibraryScreen(
            service: service,
            libraryId: state.pathParameters['id']!,
            libraryTitle: state.uri.queryParameters['title'],
            instanceId: state.uri.queryParameters['i'],
          ),
          redirect: rejectBlankId,
        ),
      ],
    },
  );
}

/// The screen at the root of one media server tab.
///
/// Overview and Libraries are real on both servers, and `StreamOverviewScreen`
/// is mounted twice from one class: the only per-service input is the
/// [ServiceKey], and the difference between the two servers lives in what their
/// clients can answer.
///
/// Every other tab is a stream capability tab. Jellyfin Users, Devices and
/// Tasks use their corresponding client reads; its Activity tab deliberately
/// presents live sessions because the historical activity-log contract is not
/// exposed by this client. Plex On deck uses the continue-watching hub, Devices
/// and Playlists use their client reads, and Activities likewise presents live
/// sessions because Plex has no supported historical activity endpoint here.
///
/// A tab's `?i=` is a hint and not the answer: a tab's root reads the
/// connection the visit has in view (`ConnectionInViewScope`), which took the
/// same `?i=` when the location arrived. The location a branch restores is the
/// one it was left at, query included, so a root that led with its own would
/// undo a connection the lens sheet chose since.
_TabScreen _streamRoot(ServiceKey service, ServiceTab tab) => switch (tab) {
  ServiceTab.libraries => (state) => StreamLibrariesScreen(
    service: service,
    showAppBar: false,
    topPadding: _serviceTabTopPadding,
    instanceId: state.uri.queryParameters['i'],
  ),
  ServiceTab.overview => (state) => StreamOverviewScreen(
    service: service,
    topPadding: _serviceTabTopPadding,
    instanceId: state.uri.queryParameters['i'],
  ),
  ServiceTab.users ||
  ServiceTab.devices ||
  ServiceTab.tasks ||
  ServiceTab.activity ||
  ServiceTab.onDeck ||
  ServiceTab.activities ||
  ServiceTab.playlists => _streamCapabilityRoot(service, tab),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on ${service.name}\'s bar with no branch root',
  ),
};

/// The root of a stream capability tab.
///
/// The screen is resolved **here**, not inside the page builder: this one arm
/// accepts the union of seven tabs across two services, so a pair that is on
/// neither bar: `(plex, users)`, or a stream tab added to `serviceTabs` before
/// its screen exists, would otherwise build a perfectly valid route and throw
/// `UnsupportedError` only when the user taps it. Every other root fails while
/// the router is being built, which is what makes a bar and a router
/// disagreeing loud at startup and in every test that constructs one.
_TabScreen _streamCapabilityRoot(ServiceKey service, ServiceTab tab) {
  _streamCapabilityScreen(service, tab);
  return (state) => _streamCapabilityScreen(
    service,
    tab,
    instanceId: state.uri.queryParameters['i'],
  );
}

Widget _streamCapabilityScreen(
  ServiceKey service,
  ServiceTab tab, {
  String? instanceId,
}) {
  return switch ((service, tab)) {
    (ServiceKey.jellyfin, ServiceTab.users) => JellyfinUsersScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
    ),
    (ServiceKey.jellyfin, ServiceTab.devices) => JellyfinDevicesScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
    ),
    (ServiceKey.jellyfin, ServiceTab.tasks) => JellyfinTasksScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
    ),
    (ServiceKey.jellyfin, ServiceTab.activity) => JellyfinActivityScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
    ),
    // Emby's four are Jellyfin's screens: the same page over the same client
    // surface, told which server it is on.
    (ServiceKey.emby, ServiceTab.users) => JellyfinUsersScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
      service: ServiceKey.emby,
    ),
    (ServiceKey.emby, ServiceTab.devices) => JellyfinDevicesScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
      service: ServiceKey.emby,
    ),
    (ServiceKey.emby, ServiceTab.tasks) => JellyfinTasksScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
      service: ServiceKey.emby,
    ),
    (ServiceKey.emby, ServiceTab.activity) => JellyfinActivityScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
      service: ServiceKey.emby,
    ),
    (ServiceKey.plex, ServiceTab.onDeck) => PlexOnDeckScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
    ),
    (ServiceKey.plex, ServiceTab.activities) => PlexActivitiesScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
    ),
    (ServiceKey.plex, ServiceTab.devices) => PlexDevicesScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
    ),
    (ServiceKey.plex, ServiceTab.playlists) => PlexPlaylistsScreen(
      topPadding: _serviceTabTopPadding,
      instanceId: instanceId,
    ),
    _ => throw UnsupportedError(
      'ServiceTab.${tab.name} is not a stream capability tab for '
      '${service.name}',
    ),
  };
}

GoRoute _truenasRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceHomeScreen(
      service: ServiceKey.truenas,
      child: const TrueNasHubScreen(topPadding: _serviceHomeTopPadding),
    ),
    routes: _truenasSectionRoutes(),
  );
}

/// Child routes for each TrueNAS management section.
List<GoRoute> _truenasSectionRoutes() => <GoRoute>[
  _page('dashboard', (state) => const TrueNasDashboardScreen()),
  _page(
    'storage',
    (state) => const TrueNasStorageScreen(),
    routes: [
      _page(
        'pool/:name',
        (state) =>
            TrueNasPoolDetailScreen(poolName: state.pathParameters['name']!),
      ),
    ],
  ),
  _page(
    'datasets',
    (state) => const TrueNasDatasetsScreen(),
    routes: [
      _page(
        'detail',
        (state) => TrueNasDatasetDetailScreen(
          datasetId: state.uri.queryParameters['id']!,
        ),
        redirect: (context, state) =>
            (state.uri.queryParameters['id'] ?? '').isEmpty
            ? ServiceRoutes.truenasDatasets
            : null,
      ),
    ],
  ),
  _page('shares', (state) => const TrueNasSharesScreen()),
  _page('data-protection', (state) => const TrueNasDataProtectionScreen()),
  _page(
    'containers',
    (state) => const TrueNasVirtScreen(type: 'CONTAINER'),
    routes: [
      _page(
        'instance/:id',
        (state) => TrueNasVirtDetailScreen(
          id: state.pathParameters['id']!,
          type: 'CONTAINER',
        ),
      ),
    ],
  ),
  _page(
    'vms',
    (state) => const TrueNasVirtScreen(type: 'VM'),
    routes: [
      _page(
        'instance/:id',
        (state) => TrueNasVirtDetailScreen(
          id: state.pathParameters['id']!,
          type: 'VM',
        ),
      ),
    ],
  ),
  _page(
    'apps',
    (state) => const TrueNasAppsScreen(),
    routes: [
      _page(
        'app/:name',
        (state) => TrueNasAppDetailScreen(name: state.pathParameters['name']!),
      ),
    ],
  ),
  _page('reporting', (state) => const TrueNasReportingScreen()),
  _page(
    'system',
    (state) => const TrueNasSystemHubScreen(),
    routes: [
      _page('general', (state) => const TrueNasGeneralScreen()),
      _page('advanced', (state) => const TrueNasAdvancedScreen()),
      _page('services', (state) => const TrueNasServicesScreen()),
      _page('network', (state) => const TrueNasNetworkScreen()),
      _page('credentials', (state) => const TrueNasCredentialsScreen()),
      _page('certificates', (state) => const TrueNasCertificatesScreen()),
      _page('email', (state) => const TrueNasEmailScreen()),
      _page('update', (state) => const TrueNasUpdateScreen()),
      _page('ntp', (state) => const TrueNasNtpScreen()),
      _page('alert-settings', (state) => const TrueNasAlertSettingsScreen()),
    ],
  ),
];

/// The pre-tab-model `/movies`, `/series` and `/music` trees, which exist only
/// to redirect, as [_rewriteTree] does for `/search`. Every node is
/// redirect-only and the `:id` child exists for one reason: a redirect cannot
/// run until something matches, so `/movies/42` with no route to match would
/// 404 instead of being rewritten. Nothing in this tree builds.
GoRoute _legacyLibraryTree(
  String path, {
  required String serviceBase,
  required String fallbackLocation,
}) {
  String? redirect(BuildContext context, GoRouterState state) {
    final id = state.uri.path.substring(path.length).replaceFirst('/', '');
    return id.isEmpty || id.contains('/')
        ? fallbackLocation
        : _preserveQuery(state.uri, '$serviceBase/$id');
  }

  return GoRoute(
    path: path,
    redirect: redirect,
    routes: [GoRoute(path: ':id', redirect: redirect)],
  );
}

String _preserveQuery(Uri source, String path) {
  final query = source.hasQuery ? '?${source.query}' : '';
  return '$path$query';
}

/// Activity's views besides All, each at its own address and beside All in
/// the branch rather than under it: a view replaces the page, it is not
/// pushed onto it. A title opened from one still hangs under `/activity`
/// (`ServiceRoutes.mediaMountFor`), and Back returns to the view.
final List<RouteBase> _activityViews = [
  for (final tab in ActivityTab.values)
    if (tab != ActivityTab.all)
      GoRoute(
        path: tab.location,
        pageBuilder: (context, state) => _activityPage(state, tab),
      ),
];

/// Activity at [tab]: one page whichever view the address names, so moving
/// between views changes what it draws and leaves the page where it is, with
/// no transition and no second header.
Page<void> _activityPage(GoRouterState state, ActivityTab tab) => _tabPage(
  state,
  ActivityPage(
    tab: tab,
    requestsOf: tab == ActivityTab.requests
        ? state.uri.queryParameters['i']
        : null,
  ),
  key: const ValueKey('activity'),
);

/// The route at the root of each tab's own navigator.
///
/// A switch on [NavTab] rather than a hand-ordered list, so the branch order
/// cannot drift from `NavTab.values`: the shell maps
/// `StatefulNavigationShell.currentIndex` straight onto that enum, and a
/// mismatch would quietly select the wrong tab instead of failing anywhere
/// visible. Exhaustive, so a fifth tab cannot be added without deciding what
/// its branch opens on.
RouteBase _branchRootFor(NavTab tab) => switch (tab) {
  NavTab.home => GoRoute(
    path: ServiceRoutes.home,
    pageBuilder: (context, state) => _tabPage(state, const HomeScreen()),
    routes: [_page('edit', (state) => const EditHomePage()), ..._mediaRoutes()],
  ),
  NavTab.stack => GoRoute(
    path: ServiceRoutes.stack,
    pageBuilder: (context, state) => _tabPage(state, const StackScreen()),
    routes: [
      ..._mediaRoutes(),
      // Every mount takes its segment from `ServiceKey.routeParam` rather than
      // repeating the literal. Sixteen of these were spelled out by hand and
      // one: `npm`, the single segment that is *not* the enum name, was not,
      // which is exactly the asymmetry that makes a hand-spelled table worth
      // deleting: the one path a typo would break was the only one guarded.
      _seerrRoutes(),
      _radarrRoutes(),
      _sonarrRoutes(),
      _lidarrRoutes(),
      _qbittorrentRoutes(),
      _bazarrRoutes(),
      _truenasRoutes(path: ServiceKey.truenas.routeParam),
      _dockgeRoutes(),
      _prowlarrRoutes(),
      _readarrRoutes(),
      _sabnzbdRoutes(),
      _nzbgetRoutes(),
      _unraidRoutes(),
      _transmissionRoutes(),
      _npmRoutes(),
      _streamRoutes(ServiceKey.jellyfin),
      _streamRoutes(ServiceKey.plex),
      _streamRoutes(ServiceKey.emby),
    ],
  ),
  NavTab.activity => GoRoute(
    path: ServiceRoutes.activity,
    pageBuilder: (context, state) => _activityPage(state, ActivityTab.all),
    routes: [
      _page(
        ServiceRoutes.activityNeedsYouSegment,
        (state) => const ActivityNeedsYouPage(),
      ),
      _page(
        ServiceRoutes.activityBlocklistSegment,
        (state) => const ActivityBlocklistPage(),
      ),
      // One download, read from its address alone; on a tablet beside the
      // list, as a title is (`MediaSplit.pageOf`).
      GoRoute(
        path: ServiceRoutes.activityDownloadSegment,
        redirect: (context, state) =>
            (state.uri.queryParameters['id'] ?? '').trim().isEmpty
            ? ServiceRoutes.activity
            : null,
        pageBuilder: (context, state) => MediaSplit.splits(context)
            ? SidePaneSlotPage(key: state.pageKey, name: state.uri.toString())
            : RouteUtils.cupertinoPage(
                key: state.pageKey,
                name: state.matchedLocation,
                child: DownloadPage(
                  instanceId: state.uri.queryParameters['i'] ?? '',
                  downloadKey: state.uri.queryParameters['id']!,
                ),
              ),
      ),
      ..._mediaRoutes(),
    ],
  ),
  // The catalogue, browsed at rest and searched by typing. Its see-alls hang
  // under it; the bare details Seerr's room and the pre-rename `/discover`
  // tree linked to (`movie/603`, `person/287`, `requests`) rewrite to where
  // those pages live now.
  NavTab.discover => GoRoute(
    path: ServiceRoutes.discover,
    pageBuilder: (context, state) => _tabPage(state, const DiscoverPage()),
    routes: [
      _page('calendar', (state) => const CalendarPage()),
      _page(
        'browse/:index',
        (state) => DiscoverIndexPage(
          index: DiscoverIndex.values.byName(state.pathParameters['index']!),
        ),
        // An index this version does not have is the lobby.
        redirect: (context, state) =>
            DiscoverIndex.values.asNameMap().containsKey(
              state.pathParameters['index'],
            )
            ? null
            : ServiceRoutes.discover,
      ),
      _catalogPage('all/:kind', CatalogBase.all),
      _catalogPage('trending', CatalogBase.trending),
      _catalogPage('upcoming/:kind', CatalogBase.upcoming),
      _catalogPage('genre/:kind/:id', CatalogBase.genre),
      _catalogPage('network/:id', CatalogBase.network),
      _catalogPage('studio/:id', CatalogBase.studio),
      _catalogPage('keyword/:kind/:id', CatalogBase.keyword),
      _catalogPage('language/:kind/:code', CatalogBase.language),
      _catalogPage('decade/:kind/:start', CatalogBase.decade),
      // The see-alls the first catalogue shipped. Before `tv/:id`: routes
      // match in declaration order.
      for (final tail in const ['movies/all', 'tv/all', 'trending/all'])
        GoRoute(
          path: tail,
          redirect: (context, state) =>
              _toDiscover(state.uri, ServiceRoutes.discover),
        ),
      for (final tail in const [
        'movie/:id',
        'tv/:id',
        'person/:id',
        'collection/:id',
      ])
        GoRoute(
          path: tail,
          redirect: (context, state) =>
              _toDiscover(state.uri, ServiceRoutes.discover),
        ),
      GoRoute(
        path: 'requests',
        redirect: (context, state) => ServiceRoutes.seerrRequests,
      ),
      ..._mediaRoutes(),
    ],
  ),
  // The requester's own requests. A title opened from one hangs under it.
  NavTab.requests => GoRoute(
    path: ServiceRoutes.requests,
    pageBuilder: (context, state) => _tabPage(state, const RequestsScreen()),
    routes: _mediaRoutes(),
  ),
  NavTab.settings => GoRoute(
    path: '/settings',
    pageBuilder: (context, state) =>
        _tabPage(state, const SettingsHomeScreen()),
    routes: [
      // `_page`, like its six siblings, rather than the bare `GoRoute` with a
      // `builder` it was: that form gave this route a Material page while every
      // other settings destination got `RouteUtils.cupertinoPage`, so the one
      // section owned by another feature was also the one that transitioned
      // differently and lost the rail. Nothing else about the route changes:
      // same path, same screen, same location in the rail's `sections` list.
      _section(
        'background-search',
        (state) => const ReleaseSearchSettingsScreen(),
      ),
      _section('appearance', (state) => const SettingsAppearanceScreen()),
      // Edit Home, from Settings: the page the Home's own row opens, whose
      // way back here is Settings.
      _section('home', (state) => const EditHomePage()),
      _section('hints', (state) => const SettingsHintsScreen()),
      _page('notifications', (state) => const SettingsNotificationsScreen()),
      _section('connections', (state) => const SettingsConnectionsScreen()),
      // The code another device copies this one's connections from: the
      // operator's, since the requester has no connection to hand over.
      _page(
        'another-device',
        (state) => const SecureScreen(child: PairOfferScreen()),
      ),
      // Former name of the connections screen, kept so an existing
      // deep link or a shortcut does not dead-end.
      GoRoute(
        path: 'services',
        redirect: (context, state) => '/settings/connections',
      ),
      _section('region', (state) => const SettingsRegionScreen()),
      // The requester's account. The operator's lives in the connection's
      // form, where `_audienceRedirect` sends him.
      _section(
        'account',
        (state) => RequesterAccountPage(
          instanceId: state.uri.queryParameters['i'] ?? '',
        ),
      ),
      _section('certificates', (state) => const TrustedCertificatesScreen()),
      _page(
        'service/:service',
        (state) {
          // Query rather than a path segment: a connection is a parameter of
          // the form, not a level of the hierarchy, and threading a segment
          // through would have every nested settings route grow one it never
          // reads.
          return SecureScreen(
            child: ServiceSettingsScreen(
              service: _settingsServiceOf(state)!,
              instanceId: state.uri.queryParameters['i'],
              isNew: state.uri.queryParameters['new'] == '1',
              initialAccess: AccessKind.byName(
                state.uri.queryParameters['access'],
              ),
              focusAway: state.uri.queryParameters['away'] == '1',
              foundFrom: state.uri.queryParameters['from'],
              foundName: state.uri.queryParameters['known'],
              prefillUrl: state.uri.queryParameters['url'],
              prefillAccess: state.extra is ConnectionAccess
                  ? state.extra as ConnectionAccess
                  : null,
            ),
          );
        },
        // A service the app does not know is no service's form. It used to
        // open Seerr's, under a link that named something else; it lands on
        // the list of connections instead, where every one of them is.
        redirect: (context, state) => _settingsServiceOf(state) == null
            ? ServiceRoutes.settingsConnections
            : null,
      ),
    ],
  ),
};

/// The service a `/settings/service/<param>` location names, or null when it
/// names none. `jellyseerr` is Seerr's former name.
ServiceKey? _settingsServiceOf(GoRouterState state) {
  final param = state.pathParameters['service'];
  final normalized = param == 'jellyseerr' ? 'seerr' : param;
  for (final service in ServiceKey.values) {
    if (service.routeParam == normalized) return service;
  }
  return null;
}

/// Where an `/activity/<type>` location from before the views lands: an
/// arr's queue for `movies`, `series` and `music`, the Requests view for
/// `discover` (with its `?i=`), All for anything else.
String _legacyActivityTarget(GoRouterState state) =>
    switch (state.pathParameters['type']) {
      'movies' => '${ServiceRoutes.radarr}/${ServiceTab.queue.segment}',
      'series' => '${ServiceRoutes.sonarr}/${ServiceTab.queue.segment}',
      'music' => '${ServiceRoutes.lidarr}/${ServiceTab.queue.segment}',
      'discover' => ServiceRoutes.activityRequestsOf(
        state.uri.queryParameters['i'],
      ),
      _ => ServiceRoutes.activity,
    };

/// Rewrites a location from where the stack used to live: `/dashboard…`
/// while it was the first tab, `/services…` before that, onto `/stack…`, in
/// one hop with the query intact.
///
/// Returns null for anything else, so the redirect callback can fall through.
/// Matching is on the path *segment* rather than a bare `startsWith`, or a
/// future `/services-of-mine` would be rewritten to something that does not
/// exist.
String? _rewriteLegacyStackPath(Uri uri) {
  final path = uri.path;
  for (final legacy in const [
    ServiceRoutes.legacyDashboard,
    ServiceRoutes.legacyServices,
  ]) {
    if (path != legacy && !path.startsWith('$legacy/')) continue;
    final rewritten = '${ServiceRoutes.stack}${path.substring(legacy.length)}';
    return uri.hasQuery ? '$rewritten?${uri.query}' : rewritten;
  }
  return null;
}

/// Where [audience] may not be: the requester's app has no control room, so
/// Activity, Stack and every service's room, and the import flow, send her
/// Home, and the operator's three settings pages (the trust store, release
/// search and the code another device copies from) send her to Settings; the
/// operator has no tab of the requester's own requests, so that one sends him
/// to Seerr's, and no account page, so that one sends him to the
/// connection's form. Null where [audience] may be.
///
/// Read from the shell's held audience ([shellAudienceProvider]), so a route
/// never disagrees with the bar on screen.
String? _audienceRedirect(Uri uri, Audience audience) {
  bool under(String root) => uri.path == root || uri.path.startsWith('$root/');
  return switch (audience) {
    Audience.requester
        when under(ServiceRoutes.activity) ||
            under(ServiceRoutes.stack) ||
            under(manualImportPathPrefix) =>
      ServiceRoutes.home,
    // Her Settings hold no trust store, no release search and no code for
    // another device: all three are the operator's, of servers she does not
    // run.
    Audience.requester
        when under(ServiceRoutes.settingsCertificates) ||
            under(ServiceRoutes.settingsBackgroundSearch) ||
            under(ServiceRoutes.settingsAnotherDevice) =>
      ServiceRoutes.settings,
    Audience.operator when under(ServiceRoutes.requests) =>
      ServiceRoutes.seerrRequests,
    // His account is in the connection's form, among its address and key.
    Audience.operator when under(ServiceRoutes.settingsAccount) =>
      ServiceRoutes.settingsForConnection(
        ServiceKey.seerr,
        uri.queryParameters['i'] ?? '',
      ),
    _ => null,
  };
}

/// Where an invite's link opens (`cupola://invite?…`): the Seerr already
/// here at one of its addresses (the account's page, or the connection's form
/// when it signs in with the key), else the sign-in, the invite in its query.
String _inviteRedirect(Uri uri, SettingsModel settings) {
  final here = SeerrInvite.fromQuery(
    uri.queryParameters,
  )?.connectedIn(settings);
  if (here != null) {
    return here.account != null
        ? ServiceRoutes.settingsAccountFor(instanceId: here.id)
        : ServiceRoutes.settingsForConnection(ServiceKey.seerr, here.id);
  }
  return Uri(
    path: ServiceRoutes.welcomeSignIn,
    queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
  ).toString();
}

bool _showsWelcome(Ref ref) => showsWelcome(
  onboardingCompleted: ref.read(onboardingCompletedProvider),
  settings: ref.read(currentSettingsProvider),
);

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerRefreshNotifierProvider);
  // The routes a person may reach follow the bar they see.
  ref.listen<Audience>(shellAudienceProvider, (_, _) => notifier.refresh());

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: notifier,
    initialLocation: _showsWelcome(ref)
        ? ServiceRoutes.welcome
        : ServiceRoutes.home,
    errorBuilder: (context, state) => const UnknownPlaceScreen(),
    redirect: (context, state) {
      // A pairing link carries the key to every secret of the device that
      // made it: taken off the location here, before anything can keep it,
      // and held in memory for the screen that uses it.
      if (PairLink.isPairUri(state.uri)) {
        ref
            .read(pendingPairProvider.notifier)
            .hold(PairArrival(PairLink.fromQuery(state.uri.queryParameters)));
        return ServiceRoutes.welcomePair;
      }
      // Before the way in's gate: an invite opens a first run too.
      if (SeerrInvite.isInviteUri(state.uri)) {
        return _inviteRedirect(state.uri, ref.read(currentSettingsProvider));
      }
      // A widget's tap: its place, which the gates below then judge like any
      // other (a first run still goes through the way in, the requester never
      // reaches the control room). A link that names none opens the Home.
      if (OutsideLink.isOpenUri(state.uri)) {
        final to = OutsideLink.routeOf(state.uri);
        if (to == null) return ServiceRoutes.home;
        // The router redirects again only onto a location some route
        // matches, so an old spelling (`/dashboard/radarr`) is rewritten
        // here rather than one hop later, which never came.
        return _rewriteLegacyStackPath(Uri.parse(to)) ?? to;
      }
      final path = state.uri.path;
      if (path == ServiceRoutes.legacyOnboarding) return ServiceRoutes.welcome;
      // Never away from the way in: a run saves its first connection before
      // it is over, "Revisit onboarding" arrives with the flag already on,
      // and the flow leaves for the Home on its own.
      if (path == ServiceRoutes.welcome ||
          path.startsWith('${ServiceRoutes.welcome}/')) {
        return null;
      }
      if (_showsWelcome(ref)) return ServiceRoutes.welcome;
      if (path == '/') return ServiceRoutes.home;

      // Everything that used to live under `/dashboard` or `/services` still
      // resolves.
      //
      // One rewrite here rather than a shadow copy of the tree: the rename
      // moved thirty-four routes and every detail tail under them, and
      // re-declaring each one as a legacy twin would double the surface that
      // has to stay in sync for the rest of the app's life. A prefix swap
      // keeps the whole subtree: `/services/radarr/movie/42?heroTag=…`
      // included, and preserves the query, which is where the instance lens
      // travels.
      final legacy = _rewriteLegacyStackPath(state.uri);
      if (legacy != null) return legacy;

      return _audienceRedirect(state.uri, ref.read(shellAudienceProvider));
    },
    routes: [
      GoRoute(
        path: ServiceRoutes.welcome,
        builder: (context, state) => const OnboardingScreen(),
        routes: [
          GoRoute(
            path: 'connect',
            builder: (context, state) =>
                const OnboardingScreen(entry: OnboardingEntry.connect),
          ),
          GoRoute(
            path: 'pair',
            builder: (context, state) =>
                const SecureScreen(child: PairReceiveScreen()),
          ),
          GoRoute(
            path: 'sign-in',
            // Keyed by the invite: one opened over another starts afresh.
            builder: (context, state) => RequesterSignInScreen(
              key: ValueKey(state.uri.query),
              invite: state.uri.queryParameters,
            ),
          ),
        ],
      ),
      GoRoute(
        path: ServiceRoutes.legacyOnboarding,
        redirect: (context, state) => ServiceRoutes.welcome,
      ),
      // One Navigator per tab, all alive at once behind a cross-fade.
      //
      // The order of [branches] is a contract, not a layout: the shell maps a
      // bar tap and `StatefulNavigationShell.currentIndex` straight onto
      // `NavTab.values[index]`, so a branch out of `NavTab` order would select
      // the wrong tab rather than fail. Asserted below.
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          for (final tab in NavTab.values)
            StatefulShellBranch(
              navigatorKey: branchNavigatorKeyFor(tab),
              observers: [branchTopRouteFor(tab)],
              routes: [
                _branchRootFor(tab),
                if (tab == NavTab.activity) ..._activityViews,
              ],
            ),
        ],
      ),
      // The manual-import flow: three stations, on the ROOT navigator rather
      // than inside a branch.
      //
      // It is full-bleed (it reserves no nav-bar clearance and the bar is not
      // drawn over it) and it belongs to no tab: it is reached from a service
      // page, from a queue item, from a review screen. Left inside a branch it
      // would be a page on that tab's stack, so its flow state and its
      // two-second command poll would survive a switch away from it: the exact
      // leak this architecture exists to remove. At root it unmounts when left.
      //
      // Every entry point uses `push`, and must keep doing so: a `go` here would
      // replace the shell page in the root navigator and take all four branch
      // stacks with it.
      GoRoute(
        path: manualImportBrowsePath,
        pageBuilder: (context, state) => _manualImportPage(
          state,
          (service, targetId, instanceId) => ManualImportLocateScreen(
            service: service,
            targetId: targetId,
            instanceId: instanceId,
            initialPath: state.uri.queryParameters['path'],
          ),
        ),
      ),
      GoRoute(
        path: manualImportReviewPath,
        pageBuilder: (context, state) => _manualImportPage(
          state,
          (service, targetId, instanceId) => ManualImportReviewScreen(
            service: service,
            targetId: targetId,
            instanceId: instanceId,
            initialPath: state.uri.queryParameters['path'],
          ),
        ),
      ),
      GoRoute(
        path: manualImportBlockedPath,
        pageBuilder: (context, state) => _manualImportPage(
          state,
          (service, targetId, instanceId) =>
              BlockedImportReviewPage(service: service, instanceId: instanceId),
        ),
      ),
      // Steps of the retired four-screen flow; an old deep link lands on
      // the merged Review station instead of dead-ending.
      GoRoute(
        path: manualImportFolderPath,
        redirect: (context, state) => _redirectLegacyManualImport(state),
      ),
      GoRoute(
        path: manualImportMatchPath,
        redirect: (context, state) => _redirectLegacyManualImport(state),
      ),
      GoRoute(
        path: manualImportProgressPath,
        pageBuilder: (context, state) => _manualImportPage(
          state,
          // Station 3 takes no `instanceId`: by the time a command is running
          // the binding is already on the flow state, and a second source of
          // truth here could only disagree with it.
          (service, targetId, instanceId) =>
              ManualImportProgressScreen(service: service),
        ),
      ),
      // The retired top-level locations, kept so old deep links land somewhere.
      // Every path they match resolves to a redirect into `/services/...`, so
      // their builders are unreachable; they exist only to give the matcher
      // something to match before the redirect runs.
      //
      // At root because under a `StatefulShellRoute` there is no shell level to
      // be a sibling of any more: the route list is derived from the branches.
      // Putting four dead trees inside the services branch would read as part of
      // that tab's subtree and invite someone to give them a real builder.
      // A title opened from a page above the tabs (`/activity/movies`, the
      // import flow): pushed into a tab, it would open underneath that page.
      ..._mediaRoutes(prefix: '/'),
      // The Search tab Discover replaced: its field is Discover's field now,
      // and a title opened from it lives under Discover.
      _rewriteTree('/search', const [
        'media/movie/:id',
        'media/tv/tvdb/:id',
        'media/tv/:id',
        'media/person/:id',
        'media/collection/:id',
      ], (uri) => _toDiscover(uri, '/search')),
      // `/movies/42?heroTag=x` lands on the title inside the Library tab in
      // one hop, not by bouncing through the service root and losing where it
      // was going.
      _legacyLibraryTree(
        '/movies',
        serviceBase: ServiceRoutes.radarrMovieBase,
        fallbackLocation: ServiceRoutes.radarrLibrary,
      ),
      _legacyLibraryTree(
        '/series',
        serviceBase: ServiceRoutes.sonarrSeriesBase,
        fallbackLocation: ServiceRoutes.sonarrLibrary,
      ),
      _legacyLibraryTree(
        '/music',
        serviceBase: ServiceRoutes.lidarrArtistBase,
        fallbackLocation: ServiceRoutes.lidarrLibrary,
      ),
      // Where Activity's per-service pages lived: a queue is its arr's own
      // tab now, and Seerr's requests are Activity's Requests. One hop, the
      // query kept; anything else under `/activity` that no view names lands
      // on All.
      GoRoute(
        path: '/activity/:type',
        redirect: (context, state) => _legacyActivityTarget(state),
      ),
    ],
  );
});
