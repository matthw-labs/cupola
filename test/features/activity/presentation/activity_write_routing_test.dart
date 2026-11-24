import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

const _second = ServiceInstance(
  id: 'sonarr-2222222',
  service: ServiceKey.sonarr,
  label: '2',
  url: 'https://second.lan:8989',
  credential: 'key-2',
);

Future<List<Override>> _settings() => settingsScopeOverrides(
  configured: activityServiceKeys,
  customize: (settings) => settings.copyWithInstance(_second),
);

Future<void> _pumpRow(
  WidgetTester tester, {
  required ProviderContainer container,
  required GlobalActivityItem item,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: GlobalActivityItemTile(item: item)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Three separate call sites pass the row's connection, so three separate
  // chances to forget one. The resolution is shared; the argument is not.

  testWidgets('and so does un-blocklisting', (tester) async {
    final lens = _RecordingSonarrService();
    final other = _RecordingSonarrService();

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        sonarrServiceProvider.overrideWith((ref) => lens),
        sonarrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: GlobalActivityItem(
        kind: GlobalActivityKind.blocklist,
        service: ServiceKey.sonarr,
        serviceType: ServiceType.series,
        instanceId: _second.id,
        instanceLabel: _second.label,
        title: 'A blocked release',
        subtitle: 'Release.Name',
        status: const MediaStatusInfo(
          availability: MediaAvailability.unknown,
          labelOverride: 'Blocked',
        ),
        raw: const {'id': 7, 'sourceTitle': 'Release.Name'},
      ),
    );

    // Through the row's overflow menu: the blocklist detail sheet carries no
    // action buttons, so the menu is the only way in.
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from blocklist'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Remove from blocklist'),
    );
    await tester.pumpAndSettle();

    expect(other.unblocked, [7]);
    expect(lens.unblocked, isEmpty);
  });
}

class _RecordingSonarrService extends FakeSonarrService {
  final List<int> removed = [];
  final List<int> unblocked = [];

  @override
  Future<void> deleteBlocklistItem(int id) async {
    unblocked.add(id);
  }

  @override
  Future<void> removeFromQueue(
    int id, {
    bool removeFromClient = true,
    bool blocklist = false,
    bool? skipRedownload,
  }) async {
    removed.add(id);
  }
}
