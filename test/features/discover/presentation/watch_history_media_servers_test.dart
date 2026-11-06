import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/library_shelves_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

import '../../../test_helpers/settings_scope.dart';

/// Because you watched asks every media server that has something to say, and
/// only those: one that is set up but whose household member nobody chose has
/// nothing to read yet.
class _Server implements StreamServerClient {
  int asked = 0;

  @override
  Future<List<StreamWatched>> getRecentlyWatched({
    String? viewerId,
    int limit = 5,
    CancelToken? cancelToken,
  }) async {
    asked++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  ServiceInstance instanceOf(ServiceKey service, {String viewerId = ''}) =>
      ServiceInstance(
        id: '${service.name}-1',
        service: service,
        label: '',
        url: 'http://media.lan:8096',
        credential: 'k',
        viewerId: viewerId,
      );

  Future<ProviderContainer> containerWith(
    List<ServiceInstance> instances, {
    Map<ServiceKey, _Server> servers = const {},
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(),
        currentSettingsProvider.overrideWith(
          (ref) => SettingsModel(instances: instances),
        ),
        for (final MapEntry(:key, :value) in servers.entries)
          streamBackendOf(key).lensClient.overrideWithValue(value),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  for (final service in mediaServers) {
    group(service.name, () {
      test(
        'a set up server with who is watching chosen has a history',
        () async {
          final container = await containerWith([
            instanceOf(service, viewerId: 'viewer-1'),
          ]);
          expect(container.read(hasWatchHistoryProvider), isTrue);
        },
      );

      test('a server that is not set up has none', () async {
        final container = await containerWith(const []);
        expect(container.read(hasWatchHistoryProvider), isFalse);
      });

      test('a server needing a viewer, with none chosen, has none', () async {
        final container = await containerWith([instanceOf(service)]);
        expect(
          container.read(hasWatchHistoryProvider),
          !service.needsViewerSelection,
        );
      });

      test('its recently watched is asked, once', () async {
        final server = _Server();
        final container = await containerWith(
          [instanceOf(service, viewerId: 'viewer-1')],
          servers: {service: server},
        );
        await container.read(becauseYouWatchedProvider.future);
        expect(server.asked, 1);
      });
    });
  }

  test('every media server set up is asked what was watched', () async {
    final servers = {for (final service in mediaServers) service: _Server()};
    final container = await containerWith([
      for (final service in mediaServers)
        instanceOf(service, viewerId: 'viewer-1'),
    ], servers: servers);
    await container.read(becauseYouWatchedProvider.future);
    for (final MapEntry(:key, :value) in servers.entries) {
      expect(value.asked, 1, reason: key.name);
    }
  });
}
