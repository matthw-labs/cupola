import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/outside/data/outside_run.dart';
import 'package:cupola/features/outside/data/outside_shelf.dart';
import 'package:cupola/features/outside/domain/outside_flagged.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_decisions.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

import '../../../test_helpers/settings_scope.dart';

/// The Flagged notification's run: what it asks Tracearr and when, what it
/// remembers per connection, and what it never asks at all.
void main() {
  // Friday 6 November 2026, 17:00 UTC; the runs are a quarter of an hour apart.
  final start = DateTime.utc(2026, 11, 6, 17);
  late Directory folder;
  late OutsideShelf shelf;
  late _Tracearr first;
  late _Tracearr second;
  final sourceReads = <DecisionSource>[];

  setUp(() {
    folder = Directory.systemTemp.createTempSync('outside-flagged');
    shelf = OutsideShelf(folder);
    first = _Tracearr();
    second = _Tracearr();
    sourceReads.clear();
  });
  tearDown(() => folder.deleteSync(recursive: true));

  Future<ProviderContainer> container({
    bool configured = true,
    bool twoConnections = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(
          configured: [if (configured) ServiceKey.tracearr],
          customize: (settings) => twoConnections
              ? settings.copyWithInstance(
                  const ServiceInstance(
                    id: 'tracearr-2',
                    service: ServiceKey.tracearr,
                    label: '4K',
                    url: 'https://four-k.test',
                    credential: 'k',
                  ),
                )
              : settings,
        ),
        tracearrClientForProvider.overrideWith(
          (ref, id) => id == 'tracearr-2' ? second : first,
        ),
        dashboardDecisionSourceProvider.overrideWith((ref, source) async {
          sourceReads.add(source);
          return (
            decisions: const <DashboardDecision>[],
            coverage: SourceCoverage.none,
          );
        }),
      ],
      // As the run with no screen builds its own.
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<OutsideHeard> run(
    ProviderContainer container, {
    required int minutes,
    bool speak = true,
    Set<OutsideNoticeKind> enabled = const {OutsideNoticeKind.flagged},
  }) => OutsideRun(
    shelf: shelf,
    clock: () => start.add(Duration(minutes: minutes)),
  ).run(container, speak: speak, enabled: enabled, probe: false);

  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  Future<Map<String, DateTime>> cursors() async => {
    // Read back in the zone of the machine: an instant is what is kept.
    for (final MapEntry(:key, :value)
        in (await shelf.readSaid()).flaggedSince.entries)
      key: value.toUtc(),
  };

  group('the first run', () {
    test(
      'says nothing of what Tracearr already holds, and starts there',
      () async {
        first.hold([
          _violation('old', at(-600)),
          _violation('older', at(-900)),
        ]);
        final heard = await run(await container(), minutes: 0);
        expect(heard.say, isEmpty);
        expect((await cursors())['tracearr'], at(-600));
        expect(first.reads, [(pageSize: 1, since: null)]);
      },
    );

    test(
      'with nothing held starts from the beginning, so the first is news',
      () async {
        final box = await container();
        expect((await run(box, minutes: 0)).say, isEmpty);
        expect((await cursors())['tracearr'], flaggedFromTheStart);
        first.hold([_violation('a', at(5))]);
        final heard = await run(box, minutes: 15);
        expect(heard.say.map((notice) => notice.id), ['a']);
      },
    );

    test(
      'a Tracearr added later starts quietly too, on its own cursor',
      () async {
        first.hold([_violation('a', at(-10))]);
        await run(await container(), minutes: 0);
        second.hold([_violation('b', at(-5))]);
        final heard = await run(
          await container(twoConnections: true),
          minutes: 15,
        );
        expect(heard.say, isEmpty);
        expect((await cursors())['tracearr-2'], at(-5));
        expect((await cursors())['tracearr'], at(-10));
      },
    );
  });

  group('a first run that cannot place itself', () {
    test('violations with no time start no cursor, and the next run does not '
        'read from the start of time', () async {
      first.hold([_violation('old', at(-600)), _violation('older', at(-900))]);
      first.undated = true;
      final box = await container();
      final heard = await run(box, minutes: 0);
      expect(heard.say, isEmpty);
      expect((await cursors()).containsKey('tracearr'), isFalse);

      // Still a first run: it reads the newest one again, and says nothing.
      first.reads.clear();
      final next = await run(box, minutes: 15);
      expect(next.say, isEmpty);
      expect(first.reads, [(pageSize: 1, since: null)]);

      // Once Tracearr sends a time, it places itself there.
      first.undated = false;
      await run(box, minutes: 30);
      expect((await cursors())['tracearr'], at(-600));
    });
  });

  group('the runs after', () {
    test('ask since the cursor and say what is new, once', () async {
      first.hold([_violation('old', at(-10))]);
      final box = await container();
      await run(box, minutes: 0);

      first.hold([_violation('a', at(7)), _violation('old', at(-10))]);
      final heard = await run(box, minutes: 15);
      expect(first.reads.last, (
        pageSize: kTracearrFlaggedPage,
        since: at(-10),
      ));
      expect(heard.say.map((notice) => notice.id), ['a']);
      expect(heard.say.single.title, 'Flagged');
      expect((await cursors())['tracearr'], at(7));

      // Tracearr's `since` is inclusive: it answers the one the cursor is
      // taken from, and nobody hears it twice.
      final quiet = await run(box, minutes: 30);
      expect(first.reads.last.since, at(7));
      expect(quiet.say, isEmpty);
    });

    test('several are one notice that opens the Violations tab', () async {
      final box = await container();
      await run(box, minutes: 0);
      first.hold([
        _violation('c', at(12), person: 'Marco'),
        _violation('b', at(8)),
        _violation('a', at(3)),
      ]);
      final heard = await run(box, minutes: 15);
      expect(heard.say, hasLength(1));
      expect(heard.say.single.body, contains('3 new violations'));
      expect(heard.say.single.route, '/stack/tracearr/violations?i=tracearr');
    });

    test('one is a notice that opens that violation', () async {
      final box = await container();
      await run(box, minutes: 0);
      first.hold([_violation('a', at(3))]);
      final heard = await run(box, minutes: 15);
      expect(heard.say.single.route, '/stack/tracearr/violations/a?i=tracearr');
    });

    test(
      'each connection has its own cursor, and one that is silent keeps it',
      () async {
        first.hold([_violation('x', at(-30))]);
        second.hold([_violation('y', at(-20))]);
        final box = await container(twoConnections: true);
        await run(box, minutes: 0);

        first.hold([_violation('a', at(5)), _violation('x', at(-30))]);
        second.fails = true;
        final heard = await run(box, minutes: 15);
        expect(heard.say.map((notice) => notice.id), ['a']);
        expect((await cursors())['tracearr'], at(5));
        expect(
          (await cursors())['tracearr-2'],
          at(-20),
          reason: 'a read that did not answer is not one that was made',
        );

        second.fails = false;
        second.hold([_violation('b', at(9)), _violation('y', at(-20))]);
        final later = await run(box, minutes: 30);
        expect(later.say.single.body, contains('Tracearr 4K'));
        expect(later.say.single.id, 'b');
      },
    );

    test(
      'Tracearr silent on the only connection says nothing and keeps its place',
      () async {
        final box = await container();
        await run(box, minutes: 0);
        first.fails = true;
        final heard = await run(box, minutes: 15);
        expect(heard.say, isEmpty);
        expect((await cursors())['tracearr'], flaggedFromTheStart);
        first.fails = false;
        first.hold([_violation('a', at(10))]);
        expect((await run(box, minutes: 30)).say, hasLength(1));
      },
    );

    test(
      'the app on the screen reads nothing it already has a cursor for',
      () async {
        first.hold([_violation('old', at(-10))]);
        final box = await container();
        await run(box, minutes: 0);
        final reads = first.reads.length;

        first.hold([_violation('a', at(3))]);
        final looked = await run(box, minutes: 5, speak: false);
        expect(looked.say, isEmpty);
        expect(
          first.reads,
          hasLength(reads),
          reason: 'nothing asked, nothing swallowed',
        );
        expect((await cursors())['tracearr'], at(-10));

        expect((await run(box, minutes: 15)).say.map((n) => n.id), ['a']);
      },
    );

    test('the app on the screen gives a connection its first cursor', () async {
      first.hold([_violation('old', at(-10))]);
      final box = await container();
      final looked = await run(box, minutes: 0, speak: false);
      expect(looked.say, isEmpty);
      expect((await cursors())['tracearr'], at(-10));
      first.hold([_violation('a', at(3)), _violation('old', at(-10))]);
      expect((await run(box, minutes: 15)).say, hasLength(1));
    });

    test(
      'settings that look empty for one run do not make the next a first run',
      () async {
        first.hold([_violation('old', at(-10))]);
        await run(await container(), minutes: 0);

        // A headless start whose settings did not load: Flagged is on, no
        // Tracearr is there to read.
        await run(await container(configured: false), minutes: 15);
        expect((await cursors())['tracearr'], at(-10));

        // What came in between is still news once the settings are back.
        first.hold([_violation('a', at(7)), _violation('old', at(-10))]);
        final heard = await run(await container(), minutes: 30);
        expect(heard.say.map((notice) => notice.id), ['a']);
      },
    );

    test('a connection that is gone is forgotten by the next read', () async {
      first.hold([_violation('x', at(-30))]);
      second.hold([_violation('y', at(-20))]);
      await run(await container(twoConnections: true), minutes: 0);
      expect(
        (await cursors()).keys,
        unorderedEquals(['tracearr', 'tracearr-2']),
      );
      await run(await container(), minutes: 15);
      expect((await cursors()).keys, ['tracearr']);
    });

    test('a read that stopped on a full page says a floor', () async {
      final box = await container();
      await run(box, minutes: 0);
      first.hold([
        for (var i = 0; i < kTracearrFlaggedPage; i++)
          _violation('v$i', at(i + 1)),
      ]);
      first.fullPage = true;
      final heard = await run(box, minutes: 15);
      expect(
        heard.say.single.body,
        startsWith('$kTracearrFlaggedPage+ new violations'),
      );
    });
  });

  group('what it never asks', () {
    test('with its switch off, Tracearr is not asked a thing', () async {
      first.hold([_violation('a', at(3))]);
      final box = await container();
      await run(box, minutes: 0, enabled: const {});
      await run(box, minutes: 15, enabled: const {OutsideNoticeKind.needsYou});
      expect(first.reads, isEmpty);
      expect(await cursors(), isEmpty);
    });

    test(
      'with no Tracearr set up, nothing is asked and no cursor is kept',
      () async {
        final box = await container(configured: false);
        final heard = await run(box, minutes: 0);
        expect(heard.say, isEmpty);
        expect(first.reads, isEmpty);
        expect(await cursors(), isEmpty);
      },
    );

    test('Needs you in the background does not read violations', () async {
      first.hold([_violation('a', at(3))]);
      final box = await container();
      await run(box, minutes: 0, enabled: const {OutsideNoticeKind.needsYou});
      expect(sourceReads, isNotEmpty);
      expect(sourceReads, isNot(contains(DecisionSource.violations)));
      expect(first.reads, isEmpty);
    });

    test('with both on, violations are read once, by Flagged alone', () async {
      first.hold([_violation('a', at(3))]);
      final box = await container();
      const both = {OutsideNoticeKind.needsYou, OutsideNoticeKind.flagged};
      await run(box, minutes: 0, enabled: both);
      expect(
        first.reads,
        hasLength(1),
        reason: 'its first run: the newest one',
      );
      first.reads.clear();
      await run(box, minutes: 15, enabled: both);
      expect(first.reads, hasLength(1));
      expect(sourceReads, isNot(contains(DecisionSource.violations)));
    });

    test(
      'switched off and on again, it starts from what is there then',
      () async {
        final box = await container();
        await run(box, minutes: 0);
        await run(box, minutes: 15, enabled: const {});
        expect(await cursors(), isEmpty);
        first.hold([_violation('during', at(20))]);
        final on = await run(box, minutes: 30);
        expect(
          on.say,
          isEmpty,
          reason: 'what came while it was off is not news',
        );
        expect((await cursors())['tracearr'], at(20));
      },
    );
  });
}

/// A violation as Tracearr sends it. Its places and addresses are invented and
/// no assertion reads them.
TracearrViolation _violation(
  String id,
  DateTime? createdAt, {
  String person = 'Anna',
}) => TracearrViolation.fromJson({
  'id': id,
  'severity': 'warning',
  'created_at': createdAt?.toIso8601String(),
  'acknowledged_at': null,
  'rule': {'id': 'r1', 'name': 'Too many streams'},
  'server': {'id': 's1', 'name': 'Casa Emby', 'type': 'emby'},
  'user': {'id': 'u-$person', 'username': person},
  'data': {'ipAddress': '203.0.113.7'},
});

/// A Tracearr that keeps what a test holds and answers a violations read as
/// the real one does: newest first, from `since` inclusive, a page at a time.
class _Tracearr extends TracearrClient {
  _Tracearr() : super(baseUrl: 'http://tracearr.test', apiKey: 'trr_pub_test');

  var _held = <TracearrViolation>[];
  bool fails = false;

  /// Whether the violations come without a `created_at`.
  bool undated = false;

  /// Whether the page is reported as full, with another behind it.
  bool fullPage = false;

  final reads = <({int pageSize, DateTime? since})>[];

  void hold(List<TracearrViolation> violations) => _held = violations;

  @override
  Future<TracearrPage<TracearrViolation>> getViolations({
    String? cursor,
    int pageSize = 25,
    TracearrViolationFilter filter = const TracearrViolationFilter(),
  }) async {
    reads.add((pageSize: pageSize, since: filter.since?.toUtc()));
    if (fails) throw StateError('did not answer');
    final since = filter.since;
    final rows = [
      for (final violation in _held)
        if (since == null || !violation.createdAt!.isBefore(since)) violation,
    ]..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    final sent = undated
        ? [for (final violation in rows) _violation(violation.id, null)]
        : rows;
    return TracearrPage(
      items: sent.take(pageSize).toList(),
      nextCursor: fullPage || rows.length > pageSize ? 'next' : null,
    );
  }
}
