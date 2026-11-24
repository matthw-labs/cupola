/// Needs you's cards on P1: each fault with its way out, what each way out
/// sends, and what the card says once one was taken.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/activity/presentation/widgets/decision_fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/storage_alert_card.dart';
import 'package:cupola/features/activity/presentation/widgets/stuck_download_card.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/services/presentation/kept_waiting_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

Future<ProfileHarness> _pump(
  WidgetTester tester, {
  void Function(ProfileHarness harness)? script,
}) async {
  final harness = await ProfileHarness.start(
    Profiles.p1,
    now: _now,
    overrides: [
      arrivalsClockProvider.overrideWith(
        (ref) =>
            () => _now,
      ),
      stallClockProvider.overrideWith(
        (ref) =>
            () => _now,
      ),
    ],
  );
  script?.call(harness);
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 8000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const ActivityPage(tab: ActivityTab.all),
      ),
    ),
  );
  await harness.settle(tester);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await harness.settle(tester);
  return harness;
}

bool _queueDelete(NetworkRequest r) =>
    r.method == 'DELETE' && r.uri.path.contains('/queue/');

Finder get _stuckCard => find.byType(StuckDownloadCard);

void main() {
  testWidgets('P1: a stuck download says where it stopped, why, and leads '
      'with another download', (tester) async {
    final harness = await _pump(tester);

    expect(_stuckCard, findsOneWidget);
    expect(find.text('Big Buck Bunny is stuck at 47%'), findsOneWidget);
    expect(
      find.textContaining('nobody sharing it has the whole file'),
      findsOneWidget,
    );
    expect(find.text('Try another download'), findsOneWidget);
    expect(
      find.textContaining('The 1.1\u00A0GB so far stays.'),
      findsOneWidget,
    );
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Keep waiting'), findsOneWidget);
    // The time is in the explanation, the route alone under the release.
    expect(
      find.descendant(
        of: _stuckCard,
        matching: find.text('Radarr 1 → qBittorrent'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _stuckCard,
        matching: find.textContaining('Nothing for '),
      ),
      findsNothing,
    );

    await harness.unmount(tester);
  });

  testWidgets('Try another download keeps the files, blocklists the release, '
      'and requests a search', (tester) async {
    final harness = await _pump(tester);

    await tester.tap(find.text('Try another download'));
    await harness.settle(tester);

    final deletes = harness.network.requests.where(_queueDelete).toList();
    expect(deletes, hasLength(1));
    expect(deletes.single.uri.queryParameters['blocklist'], 'true');
    expect(deletes.single.uri.queryParameters['removeFromClient'], 'false');
    expect(deletes.single.uri.queryParameters['skipRedownload'], 'true');
    expect(
      find.text('Retry requested\u00A0· Downloaded files kept'),
      findsOneWidget,
    );
    expect(find.text('Try another download'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('Remove asks first, then removes without a blocklist', (
    tester,
  ) async {
    final harness = await _pump(tester);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text("Remove Big Buck Bunny's download?"), findsOneWidget);
    expect(
      find.textContaining('Big Buck Bunny stays in your wanted list'),
      findsOneWidget,
    );

    // Cancelled, nothing is sent.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.network.requests.where(_queueDelete), isEmpty);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove download'));
    await harness.settle(tester);

    final delete = harness.network.requests.where(_queueDelete).single;
    expect(delete.uri.queryParameters['blocklist'], 'false');
    expect(
      find.text('Removed\u00A0· Big Buck Bunny stays in your wanted list'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Keep waiting hides it for a day, out of the count, and Undo '
      'brings it back', (tester) async {
    final harness = await _pump(tester);
    expect(find.text('4 faults\u00A0· 3 requests'), findsOneWidget);

    await tester.tap(find.text('Keep waiting'));
    await harness.settle(tester);

    expect(
      find.text(
        'Hidden until tomorrow 20:53\u00A0· it comes back if nothing moves',
      ),
      findsOneWidget,
    );
    // Out of the faults, and nothing sent to any service.
    expect(find.text('3 faults\u00A0· 3 requests'), findsOneWidget);
    expect(harness.network.requests.where(_queueDelete), isEmpty);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActivityPage)),
    );
    expect(container.read(keptWaitingProvider), hasLength(1));

    await tester.tap(find.text('Undo'));
    await harness.settle(tester);

    expect(container.read(keptWaitingProvider), isEmpty);
    expect(find.text('Try another download'), findsOneWidget);
    expect(find.text('4 faults\u00A0· 3 requests'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a way out that fails says why and leaves the card as it was', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      script: (harness) {
        for (final id in [WorldIds.radarr, WorldIds.radarr4k]) {
          harness.network.on(
            id,
            'DELETE',
            RegExp('/queue/'),
            (r) => NetworkReply.json(const {'message': 'boom'}, status: 500),
          );
        }
      },
    );

    await tester.tap(find.text('Try another download'));
    await harness.settle(tester);

    expect(
      find.textContaining('Could not try another download'),
      findsOneWidget,
    );
    expect(find.text('Try another download'), findsOneWidget);
    expect(find.textContaining('Dropped'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('a pull lets the notes go: the queue says what is still stuck', (
    tester,
  ) async {
    final harness = await _pump(tester);

    await tester.tap(find.text('Keep waiting'));
    await harness.settle(tester);
    expect(find.textContaining('Hidden until'), findsOneWidget);

    // The pull's own refresh, as the indicator starts it.
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await harness.settle(tester);

    expect(find.textContaining('Hidden until'), findsNothing);
    // Still kept waiting: its day is not up, so it is not back either.
    expect(find.text('Big Buck Bunny is stuck at 47%'), findsNothing);
    expect(find.text('3 faults\u00A0· 3 requests'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('P1: the other faults wear their words and their own control', (
    tester,
  ) async {
    final harness = await _pump(tester);

    expect(find.byType(DecisionFaultCard), findsOneWidget);
    expect(find.text('18 downloads need a manual import'), findsOneWidget);
    expect(find.text('Review 18'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('P1: a disk with errors says what they mean for its pool, and '
      'offers the scrub that repairs it', (tester) async {
    final harness = await _pump(tester);

    expect(find.byType(StorageAlertCard), findsOneWidget);
    expect(
      find.text('Disk sdd reports 8 uncorrectable errors'),
      findsOneWidget,
    );
    expect(
      find.text(
        'sdd could not read some data by itself. The pool is still healthy: '
        'a scrub reads every block and repairs it from the other disks.',
      ),
      findsOneWidget,
    );
    expect(find.text('TrueNAS\u00A0· pool tank'), findsOneWidget);
    expect(find.text('Scrub tank'), findsOneWidget);
    expect(find.text('Open alert'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Scrub tank asks first, then asks that TrueNAS to scrub tank', (
    tester,
  ) async {
    final harness = await _pump(tester);
    bool scrubs((String, String) call) => call.$2 == 'pool.scrub.scrub';

    await tester.tap(find.text('Scrub tank'));
    await tester.pumpAndSettle();
    expect(find.text('Scrub tank?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.network.rpcCalls.where(scrubs), isEmpty);

    await tester.tap(find.text('Scrub tank'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrub tank').last);
    await harness.settle(tester);

    expect(harness.network.rpcCalls.where(scrubs).single.$1, WorldIds.truenas);

    await harness.unmount(tester);
  });

  test('the downloads sources are what a way out reads again', () {
    // The card drops these after a write; a source added to the Home's
    // downloads is read again here too.
    expect(homeDownloadsSources, contains(servicesQueueProvider));
  });

  testWidgets('a health check failing on three arrs is one card in the app\'s '
      'words, the first arr on the fill and the others behind', (tester) async {
    final harness = await _pump(
      tester,
      script: (harness) {
        for (final (id, path, arr) in [
          (WorldIds.radarr, '/api/v3/health', 'Radarr'),
          (WorldIds.sonarr, '/api/v3/health', 'Sonarr'),
          (WorldIds.lidarr, '/api/v1/health', 'Lidarr'),
        ]) {
          harness.network.on(
            id,
            'GET',
            path,
            (_) => NetworkReply.json([
              {
                'source': 'IndexerRssCheck',
                'type': 'error',
                'message':
                    'No indexers available with RSS sync enabled, $arr will '
                    'not grab new releases automatically',
              },
            ]),
          );
        }
      },
    );

    expect(
      find.text('No indexer is watching for new releases'),
      findsOneWidget,
    );
    expect(
      find.text(
        "New releases aren't grabbed on their own until an indexer has RSS "
        'sync on.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'Sonarr and Lidarr$')), findsOneWidget);
    // Their own words once, behind Why?: none of them is the headline.
    expect(find.textContaining('No indexers available'), findsNothing);
    expect(
      find.ancestor(
        of: find.textContaining(RegExp(r'^Open in Radarr')),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'^Open in Sonarr')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Open in Lidarr')), findsOneWidget);

    await harness.unmount(tester);
  });
}
