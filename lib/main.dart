import 'dart:io' show File;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationCacheDirectory, getTemporaryDirectory;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/network/artwork_cache_migration.dart';

import 'package:cupola/core/network/network_change.dart';
import 'package:cupola/core/network/network_registries.dart';
import 'package:cupola/core/platform/desktop_window.dart';
import 'package:cupola/core/platform/link_handoff.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/startup/startup_overrides.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/a11y_announce.dart';
import 'package:cupola/core/widgets/app_snapshot_cover.dart';
import 'package:cupola/core/widgets/themed_system_bars.dart';
import 'package:cupola/demo/demo_door.dart';
import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/artwork.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_accounts.dart';
import 'package:cupola/features/outside/data/outside_background.dart';
import 'package:cupola/features/outside/data/outside_keeper.dart';
import 'package:cupola/features/release_search/data/release_search_bootstrap.dart';
import 'package:cupola/features/settings/data/route_probe.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/startup_failure.dart';
import 'package:cupola/features/shell/presentation/settings_back_claim.dart';
import 'package:cupola/features/shell/presentation/startup_failure_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A library of a few hundred titles outgrows the package default of 200
  // cached posters, and every scroll past them then fetches them again.
  CachedNetworkImageProvider.defaultCacheManager = CacheManager(
    Config(
      'cupola_artwork',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1500,
    ),
  );
  // Prepares the frameless window, still hidden: it is shown once something
  // is drawn in it (see [_start]), so no await below can leave a black
  // rectangle on the screen. Inert on iOS and Android.
  await DesktopWindow.ensureReady();
  _registerBundledFontLicense();
  WorldArtwork.registerLicense();
  await _start();
}

/// Reads what the app needs, then draws it, or draws why it could not.
///
/// Every read before `runApp` is inside [attemptStartup]: one that throws or
/// never answers is a page that says so, with Retry, instead of a window (or a
/// launch screen) that stays as it is for good. Retry runs this again from the
/// top, and `runApp` replaces whichever app is drawn.
Future<void> _start() async {
  // Read beside the settings, never before them: the Home's last drawing
  // is what makes the first frame useful, and it must not make it late.
  final lastKnown = _openLastKnown();
  final outcome = await attemptStartup((reach) async {
    reach(StartupStep.preferences);
    final prefs = await SharedPreferences.getInstance();
    // Once per install, in the background: the default cache's posters are
    // not reachable through the artwork cache any more.
    unawaited(
      removeLegacyArtworkCache(
        prefs: prefs,
        temporaryDirectory: getTemporaryDirectory,
      ),
    );
    final secureSettingsStore = createSecureSettingsStore();
    final settingsService = SettingsService(prefs, secureSettingsStore);

    // Unconditional, including for a user who has background search switched
    // off. It is also what purges the records the last session left behind.
    // See its own doc.
    await configureBackgroundSearch();

    reach(StartupStep.connections);
    await settingsService.migrateFromPlaintext();
    final initialSettings = await settingsService.loadSettings();
    final onboardingCompleted = await settingsService.loadOnboardingComplete();

    return startupOverrides(
      prefs: prefs,
      secureSettingsStore: secureSettingsStore,
      initialSettings: initialSettings,
      activeInstances: settingsService.loadActiveInstances(),
      onboardingCompleted: onboardingCompleted,
      lastKnown: await lastKnown,
    );
  });

  switch (outcome) {
    case StartupReady(value: final overrides):
      runApp(
        ProviderScope(
          key: UniqueKey(),
          overrides: [...overrides, demoDoorProvider.overrideWithValue(_door)],
          child: const CupolaApp(),
        ),
      );
      LinkHandoff.routerReadyWhenDrawn();
    case StartupFailed(:final failure):
      runApp(
        StartupFailureApp(
          failure: failure,
          onRetry: _start,
          onForgetKeys: _forgetKeysAndStart,
        ),
      );
  }
  DesktopWindow.showWhenDrawn();
}

/// The way into the demo and out of it: see [DemoSession].
///
/// Each `runApp` hands over a `ProviderScope` with a key of its own. Without
/// one Flutter keeps the scope already drawn and only updates its overrides,
/// so the demo would run in the real app's container (Riverpod refuses that
/// outright: the number of overrides changes).
const _door = DemoDoor(enter: _enterDemo, leave: _leaveDemo);

/// The demo running now, which leaving ends.
DemoSession? _demo;

Future<void> _enterDemo(SettingsModel leaving) async {
  final session = _demo = await DemoSession.start(leaving: leaving);
  runApp(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...session.overrides,
        demoDoorProvider.overrideWithValue(_door),
      ],
      child: const CupolaApp(),
    ),
  );
  LinkHandoff.routerReadyWhenDrawn();
}

Future<void> _leaveDemo() async {
  final session = _demo;
  _demo = null;
  await session?.end();
  await _start();
}

