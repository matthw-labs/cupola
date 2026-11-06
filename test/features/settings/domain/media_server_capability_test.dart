import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

/// What a service is, asked as a capability: the sites that used to name
/// Jellyfin and Plex read these, and the lists below are what they walk.
void main() {
  group('the media server capabilities', () {
    // A tripwire, on purpose: every other test here walks the lists the
    // capabilities derive, so a wrong capability would shrink what they check
    // without failing. A new media server edits this table.
    test('the capabilities, service by service', () {
      expect(mediaServers, [
        ServiceKey.jellyfin,
        ServiceKey.plex,
        ServiceKey.emby,
      ]);
      expect(sessionServices, [
        ServiceKey.jellyfin,
        ServiceKey.plex,
        ServiceKey.emby,
      ]);
      expect(ServiceKey.values.where((s) => s.speaksMediaBrowser), [
        ServiceKey.jellyfin,
        ServiceKey.emby,
      ]);
      expect(ServiceKey.values.where((s) => s.needsViewerSelection), [
        ServiceKey.jellyfin,
        ServiceKey.emby,
      ]);
      expect(ServiceKey.values.where((s) => s.mountsConnectionInView), [
        ServiceKey.jellyfin,
        ServiceKey.plex,
        ServiceKey.emby,
        ServiceKey.tracearr,
      ]);
    });

    test('Tracearr is in the band and is not a media server, and gives no '
        'sessions yet', () {
      const service = ServiceKey.tracearr;
      expect(service.domain, ServiceDomain.stream);
      expect(service.isMediaServer, isFalse);
      expect(service.speaksMediaBrowser, isFalse);
      expect(service.needsViewerSelection, isFalse);
      // The merge of its streams into Now playing is a later lot's: flipping
      // this earlier would send Tracearr through the media servers' session
      // code, which has no client for it.
      expect(service.givesSessions, isFalse);
      expect(sessionServices, isNot(contains(service)));
      expect(mediaServers, isNot(contains(service)));
    });

    test('the media servers are the services that answer isMediaServer', () {
      expect(mediaServers, ServiceKey.values.where((s) => s.isMediaServer));
      expect(mediaServers, isNotEmpty);
    });

    test('a media server says who is playing', () {
      for (final service in mediaServers) {
        expect(service.givesSessions, isTrue, reason: service.name);
      }
    });

    test('the playing services are in registry order and hold every '
        'media server', () {
      expect(sessionServices, ServiceKey.values.where((s) => s.givesSessions));
      expect(sessionServices, containsAll(mediaServers));
    });

    test('what speaks the MediaBrowser API is a media server that picks a '
        'viewer', () {
      for (final service in ServiceKey.values.where(
        (s) => s.speaksMediaBrowser,
      )) {
        expect(service.isMediaServer, isTrue, reason: service.name);
        expect(service.needsViewerSelection, isTrue, reason: service.name);
      }
    });

    test('only Jellyfin hides its library list from a household member', () {
      // Measured on Emby 4.10.2: `/Library/VirtualFolders/Query` answers a
      // member's token, while Users, Devices and Tasks are refused.
      expect(ServiceKey.values.where((s) => s.librariesNeedAdministrator), [
        ServiceKey.jellyfin,
      ]);
    });

    test('a service that is no media server is handed none of their lists', () {
      for (final service in ServiceKey.values.where((s) => !s.isMediaServer)) {
        expect(mediaServers, isNot(contains(service)), reason: service.name);
        expect(service.speaksMediaBrowser, isFalse, reason: service.name);
      }
    });

    test('the Stream band mounts the visit\'s connection', () {
      for (final service in ServiceDomain.stream.services) {
        expect(service.mountsConnectionInView, isTrue, reason: service.name);
      }
      for (final service in ServiceKey.values.where(
        (s) => s.domain != ServiceDomain.stream,
      )) {
        expect(service.mountsConnectionInView, isFalse, reason: service.name);
      }
    });

    test('every media server sits in the Stream band', () {
      // The band groups what is for watching; a media server out of it would
      // have no room in the stack for its libraries and sessions.
      for (final service in mediaServers) {
        expect(service.domain, ServiceDomain.stream, reason: service.name);
      }
    });
  });
}
