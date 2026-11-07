import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';

/// A remote command is only relayed: the 204 says nothing of the player. The
/// page reads the player again and says when it did not obey (Neptune on an
/// Apple TV took a Pause and went on playing).
StreamSession _session({bool paused = false}) => StreamSession(
  id: 's-1',
  userName: 'matt',
  title: 'How I Met Your Mother',
  subtitle: 'S2 E11',
  deviceLabel: 'Neptune\u00A0· Apple TV',
  posterPath: null,
  playMethod: StreamPlayMethod.directPlay,
  transcodeReasons: const [],
  bitrate: null,
  bitrateIsNominal: true,
  progress: 0.4,
  isPaused: paused,
);

void main() {
  const tick = Duration(milliseconds: 1);

  test('a player that paused is done at the first read that says so', () async {
    var reads = 0;
    final obeyed = await streamPlayerObeyed(
      read: () async => [_session(paused: ++reads >= 2)],
      sessionId: 's-1',
      done: (now) => now?.isPaused == true,
      interval: tick,
    );
    expect(obeyed, isTrue);
    expect(reads, 2);
  });

  test(
    'a player that ignores the pause is told apart after three reads',
    () async {
      var reads = 0;
      final obeyed = await streamPlayerObeyed(
        read: () async {
          reads++;
          return [_session()];
        },
        sessionId: 's-1',
        done: (now) => now?.isPaused == true,
        interval: tick,
      );
      expect(obeyed, isFalse);
      expect(reads, 3);
    },
  );

  test('a stop is done when the playback is gone', () async {
    expect(
      await streamPlayerObeyed(
        read: () async => const [],
        sessionId: 's-1',
        done: (now) => now == null,
        interval: tick,
      ),
      isTrue,
    );
  });

  test(
    'a read that fails is not a refusal, nor is a page that closed',
    () async {
      expect(
        await streamPlayerObeyed(
          read: () async => throw StateError('offline'),
          sessionId: 's-1',
          done: (now) => false,
          interval: tick,
        ),
        isTrue,
      );
      expect(
        await streamPlayerObeyed(
          read: () async => [_session()],
          sessionId: 's-1',
          done: (now) => false,
          stillShown: () => false,
          interval: tick,
        ),
        isTrue,
      );
    },
  );

  test('the reason names the player app', () {
    expect(
      streamIgnoredCommandsReason(_session()),
      'Neptune may not take commands from the server.',
    );
  });
}
