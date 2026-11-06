import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/page_tabs.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';

import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../test_helpers/settings_scope.dart';

const _secondSeerr = ServiceInstance(
  id: 'seerr-2222222',
  service: ServiceKey.seerr,
  label: 'Anime',
  url: 'https://second.lan:5055',
  credential: 'key-2',
);

/// The services whose home is a tab bar rather than a single page.
///
/// Named here rather than derived from `serviceTabs`, and the difference used
/// to be the point: that map is the *design*, this list is what the router has
/// actually mounted, and while the migration was in flight the gap between the
/// two was its remaining work.
///
/// **The gap is closed**: all sixteen are mounted, so the list is now tied to
/// the map by its own case below, and what it guards has changed with it. A
/// hand-kept list that silently covered eight of thirteen is exactly how these
/// invariants stopped being asserted for five services that had landed: every
/// case here loops over this list, so a service missing from it is a service
/// whose branch order, nesting and detail placement nothing checks.
///
/// Seventeen and not eighteen because TrueNAS is the console exception by
/// design: ten sections do not fit a bar, and `tabsFor` returns null for it.
const List<ServiceKey> _tabbedServices = [
  ServiceKey.seerr,
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.readarr,
  ServiceKey.bazarr,
  ServiceKey.qbittorrent,
  ServiceKey.transmission,
  ServiceKey.sabnzbd,
  ServiceKey.nzbget,
  ServiceKey.prowlarr,
  ServiceKey.jellyfin,
  ServiceKey.plex,
  ServiceKey.emby,
  ServiceKey.dockge,
  ServiceKey.unraid,
  ServiceKey.nginxProxyManager,
];

/// Every page pushed from inside a tab's branch, by the branch that owns it, in
/// the order the router declares them.
///
/// One table for all eighteen rather than one per record type, because the rule
/// is one rule: a page pushed *inside* its tab survives a switch away from the
/// service and back, and a Hero still flies because the list it came from is
/// under it on the same Navigator. Beside the branch it would be neither.
///
/// **Order is asserted, not just membership.** Routes match in declaration
/// order, so a literal segment has to be declared before a `:id` that could
/// swallow it: `item/:id` after `:id` resolves `/libraries/item/9421` as a
/// library browse whose id is the word `item`, and the user gets a browse of
/// nothing.
///
/// Spelled as the route paths the router declares, so this reads as the tree
/// does: `':id'` where the tab's own segment already names the record type,
/// `'<record>/:id'` where it does not.
const List<({ServiceKey service, ServiceTab tab, String path})>
_tabDetailPaths = [
  (service: ServiceKey.radarr, tab: ServiceTab.library, path: 'movie/:id'),
  (service: ServiceKey.sonarr, tab: ServiceTab.library, path: 'series/:id'),
  (service: ServiceKey.lidarr, tab: ServiceTab.library, path: 'artist/:id'),
  (service: ServiceKey.readarr, tab: ServiceTab.library, path: 'author/:id'),
  // Bazarr's bar names the record types themselves, so the detail is `:id`
  // under the tab rather than `<record>/:id` under it: `series/series/42`
  // would be a stutter nobody would type.
  (service: ServiceKey.bazarr, tab: ServiceTab.series, path: ':id'),
  (service: ServiceKey.bazarr, tab: ServiceTab.movies, path: ':id'),
  (
    service: ServiceKey.qbittorrent,
    tab: ServiceTab.queue,
    path: 'torrent/:hash',
  ),
  (service: ServiceKey.prowlarr, tab: ServiceTab.indexers, path: 'indexer/:id'),
  (service: ServiceKey.jellyfin, tab: ServiceTab.libraries, path: 'item/:id'),
  (service: ServiceKey.jellyfin, tab: ServiceTab.libraries, path: ':id'),
  (service: ServiceKey.plex, tab: ServiceTab.libraries, path: 'item/:id'),
  (service: ServiceKey.plex, tab: ServiceTab.libraries, path: ':id'),
  (service: ServiceKey.emby, tab: ServiceTab.libraries, path: 'item/:id'),
  (service: ServiceKey.emby, tab: ServiceTab.libraries, path: ':id'),
  // The new-stack editor is not a detail, and it is here for the reason one
  // would be: it is reached from the Stacks list's own header and from nowhere
  // else, so Stacks is the tab that owns it. The compose editor of an existing
  // stack hangs off `stack/:name` a segment deeper, which is why it is not a
  // row of its own.
  (service: ServiceKey.dockge, tab: ServiceTab.stacks, path: 'new'),
  (service: ServiceKey.dockge, tab: ServiceTab.stacks, path: 'stack/:name'),
  // A proxy host's custom Nginx block, opened from the host's own menu. Its
  // page carries its own app bar, which the service header would sit on top
  // of anywhere but a child of the tab.
  (
    service: ServiceKey.nginxProxyManager,
    tab: ServiceTab.proxyHosts,
    path: ':hostId/advanced',
  ),
];

