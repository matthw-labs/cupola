import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_identity.dart';

/// The one line a settings footer prints, and the one risk the file admits.
///
/// `app_identity.dart` is a deliberate refusal of `package_info_plus`. The
/// project takes no new dependencies, and a const beats a platform channel for
/// a string read before any async work is allowed. The price is that the version
/// tracks `pubspec.yaml` by hand, and a hand-tracked constant with nothing
/// watching it is a constant that drifts: the app's only other version literal,
/// the Plex `X-Plex-Version` header, had already gone stale at 0.8.0 while the
/// pubspec said 1.0.0. This is the watcher.
void main() {
  group('app identity', () {
    test('the version matches pubspec, which nothing else enforces', () {
      final pubspec = File('pubspec.yaml').readAsLinesSync();
      final versionLine = pubspec.firstWhere(
        (line) => line.startsWith('version:'),
        orElse: () => '',
      );
      expect(versionLine, isNotEmpty, reason: 'pubspec has no version:');

      // `1.0.0+1`: the build number is deliberately not part of the
      // user-facing string, so only the part before `+` is compared.
      final declared = versionLine.split(':').last.trim().split('+').first;
      expect(
        kAppVersion,
        declared,
        reason:
            'kAppVersion tracks pubspec by hand; update it in '
            'lib/core/app_identity.dart when the pubspec version moves',
      );
    });

    // Apache-2.0 rather than MIT is load-bearing rather than decorative: the
    // relicense landed on this branch only, so a footer hardcoding the other one
    // would make a legal claim about the wrong tree. `LICENSE` at the root is
    // the authority and the const has to agree with it.
    test('the licence names the file actually shipped at the root', () {
      final licence = File('LICENSE').readAsStringSync();
      expect(kAppLicence, 'Apache-2.0');
      expect(licence, contains('Apache License'));
      expect(licence, contains('Version 2.0'));
    });

    // The footer's exact sentence, assembled once so a second surface wanting
    // this line prints the same one rather than an em-dash version of it.
    test('the footer line is name, version, licence', () {
      expect(kAppIdentityLine, 'Cupola 1.1.0-beta\u00A0· Apache-2.0');
      expect(kAppIdentityLine, startsWith(kAppName));
      expect(kAppIdentityLine, endsWith(kAppLicence));
    });
  });
}
