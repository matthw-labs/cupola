import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/featured.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

final _now = DateTime(2026, 9, 29, 20, 41);
const _art = (url: 'https://art.test/wide.jpg', headers: null);
const _none = (url: '', headers: null);

ResumeRow _row(StreamItem item) => (
  service: ServiceKey.jellyfin,
  instanceId: 'jellyfin',
  connectionName: null,
  item: item,
);

const _episode = StreamItem(
  id: 'e1',
  title: 'The Second Cycle',
  subtitle: 'Cosmos Laundromat\u00A0· S2\u00A0E3',
  kind: StreamItemKind.episode,
  posterPath: null,
  year: null,
  runtimeMs: 1500000,
  isPlayed: false,
  resumeOffsetMs: 1200000,
  unplayedChildCount: null,
  seasonNumber: 2,
  episodeNumber: 3,
);

const _movie = StreamItem(
  id: 'm1',
  title: 'Sintel',
  subtitle: '2010',
  kind: StreamItemKind.movie,
  posterPath: null,
  year: 2010,
  runtimeMs: 900000,
  isPlayed: false,
  resumeOffsetMs: 600000,
  unplayedChildCount: null,
);

ArrHistoryEntry _arrival(
  String title, {
  ServiceKey service = ServiceKey.radarr,
  Duration ago = const Duration(hours: 2),
  String? connectionName,
  String backdrop = 'https://art.test/fanart.jpg',
}) => ArrHistoryEntry(
  service: service,
  id: title.hashCode,
  mediaId: title.hashCode,
  title: title,
  unitId: null,
  detail: null,
  posterUrl: '',
  outcome: ArrImportOutcome.imported,
  at: _now.subtract(ago),
  reason: null,
  instanceId: 'radarr',
  connectionName: connectionName,
  tmdbId: title.hashCode.abs(),
  backdropUrl: backdrop,
);

CalendarState _downloading() => CalendarState.inFlight(
  mediaStatusFromQueue(
    availability: MediaAvailability.missing,
    monitored: true,
    queueEntry: const ArrQueueEntry(
      pipeline: MediaPipeline.downloading,
      progress: 0.62,
    ),
  ),
);

CalendarEvent _today(
  String title, {
  CalendarKind kind = CalendarKind.movie,
  String? release = Lexicon.onDigital,
  CalendarState state = const CalendarState.out(missingKnown: false),
  DateTime? airsAt,
  int day = 29,
}) => CalendarEvent(
  identity: title,
  kind: kind,
  day: DateTime(2026, 9, day),
  title: title,
  release: kind == CalendarKind.movie ? release : null,
  airsAt: airsAt,
  season: kind == CalendarKind.episode ? 3 : null,
  episode: kind == CalendarKind.episode ? 1 : null,
  mark: kind == CalendarKind.episode ? CalendarMark.premiere : null,
  state: state,
);

