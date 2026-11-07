/// The Review of blocked imports on P1, whole app: Needs you's `Review 18`
/// opens the Review of Sonarr's eighteen Cosmos Laundromat downloads, a tape
/// is placed on its episode, and the import reports itself back in Needs you.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/presentation/activity_needs_you_page.dart';
import 'package:cupola/features/activity/presentation/widgets/import_done_card.dart';
import 'package:cupola/features/import/presentation/blocked_import_review_page.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

final _now = DateTime(2026, 10, 9, 20, 53);

Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  final container = harness.container();
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await _answer(tester);
  return (harness, router, container);
}

Future<void> _answer(WidgetTester tester, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(
  WidgetTester tester,
  ProfileHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await harness.unmount(tester);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pump();
  await tester.tap(target.first);
  await _answer(tester);
}

/// Needs you, then its `Review 18`.
Future<void> _openReview(WidgetTester tester, GoRouter router) async {
  router.go(ServiceRoutes.activityNeedsYou);
  await _answer(tester);
  await _tap(tester, find.text('Review 18'));
}

void main() {
  testWidgets("Review 18 opens the page: the arr's words, twelve clear "
      'matches selected, six that need you', (tester) async {
    final (harness, router, container) = await _app(tester);
    await _openReview(tester, router);

    expect(find.byType(BlockedImportReviewPage), findsOneWidget);
    expect(find.text('Review 18 imports'), findsOneWidget);
    expect(
      find.text(
        "The file names don't match the series name, so Sonarr won't guess.",
      ),
      findsOneWidget,
    );

    await _tap(tester, find.text('Why?'));
    expect(find.text('What Sonarr says'), findsOneWidget);
    expect(
      find.text(
        'In plain words: Sonarr grabbed these for Cosmos Laundromat, but '
        "their names don't say so. 12 name their episode clearly; 6 don't.",
      ),
      findsOneWidget,
    );

    expect(find.text('12 clear matches'), findsOneWidget);
    expect(find.text('12 of 12 selected'), findsOneWidget);
    expect(
      find.text('1080p WEB\u00A0· English\u00A0· each replaces a 720p file'),
      findsOneWidget,
    );
    expect(find.text('Clear all'), findsOneWidget);
    expect(find.text('S1\u00A0E1'), findsOneWidget);
    expect(find.text('S2\u00A0E2'), findsOneWidget);

    expect(find.text('6 need you'), findsOneWidget);
    expect(find.text('Which episode?'), findsNWidgets(6));

    expect(find.text('6 left for later'), findsOneWidget);
    expect(find.text("Imports can't be undone"), findsOneWidget);
    expect(find.text('Import 12 clear matches'), findsOneWidget);

    // Clear all takes them out, and the bar says so.
    await _tap(tester, find.text('Clear all'));
    expect(find.text('0 of 12 selected'), findsOneWidget);
    expect(find.text('Select something to import'), findsOneWidget);

    await _close(tester, harness, container);
  });

  testWidgets('a tape is placed on its season and episode, and joins the '
      'import', (tester) async {
    final (harness, router, container) = await _app(tester);
    await _openReview(tester, router);

    await _tap(tester, find.text('Which episode?'));
    expect(find.text("from Sonarr's grab"), findsOneWidget);
    // The episode its name carries; no season yet.
    expect(find.text('E1'), findsOneWidget);
    expect(find.text('Pick a season to add it'), findsOneWidget);

    await _tap(tester, find.text('S2'));
    for (var i = 0; i < 3; i++) {
      await _tap(tester, find.byTooltip('Next episode'));
    }
    expect(find.text('E4'), findsOneWidget);
    await _tap(tester, find.text('Add to the import'));

    expect(
      find.text('Added\u00A0· Cosmos Laundromat\u00A0· S2\u00A0E4'),
      findsOneWidget,
    );
    expect(find.text('Which episode?'), findsNWidgets(5));
    expect(find.text('12 clear\u00A0· 1 picked by you'), findsOneWidget);
    expect(find.text('Import 13 selected'), findsOneWidget);

    await _close(tester, harness, container);
  });

  testWidgets('the import goes back to Needs you, which reports it running '
      'and then done', (tester) async {
    final (harness, router, container) = await _app(tester);
    await _openReview(tester, router);

    await _tap(tester, find.text('Import 12 clear matches'));

    expect(find.byType(BlockedImportReviewPage), findsNothing);
    expect(find.byType(ActivityNeedsYouPage), findsOneWidget);
    expect(find.byType(ImportDoneCard), findsOneWidget);
    expect(find.text('Importing 12 episodes'), findsOneWidget);
    expect(find.text('Sonarr is moving the files'), findsOneWidget);

    // The card reads the command again; Sonarr has finished.
    await tester.pump(const Duration(seconds: 2));
    await _answer(tester);

    expect(find.text('12 episodes imported'), findsOneWidget);
    expect(find.text('Imported just now'), findsOneWidget);
    expect(
      find.text('Cosmos Laundromat S1 and S2\u00A0E1–E2 are now 1080p.'),
      findsOneWidget,
    );
    expect(find.text('720p'), findsOneWidget);
    expect(find.text('1080p WEB'), findsOneWidget);
    expect(find.text('Open in library'), findsOneWidget);

    await _close(tester, harness, container);
  });
}
