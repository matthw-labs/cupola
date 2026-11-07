import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/title_light.dart';

import 'package:cupola/features/discover/presentation/calendar_page.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_agenda.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_month_grid.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_week_strip.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The calendar of everything the household's arrs date: the atrium's band
/// that opens it, and its page, on the world of the boards (Tuesday 29
/// September, 20:53).
void main() {
  final now = DateTime(2026, 9, 29, 20, 53);

  Future<ProfileHarness> pump(
    WidgetTester tester,
    ConfigProfile profile,
    Widget child, {
    Size size = const Size(430, 4000),
  }) => pumpWithProfile(
    tester,
    profile,
    child: child,
    now: now,
    overrides: [calendarClockProvider.overrideWithValue(() => now)],
    surfaceSize: size,
  );

  /// [body] on a desktop window of [size]: the platform is set before the
  /// theme is built, and put back before the test ends.
  Future<void> onDesktop(
    WidgetTester tester,
    ConfigProfile profile,
    Size size,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final harness = await pump(
        tester,
        profile,
        const CalendarPage(),
        size: size,
      );
      await body();
      await harness.unmount(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  String band(WidgetTester tester) => tester
      .getSemantics(find.bySemanticsLabel(RegExp(r'^Calendar')).first)
      .label;

  testWidgets('P1: the band leads the atrium, names today and dots the week', (
    tester,
  ) async {
    final harness = await pump(
      tester,
      Profiles.p1,
      const Scaffold(body: DiscoverAtrium()),
    );

    expect(find.text('Calendar'), findsOneWidget);
    expect(
      band(tester),
      'Calendar: today Sprite Fright, on digital, and 3 more days this week '
      'have something',
    );
    // Above the doors.
    expect(
      tester.getTopLeft(find.text('Calendar')).dy,
      lessThan(tester.getTopLeft(find.text('Trending')).dy),
    );

    await harness.unmount(tester);
  });

  testWidgets('P1: the page, its answer, the rows of every arr and the '
      'kinds', (tester) async {
    final harness = await pump(tester, Profiles.p1, const CalendarPage());

    expect(
      find.textContaining('things come out or air this week. Today:'),
      findsOneWidget,
    );
    expect(
      find.text('From Radarr 1, Radarr 4K, Sonarr and Lidarr at 20:53'),
      findsOneWidget,
    );
    expect(find.text('Out today\u00A0· downloading 62%'), findsOneWidget);
    // The first Radarr, unnamed, is called by its place.
    expect(find.text('Radarr 1'), findsWidgets);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('S2\u00A0E5\u00A0· not aired'), findsOneWidget);
    expect(find.text('Nothing more in the next 30 days'), findsOneWidget);
    expect(
      find.text('Books appear here when Readarr is set up.'),
      findsOneWidget,
    );

    // A row is one sentence.
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Today, Sprite Fright, movie out on digital, downloading'),
      ),
      findsOneWidget,
    );

    // Series only: the movie goes.
    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(find.text('Out today\u00A0· downloading 62%'), findsNothing);
    expect(find.text('S2\u00A0E5\u00A0· not aired'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('P7, Lidarr home-only: its rows go, it is named once with '
      'what may be missing, and the count is not stated', (tester) async {
    final harness = await pump(tester, Profiles.p7, const CalendarPage());

    expect(
      find.textContaining(
        'Lidarr did not answer\u00A0· albums may be missing here',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('— things come out'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('P4, no Seerr: the band stands over the catalogue slab', (
    tester,
  ) async {
    final harness = await pump(tester, Profiles.p4, const DiscoverPage());

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('The catalog comes from Seerr'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Calendar')).dy,
      lessThan(tester.getTopLeft(find.text('The catalog comes from Seerr')).dy),
    );

    await harness.unmount(tester);
  });

  testWidgets('P2, the requester: her band comes from her requests, and '
      'names no service', (tester) async {
    final harness = await pump(
      tester,
      Profiles.p2,
      const Scaffold(body: DiscoverAtrium()),
    );

    expect(
      band(tester),
      'Calendar: today Sprite Fright, on digital, and 1 more day this week '
      'has something',
    );
    for (final service in ['Radarr', 'Sonarr', 'Seerr']) {
      expect(find.textContaining(service), findsNothing);
    }

    await harness.unmount(tester);
  });

  testWidgets('P2, the requester: her requests with a date, in her words '
      'and her country', (tester) async {
    final harness = await pump(tester, Profiles.p2, const CalendarPage());

    expect(
      find.textContaining(
        '2 of your requests have a date this week. Today: Sprite Fright, '
        'ready around',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Your requests on their way\u00A0· checked at 20:53'),
      findsOneWidget,
    );
    expect(find.text('Downloading 62%'), findsOneWidget);
    expect(find.text('On digital in Italy today'), findsOneWidget);
    expect(
      find.text('S3\u00A0E1\u00A0· premiere\u00A0· not aired'),
      findsOneWidget,
    );
    expect(find.textContaining('You asked for season 3 on '), findsOneWidget);
    expect(
      find.text('Dates are for Italy. Episodes have a date here, not a time.'),
      findsOneWidget,
    );
    // No line about the kinds no service of hers dates, no service named.
    expect(find.textContaining('appear here when'), findsNothing);
    for (final service in ['Radarr', 'Sonarr', 'Lidarr', 'Seerr']) {
      expect(find.textContaining(service), findsNothing);
    }
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Today, Sprite Fright, out on digital in Italy, downloading'),
      ),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Desktop, P1: the thirty days as a grid, the selected day '
      'read beside it, moved by the arrows and by a click', (tester) async {
    await onDesktop(tester, Profiles.p1, const Size(1208, 856), () async {
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
      expect(find.byType(CalendarWeekStrip), findsNothing);
      expect(find.text('Selected day'), findsOneWidget);
      expect(find.text('1 thing: Sprite Fright on digital.'), findsOneWidget);
      expect(find.text('Open Sprite Fright'), findsOneWidget);
      expect(
        find.text('Arrow keys move the day. Enter opens its first title.'),
        findsOneWidget,
      );
      // A day is one button.
      expect(
        find.bySemanticsLabel('Friday 2 October, 1 thing'),
        findsOneWidget,
      );

      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      expect(
        find.text('1 thing: the premiere of Cosmos Laundromat season 3.'),
        findsOneWidget,
      );

      // A week on: nothing, and the way to the next day that has something.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('Nothing on this day.'), findsOneWidget);
      expect(find.text('Next day\u00A0· Mon 12 Oct'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Monday 12 October, 1 thing'));
      await tester.pump();
      expect(find.text('1 thing: Sprite Fright on disc.'), findsOneWidget);
    });
  });

  testWidgets('Desktop, a wide window: the next release lights the whole '
      'window, and the light fades out before its foot', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final harness = await ProfileHarness.start(
        Profiles.p1,
        now: now,
        overrides: [
          calendarClockProvider.overrideWithValue(() => now),
          titleLightProvider.overrideWith(
            (ref, url) async => const TitleLight(
              light: Color(0xFFD9A35B),
              actionFill: Color(0xFFF2D3A6),
              actionInk: Color(0xFF2B1A05),
              dayPrimary: Color(0xFF6B4410),
            ),
          ),
        ],
      );
      // The world's records carry no artwork: the next release here does,
      // so the page has a light to draw.
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/calendar',
        (_) => NetworkReply.json([
          {
            'id': 1,
            'title': 'Sprite Fright',
            'tmdbId': 10378,
            'monitored': true,
            'hasFile': false,
            'digitalRelease': '2026-09-30T00:00:00Z',
            'images': [
              {
                'coverType': 'poster',
                'remoteUrl': 'https://image.tmdb.org/t/p/original/sprite.jpg',
              },
            ],
          },
        ]),
      );
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const CalendarPage(),
          ),
        ),
      );
      await harness.settle(tester);

      // The room is lit by the release's light, across the window and not
      // the well.
      final room = find.byType(AmbientRoom);
      expect(room, findsOneWidget);
      await tester.pumpAndSettle(AppAnimation.light);
      expect(tester.widget<AmbientRoom>(room).accent, const Color(0xFFD9A35B));
      expect(tester.getSize(room).width, 1600);
      // The lamp hangs at the top and is gone well before the window's foot.
      expect(LampMetrics.centreTop + LampMetrics.radius, lessThan(1000 / 2));
      await harness.unmount(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Desktop, a window too narrow for the grid: the phone\'s strip '
      'and agenda, in the reading well', (tester) async {
    await onDesktop(tester, Profiles.p1, const Size(1000, 856), () async {
      expect(find.byType(CalendarMonthGrid), findsNothing);
      expect(find.byType(CalendarWeekStrip), findsOneWidget);
      expect(
        tester.getSize(find.byType(CalendarDayGroup).first).width,
        lessThanOrEqualTo(720),
      );
    });
  });

  testWidgets('Desktop, P2: her grid and her day name no service', (
    tester,
  ) async {
    await onDesktop(tester, Profiles.p2, const Size(1208, 856), () async {
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
      expect(find.text('Open Sprite Fright'), findsOneWidget);
      for (final service in ['Radarr', 'Sonarr', 'Lidarr', 'Seerr']) {
        expect(find.textContaining(service), findsNothing);
      }
    });
  });
}
