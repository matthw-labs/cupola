import 'dart:isolate';

import 'package:cupola/features/jellyfin/domain/models/jellyfin_item_mapper.dart';

/// Maps a decoded list, moving to an isolate once the page is big enough to
/// drop a frame.
///
/// [mapper] must be a top-level function: `Isolate.run` sends the closure, and
/// one that captured `this` would drag a `Dio` across the port and throw. Kept
/// apart from the client so a dialect, which decodes rows of its own, shares
/// the one threshold instead of growing a second one.
///
/// Anything that is not a `List` answers empty: the shapes a media server can
/// send for a list (a bare array, an envelope) are unwrapped by the caller,
/// and a caller that forgot gets no rows rather than a cast error.
Future<List<T>> mapInIsolate<T>(
  Object? raw,
  List<T> Function(Object?) mapper,
) async {
  if (raw is! List) return const [];
  if (raw.length <= kJellyfinIsolateMapThreshold) return mapper(raw);
  return Isolate.run(() => mapper(raw));
}
