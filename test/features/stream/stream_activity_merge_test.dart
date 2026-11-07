/// The one list of Now playing: what a media server says of a playback and
/// what Tracearr says of it are one row, and a playback only Tracearr sees is
/// appended, marked, with none of the server's actions.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_activity_row.dart';
import 'package:cupola/features/stream/presentation/stream_activity_merge.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_stream_session.dart';

StreamActivityRow _native({
  ServiceKey service = ServiceKey.emby,
  String instanceId = 'emby-1',
  String? connectionName,
  String user = 'Anna',
  String device = 'Infuse\u00A0· Living room',
  String itemId = '15',
  StreamPlayMethod method = StreamPlayMethod.directPlay,
  List<String> reasons = const [],
}) => StreamActivityRow(
  service: service,
  instanceId: instanceId,
  connectionName: connectionName,
  session: StreamSession(
    id: 'native-$user-$itemId',
    userName: user,
    title: 'Sintel',
    subtitle: null,
    deviceLabel: device,
    posterPath: '/Items/$itemId/Images/Primary',
    playMethod: method,
    transcodeReasons: reasons,
    bitrate: null,
    bitrateIsNominal: true,
    progress: 0.4,
    isPaused: false,
    itemId: itemId,
  ),
);

TracearrStream _stream({
  TracearrServerType type = TracearrServerType.emby,
  String serverName = 'Casa Emby',
  String user = 'anna',
  String ratingKey = '15',
  String product = 'Infuse',
  String player = 'Living room',
  String device = 'Infuse',
  bool transcode = false,
  List<String> reasons = const [],
  String? avatar,
  TracearrMediaType mediaType = TracearrMediaType.movie,
  String? showTitle,
}) => TracearrStream(
  id: 'stream-$user-$ratingKey',
  server: TracearrServerRef(id: 'srv', name: serverName, type: type),
  person: TracearrPerson(name: user, avatarUrl: avatar),
  media: TracearrMedia(
    type: mediaType,
    title: 'Sintel',
    showTitle: showTitle,
    year: 2010,
    durationMs: 600000,
    ids: TracearrMediaIds(tmdb: 45745, ratingKey: ratingKey),
  ),
  device: TracearrDevice(device: device, player: player, product: product),
  quality: TracearrQuality(
    isTranscode: transcode,
    videoDecision: transcode
        ? TracearrDecision.transcode
        : TracearrDecision.directPlay,
    audioDecision: TracearrDecision.directPlay,
    bitrate: 4200,
    transcode: reasons.isEmpty ? null : TracearrTranscodeInfo(reasons: reasons),
  ),
  progressMs: 240000,
);

List<StreamActivityRow> _merge(
  List<StreamActivityRow> native,
  List<TracearrStream> streams, {
  Map<ServiceKey, Set<String>> names = const {},
}) => mergeTracearrStreams(
  native: native,
  sightings: [(instanceId: 'tracearr-1', streams: streams)],
  connectionNames: names,
);

