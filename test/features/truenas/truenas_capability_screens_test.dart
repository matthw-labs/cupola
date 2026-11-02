import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/widgets/capability_banner.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_app_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_apps_screen.dart';
import 'package:cupola/features/truenas/presentation/dashboard/truenas_dashboard_screen.dart';
import 'package:cupola/features/truenas/presentation/data_protection/truenas_data_protection_screen.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_datasets_screen.dart';
import 'package:cupola/features/truenas/presentation/shares/truenas_shares_screen.dart';
import 'package:cupola/features/truenas/presentation/storage/truenas_pool_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/storage/truenas_storage_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_credentials_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_services_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_config_screens.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_hub_screen.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_screen.dart';

import '../../test_helpers/capability_overrides.dart';
import '../../test_helpers/settings_scope.dart';

/// Answers every read from [answers] and records every write, so a gated tap
/// is proved to have reached nothing.
class _FakeNas extends TrueNasWsClient {
  _FakeNas(this.answers) : super(baseUrl: 'https://nas.local', apiKey: 'k');

  final Map<String, Object?> answers;
  final List<String> writes = [];

  static const _writeVerbs = {
    'create',
    'update',
    'delete',
    'start',
    'stop',
    'restart',
    'run',
    'sync',
    'dismiss',
    'send',
    'scrub',
    'upgrade',
    'reboot',
    'shutdown',
  };

  Object? _answer(String method) {
    if (_writeVerbs.contains(method.split('.').last)) {
      writes.add(method);
      return null;
    }
    return answers[method];
  }

  @override
  Future<dynamic> call(
    String method, [
    List<dynamic> params = const [],
  ]) async => _answer(method);

  @override
  Future<dynamic> callJob(
    String method, [
    List<dynamic> params = const [],
    TrueNasJobProgress? onProgress,
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 1),
  ]) async => _answer(method);
}

/// One small server: a pool, a dataset with a snapshot, a share of each kind,
/// the three share services, a snapshot task, a container, an app with an
/// upgrade, a user and a group, and a config document per system page.
const Map<String, Object?> _nas = {
  'system.version': 'TrueNAS-SCALE-25.04.1',
  'system.info': {'hostname': 'nas', 'version': '25.04.1'},
  'alert.list': [
    {'uuid': 'a1', 'level': 'WARNING', 'formatted': 'Disk hot'},
  ],
  'pool.query': [
    {'id': 1, 'name': 'tank', 'status': 'ONLINE', 'healthy': true},
  ],
  'pool.dataset.query': [
    {
      'id': 'tank',
      'name': 'tank',
      'pool': 'tank',
      'type': 'FILESYSTEM',
      'children': <Object>[],
    },
  ],
  'zfs.snapshot.query': [
    {'id': 'tank@auto-1', 'name': 'auto-1', 'dataset': 'tank'},
  ],
  'sharing.smb.query': [
    {'id': 1, 'name': 'media', 'path': '/mnt/tank/media', 'enabled': true},
  ],
  'sharing.nfs.query': [
    {'id': 2, 'path': '/mnt/tank/export', 'enabled': true},
  ],
  'iscsi.target.query': [
    {'id': 3, 'name': 'lun0'},
  ],
  'service.query': [
    {'id': 1, 'service': 'cifs', 'state': 'RUNNING', 'enable': true},
    {'id': 2, 'service': 'nfs', 'state': 'STOPPED', 'enable': false},
    {'id': 3, 'service': 'iscsitarget', 'state': 'STOPPED', 'enable': false},
  ],
  'pool.snapshottask.query': [
    {'id': 1, 'dataset': 'tank', 'naming_schema': 'auto-%Y', 'enabled': true},
  ],
  'replication.query': <Object>[],
  'cloudsync.query': <Object>[],
  'rsynctask.query': <Object>[],
  'pool.scrub.query': <Object>[],
  'virt.global.config': {'pool': 'tank', 'state': 'INITIALIZED'},
  'virt.instance.query': [
    {'id': 'web', 'name': 'web', 'type': 'CONTAINER', 'status': 'STOPPED'},
  ],
  'app.query': [
    {'name': 'plex', 'state': 'RUNNING', 'upgrade_available': true},
  ],
  'user.query': [
    {'id': 5, 'username': 'matt', 'builtin': false},
  ],
  'group.query': [
    {'id': 7, 'group': 'media', 'builtin': false},
  ],
  'system.general.config': {'timezone': 'UTC', 'language': 'en'},
  'system.advanced.config': {'consolemenu': true},
  'mail.config': {'fromemail': 'nas@lab.test', 'port': 25},
};

/// The first TrueNAS connection takes the service's route param as its id.
const _id = 'truenas';

