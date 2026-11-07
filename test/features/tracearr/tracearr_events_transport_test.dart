/// What `guardedDio` does with a response that never ends, proved over a real
/// socket on the loopback: no client in the app read a streamed body before
/// Tracearr's event stream, so the guards written for JSON answers (the pin, the
/// access headers, the same-origin redirect guard, the gateway guards) are shown
/// here to hold for it too, and the bytes are shown to arrive as they are sent
/// instead of when the connection ends.
///
/// Deliberately no stubbed adapter: `tracearr_client_test.dart` already feeds
/// `events()` through one, which cannot tell a transport that buffers from one
/// that streams.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/observed_transport.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';

import '../../test_helpers/real_network.dart';

const _key = 'trr_pub_exampleexampleexampleexampleexampleexample1';

const _ready =
    'event: ready\ndata: {"type":"ready","at":"2026-11-06T10:00:00Z","data":{}}'
    '\n\n';

String _progress(int ms) =>
    'event: stream.progress\ndata: {"type":"stream.progress","data":'
    '{"id":"s1","progress_ms":$ms}}\n\n';

/// A loopback server whose answer to each request is the test's.
Future<HttpServer> _serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await handler(request);
    } on Object {
      // A client that went away mid-answer is the test's business.
    }
  });
  addTearDown(() => server.close(force: true));
  return server;
}

/// A server that answers once, in chunked encoding, then goes quiet with the
/// connection open, and completes [dropped] when the client closes it. A raw
/// socket, because `HttpServer` cannot tell a client that went away from one
/// that is slow to read.
Future<ServerSocket> _raw({
  required String contentType,
  required String body,
  required Completer<void> dropped,
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    socket.listen(
      (_) {},
      onDone: () => dropped.isCompleted ? null : dropped.complete(),
      onError: (Object _) => dropped.isCompleted ? null : dropped.complete(),
    );
    final bytes = utf8.encode(body);
    socket
      ..write(
        'HTTP/1.1 200 OK\r\ncontent-type: $contentType\r\n'
        'transfer-encoding: chunked\r\n\r\n',
      )
      ..write('${bytes.length.toRadixString(16)}\r\n$body\r\n');
  });
  addTearDown(() => server.close());
  return server;
}

String _address(Object server) =>
    'http://127.0.0.1:${server is HttpServer ? server.port : (server as ServerSocket).port}';

TracearrClient _client(
  String baseUrl, {
  Map<String, String> accessHeaders = const {},
  String? pin,
}) {
  final client = TracearrClient(
    baseUrl: baseUrl,
    apiKey: _key,
    accessHeaders: accessHeaders,
    pinnedCertFingerprint: pin,
  );
  addTearDown(() => client.close(force: true));
  return client;
}

void _openStream(HttpResponse response) {
  response
    ..statusCode = 200
    ..headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    )
    ..bufferOutput = false;
}

