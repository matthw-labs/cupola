import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The global search asks what is on every media server.
void main() {
  test('every media server is among the services it fans out to', () {
    expect(globalSearchServices, containsAll(mediaServers));
  });

  test('in the registry\'s order', () {
    final order = ServiceKey.values;
    final indexes = [for (final s in globalSearchServices) order.indexOf(s)];
    expect(indexes, [...indexes]..sort());
  });
}
