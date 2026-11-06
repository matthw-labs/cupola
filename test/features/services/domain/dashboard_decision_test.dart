/// The ranking rule, and the two things that depend on it.
///
/// Pure: the region's whole argument is an ordering and a cap, and neither needs
/// a widget to be wrong.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('rankDecisions', () {
    test('faults come before backlog, however old the backlog is', () {
      final ranked = rankDecisions([
        _decision(
          DecisionKind.pendingRequest,
          'request',
          at: DateTime.utc(2020, 1, 1),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'stall',
          at: DateTime.utc(2024, 6, 1),
        ),
      ]);

      expect(ranked.map((d) => d.title), ['stall', 'request']);
    });

    test('a violation ranks after every fault and before a request', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.pendingRequest, 'request', at: null),
        _decision(
          DecisionKind.violation,
          'violation',
          at: DateTime.utc(2024, 6),
          service: ServiceKey.tracearr,
        ),
        _decision(
          DecisionKind.expiringCertificate,
          'certificate',
          at: DateTime.utc(2024, 6),
        ),
      ]);

      expect(ranked.map((d) => d.title), [
        'certificate',
        'violation',
        'request',
      ]);
    });

    test('violations are never folded into one row, however alike', () {
      final grouped = groupDecisions([
        for (final title in ['a', 'b', 'c'])
          _decision(
            DecisionKind.violation,
            title,
            at: null,
            service: ServiceKey.tracearr,
          ),
      ]);

      expect(grouped, hasLength(3));
    });

    test('oldest first inside a kind', () {
      final ranked = rankDecisions([
        _decision(
          DecisionKind.stalledDownload,
          'new',
          at: DateTime.utc(2024, 6),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'old',
          at: DateTime.utc(2024, 1),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'mid',
          at: DateTime.utc(2024, 3),
        ),
      ]);

      expect(ranked.map((d) => d.title), ['old', 'mid', 'new']);
    });

    test('an undated item sorts last inside its kind, never first', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.expiringCertificate, 'undated', at: null),
        _decision(
          DecisionKind.expiringCertificate,
          'dated',
          at: DateTime.utc(2024, 6),
        ),
      ]);

      // Dockge dates nothing. An item that cannot be placed honestly loses to
      // one that can: it must not inherit "just now" and outrank a real age.
      expect(ranked.map((d) => d.title), ['dated', 'undated']);
    });

    test('two undated items keep their source order', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.expiringCertificate, 'first', at: null),
        _decision(DecisionKind.expiringCertificate, 'second', at: null),
      ]);

      // `List.sort` is not stable; rows that shuffle on every rebuild read as a
      // page that cannot make up its mind.
      expect(ranked.map((d) => d.title), ['first', 'second']);
    });

    test('kinds rank worst-first, and the cap cuts from the bottom', () {
      final ranked = rankDecisions([
        _decision(
          DecisionKind.expiringCertificate,
          'cert',
          at: DateTime.utc(2024),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'stall',
          at: DateTime.utc(2024),
        ),
        _decision(DecisionKind.failedImport, 'import', at: DateTime.utc(2024)),
      ], cap: 2);

      expect(ranked.map((d) => d.title), ['stall', 'import']);
    });

    test('a cap larger than the list is not an error', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.stalledDownload, 'one', at: DateTime.utc(2024)),
      ], cap: 4);

      expect(ranked, hasLength(1));
    });
  });

  // APP-04: eighteen blocked imports were eighteen rows, and the phone's three
  // slots went to the first three of them.
  group('groupDecisions', () {
    test('identical faults fold into one row that counts them', () {
      final grouped = groupDecisions([
        for (var i = 0; i < 18; i++)
          _decision(
            DecisionKind.importBlocked,
            'Episode $i',
            at: DateTime.utc(2024, 1, 18 - i),
            service: ServiceKey.sonarr,
            instanceId: 'sonarr-1',
            actionId: 7,
          ),
      ]);

      expect(grouped, hasLength(1));
      final row = grouped.single;
      expect(row.kind, DecisionKind.importBlocked);
      expect(row.count, 18);
      expect(row.title, '18 need a manual import');
      expect(row.detail, 'Sonarr\u00A0· Episode 0, Episode 1 and 16 more');
      // Ranks where its oldest member would have.
      expect(row.occurredAt, DateTime.utc(2024, 1, 1));
      // What every member agrees on travels with the group.
      expect(row.actionId, 7);
      expect(row.instanceId, 'sonarr-1');
      expect(row.route, '/stack/sonarr');
    });

    test('a folded row keeps the cause every member shares, and only '
        'then', () {
      List<DashboardDecision> stalls(List<String?> reasons) => [
        for (final (i, reason) in reasons.indexed)
          _decision(
            DecisionKind.stalledDownload,
            'Film $i',
            at: null,
            requires: ServiceKey.sabnzbd,
            reason: reason,
          ),
      ];

      final shared = groupDecisions(
        stalls(['Disk full', 'Disk full', 'Disk full']),
      ).single;
      expect(shared.title, '3 stuck downloads');
      expect(
        shared.detail,
        'Disk full\u00A0· Radarr\u00A0· Film 0, Film 1 and 1 more',
      );
      expect(shared.reason, 'Disk full');

      final differing = groupDecisions(
        stalls(['Disk full', 'Password needed']),
      ).single;
      expect(differing.title, '2 stuck downloads');
      expect(differing.detail, 'Radarr\u00A0· Film 0, Film 1');
      expect(differing.reason, isNull);

      // A member that gave no cause is not one that shares it.
      expect(groupDecisions(stalls(['Disk full', null])).single.reason, isNull);
    });

    test('a lone fault stays itself', () {
      final lone = _decision(
        DecisionKind.importBlocked,
        'Dune',
        at: DateTime.utc(2024),
      );
      expect(groupDecisions([lone]).single, same(lone));
    });

    test('a different service, connection or remedy is a different row', () {
      final grouped = groupDecisions([
        _decision(DecisionKind.importBlocked, 'a', at: null),
        _decision(
          DecisionKind.importBlocked,
          'b',
          at: null,
          service: ServiceKey.sonarr,
        ),
        _decision(
          DecisionKind.importBlocked,
          'c',
          at: null,
          instanceId: 'radarr-4k',
        ),
        _decision(
          DecisionKind.stalledDownload,
          'd',
          at: null,
          requires: ServiceKey.qbittorrent,
        ),
        _decision(
          DecisionKind.stalledDownload,
          'e',
          at: null,
          requires: ServiceKey.sabnzbd,
        ),
      ]);

      expect(grouped, hasLength(5));
      expect(grouped.every((decision) => decision.count == 1), isTrue);
    });

    test('only a jump folds: Test and Approve act on one item', () {
      final grouped = groupDecisions([
        _decision(DecisionKind.failingIndexer, 'media', at: null),
        _decision(DecisionKind.failingIndexer, 'vpn', at: null),
        _decision(DecisionKind.pendingRequest, 'Dune', at: null),
        _decision(DecisionKind.pendingRequest, 'Alien', at: null),
      ]);

      expect(grouped.map((decision) => decision.title), [
        'media',
        'vpn',
        'Dune',
        'Alien',
      ]);
    });

    test('a value the members disagree on is dropped, never borrowed', () {
      final row = groupDecisions([
        _decision(DecisionKind.importBlocked, 'a', at: null, actionId: 1),
        _decision(DecisionKind.importBlocked, 'b', at: null, actionId: 2),
      ]).single;

      // Filing both under the first one's movie would import the second into
      // the wrong place.
      expect(row.actionId, isNull);
      expect(row.title, '2 need a manual import');
    });
  });

  group('decisionCapFor', () {
    test('three on the phone, four on the desktop, two at compact', () {
      expect(decisionCapFor(desktopShell: false, compact: false), 3);
      expect(decisionCapFor(desktopShell: true, compact: false), 4);
      expect(decisionCapFor(desktopShell: true, compact: true), 2);
    });
  });

  group('the vocabulary', () {
    test('only a pending request and a violation are not faults', () {
      for (final kind in DecisionKind.values) {
        expect(
          kind.isFault,
          kind != DecisionKind.pendingRequest && kind != DecisionKind.violation,
          reason: '$kind',
        );
      }
    });

    test('a violation is reviewed, and says what it could not open', () {
      expect(decisionActionLabel(DecisionKind.violation), 'Review');
      expect(
        decisionUnavailableToast(DecisionKind.violation, ServiceKey.tracearr),
        endsWith('to open this violation.'),
      );
      expect(DecisionKind.violation.opensUnderLens, isFalse);
    });

    test('the stall control names the client it would open', () {
      expect(
        decisionActionLabel(
          DecisionKind.stalledDownload,
          target: ServiceKey.qbittorrent,
        ),
        'Open in qBittorrent',
      );
      // No target named: the row still offers the act rather than going blank.
      expect(
        decisionActionLabel(DecisionKind.stalledDownload),
        'Open in client',
      );
    });

    test('a blocked import names its remedy, not the client', () {
      // APP-04: filed as a stall, it said "Open in qBittorrent", the one
      // place that cannot import a file already on disk.
      expect(
        decisionActionLabel(
          DecisionKind.importBlocked,
          target: ServiceKey.sonarr,
        ),
        'Manual import',
      );
      // Readarr has no import wizard in this app; the control says where it
      // actually goes rather than promising one.
      expect(
        decisionActionLabel(
          DecisionKind.importBlocked,
          target: ServiceKey.readarr,
        ),
        'Open in Readarr',
      );
      expect(DecisionKind.importBlocked.isFault, isTrue);
    });

    test(
      'the control opens the other service, else the one that raised it',
      () {
        final ownStall = _decision(
          DecisionKind.stalledDownload,
          'a',
          at: DateTime.utc(2024),
        );
        expect(ownStall.actionTarget, ServiceKey.radarr);
        expect(
          decisionActionLabel(ownStall.kind, target: ownStall.actionTarget),
          'Open in Radarr',
        );
      },
    );

    test('an unavailable control says what it needs, and offers a way', () {
      expect(
        decisionUnavailableToast(
          DecisionKind.stalledDownload,
          ServiceKey.qbittorrent,
        ),
        'Set up qBittorrent to open this transfer.',
      );
    });
  });
}

DashboardDecision _decision(
  DecisionKind kind,
  String title, {
  required DateTime? at,
  ServiceKey service = ServiceKey.radarr,
  ServiceKey? requires,
  String instanceId = '',
  int? actionId,
  String? reason,
}) => DashboardDecision(
  kind: kind,
  id: '$kind-$title',
  service: service,
  title: title,
  detail: 'detail',
  occurredAt: at,
  requiresService: requires,
  instanceId: instanceId,
  actionId: actionId,
  reason: reason,
);
