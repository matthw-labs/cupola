/// Play with, for an Emby title: Emby's own app where the platform says it is
/// installed, the browser always, and never a Jellyfin player. The choice
/// is Emby's own, kept apart from Jellyfin's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/stream_player_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';
import 'package:cupola/features/stream/data/stream_app_launcher.dart';
import 'package:cupola/features/stream/domain/stream_players.dart';
import 'package:cupola/features/stream/presentation/play_with.dart';

import '../../test_helpers/profiles/profiles.dart';

class _FakeLauncher implements StreamAppLauncher {
  _FakeLauncher({this.installed = const {}});

  final Set<String> installed;
  final opened = <Uri>[];

  @override
  Future<bool> canOpen(Uri url) async => installed.contains(url.scheme);

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

class _Remembered extends StreamPlayerChoiceNotifier {
  _Remembered(this.player, {required super.key});

  final StreamPlayer? player;

  @override
  StreamPlayer? build() => player;
}

final _webUrl = Uri.parse(
  'https://emby.example.com/web/index.html#!/item?id=item1&serverId=srv1',
);

const _emby = ServiceInstance(
  id: 'emby-1',
  service: ServiceKey.emby,
  url: 'https://emby.example.com',
  credential: 'k',
  viewerId: 'usr1',
);

const _jellyfin = ServiceInstance(
  id: 'jf-1',
  service: ServiceKey.jellyfin,
  url: 'https://jellyfin.example.com',
  credential: 'k',
  viewerId: 'usr1',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakeLauncher launcher,
  ServiceInstance server = _emby,
  StreamPlayer? embyChoice,
  StreamPlayer? jellyfinChoice,
}) async {
  final container = ProviderContainer(
    overrides: [
      streamAppLauncherProvider.overrideWithValue(launcher),
      embyServerIdProvider.overrideWith((ref, instanceId) async => 'srv1'),
      jellyfinServerIdProvider.overrideWith((ref, instanceId) async => 'srv1'),
      embyPlayerChoiceProvider.overrideWith(
        () => _Remembered(embyChoice, key: 'stream_player_emby'),
      ),
      streamPlayerChoiceProvider.overrideWith(
        () => _Remembered(jellyfinChoice, key: 'stream_player'),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: FilledButton(
                onPressed: () => playWith(
                  context,
                  ref,
                  server: server,
                  itemId: 'item1',
                  title: 'Sintel',
                  webUrl: _webUrl,
                ),
                child: const Text('Play'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

Future<void> _play(WidgetTester tester) async {
  await tester.tap(find.text('Play'));
  await tester.pumpAndSettle();
}

void main() {
  group('on iOS', () {
    testWidgets('Emby\'s app and the browser, and no Jellyfin player', (
      tester,
    ) async {
      final launcher = _FakeLauncher(
        installed: {'emby', 'swiftfin', 'streamyfin', 'fladder'},
      );
      await _pump(tester, launcher: launcher);

      await _play(tester);

      expect(find.text('Play with'), findsOneWidget);
      expect(find.text('Sintel'), findsOneWidget);
      expect(find.text('Emby'), findsOneWidget);
      expect(find.text('Emby in the browser'), findsOneWidget);
      for (final jellyfinOnly in [
        'Swiftfin',
        'Streamyfin',
        'Fladder',
        'Infuse',
        'Jellyfin in the browser',
      ]) {
        expect(find.text(jellyfinOnly), findsNothing, reason: jellyfinOnly);
      }
      expect(
        find.text('Change it in Settings, on your Emby connection.'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Emby')).dy,
        lessThan(tester.getTopLeft(find.text('Emby in the browser')).dy),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('the app opens the item by server id and item id', (
      tester,
    ) async {
      final launcher = _FakeLauncher(installed: {'emby'});
      await _pump(tester, launcher: launcher);

      await _play(tester);
      await tester.tap(find.text('Emby'));
      await tester.pumpAndSettle();

      expect(
        launcher.opened.single.toString(),
        'emby://items?serverId=srv1&itemId=item1',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('the browser opens the web link that names the server', (
      tester,
    ) async {
      final launcher = _FakeLauncher(installed: {'emby'});
      await _pump(tester, launcher: launcher);

      await _play(tester);
      await tester.tap(find.text('Emby in the browser'));
      await tester.pumpAndSettle();

      expect(launcher.opened.single, _webUrl);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('with the app not installed, the browser opens with no sheet', (
      tester,
    ) async {
      final launcher = _FakeLauncher(installed: {'swiftfin'});
      await _pump(tester, launcher: launcher);

      await _play(tester);

      expect(find.text('Play with'), findsNothing);
      expect(launcher.opened.single, _webUrl);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('ticking the box remembers it for Emby, and Jellyfin keeps '
        'its own', (tester) async {
      final launcher = _FakeLauncher(installed: {'emby'});
      final container = await _pump(
        tester,
        launcher: launcher,
        jellyfinChoice: StreamPlayer.swiftfin,
      );

      await _play(tester);
      await tester.tap(find.text('Remember my choice'));
      await tester.pump();
      await tester.tap(find.text('Emby'));
      await tester.pumpAndSettle();

      expect(container.read(embyPlayerChoiceProvider), StreamPlayer.emby);
      expect(
        container.read(streamPlayerChoiceProvider),
        StreamPlayer.swiftfin,
        reason: 'a Jellyfin choice is not Emby\'s to forget or to set',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a remembered Jellyfin player is no answer for an Emby title', (
      tester,
    ) async {
      final launcher = _FakeLauncher(installed: {'emby', 'swiftfin'});
      final container = await _pump(
        tester,
        launcher: launcher,
        jellyfinChoice: StreamPlayer.swiftfin,
      );

      await _play(tester);

      expect(find.text('Play with'), findsOneWidget);
      expect(launcher.opened, isEmpty);
      expect(container.read(streamPlayerChoiceProvider), StreamPlayer.swiftfin);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a remembered Emby app opens at once, with no sheet', (
      tester,
    ) async {
      final launcher = _FakeLauncher(installed: {'emby'});
      await _pump(tester, launcher: launcher, embyChoice: StreamPlayer.emby);

      await _play(tester);

      expect(find.text('Play with'), findsNothing);
      expect(launcher.opened.single.scheme, 'emby');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Jellyfin never offers Emby\'s app', (tester) async {
      final launcher = _FakeLauncher(installed: {'emby', 'swiftfin'});
      await _pump(tester, launcher: launcher, server: _jellyfin);

      await _play(tester);

      expect(find.text('Swiftfin'), findsOneWidget);
      expect(find.text('Emby'), findsNothing);
      expect(find.text('Emby in the browser'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  testWidgets('on Android the app link is the path form', (tester) async {
    final launcher = _FakeLauncher(installed: {'emby'});
    await _pump(tester, launcher: launcher, embyChoice: StreamPlayer.emby);

    await _play(tester);

    expect(launcher.opened.single.toString(), 'emby://items/srv1/item1');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('on a desktop: the browser at once, with no sheet', (
    tester,
  ) async {
    final launcher = _FakeLauncher(installed: {'emby'});
    await _pump(tester, launcher: launcher);

    await _play(tester);

    expect(find.text('Play with'), findsNothing);
    expect(launcher.opened.single, _webUrl);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('without the server id, Emby\'s app is not offered', (
    tester,
  ) async {
    final launcher = _FakeLauncher(installed: {'emby'});
    final container = ProviderContainer(
      overrides: [
        streamAppLauncherProvider.overrideWithValue(launcher),
        embyServerIdProvider.overrideWith((ref, instanceId) async => null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: FilledButton(
                  onPressed: () => playWith(
                    context,
                    ref,
                    server: _emby,
                    itemId: 'item1',
                    title: 'Sintel',
                    webUrl: _webUrl,
                  ),
                  child: const Text('Play'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await _play(tester);

    expect(find.text('Play with'), findsNothing);
    expect(launcher.opened.single, _webUrl);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  group('the Settings row', () {
    Future<ProviderContainer> pumpSettings(
      WidgetTester tester, {
      required Set<String> installed,
    }) async {
      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = await ProfileHarness.start(
        Profiles.p1.withConnection(WorldConnections.emby),
        overrides: [
          streamAppLauncherProvider.overrideWithValue(
            _FakeLauncher(installed: installed),
          ),
        ],
      );
      harness.network.followFakeTime(tester.binding);
      final container = harness.container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: ServiceSettingsScreen(
              service: ServiceKey.emby,
              instanceId: WorldIds.emby,
              certificateProber: (_, {pinnedFingerprint = ''}) async => null,
              localNetworkProbe: (_, {timeout = Duration.zero}) async =>
                  LocalNetworkAccess.unrestricted,
            ),
          ),
        ),
      );
      await harness.settle(tester);
      return container;
    }

    testWidgets('on a phone Emby\'s page says where a title plays, and saves '
        'the choice under Emby\'s own key', (tester) async {
      final container = await pumpSettings(tester, installed: {'emby'});
      await tester.pumpAndSettle();

      expect(find.text('Play with'), findsOneWidget);
      expect(find.text('Ask every time'), findsOneWidget);

      await tester.tap(find.text('Play with'));
      await tester.pumpAndSettle();

      expect(find.text('Emby titles'), findsOneWidget);
      expect(find.text('Emby'), findsWidgets);
      expect(find.text('Emby in the browser'), findsOneWidget);
      expect(find.text('Swiftfin'), findsNothing);
      expect(find.text('Jellyfin in the browser'), findsNothing);

      await tester.tap(find.widgetWithText(InkWell, 'Emby').last);
      await tester.pumpAndSettle();

      expect(container.read(embyPlayerChoiceProvider), StreamPlayer.emby);
      expect(container.read(streamPlayerChoiceProvider), isNull);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('stream_player_emby'), 'emby');
      expect(prefs.getString('stream_player'), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('on a desktop the row is not offered', (tester) async {
      await pumpSettings(tester, installed: {'emby'});
      await tester.pumpAndSettle();

      expect(find.text('Play with'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}
