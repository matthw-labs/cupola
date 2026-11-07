import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/stream_players.dart';

/// The links each Jellyfin app takes for an item, exactly, and the platforms
/// each one exists on. Pure: nothing here asks a platform anything.
void main() {
  final webUrl = Uri.parse(
    'https://jellyfin.example.com/web/index.html#!/details?id=abc',
  );

  group('the links', () {
    test('the browser opens the web client link it was given', () {
      expect(StreamPlayer.web.link(itemId: 'abc', webUrl: webUrl), webUrl);
    });

    test('Swiftfin takes the server, the viewer and the item', () {
      expect(
        StreamPlayer.swiftfin.link(
          itemId: 'item1',
          serverId: 'srv1',
          userId: 'usr1',
        ),
        Uri.parse('swiftfin://srv1/usr1/item/item1'),
      );
    });

    test('Swiftfin is not offered without the server or the viewer', () {
      expect(
        StreamPlayer.swiftfin.link(itemId: 'item1', userId: 'usr1'),
        isNull,
        reason: 'no server id',
      );
      expect(
        StreamPlayer.swiftfin.link(itemId: 'item1', serverId: 'srv1'),
        isNull,
        reason: 'no viewer id',
      );
      expect(
        StreamPlayer.swiftfin.link(
          itemId: 'item1',
          serverId: '',
          userId: 'usr1',
        ),
        isNull,
        reason: 'an empty server id is no id',
      );
    });

    test('Streamyfin opens the play screen of the item', () {
      expect(
        StreamPlayer.streamyfin.link(itemId: 'item1'),
        Uri.parse('streamyfin://topshelf/play?id=item1'),
      );
    });

    test('Fladder opens the details of the item, with three slashes', () {
      final link = StreamPlayer.fladder.link(itemId: 'item1');
      expect(link, isNotNull);
      expect(link.toString(), 'fladder:///details?id=item1');
    });

    test('an item id is encoded where it sits in a link', () {
      expect(
        StreamPlayer.streamyfin.link(itemId: 'a b&c').toString(),
        'streamyfin://topshelf/play?id=a+b%26c',
      );
    });

    test('the apps need no web link, and the browser needs no app id', () {
      expect(
        StreamPlayer.streamyfin.link(itemId: 'x', webUrl: webUrl)?.scheme,
        'streamyfin',
      );
      expect(StreamPlayer.web.link(itemId: 'x'), isNull);
    });
  });

  group('the platforms', () {
    test('Swiftfin is iOS only', () {
      expect(StreamPlayer.swiftfin.platforms, {TargetPlatform.iOS});
    });

    test('Streamyfin and Fladder are on the phones', () {
      for (final player in [StreamPlayer.streamyfin, StreamPlayer.fladder]) {
        expect(player.platforms, {TargetPlatform.iOS, TargetPlatform.android});
      }
    });

    test('the browser is on every platform', () {
      expect(StreamPlayer.web.platforms, containsAll(TargetPlatform.values));
    });
  });

  group('the probe and the scheme', () {
    test('each app is asked about its scheme, with nothing after it', () {
      expect(StreamPlayer.swiftfin.probe, Uri.parse('swiftfin://'));
      expect(StreamPlayer.streamyfin.probe, Uri.parse('streamyfin://'));
      expect(StreamPlayer.fladder.probe, Uri.parse('fladder://'));
    });

    test('the browser has no scheme to ask about: it is always there', () {
      expect(StreamPlayer.web.scheme, isNull);
      expect(StreamPlayer.web.probe, isNull);
    });
  });

  test('every player has the name and the line the sheet shows', () {
    expect(StreamPlayer.web.label, 'Jellyfin in the browser');
    expect(StreamPlayer.web.line, 'In your browser');
    expect(StreamPlayer.swiftfin.label, 'Swiftfin');
    expect(StreamPlayer.swiftfin.line, 'Opens its page');
    expect(StreamPlayer.streamyfin.label, 'Streamyfin');
    expect(StreamPlayer.streamyfin.line, 'Plays from where you stopped');
    expect(StreamPlayer.fladder.label, 'Fladder');
    expect(StreamPlayer.fladder.line, 'Opens its page');
  });

  group('Emby\'s players', () {
    test('the app takes the server and the item, one spelling a platform', () {
      expect(
        StreamPlayer.emby
            .link(itemId: '15', serverId: 'srv1', platform: TargetPlatform.iOS)
            .toString(),
        'emby://items?serverId=srv1&itemId=15',
      );
      expect(
        StreamPlayer.emby
            .link(
              itemId: '15',
              serverId: 'srv1',
              platform: TargetPlatform.android,
            )
            .toString(),
        'emby://items/srv1/15',
      );
    });

    test('the app is not offered without the server id, or off a phone', () {
      for (final serverId in [null, '']) {
        expect(
          StreamPlayer.emby.link(
            itemId: '15',
            serverId: serverId,
            platform: TargetPlatform.iOS,
          ),
          isNull,
        );
      }
      expect(
        StreamPlayer.emby.link(
          itemId: '15',
          serverId: 'srv1',
          platform: TargetPlatform.macOS,
        ),
        isNull,
      );
      expect(StreamPlayer.emby.platforms, {
        TargetPlatform.iOS,
        TargetPlatform.android,
      });
    });

    test('the browser opens the link it was given, on every platform', () {
      expect(StreamPlayer.embyWeb.link(itemId: 'x', webUrl: webUrl), webUrl);
      expect(
        StreamPlayer.embyWeb.platforms,
        containsAll(TargetPlatform.values),
      );
      expect(StreamPlayer.embyWeb.scheme, isNull);
      expect(StreamPlayer.embyWeb.probe, isNull);
      expect(StreamPlayer.emby.probe, Uri.parse('emby://'));
    });

    test('names and lines', () {
      expect(StreamPlayer.emby.label, 'Emby');
      expect(StreamPlayer.embyWeb.label, 'Emby in the browser');
      expect(StreamPlayer.embyWeb.line, 'In your browser');
    });
  });

  group('whose players are whose', () {
    test('Jellyfin keeps its three apps and the browser, in that order', () {
      expect(StreamPlayer.of(ServiceKey.jellyfin), [
        StreamPlayer.swiftfin,
        StreamPlayer.streamyfin,
        StreamPlayer.fladder,
        StreamPlayer.web,
      ]);
    });

    test('Emby has its app and the browser, and no Jellyfin player', () {
      expect(StreamPlayer.of(ServiceKey.emby), [
        StreamPlayer.emby,
        StreamPlayer.embyWeb,
      ]);
    });

    test('Plex has none: the browser link alone', () {
      expect(StreamPlayer.of(ServiceKey.plex), isEmpty);
    });

    test('every player belongs to exactly the server that lists it', () {
      for (final service in ServiceKey.values) {
        for (final player in StreamPlayer.of(service)) {
          expect(player.service, service, reason: player.name);
        }
      }
      // Nobody is listed twice, and nobody is orphaned: an Infuse that crept in
      // would be a value no server lists.
      final listed = [
        for (final service in ServiceKey.values) ...StreamPlayer.of(service),
      ];
      expect(listed.toSet(), StreamPlayer.values.toSet());
      expect(listed, hasLength(StreamPlayer.values.length));
      expect(StreamPlayer.values.map((p) => p.name), isNot(contains('infuse')));
    });

    test('exactly one browser per server that has players', () {
      for (final service in [ServiceKey.jellyfin, ServiceKey.emby]) {
        expect(
          StreamPlayer.of(service).where((p) => p.isBrowser),
          hasLength(1),
          reason: service.name,
        );
        expect(StreamPlayer.of(service).last.isBrowser, isTrue);
      }
    });
  });

  group('the platforms are told which schemes to ask about', () {
    // iOS hides a scheme that `LSApplicationQueriesSchemes` does not list, and
    // Android 11 hides a package a `<queries>` entry does not name: an app
    // that is installed would read as missing and never be offered.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    for (final player in StreamPlayer.values.where((p) => p.scheme != null)) {
      final scheme = player.scheme!;
      if (player.platforms.contains(TargetPlatform.iOS)) {
        test('${player.name} is in Info.plist', () {
          expect(plist, contains('<string>$scheme</string>'));
        });
      }
      if (player.platforms.contains(TargetPlatform.android)) {
        test('${player.name} is in the Android queries', () {
          expect(manifest, contains('android:scheme="$scheme"'));
        });
      }
    }
  });
}
