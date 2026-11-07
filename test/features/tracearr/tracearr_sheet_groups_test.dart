import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session.dart';

import '../../test_helpers/fixtures.dart';

/// The detail sheet reads a viewing in groups: when and how far, then how it
/// played, then where. Every fact the sheet states lands in one group, and
/// source and output read as one value.
void main() {
  final now = DateTime.utc(2026, 11, 7, 15);

  TracearrSession live() => TracearrSession.live(
    TracearrStreams.fromJson(
      jsonFixture('tracearr/streams.json'),
    ).streams.first,
  );

  TracearrSession recorded() => TracearrSession.recorded(
    TracearrHistoryEntry.fromJson(
      (jsonFixtureMap('tracearr/history_page.json')['data'] as List).first
          as Map<String, dynamic>,
    ),
  );

  List<String> labels(TracearrSheetGroup group) => [
    for (final row in group.rows) row.label,
  ];

  test('a recorded viewing: when first, unheaded, then Playback and Where', () {
    final groups = tracearrSheetGroupsOf(recorded(), now: now);

    expect([for (final g in groups) g.heading], [null, 'Playback', 'Where']);
    expect(labels(groups[0]), containsAllInOrder(['Started', 'Ran for']));
    expect(labels(groups[0]).last, 'Completion');
    expect(labels(groups[1]).first, 'How');
    expect(labels(groups[2]), ['Server', 'Device']);
  });

  test('no fact is lost or added: the groups hold the facts and How and the '
      'compared sides', () {
    for (final session in [live(), recorded()]) {
      final groups = tracearrSheetGroupsOf(session, now: now);
      final grouped = [for (final g in groups) ...labels(g)];
      final facts = [
        for (final fact in tracearrFactsOf(session, now: now)) fact.label,
      ];
      final compared = [
        for (final row in tracearrComparisonOf(session.quality)) row.label,
      ];
      expect(grouped.toSet(), {...facts, 'How', ...compared});
      expect(grouped.length, facts.length + 1 + compared.length);
    }
  });

  group('source to output', () {
    const row = (
      label: 'Video',
      source: 'HEVC · 2160p · HDR10',
      output: 'H.264 · 1080p · SDR',
    );

    test('a conversion reads source to output', () {
      expect(
        tracearrSourceToOutput(row, converted: true),
        'HEVC · 2160p · HDR10 → H.264 · 1080p · SDR',
      );
    });

    test(
      'nothing converted reads the source once, whatever the output says',
      () {
        expect(tracearrSourceToOutput(row, converted: false), row.source);
      },
    );

    test('sides that agree, or one unknown, read once', () {
      expect(
        tracearrSourceToOutput((
          label: 'Audio',
          source: 'EAC3 · 5.1',
          output: 'EAC3 · 5.1',
        ), converted: true),
        'EAC3 · 5.1',
      );
      expect(
        tracearrSourceToOutput((
          label: 'Audio',
          source: Lexicon.noFigure,
          output: 'AAC · Stereo',
        ), converted: true),
        'AAC · Stereo',
      );
      expect(
        tracearrSourceToOutput((
          label: 'Audio',
          source: 'EAC3 · 5.1',
          output: Lexicon.noFigure,
        ), converted: true),
        'EAC3 · 5.1',
      );
    });
  });
}
