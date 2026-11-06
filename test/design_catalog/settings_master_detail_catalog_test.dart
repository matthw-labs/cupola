@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';
import 'package:cupola/features/settings/presentation/settings_appearance_screen.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import '../test_helpers/profiles/profiles.dart';
import '../test_helpers/settings_scope.dart';
import 'catalog.dart';
import 'emby_world.dart';

/// Settings as a tablet shows it, the Appearance section open: the page the
/// router builds, in a window of [size], without the shell's rail around it.
class _Tablet extends StatefulWidget {
  const _Tablet(this.size);

  final Size size;

  @override
  State<_Tablet> createState() => _TabletState();
}

class _TabletState extends State<_Tablet> {
  late final _router = GoRouter(
    initialLocation: '/settings/appearance',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SizedBox(),
        routes: [
          GoRoute(
            path: 'appearance',
            pageBuilder: (_, state) => SettingsSectionPage(
              key: state.pageKey,
              name: state.matchedLocation,
              child: const SettingsAppearanceScreen(),
            ),
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(size: widget.size),
    child: SizedBox.fromSize(
      size: widget.size,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: Theme.of(context),
        routerConfig: _router,
      ),
    ),
  );
}

/// The household's Jellyfin form, whose address answers as an Emby: what its
/// test finds there.
final _jellyfinAnswersAsEmby = Profiles.p1.withBehaviour(
  WorldIds.jellyfin,
  const ConnectionBehaviour.answersAsOtherService(ServiceKey.emby),
);

Future<List<Override>> _overrides() async {
  await startEmbyWorld(_jellyfinAnswersAsEmby);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
    initialSettingsProvider.overrideWithValue(
      settingsWithServices(const [ServiceKey.radarr, ServiceKey.seerr]),
    ),
  ];
}

void main() {
  catalogCard(
    'SettingsMasterDetail',
    overrides: _overrides,
    width: 1240,
    scenes: [
      CatalogScene(
        'A tablet on its side, 1180 × 820 · the sections in a 300 list beside '
        'the page; Appearance open, with no back button: the list is the way '
        'between sections',
        (_) => const _Tablet(Size(1180, 820)),
        width: 1180,
        height: 820,
      ),
      CatalogScene(
        'A tablet upright, 820 × 1180 · the phone\'s drill-down: the page '
        'alone, its back button to the list',
        (_) => const _Tablet(Size(820, 1180)),
        width: 820,
        height: 1180,
      ),
      CatalogScene(
        'ServiceSettingsScreen · Jellyfin\'s form tested at an Emby\'s '
        'address · the result panel says This is Emby, and the cause under '
        'it; Set up Emby, the amber remedy, opens Emby\'s form on that '
        'address',
        (_) => const EmbyWorldScope(
          child: ServiceSettingsScreen(
            service: ServiceKey.jellyfin,
            instanceId: WorldIds.jellyfin,
          ),
        ),
        width: 390,
        height: 1340,
        act: (tester, scene) async {
          final test = find.descendant(
            of: scene,
            matching: find.text('Test connection'),
          );
          await tester.ensureVisible(test);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(test);
          // The fake server answers on the real event loop: give it the time.
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
        },
      ),
      CatalogScene(
        'Text at 200% · on its side, the list and the page at twice the '
        'reading size',
        (_) => const _Tablet(Size(1180, 820)),
        width: 1180,
        height: 820,
        textScale: catalogTextScale,
      ),
    ],
  );
}
