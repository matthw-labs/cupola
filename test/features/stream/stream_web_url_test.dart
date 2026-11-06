import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/stream_web_url.dart';

/// The web client link of an item, one spelling per media server: the else of
/// a ternary gave every server that was not Jellyfin Plex's.
void main() {
  Uri? urlOf(ServiceKey service, {String? machineId = 'srv-1'}) =>
      streamItemWebUrl(
        service: service,
        baseUrl: 'https://media.example.com/',
        itemId: 'it-9',
        plexMachineId: machineId,
      );

  test('every media server has a web client link of its own', () {
    final seen = <Uri>{};
    for (final service in mediaServers) {
      final url = urlOf(service);
      expect(url, isNotNull, reason: service.name);
      expect(url!.host, 'media.example.com', reason: service.name);
      expect(seen.add(url), isTrue, reason: '${service.name} is unique');
    }
  });

  test('Jellyfin opens the details page of the item', () {
    expect(
      urlOf(ServiceKey.jellyfin).toString(),
      'https://media.example.com/web/index.html#!/details?id=it-9',
    );
  });

  test('Plex opens the metadata key on its machine, and none without one', () {
    expect(
      urlOf(ServiceKey.plex).toString(),
      'https://media.example.com/web/index.html#!/server/srv-1/details'
      '?key=%2Flibrary%2Fmetadata%2Fit-9',
    );
    expect(urlOf(ServiceKey.plex, machineId: null), isNull);
    expect(urlOf(ServiceKey.plex, machineId: ''), isNull);
  });

  test('a service that is no media server has no web client link', () {
    for (final service in ServiceKey.values.where((s) => !s.isMediaServer)) {
      expect(urlOf(service), isNull, reason: service.name);
    }
  });

  test('no address, no link', () {
    for (final service in mediaServers) {
      expect(
        streamItemWebUrl(service: service, baseUrl: '', itemId: 'it-9'),
        isNull,
        reason: service.name,
      );
    }
  });
}
