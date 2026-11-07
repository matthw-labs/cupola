/// The one action that leads a Media page: decided from its rows, for both
/// audiences, never flipping while a source that could outrank it is still
/// out.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_lead.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../test_helpers/model_builders.dart';
import '../../test_helpers/profiles/profiles.dart';

final _at = DateTime(2026, 10, 3, 20, 41);

ServiceInstance _connection(String id, ServiceKey service) => ServiceInstance(
  id: id,
  service: service,
  url: 'https://$id',
  credential: 'k',
);

final _jellyfin = _connection('jellyfin', ServiceKey.jellyfin);
final _radarr = _connection('radarr', ServiceKey.radarr);
final _radarr4k = _connection('radarr-4k', ServiceKey.radarr);
final _seerr = _connection('seerr', ServiceKey.seerr);

MediaReading<T> _answered<T>(T value) =>
    MediaReadingAnswered<T>(MediaAnswer<T>(value, _at));

MediaReading<T> _silent<T>() =>
    MediaReadingFailed<T>(ServiceFailureReason.unreachable);

StreamItem _item({int? resumeOffsetMs}) => StreamItem(
  id: 'jf-1',
  title: 'Tears of Steel',
  subtitle: '2012',
  kind: StreamItemKind.movie,
  posterPath: null,
  year: 2012,
  runtimeMs: 720000,
  isPlayed: false,
  resumeOffsetMs: resumeOffsetMs,
  unplayedChildCount: null,
);

MediaRow _stream(MediaReading<MediaStreamCopy> reading) =>
    MediaConnectionRow<MediaStreamCopy>(_jellyfin, reading);

MediaRow _copy(
  ServiceInstance connection,
  MediaReading<MediaRadarrCopy> reading,
) => MediaConnectionRow<MediaRadarrCopy>(connection, reading);

MediaRadarrCopy _onDisk({bool hasFile = true}) => MediaRadarrCopy(
  movie: buildMovie(id: 5, title: 'Tears of Steel', hasFile: hasFile),
  queue: ArrQueueSnapshot.empty,
);

const _untracked = MediaRadarrCopy(movie: null, queue: ArrQueueSnapshot.empty);

MediaRow _seerrRow({bool trailer = false}) =>
    MediaConnectionRow<MediaSeerrRecord>(
      _seerr,
      _answered(
        MediaSeerrRecord(
          details: {
            'relatedVideos': [
              if (trailer) {'site': 'YouTube', 'key': 'abc', 'type': 'Trailer'},
            ],
          },
        ),
      ),
    );

