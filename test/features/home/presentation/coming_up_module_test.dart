import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/presentation/widgets/coming_up_module.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

// Tuesday 29 September, 20:41: the window runs to Friday.
final _now = DateTime(2026, 9, 29, 20, 41);

CalendarEvent _movie(String title, int day) => CalendarEvent(
  identity: title,
  kind: CalendarKind.movie,
  day: DateTime(2026, 9, day),
  title: title,
  sources: const ['Radarr'],
  state: const CalendarState.notYet(),
);

CalendarEvent _episode(String title, int day, int hour) => CalendarEvent(
  identity: '$title-$day',
  kind: CalendarKind.episode,
  day: DateTime(2026, 9, day),
  airsAt: DateTime(2026, 9, day, hour),
  title: title,
  season: 3,
  episode: 1,
  mark: CalendarMark.premiere,
  sources: const ['Sonarr'],
  state: const CalendarState.notYet(),
);

LibraryCalendar _calendar(
  List<CalendarEvent> events, {
  List<CalendarSilence> silent = const [],
}) => LibraryCalendar(
  window: CalendarWindow.from(_now),
  events: events,
  answered: const ['Radarr', 'Sonarr'],
  silent: silent,
  kinds: const {CalendarKind.movie, CalendarKind.episode},
  readAt: _now,
);

/// Coming up on the Home: three days of the calendar, then the Calendar.
void main() {
  Future<void> pump(WidgetTester tester, LibraryCalendar calendar) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.radarr, ServiceKey.sonarr],
          ),
          libraryCalendarProvider.overrideWith((ref) async => calendar),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: HomeComingUpModule()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('three rows from today to Friday, the day leading each, an '
      'episode\'s time in its status', (tester) async {
    await pump(
      tester,
      _calendar([
        _movie('Sprite Fright', 29),
        _episode('Cosmos Laundromat', 32, 21),
        _movie('Sintel', 32),
        _movie('Agent 327', 32),
        _movie('Next week', 36),
      ]),
    );

    expect(find.text('Coming up'), findsOne);
    expect(find.text('Calendar'), findsOne);
    expect(find.text('Today'), findsOne);
    expect(find.text('29 Sep'), findsOne);
    expect(find.text('Sprite Fright'), findsOne);
    expect(
      find.textContaining(RegExp(r'^21:00\u00A0· S3\u00A0E1\u00A0· premiere')),
      findsOne,
    );
    // Three rows, then the Calendar has the rest.
    expect(find.text('Agent 327'), findsNothing);
    expect(find.text('Next week'), findsNothing);
  });

  testWidgets('nothing by Friday is a calm line, not an absence', (
    tester,
  ) async {
    await pump(tester, _calendar([_movie('Next week', 36)]));
    expect(find.text('Coming up'), findsOne);
    expect(find.text('Nothing comes out or airs by Friday'), findsOne);
    expect(find.text('The calendar has the rest of the month.'), findsOne);
  });

  testWidgets('a connection that did not answer is named over the rows', (
    tester,
  ) async {
    await pump(
      tester,
      _calendar(
        [_movie('Sprite Fright', 29)],
        silent: const [
          (
            service: ServiceKey.lidarr,
            connectionId: 'lidarr',
            name: 'Lidarr',
            error: ClassifiedFailure(ServiceFailureReason.unreachable),
          ),
        ],
      ),
    );
    expect(find.textContaining('Lidarr did not answer'), findsOne);
    expect(find.text('Sprite Fright'), findsOne);
  });
}
