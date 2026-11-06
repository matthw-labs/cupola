import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/home/domain/set_up_next.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Any media server set up stands for the one Set up next would suggest.
void main() {
  List<String> titles(Set<ServiceKey> setUp) => [
    for (final suggestion in setUpNextOf(setUp.contains)) suggestion.title,
  ];

  const rest = {
    ServiceKey.seerr,
    ServiceKey.transmission,
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.bazarr,
  };

  test('without a media server, one is suggested', () {
    expect(titles(rest), [Lexicon.setUp(ServiceKey.jellyfin.title)]);
  });

  for (final service in mediaServers) {
    test('${service.name} set up, no media server is suggested', () {
      expect(titles({...rest, service}), isEmpty);
    });
  }
}
