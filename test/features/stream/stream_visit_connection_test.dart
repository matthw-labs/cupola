/// A media server opened on one of its connections stays on it, in the whole
/// app, on a household with two Jellyfin and two Plex.
///
/// Home's Now playing opens `?i=<connection>` on the server's Activity page,
/// and a library tile and an item name theirs the same way. None of them
/// moves the lens, so the rest of the service used to read the lens as soon
/// as a tab was switched, under a header that named the lens: the user opened
/// "Cabin" and was reading "Home" with nothing on screen to say so. A visit now
/// has one connection, every tab reads it, the header names it, and it ends
/// with the visit.
///
/// What each tab read is told by what reached each server: a request is a read
/// that went to one connection and not the other, which is what no widget can
/// fake. A tab whose answer was already cached from Home's own reads is told by
/// what it draws instead (the address on the Overview, the `?i=` a room opens
/// on).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_admin_placeholder.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_item_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';

import '../../test_helpers/profiles/profiles.dart';

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

/// Two Jellyfin: the household's, the lens, and the cabin's beside it.
final _twoJellyfin = Profiles.p1.withConnection(WorldConnections.jellyfinCabin);

/// Two Plex: the household's, the lens, and the cabin's beside it.
final _twoPlex = Profiles.p1
    .withConnection(WorldConnections.plex)
    .withConnection(WorldConnections.plexCabin);

const _jellyfin = ServiceKey.jellyfin;
const _plex = ServiceKey.plex;

