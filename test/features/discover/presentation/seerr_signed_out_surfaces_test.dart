/// A Seerr account that signed out is set up: every surface that would offer
/// to set Seerr up reads it signed out instead, blue, with `Sign in again`
/// into that connection's own form.
///
/// The connection keeps its address and its login and only its session is
/// gone, so `Set up Seerr` would send the person to a form that is already
/// filled in, under words that say nothing is there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/catalog_page.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/presentation/collection_page.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/discover/presentation/person_page.dart';
import 'package:cupola/features/discover/presentation/seerr_overview_screen.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';
import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/settings_connections_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Anna's Seerr, signed out.
final _p2SignedOut = Profiles.p2.withSeerrSignedOut(WorldIds.seerr);

/// The operator's household Seerr on its key, beside Sara's Seerr where his
/// account signed out, with the lens on Sara's.
final _p9FriendSignedOut = Profiles.p9
    .withSeerrSignedOut(WorldIds.seerrFriend)
    .withLens(ServiceKey.seerr, WorldIds.seerrFriend);

Finder _filled(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

void main() {
  group('Seerr pages, before they ask Seerr anything', () {
    final pages = <String, Widget>{
      'the Discover tab': const DiscoverPage(),
      'a movie': MediaPage(mediaKey: MediaKey.movie(10378)),
      'a person': const PersonPage(personId: 17),
      'a collection': const CollectionPage(collectionId: 3),
      'a catalogue page': const CatalogPage(
        query: CatalogQuery.genre(CatalogKind.movie, 16, 'Animation'),
      ),
      "Seerr's overview": const SeerrOverviewScreen(topPadding: 0),
    };

    // The requester reads it about herself and never names Seerr; the
    // operator reads which Seerr signed him out.
    for (final (name, profile, headline) in [
      ('P2 signed out', _p2SignedOut, 'You were signed out'),
      (
        "P9, the lens on Sara's signed-out Seerr",
        _p9FriendSignedOut,
        'Signed out of Seerr',
      ),
    ]) {
      for (final MapEntry(key: page, value: widget) in pages.entries) {
        // The operator reads a title from his other sources, and Sara's
        // Seerr as one row: below.
        if (page == 'a movie' && profile != _p2SignedOut) continue;
        testWidgets('$name: $page reads signed out, never Set up Seerr', (
          tester,
        ) async {
          final harness = await ProfileHarness.start(profile);
          final failures = _FailureLog();
          await tester.pumpWidget(
            ProviderScope(
              overrides: harness.overrides,
              observers: [failures],
              child: MaterialApp(theme: AppTheme.darkTheme(), home: widget),
            ),
          );
          await tester.pump();

          expect(find.text(headline), findsOneWidget);
          expect(_filled('Sign in again'), findsOneWidget);
          expect(find.text('Set up Seerr'), findsNothing);
          expect(find.text('Seerr is not set up'), findsNothing);
          // No Retry: no request revives a session.
          expect(find.text('Retry'), findsNothing);
          // And nothing was asked of a Seerr with no session.
          await tester.pump(const Duration(seconds: 30));
          expect(failures.providers, isEmpty);
          expect(harness.network.requestsTo(WorldIds.seerr), isEmpty);

          await harness.unmount(tester);
        });
      }
    }
  });

  testWidgets("P9: a movie's page names Sara's Seerr signed out in its row, "
      'and asks it nothing', (tester) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = await pumpWithProfile(
      tester,
      _p9FriendSignedOut,
      child: MediaPage(mediaKey: MediaKey.movie(WorldTitles.charge.tmdbId)),
      settle: false,
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Charge'), findsWidgets);
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Sign in again'), findsOneWidget);
    expect(find.text('Set up Seerr'), findsNothing);
    expect(harness.network.requestsTo(WorldIds.seerrFriend), isEmpty);

    await harness.unmount(tester);
  });

  test(
    'its client fails as the ended session, not as not configured',
    () async {
      final harness = await ProfileHarness.start(_p2SignedOut);
      final container = harness.container(retry: (_, _) => null);

      Object? failure;
      try {
        container.read(seerrServiceProvider);
      } catch (error) {
        failure = error;
      }

      // Wrapped by Riverpod, and read through the wrapping.
      expect(unwrapFailure(failure), isA<SeerrSessionEnded>());
      expect(
        classifyConnectionFailure(failure),
        ServiceFailureReason.sessionEnded,
      );
    },
  );

  for (final (name, profile, sentence, seerr) in [
    (
      'P2, the requester',
      _p2SignedOut,
      'You were signed out. Sign in again to keep asking for movies and '
          'series.',
      WorldIds.seerr,
    ),
    (
      "P9, the operator on Sara's Seerr",
      _p9FriendSignedOut,
      'Signed out of Seerr, so the request cannot be sent.',
      WorldIds.seerrFriend,
    ),
  ]) {
    testWidgets('$name: the request sheet is signed out, nothing is sent', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        profile,
        child: Scaffold(
          body: RequestBottomSheet(
            mediaId: 10378,
            mediaType: 'movie',
            onRequestComplete: () {},
          ),
        ),
      );

      expect(find.text(sentence), findsOneWidget);
      expect(_filled('Sign in again'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Submit request'), findsNothing);
      expect(harness.network.requestsTo(seerr), isEmpty);

      await harness.unmount(tester);
    });
  }

  group('Stack', () {
    testWidgets('the stack has Seerr, signed out, not an empty first run', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        _p2SignedOut,
        child: const StackScreen(),
        surfaceSize: const Size(430, 2400),
      );

      // The header counts it apart, the band names it, its cell says it.
      expect(
        find.textContaining('1 signed out\u00A0· 17 not set up'),
        findsOne,
      );
      expect(find.textContaining('Seerr signed out'), findsOne);
      expect(find.text('Signed out'), findsOne);
      expect(find.text('Set up Seerr'), findsNothing);
      expect(find.text('Did not answer'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('one header: the stack, the band and the cells agree', (
      tester,
    ) async {
      // Anna's Seerr signed out beside her own Jellyfin, whose figures say
      // what her token may read.
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2WithJellyfin.withSeerrSignedOut(WorldIds.seerr),
        child: const StackScreen(),
        surfaceSize: const Size(430, 2400),
      );

      expect(
        find.textContaining(
          '1 of 1 answering\u00A0· 1 signed out\u00A0· 16 not set up',
        ),
        findsOne,
      );
      // A band's line is drawn a part at a time, each with its dot.
      expect(find.text('Seerr signed out\u00A0·'), findsOne);
      expect(find.text('5 not set up'), findsOne);
      expect(find.text('1 of 1 clean\u00A0·'), findsOne);
      // The Stream band: Jellyfin is set up, Plex and Emby are not.
      expect(find.text('2 not set up'), findsOne);
      expect(find.text('Signed out'), findsOne);
      expect(find.textContaining('fault'), findsNothing);
      expect(find.textContaining('needs a look'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a signed-out Seerr beside a working one is no fault', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p9.withSeerrSignedOut(WorldIds.seerrFriend),
        child: const StackScreen(),
        surfaceSize: const Size(430, 3000),
      );

      expect(
        find.textContaining('11 of 11 answering\u00A0· 7 not set up'),
        findsOne,
      );
      // Radarr and Sonarr carry the world's faults (a stall, an import),
      // which Needs you holds; Seerr is among the clean.
      expect(find.text('3 of 5 clean\u00A0·'), findsOne);
      expect(find.text('Radarr needs a look\u00A0·'), findsOne);
      expect(find.text('Sonarr needs a look\u00A0·'), findsOne);
      expect(find.text('1 not set up'), findsWidgets);
      expect(find.textContaining('with a fault'), findsNothing);
      expect(find.textContaining('Seerr needs a look'), findsNothing);

      await harness.unmount(tester);
    });

    test("the probe reads a signed-out Seerr as the person's step", () async {
      final harness = await ProfileHarness.start(_p2SignedOut);
      final container = harness.container(retry: (_, _) => null);

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.seerr).future,
      );

      expect(summary.failureReason, ServiceFailureReason.sessionEnded);
      expect(summary.didNotAnswer, isFalse);
      expect(harness.network.requestsTo(WorldIds.seerr), isEmpty);
    });
  });

  testWidgets("the lens sheet lists Sara's Seerr, signed out", (tester) async {
    final harness = await pumpWithProfile(
      tester,
      _p9FriendSignedOut,
      child: const Scaffold(
        body: Center(child: InstanceLensBadge(service: ServiceKey.seerr)),
      ),
    );

    await tester.tap(find.byType(InstanceLensBadge));
    await harness.settle(tester);

    expect(find.text('Signed out\u00A0· seerr.example.net'), findsOneWidget);
    expect(find.text('nas.home.arpa:5055'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Settings lists the connection, signed out', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      _p2SignedOut,
      child: const SettingsConnectionsScreen(),
      surfaceSize: const Size(430, 2400),
    );

    expect(find.text('Signed out\u00A0· nas.home.arpa:5055'), findsOneWidget);
    // Not offered again among the services to set up.
    expect(find.text('Seerr'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Search never offers to set Seerr up', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      _p2SignedOut,
      child: const DiscoverPage(),
    );

    expect(find.textContaining('Set up Seerr'), findsNothing);
    expect(find.textContaining('Seerr,'), findsNothing);

    await harness.unmount(tester);
  });
}

/// Every provider that failed while the page was up.
final class _FailureLog extends ProviderObserver {
  final providers = <String>[];

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    providers.add('${context.provider.name ?? context.provider}: $error');
  }
}
