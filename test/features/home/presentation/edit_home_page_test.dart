import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/domain/home_layout.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/edit_home_page.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

import '../../../test_helpers/settings_scope.dart';

/// Edit Home: reorder by handle or arrows, switch off, reset, and the moves a
/// screen reader is offered.
void main() {
  late SharedPreferences prefs;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Audience audience = Audience.operator,
    Map<String, Object> stored = const {},
    // A stack that feeds every module, so each row says what it shows.
    List<ServiceKey> configured = const [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.seerr,
      ServiceKey.jellyfin,
      ServiceKey.qbittorrent,
      ServiceKey.truenas,
    ],
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    // Tall enough for the whole page: a list builds only what it shows.
    tester.view.physicalSize = const Size(1206, 5400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialSettingsProvider.overrideWith(
          (ref) => settingsWithServices(configured),
        ),
        shellAudienceProvider.overrideWith(() => _Fixed(audience)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const EditHomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('lists Needs you first with a handle and no switch, then the '
      'ordered modules, then Set up next, with Reset dimmed on the default', (
    tester,
  ) async {
    await pump(tester);

    for (final module in HomeModule.of(Audience.operator)) {
      expect(find.text(module.label), findsOneWidget, reason: module.label);
    }
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    // Needs you moves like the others, by its handle, and has no switch.
    final needsYouRow = find.ancestor(
      of: find.text('Needs you'),
      matching: find.byType(Row),
    );
    expect(find.bySemanticsLabel('Move Needs you'), findsOneWidget);
    expect(
      find.descendant(of: needsYouRow.first, matching: find.byType(Switch)),
      findsNothing,
    );
    // The ten ordered modules and Set up next each have one.
    expect(find.byType(Switch), findsNWidgets(11));
    final reset = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(reset.onPressed, isNull);
    // The other person's default, from the registry.
    expect(
      find.textContaining('Trending this week and Coming soon'),
      findsOneWidget,
    );
  });

  testWidgets('a tapped handle lifts its row; the arrows move it and the '
      'layout is kept', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.bySemanticsLabel('Move Arrived'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Move Arrived up'), findsOneWidget);
    expect(find.bySemanticsLabel('Move Arrived down'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Move Arrived down'));
    await tester.pumpAndSettle();

    expect(container.read(homeLayoutProvider).order, [
      HomeModule.needsYou,
      HomeModule.featured,
      HomeModule.continueWatching,
      HomeModule.comingUp,
      HomeModule.downloads,
      HomeModule.arrived,
      HomeModule.requests,
      HomeModule.nowPlaying,
      HomeModule.stackHealth,
      HomeModule.storage,
      HomeModule.discoverShelf,
    ]);
    final saved = HomeLayout.read(
      prefs.getString('home_layout_operator'),
      Audience.operator,
    );
    expect(saved.order, container.read(homeLayoutProvider).order);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(
      tester.getTopLeft(find.text('Downloads')).dy,
      lessThan(tester.getTopLeft(find.text('Arrived')).dy),
    );
  });

  testWidgets('a switch takes a module off the Home, and Reset brings the '
      'default back', (tester) async {
    final container = await pump(tester);

    // Featured, Continue watching, Coming up, Arrived, Downloads, then
    // Requests.
    await tester.tap(find.byType(Switch).at(5));
    await tester.pumpAndSettle();
    expect(
      container.read(homeLayoutProvider).isOn(HomeModule.requests),
      isFalse,
    );
    expect(prefs.getString('home_layout_operator'), contains('requests'));

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(container.read(homeLayoutProvider).isDefault, isTrue);
    expect(prefs.getString('home_layout_operator'), isNull);
  });

  testWidgets('a screen reader can move a row from its switch', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await pump(tester);

    final node = tester.getSemantics(
      find.descendant(
        of: find
            .ancestor(of: find.text('Downloads'), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      ),
    );
    final actions = node.getSemanticsData().customSemanticsActionIds!;
    expect(actions, hasLength(2));
    final ids = {
      for (final id in actions) CustomSemanticsAction.getAction(id)!.label: id,
    };
    expect(ids.keys, containsAll(['Move up', 'Move down']));

    node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      ids['Move up'],
    );
    await tester.pumpAndSettle();
    expect(container.read(homeLayoutProvider).order.take(5), [
      HomeModule.needsYou,
      HomeModule.featured,
      HomeModule.continueWatching,
      HomeModule.comingUp,
      HomeModule.downloads,
    ]);
    handle.dispose();
  });

  testWidgets('a module none of whose services is set up says what it '
      'needs', (tester) async {
    await pump(tester, configured: const [ServiceKey.radarr]);
    expect(find.text('Needs TrueNAS or Unraid'), findsOneWidget);
    expect(find.text('Needs Seerr'), findsNWidgets(2));
    // Continue watching needs a media server; Now playing may be given its
    // rows by Tracearr alone.
    expect(find.text('Needs Jellyfin, Plex or Emby'), findsOneWidget);
    expect(find.text('Needs Jellyfin, Plex, Emby or Tracearr'), findsOneWidget);
    // Radarr feeds Arrived: it says what it shows.
    expect(find.text(HomeModule.arrived.line), findsOneWidget);
    // Stack health reads the whole stack, and needs nothing.
    expect(find.text(HomeModule.stackHealth.line), findsOneWidget);
  });

  testWidgets('the requester arranges her own Home, kept apart', (
    tester,
  ) async {
    final container = await pump(
      tester,
      audience: Audience.requester,
      stored: {
        'home_layout_operator': HomeLayout.defaultFor(
          Audience.operator,
        ).switched(HomeModule.requests, on: false).toJson(),
      },
    );

    expect(find.text('Trending this week'), findsOneWidget);
    expect(find.text('Needs you'), findsNothing);
    expect(container.read(homeLayoutProvider).isDefault, isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(prefs.getString('home_layout_requester'), contains('trending'));
    expect(prefs.getString('home_layout_operator'), contains('requests'));
  });
}

class _Fixed extends ShellAudienceNotifier {
  _Fixed(this.audience);

  final Audience audience;

  @override
  Audience build() => audience;
}
