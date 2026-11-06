/// The live feed: Tracearr's event stream held open while a page needs it, with
/// the wait before each reconnection growing, the rows read again every ten
/// seconds while it is down, and everything stopped the moment the page or the
/// app goes away. The stream is a controller the test writes to, and time is
/// the test binding's, so a drop, a failed attempt and a long outage each take
/// no time at all.
library;

import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/data/tracearr_live_feed.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

TracearrStream _stream(String id, {int progressMs = 1000, int bitrate = 800}) =>
    TracearrStream.fromJson({
      'id': id,
      'username': 'Anna',
      'media_title': 'Title $id',
      'media_type': 'movie',
      'state': 'playing',
      'progress_ms': progressMs,
      'duration_ms': 100000,
      'bitrate': bitrate,
    });

/// One connection the loop opened: the test writes events to it and ends it.
class _Connection {
  _Connection(this.openedAt, this.onRetry)
    : controller = StreamController<TracearrEvent>();

  final Duration openedAt;
  final void Function(Duration) onRetry;
  final StreamController<TracearrEvent> controller;
  bool get cancelled => !controller.hasListener && _listened;
  bool _listened = false;

  Stream<TracearrEvent> get stream {
    controller.onListen = () => _listened = true;
    return controller.stream;
  }
}

/// A clock the test advances with the binding's, so the poll's catch-up rule
/// sees the time that passed.
class _Time {
  Duration elapsed = Duration.zero;
  final start = DateTime(2026, 11, 6, 12);

  DateTime now() => start.add(elapsed);

  Future<void> advance(WidgetTester tester, Duration by) async {
    var left = by;
    // In steps of a second: a timer set inside a timer fires in its turn.
    while (left > Duration.zero) {
      final step = left > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : left;
      elapsed += step;
      await tester.pump(step);
      left -= step;
    }
  }
}