void main() {
  group('a playback both sources describe', () {
    test('is one row, the server\'s own, enriched and not replaced', () {
      final own = _native();
      final rows = _merge(
        [own],
        [_stream(avatar: '/api/v1/images/proxy?u=anna')],
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.isThrough, isFalse);
      // The server's row wins: its id is where Stop goes, its service and
      // connection are where the page it opens is.
      expect(row.session.id, own.session.id);
      expect(row.service, ServiceKey.emby);
      expect(row.instanceId, 'emby-1');
      expect(row.tracearr?.instanceId, 'tracearr-1');
      expect(row.tracearr?.avatarPath, '/api/v1/images/proxy?u=anna');
    });

    test('is found whatever the two sources call the player', () {
      // Tracearr names the device, the player, the product and the platform;
      // the server's label holds the client and the device.
      final rows = _merge(
        [_native(device: 'Emby Web\u00A0· Phone')],
        [
          _stream(
            device: 'Browser',
            player: 'Phone',
            product: 'Emby Web',
            ratingKey: '15',
          ),
        ],
      );
      expect(rows, hasLength(1));
      expect(rows.single.isThrough, isFalse);
    });

    test('takes Tracearr\'s reasons for a transcode the server did not '
        'explain, and keeps the server\'s own when it did', () {
      final bare = _merge(
        [_native(method: StreamPlayMethod.transcode)],
        [
          _stream(transcode: true, reasons: const ['VideoCodecNotSupported']),
        ],
      );
      expect(bare.single.session.transcodeReasons, [
        'Video codec not supported',
      ]);

      final said = _merge(
        [
          _native(
            method: StreamPlayMethod.transcode,
            reasons: const ['1080p → 720p'],
          ),
        ],
        [
          _stream(transcode: true, reasons: const ['VideoCodecNotSupported']),
        ],
      );
      expect(said.single.session.transcodeReasons, ['1080p → 720p']);
    });

    test('compares item ids without case or dashes', () {
      final rows = _merge(
        [_native(service: ServiceKey.jellyfin, itemId: 'AB12CD34')],
        [
          _stream(
            type: TracearrServerType.jellyfin,
            ratingKey: 'ab12cd34'.replaceRange(2, 2, '-'),
          ),
        ],
      );
      expect(rows, hasLength(1));
    });

    test('two people on one screen are two rows, each matched once', () {
      final rows = _merge(
        [_native(user: 'Anna'), _native(user: 'Luca')],
        [_stream(user: 'luca'), _stream(user: 'anna')],
      );
      expect(rows, hasLength(2));
      expect(rows.every((r) => !r.isThrough && r.tracearr != null), isTrue);
    });
  });

  group('a playback only Tracearr sees', () {
    test('is appended, marked as coming through it, with its own id', () {
      final rows = _merge(
        [_native()],
        [
          _stream(
            type: TracearrServerType.plex,
            serverName: 'Cabin Plex',
            user: 'luca',
            ratingKey: '103',
          ),
        ],
      );

      expect(rows, hasLength(2));
      final through = rows.last;
      expect(through.isThrough, isTrue);
      expect(through.through, ServiceKey.tracearr);
      expect(through.service, ServiceKey.plex);
      expect(through.instanceId, 'tracearr-1');
      expect(through.serverLabel, 'Plex\u00A0· through Tracearr');
      expect(through.session.userName, 'luca');
      expect(through.session.title, 'Sintel');
      expect(through.session.subtitle, '2010');
      expect(through.session.itemId, '103');
      // Not the server's row: nothing of Cupola reaches that server.
      expect(rows.first.isThrough, isFalse);
    });

    test('is what a media server that did not answer leaves to Tracearr', () {
      final rows = _merge(const [], [
        _stream(type: TracearrServerType.jellyfin, ratingKey: 'jf-1'),
      ]);
      expect(rows.single.isThrough, isTrue);
      expect(rows.single.service, ServiceKey.jellyfin);
    });

    test('a kind of server Cupola has no word for stays Tracearr\'s', () {
      final rows = _merge(const [], [
        _stream(type: TracearrServerType.unknown),
      ]);
      expect(rows.single.service, ServiceKey.tracearr);
      expect(rows.single.serverLabel, 'Tracearr');
    });

    test('is a row when one thing the key holds differs', () {
      final cases = {
        'another item': _stream(ratingKey: '99'),
        'another person': _stream(user: 'luca'),
        'another device': _stream(
          device: 'Roku',
          player: 'Kitchen',
          product: 'Roku',
        ),
        'another kind of server': _stream(type: TracearrServerType.plex),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final rows = _merge([_native()], [value]);
        expect(rows, hasLength(2), reason: key);
        expect(rows.last.isThrough, isTrue, reason: key);
      }
    });
  });

  group('the server\'s name, when Cupola knows it', () {
    test('tells two connections of one kind apart when Tracearr names one '
        'of them', () {
      final home = _native(instanceId: 'emby-home', connectionName: 'Home');
      final rows = _merge(
        [home],
        [_stream(serverName: 'Cabin')],
        names: {
          ServiceKey.emby: {'home', 'cabin'},
        },
      );
      // The stream is the Cabin's and the row is Home's: not the same.
      expect(rows, hasLength(2));
      expect(rows.last.isThrough, isTrue);
    });

    test('says nothing when it matches none we hold: the owner\'s name for a '
        'server is not ours', () {
      final rows = _merge(
        [_native(instanceId: 'emby-home', connectionName: 'Home')],
        [_stream(serverName: 'Casa Emby')],
        names: {
          ServiceKey.emby: {'home', 'cabin'},
        },
      );
      expect(rows, hasLength(1));
      expect(rows.single.isThrough, isFalse);
    });

    test('is the same when the row carries the name Tracearr gives', () {
      final rows = _merge(
        [_native(instanceId: 'emby-home', connectionName: 'Casa Emby')],
        [_stream(serverName: 'casa emby')],
        names: {
          ServiceKey.emby: {'casa emby', 'cabin'},
        },
      );
      expect(rows, hasLength(1));
    });
  });

  group('two Tracearr connections that see one playback', () {
    List<StreamActivityRow> twoSee(
      List<StreamActivityRow> native,
      List<TracearrStream> first,
      List<TracearrStream> second,
    ) => mergeTracearrStreams(
      native: native,
      sightings: [
        (instanceId: 'tracearr-1', streams: first),
        (instanceId: 'tracearr-2', streams: second),
      ],
    );

    test('make one row of a playback a media server also says, the first '
        'connection\'s sight on it', () {
      final rows = twoSee([_native()], [_stream(avatar: '/first')], [
        _stream(avatar: '/second'),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.isThrough, isFalse);
      expect(rows.single.tracearr?.instanceId, 'tracearr-1');
      expect(rows.single.tracearr?.avatarPath, '/first');
    });

    test('make one appended row of a playback only they see', () {
      final plex = _stream(
        type: TracearrServerType.plex,
        user: 'luca',
        ratingKey: '103',
      );
      final rows = twoSee(const [], [plex], [plex]);

      expect(rows, hasLength(1));
      expect(rows.single.isThrough, isTrue);
      expect(rows.single.instanceId, 'tracearr-1');
    });

    test('keep a second screen, which is another playback', () {
      final rows = twoSee(
        const [],
        [_stream(type: TracearrServerType.plex, user: 'luca', ratingKey: '9')],
        [
          _stream(type: TracearrServerType.plex, user: 'luca', ratingKey: '9'),
          _stream(
            type: TracearrServerType.plex,
            user: 'luca',
            ratingKey: '9',
            product: 'Plex Web',
            player: 'Chrome',
            device: 'Browser',
          ),
        ],
      );

      expect(rows, hasLength(2));
    });

    test('never fold the streams of one connection into each other', () {
      final one = _stream(
        type: TracearrServerType.plex,
        user: 'luca',
        ratingKey: '9',
      );
      final rows = twoSee(const [], [one, one], const []);
      expect(rows, hasLength(2));
    });
  });

  group('the Tracearr stream as a session', () {
    test('says its delivery from the decisions', () {
      StreamPlayMethod method(TracearrDecision video, TracearrDecision audio) =>
          tracearrPlayMethodOf(
            TracearrQuality(videoDecision: video, audioDecision: audio),
          );
      expect(
        method(TracearrDecision.directPlay, TracearrDecision.directPlay),
        StreamPlayMethod.directPlay,
      );
      expect(
        method(TracearrDecision.copy, TracearrDecision.directPlay),
        StreamPlayMethod.directStream,
      );
      expect(
        method(TracearrDecision.directPlay, TracearrDecision.transcode),
        StreamPlayMethod.transcode,
      );
      expect(
        tracearrPlayMethodOf(const TracearrQuality(isTranscode: true)),
        StreamPlayMethod.transcode,
      );
      // No decision at all is not a transcode.
      expect(
        tracearrPlayMethodOf(const TracearrQuality()),
        StreamPlayMethod.directPlay,
      );
    });

    test('puts a series first and its episode under it, as a server does', () {
      final session = tracearrStreamSession(
        TracearrStream(
          id: 's',
          media: const TracearrMedia(
            type: TracearrMediaType.episode,
            title: 'The Second Cycle',
            showTitle: 'Cosmos Laundromat',
            seasonNumber: 2,
            episodeNumber: 3,
            durationMs: 1440000,
          ),
          person: const TracearrPerson(name: 'Anna'),
          progressMs: 1200000,
        ),
      );
      expect(session.title, 'Cosmos Laundromat');
      expect(session.subtitle, 'S2 E3\u00A0· The Second Cycle');
      expect(session.remaining, const Duration(minutes: 4));
      expect(session.userName, 'Anna');
    });

    test('names a player once when it is the product by another case', () {
      final session = tracearrStreamSession(
        _stream(product: 'Plex for LG', player: ' plex for lg'),
      );
      expect(session.deviceLabel, 'Plex for LG');
    });

    test('keeps the poster a path on Tracearr, and the bitrate in bits', () {
      final session = tracearrStreamSession(_stream());
      expect(session.bitrate, 4200000);
      expect(session.bitrateIsNominal, isTrue);
      expect(session.deviceLabel, 'Infuse\u00A0· Living room');
      expect(session.titleKey?.location, '/media/movie/45745');
      expect(session.itemId, '15');
    });
  });
}
