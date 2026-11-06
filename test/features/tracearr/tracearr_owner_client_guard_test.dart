import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/app_sources.dart';

/// The owner's client is born in one place,
/// `TracearrOwnerClient.forReach` (`lib/features/tracearr/data/
/// tracearr_owner_client.dart`).
///
/// Two credentials, two jobs: the public key reads and the owner's bearer
/// writes, and a client that mixed them would send a session where a key is
/// expected or the other way round. The owner's client also owes the route:
/// the address, the gateway's access and the pin are the connection's
/// route's (`reachOf`), and one built from the saved address works at home
/// and fails away from it. A source scan, because either regression is one
/// argument in a diff that works on a server reached the usual way.
///
/// Read for each construction: the constructor behind the factory is private,
/// so the compiler holds that nothing else builds one; this holds that every
/// call through the factory says where (`reach:`), that the bearer's header,
/// its name on the wire and its storage keys are written in the files that
/// own them and no others, and that the public client never learns of an
/// owner.
void main() {
  final libFiles = {
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') &&
          !file.path.startsWith('lib/core/generated/') &&
          !isServerStandIn(file.path))
        file.path: _withoutComments(file.readAsStringSync()),
  };
  const clientFile = 'lib/features/tracearr/data/tracearr_owner_client.dart';
  const publicFile = 'lib/features/tracearr/data/tracearr_client.dart';

  test('the constructor is private and there is one factory', () {
    final code = libFiles[clientFile]!;
    expect(code, contains('TracearrOwnerClient._('));
    expect(
      RegExp(r'factory TracearrOwnerClient\.\w+\(').allMatches(code),
      hasLength(1),
    );
    expect(code, contains('factory TracearrOwnerClient.forReach('));
  });

  test('forReach is named in the client file and the one provider that '
      'hands it out', () {
    final offenders = [
      for (final MapEntry(key: path, value: code) in libFiles.entries)
        if (path != clientFile && code.contains('TracearrOwnerClient.forReach'))
          path,
    ];
    expect(offenders, [
      'lib/features/tracearr/data/tracearr_owner_accounts.dart',
    ]);
  });

  test(
    'every call through the factory says where the connection is reached',
    () {
      final calls = [
        for (final MapEntry(key: path, value: code) in libFiles.entries)
          for (final match in RegExp(
            r'tracearrOwnerClientFactoryProvider\)\(',
          ).allMatches(code))
            (
              site: '$path:${_lineOf(code, match.start)}',
              arguments: _argumentsAt(code, match.end - 1) ?? '',
            ),
      ];
      // A scanner that found nothing would pass the check below.
      expect(calls.length, greaterThanOrEqualTo(5));
      expect(
        [
          for (final call in calls)
            if (!call.arguments.contains('reach:')) call.site,
        ],
        isEmpty,
        reason:
            'An owner client built without `reach:`. Pass the route\'s reach '
            '(watchTransport, connectionReachProvider) so it goes where the '
            'connection answers now.',
      );
    },
  );

  test('a client built off a transport is told when it may not ask', () {
    // The violation page's client and the sign-in's ways read are built off
    // a transport, and away from home with no address away they must not
    // dial.
    for (final path in [
      'lib/features/tracearr/presentation/tracearr_violations_provider.dart',
      'lib/features/tracearr/data/tracearr_owner_accounts.dart',
    ]) {
      expect(libFiles[path], contains('.onlyAtHomeOf(ServiceKey.tracearr)'));
    }
  });

  test('the bearer is named on the wire in the owner client alone', () {
    final offenders = [
      for (final MapEntry(key: path, value: code) in libFiles.entries)
        if (path != clientFile &&
            (code.contains('set-auth-token') ||
                code.contains('sign-in/email') ||
                code.contains('sign-in/username') ||
                code.contains('plex_pin')))
          path,
    ];
    expect(offenders, isEmpty);
    expect(libFiles[clientFile], contains("'set-auth-token'"));
  });

  test('the owner storage keys are written where storage lives', () {
    const owners = {
      'lib/features/settings/domain/service_instance.dart',
      'lib/features/settings/data/settings_service.dart',
    };
    final offenders = [
      for (final MapEntry(key: path, value: code) in libFiles.entries)
        if (!owners.contains(path) &&
            (code.contains('ownerSessionStorageKey') ||
                code.contains('ownerStorageKey')))
          path,
    ];
    expect(offenders, isEmpty);
  });

  test(
    'the bearer is read from the session by the owner\'s providers alone',
    () {
      const readers = {
        'lib/features/settings/data/settings_service.dart',
        'lib/features/tracearr/data/tracearr_owner_accounts.dart',
        'lib/features/tracearr/presentation/tracearr_violations_provider.dart',
        'lib/features/tracearr/domain/models/tracearr_owner_session.dart',
      };
      final offenders = [
        for (final MapEntry(key: path, value: code) in libFiles.entries)
          if (!readers.contains(path) &&
              RegExp(r'owner(\?|!)?\.token\b').hasMatch(code))
            path,
      ];
      expect(offenders, isEmpty);
    },
  );

  test('the public client never learns of an owner, nor the owner client of '
      'the key', () {
    final publicCode = libFiles[publicFile]!;
    expect(publicCode.toLowerCase(), isNot(contains('owner')));
    expect(publicCode, isNot(contains('set-auth-token')));
    final ownerCode = libFiles[clientFile]!;
    expect(ownerCode, isNot(contains('TracearrClient(')));
    expect(ownerCode, isNot(contains('trr_pub_')));
  });

  test('no log, print or failure text names a token or a password', () {
    for (final path in [
      clientFile,
      'lib/features/tracearr/data/tracearr_owner_accounts.dart',
      'lib/features/tracearr/presentation/tracearr_owner_sign_in_flow.dart',
      'lib/features/tracearr/presentation/tracearr_owner_notice.dart',
    ]) {
      final code = libFiles[path]!;
      expect(code, isNot(contains('debugPrint(')), reason: path);
      expect(code, isNot(contains('print(')), reason: path);
      expect(code, isNot(contains('log(')), reason: path);
    }
  });
}

int _lineOf(String code, int offset) =>
    '\n'.allMatches(code.substring(0, offset)).length + 1;

/// The text between the parenthesis at [open] and the one that closes it.
String? _argumentsAt(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    if (code[i] == '(') depth++;
    if (code[i] == ')') {
      depth--;
      if (depth == 0) return code.substring(open + 1, i);
    }
  }
  return null;
}

/// [source] with every `//` comment line blanked, line breaks kept.
String _withoutComments(String source) => source
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');