void main() {
  group('the loop', () {
    late _Time time;
    late PollClock clock;
    late List<_Connection> opened;
    late List<TracearrEvent> heard;
    late List<TracearrLink> links;
    late int polls;
    late TracearrFeedLoop loop;
    bool openThrows = false;

    setUp(() {
      time = _Time();
      clock = PollClock()..now = time.now;
      opened = [];
      heard = [];
      links = [];
      polls = 0;
      openThrows = false;
    });

    /// A test of the loop, which is disposed before the test ends: the
    /// binding checks for pending timers before any tear-down runs.
    void loopTest(String name, Future<void> Function(WidgetTester) body) =>
        testWidgets(name, (tester) async {
          await body(tester);
          loop.dispose();
          await tester.pump();
        });

    TracearrFeedLoop make() {
      loop = TracearrFeedLoop(
        open: (onRetry) {
          if (openThrows) throw StateError('no');
          final connection = _Connection(time.elapsed, onRetry);
          opened.add(connection);
          return connection.stream;
        },
        onEvent: heard.add,
        onLink: links.add,
        onPoll: () => polls++,
        clock: clock,
      );
      return loop;
    }

    loopTest('opens the stream, and its first word makes it the link', (
      tester,
    ) async {
      make().start();
      await tester.pump();

      expect(opened, hasLength(1));
      expect(loop.link, TracearrLink.connecting);

      opened.single.controller.add(const TracearrReady());
      await tester.pump();

      expect(loop.link, TracearrLink.streaming);
      expect(heard.single, isA<TracearrReady>());
      expect(links, [TracearrLink.connecting, TracearrLink.streaming]);
    });

    loopTest('a drop falls back to polling and reconnects after the base '
        'wait', (tester) async {
      make().start();
      opened.single.controller.add(const TracearrReady());
      await tester.pump();

      await opened.single.controller.close();
      await tester.pump();
      expect(loop.link, TracearrLink.polling);
      expect(opened, hasLength(1));

      await time.advance(tester, const Duration(seconds: 1));
      expect(opened, hasLength(1), reason: 'not yet: two seconds');
      await time.advance(tester, const Duration(seconds: 1));
      expect(opened, hasLength(2));
    });

    loopTest('the polling reads every ten seconds while the stream is '
        'down, and stops when it speaks again', (tester) async {
      openThrows = true;
      make().start();
      await tester.pump();
      expect(loop.link, TracearrLink.polling);

      await time.advance(tester, const Duration(seconds: 10));
      expect(polls, 1);
      await time.advance(tester, const Duration(seconds: 10));
      expect(polls, 2);

      openThrows = false;
      // The attempts were at 0, 2, 6 and 14 seconds; the next is at 30, and
      // this time it gets through.
      await time.advance(tester, const Duration(seconds: 11));
      expect(opened, hasLength(1));
      opened.single.controller.add(const TracearrReady());
      await tester.pump();
      expect(loop.link, TracearrLink.streaming);

      final whileDown = polls;
      await time.advance(tester, const Duration(seconds: 50));
      expect(polls, whileDown, reason: 'no poll while the stream is open');
    });

    loopTest('a connection that opens and never says a word is given up on '
        'after ten seconds, and the rows are read meanwhile', (tester) async {
      make().start();
      await time.advance(tester, const Duration(seconds: 9));
      expect(loop.link, TracearrLink.connecting);
      expect(opened.single.cancelled, isFalse);

      await time.advance(tester, const Duration(seconds: 1));
      expect(loop.link, TracearrLink.polling);
      expect(opened.single.cancelled, isTrue);
      expect(links, [TracearrLink.connecting, TracearrLink.polling]);

      // The wait before the next attempt is the base two seconds, and the poll
      // starts reading ten seconds after the stream was given up on.
      await time.advance(tester, const Duration(seconds: 2));
      expect(opened, hasLength(2));
      await time.advance(tester, const Duration(seconds: 8));
      expect(polls, 1);
    });

    loopTest('a connection that spoke and then goes quiet is given up on '
        'after a minute', (tester) async {
      make().start();
      opened.single.controller.add(const TracearrReady());
      await tester.pump();
      expect(loop.link, TracearrLink.streaming);

      await time.advance(tester, const Duration(seconds: 59));
      expect(loop.link, TracearrLink.streaming);

      await time.advance(tester, const Duration(seconds: 1));
      expect(loop.link, TracearrLink.polling);
      expect(opened.single.cancelled, isTrue);
      expect(
        opened,
        hasLength(1),
        reason: 'the reconnection waits two seconds',
      );
      await time.advance(tester, const Duration(seconds: 2));
      expect(opened, hasLength(2));
    });

    loopTest('a ping is a sign of life, and moves nothing', (tester) async {
      make().start();
      opened.single.controller.add(const TracearrReady());
      await tester.pump();

      // Pings every 25 seconds for five minutes: the minute's silence never
      // runs out.
      for (var i = 0; i < 12; i++) {
        await time.advance(tester, const Duration(seconds: 25));
        opened.single.controller.add(const TracearrKeepAlive());
        await tester.pump();
      }

      expect(loop.link, TracearrLink.streaming);
      expect(opened, hasLength(1));
      expect(polls, 0);
      expect(heard.single, isA<TracearrReady>());
    });

    loopTest('a ping is also a first word', (tester) async {
      make().start();
      await time.advance(tester, const Duration(seconds: 5));
      opened.single.controller.add(const TracearrKeepAlive());
      await tester.pump();

      expect(loop.link, TracearrLink.streaming);
      await time.advance(tester, const Duration(seconds: 30));
      expect(loop.link, TracearrLink.streaming);
      expect(heard, isEmpty);
    });

    loopTest('the loop reconnects on that schedule when attempts keep '
        'failing', (tester) async {
      make().start();
      final starts = <int>[];
      // Every connection the loop opens fails before it says a word.
      var seen = 0;
      void failTheNew() {
        while (seen < opened.length) {
          starts.add(opened[seen].openedAt.inSeconds);
          opened[seen].controller.addError(StateError('refused'));
          seen++;
        }
      }

      failTheNew();
      for (var second = 0; second < 140; second++) {
        await time.advance(tester, const Duration(seconds: 1));
        failTheNew();
      }
      await tester.pump();

      // Opened at 0, then 2, 6, 14, 30, 62, 122 seconds: each wait twice the
      // one before, ending at the minute's cap.
      expect(starts.take(7), [0, 2, 6, 14, 30, 62, 122]);
    });

    loopTest('a connection that spoke starts the wait over', (tester) async {
      make().start();
      // Fail twice: waits of two and four seconds.
      opened[0].controller.addError(StateError('a'));
      await time.advance(tester, const Duration(seconds: 2));
      opened[1].controller.addError(StateError('b'));
      await time.advance(tester, const Duration(seconds: 4));
      expect(opened, hasLength(3));

      // The third speaks, then drops: the next wait is the base again.
      opened[2].controller.add(const TracearrReady());
      await tester.pump();
      await opened[2].controller.close();
      await tester.pump();
      final droppedAt = time.elapsed;
      await time.advance(tester, const Duration(seconds: 2));

      expect(opened, hasLength(4));
      expect(opened[3].openedAt - droppedAt, const Duration(seconds: 2));
    });

    loopTest('the server\'s retry hint is the wait', (tester) async {
      make().start();
      opened.single.onRetry(const Duration(seconds: 5));
      opened.single.controller.add(const TracearrReady());
      await tester.pump();
      await opened.single.controller.close();
      await tester.pump();

      await time.advance(tester, const Duration(seconds: 4));
      expect(opened, hasLength(1));
      await time.advance(tester, const Duration(seconds: 1));
      expect(opened, hasLength(2));
    });

    loopTest('disposing closes the connection and stops every timer', (
      tester,
    ) async {
      make().start();
      opened.single.controller.add(const TracearrReady());
      await tester.pump();

      loop.dispose();
      await tester.pump();
      expect(opened.single.cancelled, isTrue);

      // Nothing runs on afterwards: no reconnect, no poll.
      await time.advance(tester, const Duration(minutes: 5));
      expect(opened, hasLength(1));
      expect(polls, 0);
    });

    loopTest('disposing while waiting to reconnect stops the reconnect', (
      tester,
    ) async {
      make().start();
      opened.single.controller.addError(StateError('x'));
      await tester.pump();

      loop.dispose();
      await time.advance(tester, const Duration(minutes: 5));

      expect(opened, hasLength(1));
    });
  });

  group('the provider', () {
    late _Time time;
    late PollClock clock;

    setUp(() {
      time = _Time();
      clock = PollClock()..now = time.now;
    });

    final containers = <ProviderContainer>[];

    /// A test of the provider, whose containers are disposed before it ends:
    /// the binding checks for pending timers before any tear-down runs.
    void providerTest(String name, Future<void> Function(WidgetTester) body) =>
        testWidgets(name, (tester) async {
          await body(tester);
          for (final container in containers) {
            container.dispose();
          }
          containers.clear();
          await tester.pump();
        });

    ProviderContainer start(_FakeClient client) {
      final container = ProviderContainer(
        overrides: [
          tracearrClientProvider.overrideWithValue(client),
          pollClockProvider.overrideWithValue(clock),
        ],
      );
      containers.add(container);
      return container;
    }

    providerTest('events move the rows the page draws', (tester) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a'), _stream('b')]),
      ]);
      final container = start(client);
      container.listen(tracearrLiveFeedProvider, (_, _) {});
      await container.read(tracearrLiveProvider.future);
      await tester.pump();
      final connection = client.connections.single;

      connection.add(TracearrStreamStarted(_stream('c')));
      connection.add(const TracearrStreamStopped(id: 'a'));
      connection.add(
        const TracearrStreamProgress(id: 'b', progressMs: 42000, bitrate: 900),
      );
      await tester.pump();

      final rows = container.read(tracearrLiveProvider).requireValue;
      expect(rows.streams.map((s) => s.id), ['b', 'c']);
      expect(rows.streams.first.progressMs, 42000);
      expect(rows.summary.total, 2);
    });

    providerTest('the stream saying it is open reads the rows again, so what '
        'happened while it was not is read and not guessed', (tester) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a')]),
        TracearrStreams(streams: [_stream('a'), _stream('late')]),
      ]);
      final container = start(client);
      container.listen(tracearrLiveFeedProvider, (_, _) {});
      await container.read(tracearrLiveProvider.future);
      await tester.pump();

      client.connections.single.add(const TracearrReady());
      await tester.pump();
      await tester.pump();

      expect(client.reads, 2);
      expect(
        container
            .read(tracearrLiveProvider)
            .requireValue
            .streams
            .map((s) => s.id),
        ['a', 'late'],
      );
    });

    providerTest('an event that arrives while a read is out is applied over '
        'the read', (tester) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a')]),
        TracearrStreams(
          streams: [_stream('a', progressMs: 1000), _stream('b')],
        ),
      ]);
      final container = start(client);
      container.listen(tracearrLiveFeedProvider, (_, _) {});
      await container.read(tracearrLiveProvider.future);
      await tester.pump();
      final connection = client.connections.single;

      client.hold = Completer<void>();
      connection.add(const TracearrReady());
      await tester.pump();
      // The read is out; the stream says more before it answers.
      connection.add(const TracearrStreamStopped(id: 'a'));
      connection.add(const TracearrStreamProgress(id: 'b', progressMs: 77000));
      await tester.pump();
      client.hold!.complete();
      await tester.pump();
      await tester.pump();

      final rows = container.read(tracearrLiveProvider).requireValue;
      expect(rows.streams.map((s) => s.id), ['b']);
      expect(rows.streams.single.progressMs, 77000);
    });

    providerTest('a read already out is not asked twice', (tester) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a')]),
      ]);
      final container = start(client);
      await container.read(tracearrLiveProvider.future);
      final notifier = container.read(tracearrLiveProvider.notifier);

      client.hold = Completer<void>();
      final first = notifier.refresh();
      final second = notifier.refresh();
      client.hold!.complete();
      await Future.wait([first, second]);

      expect(client.reads, 2, reason: 'the opening read and one more');
    });

    providerTest('a read still out when the connection is switched is dropped, '
        'not written over the new connection\'s rows', (tester) async {
      final before = _FakeClient([
        TracearrStreams(streams: [_stream('old')]),
        TracearrStreams(streams: [_stream('old'), _stream('stale')]),
      ]);
      final after = _FakeClient([
        TracearrStreams(streams: [_stream('new')]),
      ]);
      _Switch.first = before;
      final container = ProviderContainer(
        overrides: [
          tracearrClientProvider.overrideWith((ref) => ref.watch(_switch)),
          pollClockProvider.overrideWithValue(clock),
        ],
      );
      containers.add(container);
      await container.read(tracearrLiveProvider.future);
      final notifier = container.read(tracearrLiveProvider.notifier);

      before.hold = Completer<void>();
      final inFlight = notifier.refresh();
      container.read(_switch.notifier).use(after);
      final rebuilt = await container.read(tracearrLiveProvider.future);
      expect(rebuilt.streams.map((s) => s.id), ['new']);

      before.hold!.complete();
      await inFlight;

      final rows = container.read(tracearrLiveProvider).requireValue;
      expect(rows.streams.map((s) => s.id), ['new']);
    });

    providerTest('a read that fails keeps the rows and carries the failure', (
      tester,
    ) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a')]),
      ]);
      final container = start(client);
      await container.read(tracearrLiveProvider.future);

      client.failReads = true;
      await container.read(tracearrLiveProvider.notifier).refresh();

      final state = container.read(tracearrLiveProvider);
      expect(state.hasError, isTrue);
      expect(state.hasValue, isTrue);
      expect(state.requireValue.streams.single.id, 'a');

      // The next word on the stream clears it.
      client.failReads = false;
      container
          .read(tracearrLiveProvider.notifier)
          .apply(TracearrStreamUpdated(_stream('a', progressMs: 9000)));
      expect(container.read(tracearrLiveProvider).hasError, isFalse);
    });

    providerTest('a stopped stream is taken off at once by hand', (
      tester,
    ) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a'), _stream('b')]),
      ]);
      final container = start(client);
      await container.read(tracearrLiveProvider.future);

      container.read(tracearrLiveProvider.notifier).drop('a');

      expect(
        container
            .read(tracearrLiveProvider)
            .requireValue
            .streams
            .map((s) => s.id),
        ['b'],
      );
    });

    providerTest('when the event stream cannot be opened the rows are read '
        'every ten seconds, and it is tried again', (tester) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a')]),
        TracearrStreams(streams: [_stream('a'), _stream('b')]),
      ])..eventsFail = true;
      final container = start(client);
      container.listen(tracearrLiveFeedProvider, (_, _) {});
      await container.read(tracearrLiveProvider.future);
      await tester.pump();
      expect(client.reads, 1);

      await time.advance(tester, const Duration(seconds: 10));
      await tester.pump();

      expect(client.reads, 2);
      expect(
        container.read(tracearrLiveProvider).requireValue.streams,
        hasLength(2),
      );
      expect(client.opened, greaterThan(1), reason: 'reconnection was tried');
    });

    providerTest('the event stream dropping mid-way is the same: polling, then '
        'back on the stream', (tester) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a')]),
      ]);
      final container = start(client);
      container.listen(tracearrLiveFeedProvider, (_, _) {});
      await container.read(tracearrLiveProvider.future);
      await tester.pump();
      client.connections.single.add(const TracearrReady());
      await tester.pump();
      await tester.pump();
      final readsWhileStreaming = client.reads;

      await client.connections.single.close();
      await time.advance(tester, const Duration(seconds: 10));
      await tester.pump();

      expect(client.connections, hasLength(2), reason: 'it came back');
      client.connections.last.add(const TracearrReady());
      await tester.pump();
      await tester.pump();
      expect(client.reads, greaterThan(readsWhileStreaming));
    });

    providerTest('letting go of the feed closes the connection', (
      tester,
    ) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a')]),
      ]);
      final container = start(client);
      final subscription = container.listen(
        tracearrLiveFeedProvider,
        (_, _) {},
      );
      await container.read(tracearrLiveProvider.future);
      await tester.pump();
      expect(client.connections.single.hasListener, isTrue);

      subscription.close();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));

      expect(client.connections.single.hasListener, isFalse);
      await time.advance(tester, const Duration(minutes: 3));
      expect(client.connections, hasLength(1));
    });
  });

  group('the gate', () {
    Future<(_FakeClient, ProviderContainer)> pump(
      WidgetTester tester, {
      required bool branchActive,
    }) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a')]),
      ]);
      final container = ProviderContainer(
        overrides: [
          tracearrClientProvider.overrideWithValue(client),
          pollClockProvider.overrideWithValue(PollClock()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => BranchActivityScope(
                isActive: branchActive,
                branchIndex: 0,
                child: const _Watcher(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (client, container);
    }

    testWidgets('a page that is not on screen opens nothing', (tester) async {
      final (client, _) = await pump(tester, branchActive: false);

      expect(client.connections, isEmpty);
    });

    testWidgets('a page on screen holds one connection', (tester) async {
      final (client, container) = await pump(tester, branchActive: true);

      expect(client.connections, hasLength(1));
      expect(client.connections.single.hasListener, isTrue);

      // The page goes before the test ends: the connection's silence deadline
      // is a timer, and the binding checks for pending ones.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump();
    });

    testWidgets('the app leaving the foreground closes it, and coming back '
        'opens another', (tester) async {
      final (client, container) = await pump(tester, branchActive: true);

      container.read(appInForegroundProvider.notifier).set(false);
      await tester.pump();
      await tester.pump();
      expect(client.connections.single.hasListener, isFalse);
      final count = client.connections.length;

      container.read(appInForegroundProvider.notifier).set(true);
      await tester.pump();
      await tester.pump();
      expect(client.connections, hasLength(count + 1));
      expect(client.connections.last.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump();
    });

    testWidgets('leaving the page closes it', (tester) async {
      final client = _FakeClient([
        TracearrStreams(streams: [_stream('a')]),
      ]);
      final container = ProviderContainer(
        overrides: [
          tracearrClientProvider.overrideWithValue(client),
          pollClockProvider.overrideWithValue(PollClock()),
        ],
      );
      addTearDown(container.dispose);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(navigatorKey: key, home: const SizedBox()),
        ),
      );
      unawaited(
        key.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const _Watcher()),
        ),
      );
      await tester.pumpAndSettle();
      expect(client.connections.single.hasListener, isTrue);

      key.currentState!.pop();
      await tester.pumpAndSettle();

      expect(container.exists(tracearrLiveFeedProvider), isFalse);
      expect(client.connections.single.hasListener, isFalse);
    });
  });
}

