import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/app_sources.dart';

/// A Seerr client is born in one place, `seerrClientFor`
/// (`lib/features/discover/data/seerr_session.dart`).
///
/// Seerr is reached two ways, the API key and an account's session, and both
/// owe it a CSRF token when its protection is on. A client built anywhere
/// else knows only the key: an account reaches Seerr as nobody through it,
/// and with the protection on every write it sends is refused as if the key
/// were wrong. A source scan, because that regression is one construction in
/// a diff that works on a server with neither.
///
/// Read for each construction: every `ApiClient(` and
/// `ApiClient.authenticatedBy(` in `lib/` is listed in [_apiClientSites]
/// with the services it builds, and none is Seerr's outside the session
/// file; every `SeerrService(` takes a client from the Seerr constructor;
/// `watchApiClient` is never asked for Seerr; and the session cookie's name
/// is written in the session file alone.
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

  final apiClients = [
    for (final MapEntry(key: path, value: code) in libFiles.entries)
      ..._callsIn(path, code, _apiClientOpener),
  ];
  final seerrServices = [
    for (final MapEntry(key: path, value: code) in libFiles.entries)
      ..._callsIn(path, code, RegExp(r'(?<!\w)SeerrService\(')),
  ];

  test('there are constructions to read', () {
    expect(apiClients.length, greaterThan(5));
    expect(seerrServices.length, greaterThanOrEqualTo(4));
  });

  test('every ApiClient is built where it is known whose it is', () {
    final unknown = [
      for (final call in apiClients)
        if (!_apiClientSites.containsKey(call.path))
          '${call.path}:${call.line}',
    ];
    expect(
      unknown,
      isEmpty,
      reason:
          'A new ApiClient construction. If it can reach Seerr, build it '
          'with seerrClientFor instead; otherwise list the file in '
          '_apiClientSites with the services it builds.',
    );
  });

  test('every listed ApiClient site still builds one', () {
    final paths = apiClients.map((call) => call.path).toSet();
    expect(
      _apiClientSites.keys.where((path) => !paths.contains(path)),
      isEmpty,
    );
  });

  test('every SeerrService takes the Seerr constructor\'s client', () {
    final offenders = [
      for (final call in seerrServices)
        if (!_seerrConstructors.any(call.declaration.contains))
          '${call.path}:${call.line}',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A SeerrService built over a client that did not come from '
          'seerrClientFor (or watchSeerrClient, or the probe\'s '
          'seerrClientFactoryProvider).',
    );
  });

  test('watchApiClient is never asked for Seerr', () {
    final offenders = [
      for (final MapEntry(key: path, value: code) in libFiles.entries)
        for (final match in RegExp(
          r'watchApiClient\(\s*ref,\s*ServiceKey\.seerr',
        ).allMatches(code))
          '$path:${_lineOf(code, match.start)}',
    ];
    expect(offenders, isEmpty);
  });

  test('every Seerr client is told where its connection is reached', () {
    // A Seerr client built without `reach:` goes to the address at home with
    // no pin: right for a test, and for a sign-in tried at an address being
    // typed, and wrong for every saved connection away from home. The callers
    // in `lib/` all say where, so a new one has to.
    final calls = [
      for (final MapEntry(key: path, value: code) in libFiles.entries)
        for (final match in _seerrReachOpener.allMatches(code))
          if (!_declares(code, match.start))
            (
              site: '$path:${_lineOf(code, match.start)}  ${match.group(1)}(',
              arguments: _argumentsAt(code, match.end - 1) ?? '',
            ),
    ];
    // A scanner that found nothing would pass the check below.
    expect(calls.length, greaterThanOrEqualTo(8));
    expect(
      [
        for (final call in calls)
          if (!call.arguments.contains('reach:')) call.site,
      ],
      isEmpty,
      reason:
          'A Seerr client built without `reach:`. Pass the route\'s reach '
          '(watchTransport, connectionReachProvider, or reachOf with the '
          'route) so it goes where the connection answers now.',
    );
  });

  test('the session cookie is named in the session file alone', () {
    final offenders = [
      for (final MapEntry(key: path, value: code) in libFiles.entries)
        if (path != _sessionFile && code.contains('connect.sid')) path,
    ];
    expect(offenders, isEmpty);
    expect(libFiles[_sessionFile], contains("'connect.sid'"));
  });

  group('a connection reached at two addresses', () {
    // One Seerr, at home on the LAN and away through a tunnel whose gateway
    // asks for a token. Its client is built where the route is, and what
    // the server hands out stays on the connection's own two origins.
    const home = 'http://192.168.1.30:5055';
    const away = 'https://seerr.example.com';
    const elsewhere = 'https://other.example.net';
    const token = CloudflareServiceToken(
      clientId: 'id.access',
      clientSecret: 'tunnel-secret',
    );
    const reachedAway = (url: away, access: token, pin: null);

    const account = ServiceInstance(
      id: 'seerr',
      service: ServiceKey.seerr,
      url: home,
      account: SeerrAccountSignIn(
        kind: SeerrAccountKind.local,
        login: 'anna',
        session: 'anna-session',
      ),
      away: ConnectionAddress(url: away, access: token),
    );
    final key = account.copyWith(credential: 'seerr-key', clearAccount: true);

    test(
      'a client built away goes to the address away, with its access',
      () async {
        final server = _Seerr();
        final client = seerrClientFor(account, reach: reachedAway);
        addTearDown(client.close);
        client.dio.httpClientAdapter = server;

        await client.get('/api/v1/request');

        final sent = server.sent.single;
        expect(sent.uri.origin, away);
        expect(sent.headers['CF-Access-Client-Secret'], 'tunnel-secret');
      },
    );

    test('the session goes to both of its origins and to no other', () async {
      final server = _Seerr();
      final client = seerrClientFor(account, reach: reachedAway);
      addTearDown(client.close);
      client.dio.httpClientAdapter = server;

      await client.get('/api/v1/request');
      await client.dio.getUri<dynamic>(Uri.parse('$home/api/v1/request'));
      await client.dio.getUri<dynamic>(Uri.parse('$elsewhere/api/v1/request'));

      expect(
        [for (final request in server.sent) request.cookie('connect.sid')],
        ['anna-session', 'anna-session', null],
      );
    });

    test('a session handed back by another origin is not kept', () async {
      final kept = <String>[];
      final server = _Seerr(
        cookies: (request) => ['connect.sid=from-${request.uri.host}; Path=/'],
      );
      final client = seerrClientFor(
        account.copyWith(
          account: const SeerrAccountSignIn(kind: SeerrAccountKind.local),
        ),
        reach: reachedAway,
        events: SeerrSessionEvents(onSession: kept.add),
      );
      addTearDown(client.close);
      client.dio.httpClientAdapter = server;

      await client.dio.getUri<dynamic>(Uri.parse('$elsewhere/api/v1/status'));
      await client.get('/api/v1/status');

      expect(kept, ['from-seerr.example.com']);
    });

    test('the CSRF answer is kept and asked for per origin, and sent to no '
        'other', () async {
      // Each origin hands out its own pair, and refuses a write without it.
      final server = _Seerr(
        cookies: (request) => switch (request.uri.path) {
          '/api/v1/settings/public' => [
            '_csrf=secret-${request.uri.host}; Path=/; HttpOnly',
            'XSRF-TOKEN=token-${request.uri.host}; Path=/',
          ],
          _ => const [],
        },
        refuses: (request) =>
            request.method == 'POST' &&
            request.headers['X-XSRF-TOKEN'] != 'token-${request.uri.host}',
      );
      final client = seerrClientFor(key, reach: reachedAway);
      addTearDown(client.close);
      client.dio.httpClientAdapter = server;

      // Away: refused, the token asked of the address away, sent again.
      await client.post('/api/v1/request', data: const {'mediaId': 1});
      // At home: the token away is not sent; home is asked for its own.
      await client.dio.postUri<dynamic>(
        Uri.parse('$home/api/v1/request'),
        data: const {'mediaId': 2},
      );
      // Elsewhere: neither origin's pair goes there.
      await client.dio.getUri<dynamic>(Uri.parse('$elsewhere/api/v1/status'));

      final writes = [
        for (final request in server.sent)
          if (request.method == 'POST')
            (
              request.uri.origin,
              request.headers['X-XSRF-TOKEN'],
              request.cookie('_csrf'),
            ),
      ];
      expect(writes, [
        (away, null, null),
        (away, 'token-seerr.example.com', 'secret-seerr.example.com'),
        ('http://192.168.1.30:5055', null, null),
        (
          'http://192.168.1.30:5055',
          'token-192.168.1.30',
          'secret-192.168.1.30',
        ),
      ]);
      expect(
        [
          for (final request in server.sent)
            if (request.uri.path == '/api/v1/settings/public')
              request.uri.origin,
        ],
        [away, 'http://192.168.1.30:5055'],
      );
      final third = server.sent.last;
      expect(third.uri.origin, elsewhere);
      expect(third.cookie('_csrf'), isNull);
      expect(third.headers['X-XSRF-TOKEN'], isNull);
    });
  });
}

