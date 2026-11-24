/// The words of a stuck download's card: what happened, which way out comes
/// first, what each does, and what the card says once one was taken.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/stuck_download_fault.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Friday 9 October 2026, 20:53, on this device's clock.
final _now = DateTime(2026, 10, 9, 20, 53);

const _gb = 1024 * 1024 * 1024;

ServiceQueueItem _stuck({
  ServiceKey service = ServiceKey.radarr,
  String id = '7',
  ServiceKey? client = ServiceKey.qbittorrent,
  String clientLabel = 'qBittorrent',
  String? downloadId = 'abc123',
  double? progress = 0.47,
  InFlightFault fault = InFlightFault.stalled,
  Duration? idle = const Duration(hours: 3),
  int? swarmSeeds = 0,
  int? doneBytes,
  String? warning,
  String? connectionName,
  bool awaitingMetadata = false,
}) => ServiceQueueItem(
  service: service,
  id: id,
  title: 'Big Buck Bunny',
  progress: progress,
  clientLabel: clientLabel,
  clientService: client,
  downloadId: downloadId,
  fault: fault,
  stalledSince: idle == null ? null : _now.subtract(idle),
  swarmSeeds: swarmSeeds,
  doneBytes: doneBytes,
  warning: warning,
  connectionName: connectionName,
  awaitingMetadata: awaitingMetadata,
);

