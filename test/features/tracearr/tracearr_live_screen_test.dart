/// Live, the detail of a stream, and Stop: drawn over a client that answers the
/// recorded rows and holds the event stream open, with nothing above the
/// socket stubbed but the client itself. Stop is a write, so every test of it
/// is over a fake that only records what it was asked.
library;

import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_overview_screen.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

import '../../test_helpers/fixtures.dart';
import '../../test_helpers/profiles/profiles.dart';
import '../../test_helpers/recorded_pictures.dart';

final _household = Profiles.p1.withConnection(WorldConnections.tracearr);

/// A Tracearr with no socket: the streams and the people are the recorded
/// fixtures, the event stream is a controller the test writes to, and a stop
/// answers what the test says and records who it was asked about.
class _FixtureClient extends TracearrClient {
  _FixtureClient({
    this.stops = const [],
    this.streamsFixture = 'tracearr/streams.json',
  }) : super(baseUrl: 'https://tracearr.test/ui', apiKey: 'trr_pub_test');

  final List<Object> stops;
  final String streamsFixture;

  final wires = <StreamController<TracearrEvent>>[];
  final stopped = <({String id, String? reason})>[];
  var reads = 0;

  @override
  Future<TracearrStreams> getStreams({String? serverId}) async {
    reads++;
    return TracearrStreams.fromJson(jsonFixture(streamsFixture));
  }

  @override
  Future<TracearrPage<TracearrUser>> getUsers({
    String? cursor,
    int pageSize = 25,
    bool includeRemoved = false,
  }) async => TracearrPage.fromJson(
    jsonFixture('tracearr/users.json'),
    TracearrUser.fromJson,
  );

  /// The series Tracearr names by its own id, by what `media/{id}` says of it.
  /// The recorded Harbor Lights row names this one.
  TracearrMediaIdentity? series = const TracearrMediaIdentity(
    type: TracearrMediaType.show,
    tmdb: 1399,
  );

  final mediaAsked = <String>[];

  @override
  Future<TracearrMediaIdentity?> getMediaIdentity(TracearrMediaRef ref) async {
    mediaAsked.add(ref.value);
    return series;
  }

  @override
  Future<TracearrPage<TracearrViolation>> getViolations({
    String? cursor,
    int pageSize = 25,
    TracearrViolationFilter filter = const TracearrViolationFilter(),
  }) async => TracearrPage.fromJson(
    jsonFixture('tracearr/violations.json'),
    TracearrViolation.fromJson,
  );

  @override
  Stream<TracearrEvent> events({
    List<String>? types,
    String? serverId,
    CancelToken? cancelToken,
    void Function(Duration retry)? onRetry,
  }) {
    final wire = StreamController<TracearrEvent>();
    wires.add(wire);
    return wire.stream;
  }

  @override
  Future<TracearrTerminateResult> terminate(String id, {String? reason}) async {
    stopped.add((id: id, reason: reason));
    final next = stops[(stopped.length - 1).clamp(0, stops.length - 1)];
    if (next is TracearrTerminateResult) return next;
    throw next;
  }
}

const _firstId = 'f0a1b2c3-0001-4aaa-8bbb-000000000001';

Future<ProfileHarness> _pump(
  WidgetTester tester,
  Widget screen,
  _FixtureClient client, {
  List<Override> overrides = const [],
}) {
  recordPictures();
  return pumpWithProfile(
    tester,
    _household,
    child: Scaffold(body: screen),
    overrides: [tracearrClientProvider.overrideWithValue(client), ...overrides],
    surfaceSize: const Size(430, 3000),
  );
}

/// Ends every stream in the list the page draws, as an answer that was
/// already out would, while a sheet is open over the page: every row goes, so
/// none of them is left standing to act for the sheet.
void _stopBehindTheSheet(WidgetTester tester) {
  final live = ProviderScope.containerOf(
    tester.element(find.byType(TracearrLiveScreen)),
  ).read(tracearrLiveProvider.notifier);
  live
    ..apply(const TracearrStreamStopped(id: _firstId))
    ..apply(
      const TracearrStreamStopped(id: 'f0a1b2c3-0002-4aaa-8bbb-000000000002'),
    );
}

