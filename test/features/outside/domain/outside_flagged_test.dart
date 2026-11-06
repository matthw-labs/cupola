import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/outside/domain/outside_flagged.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';

/// What Cupola says when Tracearr flags a rule broken, and how far it has
/// read: the cursor, what counts as news, and the words.
///
/// Every place and address here is invented, and none is allowed to reach a
/// notice.
const _d = dotSeparator;

void main() {
  // Friday 6 November 2026, 17:00 UTC.
  final now = DateTime.utc(2026, 11, 6, 17);

  TracearrViolation violation(
    String id, {
    DateTime? at,
    String rule = 'Too many streams',
    String person = 'Anna',
    bool seen = false,
  }) => TracearrViolation.fromJson({
    'id': id,
    'severity': 'warning',
    'created_at': at?.toIso8601String(),
    'acknowledged_at': seen ? '2026-11-06T16:00:00.000Z' : null,
    'rule': {'id': 'r1', 'name': rule},
    'server': {'id': 's1', 'name': 'Casa Emby', 'type': 'emby'},
    'user': {'id': 'u-$person', 'username': person},
    // What a violation keeps beside its rule, which a notice never says.
    'data': {
      'ipAddress': '203.0.113.7',
      'evidence': [
        {
          'groupIndex': 0,
          'matched': true,
          'conditions': [
            {
              'field': 'travel_speed_kmh',
              'operator': 'gt',
              'threshold': 900,
              'actual': 2400,
              'matched': true,
              'details': {
                'distance': 5000,
                'timeDeltaHours': 2,
                'previousLocation': {'city': 'Lisbon', 'country': 'Portugal'},
                'currentLocation': {'city': 'Tokyo', 'country': 'Japan'},
              },
            },
          ],
        },
      ],
    },
  });

  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

  group('where a connection starts', () {
    test('at the newest violation it holds, whatever its age', () {
      final start = flaggedStartOf([
        violation('a', at: now.subtract(const Duration(days: 40))),
      ]);
      expect(start, now.subtract(const Duration(days: 40)));
    });

    test('at the start of time when it holds none: everything is new', () {
      expect(flaggedStartOf(const []), flaggedFromTheStart);
      expect(flaggedFromTheStart.isBefore(ago(60 * 24 * 365 * 30)), isTrue);
    });
  });

  test('violations with no time at all place no start, so no read from the '
      'beginning of time', () {
    // Holding some and knowing none of their times is not holding none: the
    // start of time would bring every old violation up as news.
    expect(flaggedStartOf([violation('lost')]), isNull);
    expect(
      flaggedStartOf([violation('lost'), violation('b', at: ago(9))]),
      ago(9),
    );
  });

  group('what a read since a cursor brings', () {
    test('only what is strictly newer, newest first', () {
      final cursor = ago(30);
      final read = flaggedFreshOf([
        violation('old', at: ago(45)),
        violation('same', at: cursor),
        violation('b', at: ago(10)),
        violation('c', at: ago(5)),
      ], cursor);
      expect(read.fresh.map((v) => v.id), ['c', 'b']);
      expect(read.cursor, ago(5));
    });

    test(
      'Tracearr answering the cursor\'s own violation again is not news',
      () {
        // Measured on Tracearr 3.1.4: `since` is inclusive, and a timestamp it
        // keeps to the microsecond comes back to the millisecond.
        final cursor = ago(30);
        final read = flaggedFreshOf([violation('same', at: cursor)], cursor);
        expect(read.fresh, isEmpty);
        expect(read.cursor, cursor);
      },
    );

    test('one somebody already acknowledged is read, and not said', () {
      final read = flaggedFreshOf([
        violation('seen', at: ago(5), seen: true),
        violation('b', at: ago(10)),
      ], ago(30));
      expect(read.fresh.map((v) => v.id), ['b']);
      expect(read.cursor, ago(5), reason: 'it was read all the same');
    });

    test('one with no time cannot be placed after anything', () {
      final read = flaggedFreshOf([violation('lost')], ago(30));
      expect(read.fresh, isEmpty);
      expect(read.cursor, ago(30));
    });
  });

  group('the notice', () {
    test('one violation says its rule, its person and when, and opens it', () {
      final notice = flaggedNotice(
        [violation('a', at: ago(4))],
        instanceId: 'tracearr',
        name: null,
        now: now,
      )!;
      expect(notice.kind, OutsideNoticeKind.flagged);
      expect(notice.title, 'Flagged');
      expect(
        notice.body,
        'Too many streams${_d}Anna$_d${withUnit(4, 'min')} ago',
      );
      expect(
        notice.route,
        ServiceRoutes.tracearrViolation('a', instanceId: 'tracearr'),
      );
      expect(notice.route, '/stack/tracearr/violations/a?i=tracearr');
      expect(notice.id, 'a');
    });

    test('a Tracearr clock ahead of the phone says just now, not "in"', () {
      // Tracearr's clock is the cursor's, and may run in front of the phone's.
      for (final ahead in [
        const Duration(seconds: 90),
        const Duration(hours: 2),
      ]) {
        final notice = flaggedNotice(
          [violation('a', at: now.add(ahead))],
          instanceId: 'tracearr',
          name: null,
          now: now,
        )!;
        expect(notice.body, 'Too many streams${_d}Anna${_d}just now');
        expect(notice.body, isNot(contains('in ')));
      }
    });

    test('several are one notice that opens the Violations tab', () {
      final notice = flaggedNotice(
        [
          violation('c', at: ago(5), person: 'Marco'),
          violation('b', at: ago(10)),
          violation('a', at: ago(20), person: 'Marco'),
        ],
        instanceId: 'tracearr',
        name: null,
        now: now,
      )!;
      expect(notice.body, '3 new violations${_d}Marco, Anna');
      expect(notice.route, '/stack/tracearr/violations?i=tracearr');
      expect(notice.id, 'group-c', reason: 'the newest names the group');
    });

    test('whose: two named and the rest counted', () {
      final notice = flaggedNotice(
        [
          for (final (index, person) in [
            'Anna',
            'Marco',
            'Luca',
            'Eva',
          ].indexed)
            violation('v$index', at: ago(index + 1), person: person),
        ],
        instanceId: 'tracearr',
        name: null,
        now: now,
      )!;
      expect(notice.body, '4 new violations${_d}Anna, Marco +2');
    });

    test('a read that stopped on a full page is a floor, even for one', () {
      final burst = flaggedNotice(
        [for (var i = 0; i < 50; i++) violation('v$i', at: ago(i + 1))],
        instanceId: 'tracearr',
        name: null,
        now: now,
        more: true,
      )!;
      expect(burst.body, startsWith('50+ new violations'));
    });

    test('a second Tracearr is named, so two are told apart', () {
      final one = flaggedNotice(
        [violation('a', at: ago(4))],
        instanceId: 'tracearr-2',
        name: '4K',
        now: now,
      )!;
      expect(
        one.body,
        'Too many streams${_d}Anna$_d${withUnit(4, 'min')} ago${_d}Tracearr 4K',
      );
      expect(one.route, endsWith('?i=tracearr-2'));
      final many = flaggedNotice(
        [violation('a', at: ago(4)), violation('b', at: ago(3))],
        instanceId: 'tracearr-2',
        name: '4K',
        now: now,
      )!;
      expect(many.body, '2 new violations${_d}Anna${_d}Tracearr 4K');
    });

    test('a rule with no name is a violation, a person with none someone', () {
      final notice = flaggedNotice(
        [violation('a', at: ago(4), rule: ' ', person: '')],
        instanceId: 'tracearr',
        name: null,
        now: now,
      )!;
      expect(notice.body, 'Violation${_d}Someone$_d${withUnit(4, 'min')} ago');
    });

    test('nothing new is no notice', () {
      expect(
        flaggedNotice(const [], instanceId: 'tracearr', name: null, now: now),
        isNull,
      );
    });

    test('never a place, an address or a speed', () {
      final notices = [
        flaggedNotice(
          [violation('a', at: ago(4))],
          instanceId: 'tracearr',
          name: null,
          now: now,
        )!,
        flaggedNotice(
          [violation('a', at: ago(4)), violation('b', at: ago(2))],
          instanceId: 'tracearr',
          name: null,
          now: now,
        )!,
      ];
      for (final notice in notices) {
        final said = [notice.body, notice.route, notice.toString()].join(' ');
        for (final secret in ['203.0.113.7', 'Lisbon', 'Tokyo', 'Portugal']) {
          expect(said, isNot(contains(secret)));
        }
      }
    });
  });
}
