import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/calendar_event_codec.dart';
import 'package:cupola/features/home/data/last_known/coming_up_last_known.dart';
import 'package:cupola/features/home/presentation/widgets/coming_up_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_as_of_line.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

// Monday 12 October, 20:53: the window runs to Thursday.
final _now = DateTime(2026, 10, 12, 20, 53);

CalendarEvent _movie(
  String title,
  int day, {
  CalendarState state = const CalendarState.notYet(),
}) => CalendarEvent(
  identity: 'movie:$title',
  kind: CalendarKind.movie,
  day: DateTime(2026, 10, day),
  title: title,
  release: 'on digital',
  sources: const ['Radarr'],
  state: state,
);

CalendarEvent _episode(String title, int day, int hour) => CalendarEvent(
  identity: 'episode:$title:$day',
  kind: CalendarKind.episode,
  day: DateTime(2026, 10, day),
  airsAt: DateTime(2026, 10, day, hour),
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
  List<String> answered = const ['Radarr', 'Sonarr'],
  DateTime? at,
}) => LibraryCalendar(
  window: CalendarWindow.from(at ?? _now),
  events: events,
  answered: answered,
  silent: silent,
  kinds: const {CalendarKind.movie, CalendarKind.episode},
  readAt: at ?? _now,
);

const _unreachable = ClassifiedFailure(ServiceFailureReason.unreachable);