/// A page that keeps the feed only while it is the page on screen.
class _Watcher extends ConsumerWidget {
  const _Watcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watchWhileLive(context, tracearrLiveFeedProvider);
    return const SizedBox();
  }
}

/// A client with no socket: the rows a read gives are the test's, and the
/// event stream is a controller per connection.
class _FakeClient extends TracearrClient {
  _FakeClient(this._reads)
    : super(baseUrl: 'http://tracearr.test', apiKey: 'trr_pub_test');

  final List<TracearrStreams> _reads;
  final connections = <_Wire>[];

  /// Reads asked so far, and connections opened (those that failed too).
  int reads = 0;
  int opened = 0;

  bool eventsFail = false;
  bool failReads = false;

  /// Holds the next read until the test lets it go.
  Completer<void>? hold;

  @override
  Future<TracearrStreams> getStreams({String? serverId}) async {
    final index = reads++;
    final held = hold;
    if (held != null && index > 0) await held.future;
    if (failReads) throw StateError('did not answer');
    return _reads[index.clamp(0, _reads.length - 1)];
  }

  @override
  Stream<TracearrEvent> events({
    List<String>? types,
    String? serverId,
    CancelToken? cancelToken,
    void Function(Duration retry)? onRetry,
  }) {
    opened++;
    if (eventsFail) return Stream.error(StateError('refused'));
    final wire = _Wire();
    connections.add(wire);
    return wire.stream;
  }
}

/// Which client the connection reads through, switched by a test the way a
/// person switches connections.
final _switch = NotifierProvider<_Switch, TracearrClient>(_Switch.new);

class _Switch extends Notifier<TracearrClient> {
  static late TracearrClient first;

  @override
  TracearrClient build() => first;

  void use(TracearrClient client) => state = client;
}

/// One connection of the fake client.
class _Wire {
  final _controller = StreamController<TracearrEvent>();
  bool _listened = false;

  Stream<TracearrEvent> get stream {
    _controller.onListen = () => _listened = true;
    return _controller.stream;
  }

  bool get hasListener => _listened && _controller.hasListener;

  void add(TracearrEvent event) => _controller.add(event);

  Future<void> close() => _controller.close();
}
