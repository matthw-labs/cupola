/// What keeps Live moving, as pure arithmetic: an event of Tracearr's stream
/// applied to the list of live streams, and the summary derived again from the
/// rows. Nothing here touches a socket or a widget.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/data/tracearr_live_reducer.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';

import '../../test_helpers/fixtures.dart';

TracearrStreams _fixture(String name) =>
    TracearrStreams.fromJson(jsonFixture('tracearr/$name.json'));

/// The events of a recorded stream, in the order the server sent them.
List<TracearrEvent> _recorded(String name) {
  final parser = SseParser();
  final frames = parser.add(
    File('test/fixtures/tracearr/$name.sse').readAsStringSync(),
  );
  return [for (final frame in frames) ?tracearrEventFrom(frame)];
}

TracearrStream _stream(
  String id, {
  int bitrate = 1000,
  bool transcode = false,
}) => TracearrStream.fromJson({
  'id': id,
  'username': 'Anna',
  'media_title': 'Title $id',
  'media_type': 'movie',
  'state': 'playing',
  'progress_ms': 1000,
  'duration_ms': 100000,
  'bitrate': bitrate,
  'is_transcode': transcode,
  'video_decision': transcode ? 'transcode' : 'directplay',
  'audio_decision': 'directplay',
});

void main() {
  group('the summary is derived from the rows', () {
    test('and says what Tracearr says, on the recorded live list', () {
      final read = _fixture('real_streams_live');

      final derived = tracearrSummaryOf(read.streams);

      expect(derived.total, read.summary.total);
      expect(derived.transcodes, read.summary.transcodes);
      expect(derived.directPlays, read.summary.directPlays);
      expect(derived.directStreams, read.summary.directStreams);
      // The words are Tracearr's, the no-break space the brand book's.
      expect(
        derived.totalBitrate?.replaceAll('\u00A0', ' '),
        read.summary.totalBitrate,
      );
    });

    test('and on the invented list with a transcode, by server too', () {
      final read = _fixture('streams');

      final derived = tracearrSummaryOf(read.streams);

      expect(derived.transcodes, 1);
      expect(derived.totalBitrate, '11.7\u00A0Mbps');
      // The words are Tracearr's, the no-break space the brand book's.
      expect(read.summary.totalBitrate, '11.7 Mbps');
    });

    test('a bandwidth reads in kilobits under a megabit and is left out for '
        'none', () {
      expect(tracearrBitrateLabel(379), '379\u00A0kbps');
      expect(tracearrBitrateLabel(999), '999\u00A0kbps');
      expect(tracearrBitrateLabel(1000), '1.0\u00A0Mbps');
      expect(tracearrBitrateLabel(12400), '12.4\u00A0Mbps');
      expect(tracearrBitrateLabel(0), isNull);
    });
  });

  group('one event at a time', () {
    final base = TracearrStreams(
      streams: [_stream('a'), _stream('b', bitrate: 500)],
    );

    test('a started stream is added at the end, with the figures moved', () {
      final next = applyTracearrEvent(
        base,
        TracearrStreamStarted(_stream('c', bitrate: 2000, transcode: true)),
      );

      expect(next.streams.map((s) => s.id), ['a', 'b', 'c']);
      expect(next.summary.total, 3);
      expect(next.summary.transcodes, 1);
      expect(next.summary.totalBitrate, '3.5\u00A0Mbps');
    });

    test('an updated stream replaces its row in place', () {
      final next = applyTracearrEvent(
        base,
        TracearrStreamUpdated(_stream('a', bitrate: 4000, transcode: true)),
      );

      expect(next.streams.map((s) => s.id), ['a', 'b']);
      expect(next.streams.first.quality.bitrate, 4000);
      expect(next.summary.transcodes, 1);
    });

    test(
      'an update of a stream we never saw adds it: the full row is enough',
      () {
        final next = applyTracearrEvent(
          base,
          TracearrStreamUpdated(_stream('z')),
        );

        expect(next.streams.map((s) => s.id), ['a', 'b', 'z']);
      },
    );

    test('a progress tick moves the row it names and nothing else', () {
      final next = applyTracearrEvent(
        base,
        const TracearrStreamProgress(
          id: 'b',
          state: TracearrStreamState.paused,
          progressMs: 55000,
          bitrate: 700,
        ),
      );

      expect(next.streams[0].progressMs, 1000);
      expect(next.streams[1].progressMs, 55000);
      expect(next.streams[1].isPaused, isTrue);
      expect(next.streams[1].quality.bitrate, 700);
      expect(next.streams[1].media.title, 'Title b');
    });

    test('a progress tick for a stream we do not hold is dropped: four fields '
        'do not make a row', () {
      final next = applyTracearrEvent(
        base,
        const TracearrStreamProgress(id: 'nobody', progressMs: 9),
      );

      expect(identical(next, base), isTrue);
    });

    test('a stopped stream leaves, and one we never held changes nothing', () {
      final next = applyTracearrEvent(
        base,
        const TracearrStreamStopped(id: 'a'),
      );

      expect(next.streams.map((s) => s.id), ['b']);
      expect(next.summary.total, 1);
      expect(next.summary.totalBitrate, '500\u00A0kbps');
      expect(
        identical(
          applyTracearrEvent(base, const TracearrStreamStopped(id: 'ghost')),
          base,
        ),
        isTrue,
      );
    });

    test('the last stream stopping leaves no bandwidth to speak of', () {
      final next = applyTracearrEvent(
        TracearrStreams(streams: [_stream('a')]),
        const TracearrStreamStopped(id: 'a'),
      );

      expect(next.streams, isEmpty);
      expect(next.summary.total, 0);
      expect(next.summary.totalBitrate, isNull);
    });

    test('ready, a violation and a server going down leave the list alone', () {
      for (final event in <TracearrEvent>[
        const TracearrReady(),
        const TracearrServerHealth(
          serverId: 's',
          status: TracearrServerStatus.down,
        ),
      ]) {
        expect(identical(applyTracearrEvent(base, event), base), isTrue);
      }
    });

    test('an event never changes the list it was given', () {
      final before = base.streams.map((s) => s.id).toList();

      applyTracearrEvent(base, const TracearrStreamStopped(id: 'a'));
      applyTracearrEvent(base, TracearrStreamStarted(_stream('c')));

      expect(base.streams.map((s) => s.id), before);
    });

    test('dropping a stream by hand is a stop', () {
      final next = withoutTracearrStream(base, 'a');

      expect(next.streams.map((s) => s.id), ['b']);
      expect(next.summary.total, 1);
    });
  });

  group('the recorded stream', () {
    test('applied over the list a read gave, ends where the server was', () {
      final read = _fixture('real_streams_live');
      final events = _recorded('real_events');

      final end = applyTracearrEvents(read, events);

      // Two streams, both still playing at the end of the recording, their
      // progress moved by the ticks and their rows replaced by the updates.
      expect(end.streams, hasLength(2));
      final first = events.whereType<TracearrStreamUpdated>().last;
      final held = end.streams.firstWhere((s) => s.id == first.stream.id);
      expect(held.progressMs, greaterThanOrEqualTo(first.stream.progressMs));
      expect(end.summary.total, 2);
    });

    test('the invented recording: started, ticked, then stopped', () {
      final events = _recorded('events');

      final end = applyTracearrEvents(
        const TracearrStreams(streams: []),
        events,
      );

      // The recording starts one stream and stops it.
      expect(end.streams, isEmpty);
      final midway = applyTracearrEvents(
        const TracearrStreams(streams: []),
        events.takeWhile((e) => e is! TracearrStreamStopped),
      );
      expect(midway.streams, hasLength(1));
      expect(midway.streams.single.progressMs, 915000);
      expect(midway.streams.single.quality.bitrate, 3600);
    });
  });
}
