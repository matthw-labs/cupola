import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/emby/data/emby_client.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../../test_helpers/settings_scope.dart';

const _half = StreamItem(
  id: 'm1',
  title: 'Sintel',
  subtitle: '2010',
  kind: StreamItemKind.movie,
  posterPath: null,
  year: 2010,
  runtimeMs: 888000,
  isPlayed: false,
  resumeOffsetMs: 444000,
  unplayedChildCount: null,
);

/// What a media server was asked for Continue watching, and with what count.
final _asked = <ServiceKey, int>{};

class _Jellyfin implements JellyfinClient {
  @override
  Future<List<StreamItem>> getContinueWatching({
    String? viewerId,
    int count = 12,
    CancelToken? cancelToken,
  }) async {
    _asked[ServiceKey.jellyfin] = count;
    return const [_half];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Emby implements EmbyClient {
  @override
  Future<List<StreamItem>> getContinueWatching({
    String? viewerId,
    int count = 12,
    CancelToken? cancelToken,
  }) async {
    _asked[ServiceKey.emby] = count;
    return const [_half];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plex implements PlexClient {
  @override
  Future<List<StreamItem>> getContinueWatching({
    int count = 100,
    CancelToken? cancelToken,
  }) async {
    _asked[ServiceKey.plex] = count;
    return const [_half];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Continue watching asks every media server, each on its own connection and
/// through its own client, and a media server that picks a viewer is not asked
/// until one is chosen.
void main() {
  setUp(_asked.clear);

  ServiceInstance instanceOf(ServiceKey service, {String viewerId = ''}) =>
      ServiceInstance(
        id: '${service.name}-1',
        service: service,
        label: '',
        url: 'http://media.lan:8096',
        credential: 'k',
        viewerId: viewerId,
      );

  Future<HomeResume> read(List<ServiceInstance> instances) async {
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(),
        currentSettingsProvider.overrideWith(
          (ref) => SettingsModel(instances: instances),
        ),
        jellyfinClientProvider.overrideWithValue(_Jellyfin()),
        embyClientProvider.overrideWithValue(_Emby()),
        plexClientProvider.overrideWithValue(_Plex()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(homeResumeProvider, (_, _) {});
    return container.read(homeResumeProvider.future);
  }

  test('every media server is asked, and its rows carry its service', () async {
    final resume = await read([
      for (final service in mediaServers)
        instanceOf(service, viewerId: 'viewer-1'),
    ]);
    expect({for (final row in resume.rows) row.service}, {...mediaServers});
    expect(_asked.keys.toSet(), {...mediaServers});
    expect(resume.viewerMissing, isEmpty);
  });

  test(
    'Plex is asked for twice what is drawn, the others for what is',
    () async {
      await read([
        for (final service in mediaServers)
          instanceOf(service, viewerId: 'viewer-1'),
      ]);
      for (final service in mediaServers) {
        expect(
          _asked[service],
          service == ServiceKey.plex
              ? continueWatchingRowLimit * 2
              : continueWatchingRowLimit,
          reason: service.name,
        );
      }
    },
  );

  test(
    'a server that picks a viewer waits for one, and is not asked',
    () async {
      final resume = await read([
        for (final service in mediaServers) instanceOf(service),
      ]);
      final waiting = mediaServers.where((s) => s.needsViewerSelection);
      expect(resume.viewerMissing, [for (final s in waiting) '${s.name}-1']);
      for (final service in waiting) {
        expect(_asked, isNot(contains(service)), reason: service.name);
      }
      for (final service in mediaServers.where(
        (s) => !s.needsViewerSelection,
      )) {
        expect(_asked, contains(service), reason: service.name);
      }
    },
  );
}
