import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/queue_title.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;
import 'package:cupola/features/settings/domain/service_key.dart';

final _now = DateTime(2026, 10, 9, 20, 53);

const _hash = 'A1F0C3D4E5F60718293A4B5C6D7E8F9012345601';

/// Sprite Fright, as Radarr's queue joined to qBittorrent's row reads it.
ServiceQueueItem _sprite({
  InFlightFault? fault,
  bool held = false,
  bool queued = false,
  int? rate = 4404019,
  int? eta = 660,
  int? startsIn,
  String clientInstanceId = 'qbittorrent',
  ServiceKey? clientService = ServiceKey.qbittorrent,
  String? downloadId = _hash,
  QueueTitle? title,
  int? doneBytes = 1331439862,
  int? totalBytes = 2147483648,
}) => ServiceQueueItem(
  service: ServiceKey.radarr,
  id: '1',
  title: 'Sprite Fright',
  progress: 0.62,
  clientLabel: 'qBittorrent',
  doneBytes: doneBytes,
  totalBytes: totalBytes,
  etaSeconds: eta,
  fault: fault,
  stalledSince: _now.subtract(const Duration(hours: 3)),
  downloadId: downloadId,
  clientService: clientService,
  instanceId: 'radarr',
  clientInstanceId: clientInstanceId,
  mediaId: 3,
  held: held,
  queued: queued,
  startsInSeconds: startsIn,
  rateBytesPerSecond: rate,
  tmdbId: 811631,
  names: const MediaNames(
    title: 'Sprite Fright',
    machineName: 'Sprite.Fright.2021.1080p.WEB',
    machineKind: MachineNameKind.release,
  ),
  queueTitle:
      title ??
      QueueTitle(
        name: 'Sprite Fright',
        year: 2021,
        qualityProfileId: 1,
        folder: '/mnt/tank/media/movies',
        digitalRelease: _now.subtract(const Duration(hours: 6)),
      ),
);

/// A torrent added by hand: qBittorrent's own row.
const _handAdded = ServiceQueueItem(
  service: ServiceKey.qbittorrent,
  id: 'b2e0c3d4e5f60718293a4b5c6d7e8f9012345790',
  title: 'Hand.Added.2024.1080p',
  progress: 0.4,
  clientLabel: 'qBittorrent',
  clientService: ServiceKey.qbittorrent,
  instanceId: 'qbittorrent',
  clientInstanceId: 'qbittorrent',
  rateBytesPerSecond: 2097152,
);

SeerrRequest _annasRequest() => SeerrRequest.fromJson({
  'id': 7,
  'status': 2,
  'type': 'movie',
  'media': {'id': 70, 'tmdbId': 811631, 'mediaType': 'movie', 'status': 3},
  'requestedBy': {'id': 2, 'displayName': 'Anna'},
});

