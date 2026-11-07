import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/room_art.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/service_overview.dart';
import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/overview_shell.dart';

/// The rules the four Overviews used to guard four times over, now once.
///
/// These are not renderings. Each case is a property that the extraction had to
/// carry across intact, and that the next nine Overviews inherit for free:
/// Prowlarr's capped trailing figure, the section link's spoken destination,
/// and the row's one-sentence label.
Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  group('ServiceOverviewRow', () {
    testWidgets(
      'the trailing figure ellipsises rather than overflowing at 3x',
      (tester) async {
        // The one feature Prowlarr's private copy had that the other three
        // lacked, and the reason it exists: an unconstrained figure beside an
        // `Expanded` title is a right-edge overflow at an accessibility reading
        // size, and a row that throws is worse than a figure that ellipsises:
        // the whole value is still in the sentence a screen reader hears.
        await tester.pumpWidget(
          _host(
            textScale: 3,
            const SizedBox(
              width: 360,
              child: ServiceOverviewRow(
                spoken: 'Nyaa, 298 queries, 4 grabs',
                leading: Icon(Icons.circle, size: 8),
                title: 'Nyaa',
                detail: 'torrent\u00A0· public',
                trailing: '298 queries',
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);

        final figure = tester.widget<Text>(find.text('298 queries'));
        expect(figure.maxLines, 1);
        expect(figure.overflow, TextOverflow.ellipsis);

        // The cap itself, not merely "it fits": a row that happened to fit at
        // this width would pass without it and overflow on a narrower one.
        final box = tester.renderObject<RenderBox>(find.text('298 queries'));
        expect(box.size.width, lessThanOrEqualTo(132));
      },
    );

    testWidgets('speaks one sentence and silences its parts', (tester) async {
      // Nothing in the row is interactive, so read separately the mark, the
      // title and the figure are three fragments of one fact.
      await tester.pumpWidget(
        _host(
          const ServiceOverviewRow(
            spoken: 'Nyaa, 298 queries',
            leading: Icon(Icons.circle, size: 8),
            title: 'Nyaa',
            detail: 'torrent\u00A0· public',
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Nyaa, 298 queries'),
        findsOneWidget,
        reason: 'the row must be one container node, not three fragments',
      );
      expect(find.bySemanticsLabel('torrent\u00A0· public'), findsNothing);
      handle.dispose();
    });
  });

  group('ServiceOverviewRow as a door', () {
    ServiceOverviewRow row({
      VoidCallback? onTap,
      String? doorHint,
      ServiceOverviewRowAction? action,
      String detail = 'torrent\u00A0· public',
    }) => ServiceOverviewRow(
      spoken: 'Nyaa, failing, disabled until 15:40',
      leading: const Icon(Icons.error_outline_rounded, size: 18),
      title: 'Nyaa',
      detail: detail,
      onTap: onTap,
      doorHint: doorHint,
      action: action,
    );

    testWidgets('a row with a door is one button: the sentence, where it '
        'goes, and the tap', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          row(
            onTap: () => opened++,
            doorHint: 'opens the Prowlarr Indexers tab',
          ),
        ),
      );

      expect(
        find.semantics.byLabel('Nyaa, failing, disabled until 15:40'),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hint: 'opens the Prowlarr Indexers tab',
        ),
      );
      // The parts are silenced: the door is one stop, not three.
      expect(find.bySemanticsLabel('Nyaa'), findsNothing);

      await tester.tap(find.text('Nyaa'));
      expect(opened, 1);
    });

    testWidgets('a row with no door is plain text, not a button', (
      tester,
    ) async {
      await tester.pumpWidget(_host(row()));

      expect(
        find.semantics.byLabel('Nyaa, failing, disabled until 15:40'),
        isSemantics(isButton: false, hasTapAction: false),
      );
      // And it draws no chevron: nothing in it opens.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('a door is marked by a chevron, and a row with a verb is '
        'marked by the verb', (tester) async {
      await tester.pumpWidget(_host(row(onTap: () {}, doorHint: 'opens it')));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      await tester.pumpWidget(
        _host(
          row(
            onTap: () {},
            doorHint: 'opens it',
            action: ServiceOverviewRowAction(
              label: 'Test',
              hint: 'tests Nyaa',
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('a door reaches 44 tall even when the row is one line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(row(onTap: () {}, doorHint: 'opens it', detail: '')),
      );

      final target = tester.getSize(find.byType(InkWell));
      expect(target.height, greaterThanOrEqualTo(44));
    });

    testWidgets('a door and a plain row take the same room when both have '
        'two lines', (tester) async {
      await tester.pumpWidget(_host(row()));
      final plain = tester.getSize(find.byType(ServiceOverviewRow)).height;

      await tester.pumpWidget(_host(row(onTap: () {}, doorHint: 'opens it')));
      final door = tester.getSize(find.byType(ServiceOverviewRow)).height;

      expect(door, plain, reason: 'the rhythm of a section must not change');
    });

    testWidgets('a verb is a real button beside the door, named by its own '
        'label and hint', (tester) async {
      var tested = 0;
      var opened = 0;
      await tester.pumpWidget(
        _host(
          row(
            onTap: () => opened++,
            doorHint: 'opens the indexer',
            action: ServiceOverviewRowAction(
              label: 'Test',
              hint: 'tests Nyaa',
              onPressed: () => tested++,
            ),
          ),
        ),
      );

      // Annotated on the button's own child, so the hint lands on its node.
      expect(
        tester.getSemantics(find.byType(TextButton)),
        isSemantics(
          label: 'Test',
          hint: 'tests Nyaa',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // The door is still one sentence, and it is not the verb's node.
      expect(
        find.semantics.byLabel('Nyaa, failing, disabled until 15:40'),
        isSemantics(isButton: true, hint: 'opens the indexer'),
      );

      await tester.tap(find.text('Test'));
      expect(tested, 1);
      expect(opened, 0, reason: 'the verb does not also open the door');

      await tester.tap(find.text('Nyaa'));
      expect(opened, 1);
      expect(tested, 1, reason: 'the door does not also run the verb');
    });

    testWidgets('an amber fault\'s remedy is the amber fill under the row\'s '
        'words, named by its label and hint', (tester) async {
      var tested = 0;
      var opened = 0;
      await tester.pumpWidget(
        _host(
          row(
            onTap: () => opened++,
            doorHint: 'opens the indexer',
            action: ServiceOverviewRowAction.remedy(
              label: 'Test',
              hint: 'tests Nyaa',
              onPressed: () => tested++,
            ),
          ),
        ),
      );

      expect(find.byType(TextButton), findsNothing);
      final button = find.byType(FilledButton);
      expect(button, findsOneWidget);
      // Under the words, so a long name keeps the row's width.
      expect(
        tester.getTopLeft(button).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Nyaa')).dy),
      );
      expect(
        tester.getSemantics(button),
        isSemantics(
          label: 'Test',
          hint: 'tests Nyaa',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(button);
      expect(tested, 1);
      expect(opened, 0, reason: 'the remedy does not also open the door');
    });

    testWidgets('a verb on a row with no door is still a button, and the row '
        'is still one sentence', (tester) async {
      await tester.pumpWidget(
        _host(
          row(
            action: ServiceOverviewRowAction(
              label: 'Start',
              hint: 'starts immich',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Start'), findsOneWidget);
      expect(
        find.semantics.byLabel('Nyaa, failing, disabled until 15:40'),
        isSemantics(isButton: false),
      );
    });

    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      testWidgets('the verb keeps its 44pt target on ${platform.name}, where '
          'the density would otherwise take 4 off it', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: SingleChildScrollView(
                child: row(
                  action: ServiceOverviewRowAction(
                    label: 'Test',
                    hint: 'tests Nyaa',
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          tester.getSize(find.byType(TextButton)).height,
          greaterThanOrEqualTo(44),
        );
      });
    }

    testWidgets('a door must say where it goes', (tester) async {
      expect(
        () => ServiceOverviewRow(
          spoken: 'x',
          leading: const SizedBox(),
          title: 'x',
          detail: '',
          onTap: () {},
        ),
        throwsAssertionError,
      );
    });

    testWidgets('a long verb is capped under half the row, so the words keep '
        'the larger part, and the whole label is still its name', (
      tester,
    ) async {
      for (final scale in [1.0, 3.0]) {
        await tester.pumpWidget(
          _host(
            textScale: scale,
            SizedBox(
              width: 360,
              child: row(
                onTap: () {},
                doorHint: 'opens the download',
                action: ServiceOverviewRowAction(
                  label: 'Look for peers again',
                  hint: 'asks the trackers again for Nyaa',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull, reason: 'at $scale');
        expect(
          tester.getSize(find.byType(TextButton)).width,
          lessThanOrEqualTo(360 * 0.45),
          reason: 'at $scale',
        );
        expect(
          tester.getSemantics(find.byType(TextButton)),
          isSemantics(label: 'Look for peers again', isButton: true),
        );
      }
    });

    testWidgets('a door and its verb fit at 3x without overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          textScale: 3,
          SizedBox(
            width: 360,
            child: row(
              onTap: () {},
              doorHint: 'opens the indexer',
              action: ServiceOverviewRowAction(
                label: 'Test',
                hint: 'tests Nyaa',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('openAttentionDoor', () {
    /// A host whose Overview is one button per door, so a test taps a door
    /// the way a row does.
    Future<OverviewShell> pumpDoors(
      WidgetTester tester,
      ServiceKey service,
      Map<String, AttentionDoor> doors,
    ) async {
      final shell = OverviewShell(
        service,
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                for (final entry in doors.entries)
                  TextButton(
                    onPressed: () =>
                        openAttentionDoor(context, service, entry.value),
                    child: Text(entry.key),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(shell.app);
      await tester.pumpAndSettle();
      return shell;
    }

    testWidgets('a tab door switches the branch, as the tab bar does', (
      tester,
    ) async {
      final shell = await pumpDoors(tester, ServiceKey.prowlarr, {
        'tab': const AttentionDoor.tab(ServiceTab.indexers),
      });
      expect(shell.tab, ServiceTab.overview);

      await tester.tap(find.text('tab'));
      await tester.pumpAndSettle();

      expect(shell.tab, ServiceTab.indexers);
      expect(find.text('tab Indexers'), findsOneWidget);
    });

    testWidgets('a download door pushes that download\'s page, with its '
        'connection and its key in the address', (tester) async {
      final shell = await pumpDoors(tester, ServiceKey.qbittorrent, {
        'download': const AttentionDoor.download(instanceId: 'qb', key: 'abc'),
      });

      await tester.tap(find.text('download'));
      await tester.pumpAndSettle();

      expect(shell.location, '/activity/download?i=qb&id=abc');
    });

    testWidgets('a page door pushes the page it names', (tester) async {
      final shell = await pumpDoors(tester, ServiceKey.dockge, {
        'page': const AttentionDoor.page(
          location: '/stack/dockge/stacks/stack/immich',
          hint: 'opens immich',
        ),
      });

      await tester.tap(find.text('page'));
      await tester.pumpAndSettle();

      expect(shell.location, '/stack/dockge/stacks/stack/immich');
    });

    testWidgets('outside a router a door does nothing and does not throw', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                for (final door in const [
                  AttentionDoor.tab(ServiceTab.indexers),
                  AttentionDoor.download(instanceId: 'qb', key: 'abc'),
                  AttentionDoor.page(location: '/x', hint: 'opens x'),
                ]) {
                  openAttentionDoor(context, ServiceKey.prowlarr, door);
                }
              },
              child: const Text('go'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      expect(tester.takeException(), isNull);
    });

    test(
      'the hint names the service and the tab, or says it is a download',
      () {
        expect(
          attentionDoorHint(
            ServiceKey.prowlarr,
            const AttentionDoor.tab(ServiceTab.indexers),
          ),
          'opens the Prowlarr Indexers tab',
        );
        expect(
          attentionDoorHint(
            ServiceKey.qbittorrent,
            const AttentionDoor.download(instanceId: 'qb', key: 'abc'),
          ),
          'opens this download',
        );
        expect(
          attentionDoorHint(
            ServiceKey.dockge,
            const AttentionDoor.page(location: '/x', hint: 'opens immich'),
          ),
          'opens immich',
        );
      },
    );
  });

  group('ServiceOverviewSection', () {
    testWidgets('the link names the service and the tab it opens', (
      tester,
    ) async {
      // The link's glyph is "→", which a screen reader says as "rightwards
      // arrow". The destination has to arrive as a hint or it does not arrive.
      await tester.pumpWidget(
        _host(
          const ServiceOverviewSection(
            service: ServiceKey.prowlarr,
            title: 'Indexers',
            destination: ServiceTab.indexers,
            child: Text('body'),
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      final hints = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.hint)
          .whereType<String>();
      expect(hints, contains('opens the Prowlarr Indexers tab'));
      handle.dispose();
    });

    testWidgets('a section with no destination offers no link', (tester) async {
      // A region whose rows belong to several tabs at once has nowhere single
      // to send anyone, so it draws no affordance rather than a dead one.
      await tester.pumpWidget(
        _host(
          const ServiceOverviewSection(
            service: ServiceKey.bazarr,
            title: 'Needs attention',
            child: Text('body'),
          ),
        ),
      );

      expect(find.textContaining('→'), findsNothing);
    });

    testWidgets('bleed leaves the body on the window edge', (tester) async {
      // The poster-rail shape: the row runs off the column while its first tile
      // still aligns to it, so the section must NOT inset the body.
      for (final bleeding in [false, true]) {
        await tester.pumpWidget(
          _host(
            bleeding
                ? const ServiceOverviewSection.bleed(
                    service: ServiceKey.radarr,
                    title: 'Recently added',
                    child: SizedBox(key: ValueKey('body'), height: 20),
                  )
                : const ServiceOverviewSection(
                    service: ServiceKey.radarr,
                    title: 'Recently added',
                    child: SizedBox(key: ValueKey('body'), height: 20),
                  ),
          ),
        );

        final left = tester.getTopLeft(find.byKey(const ValueKey('body'))).dx;
        expect(
          left,
          bleeding ? 0 : greaterThan(0),
          reason: 'bleeding=$bleeding',
        );
      }
    });
  });

  group('a section about titles', () {
    testWidgets('glows with its first title\'s light inside its slab, and a '
        'rail never does', (tester) async {
      final art = bakeRoomArt((
        source: 'teal',
        pixels: (
          rgba: Uint8List.fromList([
            for (var i = 0; i < 16 * 16; i++) ...[46, 125, 122, 255],
          ]),
          width: 16,
          height: 16,
        ),
      ))!;
      await tester.pumpWidget(
        _host(
          ServiceOverviewSection(
            service: ServiceKey.sonarr,
            title: 'Airing this week',
            light: art,
            child: const SizedBox(height: 40),
          ),
        ),
      );
      expect(find.byType(SlabLight), findsOneWidget);

      await tester.pumpWidget(
        _host(
          const ServiceOverviewSection(
            service: ServiceKey.sonarr,
            title: 'Airing this week',
            child: SizedBox(height: 40),
          ),
        ),
      );
      expect(find.byType(SlabLight), findsNothing);
    });

    testWidgets('a row with no poster shows the title\'s initials', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ServiceOverviewArt(posterUrl: null, title: 'Night Shift')),
      );
      expect(find.text('NS'), findsOneWidget);
    });

    testWidgets('the initials fit their plate at 200% and at 3x', (
      tester,
    ) async {
      for (final scale in [2.0, 3.0]) {
        await tester.pumpWidget(
          _host(
            const ServiceOverviewArt(posterUrl: null, title: 'Wide Wow'),
            textScale: scale,
          ),
        );
        final plate = tester.getRect(find.byType(ServiceOverviewArt));
        final text = tester.getRect(find.text('WW'));
        expect(text.left, greaterThanOrEqualTo(plate.left), reason: '$scale');
        expect(text.right, lessThanOrEqualTo(plate.right), reason: '$scale');
        expect(text.top, greaterThanOrEqualTo(plate.top), reason: '$scale');
        expect(text.bottom, lessThanOrEqualTo(plate.bottom), reason: '$scale');
      }
    });

    test('initials: two words, one word, and none', () {
      expect(overviewInitialsOf('Night Shift'), 'NS');
      expect(overviewInitialsOf('The Long Field'), 'TL');
      expect(overviewInitialsOf('Severance'), 'SE');
      expect(overviewInitialsOf('  '), '');
      expect(overviewInitialsOf('Cupertino: Part 2'), 'CP');
    });

    testWidgets('the day reads Today, else the weekday, over its date', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 19, 9);
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              ServiceOverviewDay(day: DateTime(2026, 10, 19), now: now),
              ServiceOverviewDay(day: DateTime(2026, 10, 21), now: now),
            ],
          ),
        ),
      );
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('19 Oct'), findsOneWidget);
      expect(find.text('Wed'), findsOneWidget);
      expect(find.text('21 Oct'), findsOneWidget);
    });
  });
}