/// The Home's last drawings (`LastKnownStore`), from the system's cache
/// folder; an empty store when there is none, when the folder cannot be read,
/// or when reading it takes longer than a start can spare.
///
/// Written once a burst of answers has passed, and when the app leaves the
/// screen, which may be the last chance this run gets.
Future<LastKnownStore> _openLastKnown() async {
  try {
    final folder = await getApplicationCacheDirectory();
    final store = await LastKnownStore.open(
      File('${folder.path}/last_known.json'),
    ).timeout(const Duration(milliseconds: 400));
    _lastKnownListener?.dispose();
    _lastKnownListener = AppLifecycleListener(
      onHide: store.flush,
      onDetach: store.flush,
    );
    return store;
  } catch (_) {
    return LastKnownStore.memory();
  }
}

AppLifecycleListener? _lastKnownListener;

/// Empties secure storage, keeping every address and preference, then
/// starts again; a store that will not even be emptied is said on the same
/// page, as its own failure.
Future<void> _forgetKeysAndStart() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await SettingsService(prefs, createSecureSettingsStore()).forgetSecrets();
  } catch (error) {
    runApp(
      StartupFailureApp(
        failure: StartupFailure(step: StartupStep.forgettingKeys, error: error),
        onRetry: _start,
      ),
    );
    return;
  }
  await _start();
}

/// The bundled font families and the SIL OFL 1.1 each one ships under.
///
/// One entry per family, because each licence names its own copyright holder:
/// a single merged entry would credit the wrong authors for two of the three.
const Map<String, String> bundledFontLicenses = {
  'Bricolage Grotesque': 'assets/fonts/BricolageGrotesque-OFL.txt',
  'Onest': 'assets/fonts/Onest-OFL.txt',
  'Geist Mono': 'assets/fonts/GeistMono-OFL.txt',
};

/// Puts each bundled font's SIL OFL 1.1 into the licence page Flutter builds
/// from [LicenseRegistry].
///
/// The registry only knows about licences declared in package metadata, and a
/// font dropped into `assets/` has none, so the one obligation the OFL puts on
/// a binary that bundles the font, that its licence travel with it, would go
/// unmet in every shipped build. Registered before `runApp` because the
/// registry is read lazily and the callback must already be there when the
/// licence page asks.
void _registerBundledFontLicense() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: family, value: asset)
        in bundledFontLicenses.entries) {
      yield LicenseEntryWithLineBreaks(<String>[
        family,
      ], await rootBundle.loadString(asset));
    }
  });
}

class CupolaApp extends ConsumerWidget {
  const CupolaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Each Seerr account's permissions, read again at start and when the
    // app comes back with them stale.
    ref.watch(seerrAccountKeeperProvider);
    // The Tracearr owner's session, read once a day of use so Tracearr keeps
    // it alive.
    ref.watch(tracearrOwnerKeeperProvider);
    // Moves each connection with an address away from home to the address
    // that answers: at start, on resume, when one stops answering.
    ref.watch(routeProbeProvider);
    // Says when the phone's network changes with the app open, so the route
    // and the connections' readouts are asked again.
    ref.watch(networkChangeWatchProvider);

    // The static registries the network code reads (pins, access headers,
    // the addresses that did not answer): see `networkRegistriesProvider`.
    ref.watch(networkRegistriesProvider);
    // What the widgets draw, written as the app leaves the screen, and the
    // run with the app away asked for while it serves someone.
    ref.watch(outsideKeeperProvider);
    ref.watch(outsideScheduleProvider);

    // No DynamicColorBuilder: the palette is fixed on purpose so per-service
    // accents stay recognisable and the experience is identical on every OS.
    // See AppTheme.darkTheme.
    return MaterialApp.router(
      title: kAppName,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Leading is tightened at the top of the ramp (the display roles sit at
      // 1.0) and opened at the bottom (body at 22 on 15). Both ends need this,
      // in opposite directions, and one behaviour covers them:
      //
      // - A line box shorter than the glyph's ink lets the ink escape it. The
      //   display face needs its full 1.20em (Onest 1.275em) to contain an
      //   accented capital, so at 1.0 the acute on `Ý` pokes out the top, and
      //   media titles arrive from TMDB in every language. Inside anything that
      //   clips (the detail hero clips by design) that is a shaved accent.
      // - Extra leading below the last line is padding nobody asked for, and it
      //   would push every fixed-height box in the app out by a couple of
      //   points, since those constants encode a measured single line.
      //
      // Declining to apply the height to the block's outer ascent and descent
      // fixes both: the *gaps between* lines carry the leading decision, while
      // the block's edges keep the font's natural metrics. Prose gets its air,
      // display type stays tight, single-line chrome measures exactly what it
      // measured before, and nothing clips.
      //
      // Around all of it, the live region `announce()` speaks through where
      // the engine has no announcement channel (Android): one, above every
      // route, so a TalkBack user hears what a VoiceOver user hears. The
      // system bars in the room's ink (`ThemedSystemBars`). And Android's back
      // claimed for Settings, above every navigator (`SettingsBackClaim`).
      builder: (context, child) => AppSnapshotCover(
        child: ThemedSystemBars(
          child: AnnouncementHost(
            child: SettingsBackClaim(
              child: DefaultTextHeightBehavior(
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