/// The title's own page, hung last under every tab of the services that open
/// titles (`ServiceRoutes.mediaMountServices`): a title opened anywhere in one
/// of them lands under the tab it was opened from.
const List<String> _mediaPaths = [
  'media/movie/:id',
  'media/tv/tvdb/:id',
  'media/tv/:id',
  // The two pages a title links to, hung beside it.
  'media/person/:id',
  'media/collection/:id',
];

/// The services with nothing pushed from any of their tabs, and why.
///
/// Named rather than left out, because "no detail" and "a detail nobody
/// asserted" look identical in a table that only lists what exists. Each of
/// these is a list of rows that expand in place or a service whose read layer
/// has no second document to open:
///
///  * Seerr: its catalogue is the Discover tab of the app now;
///  * Transmission, SABnzbd, NZBGet: a queue slot is one row that expands;
///  * Unraid: it was one page, and the split produced sections rather than
///    pages.
const List<ServiceKey> _servicesWithoutTabDetails = [
  // Seerr's see-alls, person and collection went with Discover to the app's
  // own tab; a title, a person and a collection hang under every tab of its
  // bar like everywhere else (`_mediaPaths`).
  ServiceKey.seerr,
  ServiceKey.transmission,
  ServiceKey.sabnzbd,
  ServiceKey.nzbget,
  ServiceKey.unraid,
];

/// The record each service's Library pushes, by the path it is mounted at.
const Map<ServiceKey, String> _libraryDetailPaths = {
  ServiceKey.radarr: 'movie/:id',
  ServiceKey.sonarr: 'series/:id',
  ServiceKey.lidarr: 'artist/:id',
  // Readarr's author page is in its branch too (the table above); it is not
  // here because it has no old spelling to keep a tail for.
};

/// The job each download client's Queue pushes, by the path it is mounted at.
///
/// The same rule as [_libraryDetailPaths] applied to the tab that is the
/// download clients' equivalent of Library: the list that *was* the whole
/// service. A detail beside the branch rather than inside it would lose the
/// stack on every switch away from the service.
const Map<ServiceKey, String> _queueDetailPaths = {
  ServiceKey.qbittorrent: 'torrent/:hash',
};

