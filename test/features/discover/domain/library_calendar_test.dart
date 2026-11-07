import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The calendar of everything the household's arrs date: one row per
/// release, airing, album and book in the next thirty days, each connection
/// that holds it named once, and the words each row says.
void main() {
  // Tuesday 29 September, 20:53, as on the boards.
  final now = DateTime(2026, 9, 29, 20, 53);
  final window = CalendarWindow.from(now);
  String day(int offset) {
    final d = DateTime(2026, 9, 29 + offset);
    return '${d.year}-${'${d.month}'.padLeft(2, '0')}-'
        '${'${d.day}'.padLeft(2, '0')}T00:00:00Z';
  }

  Map<String, dynamic> spriteFright({bool hasFile = false}) => {
    'id': 7,
    'tmdbId': 508947,
    'title': 'Sprite Fright',
    'hasFile': hasFile,
    'digitalRelease': day(0),
    'physicalRelease': day(13),
    // Long before the window: no row.
    'inCinemas': '2021-10-29T00:00:00Z',
  };

  ArrQueueSnapshot downloading(int id) => ArrQueueSnapshot.fromQueueItems([
    {
      'movieId': id,
      'status': 'downloading',
      'trackedDownloadState': 'downloading',
      'size': 100,
      'sizeleft': 38,
      'estimatedCompletionTime': DateTime(
        2026,
        9,
        29,
        21,
        10,
      ).toUtc().toIso8601String(),
    },
  ], idsFor: (item) => [item['movieId'] as int]);

  CalendarReading reading(
    ServiceKey service,
    String label,
    List<Map<String, dynamic>> records, {
    ArrQueueSnapshot? queue,
    String? id,
  }) => CalendarReading(
    service: service,
    connectionId: id ?? label,
    label: label,
    records: records,
    queue: queue,
  );

  test('a movie is a row per release inside the thirty days, one row for '
      'every Radarr that holds it, the furthest on of them', () {
    final events = libraryCalendarEvents(
      [
        reading(ServiceKey.radarr, 'Radarr', [
          spriteFright(),
        ], queue: downloading(7)),
        reading(ServiceKey.radarr, 'Radarr 4K', [
          spriteFright(),
        ], queue: ArrQueueSnapshot.empty),
      ],
      window,
      now,
    );

    expect(events, hasLength(2));
    final digital = events.first;
    expect(digital.release, 'on digital');
    expect(digital.sources, ['Radarr', 'Radarr 4K']);
    expect(digital.state.stand, CalendarStand.inFlight);
    expect(digital.statusLine(now), 'Out today\u00A0· downloading 62%');
    expect(digital.state.finishesAt, DateTime(2026, 9, 29, 21, 10));
    expect(digital.lead(), (lead: 'Digital', under: 'all day'));
    expect(
      digital.target,
      const CalendarMediaTarget(MediaKey.movie(508947), connectionId: 'Radarr'),
    );
    expect(
      digital.spoken(now),
      'Today, Sprite Fright, movie out on digital, downloading 62 percent, '
      'ready around 21:10, in Radarr and Radarr 4K',
    );

    // A release still to come reads as one, whatever the file says.
    final disc = events.last;
    expect(disc.day, DateTime(2026, 10, 12));
    expect(disc.statusLine(now), 'Not out yet');
    expect(disc.state.hollow, isTrue);
  });

  test("a movie's fanart is its wide artwork, kept when two Radarrs merge, "
      'and an episode takes its series\'', () {
    Map<String, dynamic> withFanart(Map<String, dynamic> record) => {
      ...record,
      'images': [
        {'coverType': 'poster', 'remoteUrl': 'https://art.test/poster.jpg'},
        {'coverType': 'fanart', 'remoteUrl': 'https://art.test/fanart.jpg'},
      ],
    };
    final events = libraryCalendarEvents(
      [
        reading(ServiceKey.radarr, 'Radarr', [spriteFright()]),
        reading(ServiceKey.radarr, 'Radarr 4K', [withFanart(spriteFright())]),
      ],
      window,
      now,
    );
    expect(events.first.backdrop?.url, 'https://art.test/fanart.jpg');
    expect(events.first.poster?.url, 'https://art.test/poster.jpg');

    final episode = libraryCalendarEvents(
      [
        reading(ServiceKey.sonarr, 'Sonarr', [
          {
            'seriesId': 1,
            'seasonNumber': 3,
            'episodeNumber': 1,
            'airDateUtc': DateTime(2026, 9, 29, 21).toUtc().toIso8601String(),
            'series': withFanart({'title': 'Cosmos Laundromat', 'tvdbId': 9}),
          },
        ]),
      ],
      window,
      now,
    ).single;
    expect(episode.backdrop?.url, 'https://art.test/fanart.jpg');
  });

  test('on the server, a movie says only that; out with nothing on disk it '
      'is missing only over a queue read whole', () {
    List<CalendarEvent> read(ArrQueueSnapshot queue, {bool hasFile = false}) =>
        libraryCalendarEvents(
          [
            reading(ServiceKey.radarr, 'Radarr', [
              spriteFright(hasFile: hasFile),
            ], queue: queue),
          ],
          window,
          now,
        );

    expect(
      read(ArrQueueSnapshot.empty, hasFile: true).first.statusLine(now),
      'On your server',
    );
    expect(
      read(ArrQueueSnapshot.empty).first.statusLine(now),
      'Out today\u00A0· missing',
    );
    expect(
      read(const ArrQueueSnapshot.failed('down')).first.statusLine(now),
      'Out today',
    );
  });

  test('an episode has its time, its mark, and leads nothing on its day', () {
    final events = libraryCalendarEvents(
      [
        reading(ServiceKey.sonarr, 'Sonarr', [
          {
            'id': 3001,
            'seasonNumber': 3,
            'episodeNumber': 1,
            'airDateUtc': DateTime(2026, 10, 2, 21).toUtc().toIso8601String(),
            'hasFile': false,
            'series': {'title': 'Cosmos Laundromat', 'tvdbId': 900},
          },
          {
            'id': 4010,
            'seasonNumber': 4,
            'episodeNumber': 10,
            'finaleType': 'season',
            'airDateUtc': DateTime(2026, 10, 11, 20).toUtc().toIso8601String(),
            'series': {'title': 'The Long Field', 'tvdbId': 901},
          },
        ]),
        reading(ServiceKey.lidarr, 'Lidarr', [
          {
            'id': 4,
            'title': 'Sintel (Anniversary Edition)',
            'foreignAlbumId': 'mb-4',
            'releaseDate': day(3),
            'artistId': 1,
            'artist': {'artistName': 'Jan Morgenstern'},
          },
        ]),
      ],
      window,
      now,
    );

    expect(
      [for (final e in events) e.title],
      [
        // Friday: the album, a date with no time, before the 21:00 episode.
        'Sintel (Anniversary Edition)',
        'Cosmos Laundromat',
        'The Long Field',
      ],
    );
    final album = events[0];
    expect(album.statusLine(now), 'Jan Morgenstern\u00A0· not out yet');
    expect(album.lead(), (lead: 'Album', under: 'all day'));
    expect(
      album.target,
      const CalendarShelfTarget(ServiceKey.lidarr, 'Lidarr', 1),
    );

    final premiere = events[1];
    expect(premiere.lead(), (lead: '21:00', under: null));
    expect(
      premiere.statusLine(now),
      'S3\u00A0E1\u00A0· premiere\u00A0· not aired',
    );
    expect(premiere.target, isA<CalendarMediaTarget>());
    expect(
      premiere.spoken(now),
      'Friday 2 October at 21:00, Cosmos Laundromat season 3 premiere, '
      'not aired yet, in Sonarr',
    );
    expect(
      events[2].statusLine(now),
      'S4\u00A0E10\u00A0· season finale\u00A0· not aired',
    );
  });

  test('an episode that aired with nothing on disk is the backlog', () {
    final events = libraryCalendarEvents(
      [
        reading(ServiceKey.sonarr, 'Sonarr', [
          {
            'id': 2105,
            'seasonNumber': 2,
            'episodeNumber': 5,
            'airDateUtc': DateTime(2026, 9, 29, 1).toUtc().toIso8601String(),
            'hasFile': false,
            'series': {'title': 'Night Shift', 'tvdbId': 902},
          },
        ], queue: ArrQueueSnapshot.empty),
      ],
      window,
      now,
    );
    expect(
      events.single.statusLine(now),
      'S2\u00A0E5\u00A0· aired\u00A0· missing',
    );
    expect(events.single.state.tone, StatusTone.neutral);
    expect(events.single.state.hollow, isFalse);
  });

  test('the queue is asked only when something is out and off the disk', () {
    expect(
      calendarNeedsQueue(ServiceKey.radarr, [spriteFright()], window, now),
      isTrue,
    );
    expect(
      calendarNeedsQueue(
        ServiceKey.radarr,
        [spriteFright(hasFile: true)],
        window,
        now,
      ),
      isFalse,
    );
  });

  test('the agenda: a quiet line for three empty days or more, none for '
      'fewer, and the end of the thirty days', () {
    CalendarEvent at(int offset) => CalendarEvent(
      identity: '$offset',
      kind: CalendarKind.movie,
      day: DateTime(2026, 9, 29 + offset),
      title: 'Title $offset',
      state: const CalendarState.notYet(),
    );
    final agenda = calendarAgenda([at(3), at(5), at(9)], window);

    expect(agenda[0], isA<AgendaGap>());
    expect((agenda[0] as AgendaGap).until, DateTime(2026, 10, 2));
    expect((agenda[1] as AgendaDay).day, DateTime(2026, 10, 2));
    // Two empty days between: skipped without a word.
    expect((agenda[2] as AgendaDay).day, DateTime(2026, 10, 4));
    expect(agenda[3], isA<AgendaGap>());
    expect((agenda[4] as AgendaDay).day, DateTime(2026, 10, 8));
    expect(agenda.last, isA<AgendaEnd>());

    // Something today: no line before it.
    expect(calendarAgenda([at(0)], window).first, isA<AgendaDay>());
  });

  test('days and weeks as the strip names them', () {
    expect(calendarDayName(DateTime(2026, 9, 29), now), 'Today');
    expect(calendarDayName(DateTime(2026, 9, 30), now), 'Tomorrow');
    expect(calendarDayName(DateTime(2026, 10, 1), now), 'Thu');
    expect(calendarDayDate(DateTime(2026, 9, 29), now), 'Tue 29 Sep');
    expect(calendarDayDate(DateTime(2026, 10, 1), now), '1 Oct');
    expect(calendarShortDate(DateTime(2026, 10, 21)), 'Wed 21 Oct');

    final weeks = calendarWeeks(window);
    expect(weeks.first, DateTime(2026, 9, 28));
    // Tue 29 Sep to Thu 29 Oct: five weeks.
    expect(weeks, hasLength(5));
    expect(calendarWeekRange(weeks.first), 'Mon 28 Sep – Sun 4 Oct');
    expect(calendarWeekName(0), 'This week');
    expect(calendarWeekName(1), 'Next week');
  });

  test(
    "a day's dot is its most pressing row, a ring when nothing has come",
    () {
      const later = CalendarState.notYet();
      final flight = CalendarState.inFlight(
        mediaStatusFromQueue(
          availability: MediaAvailability.missing,
          monitored: true,
          queueEntry: const ArrQueueEntry(pipeline: MediaPipeline.downloading),
        ),
      );
      CalendarEvent row(CalendarState state) => CalendarEvent(
        identity: '${state.stand}',
        kind: CalendarKind.movie,
        day: DateTime(2026, 9, 29),
        title: 'x',
        state: state,
      );

      expect(calendarDayDot(const []), isNull);
      expect(calendarDayDot([row(later)]), (
        tone: StatusTone.neutral,
        hollow: true,
      ));
      expect(calendarDayDot([row(later), row(flight)]), (
        tone: StatusTone.info,
        hollow: false,
      ));
    },
  );

  test("a requester's movie is dated for her country, another's named when "
      'hers has none; what she reads is where it stands', () {
    const waiting = MediaStatusInfo(availability: MediaAvailability.missing);
    Map<String, dynamic> movie(String country) => {
      'id': 508947,
      'title': 'Sprite Fright',
      'releases': {
        'results': [
          {
            'iso_3166_1': country,
            'release_dates': [
              {'type': 4, 'release_date': day(0)},
              {'type': 5, 'release_date': day(13)},
              // Long before the window: no row.
              {'type': 3, 'release_date': '2021-10-29T00:00:00.000Z'},
            ],
          },
        ],
      },
    };
    String name(String code) => code == 'IT' ? 'Italy' : 'the US';

    final italy = requesterMovieEvents(
      movie('IT'),
      region: 'it',
      countryName: name,
      window: window,
      now: now,
      status: waiting,
    );
    expect(
      [for (final e in italy) e.note],
      ['On digital in Italy today', 'On disc in Italy'],
    );
    expect(italy.first.statusLine(now), 'Out today');
    expect(italy.last.statusLine(now), 'Not out yet');
    expect(italy.first.sources, isEmpty);

    final elsewhere = requesterMovieEvents(
      movie('US'),
      region: 'IT',
      countryName: name,
      window: window,
      now: now,
      status: waiting,
    );
    expect(elsewhere.first.note, 'On digital in the US today');
  });

  test("a requester's series: the episodes of the seasons she asked for, "
      'on their dates, the first saying when she asked', () {
    const waiting = MediaStatusInfo(availability: MediaAvailability.missing);
    final events = requesterEpisodeEvents(
      {'id': 900, 'name': 'Cosmos Laundromat'},
      [
        {
          'seasonNumber': 3,
          'episodes': [
            {'episodeNumber': 1, 'airDate': '2026-10-02'},
            {'episodeNumber': 2, 'airDate': '2026-10-09'},
            // Past the thirty days.
            {'episodeNumber': 8, 'airDate': '2026-11-20'},
          ],
        },
      ],
      window: window,
      now: now,
      status: waiting,
      asked: const [1, 2, 3],
      askedOn: DateTime(2026, 9, 26),
    );

    expect([for (final e in events) e.code], ['S3\u00A0E1', 'S3\u00A0E2']);
    expect(events.first.airsAt, isNull);
    expect(
      events.first.statusLine(now),
      'S3\u00A0E1\u00A0· premiere\u00A0· not aired',
    );
    // Only the season the calendar dates.
    expect(events.first.note, 'You asked for season 3 on Sat 26 Sep');
    expect(events.last.note, isNull);
  });

  test('a season dropped at once is one row; episodes at other times are '
      'their own', () {
    Map<String, dynamic> drop(int episode, {int hour = 9, String? finale}) => {
      'id': 8000 + episode,
      'seasonNumber': 1,
      'episodeNumber': episode,
      'finaleType': ?finale,
      'airDateUtc': DateTime(2026, 9, 30, hour).toUtc().toIso8601String(),
      'series': {'title': 'Carrie', 'tvdbId': 455755},
    };
    final events = libraryCalendarEvents(
      [
        reading(ServiceKey.sonarr, 'Sonarr', [
          for (var e = 1; e <= 7; e++) drop(e),
          drop(8, finale: 'series'),
          // Same day, another hour: its own row.
          drop(9, hour: 21),
        ]),
      ],
      window,
      now,
    );

    expect(events, hasLength(2));
    expect(events.first.code, 'S1\u00A0E1–E8');
    expect(
      events.first.statusLine(now),
      'S1\u00A0E1–E8\u00A0· whole season\u00A0· not aired',
    );
    expect(
      events.first.spoken(now),
      'Tomorrow at 09:00, Carrie season 1 episodes 1 to 8, whole season, '
      'not aired yet, in Sonarr',
    );
    expect(events.last.code, 'S1\u00A0E9');
  });

  test(
    'a release date is the day it spells, whatever the hour or the '
    "device's time zone; a record dated outside the thirty days is no row",
    () {
      final events = libraryCalendarEvents(
        [
          reading(ServiceKey.radarr, 'Radarr', [
            {'id': 1, 'tmdbId': 1, 'title': 'A', 'digitalRelease': day(13)},
            {
              'id': 2,
              'tmdbId': 2,
              'title': 'B',
              'digitalRelease': '2026-10-12T23:30:00Z',
            },
            // A server reading the window in its own time zone can send one
            // a day past ours: the calendar says thirty days, and keeps to it.
            {
              'id': 3,
              'tmdbId': 3,
              'title': 'Edge',
              'physicalRelease': '2026-10-30T00:00:00Z',
            },
            {'id': 4, 'tmdbId': 4, 'title': 'Undated'},
          ]),
        ],
        window,
        now,
      );

      expect(
        [for (final e in events) (e.title, e.day)],
        [('A', DateTime(2026, 10, 12)), ('B', DateTime(2026, 10, 12))],
      );
    },
  );

  group('the month\'s grid and the day beside it', () {
    CalendarEvent episode(
      int dayOffset,
      int number, {
      CalendarMark? mark,
      String title = 'Cosmos Laundromat',
    }) => CalendarEvent(
      identity: '$title-3-$number',
      kind: CalendarKind.episode,
      day: DateTime(2026, 9, 29 + dayOffset),
      airsAt: DateTime(2026, 9, 29 + dayOffset, 21),
      title: title,
      season: 3,
      episode: number,
      mark: mark,
      sources: const ['Sonarr'],
      state: const CalendarState.notYet(),
    );
    final disc = CalendarEvent(
      identity: 'sf-disc',
      kind: CalendarKind.movie,
      day: DateTime(2026, 10, 12),
      title: 'Sprite Fright',
      release: Lexicon.onDisc,
      sources: const ['Radarr', 'Radarr 4K'],
      state: const CalendarState.notYet(),
    );
    final album = CalendarEvent(
      identity: 'album',
      kind: CalendarKind.album,
      day: DateTime(2026, 10, 2),
      title: 'Sintel (Anniversary Edition)',
      byline: 'Jan Morgenstern',
      sources: const ['Lidarr'],
      state: const CalendarState.notYet(),
    );

    test('a day\'s first line: the time and code, the kind of release', () {
      expect(calendarGridLead(episode(3, 1)), '21:00 S3\u00A0E1');
      expect(calendarGridLead(disc), 'Disc');
      expect(calendarGridLead(album), 'Album');
    });

    test('the tip under the pointer names the release, the standing and '
        'the connections', () {
      expect(
        calendarEventTip(disc, now),
        'Sprite Fright\u00A0· on disc\u00A0· not out yet\u00A0· Radarr, Radarr 4K',
      );
      expect(
        calendarEventTip(album, now),
        'Sintel (Anniversary Edition)\u00A0· Jan Morgenstern\u00A0· not out yet\u00A0· '
        'Lidarr',
      );
    });

    test('the day in a sentence: three named, the rest counted', () {
      expect(calendarDaySummary(const []), 'Nothing on this day.');
      expect(
        calendarDaySummary([album, episode(3, 1, mark: CalendarMark.premiere)]),
        '2 things: an album by Jan Morgenstern and the premiere of Cosmos '
        'Laundromat season 3.',
      );
      expect(
        calendarDaySummary([
          disc,
          album,
          episode(3, 4, title: 'Night Shift'),
          episode(3, 5, title: 'Night Shift'),
        ]),
        '4 things: Sprite Fright on disc, an album by Jan Morgenstern, '
        'Night Shift S3\u00A0E4 and 1 more.',
      );
    });

    test('the rest of a season, after the episode and only its season', () {
      final premiere = episode(3, 1, mark: CalendarMark.premiere);
      final events = [
        premiere,
        episode(10, 2),
        episode(17, 3),
        episode(10, 9, title: 'Night Shift'),
        disc,
      ];
      expect(
        [
          for (final event in calendarLaterInSeason(premiere, events))
            event.episode,
        ],
        [2, 3],
      );
      expect(calendarLaterInSeason(disc, events), isEmpty);
    });
  });
}
