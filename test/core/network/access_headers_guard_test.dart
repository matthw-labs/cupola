import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every transport in `lib/` carries the connection's access headers: the
/// sixth obligation of a client, beside ADR-6's five.
///
/// A gateway in front of a service (Cloudflare Access, a proxy's password)
/// stands in front of every request the connection makes, so a token that
/// reaches the API and not the artwork, the WebSocket or the probe leaves a
/// screen reading "behind Cloudflare Access" for a connection the user has
/// already fixed. A source scan because the regression is one construction in
/// a diff that leaves the argument out and still works at home, where nothing
/// stands in front.
///
/// Read for each construction: every `guardedDio(`, `ApiClient(`,
/// `WebSocket.connect(`, Socket.IO `io(` and every client class the app
/// builds, outside comments and declarations, must name the access in its
/// arguments. One that truly cannot is listed in [_exceptions] with the
/// reason, and that entry must still match something.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/core/generated/'))
      .toList(growable: false);

  final constructions = [
    for (final file in libFiles)
      ..._constructionsIn(file.path, file.readAsStringSync()),
  ];

  test('there are constructions to read', () {
    // A scanner that silently found nothing would pass the check below.
    expect(constructions.length, greaterThan(40));
    expect(
      constructions.map((c) => c.opener).toSet(),
      containsAll(['guardedDio', 'ApiClient', 'WebSocket.connect', 'io']),
    );
  });

  test('every transport carries the connection\'s access headers', () {
    final offenders = [
      for (final construction in constructions)
        if (!construction.arguments.contains('access') &&
            !_exceptions.containsKey(construction.site))
          '${construction.path}:${construction.line}  ${construction.opener}(',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A transport here does not pass the connection\'s access headers. '
          'Pass `accessHeaders:` (the connection\'s `access.headers()`), or '
          'list the site in _exceptions with the reason it cannot.',
    );
  });

  test('every exception still matches a construction', () {
    final sites = constructions.map((c) => c.site).toSet();
    expect(_exceptions.keys.where((site) => !sites.contains(site)), isEmpty);
  });

  test('Dockge\'s Socket.IO options carry the access headers', () {
    // The one exception's other half: the options its `io(` takes.
    final source = File(
      'lib/features/dockge/data/dockge_client.dart',
    ).readAsStringSync();
    expect(source, contains('.setExtraHeaders(accessHeaders)'));
  });
}

/// `file  opener` → why it passes no access of its own.
const _exceptions = <String, String>{
  'lib/features/discover/data/plex_tv_client.dart  guardedDio':
      'plex.tv is the sign-in provider the person chose, not a connection: '
      'no gateway of theirs stands in front of it, and a connection\'s '
      'access must never travel to a third party.',
  'lib/features/dockge/data/dockge_client.dart  io':
      'Socket.IO takes its headers in the options it is handed, built two '
      'lines up with setExtraHeaders(accessHeaders); the connector it calls '
      'adds them to the upgrade as well.',
};

/// The transports, and the client classes that own one.
const _openers = [
  'guardedDio',
  'ApiClient',
  'ApiClient.authenticatedBy',
  'WebSocket.connect',
  'io',
  'QbittorrentClient',
  'SabnzbdClient',
  'NzbgetClient',
  'TransmissionClient',
  'NpmClient',
  'UnraidClient',
  'JellyfinClient',
  'TracearrClient',
  'PlexClient',
  'TrueNasWsClient',
  'DockgeClient',
];

typedef _Construction = ({
  String path,
  int line,
  String opener,
  String arguments,
});

extension on _Construction {
  String get site => '$path  $opener';
}

final _opener = RegExp(
  r'(?<!\w)(' + _openers.map(RegExp.escape).join('|') + r')\(',
);

Iterable<_Construction> _constructionsIn(String path, String source) sync* {
  final code = _withoutComments(source);
  for (final match in _opener.allMatches(code)) {
    final open = match.end - 1;
    final arguments = _balanced(code, open);
    if (arguments == null) continue;
    // A declaration (`ApiClient({`, `Dio guardedDio({`), not a call.
    if (arguments.trimLeft().startsWith('{')) continue;
    final opener = match.group(1)!;
    // `socket_io.io(` only: any other `io(` is not Socket.IO.
    if (opener == 'io' &&
        !code.substring(0, match.start).endsWith('socket_io.')) {
      continue;
    }
    yield (
      path: path,
      line: '\n'.allMatches(code.substring(0, match.start)).length + 1,
      opener: opener,
      arguments: arguments,
    );
  }
}

/// The text between the parenthesis at [open] and the one that closes it.
String? _balanced(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final char = code[i];
    if (char == '(') depth++;
    if (char == ')') {
      depth--;
      if (depth == 0) return code.substring(open + 1, i);
    }
  }
  return null;
}

/// [source] with every `//` comment blanked, line breaks kept so line numbers
/// still point at the source.
String _withoutComments(String source) => source
    .split('\n')
    .map((line) {
      final trimmed = line.trimLeft();
      return trimmed.startsWith('//') ? '' : line;
    })
    .join('\n');