/// The words of the Home's Featured, and which titles it leads with.
void main() {
  group('the slides', () {
    test('one from each source, in order: in progress, arrived, today', () {
      final slides = featuredSlidesOf(
        resume: [FeaturedResume(_row(_episode), art: _art)],
        arrivals: [FeaturedArrival(_arrival('Spring'), art: _art)],
        today: [FeaturedToday(_today('Sprite Fright'), art: _art)],
      );
      expect(slides.map((slide) => slide.title), [
        'Cosmos Laundromat',
        'Spring',
        'Sprite Fright',
      ]);
    });

    test('a candidate without artwork is passed over for the next', () {
      final slides = featuredSlidesOf(
        resume: [
          FeaturedResume(_row(_episode), art: _none),
          FeaturedResume(_row(_movie), art: _art),
        ],
        arrivals: const [],
        today: const [],
      );
      expect(slides.map((slide) => slide.title), ['Sintel']);
    });

    test('a title is never featured twice: the series in progress is not '
        'also the arrival', () {
      final slides = featuredSlidesOf(
        resume: [FeaturedResume(_row(_episode), art: _art)],
        arrivals: [
          FeaturedArrival(_arrival('Cosmos Laundromat'), art: _art),
          FeaturedArrival(_arrival('Spring'), art: _art),
        ],
        today: [FeaturedToday(_today('Spring'), art: _art)],
      );
      expect(slides.map((slide) => slide.title), [
        'Cosmos Laundromat',
        'Spring',
      ]);
    });

    test('nothing in progress, new or out today: no slide', () {
      expect(
        featuredSlidesOf(resume: const [], arrivals: const [], today: const []),
        isEmpty,
      );
    });

    test('an album arrives in Arrived, not in Featured', () {
      final entries = [
        _arrival('Sintel OST', service: ServiceKey.lidarr),
        _arrival('Spring', ago: const Duration(hours: 5)),
      ];
      expect(
        featuredArrivalsOf(
          entries,
          since: _now.subtract(const Duration(days: 7)),
        ).map((entry) => entry.title),
        ['Spring'],
      );
    });

    test('today is today, and only movies and episodes', () {
      final events = [
        _today('Yesterday', day: 28),
        _today('Sprite Fright'),
        _today('Charge', kind: CalendarKind.album),
        _today('Cosmos Laundromat', kind: CalendarKind.episode),
        _today('Tomorrow', day: 30),
      ];
      expect(featuredTodayOf(events, _now).map((event) => event.title), [
        'Sprite Fright',
        'Cosmos Laundromat',
      ]);
    });
  });

  group('the line under the title', () {
    test('in progress: what it is and how long is left', () {
      expect(
        FeaturedResume(_row(_episode), art: _art).line(_now),
        'Continue watching\u00A0· S2\u00A0E3\u00A0· 5\u00A0min left',
      );
      expect(
        FeaturedResume(_row(_movie), art: _art).line(_now),
        'Continue watching\u00A0· 5\u00A0min left',
      );
    });

    test('arrived: when, and the connection while the service has two', () {
      expect(
        FeaturedArrival(_arrival('Spring'), art: _art).line(_now),
        'New on your server\u00A0· 2\u00A0h ago',
      );
      expect(
        FeaturedArrival(
          _arrival('Spring', connectionName: '4K'),
          art: _art,
        ).line(_now),
        'New on your server\u00A0· 2\u00A0h ago\u00A0· Radarr 4K',
      );
    });

    test('a movie out today: how, and where it stands', () {
      expect(
        FeaturedToday(
          _today('Sprite Fright', state: _downloading()),
          art: _art,
        ).line(_now),
        'Out on digital today\u00A0· downloading 62%',
      );
      expect(
        FeaturedToday(
          _today('Sprite Fright', release: Lexicon.inCinemas),
          art: _art,
        ).line(_now),
        'In cinemas today',
      );
      expect(
        FeaturedToday(
          _today(
            'Sprite Fright',
            state: const CalendarState.out(missingKnown: true),
          ),
          art: _art,
        ).line(_now),
        'Out on digital today\u00A0· missing',
      );
    });

    test('an episode today: when it airs, then what came of it', () {
      expect(
        FeaturedToday(
          _today(
            'Cosmos Laundromat',
            kind: CalendarKind.episode,
            state: const CalendarState.notYet(),
            airsAt: DateTime(2026, 9, 29, 21),
          ),
          art: _art,
        ).line(_now),
        'S3\u00A0E1\u00A0· premiere\u00A0· airs today at 21:00',
      );
      expect(
        FeaturedToday(
          _today(
            'Cosmos Laundromat',
            kind: CalendarKind.episode,
            state: const CalendarState.onServer(),
            airsAt: DateTime(2026, 9, 29, 18),
          ),
          art: _art,
        ).line(_now),
        'S3\u00A0E1\u00A0· premiere\u00A0· on your server',
      );
    });

    test('Queue only while the movie is downloading', () {
      expect(
        FeaturedToday(
          _today('Sprite Fright', state: _downloading()),
          art: _art,
        ).downloading,
        isTrue,
      );
      expect(
        FeaturedToday(_today('Sprite Fright'), art: _art).downloading,
        isFalse,
      );
    });
  });
}
