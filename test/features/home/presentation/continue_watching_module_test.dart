import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/presentation/widgets/continue_watching_module.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../../test_helpers/settings_scope.dart';

const _episode = StreamItem(
  id: 'e1',
  title: 'The Second Cycle',
  subtitle: 'Cosmos Laundromat\u00A0· S2\u00A0E3',
  kind: StreamItemKind.episode,
  posterPath: null,
  year: null,
  runtimeMs: 1500000,
  isPlayed: false,
  resumeOffsetMs: 1200000,
  unplayedChildCount: null,
  seasonNumber: 2,
  episodeNumber: 3,
);

/// Continue watching on the Home: what was started and not finished.
void main() {
  Future<void> pump(WidgetTester tester, HomeResume resume) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.jellyfin],
          ),
          homeResumeProvider.overrideWith((ref) async => resume),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: HomeContinueWatchingModule()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the series, the episode, how long is left', (tester) async {
    await pump(tester, (
      rows: [
        (
          service: ServiceKey.jellyfin,
          instanceId: 'jellyfin',
          connectionName: null,
          item: _episode,
        ),
      ],
      coverage: SourceCoverage.answeredBy(ServiceKey.jellyfin),
      viewerMissing: const [],
    ));
    expect(find.text('Continue watching'), findsOne);
    expect(find.text('Jellyfin'), findsOne);
    expect(find.text('Cosmos Laundromat'), findsOne);
    expect(find.text('S2\u00A0E3\u00A0· The Second Cycle'), findsOne);
    expect(find.text('5\u00A0min left'), findsOne);
  });

  testWidgets('a Jellyfin that does not know who you are asks, once', (
    tester,
  ) async {
    await pump(tester, (
      rows: const [],
      coverage: SourceCoverage.none,
      viewerMissing: const ['jellyfin'],
    ));
    expect(find.text('Which Jellyfin user are you?'), findsOne);
    expect(
      find.text('A server key sees every user; pick yours once'),
      findsOne,
    );
  });

  testWidgets('nothing in progress and every server answered: no module', (
    tester,
  ) async {
    await pump(tester, (
      rows: const [],
      coverage: SourceCoverage.answeredBy(ServiceKey.jellyfin),
      viewerMissing: const [],
    ));
    expect(find.text('Continue watching'), findsNothing);
  });
}
