import 'dart:async';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';

/// How the live feed is reaching Live right now.
enum TracearrLink {
  /// Opening the event stream, and none has spoken yet.
  connecting,

  /// The event stream is open and has spoken: events move the rows.
  streaming,

  /// The event stream failed or dropped: the rows are read again on a timer
  /// until it speaks once more.
  polling,
}

/// The wait before the first reconnection, when the server names none.
const Duration kTracearrReconnectBase = Duration(seconds: 2);

/// The longest the wait between two reconnections grows to.
const Duration kTracearrReconnectCap = Duration(seconds: 60);

/// How often the rows are read again while the event stream is down.
const Duration kTracearrFallbackEvery = Duration(seconds: 10);

/// How long a new connection may stay silent before it is given up on.
/// Tracearr says `ready` the moment a client connects, so ten seconds with not
/// a byte means a proxy is holding the first frames, or the address answers and
/// goes nowhere.
const Duration kTracearrFirstWordWithin = Duration(seconds: 10);

/// How long an open connection may stay silent before it is given up on: two
/// of Tracearr's pings (about 25 seconds apart) and a margin. A connection that
/// dies without a close, a wifi handoff or a dropped NAT entry, raises no error
/// at all, and this is the only thing that ends it.
const Duration kTracearrSilenceWithin = Duration(seconds: 60);

/// The wait before reconnection number [attempt] (0 for the first): the
/// server's own `retry:` hint (or [kTracearrReconnectBase]) doubled for each
/// failure since the stream last spoke, up to [kTracearrReconnectCap].
Duration tracearrReconnectDelay(int attempt, {Duration? hint}) {
  final base = hint ?? kTracearrReconnectBase;
  final grown = base * (1 << attempt.clamp(0, 16));
  return grown > kTracearrReconnectCap ? kTracearrReconnectCap : grown;
}

/// Keeps Tracearr's event stream open for as long as it lives, and reads the
/// rows on a timer while it cannot.
///
/// Plain Dart, with the stream, the event sink and the read handed in, so the
/// reconnection, the growing wait and the fallback are tested with a fake
/// stream and a fake clock. It does not know when it should run: its owner
/// creates it when the page that shows the rows is on screen and the app is in
/// the foreground, and [dispose]s it when either stops, which is the whole of
/// the gate (see `tracearrLiveFeedProvider`).
///
/// The sequence: open the stream; the first thing it says makes the link
/// [TracearrLink.streaming] and forgets the failures so far; when it ends or
/// fails the link is [TracearrLink.polling], the fallback poll starts, and the
/// stream is opened again after [tracearrReconnectDelay]. The poll stops the
/// moment the stream speaks. A failed attempt is not reported anywhere: the
/// poll's reads are what show the person that Tracearr did not answer.
///
/// A connection that never errors and never ends is the other way a stream
/// fails, so a silence deadline is held over it: [kTracearrFirstWordWithin]
/// for the first word and [kTracearrSilenceWithin] after it, restarted by every
/// word, a ping included ([TracearrKeepAlive]). Past it the stream is lost the
/// same way a drop is.
class TracearrFeedLoop {
  TracearrFeedLoop({
    required this.open,
    required this.onEvent,
    required void Function() onPoll,
    required PollClock clock,
    this.onLink,
  }) : _poller = GatedPollTimer(
         id: 'tracearr.live.fallback',
         interval: kTracearrFallbackEvery,
         onTick: onPoll,
         clock: clock,
       );

  /// Opens the stream. [onRetry] hears the server's `retry:` hint.
  final Stream<TracearrEvent> Function(void Function(Duration) onRetry) open;

  final void Function(TracearrEvent event) onEvent;

  /// Hears the link change, for a test or a readout that wants it.
  final void Function(TracearrLink link)? onLink;

  final GatedPollTimer _poller;
  StreamSubscription<TracearrEvent>? _subscription;
  Timer? _reconnect;
  Timer? _silence;
  Duration? _hint;
  int _failures = 0;
  bool _disposed = false;
  TracearrLink _link = TracearrLink.connecting;

  TracearrLink get link => _link;

  /// Opens the stream for the first time.
  void start() {
    onLink?.call(_link);
    _connect();
  }

  void _setLink(TracearrLink link) {
    if (_disposed || link == _link) return;
    _link = link;
    _poller.setLive(link == TracearrLink.polling);
    onLink?.call(link);
  }

  void _connect() {
    if (_disposed) return;
    _reconnect = null;
    var spoke = false;
    final Stream<TracearrEvent> stream;
    try {
      stream = open((retry) => _hint = retry);
    } on Object {
      _lost();
      return;
    }
    _watchSilence(kTracearrFirstWordWithin);
    _subscription = stream.listen(
      (event) {
        if (_disposed) return;
        _watchSilence(kTracearrSilenceWithin);
        if (!spoke) {
          spoke = true;
          _failures = 0;
          _setLink(TracearrLink.streaming);
        }
        // A ping only says the connection is alive: it moves no row.
        if (event is! TracearrKeepAlive) onEvent(event);
      },
      onError: (Object _) => _lost(),
      onDone: _lost,
      cancelOnError: true,
    );
  }

  /// Gives the connection [within] to say another word.
  void _watchSilence(Duration within) {
    _silence?.cancel();
    _silence = Timer(within, _lost);
  }

  void _lost() {
    if (_disposed) return;
    _silence?.cancel();
    _silence = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _setLink(TracearrLink.polling);
    _reconnect?.cancel();
    _reconnect = Timer(
      tracearrReconnectDelay(_failures, hint: _hint),
      _connect,
    );
    _failures++;
  }

  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _reconnect = null;
    _silence?.cancel();
    _silence = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _poller.dispose();
  }
}
