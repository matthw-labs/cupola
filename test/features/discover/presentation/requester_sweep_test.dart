/// The requester's sweep: every surface a household member reaches, under
/// each way she signs in, read for what she must never meet.
///
/// No service is named but the players she watches with, no operator's word
/// (an API key, a queue, an indexer, a quality profile, a root folder, an
/// instance), no operator's control (Manage, Approve, Decline, the request
/// sheet's pickers), and nobody else's name. A Seerr that does not answer is
/// one line with its time, never the classification.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/calendar_page.dart';
import 'package:cupola/features/discover/presentation/catalog_page.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/demo/world/fakes/media_fakes.dart';
import 'package:cupola/core/widgets/floating_nav_rail.dart';
import 'package:cupola/features/shell/presentation/desktop/command_deck.dart';
import 'package:cupola/features/discover/presentation/collection_page.dart';
import 'package:cupola/features/discover/presentation/person_page.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/requests/presentation/requests_screen.dart';
import 'package:cupola/features/home/presentation/edit_home_page.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/requester_account_page.dart';
import 'package:cupola/features/settings/presentation/settings_appearance_screen.dart';
import 'package:cupola/features/settings/presentation/settings_home_screen.dart';
import 'package:cupola/features/settings/presentation/settings_region_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Words the requester never reads (the brand book's requester section).
/// `release` is left out: the page's TMDB release dates are hers to read, and
/// the word she must not meet, a download's release name, is a service's.
final _never = <RegExp>[
  for (final service in ServiceKey.values)
    // The three players a household member watches with (`namesService`).
    if (service != ServiceKey.jellyfin &&
        service != ServiceKey.plex &&
        service != ServiceKey.emby)
      RegExp(RegExp.escape(service.title)),
  RegExp(r'\bAPI key\b', caseSensitive: false),
  RegExp(r'\bqueue\b', caseSensitive: false),
  RegExp(r'\bindexers?\b', caseSensitive: false),
  RegExp(r'\bquality profile\b', caseSensitive: false),
  RegExp(r'\broot folder\b', caseSensitive: false),
  RegExp(r'\binstance\b', caseSensitive: false),
  RegExp(r'^(Manage|Approve|Decline|Server)$'),
  RegExp(r'\b(Approve|Decline) request\b'),
  // The operator's words for a request that cannot be made: the requester's
  // button reads `Didn't go through` and `Can't be requested`.
  RegExp(r'^Request failed$'),
  // Seerr's and the download's state words on a badge: the requester's read
  // `On the server`, `On its way`, `Blocked` and the rest.
  RegExp(
    r'^(4K: )?(Available|Partially available|Processing|Blocklisted|Deleted|'
    r'Unknown|Queued|Stuck|Failed|Import blocked|Client unavailable)$',
  ),
  // Copying this device's connections to another is the operator's: she has
  // none to hand over, and no door to take any (Settings' two rows).
  RegExp(r'\banother device\b', caseSensitive: false),
  RegExp(r'\bnew phone\b', caseSensitive: false),
  RegExp(r'\bAll services\b'),
  RegExp(r'\bacross every service\b', caseSensitive: false),
  RegExp(r'\bconnections? asked\b'),
  // Somebody else's name: Luca's request is not hers to see.
  RegExp(WorldPeople.luca),
];

/// Every word on screen, tooltips included.
List<String> _words(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
  for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
    rich.text.toPlainText(),
  for (final tip in tester.widgetList<Tooltip>(find.byType(Tooltip)))
    tip.message ?? '',
];

void _expectNothingOfTheOperators(WidgetTester tester, String where) {
  final met = <String>[
    for (final word in _words(tester))
      if (!_herAccountLine.hasMatch(word))
        for (final pattern in _never)
          if (pattern.hasMatch(word)) '"$word" (${pattern.pattern})',
  ];
  expect(met, isEmpty, reason: where);
}

