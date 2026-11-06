import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/data/tracearr_live_feed.dart';
import 'package:cupola/features/tracearr/data/tracearr_live_reducer.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

/// What is playing now: the one list the Live tab and the Overview's Playing
/// section both draw, so a stream is the same row, with the same figures,
/// wherever it is read.
///
/// It starts from a read of the streams. What keeps it moving is the live feed
/// ([tracearrLiveFeedProvider]), which exists only while a page that shows the
/// rows is on screen: events are applied here ([apply]), and a read is made
/// again ([refresh]) when the event stream says it is open (`ready`: whatever
/// happened while it was not is read, not guessed) and on every tick of the
/// fallback poll.
///
/// A failed read over rows we hold keeps the rows and carries the failure, as
/// every list does: the page draws them under its band.
final tracearrLiveProvider =
    AsyncNotifierProvider<TracearrLiveNotifier, TracearrStreams>(
      TracearrLiveNotifier.new,
      retry: noProviderRetry,
    );

class TracearrLiveNotifier extends AsyncNotifier<TracearrStreams> {
  /// Events that arrived while a read was out: the read was asked before them
  /// and may have been answered without them, so they are applied over it.
  List<TracearrEvent>? _heldDuringRead;

  @override
  Future<TracearrStreams> build() {
    _heldDuringRead = null;
    return ref.watch(tracearrClientProvider).getStreams();
  }

  /// Applies one event of the event stream.
  void apply(TracearrEvent event) {
    if (!ref.mounted) return;
    if (event is TracearrReady) {
      unawaited(refresh());
      return;
    }
    _heldDuringRead?.add(event);
    final current = state.value;
    if (current == null) return;
    final next = applyTracearrEvent(current, event);
    if (!identical(next, current)) state = AsyncData(next);
  }

  /// Reads the streams again, in place: the rows stay on the page while the
  /// read is out, and a read already out is not asked twice.
  Future<void> refresh() async {
    if (!ref.mounted || _heldDuringRead != null) return;
    final held = _heldDuringRead = <TracearrEvent>[];
    try {
      final fresh = await ref.read(tracearrClientProvider).getStreams();
      if (!ref.mounted) return;
      state = AsyncData(applyTracearrEvents(fresh, held));
    } catch (error, stack) {
      if (!ref.mounted) return;
      state = AsyncError<TracearrStreams>(error, stack);
    } finally {
      _heldDuringRead = null;
    }
  }

  /// Takes a stream off the list at once: Tracearr ended it, and the stop
  /// event that follows would say the same.
  void drop(String id) {
    final current = state.value;
    if (!ref.mounted || current == null) return;
    state = AsyncData(withoutTracearrStream(current, id));
  }
}

/// The feed that keeps [tracearrLiveProvider] moving, alive only while it is
/// watched, and watched only while a page that shows the rows is the one on
/// screen with the app in the foreground (`WidgetRef.watchWhileLive`).
///
/// Listening is the cost: an event stream is a connection held open on the
/// person's Tracearr, and one nobody is looking at is exactly what the gate
/// exists to prevent. Dropping the last watch disposes the provider, which
/// closes the connection and the fallback poll with it.
final tracearrLiveFeedProvider = Provider.autoDispose<void>((ref) {
  final client = ref.watch(tracearrClientProvider);
  final live = ref.read(tracearrLiveProvider.notifier);
  final loop = TracearrFeedLoop(
    open: (onRetry) => client.events(types: _liveEvents, onRetry: onRetry),
    onEvent: live.apply,
    onPoll: () => unawaited(live.refresh()),
    clock: ref.read(pollClockProvider),
  );
  ref.onDispose(loop.dispose);
  // After the build: the loop may report a link at once, and a provider is
  // not written to while it is built.
  scheduleMicrotask(() {
    if (ref.mounted) loop.start();
  });
});

/// The events Live reads: a stream's life. Violations and server health are
/// other pages' news.
const List<String> _liveEvents = [
  'stream.started',
  'stream.updated',
  'stream.progress',
  'stream.stopped',
];

/// The connections whose Tracearr has no route to end a stream, so Stop is not
/// offered for them from then on.
///
/// In memory, by connection id: an upgrade of the server is the only thing
/// that brings the route back, and a new launch asks once again, which costs
/// one tap and no more.
final tracearrStopAbsentProvider =
    NotifierProvider<TracearrStopAbsentNotifier, Set<String>>(
      TracearrStopAbsentNotifier.new,
    );

class TracearrStopAbsentNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void mark(String connectionId) => state = {...state, connectionId};
}

/// Whether the connection Tracearr is read through can end a stream, as far as
/// we know: true until its Tracearr answered that it has no such route.
final tracearrCanStopProvider = Provider<bool>((ref) {
  final id = ref.watch(activeInstanceProvider(ServiceKey.tracearr))?.id ?? '';
  return !ref.watch(tracearrStopAbsentProvider).contains(id);
});