void main() {
  group('the headline', () {
    test('says where it stopped', () {
      expect(stuckHeadline(_stuck()), 'Big Buck Bunny is stuck at 47%');
    });

    test('says it is stuck when its client gave no figure', () {
      expect(stuckHeadline(_stuck(progress: null)), 'Big Buck Bunny is stuck');
    });

    test('never says 100% of a download that has not finished', () {
      expect(
        stuckHeadline(_stuck(progress: 0.999)),
        'Big Buck Bunny is stuck at 99%',
      );
    });

    test('says a download its client gave up on failed', () {
      expect(
        stuckHeadline(_stuck(fault: InFlightFault.failed)),
        'Big Buck Bunny failed',
      );
    });
  });

  group('the explanation', () {
    test('nobody has the whole file: the time, and that', () {
      expect(
        stuckExplanation(_stuck(), now: _now),
        'Nothing has arrived for 3 hours, and nobody sharing it has the whole '
        'file any more.',
      );
    });

    test('somebody has the whole file: the time, and that', () {
      expect(
        stuckExplanation(
          _stuck(swarmSeeds: 2, idle: const Duration(minutes: 40)),
          now: _now,
        ),
        'Nothing has arrived for 40 minutes, though somebody sharing it has '
        'the whole file.',
      );
    });

    test('a client that counts no one says the time alone', () {
      expect(
        stuckExplanation(
          _stuck(swarmSeeds: null, idle: const Duration(days: 2, hours: 1)),
          now: _now,
        ),
        'Nothing has arrived for 2 days.',
      );
    });

    test('an undated stall says nothing is arriving', () {
      expect(
        stuckExplanation(_stuck(idle: null, swarmSeeds: null), now: _now),
        'Nothing is arriving.',
      );
    });

    test('a magnet still fetching its file list has not got that far: '
        'the count of whole copies says nothing about it', () {
      expect(
        stuckExplanation(
          _stuck(awaitingMetadata: true, swarmSeeds: 0),
          now: _now,
        ),
        'Nothing has arrived for 3 hours, not even the list of its files.',
      );
      expect(
        stuckExplanation(
          _stuck(awaitingMetadata: true, swarmSeeds: 2),
          now: _now,
        ),
        'Nothing has arrived for 3 hours, not even the list of its files.',
      );
    });

    test('an undated magnet still fetching its file list says so', () {
      expect(
        stuckExplanation(
          _stuck(awaitingMetadata: true, idle: null, swarmSeeds: null),
          now: _now,
        ),
        'Nothing is arriving, not even the list of its files.',
      );
    });

    test('one hour is one hour', () {
      expect(
        idleWords(_now.subtract(const Duration(hours: 1)), now: _now),
        '1 hour',
      );
    });

    test('a failed download says why in its client\'s words', () {
      expect(
        stuckExplanation(
          _stuck(fault: InFlightFault.failed, warning: 'not enough disk space'),
          now: _now,
        ),
        'Not enough disk space.',
      );
      expect(
        stuckExplanation(_stuck(fault: InFlightFault.failed), now: _now),
        'qBittorrent gave up on it.',
      );
    });
  });

  group('the ways out', () {
    test('a torrent added to qBittorrent by hand asks for peers again; one '
        "in Transmission opens its client, the app's only way in", () {
      // qBittorrent 5, live: a magnet nobody shares, no arr behind it.
      final byHand = _stuck(
        service: ServiceKey.qbittorrent,
        id: '0123456789abcdef0123456789abcdef01234567',
        downloadId: null,
      );
      expect(canLookForPeers(byHand), isTrue);
      expect(stuckActionsFor(byHand).primary, StuckAction.lookForPeers);
      expect(stuckActionsFor(byHand).secondary, [StuckAction.keepWaiting]);

      final transmission = _stuck(
        service: ServiceKey.transmission,
        client: ServiceKey.transmission,
        clientLabel: 'Transmission',
        id: '89abcdef0123456789abcdef0123456789abcdef',
        downloadId: null,
      );
      expect(stuckActionsFor(transmission).primary, StuckAction.openClient);
    });

    test('nobody has the file: another download first, then Remove and '
        'Keep waiting', () {
      final actions = stuckActionsFor(_stuck());
      expect(actions.primary, StuckAction.tryAnotherDownload);
      expect(actions.secondary, [StuckAction.remove, StuckAction.keepWaiting]);
    });

    test('somebody has the file: look for peers first, another download '
        'beside it', () {
      final actions = stuckActionsFor(_stuck(swarmSeeds: 3));
      expect(actions.primary, StuckAction.lookForPeers);
      expect(actions.secondary, [
        StuckAction.tryAnotherDownload,
        StuckAction.keepWaiting,
      ]);
    });

    test('a usenet client cannot be asked for peers', () {
      final actions = stuckActionsFor(
        _stuck(
          client: ServiceKey.sabnzbd,
          clientLabel: 'SABnzbd',
          swarmSeeds: 3,
        ),
      );
      expect(actions.primary, StuckAction.tryAnotherDownload);
    });

    test('a torrent no arr asked for: peers, or its client', () {
      expect(
        stuckActionsFor(
          _stuck(service: ServiceKey.qbittorrent, id: 'abc123'),
        ).primary,
        StuckAction.lookForPeers,
      );
      final transmission = stuckActionsFor(
        _stuck(
          service: ServiceKey.transmission,
          client: ServiceKey.transmission,
          clientLabel: 'Transmission',
        ),
      );
      expect(transmission.primary, StuckAction.openClient);
      expect(transmission.secondary, [StuckAction.keepWaiting]);
    });

    test('a failed download is not kept waiting: it will not move', () {
      final actions = stuckActionsFor(_stuck(fault: InFlightFault.failed));
      expect(actions.primary, StuckAction.tryAnotherDownload);
      expect(actions.secondary, [StuckAction.remove]);
    });
  });

  group('what each does', () {
    test('another download, with what has arrived', () {
      expect(
        stuckActionSubtitle(
          StuckAction.tryAnotherDownload,
          _stuck(doneBytes: (1.1 * _gb).round()),
        ),
        'Radarr is asked to find another release. The 1.1\u00A0GB so far stays.',
      );
    });

    test('another download, by the connection that asked for it', () {
      expect(
        stuckActionSubtitle(
          StuckAction.tryAnotherDownload,
          _stuck(connectionName: '4K'),
        ),
        'Radarr 4K is asked to find another release. Downloaded files stay.',
      );
    });

    test('peers again keeps what arrived', () {
      expect(
        stuckActionSubtitle(
          StuckAction.lookForPeers,
          _stuck(doneBytes: (1.1 * _gb).round()),
        ),
        'qBittorrent asks the trackers again. The 1.1\u00A0GB so far stays.',
      );
    });

    test('the quieter ways out say nothing under them', () {
      for (final action in [
        StuckAction.remove,
        StuckAction.keepWaiting,
        StuckAction.openClient,
      ]) {
        expect(stuckActionSubtitle(action, _stuck()), isNull);
      }
    });

    test('Remove asks first, neutrally', () {
      final ask = removeConfirmation(_stuck(doneBytes: (1.1 * _gb).round()));
      expect(ask.title, "Remove Big Buck Bunny's download?");
      expect(
        ask.message,
        'Stops it and deletes the 1.1\u00A0GB. Big Buck Bunny stays in your '
        'wanted list.',
      );
      expect(ask.confirm, 'Remove download');
      expect(
        removeConfirmation(_stuck()).message,
        startsWith('Stops it and deletes what has arrived.'),
      );
    });

    test('a season pack is named by its episodes, never by the row\'s count '
        'of them', () {
      const pack = ServiceQueueItem(
        service: ServiceKey.sonarr,
        id: '1518635975',
        title: 'Cupertino\u00A0· 8 episodes',
        subject: 'Cupertino S1 E1–E8',
        progress: 1,
        clientLabel: 'qBittorrent',
        fault: InFlightFault.needsImport,
      );
      final ask = removeConfirmation(pack);
      expect(ask.title, "Remove Cupertino S1 E1–E8's download?");
      expect(
        ask.message,
        endsWith('Cupertino S1 E1–E8 stays in your wanted list.'),
      );
    });
  });

  group('the note once a way out was taken', () {
    test('each says what happened', () {
      final item = _stuck();
      expect(
        stuckActionNote(StuckAction.tryAnotherDownload, item),
        'Retry requested\u00A0· Downloaded files kept',
      );
      expect(
        stuckActionNote(StuckAction.lookForPeers, item),
        'Asked again\u00A0· qBittorrent is looking for peers',
      );
      expect(
        stuckActionNote(StuckAction.remove, item),
        'Removed\u00A0· Big Buck Bunny stays in your wanted list',
      );
    });

    test('kept waiting says until when', () {
      expect(
        keptWaitingNote(_now.add(const Duration(hours: 24)), now: _now),
        'Hidden until tomorrow 20:53\u00A0· it comes back if nothing moves',
      );
      expect(
        keptWaitingNote(DateTime(2026, 10, 9, 23, 10), now: _now),
        'Hidden until 23:10\u00A0· it comes back if nothing moves',
      );
    });
  });

  test('the proof: how long, and which way the bytes travel', () {
    expect(
      stuckProof(_stuck(), now: _now),
      'Nothing for 3\u00A0h\u00A0· Radarr → qBittorrent',
    );
    expect(
      stuckProof(_stuck(fault: InFlightFault.failed), now: _now),
      'Failed\u00A0· Radarr → qBittorrent',
    );
    expect(
      stuckProof(_stuck(idle: null), now: _now),
      'Stuck\u00A0· Radarr → qBittorrent',
    );
  });
}
