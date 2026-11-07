/// The Device line of the session sheet, composed from what the client names:
/// a player and a product that are the same words read once.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session.dart';

String? _deviceLine(TracearrDevice device) {
  final session = TracearrSession.live(
    TracearrStream(
      id: 'stream-1',
      server: const TracearrServerRef(
        id: 'srv',
        name: 'Casa',
        type: TracearrServerType.plex,
      ),
      person: const TracearrPerson(name: 'Anna'),
      media: const TracearrMedia(
        type: TracearrMediaType.movie,
        title: 'Sintel',
      ),
      device: device,
      quality: const TracearrQuality(),
    ),
  );
  for (final fact in tracearrFactsOf(session)) {
    if (fact.label == 'Device') return fact.value;
  }
  return null;
}

void main() {
  test('a player named as the product is said once, whatever its case', () {
    expect(
      _deviceLine(
        const TracearrDevice(
          device: 'Living Room TV',
          player: 'Plex for LG',
          product: 'Plex for LG',
        ),
      ),
      'Living Room TV${dotSeparator}Plex for LG',
    );
    expect(
      _deviceLine(
        const TracearrDevice(
          device: 'Living Room TV',
          player: ' plex for lg ',
          product: 'Plex for LG',
        ),
      ),
      'Living Room TV${dotSeparator}plex for lg',
    );
  });

  test('three different names are all kept, in order', () {
    expect(
      _deviceLine(
        const TracearrDevice(device: 'TV', player: 'Lounge', product: 'Infuse'),
      ),
      'TV${dotSeparator}Lounge${dotSeparator}Infuse',
    );
  });
}
