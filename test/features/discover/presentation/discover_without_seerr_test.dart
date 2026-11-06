import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_router/go_router.dart';

import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_band.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The Search tab before anything is typed, on a household where none of the
/// services it queries is set up: a sentence that asks for any one of them,
/// and one way in, to Connections, as Home has.
void main() {
  Future<Uri?> pumpSearch(
    WidgetTester tester,
    ConfigProfile profile, {
    String? tap,
  }) async {
    Uri? landedOn;
    final harness = await ProfileHarness.start(profile);
    final router = GoRouter(
      initialLocation: '/discover',
      routes: [
        GoRoute(path: '/discover', builder: (_, _) => const DiscoverPage()),
        GoRoute(
          path: ServiceRoutes.settingsConnections,
          builder: (_, state) {
            landedOn = state.uri;
            return const Scaffold(body: Text('Connections'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await harness.settle(tester);
    if (tap != null) {
      await tester.ensureVisible(find.text(tap));
      await tester.tap(find.text(tap));
      await harness.settle(tester);
    }
    return landedOn;
  }

  // P2 without its Seerr: nothing at all is set up.
  final nothingSetUp = Profiles.p2.without(ServiceKey.seerr);

  testWidgets('nothing searchable set up: one sentence with "or", one way in', (
    tester,
  ) async {
    await pumpSearch(tester, nothingSetUp);

    expect(find.text('No searchable service is set up'), findsOneWidget);
    expect(
      find.text(
        'Set up Seerr, Radarr, Sonarr, Jellyfin, Plex or Emby to search your '
        'libraries from here.',
      ),
      findsOneWidget,
    );
    // The sentence names every service; no button repeats one of them.
    for (final service in globalSearchServices) {
      expect(find.text('Set up ${service.title}'), findsNothing);
    }
    expect(find.text('Open Settings'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Set up a service'),
      findsOneWidget,
    );
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('Set up a service opens Connections', (tester) async {
    final landedOn = await pumpSearch(
      tester,
      nothingSetUp,
      tap: 'Set up a service',
    );

    expect(landedOn?.path, ServiceRoutes.settingsConnections);
  });

  testWidgets('P3 without its Seerr: the calendar band and the catalogue\'s '
      'slab share one margin', (tester) async {
    await pumpSearch(tester, Profiles.p3.without(ServiceKey.seerr));

    final band = find.descendant(
      of: find.byType(CalendarBand),
      matching: find.byType(PressableScale),
    );
    final slab = find
        .ancestor(
          of: find.text('The catalog comes from Seerr'),
          matching: find.byWidgetPredicate(
            (widget) => widget is Container && widget.decoration != null,
          ),
        )
        .first;
    expect(band, findsOneWidget);
    expect(tester.getTopLeft(band).dx, AppSpacing.lg);
    expect(tester.getTopLeft(slab).dx, AppSpacing.lg);
  });

  testWidgets('P3, with Radarr, Sonarr and Seerr: at rest the tab browses '
      'the catalogue, no Set up', (tester) async {
    await pumpSearch(tester, Profiles.p3);

    // The empty state is what a search here would reach when there is no
    // catalogue to browse; with Seerr there is one.
    expect(find.byType(DiscoverAtrium), findsOneWidget);
    expect(find.text('The catalog comes from Seerr'), findsNothing);
    expect(find.textContaining('Set up'), findsNothing);
  });
}
