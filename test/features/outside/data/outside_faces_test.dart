import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/outside/data/outside_faces.dart';
import 'package:cupola/features/outside/domain/outside_snapshot.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The three widgets' frames, in the Home's words.
void main() {
  // Friday 16 October 2026, 14:02.
  final takenAt = DateTime(2026, 10, 16, 14, 2);

  String? picture(ImageSource? source) =>
      source == null ? null : 'pic-${source.url.hashCode}.jpg';

  OutsideFace faceAt(List<OutsideFrame> frames, DateTime at) =>
      frames.lastWhere((frame) => !frame.from.isAfter(at)).face;

  group('Coming up', () {
    CalendarEvent episode(String title, DateTime airs, {int episode = 4}) =>
        CalendarEvent(
          identity: title,
          kind: CalendarKind.episode,
          day: DateTime(airs.year, airs.month, airs.day),
          airsAt: airs,
          title: title,
          season: 1,
          episode: episode,
          state: const CalendarState.notYet(),
          poster: (url: 'https://art/$title.jpg', headers: null),
          target: const CalendarMediaTarget(
            MediaKey.tv(7),
            connectionId: 'sonarr',
          ),
        );

    final tonight = episode('Sintel', DateTime(2026, 10, 16, 21));
    final tomorrow = episode(
      'Sprite Fright',
      DateTime(2026, 10, 17, 20),
      episode: 3,
    );
    final frames = comingUpFrames(
      [tonight, tomorrow],
      takenAt: takenAt,
      pictures: picture,
    );

    test('leads with the next, its day and time, as the Home says them', () {
      final face = frames.first.face;
      expect(frames.first.from, takenAt);
      expect(face.title, 'Coming up');
      expect(face.lead?.eyebrow, 'Today\u00A0· 21:00');
      expect(face.lead?.title, 'Sintel');
      expect(face.lead?.words, 'S1\u00A0E4\u00A0· not aired');
      expect(face.lead?.poster, isNotNull);
      expect(face.lead?.route, startsWith('/home/'));
      expect(face.items.single.eyebrow, 'Tomorrow');
      // A row is narrow: its day, and its code until its standing is news.
      expect(face.items.single.words, 'S1\u00A0E3');
      expect(face.age, 'As of 14:02');
      expect(face.aged, isFalse);
    });

    test('once its time has come, the next one leads', () {
      final face = faceAt(frames, DateTime(2026, 10, 16, 21, 5));
      expect(face.lead?.title, 'Sprite Fright');
      expect(face.lead?.eyebrow, 'Tomorrow\u00A0· 20:00');
      expect(face.aged, isTrue);
    });

    test('past midnight, the day is said against the new day', () {
      final face = faceAt(frames, DateTime(2026, 10, 17, 0, 1));
      expect(face.lead?.eyebrow, 'Today\u00A0· 20:00');
      expect(face.age, 'As of yesterday 14:02');
    });

    test('a row on its way says only how far it got', () {
      final morning = CalendarEvent(
        identity: 'Cupertino',
        kind: CalendarKind.episode,
        day: DateTime(2026, 10, 16),
        airsAt: DateTime(2026, 10, 16, 4),
        title: 'Cupertino',
        season: 1,
        episode: 2,
        state: CalendarState.inFlight(
          mediaStatusFromQueue(
            availability: MediaAvailability.missing,
            monitored: true,
            queueEntry: ArrQueueEntry(
              pipeline: MediaPipeline.downloading,
              progress: 0.4,
            ),
          ),
        ),
      );
      final row = comingUpFrames(
        [morning, tonight],
        takenAt: takenAt,
        pictures: picture,
      ).first.face.items.single;
      expect(row.words, '40%');
      expect(row.tone, OutsideTone.blue);
    });

    test('what aired this morning stays a row, and the next one leads', () {
      final morning = CalendarEvent(
        identity: 'Cupertino',
        kind: CalendarKind.episode,
        day: DateTime(2026, 10, 16),
        airsAt: DateTime(2026, 10, 16, 4),
        title: 'Cupertino',
        season: 1,
        episode: 2,
        state: const CalendarState.notYet(),
      );
      final face = comingUpFrames(
        [morning, tonight],
        takenAt: takenAt,
        pictures: picture,
      ).first.face;
      expect(face.lead?.title, 'Sintel');
      expect(face.items.single.title, 'Cupertino');
    });

    test(
      'a drawing with nothing left says nothing, never that nothing comes',
      () {
        final frames = comingUpFrames(
          [tonight],
          takenAt: takenAt,
          pictures: picture,
        );
        final after = faceAt(frames, DateTime(2026, 10, 17, 0, 1));
        expect(after.lead, isNull);
        expect(after.calm, isNull);
        expect(after.age, 'As of yesterday 14:02');
      },
    );

    test('nothing in the window is said calmly', () {
      final calm = comingUpFrames(
        const [],
        takenAt: takenAt,
        pictures: picture,
      );
      expect(calm.first.face.lead, isNull);
      expect(calm.first.face.calm, 'Nothing comes out or airs by Monday');
    });
  });

  group('Downloads', () {
    ServiceQueueItem item(
      String title, {
      double progress = 0.5,
      int? eta = 360,
      InFlightFault? fault,
    }) => ServiceQueueItem(
      service: ServiceKey.radarr,
      id: title,
      title: title,
      progress: progress,
      clientLabel: 'qBittorrent',
      etaSeconds: eta,
      fault: fault,
      clientService: ServiceKey.qbittorrent,
      instanceId: 'radarr',
      downloadId: 'HASH-$title',
    );

    ServicesInFlight inFlight({
      List<ServiceQueueItem> moving = const [],
      List<ServiceQueueItem> faults = const [],
      SourceCoverage? coverage,
    }) => (
      preview: moving,
      activeCount: moving.length,
      movingCount: moving.length,
      queued: const [],
      faults: faults,
      held: 0,
      rateBytesPerSecond: 2400000,
      clients: 1,
      coverage:
          coverage ??
          SourceCoverage.merge([
            SourceCoverage.answeredBy(ServiceKey.radarr),
            SourceCoverage.answeredBy(ServiceKey.qbittorrent),
          ]),
    );

    final evening = inFlight(
      moving: [item('Tears of Steel', progress: 0.68)],
      faults: [item('Charge', progress: 0.12, fault: InFlightFault.stalled)],
    );
    final frames = downloadsFrames(
      evening,
      takenAt: takenAt,
      clientSetUp: true,
      clientSilent: false,
    )!;

    test('live, it says what moves, how fast, and the stuck one in amber', () {
      final face = frames.first.face;
      expect(face.subtitle, startsWith('1 moving\u00A0· 1 stuck\u00A0· '));
      expect(face.figure, '1');
      expect(face.figureWords, 'moving');
      expect(face.lead?.title, 'Charge');
      expect(face.lead?.words, 'Stuck at 12%');
      expect(face.lead?.tone, OutsideTone.amber);
      expect(face.items.map((row) => (row.title, row.tone)), [
        ('Tears of Steel', OutsideTone.blue),
        ('Charge', OutsideTone.amber),
      ]);
      expect(face.items.first.words, movingValue(percent: 68, etaSeconds: 360));
      expect(face.items.first.route, startsWith('/activity/download'));
    });

    test('once its figures stop being true, it is the Home\'s drawing', () {
      final face = faceAt(frames, takenAt.add(outsideRunningFor));
      expect(face.subtitle, '1 moving');
      expect(face.lead, isNull);
      expect(face.items.map((row) => (row.words, row.tone)), [
        ('68%', OutsideTone.neutral),
        ('12%', OutsideTone.neutral),
      ]);
    });

    test('with nothing moving, the small one leads with no figure', () {
      final stalled = downloadsFrames(
        inFlight(
          faults: [item('Charge', progress: 0, fault: InFlightFault.stalled)],
        ),
        takenAt: takenAt,
        clientSetUp: true,
        clientSilent: false,
      )!;
      expect(stalled.first.face.figure, isNull);
      expect(stalled.first.face.lead?.words, 'Stuck at 0%');
    });

    test('nothing downloading is said only of the read it was true of', () {
      final quiet = downloadsFrames(
        inFlight(),
        takenAt: takenAt,
        clientSetUp: true,
        clientSilent: false,
      )!;
      expect(quiet.first.face.calm, 'Nothing is downloading');
      expect(faceAt(quiet, takenAt.add(outsideRunningFor)).calm, isNull);
    });

    test('a read no queue answered makes no frame', () {
      expect(
        downloadsFrames(
          inFlight(
            coverage: SourceCoverage.merge([
              SourceCoverage.failure(ServiceKey.radarr, 'timeout'),
            ]),
          ),
          takenAt: takenAt,
          clientSetUp: true,
          clientSilent: true,
        ),
        isNull,
      );
    });
  });

  group('Your requests', () {
    SeerrRequest request(
      int id,
      String title, {
      int status = 2,
      int? media,
      Duration? added,
    }) => SeerrRequest.fromJson({
      'id': id,
      'status': status,
      'type': 'movie',
      'createdAt': takenAt
          .subtract(const Duration(days: 2))
          .toUtc()
          .toIso8601String(),
      'media': {
        'id': id,
        'tmdbId': 100 + id,
        'mediaType': 'movie',
        'status': ?media,
        'title': title,
        'posterPath': '/p$id.jpg',
        if (added != null)
          'mediaAddedAt': takenAt.subtract(added).toUtc().toIso8601String(),
      },
    }, numbering: SeerrNumbering.seerr);

    test('the newest arrival leads, in green, with what is on its way', () {
      final frames = requestsFrames(
        [
          request(1, 'Spring', media: 5, added: const Duration(hours: 1)),
          request(2, 'Big Buck Bunny', status: 1),
        ],
        takenAt: takenAt,
        pictures: picture,
      );
      final face = frames.first.face;
      expect(face.title, 'Your requests');
      expect(face.lead?.eyebrow, 'Ready to watch');
      expect(face.lead?.tone, OutsideTone.green);
      expect(face.lead?.title, 'Spring');
      expect(face.lead?.poster, isNotNull);
      expect(face.lead?.route, '/home/media/movie/101');
      expect(face.calm, isNull);
    });

    test('nothing asked for says so', () {
      final frames = requestsFrames(
        const [],
        takenAt: takenAt,
        pictures: picture,
      );
      expect(frames.first.face.calm, 'Nothing on its way');
    });
  });
}
