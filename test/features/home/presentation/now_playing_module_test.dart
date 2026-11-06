import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/widgets/now_playing_module.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';

import '../../../test_helpers/settings_scope.dart';

StreamActivityRow _row(String user, String title) => StreamActivityRow(
  service: ServiceKey.jellyfin,
  instanceId: 'jellyfin',
  connectionName: null,
  session: StreamSession(
    id: '$user-$title',
    userName: user,
    title: title,
    subtitle: null,
    deviceLabel: 'Living room TV',
    posterPath: null,
    playMethod: StreamPlayMethod.directPlay,
    transcodeReasons: const [],
    bitrate: null,
    bitrateIsNominal: true,
    progress: 0.4,
    isPaused: false,
    remaining: const Duration(minutes: 9),
  ),
);

/// Now playing on the Home: who is watching, and nothing when nobody is.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<StreamActivityRow> rows,
    List<StreamOfflineSource> offline = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.jellyfin],
          ),
          streamActivityProvider.overrideWith((ref) async => rows),
          streamActivityOfflineProvider.overrideWith((ref) async => offline),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(body: HomeNowPlayingModule()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('who, what, where and how long is left', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, rows: [_row('Anna', 'Sintel')]);
    expect(find.text('Now playing'), findsOne);
    expect(find.text('Jellyfin'), findsOne);
    expect(find.text('Anna\u00A0· Sintel'), findsOne);
    expect(find.text('Living room TV\u00A0· 9\u00A0min left'), findsOne);
    expect(find.text('A'), findsOne);
    expect(find.bySemanticsLabel('Anna\u00A0· Sintel'), findsOne);
    handle.dispose();
  });

  testWidgets('nobody watching, every server answering: no module', (
    tester,
  ) async {
    await pump(tester, rows: const []);
    expect(find.text('Now playing'), findsNothing);
  });

  testWidgets('nobody seen and a server silent: the module keeps its place '
      'and names it', (tester) async {
    await pump(
      tester,
      rows: const [],
      offline: const [
        (
          service: ServiceKey.jellyfin,
          instanceId: 'jellyfin',
          title: 'Jellyfin',
          error: ClassifiedFailure(ServiceFailureReason.unreachable),
        ),
      ],
    );
    expect(find.text('Now playing'), findsOne);
    expect(find.textContaining('Jellyfin did not answer'), findsOne);
    expect(find.text(streamIdleMessage), findsNothing);
    expect(find.text('Retry'), findsOne);
  });

  testWidgets('a dark server beside answering sessions: the sessions stay, '
      'and the note says it did not answer', (tester) async {
    await pump(
      tester,
      rows: [_row('Anna', 'Sintel')],
      offline: const [
        (
          service: ServiceKey.jellyfin,
          instanceId: 'cabin',
          title: 'Jellyfin',
          error: ClassifiedFailure(ServiceFailureReason.unreachable),
        ),
      ],
    );
    expect(find.text('Anna\u00A0· Sintel'), findsOne);
    expect(find.textContaining('Jellyfin did not answer'), findsOne);
  });

  testWidgets('a refused token is said to be refused, never to be silent', (
    tester,
  ) async {
    await pump(
      tester,
      rows: const [],
      offline: const [
        (
          service: ServiceKey.plex,
          instanceId: 'plex',
          title: 'Plex',
          error: ClassifiedFailure(ServiceFailureReason.unauthorized),
        ),
        (
          service: ServiceKey.jellyfin,
          instanceId: 'cabin',
          title: 'Jellyfin',
          error: ClassifiedFailure(ServiceFailureReason.unreachable),
        ),
      ],
    );
    expect(find.textContaining('Jellyfin did not answer'), findsOne);
    expect(find.textContaining('Plex did not answer'), findsNothing);
    expect(find.textContaining('refused'), findsOne);
  });
}
