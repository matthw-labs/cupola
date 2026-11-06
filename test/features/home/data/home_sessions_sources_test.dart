import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

/// What the Home and Activity read again for Now playing includes the cache of
/// every media server: a server left out keeps its stale rows, because the
/// per-connection family collapses onto that cache.
void main() {
  test('every media server\'s sessions cache is among the sources', () {
    for (final service in mediaServers) {
      expect(
        homeSessionsSources,
        contains(streamBackendOf(service).sessions),
        reason: service.name,
      );
    }
  });

  test('so are the family over its connections and the merge', () {
    expect(homeSessionsSources, contains(streamSessionsForProvider));
    expect(homeSessionsSources, contains(streamActivityProvider));
  });
}