/// One request as the fake server saw it.
typedef _Sent = ({String method, Uri uri, Map<String, dynamic> headers});

extension on _Sent {
  /// The value of cookie [name] the request carried, or null.
  String? cookie(String name) {
    final header = headers.entries
        .where((entry) => entry.key.toLowerCase() == 'cookie')
        .map((entry) => '${entry.value}')
        .firstOrNull;
    for (final pair in (header ?? '').split(';')) {
      final at = pair.indexOf('=');
      if (at > 0 && pair.substring(0, at).trim() == name) {
        return pair.substring(at + 1).trim();
      }
    }
    return null;
  }
}

/// A Seerr that answers every request with `{}`, the cookies [cookies] hands
/// it, and `403 invalid csrf token` for the requests [refuses] picks.
class _Seerr implements HttpClientAdapter {
  _Seerr({List<String> Function(_Sent request)? cookies, this.refuses})
    : cookies = cookies ?? ((_) => const []);

  final List<String> Function(_Sent request) cookies;
  final bool Function(_Sent request)? refuses;
  final sent = <_Sent>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    final request = (
      method: options.method,
      uri: options.uri,
      headers: Map<String, dynamic>.of(options.headers),
    );
    sent.add(request);
    final refused = refuses?.call(request) ?? false;
    return ResponseBody.fromString(
      jsonEncode(refused ? {'message': 'invalid csrf token'} : {}),
      refused ? 403 : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        'set-cookie': cookies(request),
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _sessionFile = 'lib/features/discover/data/seerr_session.dart';

/// Every way a Seerr client is built for a connection, which says where.
final _seerrReachOpener = RegExp(
  r'(?<!\w)(seerrClientFor|SeerrAuthService\.forConnection|signOutOfSeerr|'
  r'diagnoseSeerr|seerrClientFactoryProvider\)|seerrClientFactory)\(',
);

/// Whether the name at [offset] is being declared rather than called: a
/// return type (`ApiClient seerrClientFor(`) or `factory` before it.
bool _declares(String code, int offset) {
  final before = code
      .substring(code.lastIndexOf('\n', offset) + 1, offset)
      .trim();
  return before == 'factory' || RegExp(r'^[A-Z][\w<>?, ]*$').hasMatch(before);
}

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

/// Where an `ApiClient` is built, and whose it is.
const _apiClientSites = <String, String>{
  _sessionFile:
      'Seerr, the only place: the API key and an account, with the session '
      'and CSRF interceptors.',
  'lib/features/settings/data/settings_provider.dart':
      'watchApiClient, for the X-Api-Key services, which asserts it is never '
      'Seerr.',
  'lib/features/settings/data/service_verification.dart':
      'The connection test of the X-Api-Key services, which asserts it is '
      'never Seerr: Seerr has its own branch with seerrClientFor.',
  'lib/features/services/presentation/services_probe.dart':
      'The probe client of the X-Api-Key services; the Seerr branch builds '
      'its own through seerrClientFactoryProvider first.',
  'lib/features/jellyfin/data/jellyfin_client.dart': 'Jellyfin.',
  'lib/features/plex/data/plex_client.dart': 'Plex.',
  'lib/features/tracearr/data/tracearr_client.dart': 'Tracearr.',
};

/// What a `SeerrService` may be built over.
const _seerrConstructors = [
  'seerrClientFor(',
  'watchSeerrClient(',
  'seerrClientFactoryProvider',
];

final _apiClientOpener = RegExp(r'(?<!\w)ApiClient(\.authenticatedBy)?\(');

typedef _Call = ({String path, int line, String declaration});

/// The calls [opener] matches in [code], each with the top-level declaration
/// it sits in. A declaration (`ApiClient({`, `SeerrService(this._client`) is
/// not a call.
Iterable<_Call> _callsIn(String path, String code, RegExp opener) sync* {
  for (final match in opener.allMatches(code)) {
    final rest = code.substring(match.end).trimLeft();
    if (rest.startsWith('{') || rest.startsWith('this.')) continue;
    // `ApiClient._(` and the like: a redirecting constructor's own name.
    if (code.substring(0, match.start).endsWith(': this.')) continue;
    yield (
      path: path,
      line: _lineOf(code, match.start),
      declaration: _declarationAround(code, match.start),
    );
  }
}

int _lineOf(String code, int offset) =>
    '\n'.allMatches(code.substring(0, offset)).length + 1;

/// The top-level declaration [offset] sits in: from the last line that
/// starts at the margin with a name, to the next one.
String _declarationAround(String code, int offset) {
  final lines = code.split('\n');
  final at = _lineOf(code, offset) - 1;
  bool opens(String line) => RegExp(r'^[A-Za-z_@]').hasMatch(line);
  var start = at;
  while (start > 0 && !opens(lines[start])) {
    start--;
  }
  var end = at + 1;
  while (end < lines.length && !opens(lines[end])) {
    end++;
  }
  return lines.sublist(start, end).join('\n');
}

/// [source] with every `//` comment line blanked, line breaks kept.
String _withoutComments(String source) => source
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');