/// The shape of the shell, asserted against the real router.
///
/// `router_test.dart` covers what each path resolves to. This file covers the
/// structure that migration put in place and that nothing in a path assertion
/// would notice going wrong: which branches exist and in what order, what was
/// deliberately left outside them, and the invariants those choices rest on.
void main() {
  Future<GoRouter> pumpRouter(
    WidgetTester tester, {
    String? at,
    List<ServiceKey> configured = const [],
    SettingsModel Function(SettingsModel settings)? customize,
  }) async {
    // `settingsScopeOverrides` already marks onboarding complete, which is what
    // keeps the router off the onboarding gate.
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(
          configured: configured,
          customize: customize,
        ),
        // The Home's thirty-second poll: a test about routes ends before the
        // container that holds its timer is disposed.
        homeLivePollProvider.overrideWith((ref) {}),
        homeRecoveryPollProvider.overrideWith((ref) {}),
        // And Activity's, for the same reason.
        activityLivePollProvider.overrideWith((ref, tab) {}),
        featuredAdvancesProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    // A phone, not the 800x600 default: several destinations here are real
    // screens whose empty states are taller than that, and an overflow is noise
    // in a test about routing.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = container.read(routerProvider);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // Reduce Motion, for the reason `router_test` states: a destination here
        // owns a continuous animation: the service ring sweeps forever by
        // design, so with motion on `pumpAndSettle` waits for a frame that
        // never stops coming. It also skips the branch cross-fade, which these
        // cases are not about.
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    if (at != null) {
      router.go(at);
      await tester.pumpAndSettle();
    } else {
      await tester.pumpAndSettle();
    }
    return router;
  }

  /// The shell route, found on the real configuration.
  StatefulShellRoute shellRouteOf(GoRouter router) =>
      router.configuration.routes.whereType<StatefulShellRoute>().single;

  /// A service's own node, walked to from the app shell rather than looked up.
  ///
  /// Walking is the point: reaching it means passing through the Stack
  /// branch, so a service shell mounted anywhere else would not be found at
  /// all.
  GoRoute serviceRouteOf(GoRouter router, ServiceKey service) {
    final stack =
        shellRouteOf(router).branches[NavTab.stack.index].routes.single
            as GoRoute;
    return stack.routes.whereType<GoRoute>().firstWhere(
      (route) => route.path == service.routeParam,
    );
  }

  StatefulShellRoute serviceShellOf(GoRouter router, ServiceKey service) =>
      serviceRouteOf(
        router,
        service,
      ).routes.whereType<StatefulShellRoute>().single;

  /// The root route of one of a service's tab branches.
  GoRoute branchRootOf(GoRouter router, ServiceKey service, ServiceTab tab) =>
      serviceShellOf(
            router,
            service,
          ).branches[tabsFor(service)!.indexOf(tab)].routes.single
          as GoRoute;

  group('shell branches', () {
    testWidgets('there is one branch per tab, in NavTab order', (tester) async {
      final router = await pumpRouter(tester);
      final branches = shellRouteOf(router).branches;

      expect(branches, hasLength(NavTab.values.length));
      for (var i = 0; i < NavTab.values.length; i++) {
        final tab = NavTab.values[i];
        final root = branches[i].routes.first as GoRoute;
        expect(
          root.path,
          tab.routePath,
          reason:
              'The shell maps currentIndex onto NavTab.values[index], so branch '
              '$i must be ${tab.name}. Out of order it would select the wrong '
              'tab rather than fail.',
        );
        // A tab has one root, except Activity, whose other views sit beside
        // All in its branch: a view replaces the page, it is not pushed on it.
        expect(
          branches[i].routes,
          hasLength(tab == NavTab.activity ? ActivityTab.values.length : 1),
          reason: tab.name,
        );
      }
    });

    testWidgets("Activity's views are the branch's routes, in ActivityTab "
        'order, each at its own address', (tester) async {
      final router = await pumpRouter(tester);
      final branch = shellRouteOf(router).branches[NavTab.activity.index];

      expect(
        [for (final route in branch.routes) (route as GoRoute).path],
        [for (final tab in ActivityTab.values) tab.location],
      );
    });

    testWidgets('each service on the model has one branch per tab, in '
        'tabsFor order', (tester) async {
      final router = await pumpRouter(tester);

      for (final service in _tabbedServices) {
        final tabs = tabsFor(service)!;
        final branches = serviceShellOf(router, service).branches;

        expect(branches, hasLength(tabs.length), reason: service.name);
        for (var i = 0; i < tabs.length; i++) {
          final tab = tabs[i];
          expect(
            (branches[i].routes.single as GoRoute).path,
            tab.segment,
            reason:
                'The bar is generated from the same list and taps it by '
                'index, so ${service.name} branch $i must be ${tab.name}. Out '
                'of order it would light one tab and show another rather than '
                'fail.',
          );
        }
      }
    });

    testWidgets('every service shell is nested inside the Stack branch', (
      tester,
    ) async {
      final router = await pumpRouter(tester);

      expect(
        router.configuration.routes.whereType<StatefulShellRoute>(),
        hasLength(1),
        reason:
            'A second shell beside the app one would replace the page the nav '
            'bar, the Portal and the whole desktop chrome hang off; opening a '
            'service would take the app\'s own navigation away with it.',
      );
      // Found only by walking down through the Stack branch, which is the
      // assertion: nothing else in this file could reach them.
      for (final service in _tabbedServices) {
        expect(
          serviceShellOf(router, service).branches,
          isNotEmpty,
          reason: service.name,
        );
      }
    });

    test('the checklist is the table of services that have a bar', () {
      // The list used to be a subset on purpose, and while the migration was in
      // flight that was right. It is a tie now: every case in this group loops
      // over it, so a service mounted but not listed is a service whose branch
      // order and nesting nothing here checks, which is exactly what happened
      // to five of them in one day.
      expect(
        _tabbedServices.toSet(),
        serviceTabs.keys.toSet(),
        reason:
            'Every service with a bar must be on the checklist, and nothing '
            'without one may be: TrueNAS keeps its console and `tabsFor` '
            'returns null for it.',
      );
      expect(
        _tabbedServices,
        hasLength(_tabbedServices.toSet().length),
        reason: 'a service listed twice would hide a missing one',
      );

      // The two tables below partition the same sixteen. Without this, a
      // service with a detail nobody listed and a service with no detail at all
      // look identical: both simply absent.
      expect({
        ..._tabDetailPaths.map((entry) => entry.service),
        ..._servicesWithoutTabDetails,
      }, serviceTabs.keys.toSet());
      expect(
        _tabDetailPaths
            .map((entry) => entry.service)
            .toSet()
            .intersection(_servicesWithoutTabDetails.toSet()),
        isEmpty,
      );
    });

    testWidgets('every branch carries exactly the pages its tab pushes, in '
        'declaration order', (tester) async {
      // The generalisation of the two cases below, over all sixteen services
      // rather than the four that had a table. It asserts three things at once:
      // that every page pushed from a tab is declared inside that tab's branch,
      // that no branch has picked up a route nobody meant to put there, and
      // that the literal-before-parameter order holds where a branch has both.
      final router = await pumpRouter(tester);

      for (final service in _tabbedServices) {
        for (final tab in tabsFor(service)!) {
          final expected = [
            ..._tabDetailPaths
                .where((entry) => entry.service == service && entry.tab == tab)
                .map((entry) => entry.path),
            if (ServiceRoutes.mediaMountServices.contains(service))
              ..._mediaPaths,
          ];
          final actual = branchRootOf(router, service, tab).routes
              .whereType<GoRoute>()
              .map((route) => route.path)
              .toList(growable: false);

          expect(
            actual,
            expected,
            reason: '${service.name}\u00A0· ${tab.name}',
          );
        }
      }
    });

    testWidgets('every library detail is inside its Library branch', (
      tester,
    ) async {
      final router = await pumpRouter(tester);

      for (final entry in _libraryDetailPaths.entries) {
        final library = branchRootOf(router, entry.key, ServiceTab.library);

        expect(
          library.routes.whereType<GoRoute>().map((route) => route.path),
          contains(entry.value),
          reason:
              'Pushed inside the branch, ${entry.key.name}\'s detail survives '
              'a switch away from the service and its Hero flies, because '
              'list and detail share one Navigator. Beside the branch it '
              'would be neither.',
        );

        // The same spelling still hangs off the service node, and that one is
        // a compatibility tail: it builds nothing and only forwards.
        final tail = serviceRouteOf(
          router,
          entry.key,
        ).routes.whereType<GoRoute>().firstWhere((r) => r.path == entry.value);
        expect(tail.builder, isNull, reason: entry.key.name);
        expect(tail.pageBuilder, isNull, reason: entry.key.name);
        expect(tail.redirect, isNotNull, reason: entry.key.name);
      }
    });

    testWidgets('every job detail is inside its Queue branch', (tester) async {
      final router = await pumpRouter(tester);

      for (final entry in _queueDetailPaths.entries) {
        final queue = branchRootOf(router, entry.key, ServiceTab.queue);

        expect(
          queue.routes.whereType<GoRoute>().map((route) => route.path),
          contains(entry.value),
          reason:
              'Pushed inside the branch, ${entry.key.name}\'s job detail '
              'survives a switch away from the service and comes back to the '
              'job rather than to the top of the queue. Beside the branch it '
              'would be neither.',
        );

        // The same spelling still hangs off the service node, and that one is
        // a compatibility tail: it builds nothing and only forwards.
        final tail = serviceRouteOf(
          router,
          entry.key,
        ).routes.whereType<GoRoute>().firstWhere((r) => r.path == entry.value);
        expect(tail.builder, isNull, reason: entry.key.name);
        expect(tail.pageBuilder, isNull, reason: entry.key.name);
        expect(tail.redirect, isNotNull, reason: entry.key.name);
        // Childless, and that is what stops it shadowing the real route: the
        // matcher treats a prefix hit with no complete match as no match, so a
        // child here would win `torrent/:hash` before the shell ever saw it.
        expect(tail.routes, isEmpty, reason: entry.key.name);
      }
    });

    testWidgets('no branch is preloaded', (tester) async {
      final router = await pumpRouter(tester);

      for (final branch in shellRouteOf(router).branches) {
        expect(
          branch.preload,
          isFalse,
          reason:
              'Preloading builds a tab, and everything it fetches, before the '
              'user has asked for it: the opposite of the rule that only the '
              'page on screen may spend anything.',
        );
      }
    });
  });

  group('routes deliberately left outside the shell', () {
    /// Every path a branch can reach, flattened.
    List<String> pathsUnder(RouteBase route, [String prefix = '']) {
      final paths = <String>[];
      if (route is GoRoute) {
        final path = route.path.startsWith('/')
            ? route.path
            : '$prefix/${route.path}';
        paths.add(path);
        for (final child in route.routes) {
          paths.addAll(pathsUnder(child, path));
        }
      } else {
        for (final child in route.routes) {
          paths.addAll(pathsUnder(child, prefix));
        }
      }
      return paths;
    }

    testWidgets('the import flow is above the shell, not inside a branch', (
      tester,
    ) async {
      final router = await pumpRouter(tester);

      final inBranches = shellRouteOf(router).branches
          .expand((branch) => branch.routes.expand(pathsUnder))
          .toList(growable: false);
      final atRoot = router.configuration.routes
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toList(growable: false);

      for (final path in [
        manualImportBrowsePath,
        manualImportReviewPath,
        manualImportProgressPath,
        manualImportFolderPath,
        manualImportMatchPath,
      ]) {
        expect(
          inBranches,
          isNot(contains(path)),
          reason:
              'Inside a branch, $path would be a page on that tab\'s stack: its '
              'flow state and its two-second command poll would survive a switch '
              'away from it.',
        );
        expect(
          atRoot,
          contains(path),
          reason: '$path must sit on the root navigator, above the shell',
        );
      }
    });

    testWidgets('the retired top-level locations are above the shell too', (
      tester,
    ) async {
      final router = await pumpRouter(tester);

      final atRoot = router.configuration.routes
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toList(growable: false);

      // Redirect-only scaffolding: four dead trees inside the services branch
      // would read as part of that tab's subtree. `/discover` is a tab now;
      // `/search`, the tab it replaced, is the retired one.
      expect(atRoot, containsAll(['/search', '/movies', '/series', '/music']));
      expect(atRoot, isNot(contains('/discover')));
      expect(
        atRoot,
        contains('/activity/:type'),
        reason:
            'the old per-service pages are a redirect at the root, one hop to '
            'where the thing lives now',
      );
    });

    testWidgets('pushing the import flow keeps the shell alive beneath it', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      expect(find.byType(ShellScreen), findsOneWidget);

      // `push`, which is how every entry point reaches this flow: a `go` would
      // replace the shell page in the root navigator and take all four branch
      // stacks with it.
      router.push('$manualImportBrowsePath?service=radarr&targetId=1');
      await tester.pumpAndSettle();

      expect(find.byType(FloatingBottomNavBar), findsNothing);
      expect(
        find.byType(ShellScreen, skipOffstage: false),
        findsOneWidget,
        reason: 'the shell, and every branch stack, is still underneath',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'the station lays out inside a phone',
      );
    });

    testWidgets('leaving the import flow lands back on a branch', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      router.push('$manualImportBrowsePath?service=radarr&targetId=1');
      await tester.pumpAndSettle();

      // What the flow's own Done button does.
      router.go(NavTab.activity.routePath);
      await tester.pumpAndSettle();

      expect(router.state.uri.path, NavTab.activity.routePath);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);

      router.go(NavTab.home.routePath);
      await tester.pumpAndSettle();
    });

    testWidgets('a view change changes the address and leaves the page where '
        'it is', (tester) async {
      final router = await pumpRouter(
        tester,
        at: NavTab.activity.routePath,
        configured: const [ServiceKey.radarr],
      );
      final page = tester.state(find.byType(ActivityPage));
      Finder viewTab(ActivityTab tab) => find.descendant(
        of: find.byType(PageTabs<ActivityTab>),
        matching: find.text(tab.label),
      );

      for (final tab in [
        ActivityTab.downloads,
        ActivityTab.requests,
        ActivityTab.history,
        ActivityTab.all,
      ]) {
        await tester.tap(viewTab(tab));
        await tester.pumpAndSettle();

        expect(router.state.uri.path, tab.location, reason: tab.name);
        expect(
          tester.widget<ActivityPage>(find.byType(ActivityPage)).tab,
          tab,
          reason: tab.name,
        );
        // The same page and the one header: a view is not a new screen.
        expect(
          identical(tester.state(find.byType(ActivityPage)), page),
          isTrue,
          reason: tab.name,
        );
        expect(find.byType(PageTabs<ActivityTab>), findsOneWidget);
        expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      }
    });

    testWidgets('a view is not pushed: Back from one leaves Activity, not '
        'the view before', (tester) async {
      final router = await pumpRouter(
        tester,
        at: NavTab.activity.routePath,
        configured: const [ServiceKey.radarr],
      );

      await tester.tap(
        find.descendant(
          of: find.byType(PageTabs<ActivityTab>),
          matching: find.text(ActivityTab.history.label),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.state.uri.path, ActivityTab.history.location);
      expect(
        router.canPop(),
        isFalse,
        reason: 'a view replaces the page: nothing was stacked on All',
      );
    });

    testWidgets('an old per-service activity link lands in a tab, with its nav '
        'bar', (tester) async {
      // Radarr configured, because the queue tab builds a real client: the
      // assertion is about where the link lands and its chrome.
      final router = await pumpRouter(
        tester,
        at: '/activity/movies',
        configured: const [ServiceKey.radarr],
      );

      expect(router.state.uri.toString(), '/stack/radarr/queue');
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(find.byType(ShellScreen), findsOneWidget);
    });

    // The requests view is the one destination here that belongs to a
    // *connection*: /activity aggregates every Seerr, so a row that came off
    // the second one has to open the second one's list. The link carries the
    // connection in `?i=` and this asserts the route reads it, both at its own
    // address and through the old one: a parameter nothing reads was removed
    // from this route once already.
    for (final at in [
      '/activity/requests?i=${_secondSeerr.id}',
      '/activity/discover?i=${_secondSeerr.id}',
    ]) {
      testWidgets('the requests view carries its connection ($at)', (
        tester,
      ) async {
        final router = await pumpRouter(
          tester,
          at: at,
          configured: const [ServiceKey.seerr],
          // A real second connection, so the id in the link names something:
          // otherwise the assertion would hold even if the page took the lens.
          customize: (settings) => settings.copyWithInstance(_secondSeerr),
        );

        expect(
          router.state.uri.toString(),
          '/activity/requests?i=${_secondSeerr.id}',
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is ActivityPage &&
                widget.tab == ActivityTab.requests &&
                widget.requestsOf == _secondSeerr.id,
          ),
          findsOneWidget,
        );
      });
    }
  });

  testWidgets('Set up X from a service page comes back to it', (tester) async {
    final page = ServiceRoutes.forService(ServiceKey.bazarr);
    final router = await pumpRouter(tester, at: page);
    final landed = router.state.uri.path;
    expect(landed, startsWith(page));

    // What `NotConfiguredPlaceholder` and a cross-service control do: the
    // form is pushed over the page that asked, in whichever branch it lives.
    router.push(ServiceRoutes.setUp(ServiceKey.bazarr));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, ServiceRoutes.setUp(ServiceKey.bazarr));

    // What the form's back button and its Save both do.
    router.pop();
    await tester.pumpAndSettle();

    expect(router.state.uri.path, landed);
    expect(tester.takeException(), isNull);
  });
}