final _pages = <String, Widget>{
  // Her Home: what arrived, what is on its way, the shelves; and her page
  // of requests, with Cancel request on the one that waits.
  'the Home': const HomeScreen(),
  'the Requests tab': const RequestsScreen(),
  'the Discover tab': const DiscoverPage(),
  // The one page a title has: the requester's reads no service but the
  // players, and no copy's fault, whatever the household holds.
  'the Media page, a movie of hers': MediaPage(
    mediaKey: MediaKey.movie(WorldTitles.charge.tmdbId),
  ),
  "the Media page, Luca's movie": MediaPage(
    mediaKey: MediaKey.movie(WorldTitles.metropolis.tmdbId),
  ),
  'the Media page, a stuck download': MediaPage(
    mediaKey: MediaKey.movie(WorldTitles.bigBuckBunny.tmdbId),
  ),
  'the Media page, a movie on the server': MediaPage(
    mediaKey: MediaKey.movie(WorldTitles.tearsOfSteel.tmdbId),
  ),
  'the Media page, a series with a season to ask for': MediaPage(
    mediaKey: MediaKey.tv(WorldTitles.nightShift.tmdbId),
  ),
  'the Media page, a series on the server in part': MediaPage(
    mediaKey: MediaKey.tv(WorldTitles.cosmosLaundromat.tmdbId),
  ),
  'a person': const PersonPage(personId: SeerrFake.personId),
  'a collection': const CollectionPage(collectionId: SeerrFake.collectionId),
  'a catalogue page': const CatalogPage(
    query: CatalogQuery.genre(CatalogKind.movie, 16, 'Animation'),
  ),
  'the request sheet, a movie': Scaffold(
    body: SingleChildScrollView(
      child: RequestBottomSheet(
        mediaId: WorldTitles.bigBuckBunny.tmdbId,
        mediaType: 'movie',
        onRequestComplete: () {},
      ),
    ),
  ),
  'the request sheet, a series': Scaffold(
    body: SingleChildScrollView(
      child: RequestBottomSheet(
        mediaId: WorldTitles.agent327.tmdbId,
        mediaType: 'tv',
        onRequestComplete: () {},
      ),
    ),
  ),
  'the global search': const DiscoverPage(),
  // Her calendar comes from her requests, and says no service.
  'the calendar': const CalendarPage(),
  // Her Settings: her account, what she sets for herself, the app.
  'Settings': const SettingsHomeScreen(),
  'her account': const RequesterAccountPage(),
  'Region': const SettingsRegionScreen(),
  'Appearance': const SettingsAppearanceScreen(),
  'Edit Home': const EditHomePage(),
};

