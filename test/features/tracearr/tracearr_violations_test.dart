/// Violations, whole: the tab's filters and the person a link narrows it to,
/// the violation's own page (typed for the rules we know, the name alone for
/// any other), the owner's two controls, and what Needs you holds.
///
/// **The lab has no violation yet**, so every violation here is made up: the
/// rows of `test/fixtures/tracearr/violations.json` and
/// `violation_detail.json`, whose places and addresses are invented. What is
/// not invented is the shape of their `data`: its keys are the ones Tracearr
/// 3.1.4's server writes (`data.evidence`, groups of conditions, each told by
/// its `field`), read from its source and recorded in the probe notes, though
/// never yet captured from a live violation. No test name, and no failure
/// text, carries a place or an address.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_needs_you_page.dart';
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/violation_rows.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_accounts.dart';
import 'package:cupola/features/tracearr/data/tracearr_violation_owner.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_owner_session.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_overview_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_person_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violation_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_screen.dart';

import '../../test_helpers/fake_tracearr_owner.dart';
import '../../test_helpers/fixtures.dart';
import '../../test_helpers/profiles/profiles.dart';

/// A UUID, which is what Tracearr's `user_id` accepts.
const _personId = '7a3e91c4-5d28-4b6f-8e10-2f4a6c8d0b13';

final _household = Profiles.p1.withConnection(WorldConnections.tracearr);

/// The id of the test violation called [name]: a UUID, as every id Tracearr
/// gives is (the screens refuse any other before asking), the same one every
/// time. FNV-1a over the name, so two names never share one in practice.
String _idOf(String name) {
  var hash = 0x811c9dc5;
  for (final unit in name.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return '${hash.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-'
      '000000000000';
}

/// The id of the demo world's violation number [n].
String _demoViolation(int n) => '00000000-0000-4000-8000-00000000000$n';

/// What Tracearr 3.x writes in a violation's `data`: the conditions its engine
/// weighed, each told by its `field`, with the figure it measured (`actual`)
/// and the one it was held to (`threshold`). [extra] is what else the run
/// keeps beside them (an address, a title), which never reaches the screen.
Map<String, Object?> _evidenceOf(
  String field,
  String operator, {
  required Object threshold,
  required Object actual,
  Map<String, Object?>? details,
  bool matched = true,
  Map<String, Object?> extra = const {},
}) => {
  'evidence': [
    {
      'groupIndex': 0,
      'matched': matched,
      'match': 'all',
      'conditions': [
        {
          'field': field,
          'operator': operator,
          'threshold': threshold,
          'actual': actual,
          'matched': matched,
          'details': ?details,
        },
      ],
    },
  ],
  'relatedSessionIds': const <String>[],
  'matchedGroups': const [0],
  ...extra,
};

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

/// The rows of `violations.json`: impossible travel (high, unseen), too many
/// streams (acknowledged) and a rule of the owner's own (low, unseen).
List<TracearrViolation> _rows() => [
  for (final row
      in (jsonFixtureMap('tracearr/violations.json')['data'] as List))
    TracearrViolation.fromJson((row as Map).cast<String, Object?>()),
];

/// `violation_detail.json`: the same impossible travel, with the three actions
/// Tracearr took (one notified, one failed, one skipped).
TracearrViolation _detail() => TracearrViolation.fromJson(
  jsonFixtureMap('tracearr/violation_detail.json').cast<String, Object?>(),
);

/// A violation of [rule] with the [data] given, unseen unless [seen].
TracearrViolation _violation(
  String id, {
  String rule = 'Rule',
  TracearrSeverity severity = TracearrSeverity.high,
  bool seen = false,
  Map<String, Object?> data = const {},
  List<Map<String, Object?>> actions = const [],
  String person = 'anna',
  DateTime? at,
}) => TracearrViolation.fromJson({
  'id': _idOf(id),
  'severity': severity.name,
  'created_at': (at ?? DateTime.utc(2026, 10, 9, 17, 30)).toIso8601String(),
  'acknowledged_at': seen ? '2026-10-09T18:00:00.000Z' : null,
  'session_id': null,
  'rule': {'id': 'rule-$id', 'name': rule},
  'server': {'id': 'server-1', 'name': 'Plex Living Room', 'type': 'plex'},
  'user': {'id': _personId, 'username': person},
  'data': data,
  'actions': actions,
});

/// Tracearr as the violation screens read it: the rows a test hands it, the
/// filter and page size of every list read, and the single reads by id.
class _Client extends TracearrClient {
  _Client({this.violations = const [], this.single = const []})
    : super(baseUrl: 'http://tracearr.test', apiKey: 'trr_pub_test');

  /// What the server lists now: a test that plays the owner's decision takes a
  /// violation off it, as Tracearr stops listing one that was acknowledged.
  List<TracearrViolation> violations;
  final List<TracearrViolation> single;

  /// Whether the read Needs you makes (the unseen of severity high) does not
  /// answer.
  bool failFlagged = false;

  final filters = <TracearrViolationFilter>[];
  final pageSizes = <int>[];

  @override
  Future<TracearrPage<TracearrViolation>> getViolations({
    String? cursor,
    int pageSize = 25,
    TracearrViolationFilter filter = const TracearrViolationFilter(),
  }) async {
    filters.add(filter);
    pageSizes.add(pageSize);
    if (failFlagged && filter.severity == TracearrSeverity.high) {
      throw StateError('did not answer');
    }
    return TracearrPage(items: violations);
  }

  /// The ids a single read was made for.
  final singleReads = <String>[];

  @override
  Future<TracearrViolation?> getViolation(String id) async {
    singleReads.add(id);
    for (final violation in [...single, ...violations]) {
      if (violation.id == id) return violation;
    }
    return null;
  }

  @override
  Future<TracearrUser?> getUser(String id) async =>
      TracearrUser(id: id, username: 'anna');

  // The person's page reads these two too: nothing to show, nothing failing.
  @override
  Future<TracearrUserStats?> getUserStats(String id) async => null;

  @override
  Future<TracearrPage<TracearrHistoryEntry>> getHistory({
    String? cursor,
    int pageSize = 25,
    TracearrHistoryFilter filter = const TracearrHistoryFilter(),
  }) async => const TracearrPage(items: []);
}

/// A Tracearr that lists two pages, the second held until a test lets it go,
/// so a later page can answer after the filter has moved on.
class _TwoPages extends _Client {
  _TwoPages({required this.first, required this.second});

  final TracearrViolation first;
  final TracearrViolation second;
  final secondPage = Completer<void>();

  @override
  Future<TracearrPage<TracearrViolation>> getViolations({
    String? cursor,
    int pageSize = 25,
    TracearrViolationFilter filter = const TracearrViolationFilter(),
  }) async {
    filters.add(filter);
    if (cursor == null) {
      return TracearrPage(items: [first], nextCursor: 'next');
    }
    await secondPage.future;
    return TracearrPage(items: [second]);
  }
}

/// The owner's two writes, answering with [outcome] and keeping what was asked.
class _Owner implements TracearrViolationOwner {
  _Owner(this.outcome, {this.onDecided});

  final TracearrOwnerOutcome outcome;
  final asked = <String>[];

  /// Hears the id of a violation the owner acted on, for a test whose server
  /// stops listing it.
  final void Function(String id)? onDecided;

  @override
  Future<TracearrOwnerOutcome> acknowledge(String violationId) async {
    asked.add('acknowledge $violationId');
    onDecided?.call(violationId);
    return outcome;
  }

  @override
  Future<TracearrOwnerOutcome> dismiss(String violationId) async {
    asked.add('dismiss $violationId');
    onDecided?.call(violationId);
    return outcome;
  }
}

class _Opener implements BrowserOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }

  @override
  Future<void> close() async {}
}

