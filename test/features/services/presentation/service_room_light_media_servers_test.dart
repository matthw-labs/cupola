import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/presentation/service_room_light.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_session_poster.dart';

const _poster = 'https://image.tmdb.org/t/p/original/sintel.jpg';

/// A media server's room is lit by what it plays: the list of rooms lit by
/// what they hold is built from the capability, so a new media server cannot
/// be left on the lamp without this saying so.
void main() {
  for (final service in mediaServers) {
    test('${service.name}\'s room is lit by what it plays', () async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => SettingsModel(
              instances: [
                ServiceInstance(
                  id: 'room',
                  service: service,
                  label: '',
                  url: 'http://media.lan:8096',
                  credential: 'k',
                ),
              ],
            ),
          ),
          streamSessionsForProvider.overrideWith(
            (ref, key) async =>
                key.service == service ? [_playing('title-1')] : const [],
          ),
          streamSessionPosterProvider.overrideWith(
            (ref, title) async => title.service == service ? _poster : null,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        serviceRoomSourceProvider(service),
        (_, _) {},
      );
      addTearDown(sub.close);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(sub.read(), _poster);
    });
  }
}

StreamSession _playing(String titleId) => StreamSession(
  id: 's1',
  userName: 'Anna',
  title: 'Sintel',
  subtitle: null,
  deviceLabel: 'Living room TV',
  posterPath: '/Items/$titleId/Images/Primary',
  playMethod: StreamPlayMethod.directPlay,
  transcodeReasons: const [],
  bitrate: null,
  bitrateIsNominal: true,
  progress: 0.4,
  isPaused: false,
  titleId: titleId,
);