/// The one service name she reads besides the players: her server's own, in
/// her account, beside its address (the spec of the requester, § 6.2).
final _herAccountLine = RegExp(r'^\S+\u00A0· nas\.home\.arpa:5055$');

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget page,
) async {
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        globalSearchQueryProvider.overrideWith((ref) => 'sprite'),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

/// Anna with her own Emby token beside her Seerr account: a player she
/// watches in, named where Jellyfin and Plex are (`namesService`).
final _p2WithEmby = Profiles.p2.withConnection(
  ProfileConnection(
    WorldConnections.emby.instance.copyWith(viewerId: EmbyFake.annaId),
    behaviour: ConnectionBehaviour.readOnly,
  ),
);

void main() {
  for (final profile in [
    Profiles.p2,
    Profiles.p2ViaJellyfin,
    Profiles.p2ViaPlex,
  ]) {
    for (final MapEntry(key: name, value: page) in _pages.entries) {
      testWidgets('${profile.id}: $name', (tester) async {
        final harness = await _pump(tester, profile, page);

        _expectNothingOfTheOperators(tester, '${profile.id}, $name');

        await harness.unmount(tester);
      });
    }
  }

  // Her own Emby beside her account: the pages that name a player. The Media
  // pages of a title her player holds are not walked here: its server row says
  // `Available`, a word the sweep refuses, exactly as with her own Jellyfin
  // (P2+J), so it is a finding about those rows and not about Emby.
  for (final name in [
    'the Home',
    'the Requests tab',
    'the Discover tab',
    'the Media page, a movie of hers',
    'the global search',
    'Settings',
    'her account',
  ]) {
    testWidgets('P2+E: $name', (tester) async {
      final harness = await _pump(tester, _p2WithEmby, _pages[name]!);

      _expectNothingOfTheOperators(tester, 'P2+E, $name');

      await harness.unmount(tester);
    });
  }

  testWidgets('the sweep sees the operator\'s words where they are (P3)', (
    tester,
  ) async {
    // A scan that read nothing would pass every sweep above.
    final harness = await _pump(
      tester,
      Profiles.p3,
      _pages['the Media page, a movie of hers']!,
    );

    final met = [
      for (final word in _words(tester))
        for (final pattern in _never)
          if (pattern.hasMatch(word)) word,
    ];
    expect(met, containsAll(['Approve', 'Decline', 'Seerr']));

    await harness.unmount(tester);
  });

  group('a Seerr that does not answer', () {
    final silent = Profiles.p2.withBehaviour(
      WorldIds.seerr,
      ConnectionBehaviour.didNotAnswer,
    );
    final line = RegExp(r"^Can't reach the server since \d\d:\d\d\.?$");

    for (final name in [
      'the Home',
      'the Requests tab',
      'the Discover tab',
      'the Media page, a movie of hers',
      'the global search',
      'the calendar',
    ]) {
      testWidgets('P2: $name says one line with its time, and Retry', (
        tester,
      ) async {
        final harness = await _pump(tester, silent, _pages[name]!);

        final lines = [
          for (final word in _words(tester))
            if (line.hasMatch(word)) word,
        ];
        expect(lines, isNotEmpty);
        expect(find.text('Retry'), findsWidgets);
        expect(find.textContaining('did not answer'), findsNothing);
        _expectNothingOfTheOperators(tester, 'P2 silent, $name');

        await harness.unmount(tester);
      });
    }
  });

  group('her window and her tablet', () {
    // The platform comes from each test's variant, which sets it and puts it
    // back around the body.
    Future<(ProfileHarness, ProviderContainer)> pumpApp(
      WidgetTester tester, {
      required Size size,
      String? location,
      ConfigProfile? profile,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = await ProfileHarness.start(profile ?? Profiles.p2);
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
      await harness.settle(tester);
      if (location != null) {
        router.go(location);
        await harness.settle(tester);
      }
      return (harness, container);
    }

    for (final (name, location) in [
      ('the Home', null),
      ('the Requests tab', ServiceRoutes.requests),
      ('the Discover tab', ServiceRoutes.discover),
      ('Settings', ServiceRoutes.settings),
      ('her account', ServiceRoutes.settingsAccount),
    ]) {
      testWidgets('on a Mac, $name: her sections, no service, no '
          'inspector, no deck', (tester) async {
        final (harness, _) = await pumpApp(
          tester,
          size: const Size(1440, 900),
          location: location,
        );

        expect(find.text('Requests'), findsWidgets);
        expect(find.text('Services'), findsNothing);
        expect(find.text('Inspector'), findsNothing);
        expect(find.textContaining('Jump to'), findsNothing);
        _expectNothingOfTheOperators(tester, 'P2 on a Mac, $name');

        await harness.unmount(tester);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

      testWidgets('on a tablet, $name', (tester) async {
        final (harness, _) = await pumpApp(
          tester,
          size: const Size(1180, 820),
          location: location,
        );

        expect(find.byType(FloatingNavRail), findsOne);
        _expectNothingOfTheOperators(tester, 'P2 on a tablet, $name');

        await harness.unmount(tester);
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }

    testWidgets('the code another device copies from is not hers: its page '
        'sends her to Settings', (tester) async {
      final (harness, container) = await pumpApp(
        tester,
        size: const Size(430, 900),
        location: ServiceRoutes.settingsAnotherDevice,
      );

      expect(
        container.read(routerProvider).state.uri.toString(),
        ServiceRoutes.settings,
      );
      expect(find.text('Set up another device'), findsNothing);
      expect(find.text('Copy from another device'), findsNothing);
      await harness.unmount(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('⌘K opens no deck: it reaches every room and connection by '
        'name', (tester) async {
      final (harness, _) = await pumpApp(tester, size: const Size(1440, 900));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await harness.settle(tester);

      expect(find.byType(CommandDeck), findsNothing);
      _expectNothingOfTheOperators(tester, 'P2, after ⌘K');

      await harness.unmount(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('the same keys open the operator\'s deck (P1)', (tester) async {
      // A keystroke that reached nothing would pass the test above.
      final (harness, container) = await pumpApp(
        tester,
        size: const Size(1440, 900),
        profile: Profiles.p1,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await harness.settle(tester);

      expect(find.byType(CommandDeck), findsOne);

      // Dockge's socket closes with its container, and leaves a timer that
      // must run out before the test does.
      await harness.unmount(tester);
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}