/// One screen, on the household, with no router.
Future<ProfileHarness> _pump(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
}) => pumpWithProfile(
  tester,
  _household,
  child: Scaffold(body: screen),
  overrides: overrides,
  surfaceSize: const Size(430, 3000),
);

/// The whole app, on the household, with its own router.
Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester, {
  List<Override> overrides = const [],
  ConfigProfile? profile,
}) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(
    profile ?? _household,
    now: _now,
    overrides: [
      arrivalsClockProvider.overrideWith(
        (ref) =>
            () => _now,
      ),
      stallClockProvider.overrideWith(
        (ref) =>
            () => _now,
      ),
      ...overrides,
    ],
  );
  harness.network.followFakeTime(tester.binding);
  final container = harness.container();
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await _answer(tester);
  return (harness, router, container);
}

Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(
  WidgetTester tester,
  ProfileHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await harness.unmount(tester);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pump();
  await tester.tap(target.first);
  await _answer(tester);
}

void main() {
  group('the list', () {
    testWidgets('opens on the unseen of any severity, and says so in pills', (
      tester,
    ) async {
      final client = _Client(violations: _rows());
      final harness = await _pump(
        tester,
        const TracearrViolationsScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      expect(client.filters.single.acknowledged, isFalse);
      expect(client.filters.single.severity, isNull);
      expect(client.filters.single.userId, isNull);
      for (final word in ['Unseen', 'All', 'Any severity']) {
        expect(find.text(word), findsOneWidget);
      }
      // The severity pills say the same three words the rows do.
      for (final word in ['Low', 'Warning', 'High']) {
        expect(
          find.descendant(
            of: find.byType(SelectionPills<TracearrSeverity?>),
            matching: find.text(word),
          ),
          findsOneWidget,
        );
      }
      await harness.unmount(tester);
    });

    testWidgets('a severity is asked of the server, and Any takes it off', (
      tester,
    ) async {
      final client = _Client(violations: _rows());
      final harness = await _pump(
        tester,
        const TracearrViolationsScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      await tester.tap(
        find.descendant(
          of: find.byType(SelectionPills<TracearrSeverity?>),
          matching: find.text('High'),
        ),
      );
      await harness.settle(tester);
      expect(client.filters.last.severity, TracearrSeverity.high);
      expect(client.filters.last.acknowledged, isFalse);

      await tester.tap(find.text('All'));
      await harness.settle(tester);
      expect(client.filters.last.severity, TracearrSeverity.high);
      expect(client.filters.last.acknowledged, isNull);

      await tester.tap(find.text('Any severity'));
      await harness.settle(tester);
      expect(client.filters.last.severity, isNull);
      await harness.unmount(tester);
    });

    testWidgets('a narrowed list that is empty says it is the filters', (
      tester,
    ) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrViolationsScreen(),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      expect(find.text('Nothing unseen'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(SelectionPills<TracearrSeverity?>),
          matching: find.text('Low'),
        ),
      );
      await harness.settle(tester);

      expect(find.text('No violations match'), findsOneWidget);
      expect(find.text('Nothing unseen'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('?user= narrows to a person, names them and lets go', (
      tester,
    ) async {
      final client = _Client(violations: _rows());
      final harness = await _pump(
        tester,
        const TracearrViolationsScreen(userId: _personId),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      expect(client.filters.single.userId, _personId);
      expect(find.text("Only anna's violations"), findsOneWidget);

      await tester.tap(find.text('Show everyone'));
      await harness.settle(tester);

      expect(client.filters.last.userId, isNull);
      expect(find.textContaining('Only '), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a ?user= that is not a Tracearr id is left out, since the '
        'server would answer it with a 400', (tester) async {
      final client = _Client(violations: _rows());
      final harness = await _pump(
        tester,
        const TracearrViolationsScreen(userId: 'not-an-id'),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      expect(client.filters.single.userId, isNull);
      expect(find.text('Show everyone'), findsNothing);
      expect(tracearrUserParam(null), isNull);
      expect(tracearrUserParam('  $_personId '), _personId);
      await harness.unmount(tester);
    });

    testWidgets('a row opens its violation, which a link opens cold', (
      tester,
    ) async {
      final (harness, router, container) = await _app(tester);
      router.go(ServiceRoutes.tracearrViolations);
      await _answer(tester);

      // The lab world: Anna on two servers at once, and a rule of the owner's
      // own, both unseen.
      expect(find.byType(ServiceRecordRow), findsNWidgets(2));
      await _tap(tester, find.text('Concurrent streams'));

      expect(
        router.state.uri.path,
        ServiceRoutes.tracearrViolation(_demoViolation(1)),
      );
      expect(find.byType(TracearrViolationScreen), findsOneWidget);
      // The invented stream counts the demo world's rule carries.
      expect(find.text('2 streams at once'), findsOneWidget);
      expect(find.text('The limit is 1'), findsOneWidget);

      // A cold deep link resolves from the path alone, and a blank id goes
      // back to the tab.
      router.go(ServiceRoutes.tracearrViolation(_demoViolation(2)));
      await _answer(tester);
      expect(find.byType(TracearrViolationScreen), findsOneWidget);
      expect(
        find.text('Only Tracearr shows what this rule saw'),
        findsOneWidget,
      );
      router.go('${ServiceRoutes.tracearrViolations}/%20');
      await _answer(tester);
      expect(router.state.uri.path, ServiceRoutes.tracearrViolations);
      expect(find.byType(TracearrViolationsScreen), findsOneWidget);

      // A link names a person.
      router.go(ServiceRoutes.tracearrViolationsOf(_personId));
      await _answer(tester);
      expect(router.state.uri.queryParameters['user'], _personId);
      expect(find.byType(TracearrViolationsScreen), findsOneWidget);

      // A notification of several names the Tracearr they came off.
      router.go(ServiceRoutes.tracearrViolationsOn('tracearr'));
      await _answer(tester);
      expect(
        tester
            .widget<TracearrViolationsScreen>(
              find.byType(TracearrViolationsScreen),
            )
            .instanceId,
        'tracearr',
      );
      await _close(tester, harness, container);
    });

    testWidgets('a person\'s page leads here with their id, and the real tab '
        'asks the server for them alone', (tester) async {
      final client = _Client(violations: _rows());
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      router.go('${ServiceRoutes.tracearrUsers}/$_personId');
      await _answer(tester);
      expect(find.byType(TracearrPersonScreen), findsOneWidget);
      expect(client.filters.where((f) => f.userId != null), isEmpty);

      await _tap(tester, find.widgetWithText(OutlinedButton, 'Violations'));

      expect(router.state.uri.path, ServiceRoutes.tracearrViolations);
      expect(router.state.uri.queryParameters['user'], _personId);
      expect(find.byType(TracearrViolationsScreen), findsOneWidget);
      expect(client.filters.last.userId, _personId);
      expect(find.text("Only anna's violations"), findsOneWidget);
      await _close(tester, harness, container);
    });

    testWidgets('a violation that is gone says so, after one read', (
      tester,
    ) async {
      final client = _Client();
      const unknown = '5e1f0a22-93c4-4b7d-a0e8-6d2b9c4f1a77';
      final harness = await _pump(
        tester,
        const TracearrViolationScreen(violationId: unknown),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      expect(find.text('Violation not found'), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(client.singleReads, [unknown]);
      await harness.unmount(tester);
    });

    testWidgets('a Tracearr that is not set up says so on the violation page '
        'and reads nothing', (tester) async {
      final client = _Client(single: [_violation('n2')]);
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1,
        child: Scaffold(
          body: TracearrViolationScreen(violationId: _idOf('n2')),
        ),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
        surfaceSize: const Size(430, 3000),
      );

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(client.singleReads, isEmpty);
      await harness.unmount(tester);
    });

    testWidgets('a link naming a connection that is gone reads the active one '
        'instead', (tester) async {
      final shown = _violation('k1', rule: 'Too many streams');
      final client = _Client(single: [shown]);
      final harness = await _pump(
        tester,
        TracearrViolationScreen(
          violationId: shown.id,
          instanceId: 'a-connection-removed-since',
        ),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      expect(client.singleReads, [shown.id]);
      expect(find.text('Too many streams'), findsWidgets);
      expect(find.text('Violation not found'), findsNothing);
      expect(find.byType(AppErrorState), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('an id that is not a UUID is not found with no request, as an '
        'old link or a bad payload would send it', (tester) async {
      final client = _Client();
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );

      for (final id in ['abc', '1234', 'not-a-uuid-at-all']) {
        router.go(ServiceRoutes.tracearrViolation(id));
        await _answer(tester);

        expect(
          find.byType(TracearrViolationScreen),
          findsOneWidget,
          reason: id,
        );
        expect(find.text('Violation not found'), findsOneWidget, reason: id);
        expect(find.byType(AppErrorState), findsNothing, reason: id);
      }
      expect(client.singleReads, isEmpty, reason: 'Tracearr would say 400');
      await _close(tester, harness, container);
    });
  });

  group('the list, paged', () {
    for (final (what, change) in <(String, void Function(ProviderContainer))>[
      (
        'the severity',
        (c) => c
            .read(tracearrViolationSeverityProvider.notifier)
            .choose(TracearrSeverity.high),
      ),
      (
        'the scope',
        (c) => c
            .read(tracearrViolationScopeProvider.notifier)
            .choose(TracearrViolationScope.all),
      ),
    ]) {
      test('a next page that answers after $what changed is dropped', () async {
        final client = _TwoPages(
          first: _violation('p1'),
          second: _violation('p2'),
        );
        final container = ProviderContainer(
          overrides: [tracearrClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);
        final list = tracearrViolationsListProvider(null);
        container.listen(list, (_, _) {});
        await container.read(list.future);
        final late = container.read(list.notifier).loadMore();
        await Future<void>.delayed(Duration.zero);

        change(container);
        final fresh = await container.read(list.future);
        expect(fresh.items.map((v) => v.id), [_idOf('p1')]);

        client.secondPage.complete();
        await late;

        final after = container.read(list).requireValue;
        expect(after.items.map((v) => v.id), [_idOf('p1')]);
        expect(after.nextCursor, 'next', reason: 'the new list is on page one');
        expect(after.loadingMore, isFalse);
      });
    }
  });

  group('the detail', () {
    Future<ProfileHarness> pumpDetail(
      WidgetTester tester,
      TracearrViolation violation, {
      _Opener? opener,
    }) => _pump(
      tester,
      TracearrViolationScreen(violationId: violation.id),
      overrides: [
        tracearrClientProvider.overrideWithValue(_Client(single: [violation])),
        if (opener != null) browserOpenerProvider.overrideWithValue(opener),
      ],
    );

    testWidgets('impossible travel: the two places, the distance and the '
        'time between', (tester) async {
      final harness = await pumpDetail(tester, _detail());

      expect(find.text('Valmora, Nordavia'), findsOneWidget);
      expect(find.text('Port Aster, Eastmark'), findsOneWidget);
      expect(find.text('First stream'), findsOneWidget);
      expect(find.text('Second stream'), findsOneWidget);
      expect(find.text('${withUnit('5,120', 'km')} apart'), findsOneWidget);
      expect(
        find.text(
          '${formatTimeSpan(const Duration(minutes: 90))} between the two '
          'streams',
        ),
        findsOneWidget,
      );
      // The address that came with them is never drawn, nor a raw key.
      expect(find.textContaining('192.0.2.'), findsNothing);
      expect(find.textContaining('travel_speed_kmh'), findsNothing);
      expect(find.textContaining('timeDeltaHours'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('concurrent streams: how many and the limit', (tester) async {
      final harness = await pumpDetail(
        tester,
        _violation(
          'c1',
          rule: 'Too many streams',
          data: _evidenceOf(
            'concurrent_streams',
            'gt',
            threshold: 2,
            actual: 4,
            extra: {'ipAddress': '192.0.2.45'},
          ),
        ),
      );

      expect(find.text('4 streams at once'), findsOneWidget);
      expect(find.text('The limit is 2'), findsOneWidget);
      expect(find.textContaining('192.0.2.'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a rule we do not know shows its name and the way to open '
        'Tracearr, never its keys and values', (tester) async {
      final opener = _Opener();
      final harness = await pumpDetail(
        tester,
        _violation(
          'u1',
          rule: 'Night owl',
          // Two figures that look like a count and a limit, on a rule that is
          // not the one that reads them.
          data: _evidenceOf(
            'unique_ips_in_window',
            'gt',
            threshold: 3,
            actual: 5,
            details: {
              'ips': ['192.0.2.60'],
              'count': 5,
              'limit': 3,
              'city': 'Valmora',
            },
            extra: {'ipAddress': '192.0.2.60'},
          ),
        ),
        opener: opener,
      );

      // The name, as the page's title and in its first row.
      expect(find.text('Night owl'), findsWidgets);
      expect(
        find.text('Only Tracearr shows what this rule saw'),
        findsOneWidget,
      );
      for (final leak in ['Valmora', '192.0.2.', 'ipAddress', 'unique_ips']) {
        expect(find.textContaining(leak), findsNothing, reason: 'a raw value');
      }

      await tester.ensureVisible(find.text('Open in Tracearr'));
      await tester.tap(find.text('Open in Tracearr'));
      await tester.pump();
      expect(opener.opened.single.host, 'tower.home.arpa');
      expect(opener.opened.single.path, '/violations/${_idOf('u1')}');
      await harness.unmount(tester);
    });

    testWidgets('a failed automatic action is the fault, amber, with what '
        'failed; a skipped one rests', (tester) async {
      final harness = await pumpDetail(tester, _detail());
      final context = tester.element(find.text('Ended the stream'));
      final colorScheme = Theme.of(context).colorScheme;
      final amber = statusToneColor(
        colorScheme,
        StatusTone.warning,
        surface: colorScheme.surfaceContainerLow,
      );

      expect(find.text('Sent a notification'), findsOneWidget);
      expect(find.text('Ended the stream'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Plex Living Room did not answer'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Ended the stream')).style?.color,
        amber,
      );
      // The notification that went through and the skip are not amber.
      expect(
        tester.widget<Text>(find.text('Sent a notification')).style?.color,
        isNot(amber),
      );
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Cooldown'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Notify admins')).style?.color,
        isNot(amber),
      );
      await harness.unmount(tester);
    });

    testWidgets('an unseen violation is blue whatever its severity, and an '
        'acknowledged one rests', (tester) async {
      var harness = await pumpDetail(tester, _violation('s1', rule: 'Loud'));
      var context = tester.element(find.text('Unseen'));
      var colorScheme = Theme.of(context).colorScheme;
      final blue = statusToneColor(
        colorScheme,
        StatusTone.info,
        surface: colorScheme.surfaceContainerLow,
      );
      final neutral = statusToneColor(
        colorScheme,
        StatusTone.neutral,
        surface: colorScheme.surfaceContainerLow,
      );
      expect(find.text('High'), findsWidgets);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byType(ServiceOverviewRow).first,
                matching: find.text('Loud'),
              ),
            )
            .style
            ?.color,
        blue,
      );
      await harness.unmount(tester);

      harness = await pumpDetail(
        tester,
        _violation('s2', rule: 'Loud', seen: true),
      );
      context = tester.element(find.textContaining('Acknowledged'));
      colorScheme = Theme.of(context).colorScheme;
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byType(ServiceOverviewRow).first,
                matching: find.text('Loud'),
              ),
            )
            .style
            ?.color,
        neutral,
      );
      // Nothing left to acknowledge, and Dismiss stays.
      expect(find.text('Acknowledge'), findsNothing);
      expect(find.text('Dismiss'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('no automatic action is said, not left blank', (tester) async {
      final harness = await pumpDetail(tester, _violation('n1'));
      expect(find.text('Tracearr took no automatic action'), findsOneWidget);
      await harness.unmount(tester);
    });

    test('nothing the violation holds reaches toString', () {
      final text = [_detail(), _detail().impossibleTravel].join(' ');
      for (final secret in ['Valmora', 'Port Aster', '192.0.2.', 'anna']) {
        expect(text, isNot(contains(secret)));
      }
    });
  });

  group('Acknowledge and Dismiss', () {
    Future<(ProfileHarness, GoRouter, ProviderContainer)> detail(
      WidgetTester tester, {
      _Owner? owner,
      TracearrViolation? violation,
    }) async {
      final shown = violation ?? _violation('o1', rule: 'Too many streams');
      final app = await _app(
        tester,
        overrides: [
          tracearrClientProvider.overrideWithValue(_Client(single: [shown])),
          if (owner != null)
            tracearrViolationOwnerProvider.overrideWith((ref, id) => owner),
        ],
      );
      app.$2.go(ServiceRoutes.tracearrViolation(shown.id));
      await _answer(tester);
      return app;
    }

    testWidgets('without the owner both are dimmed, hinted, big enough and '
        'still tappable, and the tap leads to the connection', (tester) async {
      final (harness, router, container) = await detail(tester);

      for (final label in ['Acknowledge', 'Dismiss']) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.bySubtype<ButtonStyleButton>(),
        );
        expect(button, findsOneWidget, reason: label);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
        // Never `onPressed: null`: a disabled node is skipped by a screen
        // reader.
        expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
        final semantics = tester.getSemantics(button);
        expect(semantics.label, label);
        expect(semantics.hint, kTracearrOwnerHint);
        expect(
          semantics.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        final dim = tester.widget<Opacity>(
          find.descendant(of: button, matching: find.byType(Opacity)),
        );
        expect(dim.opacity, GatedAffordance.dimmedOpacity);
      }

      await _tap(tester, find.text('Acknowledge'));
      expect(
        router.state.uri.path,
        ServiceRoutes.settingsFor(ServiceKey.tracearr),
      );
      await _close(tester, harness, container);
    });

    testWidgets('Dismiss without the owner leads to the same place and asks '
        'nothing first', (tester) async {
      final (harness, router, container) = await detail(tester);

      await _tap(tester, find.text('Dismiss'));

      expect(
        router.state.uri.path,
        ServiceRoutes.settingsFor(ServiceKey.tracearr),
      );
      expect(find.text('Dismiss this violation?'), findsNothing);
      await _close(tester, harness, container);
    });

    testWidgets('with the owner, Acknowledge acts at full ink', (tester) async {
      final owner = _Owner(TracearrOwnerOutcome.done);
      final (harness, router, container) = await detail(tester, owner: owner);
      final button = find.ancestor(
        of: find.text('Acknowledge'),
        matching: find.bySubtype<ButtonStyleButton>(),
      );
      expect(
        find.descendant(of: button, matching: find.byType(Opacity)),
        findsNothing,
      );

      await _tap(tester, find.text('Acknowledge'));

      expect(owner.asked, ['acknowledge ${_idOf('o1')}']);
      expect(find.text('Acknowledged'), findsOneWidget);
      expect(
        router.state.uri.path,
        ServiceRoutes.tracearrViolation(_idOf('o1')),
      );
      await _close(tester, harness, container);
    });

    for (final dismiss in [false, true]) {
      testWidgets('${dismiss ? 'Dismiss' : 'Acknowledge'} reads again what '
          'listed the violation: the tab, the unseen count and the latest', (
        tester,
      ) async {
        final owner = _Owner(TracearrOwnerOutcome.done);
        final shown = _violation('o2', rule: 'Too many streams');
        final client = _Client(single: [shown]);
        final (harness, router, container) = await _app(
          tester,
          overrides: [
            tracearrClientProvider.overrideWithValue(client),
            tracearrViolationOwnerProvider.overrideWith((ref, id) => owner),
          ],
        );
        // What the Overview and the tab hold, read once.
        await container.read(tracearrUnseenViolationsProvider.future);
        await container.read(tracearrLatestViolationsProvider.future);
        final before = client.filters.length;
        router.go(ServiceRoutes.tracearrViolation(shown.id));
        await _answer(tester);

        await _tap(tester, find.text(dismiss ? 'Dismiss' : 'Acknowledge'));
        if (dismiss) {
          await _tap(
            tester,
            find.widgetWithText(FilledButton, 'Dismiss violation'),
          );
        }
        expect(owner.asked, hasLength(1));
        // Each of the two reads is asked once more, for the figures that name
        // the violation to stop naming it.
        await container.read(tracearrUnseenViolationsProvider.future);
        await container.read(tracearrLatestViolationsProvider.future);
        expect(
          client.filters.length - before,
          greaterThanOrEqualTo(2),
          reason: 'the unseen count and the latest were read again',
        );
        await _close(tester, harness, container);
      });
    }

    testWidgets('Dismiss confirms with a verb, and Keep it does nothing', (
      tester,
    ) async {
      final owner = _Owner(TracearrOwnerOutcome.done);
      final (harness, router, container) = await detail(tester, owner: owner);

      await _tap(tester, find.text('Dismiss'));
      expect(find.text('Dismiss this violation?'), findsOneWidget);
      expect(
        find.text('Tracearr removes it and gives back the trust it cost anna.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Keep it'));
      expect(owner.asked, isEmpty);

      await _tap(tester, find.text('Dismiss'));
      await _tap(
        tester,
        find.widgetWithText(FilledButton, 'Dismiss violation'),
      );
      expect(owner.asked, ['dismiss ${_idOf('o1')}']);
      // Gone, so the page leaves to the list.
      expect(router.state.uri.path, ServiceRoutes.tracearrViolations);
      await _close(tester, harness, container);
    });

    for (final (outcome, sentence) in [
      (TracearrOwnerOutcome.signedOut, 'Signed out of Tracearr'),
      (TracearrOwnerOutcome.notOwner, 'Only the owner can acknowledge'),
      (TracearrOwnerOutcome.failed, 'Could not acknowledge this violation'),
    ]) {
      testWidgets('${outcome.name} says $sentence and keeps the page', (
        tester,
      ) async {
        final owner = _Owner(outcome);
        final (harness, router, container) = await detail(tester, owner: owner);

        await _tap(tester, find.text('Acknowledge'));

        expect(find.text(sentence), findsOneWidget);
        expect(
          router.state.uri.path,
          ServiceRoutes.tracearrViolation(_idOf('o1')),
        );
        expect(find.text('Acknowledge'), findsOneWidget);
        await _close(tester, harness, container);
      });
    }

    testWidgets('a Tracearr with no such route takes the controls off the '
        'page and leaves the rest', (tester) async {
      final owner = _Owner(TracearrOwnerOutcome.unavailable);
      final (harness, _, container) = await detail(tester, owner: owner);

      await _tap(tester, find.text('Acknowledge'));

      expect(find.text('Acknowledge'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      expect(find.text('Open in Tracearr'), findsWidgets);
      expect(find.text('Too many streams'), findsWidgets);
      await _close(tester, harness, container);
    });
  });

  group('the owner\'s session is the one the page acts with', () {
    // The real owner provider, over the fake Tracearr: the bearer held in the
    // connection's session reaches the two routes, and what Tracearr says
    // decides what the page draws.
    Future<(FakeTracearr, ProfileHarness, GoRouter, ProviderContainer)>
    signedIn(
      WidgetTester tester, {
      FakeTracearrRole role = FakeTracearrRole.owner,
      String? token,
      void Function(FakeTracearr server)? tune,
    }) async {
      final server = FakeTracearr()
        ..addAccount('anna', password: 'x', role: role, name: 'anna')
        ..violations.add(_idOf('o1'));
      tune?.call(server);
      final shown = _violation('o1', rule: 'Too many streams');
      final (harness, router, container) = await _app(
        tester,
        overrides: [
          tracearrClientProvider.overrideWithValue(_Client(single: [shown])),
          tracearrOwnerClientFactoryProvider.overrideWithValue(server.factory),
        ],
      );
      if (token != 'none') {
        await container.read(settingsProvider.notifier).update((settings) {
          final instance = settings.instanceById(WorldIds.tracearr)!;
          return settings.copyWithInstance(
            instance.copyWith(
              owner: TracearrOwnerSession(
                kind: TracearrOwnerKind.email,
                login: 'anna@example.test',
                displayName: 'anna',
                token: token ?? server.mint('anna'),
              ),
            ),
          );
        });
      }
      router.go(ServiceRoutes.tracearrViolation(shown.id));
      await _answer(tester);
      return (server, harness, router, container);
    }

    testWidgets('Acknowledge is a PATCH with the bearer, and says so', (
      tester,
    ) async {
      final (server, harness, _, container) = await signedIn(tester);

      await _tap(tester, find.text('Acknowledge'));

      final sent = server.to('PATCH', '/violations/${_idOf('o1')}').single;
      expect(sent.headers['authorization'], startsWith('Bearer tok-'));
      expect(server.acknowledged, {_idOf('o1')});
      expect(find.text('Acknowledged'), findsOneWidget);
      await _close(tester, harness, container);
    });

    testWidgets('Dismiss asks first, then is a DELETE with the bearer', (
      tester,
    ) async {
      final (server, harness, _, container) = await signedIn(tester);

      await _tap(tester, find.text('Dismiss'));
      expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await _tap(
        tester,
        find.widgetWithText(FilledButton, 'Dismiss violation'),
      );

      expect(server.to('DELETE', '/violations/${_idOf('o1')}'), hasLength(1));
      expect(server.dismissed, {_idOf('o1')});
      await _close(tester, harness, container);
    });

    testWidgets('a session Tracearr ended says so in blue words, empties the '
        'saved one and dims the controls again', (tester) async {
      final (_, harness, _, container) = await signedIn(
        tester,
        token: 'unknown.sig',
      );

      await _tap(tester, find.text('Acknowledge'));

      expect(find.text('Signed out of Tracearr'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);
      final owner = container
          .read(currentSettingsProvider)
          .instanceById(WorldIds.tracearr)!
          .owner!;
      expect(owner.isSignedIn, isFalse);
      expect(container.read(tracearrViolationOwnerProvider('')), isNull);
      await _close(tester, harness, container);
    });

    testWidgets('a member is told only the owner can, not that the route is '
        'gone', (tester) async {
      final (_, harness, _, container) = await signedIn(
        tester,
        role: FakeTracearrRole.member,
      );

      await _tap(tester, find.text('Acknowledge'));

      expect(find.text('Only the owner can acknowledge'), findsOneWidget);
      expect(find.text('Acknowledge'), findsOneWidget);
      await _close(tester, harness, container);
    });

    testWidgets('a Tracearr with no such route takes the controls off, for '
        'this page and the next', (tester) async {
      final (_, harness, router, container) = await signedIn(
        tester,
        tune: (server) => server.writesAbsent = true,
      );

      await _tap(tester, find.text('Dismiss'));
      await _tap(
        tester,
        find.widgetWithText(FilledButton, 'Dismiss violation'),
      );

      expect(find.text('Acknowledge'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      expect(find.text('Too many streams'), findsWidgets);
      router.go(ServiceRoutes.tracearrViolations);
      await _answer(tester);
      router.go(ServiceRoutes.tracearrViolation(_idOf('o1')));
      await _answer(tester);
      expect(find.text('Acknowledge'), findsNothing);
      await _close(tester, harness, container);
    });

    testWidgets('a schema that changed under us is the same as no route', (
      tester,
    ) async {
      final (_, harness, _, container) = await signedIn(
        tester,
        tune: (server) => server.writesSay = (status: 200, body: {'ok': true}),
      );

      await _tap(tester, find.text('Acknowledge'));

      expect(find.text('Acknowledge'), findsNothing);
      expect(
        find.text('This Tracearr cannot do that from Cupola.'),
        findsOneWidget,
      );
      await _close(tester, harness, container);
    });

    testWidgets('a violation already gone is said, never a failure', (
      tester,
    ) async {
      final (_, harness, _, container) = await signedIn(
        tester,
        tune: (server) => server.violations.clear(),
      );

      await _tap(tester, find.text('Acknowledge'));

      expect(
        find.text('Tracearr no longer has this violation'),
        findsOneWidget,
      );
      expect(find.textContaining('Could not'), findsNothing);
      await _close(tester, harness, container);
    });

    testWidgets('single sign-on alone, with nobody signed in, offers no '
        'dimmed control that cannot be kept', (tester) async {
      final (_, harness, _, container) = await signedIn(
        tester,
        token: 'none',
        tune: (server) => server
          ..local = false
          ..oidc = true,
      );

      expect(find.text('Acknowledge'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      expect(
        find.text(
          "This Tracearr signs in with single sign-on, which Cupola can't use.",
        ),
        findsOneWidget,
      );
      expect(find.text('Acknowledge it in Tracearr.'), findsOneWidget);
      await _close(tester, harness, container);
    });

    testWidgets('a Tracearr whose ways cannot be read keeps the dimmed '
        'controls', (tester) async {
      final (_, harness, _, container) = await signedIn(
        tester,
        token: 'none',
        tune: (server) => server.down = true,
      );

      expect(find.text('Acknowledge'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      await _close(tester, harness, container);
    });
  });

  group('Needs you', () {
    final high = [
      _violation(
        'h1',
        rule: 'Impossible travel',
        at: DateTime.utc(2026, 10, 9, 17, 53),
      ),
      _violation(
        'h2',
        rule: 'Too many streams',
        person: 'luca',
        at: DateTime.utc(2026, 10, 9, 15, 53),
      ),
    ];

    testWidgets('asks the server for the unseen of severity high, one page '
        'past the cap', (tester) async {
      final client = _Client(violations: high);
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      router.go(ServiceRoutes.activityNeedsYou);
      await _answer(tester);

      final asked = client.filters.where(
        (filter) => filter.severity == TracearrSeverity.high,
      );
      expect(asked, isNotEmpty);
      expect(asked.first.acknowledged, isFalse);
      expect(client.pageSizes, contains(kNeedsYouViolationCap + 1));
      await _close(tester, harness, container);
    });

    testWidgets('draws them in blue beside the faults, which they do not '
        'join, with the rule, the person and when', (tester) async {
      final client = _Client(violations: high);
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      router.go(ServiceRoutes.activityNeedsYou);
      await _answer(tester);

      expect(find.byType(ActivityNeedsYouPage), findsOneWidget);
      // The faults and the requests of the household are as they were.
      expect(find.text('3 faults'), findsOneWidget);
      expect(find.text('3 requests'), findsOneWidget);
      expect(find.byType(FaultCard), findsNWidgets(3));
      expect(find.text('2 violations'), findsOneWidget);
      expect(find.text('2 violations to review'), findsOneWidget);
      expect(find.byType(ViolationDecisionRow), findsNWidgets(2));
      expect(find.text('Impossible travel'), findsOneWidget);
      expect(find.textContaining('anna'), findsWidgets);
      expect(find.textContaining('luca'), findsWidgets);
      // No place and no address, only the rule, the person and when.
      expect(find.textContaining('192.0.2.'), findsNothing);

      final context = tester.element(find.text('2 violations'));
      final room = CupolaRoom.of(context);
      final blue = statusToneColor(
        Theme.of(context).colorScheme,
        StatusTone.info,
        surface: room.slab,
      );
      expect(tester.widget<Text>(find.text('2 violations')).style?.color, blue);
      expect(
        tester.widget<Text>(find.text('2 violations to review')).style?.color,
        blue,
      );
      await _close(tester, harness, container);
    });

    testWidgets('are decisions of their own kind, not faults, and never a '
        'notification of Needs you', (tester) async {
      final client = _Client(violations: high);
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      router.go(ServiceRoutes.activityNeedsYou);
      await _answer(tester);

      final decisions = container.read(dashboardDecisionsProvider).decisions;
      final violations = decisions
          .where((decision) => decision.kind == DecisionKind.violation)
          .toList();
      expect(violations, hasLength(2));
      for (final violation in violations) {
        expect(violation.isFault, isFalse);
        expect(violation.service, ServiceKey.tracearr);
        expect(violation.route, startsWith('/stack/tracearr/violations/'));
      }
      final notices = needsYouNotices(decisions, now: _now);
      expect(notices, isNotEmpty);
      for (final notice in notices) {
        expect(notice.id, isNot(contains('tracearr-violation')));
        expect(notice.route, isNot(contains('/violations/')));
      }
      await _close(tester, harness, container);
    });

    testWidgets('only the unseen of severity high are decisions, whatever '
        'the server answered', (tester) async {
      final client = _Client(
        violations: [
          ...high.take(1),
          _violation('w1', rule: 'Warned', severity: TracearrSeverity.warning),
          _violation('a1', rule: 'Read', seen: true),
        ],
      );
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      router.go(ServiceRoutes.activityNeedsYou);
      await _answer(tester);

      expect(find.byType(ViolationDecisionRow), findsOneWidget);
      expect(find.text('1 violation'), findsOneWidget);
      expect(find.text('Warned'), findsNothing);
      expect(find.text('Read'), findsNothing);
      await _close(tester, harness, container);
    });

    testWidgets('the lab world holds none: its one high violation is '
        'acknowledged', (tester) async {
      final (harness, router, container) = await _app(tester);
      router.go(ServiceRoutes.activityNeedsYou);
      await _answer(tester);

      expect(find.byType(ViolationDecisionRow), findsNothing);
      expect(find.textContaining('violation'), findsNothing);
      await _close(tester, harness, container);
    });

    testWidgets('a longer list than the cap reads as a floor', (tester) async {
      final client = _Client(
        violations: [
          for (var i = 0; i <= kNeedsYouViolationCap; i++)
            _violation('f$i', rule: 'Rule $i'),
        ],
      );
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      router.go(ServiceRoutes.activityNeedsYou);
      await _answer(tester);

      expect(find.byType(ViolationDecisionRow), findsNWidgets(5));
      expect(find.text('5+ violations'), findsOneWidget);
      expect(find.text('5+ violations to review'), findsOneWidget);
      expect(find.text('6 violations'), findsNothing);
      await _close(tester, harness, container);
    });

    testWidgets('are on All too, counted in the section and drawn after the '
        'faults', (tester) async {
      final client = _Client(violations: high);
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      router.go(ActivityTab.all.location);
      await _answer(tester);

      expect(find.byType(ViolationDecisionRow), findsNWidgets(2));
      expect(find.textContaining('2 violations'), findsWidgets);
      // The faults are still the faults: three cards, none of them a violation.
      expect(find.byType(FaultCard), findsNWidgets(3));
      await _close(tester, harness, container);
    });

    testWidgets('a tap opens the violation on the Tracearr it came off', (
      tester,
    ) async {
      final client = _Client(violations: high);
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      router.go(ServiceRoutes.activityNeedsYou);
      await _answer(tester);

      await _tap(tester, find.text('Impossible travel'));

      expect(
        router.state.uri.path,
        ServiceRoutes.tracearrViolation(_idOf('h1')),
      );
      expect(router.state.uri.queryParameters['i'], WorldIds.tracearr);
      expect(find.byType(TracearrViolationScreen), findsOneWidget);
      await _close(tester, harness, container);
    });

    for (final dismiss in [false, true]) {
      testWidgets('${dismiss ? 'a dismissed' : 'an acknowledged'} violation '
          'leaves Needs you, which reads it again', (tester) async {
        final client = _Client(violations: high);
        final owner = _Owner(
          TracearrOwnerOutcome.done,
          onDecided: (id) => client.violations = [
            for (final v in client.violations)
              if (v.id != id) v,
          ],
        );
        final (harness, router, container) = await _app(
          tester,
          overrides: [
            tracearrClientProvider.overrideWithValue(client),
            tracearrViolationOwnerProvider.overrideWith((ref, id) => owner),
          ],
        );
        // What Needs you holds, read the way its page and the Home do.
        List<String> flagged() => [
          for (final decision
              in container.read(dashboardDecisionsProvider).decisions)
            if (decision.kind == DecisionKind.violation)
              Uri.parse(decision.route!).path,
        ];
        container.read(dashboardDecisionsProvider);
        await _answer(tester);
        expect(
          flagged(),
          unorderedEquals([
            ServiceRoutes.tracearrViolation(_idOf('h1')),
            ServiceRoutes.tracearrViolation(_idOf('h2')),
          ]),
        );

        // The first of them, opened by its link, and decided on.
        router.go(ServiceRoutes.tracearrViolation(_idOf('h1')));
        await _answer(tester);
        await _tap(tester, find.text(dismiss ? 'Dismiss' : 'Acknowledge'));
        if (dismiss) {
          await _tap(
            tester,
            find.widgetWithText(FilledButton, 'Dismiss violation'),
          );
        }
        expect(owner.asked, [
          '${dismiss ? 'dismiss' : 'acknowledge'} ${_idOf('h1')}',
        ]);

        container.read(dashboardDecisionsProvider);
        await _answer(tester);
        expect(flagged(), [ServiceRoutes.tracearrViolation(_idOf('h2'))]);
        await _close(tester, harness, container);
      });
    }

    testWidgets('a read that failed is made again by a pull, not served from '
        'the failure', (tester) async {
      final client = _Client(violations: high)..failFlagged = true;
      final (harness, router, container) = await _app(
        tester,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      router.go(ServiceRoutes.activityNeedsYou);
      await _answer(tester);
      expect(find.byType(ViolationDecisionRow), findsNothing);
      final asked = client.filters
          .where((f) => f.severity == TracearrSeverity.high)
          .length;

      client.failFlagged = false;
      // The page's own pull, asked for the way a drag down would.
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator).first)
            .show(),
      );
      await _answer(tester);

      expect(
        client.filters.where((f) => f.severity == TracearrSeverity.high),
        hasLength(greaterThan(asked)),
        reason: 'asked again',
      );
      expect(find.byType(ViolationDecisionRow), findsNWidgets(2));
      await _close(tester, harness, container);
    });

    test('a pull and a Retry drop the page Needs you reads', () {
      expect(
        dashboardSourcesOf(ServiceKey.tracearr),
        contains(tracearrFlaggedProvider),
      );
    });

    testWidgets('a Tracearr that did not answer is named under the region '
        'and is not a fault', (tester) async {
      final (harness, router, container) = await _app(
        tester,
        profile: _household.withBehaviour(
          WorldIds.tracearr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      router.go(ServiceRoutes.activityNeedsYou);
      await _answer(tester);

      expect(find.byType(ViolationDecisionRow), findsNothing);
      expect(find.text('3 faults'), findsOneWidget);
      final decisions = container.read(dashboardDecisionsProvider);
      expect(
        decisions.decisions.where((d) => d.kind == DecisionKind.violation),
        isEmpty,
      );
      expect(decisions.coverage.failedServices, contains(ServiceKey.tracearr));
      await _close(tester, harness, container);
    });
  });

  group('the words', () {
    test('a count of violations says its floor and its plural', () {
      expect(violationsWaitLine(1), '1 violation to review');
      expect(violationsWaitLine(3), '3 violations to review');
      expect(violationsWaitLine(5, floor: true), '5+ violations to review');
    });
  });
}
