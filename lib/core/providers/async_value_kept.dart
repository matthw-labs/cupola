import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [AsyncValue.whenData] for what a page draws while its sources are read
/// again.
extension AsyncValueKept<T> on AsyncValue<T> {
  /// [whenData] that keeps the answer a reload is about to replace.
  ///
  /// Riverpod's own [whenData] turns a reload (a poll's invalidate, a pull,
  /// a source the provider watches moving) into a bare `AsyncLoading` with no
  /// value: a page that maps its answer through it drew its skeleton for the
  /// instant of every tick, and the rows under it jumped up and back (the
  /// "flash" of a room every 15 s). Here a reload over an answer maps that
  /// answer, so the page keeps it until the new one arrives, as an unmapped
  /// value already does. A first load, a failure and an answer are
  /// [whenData]'s.
  AsyncValue<R> whenDataKept<R>(R Function(T value) cb) {
    if (isLoading && hasValue && !hasError) {
      try {
        return AsyncData<R>(cb(requireValue));
      } catch (error, stack) {
        return AsyncError<R>(error, stack);
      }
    }
    return whenData(cb);
  }
}
