import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/import/domain/blocked_import.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/blocked_import_parts.dart';
import 'package:cupola/features/import/presentation/manual_import_fix_sheet.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The match sheet: which title, then which episode, for one file or
/// several; and the Review's episode row that sits beside it.
void main() {
  final single = _file('Laundromat.Tapes.E04.720p.WEB');
  final reels = [
    for (final reel in ['A', 'B', 'C']) _file('Laundromat.Tapes.Reel.$reel'),
  ];

  group('one file', () {
    testWidgets('the series wear their posters and say what they are', (
      tester,
    ) async {
      await _open(tester, [single], flow: _Flow([single, _placed]));

      expect(find.text('Which series?'), findsOne);
      expect(find.text('Laundromat.Tapes.E04.720p.WEB'), findsOne);
      expect(find.text('Series\u00A0· 2015\u00A0· 2 seasons'), findsOne);
      // No button until there is something to match to: the row is the step.
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('each episode says when it aired and whether it is on disk, '
        'and the one another file holds says which', (tester) async {
      await _open(tester, [single], flow: _Flow([single, _placed]));
      await _tapText(tester, 'Cosmos Laundromat');

      expect(find.text('Which episode?'), findsOne);
      expect(find.text('Aired 11 Feb 2016\u00A0· On disk'), findsOne);
      expect(find.text('Aired 13 Apr 2016\u00A0· Missing'), findsOne);
      expect(find.text('Episode'), findsOne, reason: 'the label, not a line');
      expect(
        find.textContaining(
          'Laundromat.Tapes.E03.720p.WEB',
          findRichText: true,
        ),
        findsOne,
      );
      // The name says E04: the sheet starts there.
      expect(find.text('Match to S1\u00A0E4'), findsOne);
    });

    testWidgets('Match writes the episode picked', (tester) async {
      final flow = _Flow([single, _placed]);
      await _open(tester, [single], flow: flow);
      await _tapText(tester, 'Cosmos Laundromat');
      await _tapText(tester, 'E5\u00A0· Tilly');
      await _tapText(tester, 'Match to S1\u00A0E5');

      expect(flow.applied.keys.single.path, single.path);
      expect(flow.applied.values.single.episode?.episodeNumber, 5);
      expect(find.text('Which episode?'), findsNothing, reason: 'closed');
    });

    testWidgets('Change goes back to the series', (tester) async {
      await _open(tester, [single], flow: _Flow([single]));
      await _tapText(tester, 'Cosmos Laundromat');
      await _tapText(tester, 'Change');

      expect(find.text('Which series?'), findsOne);
    });
  });

  group('several files', () {
    testWidgets('one episode picked, the files after it follow in order', (
      tester,
    ) async {
      final flow = _Flow([...reels]);
      await _open(tester, reels, flow: flow);
      await _tapText(tester, 'Cosmos Laundromat');
      expect(find.text('Which episodes?'), findsOne);
      expect(find.text('Pick one'), findsNWidgets(3));

      await tester.tap(find.text('Laundromat.Tapes.Reel.A'));
      await _settle(tester);
      await _tapText(tester, 'E4\u00A0· The Island');

      expect(find.text('E5\u00A0· Tilly'), findsOne);
      expect(find.text('E6\u00A0· Second Spin'), findsOne);
      await _tapText(tester, 'Match 3 files');
      expect(
        [for (final a in flow.bulk.values) a.episode?.episodeNumber],
        [4, 5, 6],
      );
      // One episode per file: no file is ever given a list of them (M-05).
      expect([for (final a in flow.bulk.values) a.episodes.length], [1, 1, 1]);
    });
  });

  testWidgets('a movie is picked, then matched', (tester) async {
    final flow = _Flow([single], service: ServiceKey.radarr);
    await _open(tester, [single], flow: flow, service: ServiceKey.radarr);

    expect(find.text('Which movie?'), findsOne);
    expect(find.text('Pick a movie'), findsOne);
    await _tapText(tester, 'Hero');
    await _tapText(tester, 'Match to Hero');

    expect(flow.applied.values.single.match.title, 'Hero');
  });

  group("the Review's episode row", () {
    testWidgets('follows the episode placed before it, in its season', (
      tester,
    ) async {
      final second = _file('Laundromat.Tapes.Reel.B');
      await _review(tester, second, flow: _Flow([_placed, second]));

      expect(find.text('E4'), findsOne);
      expect(find.textContaining('is already on'), findsNothing);
    });

    testWidgets('says which file already holds the episode it is on', (
      tester,
    ) async {
      final second = _file('Laundromat.Tapes.Reel.B');
      await _review(tester, second, flow: _Flow([_placed, second]));
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await _settle(tester);

      expect(find.text('E3'), findsOne);
      expect(
        find.textContaining('S1\u00A0E3 is already on', findRichText: true),
        findsOne,
      );
    });
  });
}

final _cosmos = <String, dynamic>{
  'id': 7,
  'title': 'Cosmos Laundromat',
  'year': 2015,
  'seasons': [
    {'seasonNumber': 0},
    {'seasonNumber': 1},
    {'seasonNumber': 2},
  ],
};

const _titles = [
  'First Cycle',
  'The Sheep',
  'Franck',
  'The Island',
  'Tilly',
  'Second Spin',
];

ManualImportItem _file(String name, {Map<String, dynamic>? episode}) =>
    ManualImportItem.fromJson({
      'id': name.hashCode,
      'path': '/downloads/$name/$name.mkv',
      'name': name,
      'size': 700000000,
      'series': _cosmos,
      'episodes': [?episode],
      'quality': {
        'quality': {'id': 5, 'name': 'WEBDL-720p'},
      },
    });

final _placed = _file(
  'Laundromat.Tapes.E03.720p.WEB',
  episode: {'id': 2103, 'seasonNumber': 1, 'episodeNumber': 3},
);

class _Flow extends ManualImportFlowNotifier {
  _Flow(this.items, {this.service = ServiceKey.sonarr});

  final List<ManualImportItem> items;
  final ServiceKey service;
  final applied = <ManualImportItem, ManualImportFixAssignment>{};
  final bulk = <ManualImportItem, ManualImportFixAssignment>{};

  @override
  ManualImportFlowState build() =>
      ManualImportFlowState(service: service, items: items);

  @override
  Future<List<ManualImportLookupResult>> getLibraryMatches() async => [
    for (final json in [
      _cosmos,
      {'id': 9, 'title': 'Hero', 'year': 2018},
    ])
      ManualImportLookupResult.fromJson(service, json),
  ];

  @override
  Future<List<ManualImportLookupResult>> lookup(String term) async => const [];

  @override
  Future<List<ManualImportEpisode>> getEpisodes({
    required int seriesId,
    int? seasonNumber,
  }) async => [
    for (var e = 1; e <= _titles.length; e++)
      if (seasonNumber == null || seasonNumber == 1)
        ManualImportEpisode.fromJson({
          'id': 2100 + e,
          'seasonNumber': 1,
          'episodeNumber': e,
          'title': _titles[e - 1],
          'airDate': '2016-0${e + 1}-1$e',
          'hasFile': e <= 2,
        }),
  ];

  @override
  Future<ManualImportItem?> applyFixAssignment(
    ManualImportItem item,
    ManualImportFixAssignment assignment,
  ) async {
    applied[item] = assignment;
    return item;
  }

  @override
  Future<List<ManualImportItem>> applyBulkFixAssignments(
    Map<ManualImportItem, ManualImportFixAssignment> assignments, {
    bool select = true,
  }) async {
    bulk.addAll(assignments);
    return assignments.keys.toList();
  }
}

Future<void> _pump(WidgetTester tester, _Flow flow, Widget home) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [manualImportFlowProvider.overrideWith(() => flow)],
      child: MaterialApp(theme: AppTheme.darkTheme(), home: home),
    ),
  );
  await _settle(tester);
}

