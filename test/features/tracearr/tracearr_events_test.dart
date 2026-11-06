import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';

import '../../test_helpers/fixtures.dart';

List<SseFrame> _parse(Iterable<String> chunks) {
  final parser = SseParser();
  return [for (final chunk in chunks) ...parser.add(chunk)];
}

void main() {
  group('the event-stream format', () {
    test('one frame: event, data, blank line', () {
      final frames = _parse(['event: ping\ndata: hello\n\n']);

      expect(frames, hasLength(1));
      expect(frames.single.event, 'ping');
      expect(frames.single.data, 'hello');
    });

    test('a frame with no event field is a message', () {
      expect(_parse(['data: x\n\n']).single.event, 'message');
    });

    test('data lines join with a newline', () {
      final frame = _parse(['data: {"a":\ndata: 1}\n\n']).single;

      expect(frame.data, '{"a":\n1}');
      expect(frame.json, {'a': 1});
    });

    test('comments are dropped and do not dispatch', () {
      final frames = _parse([': connected\n\n: keep-alive\ndata: x\n\n']);

      expect(frames.map((f) => f.data), ['x']);
    });

    test('a comment between the lines of a frame does not break it', () {
      final frames = _parse(['data: a\n: noise\ndata: b\n\n']);

      expect(frames.single.data, 'a\nb');
    });

    test('CRLF ends a line', () {
      final frames = _parse(['event: x\r\ndata: 1\r\n\r\ndata: 2\r\n\r\n']);

      expect(frames.map((f) => '${f.event}/${f.data}'), ['x/1', 'message/2']);
    });

    test('a bare CR ends a line too', () {
      final frames = _parse(['event: x\rdata: 1\r\r']);

      expect(frames.single.event, 'x');
      expect(frames.single.data, '1');
    });

    test('a CRLF cut between its two characters is one break', () {
      final frames = _parse(['data: 1\r', '\n\r', '\n']);

      expect(frames, hasLength(1));
      expect(frames.single.data, '1');
    });

    test('a line cut at any point comes out whole', () {
      final frames = _parse(['da', 'ta: hel', 'lo\n', '\nda', 'ta: b\n\n']);

      expect(frames.map((f) => f.data), ['hello', 'b']);
    });

    test('every split of the same text gives the same frames', () {
      const text =
          ': hi\nretry: 100\nevent: a\nid: 1\ndata: x\ndata: y\n\ndata: z\r\n\r\n';
      final expected = _parse([
        text,
      ]).map((f) => '${f.event}|${f.data}|${f.id}');

      for (var cut = 1; cut < text.length; cut++) {
        final split = _parse([text.substring(0, cut), text.substring(cut)]);
        expect(
          split.map((f) => '${f.event}|${f.data}|${f.id}'),
          expected,
          reason: 'cut at $cut',
        );
      }
    });

    test('one space after the colon is dropped and no more', () {
      expect(_parse(['data:x\n\n']).single.data, 'x');
      expect(_parse(['data: x\n\n']).single.data, 'x');
      expect(_parse(['data:  x\n\n']).single.data, ' x');
    });

    test('a field with no colon is that field with an empty value', () {
      final frame = _parse(['data\n\n']).single;

      expect(frame.data, '');
      expect(frame.json, isNull);
    });

    test(
      'a blank line with no data dispatches nothing and resets the event',
      () {
        final frames = _parse(['event: lost\n\ndata: x\n\n']);

        expect(frames.single.event, 'message');
      },
    );

    test('an unknown field is ignored', () {
      expect(_parse(['colour: red\ndata: x\n\n']).single.data, 'x');
    });

    test('the id persists across frames and ignores a NUL', () {
      final frames = _parse([
        'id: 7\ndata: a\n\ndata: b\n\nid: 8\u0000\ndata: c\n\n',
      ]);

      expect(frames.map((f) => f.id), ['7', '7', '7']);
    });

    test('retry takes digits only', () {
      final parser = SseParser();

      parser.add('retry: 2500\n\n');
      expect(parser.retry, const Duration(milliseconds: 2500));
      parser.add('retry: soon\n\n');
      expect(parser.retry, const Duration(milliseconds: 2500));
      parser.add('retry: -5\n\n');
      expect(parser.retry, const Duration(milliseconds: 2500));
    });

    test('a byte order mark at the start is not part of the first field', () {
      final frames = _parse(['﻿data: x\n\n']);

      expect(frames.single.data, 'x');
    });

    test('data that is not JSON has no json', () {
      expect(_parse(['data: not json\n\n']).single.json, isNull);
    });
  });

  group('a byte stream', () {
    test('a character cut by a chunk boundary arrives whole', () {
      // Two, three and four bytes in UTF-8: e acute, a snowman, an emoji.
      final word = String.fromCharCodes([0xE9, 0x2603, 0x1F600]);
      final bytes = utf8.encode('data: $word\n\n');

      expect(
        sseFrames(
          Stream.fromIterable([
            for (final b in bytes) [b],
          ]),
        ),
        emits(isA<SseFrame>().having((f) => f.data, 'data', word)),
      );
    });

    test(
      'a frame cut off by the end of the stream is not dispatched',
      () async {
        final frames = await sseFrames(
          Stream.value(utf8.encode('data: one\n\ndata: two')),
        ).toList();

        expect(frames.map((f) => f.data), ['one']);
      },
    );

    test('the retry hint is reported once per change', () async {
      final heard = <Duration>[];
      await sseFrames(
        Stream.fromIterable([
          utf8.encode('retry: 3000\n\ndata: a\n\n'),
          utf8.encode('data: b\n\n'),
          utf8.encode('retry: 5000\n\n'),
        ]),
        onRetry: heard.add,
      ).toList();

      expect(heard, [const Duration(seconds: 3), const Duration(seconds: 5)]);
    });

    test('an error on the stream reaches the listener', () {
      final stream = Stream<List<int>>.error(const SocketException('reset'));

      expect(sseFrames(stream), emitsError(isA<SocketException>()));
    });
  });

  group('the recorded stream', () {
    final frames = _parse([
      File('test/fixtures/tracearr/events.sse').readAsStringSync(),
    ]);

    test('has seven frames, comments aside', () {
      expect(frames.map((f) => f.event), [
        'ready',
        'stream.started',
        'stream.progress',
        'server.health',
        'violation.created',
        'library.scanned',
        'stream.stopped',
      ]);
      expect(frames.map((f) => f.id), ['1', '2', '3', '4', '5', '6', '7']);
    });

    test('maps to typed events and ignores the unknown one', () {
      final events = frames.map(tracearrEventFrom).toList();

      expect(events[0], isA<TracearrReady>());
      expect(events[1], isA<TracearrStreamStarted>());
      expect(events[2], isA<TracearrStreamProgress>());
      expect(events[3], isA<TracearrServerHealth>());
      expect(events[4], isA<TracearrViolationCreated>());
      expect(events[5], isNull, reason: 'library.scanned is not ours');
      expect(events[6], isA<TracearrStreamStopped>());
    });

    test('the events carry what they say', () {
      final events = frames.map(tracearrEventFrom).toList();

      final ready = events[0]! as TracearrReady;
      expect(ready.at, DateTime.utc(2026, 11, 6, 10, 15));

      final started = events[1]! as TracearrStreamStarted;
      expect(started.stream.person.name, 'Luca');
      expect(started.stream.media.showTitle, 'Harbor Lights');
      expect(started.stream.server.type, TracearrServerType.emby);
      expect(started.at, DateTime.utc(2026, 11, 6, 10, 15, 5));

      final progress = events[2]! as TracearrStreamProgress;
      expect(progress.id, started.stream.id);
      expect(progress.state, TracearrStreamState.playing);
      expect(progress.progressMs, 915000);
      expect(progress.bitrate, 3600);
      final moved = progress.applyTo(started.stream);
      expect(moved.state, TracearrStreamState.playing);
      expect(moved.progressMs, 915000);
      expect(moved.quality.bitrate, 3600);

      final health = events[3]! as TracearrServerHealth;
      expect(health.serverName, 'Jellyfin Attic');
      expect(health.status, TracearrServerStatus.down);
      expect(health.reason, TracearrServerReason.unauthorized);

      final violation = events[4]! as TracearrViolationCreated;
      expect(violation.violation.severity, TracearrSeverity.high);
      expect(violation.violation.impossibleTravel, isNotNull);

      final stopped = events[6]! as TracearrStreamStopped;
      expect(stopped.id, started.stream.id);
      expect(stopped.stream?.person.name, 'Luca');
    });
  });

  group('typed mapping', () {
    SseFrame frame(String event, Object? payload) =>
        SseFrame(event: event, data: jsonEncode(payload));

    test('a frame with no event name falls back to the payload type', () {
      final event = tracearrEventFrom(
        frame('message', {
          'type': 'ready',
          'at': '2026-11-06T10:00:00Z',
          'data': {},
        }),
      );

      expect(event, isA<TracearrReady>());
    });

    test('a bare payload, with no envelope, still maps', () {
      final event = tracearrEventFrom(
        frame('stream.progress', {
          'id': 's',
          'progress_ms': 10,
          'state': 'paused',
        }),
      );

      expect(event, isA<TracearrStreamProgress>());
      expect(
        (event! as TracearrStreamProgress).state,
        TracearrStreamState.paused,
      );
      expect(event.at, isNull);
    });

    test('an event we do not know is ignored', () {
      expect(tracearrEventFrom(frame('rule.deleted', {'data': {}})), isNull);
      expect(
        tracearrEventFrom(frame('message', {'type': 'x', 'data': {}})),
        isNull,
      );
      expect(tracearrEventFrom(frame('message', {'nothing': 1})), isNull);
    });

    test('a payload that is not JSON, or not an object, is ignored', () {
      expect(
        tracearrEventFrom(const SseFrame(event: 'ready', data: 'oops')),
        isNull,
      );
      expect(tracearrEventFrom(frame('ready', [1, 2])), isNull);
      expect(tracearrEventFrom(frame('ready', 'text')), isNull);
    });

    test('a payload missing what its kind needs is ignored', () {
      expect(
        tracearrEventFrom(
          frame('stream.started', {
            'type': 'stream.started',
            'data': {'media_title': 'x'},
          }),
        ),
        isNull,
      );
      expect(
        tracearrEventFrom(
          frame('stream.progress', {
            'data': {'progress_ms': 1},
            'type': 'stream.progress',
          }),
        ),
        isNull,
      );
      expect(
        tracearrEventFrom(
          frame('server.health', {
            'type': 'server.health',
            'data': {'status': 'up'},
          }),
        ),
        isNull,
      );
      expect(
        tracearrEventFrom(
          frame('violation.created', {'type': 'violation.created', 'data': {}}),
        ),
        isNull,
      );
    });

    test('a stopped event without its stream still maps', () {
      final event = tracearrEventFrom(
        frame('stream.stopped', {
          'type': 'stream.stopped',
          'data': {'id': 's', 'server_id': null},
        }),
      );

      final stopped = event! as TracearrStreamStopped;
      expect(stopped.stream, isNull);
      expect(stopped.serverId, isNull);
    });

    test('a stopped event whose stream is unreadable keeps its id', () {
      final event = tracearrEventFrom(
        frame('stream.stopped', {
          'type': 'stream.stopped',
          'data': {
            'id': 's',
            'stream': {'media_title': 'no id'},
          },
        }),
      );

      final stopped = event! as TracearrStreamStopped;
      expect(stopped.id, 's');
      expect(stopped.stream, isNull);
    });

    test('an unseen state in a progress tick leaves the state alone', () {
      final stream = TracearrStream.fromJson({'id': 's', 'state': 'playing'});
      final tick =
          tracearrEventFrom(
                frame('stream.progress', {
                  'id': 's',
                  'state': 'buffering',
                  'progress_ms': 5,
                }),
              )!
              as TracearrStreamProgress;

      final moved = tick.applyTo(stream);

      expect(moved.state, TracearrStreamState.playing);
      expect(moved.progressMs, 5);
    });
  });

  test('the fixture is the server-sent format', () {
    // The recorded stream is what the tests above feed the parser, so it has
    // to be a faithful shape: comments, a retry hint and ids, LF line ends.
    final text = File('test/fixtures/tracearr/events.sse').readAsStringSync();
    expect(text, startsWith(': connected\nretry: 3000\n\n'));
    expect(text, contains('\nid: 7\n'));
    expect(text, isNot(contains('\r')));
    expect(text.endsWith('\n\n'), isTrue);
    final json = jsonFixtureMap('tracearr/health.json');
    expect(json['version'], 'v3.1.4');
  });
}
