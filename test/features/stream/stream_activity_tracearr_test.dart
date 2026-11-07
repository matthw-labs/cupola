/// Now playing's one list, built in the provider: the media servers' rows and
/// Tracearr's, said once, over every source that answered.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_sessions_provider.dart';

import '../../test_helpers/settings_scope.dart';

StreamSession _session(String user, String itemId) => StreamSession(
  id: 'jf-$user',
  userName: user,
  title: 'Sintel',
  subtitle: null,
  deviceLabel: 'Infuse\u00A0· Living room',
  posterPath: null,
  playMethod: StreamPlayMethod.directPlay,
  transcodeReasons: const [],
  bitrate: null,
  bitrateIsNominal: true,
  progress: 0.4,
  isPaused: false,
  itemId: itemId,
);

TracearrStream _seen(
  String user,
  String ratingKey, {
  TracearrServerType type = TracearrServerType.jellyfin,
}) => TracearrStream(
  id: 'tr-$user-$ratingKey',
  server: TracearrServerRef(id: 's', name: 'Casa', type: type),
  person: TracearrPerson(name: user),
  media: TracearrMedia(
    type: TracearrMediaType.movie,
    title: 'Sintel',
    year: 2010,
    ids: TracearrMediaIds(tmdb: 45745, ratingKey: ratingKey),
  ),
  device: const TracearrDevice(product: 'Infuse', player: 'Living room'),
  progressMs: 1000,
);

ProviderContainer _container({
  required List<ServiceKey> configured,
  required List<Override> overrides,
}) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => settingsWithServices(configured),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Override _tracearrSees(List<TracearrStream> streams) =>
    tracearrStreamsForProvider.overrideWith(
      (ref, id) async => TracearrStreams(streams: streams),
    );

Override get _tracearrDown => tracearrStreamsForProvider.overrideWith(
  (ref, id) async => throw StateError('no answer'),
);

/// The live list with its reads counted: what a poll's tick reaches for a
/// connection that is in view.
class _CountingLive extends TracearrLiveNotifier {
  static int refreshes = 0;

  @override
  Future<TracearrStreams> build() async => const TracearrStreams(streams: []);

  @override
  Future<void> refresh() async => refreshes++;
}

