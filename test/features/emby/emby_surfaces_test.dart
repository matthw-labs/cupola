/// Emby's own rooms, drawn over the demo world's fake server with nothing
/// stubbed above the socket: the Overview with its Now playing slab, the
/// Libraries and the library, an item, the administrator placeholder, and
/// the remote control of a session.
///
/// Every request is checked for the route it asked: Emby answers 404 or 500
/// to Jellyfin's spellings, so a surface that still read a Jellyfin provider
/// would draw a fault here, not the household's titles.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/demo/world/fakes/media_fakes.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_admin_placeholder.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/data/stream_app_launcher.dart';
import 'package:cupola/features/stream/presentation/stream_item_screen.dart';
import 'package:cupola/features/stream/presentation/stream_libraries_screen.dart';
import 'package:cupola/features/stream/presentation/stream_library_screen.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';

import '../../test_helpers/profiles/profiles.dart';

final _withEmby = Profiles.p1.withConnection(WorldConnections.emby);

/// Anna's own token on the same server: refused the administrator's reads.
final _annaOnEmby = Profiles.p1.withConnection(
  ProfileConnection(
    WorldConnections.emby.instance.copyWith(viewerId: EmbyFake.annaId),
    behaviour: ConnectionBehaviour.readOnly,
  ),
);

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget child,
) async {
  final harness = await ProfileHarness.start(profile);
  await tester.binding.setSurfaceSize(const Size(430, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  await harness.settle(tester);
  return harness;
}

/// Answers that no app is installed, and records what was opened.
class _Launcher implements StreamAppLauncher {
  final opened = <Uri>[];

  @override
  Future<bool> canOpen(Uri url) async => false;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

Iterable<String> _paths(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.emby)
    .map((r) => '${r.method} ${r.path}');

void main() {
  group('the Overview', () {
    testWidgets('draws the Now playing slab, the libraries and no fault', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: StreamOverviewScreen(service: ServiceKey.emby)),
      );

      expect(find.text('Now playing'), findsWidgets);
      expect(find.textContaining('Sintel'), findsWidgets);
      final libraries = find.byWidgetPredicate(
        (widget) =>
            widget is ServiceOverviewSection && widget.title == 'Libraries',
      );
      expect(libraries, findsOneWidget);
      expect(
        find.descendant(of: libraries, matching: find.text('Movies')),
        findsOneWidget,
      );
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.text(needsAdministratorTitle(ServiceKey.emby)), findsNothing);
      expect(
        _paths(harness),
        contains('GET /emby/Library/VirtualFolders/Query'),
      );
      await harness.unmount(tester);
    });

    testWidgets('on a household member\'s token: the libraries still list '
        '(Emby lets a member read them), and the playback note stands', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _annaOnEmby,
        const Scaffold(body: StreamOverviewScreen(service: ServiceKey.emby)),
      );

      final libraries = find.byWidgetPredicate(
        (widget) =>
            widget is ServiceOverviewSection && widget.title == 'Libraries',
      );
      expect(
        find.descendant(of: libraries, matching: find.text('Movies')),
        findsOneWidget,
      );
      expect(find.text('Needs an Emby administrator'), findsNothing);
      expect(
        find.text('Showing only this account\'s playback'),
        findsOneWidget,
      );
      expect(find.textContaining('refused'), findsNothing);
      expect(find.byType(AppErrorState), findsNothing);
      // The kind came from Emby's own route, never Jellyfin's `/Users/Me`.
      expect(_paths(harness), isNot(contains('GET /emby/Users/Me')));
      expect(_paths(harness), contains('GET /emby/Users/Query'));
      await harness.unmount(tester);
    });
  });

  group('the tabs', () {
    testWidgets('Libraries lists the three libraries from Emby\'s route', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: StreamLibrariesScreen(service: ServiceKey.emby)),
      );

      for (final name in ['Movies', 'Series', 'Music']) {
        expect(find.text(name), findsWidgets, reason: name);
      }
      expect(
        _paths(harness),
        contains('GET /emby/Library/VirtualFolders/Query'),
      );
      await harness.unmount(tester);
    });

    testWidgets('Libraries, on a member\'s token, lists them: Emby does not '
        'hide them behind an administrator', (tester) async {
      final harness = await _pump(
        tester,
        _annaOnEmby,
        const Scaffold(body: StreamLibrariesScreen(service: ServiceKey.emby)),
      );

      expect(find.text('Movies'), findsWidgets);
      expect(find.text('Needs an Emby administrator'), findsNothing);
      expect(find.byType(AppErrorState), findsNothing);
      await harness.unmount(tester);
    });

    for (final (name, screen, what) in <(String, Widget, String)>[
      (
        'Users',
        const JellyfinUsersScreen(service: ServiceKey.emby),
        'list users',
      ),
      (
        'Devices',
        const JellyfinDevicesScreen(service: ServiceKey.emby),
        'list devices',
      ),
      (
        'Tasks',
        const JellyfinTasksScreen(service: ServiceKey.emby),
        'list scheduled tasks',
      ),
    ]) {
      testWidgets('$name on a member\'s token: the Emby placeholder, no '
          'refusal drawn', (tester) async {
        final harness = await _pump(
          tester,
          _annaOnEmby,
          Scaffold(body: screen),
        );

        expect(find.text('Needs an Emby administrator'), findsOneWidget);
        expect(find.textContaining(what), findsOneWidget);
        expect(find.textContaining('Jellyfin'), findsNothing);
        expect(find.byType(AppErrorState), findsNothing);
        await harness.unmount(tester);
      });
    }

    testWidgets('Devices lists them from /Devices', (tester) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: JellyfinDevicesScreen(service: ServiceKey.emby)),
      );

      expect(find.text('Living room TV'), findsWidgets);
      expect(_paths(harness), contains('GET /emby/Devices'));
      await harness.unmount(tester);
    });

    testWidgets('Tasks reads /ScheduledTasks', (tester) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: JellyfinTasksScreen(service: ServiceKey.emby)),
      );

      expect(_paths(harness), contains('GET /emby/ScheduledTasks'));
      expect(find.byType(AppErrorState), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('Activity lists Anna\'s session and nobody else', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: JellyfinActivityScreen(service: ServiceKey.emby)),
      );

      expect(find.textContaining('Sintel'), findsWidgets);
      expect(find.byTooltip('Pause this playback'), findsOneWidget);
      expect(_paths(harness), contains('GET /emby/Sessions'));
      await harness.unmount(tester);
    });
  });

  group('a library and an item', () {
    testWidgets('the library opens whole, by name, under /emby/Items', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(
          body: StreamLibraryScreen(
            service: ServiceKey.emby,
            libraryId: '4',
            libraryTitle: 'Series',
          ),
        ),
      );

      expect(find.widgetWithText(MediaBrowseFilterChip, 'All'), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      final shelf = harness.network.requests
          .where((r) => r.method == 'GET' && r.path == '/emby/Items')
          .last;
      expect(shelf.query['ParentId'] ?? shelf.query['parentId'], '4');
      expect(shelf.query['sortBy'] ?? shelf.query['SortBy'], 'SortName');
      await harness.unmount(tester);
    });

    testWidgets('Next up is the Activity\'s, read from /Shows/NextUp', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: JellyfinActivityScreen(service: ServiceKey.emby)),
      );

      expect(find.text('Next up'), findsOneWidget);
      expect(_paths(harness), contains(startsWith('GET /emby/Shows/NextUp')));
      expect(find.byType(AppErrorState), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('an item opens by its numeric id, with Open in Emby', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(
          body: StreamItemScreen(service: ServiceKey.emby, itemId: '100'),
        ),
      );

      expect(find.byType(AppErrorState), findsNothing);
      expect(
        _paths(harness),
        contains('GET /emby/Users/${EmbyFake.operatorId}/Items/100'),
      );
      expect(find.textContaining('in Emby'), findsOneWidget);
      await harness.unmount(tester);
    });
  });

  testWidgets('Open in Emby opens the web client at the item, naming the '
      'server', (tester) async {
    final launcher = _Launcher();
    final harness = await ProfileHarness.start(
      _withEmby,
      overrides: [streamAppLauncherProvider.overrideWithValue(launcher)],
    );
    await tester.binding.setSurfaceSize(const Size(430, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: StreamItemScreen(service: ServiceKey.emby, itemId: '100'),
          ),
        ),
      ),
    );
    await harness.settle(tester);

    await tester.tap(find.textContaining('in Emby'));
    await harness.settle(tester);

    expect(
      launcher.opened.single.toString(),
      'http://tower.home.arpa:8096/web/index.html#!/item?id=100'
      '&serverId=${EmbyFake.serverId}',
    );
    await harness.unmount(tester);
  });

  group('a session\'s remote control', () {
    testWidgets('Pause is /emby/Sessions/{id}/Playing/Pause', (tester) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: JellyfinActivityScreen(service: ServiceKey.emby)),
      );

      await tester.tap(find.byTooltip('Pause this playback'));
      await harness.settle(tester);
      // The page reads the player again to see that it paused: the world's
      // player obeys, so the page says nothing more and draws Resume.
      await tester.pump(const Duration(seconds: 7));
      await harness.settle(tester);
      expect(find.textContaining('did not pause'), findsNothing);
      expect(find.byTooltip('Resume this playback'), findsOneWidget);

      expect(
        _paths(harness),
        contains(
          'POST /emby/Sessions/emby-session-anna-livingroom/Playing/Pause',
        ),
      );
      expect(find.byType(AppErrorState), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('Message is /emby/Sessions/{id}/Message, with the text', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: JellyfinActivityScreen(service: ServiceKey.emby)),
      );

      await tester.tap(find.byTooltip('Send a message to this player'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Dinner in ten');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await harness.settle(tester);

      final sent = harness.network
          .requestsTo(WorldIds.emby)
          .where((r) => r.path.endsWith('/Message'))
          .single;
      expect(sent.method, 'POST');
      expect(sent.path, '/emby/Sessions/emby-session-anna-livingroom/Message');
      expect('${sent.json}${sent.query}', contains('Dinner in ten'));
      expect(find.text('Message sent to ${WorldPeople.anna}'), findsOneWidget);
      await harness.unmount(tester);
    });
  });
}
