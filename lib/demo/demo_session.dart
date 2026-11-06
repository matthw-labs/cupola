import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/network/connection_access_registry.dart';
import 'package:cupola/core/network/host_reach.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/network/route_poster.dart';
import 'package:cupola/core/network/unanswered_addresses.dart';
import 'package:cupola/core/startup/startup_overrides.dart';
import 'package:cupola/demo/world/artwork.dart';
import 'package:cupola/demo/world/fixtures.dart';
import 'package:cupola/demo/world/profiles.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/outside/data/outside_background.dart';
import 'package:cupola/features/outside/data/outside_keeper.dart';
import 'package:cupola/features/release_search/data/release_search_notifications.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The household the demo opens on: World A with all nineteen services, P1
/// and every service P1 leaves out.
final demoProfile = Profiles.p1
    .withConnection(WorldConnections.plex)
    .withConnection(WorldConnections.readarr)
    .withConnection(WorldConnections.transmission)
    .withConnection(WorldConnections.nzbget)
    .withConnection(WorldConnections.unraid)
    .withConnection(WorldConnections.npm)
    .withConnection(WorldConnections.emby)
    .withConnection(WorldConnections.tracearr);

/// The demo home, live: the world's servers answering inside the process,
/// and every store the app writes to held in memory.
///
/// A mode of the production app, never an identity of its own (AGENTS.md,
/// App identities): it is entered only from an onboarding with no
/// connections, so real and invented data never share a run. While it lasts:
///
///  * every `HttpClient` and WebSocket lands on [network], and a raw socket
///    (a host probe, a certificate read) is refused: nothing leaves the
///    process;
///  * preferences, the secure store and the Home's last drawings live in
///    memory, so nothing the visitor does reaches the disk or the keychain;
///  * the widgets' shelf, the background run, background release searches
///    and notifications stay off;
///  * posters go to image stores of their own, emptied on the way out.
///
/// [end] puts each of these back; the app then starts again from its real
/// stores, on the onboarding it left.
class DemoSession {
  DemoSession._(this.network, this.overrides, this._ends);

  /// The world's servers.
  final ProfileNetwork network;

  /// What the demo's `ProviderScope` is built with.
  final List<Override> overrides;

  final List<FutureOr<void> Function()> _ends;
  bool _ended = false;

  /// Opens the demo over an app whose settings are [leaving].
  ///
  /// Throws [DemoRefused] when [leaving] holds a connection: the demo is a
  /// door from an empty onboarding, never a way to put a real household
  /// aside.
  static Future<DemoSession> start({
    required SettingsModel leaving,
    AssetBundle? bundle,
    DateTime? now,
  }) async {
    if (leaving.instances.isNotEmpty) throw const DemoRefused();
    await WorldFixtures.preload(bundle ?? rootBundle);
    await WorldArtwork.preload(bundle ?? rootBundle);
    final ends = <FutureOr<void> Function()>[];

    // Preferences. `SharedPreferences` writes through whichever store the
    // platform holds at the moment of the write, so the in-memory one stays
    // in place for the whole session, and the cached instance is dropped on
    // both sides so each run reads its own.
    final realPreferences = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
    _forgetPreferencesInstance();
    final prefs = await SharedPreferences.getInstance();
    ends.add(() {
      SharedPreferencesStorePlatform.instance = realPreferences;
      _forgetPreferencesInstance();
    });

    final profile = demoProfile;
    final network = ProfileNetwork(profile, now: now);
    // The world lives: what the visitor does stays done, and the downloads
    // move with the wall clock.
    network.live();
    final clock = Stopwatch()..start();
    network.followClock(() => clock.elapsed);
    ends.add(clock.stop);
    ends.add(network.install());
    final previousIo = IOOverrides.current;
    IOOverrides.global = _NoSockets();
    ends.add(() => IOOverrides.global = previousIo);

    ends.add(WorldArtwork.forget);
    ends.add(separateImageCaches('demo'));
    ends.add(() {
      // Flutter's own memory of decoded images is keyed by address too.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    });
    // The static registries the demo's settings filled. The app's next start
    // fills them again from its own; emptied here so nothing in between
    // reads the world's.
    ends.add(() {
      ConnectionAccessRegistry.update(const []);
      CertTrustRegistry.update(const {});
      RoutePoster.update(const []);
      UnansweredAddresses.update(const []);
    });

    late final DemoSession session;
    final overrides = <Override>[
      ...startupOverrides(
        prefs: prefs,
        secureSettingsStore: MemorySecureSettingsStore(),
        initialSettings: profile.settings,
        activeInstances: profile.lens,
        onboardingCompleted: true,
        lastKnown: LastKnownStore.memory(),
      ),
      hostReachProvider.overrideWithValue(network.reach),
      npmUpstreamConnectorProvider.overrideWithValue(
        (host, port, timeout) =>
            network.reach(Uri(scheme: 'http', host: host, port: port)),
      ),
      outsideKeeperProvider.overrideWith((ref) {}),
      outsideSchedulerProvider.overrideWithValue(null),
      releaseSearchNotificationsProvider.overrideWithValue(
        _QuietNotifications(),
      ),
      // A background search is a native task, which no `HttpOverrides`
      // reaches: in the demo every search runs in the app, on the world.
      releaseSearchReachProvider.overrideWith(
        (ref, target) => ReleaseSearchReach.whileOpen,
      ),
      demoSessionProvider.overrideWith((ref) => session),
    ];
    return session = DemoSession._(network, overrides, ends);
  }

  /// Puts back everything [start] replaced, last first. Safe to call twice.
  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    for (final end in _ends.reversed) {
      await end();
    }
  }
}

/// The running demo, or null outside it.
final demoSessionProvider = Provider<DemoSession?>((ref) => null);

/// Whether the demo runs: what a screen reads to draw the demo's mark.
final demoRunningProvider = Provider<bool>(
  (ref) => ref.watch(demoSessionProvider) != null,
);

/// The demo was asked for over an app that has connections.
class DemoRefused implements Exception {
  const DemoRefused();

  @override
  String toString() => 'DemoRefused: the app has connections';
}

/// A secure store that forgets everything when the demo ends.
class MemorySecureSettingsStore implements SecureSettingsStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      _values[key] = value;

  @override
  Future<void> delete({required String key}) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}

/// Lets the next `SharedPreferences.getInstance` read the store the platform
/// holds now. The package offers this to tests alone; the demo is the one
/// run that swaps the store under a live app.
void _forgetPreferencesInstance() {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.resetStatic();
}

/// Refuses every raw socket: a host probe, a certificate read, an upstream
/// check. The world answers HTTP and WebSockets; anything else would reach
/// for a real network the demo does not have.
final class _NoSockets extends IOOverrides {
  @override
  Future<Socket> socketConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) => Future.error(
    SocketException('The demo has no network', address: null, port: port),
  );

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) => Future.error(
    SocketException('The demo has no network', address: null, port: port),
  );
}

/// Notifications in the demo: allowed, and never shown.
class _QuietNotifications extends ReleaseSearchNotifications {
  _QuietNotifications();

  @override
  Future<void> initialise() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool?> permissionGranted() async => true;

  @override
  Future<void> show(
    ReleaseSearchNotice notice, {
    required String jobId,
  }) async {}
}
