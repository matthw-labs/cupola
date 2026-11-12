/// A series' page reads its seasons from Sonarr and the media server
/// together: each episode one word, Sonarr's facts one row each, the next
/// episode to air, and the one Play continues.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/media/domain/media_lead.dart';
import 'package:cupola/features/media/domain/media_row_view.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/domain/media_series_manage.dart';
import 'package:cupola/features/media/domain/media_subtitles.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode_file.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../test_helpers/profiles/profiles.dart';
import 'media_test_helpers.dart';

StreamItem _episode(
  int season,
  int number, {
  bool played = false,
  int? offset,
}) => StreamItem(
  id: 'e$season$number',
  title: 'Episode $number',
  subtitle: null,
  kind: StreamItemKind.episode,
  posterPath: null,
  year: null,
  runtimeMs: 1200000,
  isPlayed: played,
  resumeOffsetMs: offset,
  unplayedChildCount: null,
  seasonNumber: season,
  episodeNumber: number,
);

void main() {
  final now = DateTime.now();

  group('Cosmos Laundromat in the full household', () {
    late List<MediaRow> rows;

    setUpAll(() async {
      rows = (await settledRows(
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
      )).rows;
    });

    test('each episode says one word, from the queue, the server, the '
        'file and the air date', () {
      final seasons = mediaSeasonsOf(
        rows,
        audience: Audience.operator,
        now: now,
      );

      expect(seasons.map((s) => s.label), ['Season 1', 'Season 2', 'Season 3']);
      final second = seasons[1].episodes;
      expect(second.map((e) => e.state), [
        // A stuck upgrade leaves a watched episode watched.
        'Watched',
        'Watched',
        '5\u00A0min\u00A0left',
        'Downloading 88%',
        'Downloading 9%',
        'Missing',
        'Missing',
        'Missing',
        'Missing',
        'Missing',
      ]);
      expect(second[2].title, 'The Second Cycle');
      expect(second[2].progress, closeTo(0.75, 0.001));
      expect(second[2].downloading, isFalse);
      expect(second[3].tone, StatusTone.info);
      expect(second[3].downloading, isTrue);
      expect(seasons[1].missing.map((e) => e.number), [6, 7, 8, 9, 10]);
      // Eight announced with a date, then two without one (Sonarr's `TBA`,
      // issue #13): neither aired nor missing.
      expect(seasons[2].episodes.map((e) => e.state), [
        for (var e = 1; e <= 8; e++) 'Not aired',
        'No air date',
        'No air date',
      ]);
      expect(seasons[2].missing, isEmpty);
      expect(
        second[2].spoken,
        'Episode 3, The Second Cycle. 5\u00A0min\u00A0left',
      );
    });

    test('the requester reads where it stands, never what Sonarr misses', () {
      final second = mediaSeasonsOf(
        rows,
        audience: Audience.requester,
        now: now,
      )[1].episodes;

      expect(second[5].state, 'Not on the server yet');
      expect(second.any((e) => e.missing), isFalse);
    });

    test('Sonarr says one row per fact; the server counts by season', () {
      String title(ServiceInstance connection) => connection.service.title;
      final sonarr = rows.firstWhere((r) => r.service == ServiceKey.sonarr);
      final views = mediaRowViews(sonarr, title: title, now: now, rows: rows);

      expect(views.map((v) => (v.detail, v.state)).take(2), [
        ('S2\u00A0E4–E5', 'Downloading'),
        ('S2\u00A0E6–E10 aired', '5 missing'),
      ]);
      final fault = views.last;
      expect(fault.shape, MediaRowShape.fault);
      expect(
        fault.state,
        'S1\u00A0· S2\u00A0E1–E2\u00A0· 12 upgrades need import',
      );
      expect(fault.tone, StatusTone.warning);
      expect(fault.action, 'Review the imports');
      expect(fault.way, MediaRowWay.review);
      expect(fault.targetId, 1);

      final jellyfin = rows.firstWhere((r) => r.service == ServiceKey.jellyfin);
      expect(
        mediaRowViews(
          jellyfin,
          title: title,
          now: now,
          rows: rows,
        ).single.detail,
        'S1 10 of 10\u00A0· S2 3 of 10',
      );
    });

    test('Bazarr says the languages on disk, where one is wanted, and '
        'which', () {
      String title(ServiceInstance connection) => connection.service.title;
      final bazarr = rows.firstWhere((r) => r.service == ServiceKey.bazarr);
      final view = mediaRowViews(
        bazarr,
        title: title,
        now: now,
        rows: rows,
      ).single;

      expect(view.detail, 'English on disk\u00A0· S2\u00A0E1–E3');
      expect(view.state, 'Italian wanted');
    });

    test('Play continues the episode part-way through', () {
      final lead = resolveMediaLead(rows, audience: Audience.operator);

      expect(lead, isA<MediaLeadPlay>());
      final play = lead as MediaLeadPlay;
      expect((play.episode?.seasonNumber, play.episode?.episodeNumber), (2, 3));
      expect(play.resume, isTrue);
    });

    test('Manage names the files, the last import and each season', () {
      final MediaSonarrCopy copy = rows
          .whereType<MediaConnectionRow<MediaSonarrCopy>>()
          .map((row) => (row.reading as MediaReadingAnswered).answer.value)
          .single;
      final series = copy.series!;
      final files = <int, SonarrEpisodeFile>{
        for (final episode in copy.episodes.where((e) => e.hasFile))
          episode.episodeFileId!: SonarrEpisodeFile(
            id: episode.episodeFileId!,
            relativePath: 'file.mkv',
            qualityName: episode.seasonNumber == 2 && episode.episodeNumber == 3
                ? 'WEBDL-1080p'
                : 'WEBDL-720p',
            dateAdded: episode.seasonNumber == 2 && episode.episodeNumber == 3
                ? now.subtract(const Duration(hours: 2))
                : now.subtract(const Duration(days: 40)),
          ),
      };

      expect(
        mediaSeriesFilesSummary(series, null),
        '13 files\u00A0· 8.3\u00A0GB',
      );
      expect(
        mediaSeriesFilesSummary(series, files.values),
        '13 files\u00A0· 720p WEB, 1080p WEB',
      );
      expect(
        mediaSeriesLastImport(copy.episodes, files, now: now),
        startsWith('Last imported S2\u00A0E3\u00A0· '),
      );
      expect(mediaSeriesLastImport(copy.episodes, null), isEmpty);

      final seasons = mediaSeasonFilesOf(
        series,
        copy.episodes,
        files: files,
        now: now,
      );
      expect(seasons.map((s) => (s.label, s.detail, s.aired)), [
        ('Season 1', '10 of 10 on disk\u00A0· 720p WEB', true),
        ('Season 2', '3 of 10 on disk\u00A0· 720p WEB, 1080p WEB', true),
        ('Season 3', '10 episodes\u00A0· not aired', false),
      ]);
    });

    test('the next to air is Sonarr\'s, with its hour', () {
      final next = mediaNextAiringOf(rows, now: now)!;

      expect((next.season, next.number), (3, 1));
      expect(next.premiere, isTrue);
      expect(next.timed, isTrue);
      expect(next.sonarrMonitors, isTrue);
    });
  });

  test('a series\' Sonarr copy never leads: without a media server, the '
      'rows say what is missing', () async {
    final rows = (await settledRows(
      Profiles.p3,
      WorldTitles.cosmosLaundromat,
    )).rows;

    expect(
      resolveMediaLead(rows, audience: Audience.operator),
      isNot(isA<MediaLeadCopy>()),
    );
  });

  test('subtitles name up to two languages, then their codes', () {
    const english = BazarrSubtitleLanguage(name: 'English', code2: 'en');
    const italian = BazarrSubtitleLanguage(name: 'Italian', code2: 'it');
    const german = BazarrSubtitleLanguage(name: 'German', code2: 'de');
    BazarrEpisode episode(
      int number, {
      List<BazarrSubtitleLanguage> present = const [],
      List<BazarrSubtitleLanguage> missing = const [],
    }) => BazarrEpisode(
      sonarrEpisodeId: number,
      season: 1,
      episode: number,
      presentLanguages: present,
      missingLanguages: missing,
    );

    expect(
      mediaEpisodeSubtitles(episode(1, present: [english], missing: [italian])),
      'English on disk\u00A0· Italian wanted',
    );
    expect(
      mediaEpisodeSubtitles(episode(2, missing: [english, italian, german])),
      'EN\u00A0· IT\u00A0· DE wanted',
    );
    expect(mediaEpisodeSubtitles(episode(3)), isNull);
    expect(
      mediaSeriesSubtitlesSummary([
        episode(1, present: [english], missing: [italian]),
        episode(2, present: [english], missing: [italian]),
        episode(3, present: [english, italian]),
      ]),
      'EN\u00A0· IT wanted on 2 episodes',
    );
  });

  test('qualities name the commonest first, then how many more', () {
    SonarrEpisodeFile file(String quality) =>
        SonarrEpisodeFile(id: 0, relativePath: '', qualityName: quality);
    expect(
      mediaQualitiesOf([
        file('WEBDL-1080p'),
        file('WEBDL-720p'),
        file('WEBDL-720p'),
        file('Bluray-2160p'),
        file('HDTV-720p'),
      ]),
      '720p WEB, 1080p WEB +2',
    );
  });

  test('without Sonarr, TMDB dates the next episode: a day, and the '
      'season it opens', () async {
    final rows = (await settledRows(
      Profiles.p5,
      WorldTitles.cosmosLaundromat,
    )).rows;

    final next = mediaNextAiringOf(rows, now: DateTime.now())!;

    expect((next.season, next.number), (3, 1));
    expect(next.timed, isFalse);
    expect(next.seasonEpisodes, 8);
  });

  group('the episode Play opens', () {
    test('the one part-way through', () {
      expect(
        mediaNextEpisode([
          _episode(1, 1, played: true),
          _episode(1, 2, offset: 60000),
          _episode(1, 3),
        ])?.episodeNumber,
        2,
      );
    });

    test('else the first unwatched after the last watched', () {
      expect(
        mediaNextEpisode([
          _episode(1, 1, played: true),
          _episode(1, 2),
          _episode(2, 1, played: true),
          _episode(2, 2),
        ]),
        isA<StreamItem>()
            .having((e) => e.seasonNumber, 'season', 2)
            .having((e) => e.episodeNumber, 'number', 2),
      );
    });

    test('the first of all when none is watched, none when all are', () {
      expect(
        mediaNextEpisode([_episode(1, 2), _episode(1, 1)])?.episodeNumber,
        1,
      );
      expect(mediaNextEpisode([_episode(1, 1, played: true)]), isNull);
    });
  });

  test('the graph averages each season, ranks the best, and names the '
      'stronger season', () {
    MediaEpisodeFacts facts(int season, int number, double? vote, int votes) =>
        MediaEpisodeFacts(
          season: season,
          number: number,
          voteAverage: vote,
          voteCount: votes,
        );
    final graph = mediaEpisodesGraphOf({
      1: [facts(1, 1, 7.0, 40), facts(1, 2, 8.0, 40)],
      2: [facts(2, 1, 8.9, 31), facts(2, 2, 8.1, 12)],
      3: [facts(3, 1, null, 0)],
    });

    expect(graph.seasons.map((s) => s.average), [
      7.5,
      closeTo(8.5, 1e-9),
      null,
    ]);
    expect(graph.best.map((e) => (e.season, e.number)), [
      (2, 1),
      (2, 2),
      (1, 2),
    ]);
    expect(graph.stronger?.season, 2);
    expect(graph.stronger?.fewVotes, 1);
    expect(MediaEpisodesGraph.stepOf(7.2), 0);
    expect(MediaEpisodesGraph.stepOf(8.5), 5);
  });

  test('a profile names the resolution its cutoff stops at', () {
    expect(
      sonarrCutoffResolution({
        'cutoff': 1001,
        'items': [
          {
            'quality': {'id': 5, 'resolution': 720},
          },
          {
            'id': 1001,
            'name': 'WEB 1080p',
            'items': [
              {
                'quality': {'id': 3, 'resolution': 1080},
              },
            ],
          },
        ],
      }),
      '1080p',
    );
    expect(sonarrCutoffResolution({'cutoff': 9, 'items': const []}), isNull);
  });
}
