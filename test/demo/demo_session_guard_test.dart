import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/features/outside/data/outside_background.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The demo runs inside the production app, on a phone that may hold the
/// visitor's own preferences and keychain. These hold that it writes to
/// none of them, reaches no network, and leaves the app as it found it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesStorePlatform real;

  setUp(() {
    // The phone's own preferences: one the visitor set before the demo.
    real = InMemorySharedPreferencesStore.withData({'flutter.theme': 'dark'});
    SharedPreferencesStorePlatform.instance = real;
    SharedPreferences.resetStatic();
  });

  Future<(DemoSession, ProviderContainer)> open() async {
    final session = await DemoSession.start(leaving: const SettingsModel());
    addTearDown(session.end);
    final container = ProviderContainer(overrides: session.overrides);
    addTearDown(container.dispose);
    return (session, container);
  }

  test('an app with a connection never opens the demo', () async {
    final settings = (await open()).$1.network.profile.settings;
    await expectLater(
      DemoSession.start(leaving: settings),
      throwsA(isA<DemoRefused>()),
    );
  });

  test('preferences written in the demo never reach the real store', () async {
    final (session, container) = await open();
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getString('theme'), isNull, reason: 'the demo reads none');
    await prefs.setString('theme', 'light');
    await prefs.setString('written_in_demo', 'yes');
    expect(await real.getAll(), {'flutter.theme': 'dark'});

    await session.end();
    expect(SharedPreferencesStorePlatform.instance, same(real));
    final after = await SharedPreferences.getInstance();
    expect(after.getString('theme'), 'dark');
    expect(after.getString('written_in_demo'), isNull);
  });

  test('the secure store lives in memory', () async {
    final (_, container) = await open();
    expect(
      container.read(secureSettingsStoreProvider),
      isA<MemorySecureSettingsStore>(),
    );
  });

  test('every HttpClient lands on the world, and only while it runs', () async {
    final before = HttpOverrides.current;
    final (session, _) = await open();
    expect(HttpOverrides.current, isNot(same(before)));

    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('http://nas.home.arpa:7878/api/v3/system/status'),
    );
    final response = await request.close();
    await response.drain<void>();
    client.close();
    expect(session.network.requests, isNotEmpty);
    expect(session.network.unanswered, isEmpty);

    await session.end();
    expect(HttpOverrides.current, same(before));
  });

  test('a raw socket is refused before it dials', () async {
    final before = IOOverrides.current;
    final (session, _) = await open();
    await expectLater(
      Socket.connect('127.0.0.1', 9),
      throwsA(
        isA<SocketException>().having(
          (e) => e.message,
          'message',
          'The demo has no network',
        ),
      ),
    );
    await session.end();
    expect(IOOverrides.current, same(before));
  });

  test('the background run, the widgets and notifications stay off', () async {
    final (_, container) = await open();
    expect(container.read(outsideSchedulerProvider), isNull);
    final notifications = container.read(releaseSearchNotificationsProvider);
    expect(await notifications.permissionGranted(), isTrue);
    expect(await notifications.requestPermission(), isTrue);
  });

  test('a release search never leaves the app for a native task', () async {
    final (_, container) = await open();
    const target = ReleaseSearchTarget.movie(movieId: 1, label: 'Sintel');
    expect(
      container.read(releaseSearchReachProvider(target)),
      ReleaseSearchReach.whileOpen,
    );
  });

  test('the demo opens on the whole household, onboarding done', () async {
    final (session, container) = await open();
    expect(container.read(demoSessionProvider), same(session));
    expect(
      container.read(currentSettingsProvider).instances,
      hasLength(session.network.profile.connections.length),
    );
    expect(
      session.network.profile.connections.map((c) => c.service).toSet(),
      hasLength(18),
    );
  });

  test('ending twice is harmless', () async {
    final (session, _) = await open();
    await session.end();
    await session.end();
    expect(SharedPreferencesStorePlatform.instance, same(real));
  });
}
