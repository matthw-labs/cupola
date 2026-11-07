/// Sonarr's Needs attention leads where the fault is fixed: a stuck season pack
/// is one download and opens its page, several downloads in one state are one
/// row that opens the Queue tab, and the backlog opens Wanted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/series/presentation/sonarr_overview_screen.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/overview_shell.dart';
import '../../../test_helpers/profiles/profiles.dart';

Map<String, Object?> _stalled(
  int id,
  String series,
  String downloadId, {
  int season = 1,
  int episode = 1,
}) => {
  'id': id,
  'seriesId': 1,
  'series': {'id': 1, 'title': series, 'tvdbId': 1},
  'seasonNumber': season,
  'episode': {'id': id, 'seasonNumber': season, 'episodeNumber': episode},
  'title': '$series.S0$season.1080p.WEB',
  'status': 'warning',
  'trackedDownloadStatus': 'warning',
  'trackedDownloadState': 'downloading',
  'statusMessages': [
    {
      'title': series,
      'messages': ['The download is stalled with no connections'],
    },
  ],
  'errorMessage': 'The download is stalled with no connections',
  'added': DateTime.now().toUtc().toIso8601String(),
  'downloadId': downloadId,
  'downloadClient': 'qBittorrent',
  'size': 1000,
  'sizeleft': 500,
};

Future<(ProfileHarness, OverviewShell)> _pump(
  WidgetTester tester,
  List<Map<String, Object?>> queue,
) async {
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.on(
    WorldIds.sonarr,
    'GET',
    '/api/v3/queue',
    (request) => NetworkReply.json({
      'page': 1,
      'pageSize': 200,
      'totalRecords': queue.length,
      'records': queue,
    }),
  );
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final shell = OverviewShell(
    ServiceKey.sonarr,
    const SonarrOverviewScreen(topPadding: 0),
  );
  await tester.pumpWidget(
    ProviderScope(overrides: harness.overrides, child: shell.app),
  );
  await harness.settle(tester);
  return (harness, shell);
}

void main() {
  testWidgets('P1: a stuck season pack is one row for one download, and opens '
      'its page', (tester) async {
    final (harness, shell) = await _pump(tester, [
      for (var episode = 1; episode <= 3; episode++)
        _stalled(episode, 'Slow Horses', 'PACK', season: 4, episode: episode),
    ]);

    final row = find.text('Stuck\u00A0· Slow Horses S4\u00A0E1–E3');
    expect(row, findsOneWidget);
    expect(
      find.semantics.byLabel(RegExp(r'^Stuck, Slow Horses S4\u00A0E1–E3, ')),
      isSemantics(isButton: true, hint: 'opens this download'),
    );

    await tester.tap(row);
    await harness.settle(tester);
    expect(shell.location, '/activity/download?i=${WorldIds.sonarr}&id=PACK');

    await harness.unmount(tester);
  });

  testWidgets('P1: two stuck downloads are one row that opens the Queue tab', (
    tester,
  ) async {
    final (harness, shell) = await _pump(tester, [
      _stalled(1, 'Andor', 'A'),
      _stalled(2, 'Severance', 'B'),
    ]);

    expect(find.text('2 downloads stuck'), findsOneWidget);
    expect(find.text('Andor S1\u00A0E1, Severance S1\u00A0E1'), findsOneWidget);

    await tester.tap(find.text('2 downloads stuck'));
    await harness.settle(tester);
    expect(shell.tab, ServiceTab.queue);

    await harness.unmount(tester);
  });
}
