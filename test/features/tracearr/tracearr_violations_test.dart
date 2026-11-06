/// Violations, whole: the tab's filters and the person a link narrows it to,
/// the violation's own page (typed for the rules we know, the name alone for
/// any other), the owner's two controls, and what Needs you holds.
///
/// **The lab has no violation yet**, so every violation here is invented: the
/// rows of `test/fixtures/tracearr/violations.json` and
/// `violation_detail.json`, whose places and addresses are made up, and whose
/// `data` key spellings are the ones the model expects and not ones read off a
/// real Tracearr. The two typed renders are therefore pinned to the invented
/// shape. No test name, and no failure text, carries a place or an address.
library;

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
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_violation_owner.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violation_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_screen.dart';

import '../../test_helpers/fixtures.dart';
import '../../test_helpers/profiles/profiles.dart';

/// A UUID, which is what Tracearr's `user_id` accepts.
const _personId = '7a3e91c4-5d28-4b6f-8e10-2f4a6c8d0b13';

final _household = Profiles.p1.withConnection(WorldConnections.tracearr);

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
  'id': id,
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

  final List<TracearrViolation> violations;
  final List<TracearrViolation> single;

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
    return TracearrPage(items: violations);
  }

  @override
  Future<TracearrViolation?> getViolation(String id) async {
    for (final violation in [...single, ...violations]) {
      if (violation.id == id) return violation;
    }
    return null;
  }

  @override
  Future<TracearrUser?> getUser(String id) async =>
      TracearrUser(id: id, username: 'anna');
}

/// The owner's two writes, answering with [outcome] and keeping what was asked.
class _Owner implements TracearrViolationOwner {
  _Owner(this.outcome);

  final TracearrOwnerOutcome outcome;
  final asked = <String>[];

  @override
  Future<TracearrOwnerOutcome> acknowledge(String violationId) async {
    asked.add('acknowledge $violationId');
    return outcome;
  }

  @override
  Future<TracearrOwnerOutcome> dismiss(String violationId) async {
    asked.add('dismiss $violationId');
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
        ServiceRoutes.tracearrViolation('violation-1'),
      );
      expect(find.byType(TracearrViolationScreen), findsOneWidget);
      // The invented stream counts the demo world's rule carries.
      expect(find.text('2 streams at once'), findsOneWidget);
      expect(find.text('The limit is 1'), findsOneWidget);

      // A cold deep link resolves from the path alone, and a blank id goes
      // back to the tab.
      router.go(ServiceRoutes.tracearrViolation('violation-2'));
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

      // The Users tab leads here with a person.
      router.go(ServiceRoutes.tracearrViolationsOf(_personId));
      await _answer(tester);
      expect(router.state.uri.queryParameters['user'], _personId);
      expect(find.byType(TracearrViolationsScreen), findsOneWidget);
      await _close(tester, harness, container);
    });

    testWidgets('a violation that is gone says so', (tester) async {
      final client = _Client();
      final harness = await _pump(
        tester,
        const TracearrViolationScreen(violationId: 'gone'),
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      expect(find.text('Violation not found'), findsOneWidget);
      await harness.unmount(tester);
    });
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

      expect(find.text('Valmora, North Reach, Nordavia'), findsOneWidget);
      expect(find.text('Port Aster, Eastmark, Eastmark'), findsOneWidget);
      expect(find.text('First stream'), findsOneWidget);
      expect(find.text('Second stream'), findsOneWidget);
      expect(find.text('${withUnit('5,120', 'km')} apart'), findsOneWidget);
      expect(
        find.text(
          '${formatTimeSpan(const Duration(minutes: 95))} between the two '
          'streams',
        ),
        findsOneWidget,
      );
      // The address that came with them is never drawn, nor a raw key.
      expect(find.textContaining('192.0.2.'), findsNothing);
      expect(find.textContaining('distance_km'), findsNothing);
      expect(find.textContaining('time_diff'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('concurrent streams: how many and the limit', (tester) async {
      final harness = await pumpDetail(
        tester,
        _violation(
          'c1',
          rule: 'Too many streams',
          data: {'stream_count': 4, 'max_streams': 2, 'ip': '192.0.2.45'},
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
          data: {
            'city': 'Valmora',
            'ip_address': '192.0.2.60',
            'hour': 3,
            'quiet_hours': [1, 5],
          },
        ),
        opener: opener,
      );

      // The name, as the page's title and in its first row.
      expect(find.text('Night owl'), findsWidgets);
      expect(
        find.text('Only Tracearr shows what this rule saw'),
        findsOneWidget,
      );
      for (final leak in ['Valmora', '192.0.2.', 'ip_address', 'quiet_hours']) {
        expect(find.textContaining(leak), findsNothing, reason: 'a raw value');
      }

      await tester.ensureVisible(find.text('Open in Tracearr'));
      await tester.tap(find.text('Open in Tracearr'));
      await tester.pump();
      expect(opener.opened.single.host, 'tower.home.arpa');
      expect(opener.opened.single.path, '/violations/u1');
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

      expect(owner.asked, ['acknowledge o1']);
      expect(find.text('Acknowledged'), findsOneWidget);
      expect(router.state.uri.path, ServiceRoutes.tracearrViolation('o1'));
      await _close(tester, harness, container);
    });

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
      expect(owner.asked, ['dismiss o1']);
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
        expect(router.state.uri.path, ServiceRoutes.tracearrViolation('o1'));
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
        expect(violation.route, startsWith('/stack/tracearr/violations/h'));
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

      expect(router.state.uri.path, ServiceRoutes.tracearrViolation('h1'));
      expect(router.state.uri.queryParameters['i'], WorldIds.tracearr);
      expect(find.byType(TracearrViolationScreen), findsOneWidget);
      await _close(tester, harness, container);
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
