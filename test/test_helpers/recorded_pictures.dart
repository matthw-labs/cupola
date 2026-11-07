import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client;

import 'package:cupola/core/network/pinned_image_cache.dart';

/// What the pinned image cache was asked for, the key and all: a picture goes
/// out through it or not at all. Nothing is fetched.
class RecordedPictures implements BaseCacheManager {
  final requests = <({String url, Map<String, String>? headers})>[];

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    requests.add((url: url, headers: headers));
    return Stream.error(StateError('no picture in a test'));
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _NoTransport implements Client {
  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// The pictures asked for since [recordPictures] was last called.
late RecordedPictures pictures;

/// Routes every picture a widget asks the pinned image cache for to a log,
/// and fetches nothing: the cache's own store needs `path_provider`, which a
/// test has no plugin for. Put back when the test ends.
void recordPictures() {
  pictures = RecordedPictures();
  pinnedImageCacheBuilder =
      ({
        required cacheKey,
        required fingerprint,
        required host,
        required port,
      }) => (manager: pictures, transport: _NoTransport());
  addTearDown(() {
    resetPinnedImageCaches();
    pinnedImageCacheBuilder = defaultPinnedImageCacheBuilder;
  });
}