void main() {
  group('the rows', () {
    testWidgets('carry a poster the proxy serves, the person, the device, how '
        'it reaches them and why', (tester) async {
      final client = _FixtureClient();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      expect(find.byType(ServiceRecordRow), findsNWidgets(2));
      expect(find.text('The Lantern Keeper'), findsOneWidget);
      // A transcode says so, with the first reason in words.
      expect(find.text('Transcode'), findsOneWidget);
      expect(find.textContaining('Video codec not supported'), findsOneWidget);
      expect(find.text('Direct play'), findsOneWidget);
      // A series' episode is named by its show and its code.
      expect(find.text('Harbor Lights\u00A0· S2 E5'), findsOneWidget);
      expect(find.textContaining('Paused'), findsOneWidget);
      expect(
        find.textContaining(
          'Anna\u00A0· Living Room TV\u00A0· Plex Living Room',
        ),
        findsOneWidget,
      );

      // The poster is Tracearr's own path, joined to the address the client
      // reads (under its prefix) and fetched with the key in a header, never
      // in the address.
      final requested = pictures.requests.firstWhere(
        (r) => r.url.contains('/api/v1/images/proxy'),
      );
      expect(
        requested.url,
        startsWith('https://tracearr.test/ui/api/v1/images/proxy?server='),
      );
      expect(requested.url, isNot(contains('trr_pub_')));
      expect(requested.headers?['Authorization'], 'Bearer trr_pub_test');
      await harness.unmount(tester);
    });

    testWidgets('and a summary bar: how many, how many transcode, bandwidth '
        'as Tracearr gave it', (tester) async {
      final client = _FixtureClient();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      expect(
        find.text('2 streams\u00A0· 1 transcode\u00A0· 11.7 Mbps'),
        findsOneWidget,
      );
      await harness.unmount(tester);
    });

    testWidgets('an idle Tracearr says nothing is playing', (tester) async {
      final client = _FixtureClient(
        streamsFixture: 'tracearr/streams_idle.json',
      );
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      expect(find.text('Nothing is playing'), findsOneWidget);
      await harness.unmount(tester);
    });
  });

  group('while it is on screen', () {
    testWidgets('events move the rows and the summary', (tester) async {
      final client = _FixtureClient();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);
      expect(client.wires, hasLength(1), reason: 'the stream is open');
      final wire = client.wires.single;

      wire.add(
        TracearrStreamStarted(
          TracearrStream.fromJson({
            'id': 'new-one',
            'username': 'Luca',
            'media_title': 'Brand New',
            'media_type': 'movie',
            'state': 'playing',
            'bitrate': 1000,
            'device': 'Phone',
          }),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Brand New'), findsOneWidget);
      expect(find.byType(ServiceRecordRow), findsNWidgets(3));
      expect(find.textContaining('3 streams'), findsOneWidget);

      wire.add(const TracearrStreamStopped(id: _firstId));
      await tester.pump();
      await tester.pump();
      expect(find.text('The Lantern Keeper'), findsNothing);
      expect(find.textContaining('2 streams'), findsOneWidget);
      // The transcode went with it.
      expect(find.textContaining('transcode'), findsNothing);

      wire.add(
        const TracearrStreamProgress(
          id: 'f0a1b2c3-0002-4aaa-8bbb-000000000002',
          progressMs: 1,
        ),
      );
      await tester.pump();
      await harness.unmount(tester);
    });

    testWidgets('when the stream cannot be opened the rows are read every ten '
        'seconds', (tester) async {
      final client = _FailingEvents();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);
      final opening = client.reads;

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(client.reads, greaterThan(opening));
      expect(find.byType(ServiceRecordRow), findsNWidgets(2));
      await harness.unmount(tester);
    });
  });

  group('the detail', () {
    Future<void> open(WidgetTester tester, String title) async {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testWidgets('puts source against output and lists what the row has no '
        'room for', (tester) async {
      final client = _FixtureClient();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await open(tester, 'The Lantern Keeper');

      // How it reaches them, with every reason the server gave.
      expect(
        find.text(
          'Transcode\u00A0· Video codec not supported\u00A0· Video resolution '
          'above the client limit',
        ),
        findsOneWidget,
      );
      // Source against output.
      expect(find.text('HEVC\u00A0· 2160p\u00A0· HDR10'), findsOneWidget);
      expect(find.text('H.264\u00A0· 1080p\u00A0· SDR'), findsOneWidget);
      expect(find.text('EAC3\u00A0· 5.1'), findsWidgets);
      expect(find.text('mkv'), findsOneWidget);
      expect(find.text('mpegts'), findsOneWidget);
      // The facts.
      expect(find.text('8.2\u00A0Mbps'), findsOneWidget);
      expect(
        find.text('Decoding on videotoolbox\u00A0· encoding on videotoolbox'),
        findsOneWidget,
      );
      expect(find.text('1.4x'), findsOneWidget);
      expect(find.text('Burned in\u00A0· ita\u00A0· srt'), findsOneWidget);
      expect(find.text('Plex Living Room'), findsWidgets);
      await harness.unmount(tester);
    });

    testWidgets('offers the title of a movie by its TMDB id, the person by '
        'their name, and Stop', (tester) async {
      final client = _FixtureClient();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await open(tester, 'The Lantern Keeper');

      expect(find.text('Open title'), findsOneWidget);
      expect(find.text('Go to Anna'), findsOneWidget);
      expect(find.text('Stop stream'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('offers an episode as its series, found by one read of the '
        'show Tracearr names, and never by the episode\'s own ids', (
      tester,
    ) async {
      final client = _FixtureClient();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await open(tester, 'Harbor Lights\u00A0· S2 E5');

      expect(find.text('Open title'), findsOneWidget);
      expect(client.mediaAsked, ['d1d1d1d1-0000-4000-8000-0000000000b3']);
      expect(find.text('Go to Luca'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a series Tracearr holds no external id for is no door', (
      tester,
    ) async {
      final client = _FixtureClient()
        ..series = const TracearrMediaIdentity(type: TracearrMediaType.show);
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await open(tester, 'Harbor Lights\u00A0· S2 E5');

      expect(find.text('Open title'), findsNothing);
      expect(find.text('Go to Luca'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a series Tracearr does not know is no door, and no failure', (
      tester,
    ) async {
      final client = _FixtureClient()..series = null;
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await open(tester, 'Harbor Lights\u00A0· S2 E5');

      expect(find.text('Open title'), findsNothing);
      expect(find.byType(AppErrorState), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a movie asks nothing more: its own ids open it', (
      tester,
    ) async {
      final client = _FixtureClient();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await open(tester, 'The Lantern Keeper');

      expect(client.mediaAsked, isEmpty);
      await harness.unmount(tester);
    });

    testWidgets('the door to a person is found again after the people list '
        'failed once', (tester) async {
      final client = _FlakyPeople();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await open(tester, 'The Lantern Keeper');
      expect(find.text('Open title'), findsOneWidget, reason: 'the sheet');
      expect(find.textContaining('Go to'), findsNothing);

      // Closed and opened again: the list is asked for a second time, and
      // this time it answers.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await open(tester, 'The Lantern Keeper');

      expect(client.peopleAsked, 2);
      expect(find.text('Go to Anna'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a person two people share a name with is not a door', (
      tester,
    ) async {
      final client = _TwinsClient();
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await open(tester, 'The Lantern Keeper');

      expect(find.textContaining('Go to'), findsNothing);
      await harness.unmount(tester);
    });
  });

  group('the doors of the detail', () {
    testWidgets('the title lands under the tab it was opened from, and the '
        'person on a page of their own', (tester) async {
      recordPictures();
      final client = _FixtureClient();
      final harness = await ProfileHarness.start(
        _household,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      harness.network.followFakeTime(tester.binding);
      await tester.binding.setSurfaceSize(const Size(430, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        initialLocation: '/stack/tracearr/live',
        routes: [
          GoRoute(
            path: '/stack/tracearr/live',
            builder: (_, _) => const Scaffold(body: TracearrLiveScreen()),
            routes: [
              GoRoute(
                path: 'media/movie/:id',
                builder: (_, state) =>
                    Text('movie ${state.pathParameters['id']}'),
              ),
              GoRoute(
                path: 'person/:id',
                builder: (_, state) =>
                    Text('person ${state.pathParameters['id']}'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await harness.settle(tester);

      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open title'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open title'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/stack/tracearr/live/media/movie/603');

      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Go to Anna'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to Anna'));
      await tester.pumpAndSettle();
      expect(
        router.state.uri.path,
        '/stack/tracearr/live/person/7a3e91c4-5d28-4b6f-8e10-2f4a6c8d0b13',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('the doors of a sheet whose row has gone', () {
    testWidgets('the title still opens when the stream stopped meanwhile', (
      tester,
    ) async {
      recordPictures();
      final client = _FixtureClient();
      final harness = await ProfileHarness.start(
        _household,
        overrides: [tracearrClientProvider.overrideWithValue(client)],
      );
      harness.network.followFakeTime(tester.binding);
      await tester.binding.setSurfaceSize(const Size(430, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        initialLocation: '/stack/tracearr/live',
        routes: [
          GoRoute(
            path: '/stack/tracearr/live',
            builder: (_, _) => const Scaffold(body: TracearrLiveScreen()),
            routes: [
              GoRoute(
                path: 'media/movie/:id',
                builder: (_, state) =>
                    Text('movie ${state.pathParameters['id']}'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await harness.settle(tester);

      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();
      _stopBehindTheSheet(tester);
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('Open title'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open title'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/stack/tracearr/live/media/movie/603');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('Stop', () {
    Future<void> toStop(WidgetTester tester) async {
      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Stop stream'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop stream'));
      await tester.pumpAndSettle();
    }

    testWidgets('works from a sheet whose row has gone: the stream stopped by '
        'itself while the sheet was open', (tester) async {
      final client = _FixtureClient(stops: [const TracearrTerminated()]);
      final harness = await _pump(tester, const TracearrLiveScreen(), client);
      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceRecordRow), findsNWidgets(2));

      // The stream ends, and its row leaves the list under the open sheet. The
      // feed is gated off while a sheet covers the page, so the word reaches
      // the list the way a read that was already out would bring it.
      _stopBehindTheSheet(tester);
      await tester.pump();
      await tester.pump();
      expect(find.byType(ServiceRecordRow), findsNothing);

      await tester.ensureVisible(find.text('Stop stream'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop stream'));
      await tester.pumpAndSettle();

      expect(find.text('Stop this stream?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Stop stream'));
      await tester.pumpAndSettle();
      expect(client.stopped.single.id, _firstId);
      await harness.unmount(tester);
    });

    testWidgets('asks first, in neutral words, with a word for the viewer', (
      tester,
    ) async {
      final client = _FixtureClient(stops: [const TracearrTerminated()]);
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await toStop(tester);

      expect(find.text('Stop this stream?'), findsOneWidget);
      expect(find.text('Message for Anna\u00A0· optional'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Stop stream'), findsOneWidget);
      expect(find.text('Keep playing'), findsOneWidget);
      expect(client.stopped, isEmpty, reason: 'nothing before the person says');
      await harness.unmount(tester);
    });

    testWidgets('Keep playing leaves the stream alone', (tester) async {
      final client = _FixtureClient(stops: [const TracearrTerminated()]);
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await toStop(tester);
      await tester.tap(find.text('Keep playing'));
      await tester.pumpAndSettle();

      expect(client.stopped, isEmpty);
      expect(find.text('The Lantern Keeper'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('ends it with the word typed, takes the row off at once and '
        'says so', (tester) async {
      final client = _FixtureClient(stops: [const TracearrTerminated()]);
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await toStop(tester);
      await tester.enterText(find.byType(TextField), '  dinner is ready ');
      await tester.tap(find.widgetWithText(FilledButton, 'Stop stream'));
      await tester.pumpAndSettle();

      expect(client.stopped.single.id, _firstId);
      expect(client.stopped.single.reason, 'dinner is ready');
      expect(find.text('The Lantern Keeper'), findsNothing);
      expect(find.text('Stream stopped'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('with no word it sends none', (tester) async {
      final client = _FixtureClient(stops: [const TracearrTerminated()]);
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await toStop(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Stop stream'));
      await tester.pumpAndSettle();

      expect(client.stopped.single.reason, isEmpty);
      await harness.unmount(tester);
    });

    testWidgets('a Tracearr with no such route loses the control for this '
        'connection, and says it is not a fault', (tester) async {
      final client = _FixtureClient(
        stops: [const TracearrTerminateRouteAbsent()],
      );
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await toStop(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Stop stream'));
      await tester.pumpAndSettle();

      expect(find.text('This Tracearr cannot stop streams.'), findsOneWidget);
      // The row stands: nothing was stopped.
      expect(find.text('The Lantern Keeper'), findsOneWidget);

      // And the control is gone from every stream from then on.
      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();
      expect(find.text('Open title'), findsOneWidget);
      expect(find.text('Stop stream'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a stream that already ended refreshes the list and says so', (
      tester,
    ) async {
      final client = _FixtureClient(
        stops: [const TracearrTerminateStreamGone()],
      );
      final harness = await _pump(tester, const TracearrLiveScreen(), client);
      final before = client.reads;

      await toStop(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Stop stream'));
      await tester.pumpAndSettle();

      expect(find.text('That stream had already ended.'), findsOneWidget);
      expect(client.reads, greaterThan(before));
      await harness.unmount(tester);
    });

    testWidgets('a refusal surfaces as an error without the server\'s own '
        'words, and keeps the control', (tester) async {
      final client = _FixtureClient(
        stops: [
          const TracearrTerminateFailed(
            statusCode: 502,
            message: 'could not reach 192.168.1.20',
          ),
        ],
      );
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await toStop(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Stop stream'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not stop the stream. Tracearr refused (502).'),
        findsOneWidget,
      );
      expect(find.textContaining('192.168'), findsNothing);
      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();
      expect(find.text('Stop stream'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a failure of the transport is said in the classification\'s '
        'words', (tester) async {
      final client = _FixtureClient(stops: [StateError('boom')]);
      final harness = await _pump(tester, const TracearrLiveScreen(), client);

      await toStop(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Stop stream'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not stop the stream.'), findsOneWidget);
      expect(find.text('The Lantern Keeper'), findsOneWidget);
      await harness.unmount(tester);
    });
  });

  group('the Overview', () {
    testWidgets('draws the same rows, each a door to the detail', (
      tester,
    ) async {
      final client = _FixtureClient();
      final harness = await _pump(
        tester,
        const TracearrOverviewScreen(),
        client,
        overrides: [pollClockProvider.overrideWithValue(PollClock())],
      );

      expect(find.text('The Lantern Keeper'), findsOneWidget);
      expect(
        client.wires,
        hasLength(1),
        reason: 'moving while it is on screen',
      );
      await tester.tap(find.text('The Lantern Keeper'));
      await tester.pumpAndSettle();

      expect(find.text('Stop stream'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a violation row is a door to the violation itself', (
      tester,
    ) async {
      final client = _FixtureClient();
      final harness = await _pump(
        tester,
        const TracearrOverviewScreen(),
        client,
      );

      final row = tester.widget<ServiceOverviewRow>(
        find.widgetWithText(ServiceOverviewRow, 'Impossible travel'),
      );
      expect(row.onTap, isNotNull);
      expect(row.doorHint, 'opens the violation');
      expect(row.spoken, contains('Impossible travel'));
      await harness.unmount(tester);
    });
  });
}

/// A client whose event stream never opens.
class _FailingEvents extends _FixtureClient {
  @override
  Stream<TracearrEvent> events({
    List<String>? types,
    String? serverId,
    CancelToken? cancelToken,
    void Function(Duration retry)? onRetry,
  }) => Stream.error(StateError('refused'));
}

/// A client whose people list fails the first time it is asked, as one read
/// that did not get through does.
class _FlakyPeople extends _FixtureClient {
  int peopleAsked = 0;

  @override
  Future<TracearrPage<TracearrUser>> getUsers({
    String? cursor,
    int pageSize = 25,
    bool includeRemoved = false,
  }) {
    if (peopleAsked++ == 0) throw StateError('did not answer');
    return super.getUsers(
      cursor: cursor,
      pageSize: pageSize,
      includeRemoved: includeRemoved,
    );
  }
}

/// A client whose two people share a name.
class _TwinsClient extends _FixtureClient {
  @override
  Future<TracearrPage<TracearrUser>> getUsers({
    String? cursor,
    int pageSize = 25,
    bool includeRemoved = false,
  }) async => TracearrPage(
    items: [
      for (final id in ['a', 'b'])
        TracearrUser(id: id, username: 'Anna', accounts: const []),
    ],
  );
}