void main() {
  group('the address', () {
    test("names a download by its client's id, which the client's own row "
        'shares', () {
      expect(downloadPageKey(_sprite()), _hash);
      expect(downloadPageKey(_sprite(downloadId: null)), '1');
      expect(downloadPageKey(_handAdded), _handAdded.id);
    });

    test('finds it on its connection, in any case of the hash', () {
      final items = [_handAdded, _sprite()];
      expect(
        downloadAt(items, instanceId: 'radarr', key: _hash.toLowerCase()),
        same(items[1]),
      );
      expect(downloadAt(items, instanceId: '', key: _hash), same(items[1]));
      expect(downloadAt(items, instanceId: 'radarr-4k', key: _hash), isNull);
      expect(downloadAt(items, instanceId: 'radarr', key: 'gone'), isNull);
      expect(downloadAt(items, instanceId: 'radarr', key: ' '), isNull);
    });

    test("a link made on the client's row still finds the download once an "
        'arr claims it', () {
      final claimed = _sprite();
      expect(
        downloadAt(
          [claimed],
          instanceId: 'qbittorrent',
          key: _hash.toLowerCase(),
        ),
        same(claimed),
      );
    });
  });

  group('where it stands', () {
    test('in its word and tone', () {
      expect(downloadStandOf(_sprite()), DownloadStand.downloading);
      expect(downloadStandOf(_sprite(queued: true)), DownloadStand.queued);
      expect(downloadStandOf(_sprite(held: true)), DownloadStand.stopped);
      expect(
        downloadStandOf(_sprite(fault: InFlightFault.stalled)),
        DownloadStand.stuck,
      );
      expect(
        downloadStandOf(_sprite(fault: InFlightFault.needsImport)),
        DownloadStand.needsImport,
      );
      expect(downloadStandWord(DownloadStand.needsImport), 'Needs you');
      expect(downloadStandWord(DownloadStand.stopped), 'Stopped');
    });

    test('a Stop just sent stands until the queue says the same', () {
      expect(downloadStandOf(_sprite(), held: true), DownloadStand.stopped);
      expect(
        downloadStandOf(_sprite(held: true), held: false),
        DownloadStand.downloading,
      );
      // A fault is a fault, stopped or not.
      expect(
        downloadStandOf(_sprite(fault: InFlightFault.stalled), held: true),
        DownloadStand.stuck,
      );
    });

    test('the line under the figure says how fast and until when', () {
      expect(
        downloadPaceLine(_sprite(), now: _now),
        '4.2\u00A0MB/\u2060s\u00A0· 11\u00A0min left\u00A0· ready around 21:04',
      );
      expect(
        downloadPaceLine(_sprite(rate: null, eta: null), now: _now),
        '1.2 of 2.0\u00A0GB arrived',
      );
      expect(
        downloadPaceLine(_sprite(queued: true, startsIn: 360), now: _now),
        'Starts in about 6\u00A0min',
      );
      expect(
        downloadPaceLine(_sprite(queued: true), now: _now),
        'Waits its turn in qBittorrent',
      );
      expect(
        downloadPaceLine(_sprite(held: true), now: _now),
        '1.2 of 2.0\u00A0GB arrived',
      );
      expect(
        downloadPaceLine(_sprite(fault: InFlightFault.stalled), now: _now),
        'Nothing for 3\u00A0h',
      );
      expect(
        downloadPaceLine(_sprite(fault: InFlightFault.failed), now: _now),
        isNull,
      );
    });

    test('stopped, the line says what has arrived, of the total when it is '
        'known', () {
      expect(
        downloadPaceLine(_sprite(held: true), now: _now),
        '1.2 of 2.0\u00A0GB arrived',
      );
      expect(
        downloadPaceLine(_sprite(held: true, totalBytes: null), now: _now),
        '1.2\u00A0GB arrived',
      );
      expect(
        downloadPaceLine(_sprite(held: true, doneBytes: 0), now: _now),
        isNull,
      );
      expect(
        downloadPaceLine(
          _sprite(held: true, doneBytes: 0, totalBytes: null),
          now: _now,
        ),
        isNull,
      );
      expect(
        downloadPaceLine(
          _sprite(held: true, doneBytes: null, totalBytes: null),
          now: _now,
        ),
        isNull,
      );
    });

    test('the line under the title: the year, a release out today, who '
        'asked', () {
      expect(
        downloadMetaLine(_sprite(), request: _annasRequest(), now: _now),
        '2021\u00A0· out on digital today\u00A0· Anna asked for it',
      );
      expect(
        downloadMetaLine(
          _sprite(
            title: QueueTitle(
              year: 2021,
              digitalRelease: _now.subtract(const Duration(days: 2)),
            ),
          ),
          now: _now,
        ),
        '2021',
      );
      expect(
        downloadMetaLine(
          _sprite(
            title: const QueueTitle(
              name: 'Cosmos Laundromat',
              year: 2015,
              episode: 'S2\u00A0E4\u00A0· The Second Cycle',
            ),
          ),
          now: _now,
        ),
        'S2\u00A0E4\u00A0· The Second Cycle',
      );
      expect(downloadMetaLine(_handAdded, now: _now), isEmpty);
    });
  });

  group('the steps', () {
    test('from the grab to the server, the one it is on now', () {
      final steps = downloadStepsOf(
        _sprite(),
        player: ServiceKey.jellyfin,
        now: _now,
      );
      expect(steps.map((step) => step.name), [
        'Grabbed',
        'Downloading',
        'Import',
        'On Jellyfin',
      ]);
      expect(steps.map((step) => step.detail), [
        'Radarr → qBittorrent',
        'qBittorrent\u00A0· 62%',
        'Radarr, when it finishes',
        'around 21:04',
      ]);
      expect(steps.map((step) => step.state), [
        DownloadStepState.done,
        DownloadStepState.now,
        DownloadStepState.later,
        DownloadStepState.later,
      ]);
    });

    test('a stall and an import that needs you are where it stopped', () {
      final stuck = downloadStepsOf(
        _sprite(fault: InFlightFault.stalled),
        now: _now,
      );
      expect(stuck[1].detail, 'qBittorrent\u00A0· stuck at 62%');
      expect(stuck[1].state, DownloadStepState.fault);
      expect(stuck, hasLength(3));

      final blocked = downloadStepsOf(
        _sprite(fault: InFlightFault.needsImport),
        player: ServiceKey.plex,
        now: _now,
      );
      expect(blocked[1].name, 'Downloaded');
      expect(blocked[1].state, DownloadStepState.done);
      expect(blocked[2].detail, 'Radarr needs you');
      expect(blocked[2].state, DownloadStepState.fault);
      expect(blocked[3].detail, 'once imported');
    });

    test('a transfer no arr asked for has none', () {
      expect(downloadStepsOf(_handAdded, now: _now), isEmpty);
    });
  });

  group('the facts', () {
    test('release, profile with its arr, folder, client with its address', () {
      final facts = downloadFactsOf(
        _sprite(),
        profile: 'HD-1080p',
        clientAddress: 'nas.home.arpa:8080',
      );
      expect(facts.map((fact) => '${fact.label}: ${fact.value}'), [
        'Release: Sprite.Fright.2021.1080p.WEB',
        'Profile: HD-1080p\u00A0· Radarr',
        'Folder: /mnt/tank/media/movies',
        'Client: qBittorrent',
      ]);
      expect(facts.map((fact) => fact.machine), [true, false, true, false]);
      expect(facts.last.address, 'nas.home.arpa:8080');
    });

    test('a profile not read yet, and an address nobody knows, are left '
        'out', () {
      final facts = downloadFactsOf(_handAdded);
      expect(facts.map((fact) => '${fact.label}: ${fact.value}'), [
        'Client: qBittorrent',
      ]);
    });

    test("a connection's address is its host and port", () {
      expect(
        connectionAddress('http://nas.home.arpa:8080/'),
        'nas.home.arpa:8080',
      );
      expect(connectionAddress('https://qb.example.org'), 'qb.example.org');
      expect(connectionAddress('not a url'), isNull);
    });
  });

  group('Stop and Resume', () {
    test("go to the client moving the bytes, by its id in the client's "
        'case', () {
      final joined = downloadClientOf(_sprite());
      expect(joined?.client, ServiceKey.qbittorrent);
      expect(joined?.instanceId, 'qbittorrent');
      expect(joined?.id, _hash.toLowerCase());

      final own = downloadClientOf(_handAdded);
      expect(own?.id, _handAdded.id);

      final sab = downloadClientOf(
        _sprite(
          clientService: ServiceKey.sabnzbd,
          clientInstanceId: 'sabnzbd',
          downloadId: 'SABnzbd_nzo_Ab12',
        ),
      );
      expect(sab?.id, 'SABnzbd_nzo_Ab12');
    });

    test("an arr row its client was not matched to can't be stopped from "
        'here, nor a finished or failed one', () {
      expect(downloadClientOf(_sprite(clientService: null)), isNull);
      expect(canStopDownload(_sprite(clientService: null)), isFalse);
      expect(canStopDownload(_sprite()), isTrue);
      expect(canStopDownload(_sprite(held: true)), isTrue);
      expect(
        canStopDownload(_sprite(fault: InFlightFault.needsImport)),
        isFalse,
      );
      expect(canStopDownload(_sprite(fault: InFlightFault.failed)), isFalse);
      expect(canStopDownload(_sprite(fault: InFlightFault.stalled)), isTrue);
    });
  });

  group('the speed since the page was opened', () {
    test('keeps a reading while it moves and its client measures it', () {
      var trace = const <RateSample>[];
      trace = withRateSample(trace, _sprite(), at: _now);
      trace = withRateSample(
        trace,
        _sprite(rate: 5000000),
        at: _now.add(const Duration(seconds: 15)),
      );
      expect(trace.map((sample) => sample.bytesPerSecond), [4404019, 5000000]);
      expect(withRateSample(trace, _sprite(held: true), at: _now), same(trace));
      expect(withRateSample(trace, _sprite(rate: null), at: _now), same(trace));
      expect(withRateSample(trace, null, at: _now), same(trace));
    });

    test('keeps an hour of readings at most', () {
      var trace = const <RateSample>[];
      for (var i = 0; i < rateTraceLength + 5; i++) {
        trace = withRateSample(
          trace,
          _sprite(rate: i + 1),
          at: _now.add(Duration(seconds: 15 * i)),
        );
      }
      expect(trace, hasLength(rateTraceLength));
      expect(trace.first.bytesPerSecond, 6);
    });

    test('says how long it has been watched', () {
      expect(
        rateTraceCaption(const Duration(seconds: 40)),
        'since you opened this',
      );
      expect(
        rateTraceCaption(const Duration(minutes: 4, seconds: 10)),
        'since you opened this\u00A0· 4\u00A0min',
      );
    });
  });

  group("the title a queue record embeds", () {
    test('a movie: its year, profile, folder and dates', () {
      final title = QueueTitle.ofRecord({
        'movie': {
          'title': 'Sprite Fright',
          'year': 2021,
          'qualityProfileId': 4,
          'path': '/mnt/tank/media/movies/Sprite Fright (2021)',
          'digitalRelease': '2026-10-09T14:00:00Z',
        },
      })!;
      expect(title.name, 'Sprite Fright');
      expect(title.year, 2021);
      expect(title.qualityProfileId, 4);
      expect(title.folder, '/mnt/tank/media/movies');
      expect(title.digitalRelease, isNotNull);
      expect(title.episode, isNull);
    });

    test('an episode: the series, and the episode with its title', () {
      final record = {
        'series': {
          'title': 'Cosmos Laundromat',
          'year': 2015,
          'rootFolderPath': '/mnt/tank/media/series/',
        },
        'episode': {
          'seasonNumber': 2,
          'episodeNumber': 4,
          'title': 'The Second Cycle',
        },
        'seasonNumber': 2,
      };
      final title = QueueTitle.ofRecord(record)!;
      expect(title.name, 'Cosmos Laundromat');
      expect(title.episode, 'S2\u00A0E4\u00A0· The Second Cycle');
      expect(title.folder, '/mnt/tank/media/series');
      // A pack names its series and no episode.
      expect(QueueTitle.ofRecord(record, single: false)!.episode, isNull);
    });

    test('nothing for a record that embeds no title', () {
      expect(QueueTitle.ofRecord({'title': 'Unknown.Release'}), isNull);
    });
  });
}