Future<_FakeNas> _pump(
  WidgetTester tester,
  Widget page, {
  required CapabilityGrant grant,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final nas = _FakeNas(_nas);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...await settingsScopeOverrides(configured: const [ServiceKey.truenas]),
        truenasClientProvider.overrideWithValue(nas),
        capabilityOverride({_id: grant}),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
  return nas;
}

/// Tears the page down, so a page that owns a poll timer leaves none behind.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

/// One write control: how to reach it, and the verb its blocked toast names.
/// [menu] is the finder of the menu button to open first, for a menu item.
typedef _Control = ({Finder control, String verb, Finder? menu});

_Control _c(Finder control, String verb, {Finder? menu}) =>
    (control: control, verb: verb, menu: menu);

/// Rows 1–14 of the write inventory.
final _pages = <(String, Widget Function(), List<_Control> Function())>[
  (
    '1 Dashboard',
    () => const TrueNasDashboardScreen(),
    () => [_c(find.widgetWithText(TextButton, 'Dismiss'), 'dismiss alerts')],
  ),
  (
    '2 Datasets',
    () => const TrueNasDatasetsScreen(),
    () => [_c(find.byType(FloatingActionButton), 'create datasets')],
  ),
  (
    '3 Dataset detail',
    () => const TrueNasDatasetDetailScreen(datasetId: 'tank'),
    () => [
      _c(find.widgetWithText(TextButton, 'New'), 'create snapshots'),
      _c(find.byTooltip('Delete snapshot'), 'delete snapshots'),
      _c(
        find.text('Edit'),
        'edit datasets',
        menu: find.byType(PopupMenuButton<String>),
      ),
      _c(
        find.text('Delete dataset'),
        'delete datasets',
        menu: find.byType(PopupMenuButton<String>),
      ),
    ],
  ),
  (
    '4 Pool detail',
    () => const TrueNasPoolDetailScreen(poolName: 'tank'),
    () => [_c(find.byTooltip('Start scrub'), 'start a scrub')],
  ),
  (
    '5 Shares',
    () => const TrueNasSharesScreen(),
    () => [
      _c(find.byType(Switch).first, 'start or stop the SMB service'),
      _c(find.byTooltip('Edit'), 'edit SMB shares'),
      _c(find.byTooltip('Delete share'), 'delete SMB shares'),
      _c(find.byType(Switch).last, 'enable or disable SMB shares'),
      _c(find.byType(FloatingActionButton), 'create SMB shares'),
    ],
  ),
  (
    '6 Data protection',
    () => const TrueNasDataProtectionScreen(),
    () => [
      _c(find.byTooltip('Run now'), 'run snapshot tasks'),
      _c(find.byTooltip('Delete task'), 'delete snapshot tasks'),
      _c(find.byType(Switch), 'enable or disable snapshot tasks'),
    ],
  ),
  (
    '7 Virtualization',
    () => const TrueNasVirtScreen(type: 'CONTAINER'),
    () => [
      _c(find.byType(FloatingActionButton), 'create instances'),
      _c(find.byTooltip('Start web'), 'start instances'),
    ],
  ),
  (
    '8 Virtualization detail',
    () => const TrueNasVirtDetailScreen(id: 'web', type: 'CONTAINER'),
    () => [
      _c(find.byTooltip('Delete instance'), 'delete instances'),
      _c(find.byTooltip('Start web'), 'start instances'),
    ],
  ),
  (
    '9 Apps',
    () => const TrueNasAppsScreen(),
    () => [
      _c(find.byTooltip('Update all (1)'), 'update apps'),
      _c(find.byTooltip('Stop'), 'start or stop apps'),
      _c(
        find.text('Upgrade'),
        'upgrade apps',
        menu: find.byIcon(Icons.more_vert_rounded).last,
      ),
    ],
  ),
  (
    '10 App detail',
    () => const TrueNasAppDetailScreen(name: 'plex'),
    () => [_c(find.byTooltip('Stop'), 'start or stop apps')],
  ),
  (
    '11 System hub',
    () => const TrueNasSystemHubScreen(),
    () => [
      _c(find.widgetWithText(OutlinedButton, 'Reboot…'), 'reboot this server'),
      _c(
        find.widgetWithText(OutlinedButton, 'Shut down…'),
        'shut down this server',
      ),
    ],
  ),
  (
    '12 Services',
    () => const TrueNasServicesScreen(),
    () => [
      _c(find.byTooltip('Disable autostart'), 'change cifs'),
      _c(find.byType(Switch).first, 'start or stop cifs'),
    ],
  ),
  (
    '13 Credentials',
    () => const TrueNasCredentialsScreen(),
    () => [
      _c(find.byType(FloatingActionButton), 'create users'),
      _c(find.byTooltip('Delete user'), 'delete users'),
    ],
  ),
  (
    '14 General',
    () => const TrueNasGeneralScreen(),
    () => [_c(find.byTooltip('Edit'), 'change general settings')],
  ),
  (
    '14 Advanced',
    () => const TrueNasAdvancedScreen(),
    () => [_c(find.byTooltip('Edit'), 'change advanced settings')],
  ),
  (
    '14 Email',
    () => const TrueNasEmailScreen(),
    () => [
      _c(find.byTooltip('Edit'), 'change email settings'),
      _c(find.byTooltip('Send test email'), 'send a test email'),
    ],
  ),
];

Future<void> _open(WidgetTester tester, _Control c) async {
  if (c.menu case final menu?) {
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }
}

Future<void> _dismissMenu(WidgetTester tester, _Control c) async {
  if (c.menu != null &&
      find.byWidgetPredicate((w) => w is PopupMenuItem).evaluate().isNotEmpty) {
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
  }
}

void _clearToasts(WidgetTester tester) {
  ScaffoldMessenger.of(
    tester.element(find.byType(Scaffold).first),
  ).clearSnackBars();
}

void main() {
  for (final (name, page, controls) in _pages) {
    group(name, () {
      testWidgets('a read-only key: one banner, first; every write dimmed, '
          'reachable, hinted, and answering without a call', (tester) async {
        final nas = await _pump(
          tester,
          page(),
          grant: const CapabilityGrant.readOnly(),
        );

        expect(find.byType(CapabilityBanner), findsOneWidget);
        expect(find.text(trueNasCapabilityCopy.answered), findsOneWidget);
        final shell = find.byType(TrueNasConsoleShell);
        if (shell.evaluate().isNotEmpty) {
          expect(
            tester.getBottomLeft(find.byType(CapabilityBanner)).dy,
            lessThanOrEqualTo(tester.getTopLeft(shell.first).dy),
          );
        }

        for (final c in controls()) {
          await _open(tester, c);
          expect(c.control, findsWidgets, reason: c.verb);
          expect(
            tester.getSemantics(c.control.first),
            isSemantics(hint: trueNasCapabilityHint, isEnabled: true),
            reason: c.verb,
          );
          // The page's name sits over the section now: a control under the
          // fold is scrolled to first.
          final screen =
              tester.view.physicalSize / tester.view.devicePixelRatio;
          if (tester.getRect(c.control.first).bottom > screen.height) {
            await tester.ensureVisible(c.control.first);
            await tester.pump();
          }
          await tester.tap(c.control.first);
          await tester.pumpAndSettle();
          expect(
            find.text(trueNasBlockedMessage(c.verb)),
            findsOneWidget,
            reason: c.verb,
          );
          // No form, no confirmation: the gate is at the tap that opens a flow.
          expect(find.byType(AlertDialog), findsNothing, reason: c.verb);
          expect(find.byType(BottomSheet), findsNothing, reason: c.verb);
          _clearToasts(tester);
          await tester.pumpAndSettle();
        }
        expect(nas.writes, isEmpty);
        await _unmount(tester);
      });

      testWidgets('a read-write key: no banner, and the writes are live', (
        tester,
      ) async {
        await _pump(tester, page(), grant: const CapabilityGrant.readWrite());
        expect(find.byType(CapabilityBanner), findsNothing);
        final first = controls().first;
        await _open(tester, first);
        expect(tester.getSemantics(first.control.first).hint, isEmpty);
        await tester.tap(first.control.first);
        await tester.pumpAndSettle();
        expect(find.textContaining('This TrueNAS key can\'t'), findsNothing);
        await _dismissMenu(tester, first);
        await _unmount(tester);
      });

      testWidgets('an unprobed key: no banner, controls live', (tester) async {
        await _pump(tester, page(), grant: const CapabilityGrant.unknown());
        expect(find.byType(CapabilityBanner), findsNothing);
        final first = controls().first;
        await _open(tester, first);
        expect(tester.getSemantics(first.control.first).hint, isEmpty);
        await _dismissMenu(tester, first);
        await _unmount(tester);
      });
    });
  }

  testWidgets('a page with no writes has no slot', (tester) async {
    await _pump(
      tester,
      const TrueNasStorageScreen(),
      grant: const CapabilityGrant.readOnly(),
    );
    expect(find.byType(CapabilityBannerSlot), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a pool reads the lexicon\'s word, never ZFS\'s uppercase one', (
    tester,
  ) async {
    await _pump(
      tester,
      const TrueNasStorageScreen(),
      grant: const CapabilityGrant.readOnly(),
    );
    expect(find.text('Healthy'), findsOneWidget);
    expect(find.text('ONLINE'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a key that may write SMB but not NFS still owes Shares a band', (
    tester,
  ) async {
    await _pump(
      tester,
      const TrueNasSharesScreen(),
      grant: const CapabilityGrant.partial({'smb', 'service:cifs'}),
    );
    expect(find.byType(CapabilityBanner), findsOneWidget);
    // …and the SMB controls on screen are live.
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This TrueNAS key can\'t'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('an EACCES on a write marks the key and the page says so', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nas = _RefusingNas(_nas);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.truenas],
          ),
          truenasClientProvider.overrideWithValue(nas),
          capabilityOverride(),
        ],
        child: const MaterialApp(home: TrueNasDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityBanner), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text(trueNasCapabilityCopy.refusal), findsOneWidget);
    expect(find.text(trueNasCapabilityCopy.refused), findsOneWidget);
    await _unmount(tester);
  });
}

/// Refuses every write the way the middleware refuses a missing role.
class _RefusingNas extends _FakeNas {
  _RefusingNas(super.answers);

  @override
  Object? _answer(String method) {
    final answer = super._answer(method);
    if (writes.contains(method)) {
      throw const TrueNasException('[EACCES] Not authorized', forbidden: true);
    }
    return answer;
  }
}