void main() {
  group('the operator', () {
    test('a verified copy on Jellyfin plays', () {
      final lead = resolveMediaLead([
        _stream(_answered(MediaStreamCopy.found(_item()))),
        _copy(_radarr, _answered(_onDisk())),
        _seerrRow(trailer: true),
      ], audience: Audience.operator);

      expect(lead, isA<MediaLeadPlay>());
      expect((lead as MediaLeadPlay).resume, isFalse);
    });

    test('partway in, it resumes', () {
      final lead = resolveMediaLead([
        _stream(
          _answered(MediaStreamCopy.found(_item(resumeOffsetMs: 300000))),
        ),
      ], audience: Audience.operator);

      expect((lead as MediaLeadPlay).resume, isTrue);
    });

    test('a title on three servers plays on the one the page was opened '
        'from, and a playback partway in still wins', () {
      final plex = _connection('plex', ServiceKey.plex);
      final emby = _connection('emby', ServiceKey.emby);
      MediaRow on(ServiceInstance server, {int? resumeOffsetMs}) =>
          MediaConnectionRow<MediaStreamCopy>(
            server,
            _answered(
              MediaStreamCopy.found(_item(resumeOffsetMs: resumeOffsetMs)),
            ),
          );
      MediaLeadPlay lead(List<MediaRow> rows, {String? focus}) =>
          resolveMediaLead(rows, audience: Audience.operator, focus: focus)
              as MediaLeadPlay;

      final fresh = [on(plex), on(emby), on(_jellyfin)];
      expect(lead(fresh, focus: 'emby').server.id, 'emby');
      expect(lead(fresh).server.id, 'plex', reason: 'no focus: the first');
      expect(lead(fresh, focus: 'radarr').server.id, 'plex');

      final partway = [on(plex), on(emby), on(_jellyfin, resumeOffsetMs: 9000)];
      expect(lead(partway, focus: 'emby').server.id, 'jellyfin');
      expect(lead(partway, focus: 'emby').resume, isTrue);

      final bothPartway = [
        on(plex, resumeOffsetMs: 9000),
        on(emby, resumeOffsetMs: 9000),
      ];
      expect(lead(bothPartway, focus: 'emby').server.id, 'emby');
    });

    test('while Jellyfin has not answered, nothing leads yet: no Trailer '
        'that turns into Play', () {
      final lead = resolveMediaLead([
        _stream(const MediaReadingWaiting()),
        _copy(_radarr, _answered(_onDisk())),
        _seerrRow(trailer: true),
      ], audience: Audience.operator);

      expect(lead, isA<MediaLeadWaiting>());
    });

    test('Jellyfin silent and every copy on disk: the trailer leads '
        '(rule 4)', () {
      final lead = resolveMediaLead([
        _stream(_silent()),
        _copy(_radarr, _answered(_onDisk())),
        _seerrRow(trailer: true),
      ], audience: Audience.operator);

      expect(lead, isA<MediaLeadTrailer>());
    });

    test('no trailer either: nothing leads', () {
      final lead = resolveMediaLead([
        _copy(_radarr, _answered(_onDisk())),
        _seerrRow(),
      ], audience: Audience.operator);

      expect(lead, isA<MediaLeadNone>());
    });

    test('no Radarr holds it, and every Radarr answered: Add', () {
      final lead = resolveMediaLead([
        _copy(_radarr, _answered(_untracked)),
        _copy(_radarr4k, _answered(_untracked)),
      ], audience: Audience.operator);

      expect((lead as MediaLeadAdd).arr, ServiceKey.radarr);
    });

    test('a silent Radarr is never one that holds nothing: no Add', () {
      final lead = resolveMediaLead([
        _copy(_radarr, _answered(_untracked)),
        _copy(_radarr4k, _silent()),
      ], audience: Audience.operator);

      expect(lead, isA<MediaLeadNone>());
    });

    test('a silent Radarr, and a Seerr that answered and may request: the '
        'request leads, with no Add beside it', () {
      final lead = resolveMediaLead(
        [_copy(_radarr, _silent()), _seerrRow()],
        audience: Audience.operator,
        addsVia: OperatorAddsVia.arr,
        seerrMayRequest: (_) => true,
      );

      expect(lead, isA<MediaLeadRequest>());
      expect((lead as MediaLeadRequest).alternative, isNull);
    });

    test(
      'a silent Radarr, and a Seerr that may not request: nothing leads',
      () {
        final lead = resolveMediaLead(
          [_copy(_radarr, _silent()), _seerrRow()],
          audience: Audience.operator,
          seerrMayRequest: (_) => false,
        );

        expect(lead, isA<MediaLeadNone>());
      },
    );

    test('no Radarr set up, Seerr is: the operator requests through it', () {
      final lead = resolveMediaLead([
        _seerrRow(),
        const MediaNotSetUpRow(ServiceKey.radarr),
      ], audience: Audience.operator);

      expect((lead as MediaLeadRequest).seerr.id, _seerr.id);
    });

    test('a copy not on disk leads with its own action, the focused one '
        'first', () {
      final rows = [
        _copy(_radarr, _answered(_onDisk(hasFile: false))),
        _copy(_radarr4k, _answered(_onDisk(hasFile: false))),
      ];

      final first = resolveMediaLead(rows, audience: Audience.operator);
      final focused = resolveMediaLead(
        rows,
        audience: Audience.operator,
        focus: _radarr4k.id,
      );

      expect((first as MediaLeadCopy).connection.id, _radarr.id);
      expect(first.status.availability, MediaAvailability.missing);
      expect((focused as MediaLeadCopy).connection.id, _radarr4k.id);
    });
  });

  group('the operator adds a title nobody holds', () {
    // A Radarr that holds nothing, answered; a Seerr that answered; and the
    // preference, which defaults to Seerr.
    MediaRow seerrAnswered() => _seerrRow();
    MediaRow seerrWaiting() => MediaConnectionRow<MediaSeerrRecord>(
      _seerr,
      const MediaReadingWaiting(),
    );
    MediaRow seerrFailed() =>
        MediaConnectionRow<MediaSeerrRecord>(_seerr, _silent());
    List<MediaRow> rows(MediaRow seerr) => [
      _copy(_radarr, _answered(_untracked)),
      seerr,
    ];

    test(
      'through Seerr by default: Request leads, and Radarr is the other way',
      () {
        final lead = resolveMediaLead(
          rows(seerrAnswered()),
          audience: Audience.operator,
          seerrMayRequest: (_) => true,
        );

        expect(lead, isA<MediaLeadRequest>());
        expect((lead as MediaLeadRequest).seerr.id, _seerr.id);
        expect(lead.alternative, ServiceKey.radarr);
      },
    );

    test('straight to the arr: Add leads, and Seerr is the other way', () {
      final lead = resolveMediaLead(
        rows(seerrAnswered()),
        audience: Audience.operator,
        addsVia: OperatorAddsVia.arr,
        seerrMayRequest: (_) => true,
      );

      expect(lead, isA<MediaLeadAdd>());
      expect((lead as MediaLeadAdd).arr, ServiceKey.radarr);
      expect(lead.alternative?.id, _seerr.id);
    });

    test('through Seerr, but Seerr may not request this kind: Add leads, with '
        'no other way offered', () {
      final lead = resolveMediaLead(
        rows(seerrAnswered()),
        audience: Audience.operator,
        seerrMayRequest: (_) => false,
      );

      expect(lead, isA<MediaLeadAdd>());
      expect((lead as MediaLeadAdd).alternative, isNull);
    });

    test('straight to the arr, and Seerr may not request: no request is '
        'offered either', () {
      final lead = resolveMediaLead(
        rows(seerrAnswered()),
        audience: Audience.operator,
        addsVia: OperatorAddsVia.arr,
        seerrMayRequest: (_) => false,
      );

      expect((lead as MediaLeadAdd).alternative, isNull);
    });

    test('through Seerr, and Seerr is still deciding whether it may: the lead '
        'holds, and does not flip to Add', () {
      final lead = resolveMediaLead(
        rows(seerrAnswered()),
        audience: Audience.operator,
        seerrMayRequest: (_) => null,
      );

      expect(lead, isA<MediaLeadWaiting>());
    });

    test('through Seerr, and Seerr has not answered: the lead waits', () {
      final lead = resolveMediaLead(
        rows(seerrWaiting()),
        audience: Audience.operator,
      );

      expect(lead, isA<MediaLeadWaiting>());
    });

    test('straight to the arr, and Seerr has not answered: Add leads at once, '
        'with no other way yet', () {
      final lead = resolveMediaLead(
        rows(seerrWaiting()),
        audience: Audience.operator,
        addsVia: OperatorAddsVia.arr,
      );

      expect(lead, isA<MediaLeadAdd>());
      expect((lead as MediaLeadAdd).alternative, isNull);
    });

    test(
      'through Seerr, and Seerr failed: Add leads, with no request offered',
      () {
        final lead = resolveMediaLead(
          rows(seerrFailed()),
          audience: Audience.operator,
        );

        expect(lead, isA<MediaLeadAdd>());
        expect((lead as MediaLeadAdd).alternative, isNull);
      },
    );

    test('no Seerr set up: Add leads, with no other way', () {
      final lead = resolveMediaLead([
        _copy(_radarr, _answered(_untracked)),
      ], audience: Audience.operator);

      expect(lead, isA<MediaLeadAdd>());
      expect((lead as MediaLeadAdd).alternative, isNull);
    });

    test(
      'the requester is unchanged by the preference: Request, no other way',
      () {
        final lead = resolveMediaLead(
          [seerrAnswered()],
          audience: Audience.requester,
          addsVia: OperatorAddsVia.arr,
        );

        expect(lead, isA<MediaLeadRequest>());
        expect((lead as MediaLeadRequest).alternative, isNull);
      },
    );
  });

  group('the requester', () {
    test('a verified copy plays', () {
      final lead = resolveMediaLead([
        _stream(_answered(MediaStreamCopy.found(_item()))),
        _seerrRow(),
      ], audience: Audience.requester);

      expect(lead, isA<MediaLeadPlay>());
    });

    test('anything else is asked for through Seerr', () {
      final lead = resolveMediaLead([
        _stream(_answered(const MediaStreamCopy.notInLibrary())),
        _seerrRow(trailer: true),
      ], audience: Audience.requester);

      expect((lead as MediaLeadRequest).seerr.id, _seerr.id);
    });
  });

  group('against the households', () {
    Future<MediaLead> leadOf(ConfigProfile profile, WorldTitle title) async {
      final harness = await ProfileHarness.start(profile);
      final container = harness.container();
      final rows = mediaRowsProvider(MediaKey.movie(title.tmdbId));
      container.listen(rows, (_, _) {});
      for (var turn = 0; turn < 200; turn++) {
        final lead = resolveMediaLead(
          container.read(rows),
          audience: Audience.operator,
        );
        if (lead is! MediaLeadWaiting) return lead;
        await pumpEventQueue();
      }
      fail('the lead of ${title.title} never settled under ${profile.id}');
    }

    test('P1, Tears of Steel: Play on Jellyfin', () async {
      final lead = await leadOf(Profiles.p1, WorldTitles.tearsOfSteel);

      expect((lead as MediaLeadPlay).server.id, WorldIds.jellyfin);
    });

    test('P1, Charge, which no Radarr holds: through Seerr by default, so '
        'Request leads, with Radarr the other way', () async {
      final lead = await leadOf(Profiles.p1, WorldTitles.charge);

      expect((lead as MediaLeadRequest).seerr.id, WorldIds.seerr);
      expect(lead.alternative, ServiceKey.radarr);
    });

    test('P1, Charge, straight to the arr: Add to Radarr, with Seerr the '
        'other way', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final container = harness.container();
      final rows = mediaRowsProvider(MediaKey.movie(WorldTitles.charge.tmdbId));
      container.listen(rows, (_, _) {});
      // Add leads as soon as Radarr has answered; Seerr's way comes once it has.
      MediaLead lead = const MediaLeadWaiting();
      for (var turn = 0; turn < 200; turn++) {
        lead = resolveMediaLead(
          container.read(rows),
          audience: Audience.operator,
          addsVia: OperatorAddsVia.arr,
          seerrMayRequest: (_) => true,
        );
        if (lead is MediaLeadAdd && lead.alternative != null) break;
        await pumpEventQueue();
      }

      expect((lead as MediaLeadAdd).arr, ServiceKey.radarr);
      expect(lead.alternative?.id, WorldIds.seerr);
    });

    test('P7, Tears of Steel with Jellyfin silent: no Play', () async {
      final lead = await leadOf(Profiles.p7, WorldTitles.tearsOfSteel);

      expect(lead, isNot(isA<MediaLeadPlay>()));
    });
  });
}