Future<void> _open(
  WidgetTester tester,
  List<ManualImportItem> items, {
  required _Flow flow,
  ServiceKey service = ServiceKey.sonarr,
}) async {
  await _pump(
    tester,
    flow,
    Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => items.length == 1
              ? showManualImportFixSheet(
                  context: context,
                  service: service,
                  item: items.single,
                )
              : showManualImportBulkFixSheet(
                  context: context,
                  service: service,
                  items: items,
                ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await _tapText(tester, 'open');
}

Future<void> _review(
  WidgetTester tester,
  ManualImportItem item, {
  required _Flow flow,
}) async {
  await _pump(tester, flow, Scaffold(body: _OpenRow(item: item)));
  await tester.tap(find.byIcon(Icons.expand_more_rounded));
  await _settle(tester);
}

class _OpenRow extends StatefulWidget {
  const _OpenRow({required this.item});

  final ManualImportItem item;

  @override
  State<_OpenRow> createState() => _OpenRowState();
}

class _OpenRowState extends State<_OpenRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      BlockedImportNeedYouRow(
        service: ServiceKey.sonarr,
        item: widget.item,
        kind: NeedYouKind.episode,
        selected: false,
        open: _open,
        onOpen: () => setState(() => _open = !_open),
        onPlaced: () {},
      ),
    ],
  );
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pump();
  await tester.tap(find.text(text).last);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