/// The whole app, on [profile]'s household, with its own router: a phone's
/// screen unless [size] says otherwise.
Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester,
  ConfigProfile profile, {
  Size size = const Size(390, 3000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(profile, now: _now);
  harness.network.followFakeTime(tester.binding);
  final container = harness.container();
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await _answer(tester);
  // What the household's own pages asked while they came up is not what the
  // visit under test asks.
  harness.network.requests.clear();
  return (harness, router, container);
}

/// Lets the household's servers answer.
Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(
  WidgetTester tester,
  ProfileHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await harness.unmount(tester);
}

/// Opens [tab] through the service's tab bar, as a thumb does.
Future<void> _openTab(WidgetTester tester, ServiceTab tab) async {
  final target = find.descendant(
    of: find.byType(ServiceTabBar),
    matching: find.text(tab.label),
  );
  await tester.ensureVisible(target.first);
  await tester.pump();
  await tester.tap(target.first);
  await _answer(tester);
}

/// What the lens badge says, or null when it draws nothing.
String? _badge(WidgetTester tester) {
  final texts = find.descendant(
    of: find.byType(InstanceLensBadge),
    matching: find.byType(Text),
  );
  return texts.evaluate().isEmpty
      ? null
      : tester.widget<Text>(texts.first).data;
}

/// The paths that reached connection [id] since the last [_forget].
Set<String> _reached(ProfileHarness harness, String id) => {
  for (final request in harness.network.requestsTo(id)) request.path,
};

void _forget(ProfileHarness harness) => harness.network.requests.clear();

/// The connection the playbacks page on screen reads: what its Now playing
/// section was handed.
String _nowPlayingReads(WidgetTester tester) => tester
    .widget<StreamNowPlayingSection>(find.byType(StreamNowPlayingSection))
    .instanceId;

String _lensOf(ProviderContainer container, ServiceKey service) =>
    container.read(activeInstanceProvider(service))!.id;

/// Chooses [name] in the lens sheet the badge opens.
Future<void> _chooseInLensSheet(WidgetTester tester, String name) async {
  await tester.tap(find.byType(InstanceLensBadge));
  await _answer(tester);
  // The sheet is the last thing in the tree: the badge and the page behind it
  // may say the same word.
  await tester.tap(find.text(name).last);
  await _answer(tester);
}

void main() {
  group('Jellyfin', () {
    testWidgets('opened on the cabin, every tab reads the cabin, the header '
        'names it and the lens stays at home', (tester) async {
      final (harness, router, container) = await _app(tester, _twoJellyfin);
      router.go(
        ServiceRoutes.streamActivity(
          _jellyfin,
          instanceId: WorldIds.jellyfinCabin,
        ),
      );
      await _answer(tester);
      expect(_badge(tester), 'Cabin');
      expect(_nowPlayingReads(tester), WorldIds.jellyfinCabin);

      // The Overview: the cabin's address on the identity line, and the
      // cabin's own libraries asked for. Its sessions are the read the
      // playbacks page already made of the cabin: the figure and Now playing
      // share it, so it is not asked again.
      _forget(harness);
      await _openTab(tester, ServiceTab.overview);
      expect(_badge(tester), 'Cabin');
      expect(find.textContaining('cabin.home.arpa'), findsWidgets);
      expect(find.textContaining('nas.home.arpa'), findsNothing);
      expect(
        _reached(harness, WorldIds.jellyfinCabin),
        contains('/Library/VirtualFolders'),
      );
      expect(_nowPlayingReads(tester), WorldIds.jellyfinCabin);
      expect(_reached(harness, WorldIds.jellyfin), isEmpty);

      // Libraries: each room opens on the cabin, so its browse reads it.
      await _openTab(tester, ServiceTab.libraries);
      expect(_badge(tester), 'Cabin');
      await tester.tap(find.text('Films').first);
      await _answer(tester);
      expect(router.state.uri.queryParameters['i'], WorldIds.jellyfinCabin);
      router.pop();
      await _answer(tester);

      // Every capability tab asks the cabin, and never home.
      for (final (tab, path) in [
        (ServiceTab.users, '/Users'),
        (ServiceTab.devices, '/Devices'),
        (ServiceTab.tasks, '/ScheduledTasks'),
      ]) {
        _forget(harness);
        await _openTab(tester, tab);
        expect(_badge(tester), 'Cabin', reason: tab.label);
        expect(
          _reached(harness, WorldIds.jellyfinCabin),
          contains(path),
          reason: '${tab.label} reads the cabin',
        );
        expect(
          _reached(harness, WorldIds.jellyfin),
          isNot(contains(path)),
          reason: '${tab.label} does not read home',
        );
      }

      // Opening it moved nothing else.
      expect(_lensOf(container, _jellyfin), WorldIds.jellyfin);

      await _close(tester, harness, container);
    });

    testWidgets('choosing home in the lens sheet mid-visit makes the rest of '
        'the visit read home', (tester) async {
      final (harness, router, container) = await _app(tester, _twoJellyfin);
      router.go(
        ServiceRoutes.streamActivity(
          _jellyfin,
          instanceId: WorldIds.jellyfinCabin,
        ),
      );
      await _answer(tester);
      await _openTab(tester, ServiceTab.overview);
      expect(_badge(tester), 'Cabin');

      await _chooseInLensSheet(tester, 'Jellyfin 1');
      expect(_badge(tester), 'Jellyfin 1');
      expect(_lensOf(container, _jellyfin), WorldIds.jellyfin);
      expect(find.textContaining('nas.home.arpa'), findsWidgets);

      _forget(harness);
      await _openTab(tester, ServiceTab.users);
      expect(_reached(harness, WorldIds.jellyfin), contains('/Users'));
      expect(
        _reached(harness, WorldIds.jellyfinCabin),
        isNot(contains('/Users')),
      );

      // The Activity tab was opened with `?i=` for the cabin, and `goBranch`
      // puts it back as it was left. That link was read when it arrived: it is
      // not a second one, and it does not take the visit back to the cabin.
      await _openTab(tester, ServiceTab.activity);
      expect(_badge(tester), 'Jellyfin 1');
      expect(_nowPlayingReads(tester), WorldIds.jellyfin);
      await _openTab(tester, ServiceTab.overview);
      expect(_badge(tester), 'Jellyfin 1');
      expect(find.textContaining('nas.home.arpa'), findsWidgets);

      await _close(tester, harness, container);
    });

    testWidgets('choosing the cabin moves the lens as it always did, and the '
        'tabs read it', (tester) async {
      final (harness, router, container) = await _app(tester, _twoJellyfin);
      router.go(ServiceRoutes.jellyfinOverview);
      await _answer(tester);
      expect(_badge(tester), 'Jellyfin 1');

      await _chooseInLensSheet(tester, 'Cabin');
      expect(_badge(tester), 'Cabin');
      expect(_lensOf(container, _jellyfin), WorldIds.jellyfinCabin);

      _forget(harness);
      await _openTab(tester, ServiceTab.users);
      expect(_reached(harness, WorldIds.jellyfinCabin), contains('/Users'));
      expect(_reached(harness, WorldIds.jellyfin), isNot(contains('/Users')));

      await _close(tester, harness, container);
    });

    testWidgets('the visit ends with the service: the next one, opened with no '
        'link, reads the lens', (tester) async {
      final (harness, router, container) = await _app(tester, _twoJellyfin);
      router.go(
        ServiceRoutes.streamActivity(
          _jellyfin,
          instanceId: WorldIds.jellyfinCabin,
        ),
      );
      await _answer(tester);
      await _openTab(tester, ServiceTab.users);
      expect(_badge(tester), 'Cabin');

      router.go(ServiceRoutes.stack);
      await _answer(tester);

      _forget(harness);
      router.go(ServiceRoutes.jellyfinUsers);
      await _answer(tester);
      expect(_badge(tester), 'Jellyfin 1');
      expect(_reached(harness, WorldIds.jellyfin), contains('/Users'));
      expect(
        _reached(harness, WorldIds.jellyfinCabin),
        isNot(contains('/Users')),
      );

      await _close(tester, harness, container);
    });

    testWidgets('a link naming no Jellyfin reads the lens', (tester) async {
      final (harness, router, container) = await _app(tester, _twoJellyfin);

      // Gone, another service's, and blank: each on a tab the others have not
      // read, whose answer is then not already held from the one before.
      for (final (dead, tab, path) in [
        ('gone', ServiceTab.users, '/Users'),
        (WorldIds.seerr, ServiceTab.devices, '/Devices'),
        ('', ServiceTab.tasks, '/ScheduledTasks'),
      ]) {
        router.go(ServiceRoutes.stack);
        await _answer(tester);
        _forget(harness);
        router.go('${ServiceRoutes.jellyfinOverview}?i=$dead');
        await _answer(tester);
        await _openTab(tester, tab);
        expect(_badge(tester), 'Jellyfin 1', reason: 'i=$dead');
        expect(
          _reached(harness, WorldIds.jellyfin),
          contains(path),
          reason: 'i=$dead',
        );
        expect(
          _reached(harness, WorldIds.jellyfinCabin),
          isNot(contains(path)),
          reason: 'i=$dead',
        );
      }

      await _close(tester, harness, container);
    });

    testWidgets('one connection has no badge and reads the one it has, with or '
        'without a link', (tester) async {
      final (harness, router, container) = await _app(tester, Profiles.p1);

      for (final (link, tab, path) in [
        ('', ServiceTab.users, '/Users'),
        ('?i=${WorldIds.jellyfin}', ServiceTab.devices, '/Devices'),
        ('?i=gone', ServiceTab.tasks, '/ScheduledTasks'),
      ]) {
        router.go(ServiceRoutes.stack);
        await _answer(tester);
        _forget(harness);
        router.go('${ServiceRoutes.jellyfinOverview}$link');
        await _answer(tester);
        await _openTab(tester, tab);
        expect(_badge(tester), isNull, reason: link);
        expect(
          _reached(harness, WorldIds.jellyfin),
          contains(path),
          reason: link,
        );
      }

      await _close(tester, harness, container);
    });

    testWidgets('a cabin that does not answer is said on the Overview as the '
        'cabin, at its own address, while home answers', (tester) async {
      final (harness, router, container) = await _app(
        tester,
        Profiles.p1.withConnection(
          WorldConnections.jellyfinCabin.withBehaviour(
            ConnectionBehaviour.didNotAnswer,
          ),
        ),
      );
      router.go(
        '${ServiceRoutes.jellyfinOverview}?i=${WorldIds.jellyfinCabin}',
      );
      await _answer(tester);

      expect(find.byType(ServiceOfflineState), findsOneWidget);
      expect(find.textContaining('cabin.home.arpa'), findsWidgets);
      expect(find.textContaining('nas.home.arpa'), findsNothing);

      await _close(tester, harness, container);
    });

    testWidgets('a home that does not answer is not said on the Overview of '
        'the cabin, which answers', (tester) async {
      final (harness, router, container) = await _app(
        tester,
        Profiles.p1
            .withBehaviour(WorldIds.jellyfin, ConnectionBehaviour.didNotAnswer)
            .withConnection(WorldConnections.jellyfinCabin),
      );
      router.go(
        '${ServiceRoutes.jellyfinOverview}?i=${WorldIds.jellyfinCabin}',
      );
      await _answer(tester);

      expect(find.byType(ServiceOfflineState), findsNothing);
      expect(find.text('Now playing'), findsOneWidget);
      expect(find.textContaining('cabin.home.arpa'), findsWidgets);

      await _close(tester, harness, container);
    });

    testWidgets('a household member\'s token on the cabin is told on its tabs, '
        'and the key they ask for is the cabin\'s', (tester) async {
      // Home's token is an administrator's, the cabin's a household member's:
      // the tabs that need one say so for the connection they read.
      final (harness, router, container) = await _app(
        tester,
        Profiles.p1.withConnection(
          WorldConnections.jellyfinCabin.withBehaviour(
            ConnectionBehaviour.readOnly,
          ),
        ),
      );
      router.go(ServiceRoutes.jellyfinUsers);
      await _answer(tester);
      expect(find.text(jellyfinNeedsAdministratorTitle), findsNothing);

      router.go(
        ServiceRoutes.streamActivity(
          _jellyfin,
          instanceId: WorldIds.jellyfinCabin,
        ),
      );
      await _answer(tester);
      await _openTab(tester, ServiceTab.users);
      expect(find.text(jellyfinNeedsAdministratorTitle), findsOneWidget);
      await _openTab(tester, ServiceTab.libraries);
      expect(find.text(jellyfinNeedsAdministratorTitle), findsOneWidget);

      await tester.tap(find.text('Update the key'));
      await _answer(tester);
      expect(
        router.state.uri.toString(),
        ServiceRoutes.settingsForConnection(_jellyfin, WorldIds.jellyfinCabin),
      );

      await _close(tester, harness, container);
    });

    testWidgets('a page pushed inside a tab keeps its place across a tab '
        'switch, and the connection it is on', (tester) async {
      final (harness, router, container) = await _app(tester, _twoJellyfin);
      router.go(
        ServiceRoutes.jellyfinItem(
          'jf-spring',
          instanceId: WorldIds.jellyfinCabin,
        ),
      );
      await _answer(tester);
      expect(find.byType(StreamItemScreen), findsOneWidget);
      expect(
        harness.network.requestsTo(WorldIds.jellyfinCabin).map((r) => r.path),
        contains('/Items/jf-spring'),
      );

      // `goBranch`, as the bar's own tap does: the Libraries branch keeps its
      // stack while Overview is in front.
      final shell = StatefulNavigationShell.of(
        tester.element(find.byType(StreamItemScreen)),
      );
      final tabs = tabsFor(_jellyfin)!;
      shell.goBranch(tabs.indexOf(ServiceTab.overview));
      await _answer(tester);
      expect(find.byType(StreamItemScreen), findsNothing);
      expect(_badge(tester), 'Cabin');

      shell.goBranch(tabs.indexOf(ServiceTab.libraries));
      await _answer(tester);
      expect(find.byType(StreamItemScreen), findsOneWidget);
      expect(router.state.uri.queryParameters['i'], WorldIds.jellyfinCabin);

      await _close(tester, harness, container);
    });
  });

  group('in a desktop window', () {
    testWidgets('the header names the connection in view, on every tab', (
      tester,
    ) async {
      final (harness, router, container) = await _app(
        tester,
        _twoJellyfin,
        size: const Size(1440, 900),
      );
      router.go(
        ServiceRoutes.streamActivity(
          _jellyfin,
          instanceId: WorldIds.jellyfinCabin,
        ),
      );
      await _answer(tester);
      expect(_badge(tester), 'Cabin');

      _forget(harness);
      await _openTab(tester, ServiceTab.users);
      expect(_badge(tester), 'Cabin');
      expect(_reached(harness, WorldIds.jellyfinCabin), contains('/Users'));
      expect(_reached(harness, WorldIds.jellyfin), isNot(contains('/Users')));
      expect(_lensOf(container, _jellyfin), WorldIds.jellyfin);

      await _chooseInLensSheet(tester, 'Jellyfin 1');
      expect(_badge(tester), 'Jellyfin 1');

      await _close(tester, harness, container);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets(
      'the strip above does not name a second connection at a tab, and names '
      'the one a pushed page is on',
      (tester) async {
        final (harness, router, container) = await _app(
          tester,
          _twoJellyfin,
          size: const Size(1440, 900),
        );
        router.go(
          ServiceRoutes.streamActivity(
            _jellyfin,
            instanceId: WorldIds.jellyfinCabin,
          ),
        );
        await _answer(tester);
        await _openTab(tester, ServiceTab.users);
        // The location at a tab's root says the lens, or a link already read:
        // the header's badge is the one reading.
        expect(find.textContaining('Lens: '), findsNothing);
        expect(_badge(tester), 'Cabin');

        // A page pushed from a tab is one connection's, and says which.
        router.go(
          ServiceRoutes.jellyfinItem(
            'jf-spring',
            instanceId: WorldIds.jellyfinCabin,
          ),
        );
        await _answer(tester);
        expect(find.text('Lens: Cabin'), findsOneWidget);

        await _close(tester, harness, container);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });

  group('Plex', () {
    testWidgets('opened on the cabin, every tab reads the cabin and the lens '
        'stays at home', (tester) async {
      final (harness, router, container) = await _app(tester, _twoPlex);
      router.go(
        ServiceRoutes.streamActivity(_plex, instanceId: WorldIds.plexCabin),
      );
      await _answer(tester);
      expect(_badge(tester), 'Cabin');
      // Activities reads the cabin's on deck, beside who is watching there.
      expect(
        _reached(harness, WorldIds.plexCabin),
        contains('/hubs/continueWatching'),
      );

      // The Overview's glance shares that read; its own are the cabin's too.
      _forget(harness);
      await _openTab(tester, ServiceTab.overview);
      expect(_badge(tester), 'Cabin');
      expect(find.textContaining('cabin.home.arpa'), findsWidgets);
      expect(find.textContaining('nas.home.arpa'), findsNothing);
      expect(
        _reached(harness, WorldIds.plexCabin),
        contains('/library/sections'),
      );
      expect(_reached(harness, WorldIds.plex), isEmpty);

      await _openTab(tester, ServiceTab.libraries);
      expect(_badge(tester), 'Cabin');
      await tester.tap(find.text('Movies').first);
      await _answer(tester);
      expect(router.state.uri.queryParameters['i'], WorldIds.plexCabin);
      router.pop();
      await _answer(tester);

      for (final (tab, path) in [
        (ServiceTab.devices, '/devices'),
        (ServiceTab.playlists, '/playlists'),
      ]) {
        _forget(harness);
        await _openTab(tester, tab);
        expect(_badge(tester), 'Cabin', reason: tab.label);
        expect(
          _reached(harness, WorldIds.plexCabin),
          contains(path),
          reason: '${tab.label} reads the cabin',
        );
        expect(
          _reached(harness, WorldIds.plex),
          isNot(contains(path)),
          reason: '${tab.label} does not read home',
        );
      }

      // The tab the link opened reads the cabin too.
      await _openTab(tester, ServiceTab.activities);
      expect(_badge(tester), 'Cabin');
      expect(_nowPlayingReads(tester), WorldIds.plexCabin);
      expect(_lensOf(container, _plex), WorldIds.plex);

      await _close(tester, harness, container);
    });

    testWidgets('choosing home in the lens sheet mid-visit makes the rest of '
        'the visit read home', (tester) async {
      final (harness, router, container) = await _app(tester, _twoPlex);
      router.go(
        ServiceRoutes.streamActivity(_plex, instanceId: WorldIds.plexCabin),
      );
      await _answer(tester);
      await _openTab(tester, ServiceTab.devices);
      expect(_badge(tester), 'Cabin');

      await _chooseInLensSheet(tester, 'Plex 1');
      expect(_badge(tester), 'Plex 1');
      expect(_lensOf(container, _plex), WorldIds.plex);

      _forget(harness);
      await _openTab(tester, ServiceTab.playlists);
      expect(_reached(harness, WorldIds.plex), contains('/playlists'));
      expect(
        _reached(harness, WorldIds.plexCabin),
        isNot(contains('/playlists')),
      );

      // Activities came from the link: back on it, still home.
      await _openTab(tester, ServiceTab.activities);
      expect(_badge(tester), 'Plex 1');
      expect(_nowPlayingReads(tester), WorldIds.plex);

      await _close(tester, harness, container);
    });

    testWidgets('the visit ends with the service', (tester) async {
      final (harness, router, container) = await _app(tester, _twoPlex);
      router.go(
        ServiceRoutes.streamActivity(_plex, instanceId: WorldIds.plexCabin),
      );
      await _answer(tester);
      await _openTab(tester, ServiceTab.playlists);
      expect(_badge(tester), 'Cabin');

      router.go(ServiceRoutes.stack);
      await _answer(tester);

      _forget(harness);
      router.go(ServiceRoutes.plexPlaylists);
      await _answer(tester);
      expect(_badge(tester), 'Plex 1');
      expect(_reached(harness, WorldIds.plex), contains('/playlists'));
      expect(
        _reached(harness, WorldIds.plexCabin),
        isNot(contains('/playlists')),
      );

      await _close(tester, harness, container);
    });
  });
}
