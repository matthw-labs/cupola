import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/sonarr_overview_provider.dart';
import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/fake_services.dart';

void main() {
  // A fixed instant, never `DateTime.now()`: every rule under test takes its
  // `now` explicitly, which is the whole reason they are top-level functions.
  final now = DateTime(2026, 9, 2, 14, 30);

  group('the week window', () {
    test('opens at local midnight today and closes seven days later', () {
      final week = sonarrAiringWeek([
        // Aired at 09:00 this morning: still today's row. The user has not
        // seen this screen yet.
        _series(id: 1, title: 'Earlier today', nextAiring: _at(now, 0, 9)),
        // 23:59 last night is the previous window.
        _series(id: 2, title: 'Yesterday', nextAiring: _at(now, -1, 23, 59)),
        // Exactly seven days out belongs to next week, not this one.
        _series(id: 3, title: 'Day seven', nextAiring: _at(now, 7, 0, 1)),
        // The last instant that is still inside.
        _series(id: 4, title: 'Day six', nextAiring: _at(now, 6, 23, 59)),
      ], now: now);

      expect(week.entries.map((e) => e.series.title), [
        'Earlier today',
        'Day six',
      ]);
    });

    test('sorts by air time, then by sort title within one slot', () {
      final week = sonarrAiringWeek([
        _series(id: 1, title: 'Zulu', nextAiring: _at(now, 1, 21)),
        _series(id: 2, title: 'Alpha', nextAiring: _at(now, 1, 21)),
        _series(id: 3, title: 'Middle', nextAiring: _at(now, 0, 21)),
      ], now: now);

      expect(week.entries.map((e) => e.series.title), [
        'Middle',
        'Alpha',
        'Zulu',
      ]);
    });

    test('a series without a date is simply not in the window', () {
      final week = sonarrAiringWeek([
        _series(id: 1, title: 'Scheduled', nextAiring: _at(now, 2, 21)),
        _series(id: 2, title: 'Ended', status: 'ended'),
      ], now: now);

      expect(week.entries.map((e) => e.series.title), ['Scheduled']);
    });
  });

  group('whether an empty week can be believed', () {
    test('a running library with no dates at all cannot be reported on', () {
      // The shape of an older Sonarr, or a proxy that dropped the field: eleven
      // continuing series and not one `nextAiring`. Saying "nothing airs this
      // week" here would be a confident answer to an unanswered question.
      final week = sonarrAiringWeek([
        _series(id: 1, status: 'continuing'),
        _series(id: 2, status: 'upcoming'),
      ], now: now);

      expect(week.entries, isEmpty);
      expect(week.canReport, isFalse);
    });

    test('one date anywhere proves the server answers', () {
      final week = sonarrAiringWeek([
        _series(id: 1, status: 'continuing'),
        // Outside the window, so it draws no row, but it settles the question
        // of whether this server reports airings at all.
        _series(id: 2, status: 'continuing', nextAiring: _at(now, 30, 21)),
      ], now: now);

      expect(week.entries, isEmpty);
      expect(week.canReport, isTrue);
    });

    test('a library of finished series reports an honest empty week', () {
      final week = sonarrAiringWeek([
        _series(id: 1, status: 'ended'),
        _series(id: 2, status: 'deleted'),
      ], now: now);

      expect(week.canReport, isTrue);
    });
  });

  group('naming the record', () {
    test('an episode record reads as a slot', () {
      expect(
        sonarrEpisodeSlot({
          'episode': {'seasonNumber': 2, 'episodeNumber': 5},
        }),
        'S2\u00A0E5',
      );
    });

    test('a season pack falls back to the bare season', () {
      // The board's own example row. Without this the season pack loses the
      // only thing that identifies which part of the series failed.
      expect(sonarrEpisodeSlot({'seasonNumber': 4}), 'S4');
    });

    test('a record naming neither says nothing rather than guessing', () {
      expect(sonarrEpisodeSlot({'title': 'Some.Release.1080p'}), isNull);
    });

    test(
      'the subject joins series and slot, then falls back to the release',
      () {
        expect(
          sonarrRecordSubject({
            'series': {'title': 'Slow Horses'},
            'seasonNumber': 4,
          }),
          'Slow Horses S4',
        );
        expect(
          sonarrRecordSubject({'sourceTitle': 'Some.Release.1080p'}),
          'Some.Release.1080p',
        );
        expect(sonarrRecordSubject(const {}), 'Unknown release');
      },
    );
  });

  group('queue faults', () {
    test('a stalled transfer is read as stalled, not as an import fault', () {
      // Sonarr marks both with `trackedDownloadStatus: warning`; a transfer
      // that is not moving has not reached the import stage at all.
      final items = sonarrQueueFaults([
        {
          'series': {'title': 'Andor'},
          'episode': {'seasonNumber': 2, 'episodeNumber': 3},
          'trackedDownloadState': 'importPending',
          'errorMessage': 'The download is stalled with no connections',
          'downloadClient': 'qBittorrent',
          'added': now.subtract(const Duration(hours: 3)).toIso8601String(),
        },
      ], now: now);

      expect(items.single.kind, SonarrAttentionKind.stalled);
      expect(items.single.headline, 'Stuck\u00A0· Andor S2\u00A0E3');
      expect(items.single.detail, contains('qBittorrent'));
      expect(items.single.detail, contains('3\u00A0h ago'));
    });

    test('a failed import names the season pack that failed', () {
      final items = sonarrQueueFaults([
        {
          'series': {'title': 'Slow Horses'},
          'seasonNumber': 4,
          'trackedDownloadState': 'importFailed',
          'errorMessage': 'name does not match',
        },
      ], now: now);

      expect(items.single.kind, SonarrAttentionKind.importFailed);
      expect(items.single.headline, 'Import failed\u00A0· Slow Horses S4');
    });

    test('a healthy queue record is not a fault', () {
      final items = sonarrQueueFaults([
        {
          'series': {'title': 'Severance'},
          'trackedDownloadState': 'downloading',
        },
      ], now: now);

      expect(items, isEmpty);
    });

    test('faults are amber and the backlog is neutral', () {
      // The five-arm tone rule, asserted rather than left to review: painting
      // the backlog amber is the single most common way it is broken.
      expect(SonarrAttentionKind.stalled.tone, StatusTone.warning);
      expect(SonarrAttentionKind.importFailed.tone, StatusTone.warning);
      expect(SonarrAttentionKind.missing.tone, StatusTone.neutral);
      expect(SonarrAttentionKind.belowCutoff.tone, StatusTone.neutral);
    });
  });

  group('queue faults lead to where the fault is fixed', () {
    Map<String, dynamic> stalled(
      String series, {
      required int id,
      required String downloadId,
      int season = 1,
      int episode = 1,
    }) => {
      'id': id,
      'series': {'title': series},
      'episode': {'seasonNumber': season, 'episodeNumber': episode},
      'status': 'warning',
      'errorMessage': 'The download is stalled with no connections',
      'downloadId': downloadId,
    };

    test('one stuck download opens its own page', () {
      final items = sonarrQueueFaults(
        [stalled('Andor', id: 4, downloadId: 'ABC')],
        now: now,
        instanceId: 'sonarr',
      );

      expect(
        items.single.door,
        const AttentionDoor.download(instanceId: 'sonarr', key: 'ABC'),
      );
    });

    test('a season pack is one download, named as a pack', () {
      // Six records of one torrent: six rows before, one fault now.
      final items = sonarrQueueFaults([
        for (var episode = 1; episode <= 6; episode++)
          stalled(
            'Slow Horses',
            id: episode,
            downloadId: 'PACK',
            season: 4,
            episode: episode,
          ),
      ], now: now);

      expect(items, hasLength(1));
      expect(items.single.headline, 'Stuck\u00A0· Slow Horses S4\u00A0E1–E6');
      expect(items.single.count, 1);
      expect(items.single.door, isA<AttentionDownload>());
    });

    test('several stuck downloads are one row that opens the Queue tab', () {
      final items = sonarrQueueFaults(
        [
          stalled('Andor', id: 1, downloadId: 'A'),
          stalled('Severance', id: 2, downloadId: 'B'),
          stalled('Slow Horses', id: 3, downloadId: 'C'),
        ],
        now: now,
        cutShort: true,
      );

      final row = items.single;
      expect(row.headline, '3+ downloads stuck');
      expect(
        row.spoken,
        'at least 3 downloads stuck, Andor S1\u00A0E1, '
        'Severance S1\u00A0E1, Slow Horses S1\u00A0E1',
      );
      expect(row.count, 3);
      expect(row.door, const AttentionDoor.tab(ServiceTab.queue));
    });

    test('the backlog opens Wanted, which lists what is missing and what is '
        'below its cutoff', () {
      expect(
        sonarrMissingEpisodesItem(12)!.door,
        const AttentionDoor.tab(ServiceTab.wanted),
      );
      expect(
        sonarrBelowCutoffItem(3)!.door,
        const AttentionDoor.tab(ServiceTab.wanted),
      );
    });
  });

  group('the backlog rows', () {
    test('a total nobody answered draws no row, and never a zero', () {
      // `ArrRecordPage.total` is nullable precisely so "did not answer" and
      // "answered none" stay different facts. A `0 missing episodes` row over
      // an unasked question is the failure this whole file guards.
      expect(sonarrMissingEpisodesItem(null), isNull);
      expect(sonarrBelowCutoffItem(null), isNull);
    });

    test('an answered zero also draws no row', () {
      expect(sonarrMissingEpisodesItem(0), isNull);
      expect(sonarrBelowCutoffItem(0), isNull);
    });

    test('the rows say episodes, because the record is an episode', () {
      expect(
        sonarrMissingEpisodesItem(12)!.headline,
        '12 missing monitored episodes',
      );
      expect(
        sonarrMissingEpisodesItem(1)!.headline,
        '1 missing monitored episode',
      );
      expect(
        sonarrBelowCutoffItem(9)!.headline,
        '9 episodes below your quality cutoff',
      );
    });

    test('"across 5 series" is printed only when it is known', () {
      expect(
        sonarrMissingEpisodesItem(12, seriesCount: 5)!.detail,
        'across 5 series',
      );
      expect(
        sonarrMissingEpisodesItem(12)!.detail,
        'Sonarr keeps searching for them',
      );
    });
  });

  group('the series a backlog page spans', () {
    test('is null when the page is only a sample of the backlog', () {
      // Twenty rows out of two hundred span the series those twenty happened to
      // touch. Printing that as a fact about the library is a sampling artefact
      // wearing a number.
      final page = ArrRecordPage(
        records: [
          {'seriesId': 1},
          {'seriesId': 2},
        ],
        total: 200,
      );

      expect(sonarrSeriesSpread(page), isNull);
    });

    test('counts distinct series when the page holds every record', () {
      final page = ArrRecordPage(
        records: [
          {'seriesId': 1},
          {'seriesId': 1},
          {
            'series': {'id': 7},
          },
        ],
        total: 3,
      );

      expect(sonarrSeriesSpread(page), 2);
    });

    test('is null when the server did not say how many there are', () {
      final page = ArrRecordPage(
        records: [
          {'seriesId': 1},
        ],
        total: null,
      );

      expect(sonarrSeriesSpread(page), isNull);
    });
  });

  group('recently downloaded', () {
    test('keeps imports, drops grabs, and shows one tile per series', () {
      // A season pack import writes one record per episode; a rail of eight
      // identical posters says less than one.
      final tiles = sonarrRecentlyDownloaded([
        _import(
          seriesId: 1,
          title: 'Severance',
          season: 2,
          episode: 4,
          at: now,
        ),
        _import(
          seriesId: 1,
          title: 'Severance',
          season: 2,
          episode: 3,
          at: now.subtract(const Duration(hours: 1)),
        ),
        {
          'eventType': 'grabbed',
          'seriesId': 2,
          'series': {'title': 'Andor'},
          'date': now.toIso8601String(),
        },
        _import(
          seriesId: 3,
          title: 'Silo',
          season: 3,
          episode: 1,
          at: now.subtract(const Duration(hours: 2)),
        ),
      ], now: now);

      expect(tiles.map((t) => t.seriesTitle), ['Severance', 'Silo']);
      // The newest record of the series is the one whose slot the caption shows.
      expect(tiles.first.slot, 'S2\u00A0E4');
      expect(tiles.first.caption, 'S2\u00A0E4\u00A0· just now');
    });

    test(
      'a record with no series id is dropped, because the tile is a link',
      () {
        final tiles = sonarrRecentlyDownloaded([
          {
            'eventType': 'downloadFolderImported',
            'series': {'title': 'Orphan'},
            'date': now.toIso8601String(),
          },
        ], now: now);

        expect(tiles, isEmpty);
      },
    );

    test('honours the limit, newest first', () {
      final tiles = sonarrRecentlyDownloaded(
        [
          for (var i = 1; i <= 10; i++)
            _import(
              seriesId: i,
              title: 'Series $i',
              season: 1,
              episode: 1,
              at: now.subtract(Duration(hours: i)),
            ),
        ],
        now: now,
        limit: 3,
      );

      expect(tiles.map((t) => t.seriesTitle), [
        'Series 1',
        'Series 2',
        'Series 3',
      ]);
    });
  });

  group('history today', () {
    test('a record from 23:50 yesterday is out, however recent it is', () {
      // The section is headed `today`, and a heading is a promise.
      final entries = sonarrHistoryToday([
        _history(title: 'Late', at: DateTime(2026, 9, 1, 23, 50)),
        _history(title: 'Early', at: DateTime(2026, 9, 2, 0, 10)),
      ], now: now);

      expect(entries.map((e) => e.subject), ['Early']);
    });

    test('names the slot, the event and the evidence', () {
      final entries = sonarrHistoryToday([
        {
          'eventType': 'downloadFolderImported',
          'series': {'title': 'Severance'},
          'episode': {'seasonNumber': 2, 'episodeNumber': 4},
          'quality': {
            'quality': {'name': 'WEB-DL 1080p'},
          },
          'size': 2600000000,
          'date': now.subtract(const Duration(minutes: 40)).toIso8601String(),
        },
      ], now: now);

      final entry = entries.single;
      expect(entry.subject, 'Severance S2\u00A0E4');
      expect(entry.event, 'Imported');
      expect(entry.tone, StatusTone.success);
      expect(entry.detail, contains('WEB-DL 1080p'));
      expect(entry.detail, contains('40\u00A0min ago'));
      // One sentence for the ear, with the layout's dots turned into commas.
      expect(entry.spoken, startsWith('Severance S2\u00A0E4, Imported, '));
      expect(entry.spoken, isNot(contains('·')));
    });

    test('newest first, capped at the limit', () {
      final entries = sonarrHistoryToday(
        [
          _history(title: 'Oldest', at: DateTime(2026, 9, 2, 1)),
          _history(title: 'Newest', at: DateTime(2026, 9, 2, 13)),
          _history(title: 'Middle', at: DateTime(2026, 9, 2, 8)),
        ],
        now: now,
        limit: 2,
      );

      expect(entries.map((e) => e.subject), ['Newest', 'Middle']);
    });
  });

  group('Needs attention, assembled', () {
    test('faults come before the backlog', () async {
      final container = _container(
        _ScriptedSonarr(
          queue: [
            {
              'series': {'title': 'Slow Horses'},
              'seasonNumber': 4,
              'trackedDownloadState': 'importFailed',
            },
          ],
          missing: ArrRecordPage(records: const [], total: 12),
          cutoff: ArrRecordPage(records: const [], total: 9),
        ),
      );

      final items = await container.read(sonarrNeedsAttentionProvider.future);

      expect(items.map((i) => i.kind), [
        SonarrAttentionKind.importFailed,
        SonarrAttentionKind.missing,
        SonarrAttentionKind.belowCutoff,
      ]);
    });

    test('a backlog endpoint that failed does not take the faults down', () {
      // `wanted/missing` is not served by every fork. The faults are the subject
      // of this section; the backlog is an addition to it.
      final container = _container(
        _ScriptedSonarr(
          queue: [
            {
              'series': {'title': 'Andor'},
              'trackedDownloadState': 'importFailed',
            },
          ],
          missingThrows: true,
        ),
      );

      expect(
        container.read(sonarrNeedsAttentionProvider.future),
        completion(
          isA<List<SonarrAttentionItem>>().having(
            (items) => items.map((i) => i.kind),
            'kinds',
            [SonarrAttentionKind.importFailed],
          ),
        ),
      );
    });
  });

  group('the library the week is built from', () {
    test(
      'a failed fetch stays a failure instead of becoming an empty library',
      () {
        // The defect this provider exists for. `getSeries`, the read
        // `seriesProvider` makes, and what this fake still answers, degrades to
        // `[]`, so an unreachable Sonarr resolved the week *successfully* and the
        // header printed "0 series" over "Nothing airing this week". The window
        // function cannot tell those apart; only the fetch can.
        final container = _container(_UnreachableSonarr());

        expect(
          container.read(sonarrOverviewSeriesProvider.future),
          throwsA(isA<Exception>()),
        );
        expect(
          container.read(sonarrAiringWeekProvider.future),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('an empty library that Sonarr really sent is an answer', () async {
      final container = _container(_ScriptedSonarr());

      final week = await container.read(sonarrAiringWeekProvider.future);

      expect(week.entries, isEmpty);
      // Nothing could still air, so silence means nothing airs, and the
      // section is allowed to say so.
      expect(week.canReport, isTrue);
    });
  });

  test('both history sections are read from one page', () async {
    // Two sections, one request: they are two readings of the same rows.
    final service = _ScriptedSonarr(
      history: [
        _import(
          seriesId: 1,
          title: 'Severance',
          season: 2,
          episode: 4,
          at: now,
        ),
      ],
    );
    final container = _container(service);

    await container.read(sonarrRecentlyDownloadedProvider.future);
    await container.read(sonarrHistoryTodayProvider.future);

    expect(service.historyCalls, 1);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

ProviderContainer _container(SonarrService service) {
  final container = ProviderContainer(
    // Riverpod re-runs a failed provider on an exponential backoff; a test that
    // deliberately fails one would otherwise wait out the whole sequence.
    retry: (_, _) => null,
    overrides: [
      sonarrServiceProvider.overrideWith((ref) => service),
      // The connection the lens is on, which a download's door is addressed
      // by: none here, so the door names no connection.
      activeInstanceProvider.overrideWith((ref, service) => null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A [FakeSonarrService] with a scripted queue, history and backlog.
///
/// Extends the shared fake rather than editing it: every other test that builds
/// a `FakeSonarrService` keeps the empty defaults it relies on. The two backlog
/// getters are overridden at the **page** level, because the total is the whole
/// point: the fake's record-only defaults answer `total: null`, which is the
/// "nobody said" case rather than a figure.
class _ScriptedSonarr extends FakeSonarrService {
  _ScriptedSonarr({
    this.queue = const [],
    this.history = const [],
    this.missing = const ArrRecordPage(records: [], total: null),
    this.cutoff = const ArrRecordPage(records: [], total: null),
    this.missingThrows = false,
  });

  final List<dynamic> queue;
  final List<dynamic> history;
  final ArrRecordPage missing;
  final ArrRecordPage cutoff;
  final bool missingThrows;

  /// How many times the history page was actually fetched.
  int historyCalls = 0;

  @override
  Future<List<SonarrSeries>> getSeriesOrThrow() async => const [];

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    historyCalls++;
    return history;
  }

  @override
  Future<ArrRecordPage> getMissingPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (missingThrows) throw Exception('wanted/missing is not served here');
    return missing;
  }

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => cutoff;
}

/// A series carrying only the fields the Overview reads.
SonarrSeries _series({
  required int id,
  String title = 'Series',
  String status = 'continuing',
  bool monitored = true,
  String? nextAiring,
}) => SonarrSeries(
  id: id,
  title: title,
  sortTitle: title.toLowerCase(),
  status: status,
  monitored: monitored,
  year: 2024,
  images: const [],
  tvdbId: id,
  runtime: 45,
  genres: const [],
  seasons: const [],
  nextAiring: nextAiring,
);

/// Local-time ISO, so the window's local calendar days are what the test is
/// actually exercising: a `Z` suffix would move the boundary by the runner's
/// offset and make the assertion pass or fail by timezone.
String _at(DateTime now, int dayOffset, int hour, [int minute = 0]) => DateTime(
  now.year,
  now.month,
  now.day + dayOffset,
  hour,
  minute,
).toIso8601String();

Map<String, dynamic> _import({
  required int seriesId,
  required String title,
  required int season,
  required int episode,
  required DateTime at,
}) => {
  'eventType': 'downloadFolderImported',
  'seriesId': seriesId,
  'series': {'title': title, 'id': seriesId, 'images': const []},
  'episode': {'seasonNumber': season, 'episodeNumber': episode},
  'date': at.toIso8601String(),
};

Map<String, dynamic> _history({required String title, required DateTime at}) =>
    {
      'eventType': 'downloadFolderImported',
      'series': {'title': title},
      'date': at.toIso8601String(),
    };

/// The library fetch fails; everything else is the shared fake's empty default.
///
/// `getSeries` is left alone deliberately: it keeps answering `[]`, which is
/// exactly the ambiguity the Overview's own read was added to escape.
class _UnreachableSonarr extends FakeSonarrService {
  @override
  Future<List<SonarrSeries>> getSeriesOrThrow() async =>
      throw Exception('Sonarr unreachable');
}
