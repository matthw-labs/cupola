import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/media/presentation/media_copy_panel_card.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/fake_services.dart';
import '../../test_helpers/model_builders.dart';
import '../../test_helpers/settings_scope.dart';

/// A second Radarr, beside the one the lens is on.
const _second = ServiceInstance(
  id: 'radarr-4k',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'https://4k.lan:7878',
  credential: 'key-2',
);

/// The queue record the copy is downloading, under the same id on both servers.
final _record = <String, dynamic>{
  'id': 9,
  'movieId': 5,
  'downloadId': 'fake-download',
  'title': 'Big.Buck.Bunny.2008.1080p.BluRay',
  'downloadClient': 'qBittorrent',
  'size': 2400000000,
  'sizeleft': 1200000000,
};

const _stalled = MediaStatusInfo(
  availability: MediaAvailability.missing,
  pipeline: MediaPipeline.stalled,
  progress: 0.47,
  detail: 'The download is stalled with no connections',
);

/// Records the queue writes that reach one Radarr.
class _RecordingRadarr extends FakeRadarrService {
  final List<int> removed = [];
  final List<int> searched = [];
  final List<bool> deleteFromClient = [];

  @override
  Future<ArrRecordPage> getQueuePage({
    Map<String, dynamic>? queryParameters,
  }) async => ArrRecordPage(records: [_record], total: 1);

  @override
  Future<void> searchMovie(int id) async {
    searched.add(id);
  }

  @override
  Future<List<Map<String, dynamic>>> getMovieQueue(int movieId) async => [
    _record,
  ];

  @override
  Future<DateTime?> searchingSince(int movieId) async => null;

  @override
  Future<void> removeFromQueue(
    int id, {
    bool removeFromClient = true,
    bool blocklist = false,
    bool? skipRedownload,
  }) async {
    removed.add(id);
    deleteFromClient.add(removeFromClient);
  }
}

Future<ProviderContainer> _container({
  required RadarrService lens,
  required RadarrService other,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...await settingsScopeOverrides(
        configured: const [ServiceKey.radarr],
        customize: (settings) => settings.copyWithInstance(_second),
      ),
      radarrServiceProvider.overrideWith((ref) => lens),
      radarrServiceForProvider(_second.id).overrideWithValue(other),
      connectionArrServiceProvider((
        ServiceType.movies,
        _second.id,
      )).overrideWithValue(other),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MediaCopyPanelCard(
              connection: _second,
              name: 'Radarr',
              movie: buildMovie(id: 5),
              status: _stalled,
              onChanged: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Try another download goes to the copy\'s own Radarr', (
    tester,
  ) async {
    final lens = _RecordingRadarr();
    final other = _RecordingRadarr();
    final container = await _container(lens: lens, other: other);

    await _pump(tester, container);
    await tester.tap(find.text('Try another download').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Try another download').last,
    );
    await tester.pumpAndSettle();

    expect(other.removed, [9]);
    expect(other.deleteFromClient, [false]);
    expect(other.searched, [5]);
    expect(lens.removed, isEmpty);
    expect(lens.searched, isEmpty);
  });

  testWidgets('Remove download goes to the copy\'s own Radarr', (tester) async {
    final lens = _RecordingRadarr();
    final other = _RecordingRadarr();
    final container = await _container(lens: lens, other: other);

    await _pump(tester, container);
    await tester.tap(find.text('Remove download').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Remove and delete files'),
    );
    await tester.pumpAndSettle();

    expect(other.removed, [9]);
    expect(lens.removed, isEmpty);
  });
}