void main() {
  useRealNetwork();

  test(
    'an event reaches the caller while the server is still talking',
    () async {
      final release = Completer<void>();
      final server = await _serve((request) async {
        _openStream(request.response);
        request.response.write('retry: 5000\n\n$_ready');
        await request.response.flush();
        // The second event is held until the test has seen the first: a
        // transport that waits for the end of the body would deadlock here.
        await release.future;
        request.response.write(_progress(42));
        await request.response.flush();
        await request.response.close();
      });

      final events = <TracearrEvent>[];
      final retries = <Duration>[];
      final firstSeen = Completer<void>();
      final done = Completer<void>();
      final subscription = _client(_address(server))
          .events(onRetry: retries.add)
          .listen((event) {
            events.add(event);
            if (!firstSeen.isCompleted) firstSeen.complete();
          }, onDone: done.complete);
      addTearDown(subscription.cancel);

      await firstSeen.future.timeout(const Duration(seconds: 5));
      expect(events.single, isA<TracearrReady>());
      expect(done.isCompleted, isFalse, reason: 'the stream is still open');

      release.complete();
      await done.future.timeout(const Duration(seconds: 5));
      expect(events.last, isA<TracearrStreamProgress>());
      expect((events.last as TracearrStreamProgress).progressMs, 42);
      expect(retries, [const Duration(seconds: 5)]);
    },
  );

  test('the receive deadline of a JSON read is not the stream\'s', () async {
    final server = await _serve((request) async {
      _openStream(request.response);
      request.response.write(_ready);
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      request.response.write(_progress(7));
      await request.response.close();
    });
    final client = _client(_address(server));
    // The deadline a JSON read lives by is 15 seconds. The request must not
    // inherit it: it is lifted for this request alone.
    expect(client.dio.options.receiveTimeout, const Duration(seconds: 15));

    final events = await client.events().toList();

    expect(events, hasLength(2));
  });

  test('the key and the access headers go out on the stream request, and the '
      'client asks for an event stream', () async {
    HttpHeaders? seen;
    String? path;
    final server = await _serve((request) async {
      seen = request.headers;
      path = request.uri.toString();
      _openStream(request.response);
      request.response.write(_ready);
      await request.response.close();
    });

    await _client(
      _address(server),
      accessHeaders: {'X-Gateway-Token': 'let-me-in'},
    ).events(types: ['stream.started'], serverId: 's1').toList();

    expect(seen!.value('authorization'), 'Bearer $_key');
    expect(seen!.value('x-gateway-token'), 'let-me-in');
    expect(seen!.value('accept'), 'text/event-stream');
    expect(path, contains('/api/v2/public/events'));
    expect(path, contains('types=stream.started'));
    expect(path, contains('server_id=s1'));
  });

  test(
    'a same-origin redirect is followed as a stream, with the key kept',
    () async {
      final seen = <String, String?>{};
      final server = await _serve((request) async {
        seen[request.uri.path] = request.headers.value('authorization');
        if (!request.uri.path.endsWith('/')) {
          request.response
            ..statusCode = 301
            ..headers.set('location', '${request.uri.path}/');
          await request.response.close();
          return;
        }
        _openStream(request.response);
        request.response.write(_ready);
        await request.response.flush();
        request.response.write(_progress(3));
        await request.response.close();
      });

      final events = await _client(_address(server)).events().toList();

      expect(events, hasLength(2));
      expect(seen.values.toSet(), {'Bearer $_key'});
      expect(seen, hasLength(2));
    },
  );

  test('a redirect to another origin is refused, and the key is never sent '
      'there', () async {
    var elsewhereAsked = false;
    final elsewhere = await _serve((request) async {
      elsewhereAsked = true;
      _openStream(request.response);
      request.response.write(_ready);
      await request.response.close();
    });
    final server = await _serve((request) async {
      request.response
        ..statusCode = 302
        ..headers.set('location', '${_address(elsewhere)}/stream');
      await request.response.close();
    });

    await expectLater(
      _client(_address(server)).events().toList(),
      throwsA(
        isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<RedirectRefused>(),
        ),
      ),
    );
    expect(elsewhereAsked, isFalse);
  });

  test('a redirect to a gateway sign-in is named as one', () async {
    final server = await _serve((request) async {
      request.response
        ..statusCode = 302
        ..headers.set('location', '/cdn-cgi/access/login/tracearr');
      await request.response.close();
    });

    await expectLater(
      _client(_address(server)).events().toList(),
      throwsA(
        isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<AccessGatewayAnswer>(),
        ),
      ),
    );
  });

  test('a proxy password prompt is a gateway, not a refused key', () async {
    final server = await _serve((request) async {
      request.response
        ..statusCode = 401
        ..headers.set('www-authenticate', 'Basic realm="proxy"');
      await request.response.close();
    });

    await expectLater(
      _client(_address(server)).events().toList(),
      throwsA(
        isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<AccessGatewayAnswer>().having(
            (a) => a.kind,
            'kind',
            AccessGatewayKind.passwordPrompt,
          ),
        ),
      ),
    );
  });

  test('a web page answering 200 is a gateway, read from a real socket and '
      'the connection dropped', () async {
    final dropped = Completer<void>();
    final server = await _raw(
      contentType: 'text/html',
      body:
          '<html><form method="post"><input type="password" name="pw">'
          '</form></html>',
      dropped: dropped,
    );

    await expectLater(
      _client(_address(server)).events().toList(),
      throwsA(
        isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<AccessGatewayAnswer>(),
        ),
      ),
    );
    // The page stalled under the 8 KB the client reads: the probe is bounded
    // in time too, and ends by dropping the connection.
    await dropped.future.timeout(const Duration(seconds: 5));
  });

  test('a refused key is a failure before any event', () async {
    final server = await _serve((request) async {
      request.response
        ..statusCode = 401
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'statusCode': 401, 'message': 'no'}));
      await request.response.close();
    });

    await expectLater(
      _client(_address(server)).events().toList(),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
  });

  test(
    'cancelling the subscription closes the connection at the server',
    () async {
      final closed = Completer<void>();
      final server = await _raw(
        contentType: 'text/event-stream',
        body: _ready,
        dropped: closed,
      );
      final first = Completer<void>();
      final subscription = _client(
        _address(server),
      ).events().listen((_) => first.isCompleted ? null : first.complete());

      await first.future.timeout(const Duration(seconds: 5));
      expect(closed.isCompleted, isFalse);
      await subscription.cancel();

      await closed.future.timeout(const Duration(seconds: 5));
    },
  );

  test('a pinned client streams through the same observed adapter as every '
      'other read', () async {
    final client = _client('https://127.0.0.1:1', pin: 'ab:cd');

    // One `HttpClient` serves a Dio's every request, a stream included, so the
    // pin the user trusted is the one deciding the certificate of the stream.
    expect(client.dio.httpClientAdapter, isA<ObservedIOHttpClientAdapter>());
    expect(
      client.dio.interceptors.whereType<SameOriginRedirectInterceptor>(),
      hasLength(1),
    );
  });

  test(
    'a server that does not answer is a connection failure, not a hang',
    () async {
      final unused = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = unused.port;
      await unused.close(force: true);

      final failure = await _client(
        'http://127.0.0.1:$port',
      ).events().toList().then<Object?>((_) => null, onError: (e) => e);

      expect(failure, isA<DioException>());
      expect(
        classifyConnectionFailure(failure!),
        ServiceFailureReason.unreachable,
      );
    },
  );
}
