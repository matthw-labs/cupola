/// The Home's row of a stuck download takes Needs you's ways out: the same
/// choice, the same write, the same note.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/data/acted_faults.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/services/presentation/kept_waiting_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

Future<ProfileHarness> _pump(WidgetTester tester) async {
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
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(child: HomeDownloadsModule()),
        ),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

bool _queueDelete(NetworkRequest r) =>
    r.method == 'DELETE' && r.uri.path.contains('/queue/');

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeDownloadsModule)));

void main() {
  testWidgets('P1: Try another download keeps the existing files, '
      'blocklisted, and the row says so until the Home is read again', (
    tester,
  ) async {
    final harness = await _pump(tester);
    expect(find.text('Stuck at 47%'), findsOneWidget);

    await tester.tap(find.text('Try another download'));
    await harness.settle(tester);

    // No question first: the fill says what it does, as in Needs you.
    final deletes = harness.network.requests.where(_queueDelete).toList();
    expect(deletes, hasLength(1));
    expect(deletes.single.uri.queryParameters['blocklist'], 'true');
    expect(deletes.single.uri.queryParameters['removeFromClient'], 'false');
    expect(deletes.single.uri.queryParameters['skipRedownload'], 'true');
    final note = find.text('Retry requested\u00A0· Downloaded files kept');
    expect(note, findsOneWidget);
    expect(find.text('Try another download'), findsNothing);

    // Read again, the queue says what is still stuck.
    _container(tester).read(actedFaultsProvider.notifier).clear();
    await harness.settle(tester);
    expect(note, findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P1: Keep waiting hides the remedy for a day, and Undo brings '
      'it back', (tester) async {
    final harness = await _pump(tester);

    await tester.tap(find.byTooltip('More for Big Buck Bunny'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep waiting'));
    await harness.settle(tester);

    expect(
      find.text(
        'Hidden until tomorrow 20:53\u00A0· it comes back if nothing moves',
      ),
      findsOneWidget,
    );
    expect(harness.network.requests.where(_queueDelete), isEmpty);

    await tester.tap(find.text('Undo'));
    await harness.settle(tester);
    expect(_container(tester).read(keptWaitingProvider), isEmpty);
    expect(find.text('Try another download'), findsOneWidget);

    // Kept again and read again: the row still says it is stuck, and offers
    // nothing until its day is up.
    await tester.tap(find.byTooltip('More for Big Buck Bunny'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep waiting'));
    await harness.settle(tester);
    _container(tester).read(actedFaultsProvider.notifier).clear();
    await harness.settle(tester);
    expect(find.text('Stuck at 47%'), findsOneWidget);
    expect(find.text('Try another download'), findsNothing);
    expect(find.textContaining('Hidden until'), findsNothing);

    await harness.unmount(tester);
  });
}
