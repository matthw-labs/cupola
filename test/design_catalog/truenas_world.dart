import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

import '../test_helpers/capability_overrides.dart';
import '../test_helpers/settings_scope.dart';

/// The id the first TrueNAS connection takes in `settingsScopeOverrides`.
/// The capability grant is keyed by it.
const trueNasConnectionId = 'truenas';

/// The small server the TrueNAS section cards draw: two pools, one sound and
/// one degraded, the three share services, two SMB shares, an NFS export, a
/// user and a group.
///
/// It is the capability screens' world reduced to what the sheets read: every
/// method a section asks for while it draws, and nothing a write would reach.
const trueNasWorld = <String, Object?>{
  'system.version': 'TrueNAS-SCALE-25.04.1',
  'system.info': {'hostname': 'nas', 'version': '25.04.1'},
  'pool.query': [
    {
      'id': 1,
      'name': 'tank',
      'status': 'ONLINE',
      'healthy': true,
      'size': 47960000000000,
      'allocated': 34300000000000,
    },
    {
      'id': 2,
      'name': 'backup',
      'status': 'DEGRADED',
      'healthy': false,
      'size': 15990000000000,
      'allocated': 6400000000000,
    },
  ],
  'sharing.smb.query': [
    {'id': 1, 'name': 'media', 'path': '/mnt/tank/media', 'enabled': true},
    {'id': 2, 'name': 'backups', 'path': '/mnt/tank/backups', 'enabled': false},
  ],
  'sharing.nfs.query': [
    {'id': 3, 'path': '/mnt/tank/export', 'enabled': true},
  ],
  'iscsi.target.query': [
    {'id': 4, 'name': 'lun0'},
  ],
  'service.query': [
    {'id': 1, 'service': 'cifs', 'state': 'RUNNING', 'enable': true},
    {'id': 2, 'service': 'nfs', 'state': 'RUNNING', 'enable': true},
    {'id': 3, 'service': 'iscsitarget', 'state': 'STOPPED', 'enable': false},
  ],
  'user.query': [
    {
      'id': 5,
      'uid': 1000,
      'username': 'matt',
      'full_name': 'Matt',
      'builtin': false,
      'smb': true,
    },
  ],
  'group.query': [
    {
      'id': 7,
      'gid': 1000,
      'group': 'media',
      'builtin': false,
      'users': ['matt'],
    },
  ],
};

/// Answers every read from [trueNasWorld]; nothing is written while a sheet
/// is drawn.
class TrueNasCatalogBackend extends TrueNasWsClient {
  TrueNasCatalogBackend()
    : super(baseUrl: 'https://nas.catalog', apiKey: 'catalog');

  @override
  Future<dynamic> call(
    String method, [
    List<dynamic> params = const [],
  ]) async => trueNasWorld[method];

  @override
  Future<dynamic> callJob(
    String method, [
    List<dynamic> params = const [],
    TrueNasJobProgress? onProgress,
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 1),
  ]) async => trueNasWorld[method];
}

/// The overrides a TrueNAS section card needs: a configured connection, the
/// backend above, and a key that may write, so a New FAB draws enabled.
Future<List<Override>> trueNasCatalogOverrides() async => [
  ...await settingsScopeOverrides(configured: const [ServiceKey.truenas]),
  truenasClientProvider.overrideWithValue(TrueNasCatalogBackend()),
  capabilityOverride({trueNasConnectionId: const CapabilityGrant.readWrite()}),
];

/// A phone's insets, so a page sits where it does on the device: under the
/// status bar, over the home indicator the floating bar carries.
Widget trueNasPhone(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(padding: const EdgeInsets.only(top: 47, bottom: 34)),
    child: child,
  ),
);

/// The shell around a pushed TrueNAS section: the page over the floating bar,
/// which is the body's bottom padding and the reason the section's New FAB
/// has to clear it.
///
/// The page sits one route deep, as it does in the app, so its glass app bar
/// draws the back control; the blank root is never seen.
Widget trueNasShell(Widget page) => Scaffold(
  backgroundColor: Colors.transparent,
  extendBody: true,
  body: Navigator(
    onGenerateRoute: (_) => throw StateError('the section is not named'),
    onGenerateInitialRoutes: (_, _) => [
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SizedBox.expand(),
      ),
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => page,
      ),
    ],
  ),
  bottomNavigationBar: FloatingBottomNavBar(
    selectedIndex: NavTab.barFor(Audience.operator).indexOf(NavTab.home),
    onDestinationSelected: (_) {},
    destinations: [
      for (final tab in NavTab.barFor(Audience.operator))
        FloatingNavDestination(
          icon: tab.icon,
          selectedIcon: tab.selectedIcon,
          railIcon: tab.railIcon,
          label: tab.label,
        ),
    ],
  ),
);