void main() {
  group('Now playing\'s one list', () {
    test('the same playback from both is one native row, enriched', () async {
      final container = _container(
        configured: const [ServiceKey.jellyfin, ServiceKey.tracearr],
        overrides: [
          jellyfinSessionsProvider.overrideWith(
            (ref) async => [_session('Anna', 'item-1')],
          ),
          _tracearrSees([_seen('Anna', 'item-1')]),
        ],
      );

      final rows = await container.read(streamActivityProvider.future);

      expect(rows, hasLength(1));
      expect(rows.single.isThrough, isFalse);
      expect(rows.single.service, ServiceKey.jellyfin);
      expect(rows.single.session.id, 'jf-Anna');
      expect(rows.single.tracearr, isNotNull);
      expect(
        await container.read(streamActivityOfflineProvider.future),
        isEmpty,
      );
    });

    test('a playback only Tracearr sees is appended and marked', () async {
      final container = _container(
        configured: const [ServiceKey.jellyfin, ServiceKey.tracearr],
        overrides: [
          jellyfinSessionsProvider.overrideWith(
            (ref) async => [_session('Anna', 'item-1')],
          ),
          _tracearrSees([
            _seen('Anna', 'item-1'),
            _seen('Luca', '103', type: TracearrServerType.plex),
          ]),
        ],
      );

      final rows = await container.read(streamActivityProvider.future);

      expect(rows.map((r) => r.isThrough), [false, true]);
      expect(rows.last.service, ServiceKey.plex);
      expect(rows.last.serverLabel, 'Plex\u00A0· through Tracearr');
    });

    test('a Tracearr that did not answer leaves the servers\' rows and is '
        'named once', () async {
      final container = _container(
        configured: const [ServiceKey.jellyfin, ServiceKey.tracearr],
        overrides: [
          jellyfinSessionsProvider.overrideWith(
            (ref) async => [_session('Anna', 'item-1')],
          ),
          _tracearrDown,
        ],
      );

      final rows = await container.read(streamActivityProvider.future);
      final offline = await container.read(
        streamActivityOfflineProvider.future,
      );

      expect(rows, hasLength(1));
      expect(rows.single.isThrough, isFalse);
      expect(rows.single.tracearr, isNull);
      expect(offline.map((source) => source.service), [ServiceKey.tracearr]);
    });

    test('Tracearr alone is enough: its rows are all there is', () async {
      final container = _container(
        configured: const [ServiceKey.tracearr],
        overrides: [
          _tracearrSees([
            _seen('Anna', 'item-1'),
            _seen('Luca', '103', type: TracearrServerType.plex),
          ]),
        ],
      );

      final rows = await container.read(streamActivityProvider.future);

      expect(rows, hasLength(2));
      expect(rows.every((row) => row.isThrough), isTrue);
    });

    test(
      'Tracearr alone that did not answer is a failure, not nobody',
      () async {
        final container = _container(
          configured: const [ServiceKey.tracearr],
          overrides: [_tracearrDown],
        );

        await expectLater(
          container.read(streamActivityProvider.future),
          throwsA(isA<StateError>()),
        );
        expect(
          (await container.read(
            streamActivityOfflineProvider.future,
          )).map((source) => source.service),
          [ServiceKey.tracearr],
        );
      },
    );

    test('without Tracearr nothing changes, and it is never asked', () async {
      final container = _container(
        configured: const [ServiceKey.jellyfin],
        overrides: [
          jellyfinSessionsProvider.overrideWith(
            (ref) async => [_session('Anna', 'item-1')],
          ),
          // Asked, it would fail the read: it must not be.
          _tracearrDown,
        ],
      );

      final rows = await container.read(streamActivityProvider.future);

      expect(rows.single.isThrough, isFalse);
      expect(rows.single.tracearr, isNull);
      expect(
        await container.read(streamActivityOfflineProvider.future),
        isEmpty,
      );
    });

    test('Tracearr\'s own session read never reaches a media server\'s '
        'backend', () async {
      final container = _container(
        configured: const [ServiceKey.tracearr],
        overrides: [
          _tracearrSees([_seen('Anna', 'item-1')]),
        ],
      );

      final sessions = await container.read(
        streamSessionsForProvider((
          service: ServiceKey.tracearr,
          instanceId: '',
        )).future,
      );

      expect(sessions.single.userName, 'Anna');
      expect(sessions.single.itemId, 'item-1');
    });

    test('the Stack\'s poll is built for Tracearr too, and never asks a '
        'media server\'s backend for it', () async {
      final container = _container(
        configured: const [ServiceKey.tracearr],
        overrides: [
          _tracearrSees([_seen('Anna', 'item-1')]),
        ],
      );

      final sub = container.listen(
        streamSessionsPollProvider((
          service: ServiceKey.tracearr,
          instanceId: '',
        )),
        (_, _) {},
      );
      addTearDown(sub.close);

      expect(sub.read, returnsNormally);
    });

    testWidgets('the Stack\'s poll follows the lens on every tick: the '
        'connection that came into view is the one read again', (tester) async {
      _CountingLive.refreshes = 0;
      const second = ServiceInstance(
        id: 'tracearr-b',
        service: ServiceKey.tracearr,
        label: 'B',
        url: 'https://b.test',
        credential: 'key-b',
      );
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.tracearr],
            customize: (settings) =>
                SettingsModel(instances: [...settings.instances, second]),
          ),
          tracearrLiveProvider.overrideWith(_CountingLive.new),
          _tracearrSees(const []),
        ],
      );
      addTearDown(container.dispose);

      // Built while the first connection is in view, so the second is a
      // connection that is not.
      final sub = container.listen(
        streamSessionsPollProvider((
          service: ServiceKey.tracearr,
          instanceId: second.id,
        )),
        (_, _) {},
      );
      addTearDown(sub.close);

      // The lens moves to it while the poll lives.
      await container
          .read(activeInstancesProvider.notifier)
          .select(ServiceKey.tracearr, second.id);
      await tester.pump(streamSessionsInterval + const Duration(seconds: 1));

      expect(_CountingLive.refreshes, 1);

      // The poll's timer goes with it: a pending one fails the test.
      sub.close();
      container.dispose();
    });

    testWidgets('the Stack\'s poll gates its first read on the source of the '
        'connection now in view, not the one it was built over', (
      tester,
    ) async {
      _CountingLive.refreshes = 0;
      const second = ServiceInstance(
        id: 'tracearr-b',
        service: ServiceKey.tracearr,
        label: 'B',
        url: 'https://b.test',
        credential: 'key-b',
      );
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.tracearr],
            customize: (settings) =>
                SettingsModel(instances: [...settings.instances, second]),
          ),
          tracearrLiveProvider.overrideWith(_CountingLive.new),
          _tracearrSees(const []),
        ],
      );
      addTearDown(container.dispose);

      // The Live list is a cache another page filled, of any age.
      final live = container.listen(tracearrLiveProvider, (_, _) {});
      addTearDown(live.close);
      await container.read(tracearrLiveProvider.future);

      // Built over the connection that is not in view: its own read does not
      // exist, so nothing is due at build.
      final sub = container.listen(
        streamSessionsPollProvider((
          service: ServiceKey.tracearr,
          instanceId: second.id,
        )),
        (_, _) {},
      );
      addTearDown(sub.close);
      await tester.pump();
      expect(_CountingLive.refreshes, 0);

      // It enters the view: the cache it now reads is already answered, so
      // the read comes at once, not an interval later.
      await container
          .read(activeInstancesProvider.notifier)
          .select(ServiceKey.tracearr, second.id);
      await tester.pump(const Duration(milliseconds: 1));

      expect(_CountingLive.refreshes, 1);

      sub.close();
      container.dispose();
    });
  });
}
