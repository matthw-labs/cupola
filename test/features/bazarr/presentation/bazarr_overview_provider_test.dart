import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_overview_provider.dart';

void main() {
  group('bazarrWantedHeadline', () {
    test('an episode is its series plus the code, in the app\'s spelling '
        'whichever way Bazarr wrote it', () {
      for (final written in ['S02E04', '2x4', '2x04']) {
        expect(
          bazarrWantedHeadline(
            BazarrWantedItem(
              seriesTitle: 'Severance',
              episodeNumber: written,
              sonarrSeriesId: 3,
            ),
          ),
          'Severance\u00A0· S2\u00A0E4',
          reason: written,
        );
      }
    });

    test('a code in neither shape is printed as Bazarr sent it', () {
      expect(
        bazarrWantedHeadline(
          const BazarrWantedItem(
            seriesTitle: 'Severance',
            episodeNumber: 'Special 1',
            sonarrSeriesId: 3,
          ),
        ),
        'Severance\u00A0· Special 1',
      );
    });

    test('a film is its title', () {
      expect(
        bazarrWantedHeadline(
          const BazarrWantedItem(title: 'Poor Things', radarrId: 8),
        ),
        'Poor Things',
      );
    });

    test('a row with neither still has a name', () {
      expect(bazarrWantedHeadline(const BazarrWantedItem()), 'Unknown title');
    });
  });

  group('bazarrWantedDetail', () {
    test('names the missing languages and which arr owns the record', () {
      expect(
        bazarrWantedDetail(
          const BazarrWantedItem(
            seriesTitle: 'Severance',
            episodeNumber: 'S02E04',
            sonarrSeriesId: 3,
            missingLanguages: [BazarrSubtitleLanguage(name: 'Italian')],
          ),
        ),
        'Italian\u00A0· Sonarr',
      );
      expect(
        bazarrWantedDetail(
          const BazarrWantedItem(
            title: 'Poor Things',
            radarrId: 8,
            missingLanguages: [
              BazarrSubtitleLanguage(name: 'English', forced: true),
            ],
          ),
        ),
        'English forced\u00A0· Radarr',
      );
    });

    test('never prints an age, because Bazarr never sends one', () {
      // The board draws "missing 3 days"; neither wanted endpoint carries a
      // date, so a figure there would be invented rather than read.
      final detail = bazarrWantedDetail(
        const BazarrWantedItem(title: 'Past Lives', radarrId: 1),
      );
      expect(detail, 'Radarr');
      expect(detail, isNot(contains('day')));
    });
  });

  group('bazarrWantedSection', () {
    test('backlog is NEUTRAL: a wanted count is not a fault', () {
      final section = bazarrWantedSection(const [
        BazarrWantedItem(title: 'Poor Things', radarrId: 1),
      ], total: 47);

      expect(section.rows.single.tone, StatusTone.neutral);
      // And nothing in the section is amber, whatever the size of the backlog.
      expect(
        section.rows.every((row) => row.tone == StatusTone.neutral),
        isTrue,
      );
    });

    test('the total is Bazarr\'s badge, not the length of the page', () {
      final section = bazarrWantedSection(
        [
          for (var i = 0; i < 12; i++)
            BazarrWantedItem(title: 'T$i', radarrId: i),
        ],
        total: 47,
        limit: 5,
      );

      expect(section.rows, hasLength(5));
      expect(section.total, 47);
    });
  });

  group('bazarrHistoryTone', () {
    test('a subtitle that landed is green, a match is informational', () {
      expect(
        bazarrHistoryTone(_history(action: BazarrHistoryActionCode.downloaded)),
        StatusTone.success,
      );
      expect(
        bazarrHistoryTone(_history(action: BazarrHistoryActionCode.upgraded)),
        StatusTone.success,
      );
    });

    test('a blacklisted entry is NEUTRAL: blacklisting is a choice', () {
      expect(
        bazarrHistoryTone(
          _history(
            action: BazarrHistoryActionCode.downloaded,
            blacklisted: true,
          ),
        ),
        StatusTone.neutral,
      );
    });

    test('a removal is neutral, not a fault', () {
      expect(
        bazarrHistoryTone(_history(action: BazarrHistoryActionCode.removed)),
        StatusTone.neutral,
      );
    });
  });

  group('bazarrHistoryRows', () {
    test('quotes Bazarr\'s own words for when, and computes no age', () {
      final rows = bazarrHistoryRows([
        _history(
          action: BazarrHistoryActionCode.downloaded,
          title: 'Severance',
          subtitle: 'S02E03',
          language: 'Italian',
          provider: 'OpenSubtitles',
          score: 94,
          timestamp: '20 minutes ago',
        ),
      ]);

      final row = rows.single;
      expect(row.headline, 'Severance, S02E03\u00A0· Italian downloaded');
      expect(row.detail, 'OpenSubtitles\u00A0· score 94\u00A0· 20 minutes ago');
      // Spoken as a sentence: the layout's dots come back as pauses.
      expect(
        row.spoken,
        'Severance, S02E03, Italian downloaded, OpenSubtitles, '
        'score 94, 20 minutes ago',
      );
    });

    test('cuts at the preview limit', () {
      final rows = bazarrHistoryRows([
        for (var i = 0; i < 9; i++)
          _history(action: BazarrHistoryActionCode.downloaded, title: 'T$i'),
      ], limit: 3);
      expect(rows, hasLength(3));
    });
  });

  group('bazarrHistoryWhen', () {
    test('prefers the pretty string and falls back to the parsed one', () {
      expect(
        bazarrHistoryWhen(
          _history(
            action: 1,
            timestamp: '1 hour ago',
            parsed: '09/16/26 13:20',
          ),
        ),
        '1 hour ago',
      );
      expect(
        bazarrHistoryWhen(
          _history(action: 1, timestamp: '', parsed: '09/16/26 13:20'),
        ),
        '09/16/26 13:20',
      );
      expect(bazarrHistoryWhen(_history(action: 1)), isNull);
    });
  });
}

BazarrHistoryItem _history({
  required int action,
  String title = 'Title',
  String? subtitle,
  String? language,
  String? provider,
  int? score,
  String? timestamp,
  String? parsed,
  bool blacklisted = false,
}) => BazarrHistoryItem(
  kind: subtitle == null ? BazarrHistoryKind.movie : BazarrHistoryKind.episode,
  title: title,
  subtitle: subtitle,
  languageLabel: language,
  provider: provider,
  actionCode: action,
  timestamp: timestamp,
  parsedTimestamp: parsed,
  score: score,
  blacklisted: blacklisted,
);