/// The Home at a cold start: Coming up as it was last drawn, said for what it
/// is, until the live answer comes.
void main() {
  group('a cold start', () {
    late LastKnownStore store;
    setUp(() => store = LastKnownStore.memory());

    /// One run of the app: a fresh scope over the same [store], as a start
    /// over the same file would be.
    Future<void> run(
      WidgetTester tester,
      Future<LibraryCalendar> Function() calendar, {
      SettingsModel Function(SettingsModel)? customize,
      DateTime? now,
    }) async {
      tester.view.physicalSize = const Size(1170, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final clock = now ?? _now;
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.radarr, ServiceKey.sonarr],
              customize: customize,
            ),
            lastKnownStoreProvider.overrideWithValue(store),
            calendarClockProvider.overrideWithValue(() => clock),
            libraryCalendarProvider.overrideWith((ref) => calendar()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Column(children: [HomeAsOfLine(), HomeComingUpModule()]),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> firstRun(
      WidgetTester tester, [
      List<CalendarEvent>? events,
    ]) async {
      await run(
        tester,
        () async => _calendar(
          events ??
              [
                _episode('Cosmos Laundromat', 12, 21),
                _movie('Sprite Fright', 13),
              ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sprite Fright'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    }

    testWidgets('draws the last drawing at once, says so, then the live one', (
      tester,
    ) async {
      await firstRun(tester);

      final answer = Completer<LibraryCalendar>();
      await run(
        tester,
        () => answer.future,
        now: _now.add(const Duration(minutes: 2)),
      );
      // No skeleton: the rows the person last saw, and the one line.
      expect(find.text('Sprite Fright'), findsOne);
      expect(find.text('Cosmos Laundromat'), findsOne);
      expect(find.byType(ShimmerList), findsNothing);
      expect(find.text('As of 20:53\u00A0· checking now'), findsOne);
      // The way to the Calendar stays where it is.
      expect(find.text('Calendar'), findsOne);

      answer.complete(_calendar([_movie('Agent 327', 13)]));
      await tester.pumpAndSettle();
      expect(find.text('Sprite Fright'), findsNothing);
      expect(find.text('Agent 327'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a live read that fails keeps the drawing at full ink, over '
        'the failure, and stops checking', (tester) async {
      await firstRun(tester);

      await run(tester, () async => throw _unreachable);
      await tester.pumpAndSettle();
      expect(find.text('Sprite Fright'), findsOne);
      expect(find.textContaining('did not answer'), findsOne);
      expect(find.text('As of 20:53'), findsOne);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('another server draws nothing of it', (tester) async {
      await firstRun(tester);

      await run(
        tester,
        () => Completer<LibraryCalendar>().future,
        customize: (settings) => settings.copyWithService(
          ServiceKey.radarr,
          url: 'https://other.test',
          apiKey: 'radarr-key',
        ),
      );
      expect(find.text('Sprite Fright'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('the window is cut again: what went by is gone, and a drawing '
        'with nothing left is no calm line', (tester) async {
      await firstRun(tester);

      // The next evening: Monday's episode is behind, the movie is today.
      await run(
        tester,
        () => Completer<LibraryCalendar>().future,
        now: DateTime(2026, 10, 13, 18),
      );
      expect(find.text('Cosmos Laundromat'), findsNothing);
      expect(find.text('Sprite Fright'), findsOne);

      // A week on there is nothing left to draw: the loading frame, never
      // "Nothing comes out or airs by", which only the live answer may say.
      await run(
        tester,
        () => Completer<LibraryCalendar>().future,
        now: DateTime(2026, 10, 20, 9),
      );
      expect(find.text('Coming up'), findsOne);
      expect(find.byType(ShimmerList), findsOne);
      expect(find.textContaining('Nothing comes out'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);

      // And a failed live read over it is the failure alone.
      await run(
        tester,
        () async => throw _unreachable,
        now: DateTime(2026, 10, 20, 9),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('did not answer'), findsOne);
      expect(find.textContaining('Nothing comes out'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('its words are made again at the time of the drawing', (
      tester,
    ) async {
      await firstRun(tester);

      await run(
        tester,
        () async => _calendar([
          _episode('Cosmos Laundromat', 12, 21),
          _movie('Sprite Fright', 13),
        ]),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('21:00\u00A0· S3\u00A0E1\u00A0· premiere\u00A0· not aired'),
        findsOne,
        reason: 'live at 20:53, seven minutes before it airs',
      );
      expect(find.text('Tomorrow'), findsOne);
      expect(find.text('Not out yet'), findsOne);

      // Half past nine: it aired while the app was closed. The drawing does
      // not say it is "not aired", nor what became of it.
      await run(
        tester,
        () => Completer<LibraryCalendar>().future,
        now: DateTime(2026, 10, 12, 21, 30),
      );
      expect(
        find.text('21:00\u00A0· S3\u00A0E1\u00A0· premiere\u00A0· aired'),
        findsOne,
      );
      expect(find.textContaining('not aired'), findsNothing);
      expect(find.textContaining('missing'), findsNothing);
      expect(find.text('Tomorrow'), findsOne);

      // The next morning: tomorrow's movie is today, out, and says no more.
      await run(
        tester,
        () => Completer<LibraryCalendar>().future,
        now: DateTime(2026, 10, 13, 8),
      );
      expect(find.text('Tomorrow'), findsNothing);
      expect(find.text('Today'), findsOne);
      expect(find.text('Out today'), findsOne);
      expect(find.text('Not out yet'), findsNothing);
    });

    testWidgets('a download is drawn as the state it was in, with no figure '
        'and no time it would finish', (tester) async {
      final downloading = _movie(
        'Sintel',
        12,
        state: CalendarState.inFlight(
          const MediaStatusInfo(
            availability: MediaAvailability.missing,
            pipeline: MediaPipeline.downloading,
            progress: 0.62,
          ),
          finishesAt: DateTime(2026, 10, 12, 21, 10),
        ),
      );
      await firstRun(tester, [downloading, _movie('Sprite Fright', 13)]);
      // Live: the figure.
      expect(find.text('Out today\u00A0· downloading 62%'), findsOne);

      await run(tester, () => Completer<LibraryCalendar>().future);
      expect(find.text('Out today\u00A0· downloading'), findsOne);
      expect(find.textContaining('62'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('21:10'), findsNothing);
      expect(find.text('As of 20:53\u00A0· checking now'), findsOne);
    });

    testWidgets('a read with every connection silent is not kept', (
      tester,
    ) async {
      await firstRun(tester);
      await run(
        tester,
        () async => _calendar(
          const [],
          answered: const [],
          silent: const [
            (
              service: ServiceKey.radarr,
              connectionId: 'radarr',
              name: 'Radarr',
              error: _unreachable,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await run(tester, () => Completer<LibraryCalendar>().future);
      expect(find.text('Sprite Fright'), findsOne);
    });

    testWidgets('a read that answered with an empty window is kept as one, so '
        'the drawing before it is not drawn in its place', (tester) async {
      await firstRun(tester);
      await run(tester, () async => _calendar(const []));
      await tester.pumpAndSettle();
      expect(find.text('Nothing comes out or airs by Thursday'), findsOne);

      await run(tester, () => Completer<LibraryCalendar>().future);
      expect(find.text('Sprite Fright'), findsNothing);
      expect(find.byType(ShimmerList), findsOne);
      expect(find.textContaining('Nothing comes out'), findsNothing);
    });
  });

  group('the codec', () {
    // What a drawn picture would get back from its connection today.
    ImageSource resolve(StoredImage image) => switch (image) {
      StoredUrl(:final url) => (url: url, headers: null),
      StoredArrImage(:final path) => (
        url: 'https://sonarr.test$path',
        headers: const {'X-Api-Key': 'put-back'},
      ),
      StoredStreamImage() => noImage,
    };

    CalendarEvent? roundTrip(CalendarEvent event) => calendarEventFromJson(
      jsonDecode(jsonEncode(calendarEventToJson(event, _keep))),
      resolve,
    );

    final airsAt = DateTime(2026, 10, 14, 21);
    final everything = <CalendarEvent>[
      CalendarEvent(
        identity: 'episode:5:3:1..8',
        kind: CalendarKind.episode,
        day: DateTime(2026, 10, 14),
        airsAt: airsAt,
        title: 'Cosmos Laundromat',
        season: 3,
        episode: 1,
        lastEpisode: 8,
        mark: CalendarMark.wholeSeason,
        tmdbId: 4242,
        poster: (
          url: 'https://sonarr.test/mediacover/5/poster.jpg',
          headers: const {'X-Api-Key': 'sonarr-secret'},
        ),
        backdrop: (
          url: 'https://image.tmdb.org/t/p/w1280/b.jpg',
          headers: null,
        ),
        sources: const ['Sonarr', 'Sonarr 4K'],
        note: 'A note',
        region: 'Italy',
        state: const CalendarState.out(missingKnown: true),
        target: const CalendarMediaTarget(
          MediaKey.tvdb(77),
          connectionId: 'sonarr-1',
        ),
      ),
      CalendarEvent(
        identity: 'movie:12345:digitalRelease',
        kind: CalendarKind.movie,
        day: DateTime(2026, 10, 13),
        title: 'Sprite Fright',
        release: 'on digital',
        tmdbId: 12345,
        poster: (url: 'https://image.tmdb.org/t/p/w500/a.jpg', headers: null),
        sources: const ['Radarr'],
        state: const CalendarState.onServer(),
        target: const CalendarMediaTarget(
          MediaKey.movie(12345),
          connectionId: 'radarr-1',
        ),
      ),
      CalendarEvent(
        identity: 'album:abc',
        kind: CalendarKind.album,
        day: DateTime(2026, 10, 15),
        title: 'Sintel (Anniversary Edition)',
        byline: 'Jan Morgenstern',
        sources: const ['Lidarr'],
        state: const CalendarState.notYet(),
        target: const CalendarShelfTarget(ServiceKey.lidarr, 'lidarr-1', 9),
      ),
    ];

    test('keeps every field an event draws', () {
      for (final event in everything) {
        final back = roundTrip(event)!;
        // Compared by the JSON they make, which names every field, and by
        // the fields that carry a moment.
        expect(
          calendarEventToJson(back, _keep),
          calendarEventToJson(event, _keep),
        );
        expect(back.identity, event.identity);
        expect(back.kind, event.kind);
        expect(back.day, event.day);
        expect(back.title, event.title);
        expect(back.sources, event.sources);
        expect(back.state.stand, event.state.stand);
        expect(back.state.missingKnown, event.state.missingKnown);
        expect(back.target, event.target);
        expect(back.mark, event.mark);
        expect(back.code, event.code);
        expect(back.tmdbId, event.tmdbId);
        expect(back.byline, event.byline);
        expect(back.note, event.note);
        expect(back.region, event.region);
        expect(back.release, event.release);
        if (event.airsAt case final at?) {
          expect(back.airsAt!.isAtSameMomentAs(at), isTrue);
        } else {
          expect(back.airsAt, isNull);
        }
      }
    });

    test("keeps an arr's picture by its connection and its path, putting "
        'the key back only on it', () {
      final episode = roundTrip(everything[0])!;
      expect(
        episode.poster?.url,
        'https://sonarr.test/mediacover/5/poster.jpg',
      );
      expect(episode.poster?.headers, {'X-Api-Key': 'put-back'});
      expect(episode.backdrop?.url, 'https://image.tmdb.org/t/p/w1280/b.jpg');
      expect(episode.backdrop?.headers, isNull);
      expect(roundTrip(everything[2])!.poster, isNull);
    });

    test('keeps no credential: no header value, no key in an address', () {
      final data = comingUpLastKnown.encode(
        _calendar(everything, at: airsAt),
        _keep,
      );
      final json = jsonEncode(data);
      expect(json, isNot(contains('sonarr-secret')));
      expect(json, isNot(contains('X-Api-Key')));
      expect(json, contains('"kind":"arr"'));
      // No address either: the connection's, whichever it is reached at
      // when it is drawn, goes in front of the path.
      expect(json, isNot(contains('sonarr.test')));
      expect(json, contains('"path":"/mediacover/5/poster.jpg"'));

      // Headers with no connection to put them back from keep no picture.
      final stray = CalendarEvent(
        identity: 'movie:1',
        kind: CalendarKind.movie,
        day: DateTime(2026, 10, 13),
        title: 'Stray',
        poster: (
          url: 'https://radarr.test/mediacover/1/poster.jpg',
          headers: const {'X-Api-Key': 'radarr-secret'},
        ),
        state: const CalendarState.notYet(),
      );
      expect(
        jsonEncode(calendarEventToJson(stray, _keep)),
        isNot(contains('secret')),
      );
      expect(roundTrip(stray)!.poster, isNull);

      // A key in the address itself is never kept either.
      final keyed = CalendarEvent(
        identity: 'movie:2',
        kind: CalendarKind.movie,
        day: DateTime(2026, 10, 13),
        title: 'Keyed',
        poster: (url: 'https://x.test/p.jpg?apikey=abc123', headers: null),
        state: const CalendarState.notYet(),
      );
      expect(
        jsonEncode(calendarEventToJson(keyed, _keep)),
        isNot(contains('abc123')),
      );
    });

    test('a download keeps its state and nothing that runs', () {
      for (final (pipeline, warning) in [
        (MediaPipeline.downloading, false),
        (MediaPipeline.stalled, true),
        (MediaPipeline.clientUnavailable, false),
      ]) {
        final event = _movie(
          'Sintel',
          12,
          state: CalendarState.inFlight(
            MediaStatusInfo(
              availability: MediaAvailability.missing,
              pipeline: pipeline,
              progress: 0.62,
              hasWarning: warning,
              detail: 'about 4 minutes left',
            ),
            finishesAt: DateTime(2026, 10, 12, 21, 10),
          ),
        );
        final json = jsonEncode(calendarEventToJson(event, _keep));
        expect(json, isNot(contains('0.62')));
        expect(json, isNot(contains('62')));
        expect(json, isNot(contains('4 minutes')));
        expect(json, isNot(contains('21:10')));
        expect(json, isNot(contains('finishesAt')));

        final state = roundTrip(event)!.state;
        expect(state.stand, CalendarStand.inFlight);
        expect(state.queue?.pipeline, pipeline);
        expect(state.queue?.label, pipeline.label);
        expect(state.percent, isNull);
        expect(state.finishesAt, isNull);
        // A fault or an outage of an old read is not news of today.
        expect(state.tone, StatusTone.neutral);
      }
    });

    test('refuses a record it cannot read whole', () {
      final good = calendarEventToJson(everything[1], _keep);
      Object? broken(String key, Object? value) =>
          calendarEventFromJson({...good, key: value}, resolve);

      expect(calendarEventFromJson(good, resolve), isNotNull);
      expect(calendarEventFromJson(null, resolve), isNull);
      expect(calendarEventFromJson('nope', resolve), isNull);
      expect(calendarEventFromJson(<String, Object?>{}, resolve), isNull);
      expect(broken('kind', 'nope'), isNull);
      expect(broken('day', '12/10/2026'), isNull);
      expect(broken('day', 20261012), isNull);
      expect(broken('identity', ''), isNull);
      expect(broken('title', 7), isNull);
      expect(broken('season', 'three'), isNull);
      expect(broken('mark', 'nope'), isNull);
      expect(broken('sources', 'Radarr'), isNull);
      expect(broken('sources', [1]), isNull);
      expect(broken('airsAt', 'yesterday'), isNull);
      expect(broken('poster', {'kind': 'nope'}), isNull);
      expect(broken('state', {'stand': 'nope'}), isNull);
      expect(broken('state', {'stand': 'out'}), isNull);
      expect(broken('state', {'stand': 'inFlight'}), isNull);
      expect(
        broken('state', {'stand': 'inFlight', 'pipeline': 'nope'}),
        isNull,
      );
      expect(
        broken('target', {'kind': 'media', 'media': 'movie', 'id': 0}),
        isNull,
      );
      expect(broken('target', {'kind': 'shelf', 'id': 3}), isNull);
    });

    test('an event with a time takes its day from it', () {
      final json = calendarEventToJson(everything[0], _keep);
      final back = calendarEventFromJson({
        ...json,
        'day': '2026-01-01',
      }, resolve);
      expect(back!.day, DateTime(2026, 10, 14));
    });
  });

  group('the slot', () {
    test('keeps what is drawn, a day more, capped', () {
      final events = [
        for (var day = 12; day <= 20; day++) _movie('Day $day', day),
        for (var i = 0; i < 20; i++) _movie('Again $i', 13),
      ];
      final data =
          comingUpLastKnown.encode(_calendar(events), _keep)
              as Map<String, Object?>;
      final kept = data['events'] as List;
      expect(kept, hasLength(12));
      final titles = [for (final event in kept) (event as Map)['title']];
      expect(titles, contains('Day 12'));
      expect(titles, contains('Day 16'));
      expect(titles, isNot(contains('Day 17')));
      expect(titles, isNot(contains('Day 20')));
    });

    test('is not kept when every connection was silent', () {
      expect(
        comingUpLastKnown.encode(
          _calendar(
            const [],
            answered: const [],
            silent: const [
              (
                service: ServiceKey.radarr,
                connectionId: 'radarr',
                name: 'Radarr',
                error: _unreachable,
              ),
            ],
          ),
          _keep,
        ),
        isNull,
      );
    });

    test('a drawing keeps no fault: a partial read is drawn whole, without '
        'the connection that did not answer', () {
      final data = comingUpLastKnown.encode(
        _calendar(
          [_movie('Sprite Fright', 13)],
          silent: const [
            (
              service: ServiceKey.sonarr,
              connectionId: 'sonarr',
              name: 'Sonarr',
              error: _unreachable,
            ),
          ],
          answered: const ['Radarr'],
        ),
        _keep,
      );
      expect(jsonEncode(data), isNot(contains('Sonarr')));
      final back = comingUpLastKnown.decode(
        jsonDecode(jsonEncode(data)),
        (_) => noImage,
      )!;
      expect(back.silent, isEmpty);
      expect(back.events.map((event) => event.title), ['Sprite Fright']);
      expect(back.readAt, _now);
    });

    test(
      'reads nothing it cannot read, and skips only the event it cannot',
      () {
        ImageSource none(StoredImage _) => noImage;
        expect(comingUpLastKnown.decode(null, none), isNull);
        expect(comingUpLastKnown.decode({'events': 'x'}, none), isNull);
        expect(comingUpLastKnown.decode({'events': <Object>[]}, none), isNull);
        expect(
          comingUpLastKnown
              .decode({
                'readAt': _now.toUtc().toIso8601String(),
                'events': [
                  {'kind': 'nope'},
                  calendarEventToJson(_movie('Sprite Fright', 13), _keep),
                ],
              }, none)!
              .events
              .map((event) => event.title),
          ['Sprite Fright'],
        );
      },
    );
  });
}

/// Keeps the pictures as the Home does, against the Sonarr the events with an
/// arr's picture were read from.
final _keep = storedImageKeeper(
  const SettingsModel(
    instances: [
      ServiceInstance(
        id: 'sonarr-1',
        service: ServiceKey.sonarr,
        url: 'https://sonarr.test',
        credential: 'sonarr-secret',
      ),
    ],
  ),
);
