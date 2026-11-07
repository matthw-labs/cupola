/// Now playing with Tracearr in it: a playback only Tracearr sees is marked,
/// has no way into a server Cupola is not connected to, Tracearr alone is
/// enough for the module to exist, and its silence is said once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/home/domain/now_playing.dart';
import 'package:cupola/features/home/presentation/widgets/now_playing_module.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_person_provider.dart';

import '../../../test_helpers/settings_scope.dart';

StreamActivityRow _row(
  String user,
  String title, {
  ServiceKey service = ServiceKey.jellyfin,
  ServiceKey? through,
  String? userId,
  StreamTracearrSight? tracearr,
}) => StreamActivityRow(
  service: service,
  instanceId: through == null ? 'native' : 'tracearr',
  connectionName: null,
  through: through,
  tracearr: tracearr,
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
    userId: userId,
  ),
);

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    required List<ServiceKey> configured,
    required List<StreamActivityRow> rows,
    List<StreamOfflineSource> offline = const [],
    String? person,
  }) async {
    final visited = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: HomeNowPlayingModule()),
        ),
        GoRoute(
          path: '/:rest(.*)',
          builder: (context, state) {
            visited.add(state.uri.path);
            return const SizedBox.shrink();
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(configured: configured),
          streamActivityProvider.overrideWith((ref) async => rows),
          streamActivityOfflineProvider.overrideWith((ref) async => offline),
          tracearrPersonOfSessionProvider.overrideWith(
            (ref, who) async => person,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return visited;
  }

  testWidgets('a playback only Tracearr sees says so, first on its line, '
      'and its header names the server once', (tester) async {
    await pump(
      tester,
      configured: const [ServiceKey.jellyfin, ServiceKey.tracearr],
      rows: [
        _row('Anna', 'Sintel'),
        _row(
          'Luca',
          'Elephants Dream',
          service: ServiceKey.plex,
          through: ServiceKey.tracearr,
        ),
      ],
    );

    expect(
      find.text(
        'Plex\u00A0· through Tracearr\u00A0· Living room TV\u00A0· 9\u00A0min left',
      ),
      findsOne,
    );
    // The server's own row is told as before.
    expect(find.text('Living room TV\u00A0· 9\u00A0min left'), findsOne);
    expect(find.text('Jellyfin\u00A0· Plex\u00A0· through Tracearr'), findsOne);
  });

  testWidgets('Tracearr alone gives the module its rows, and a tap goes to '
      'Tracearr\'s Live, never a server page', (tester) async {
    final visited = await pump(
      tester,
      configured: const [ServiceKey.tracearr],
      rows: [
        _row(
          'Luca',
          'Elephants Dream',
          service: ServiceKey.plex,
          through: ServiceKey.tracearr,
        ),
      ],
    );

    expect(find.text('Now playing'), findsOne);
    await tester.tap(find.textContaining('Elephants Dream'));
    await tester.pumpAndSettle();
    expect(visited, ['/stack/tracearr/live']);
  });

  testWidgets('a Tracearr that did not answer is one line, naming what is '
      'missing, over the servers\' rows', (tester) async {
    await pump(
      tester,
      configured: const [ServiceKey.jellyfin, ServiceKey.tracearr],
      rows: [_row('Anna', 'Sintel')],
      offline: const [
        (
          service: ServiceKey.tracearr,
          instanceId: 'tracearr',
          title: 'Tracearr',
          error: ClassifiedFailure(ServiceFailureReason.unreachable),
        ),
      ],
    );

    expect(find.text('Anna\u00A0· Sintel'), findsOne);
    expect(
      find.text('Tracearr did not answer. $nowPlayingTracearrMissing'),
      findsOne,
    );
  });

  testWidgets('a Plex row leads to the person in Tracearr where Tracearr '
      'knows them', (tester) async {
    final handle = tester.ensureSemantics();
    final visited = await pump(
      tester,
      configured: const [ServiceKey.plex, ServiceKey.tracearr],
      rows: [
        _row(
          'Luca',
          'Elephants Dream',
          service: ServiceKey.plex,
          userId: '2',
          tracearr: const StreamTracearrSight(instanceId: 'tracearr'),
        ),
      ],
      person: 'person-luca',
    );

    await tester.tap(find.byType(InkResponse));
    await tester.pumpAndSettle();
    expect(visited, ['/stack/tracearr/users/person-luca']);
    handle.dispose();
  });

  testWidgets('a door keeps the text of its row where the other rows have '
      'it, and is a 44pt target', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      configured: const [
        ServiceKey.plex,
        ServiceKey.jellyfin,
        ServiceKey.tracearr,
      ],
      rows: [
        _row('Luca', 'Elephants Dream', service: ServiceKey.plex, userId: '2'),
        _row('Anna', 'Sintel'),
      ],
      person: 'person-luca',
    );

    // Only the Plex row has the door.
    expect(find.byType(InkResponse), findsOne);
    expect(tester.getSize(find.byType(InkResponse)), const Size(44, 44));
    expect(
      tester.getTopLeft(find.text('Luca\u00A0· Elephants Dream')).dx,
      tester.getTopLeft(find.text('Anna\u00A0· Sintel')).dx,
    );
    handle.dispose();
  });

  testWidgets('See all leads to the page of a media server\'s own row, '
      'which lists what it counts, even when a Tracearr-only transcode '
      'is first', (tester) async {
    final visited = await pump(
      tester,
      configured: const [ServiceKey.jellyfin, ServiceKey.tracearr],
      rows: [
        _row(
          'Luca',
          'Elephants Dream',
          service: ServiceKey.plex,
          through: ServiceKey.tracearr,
        ),
        _row('Anna', 'Sintel'),
        _row('Marco', 'Tears of Steel'),
        _row('Giulia', 'Spring'),
        _row('Paolo', 'Caminandes'),
      ],
    );

    await tester.tap(find.text('See all 5'));
    await tester.pumpAndSettle();
    expect(visited, [ServiceRoutes.jellyfinActivity]);
  });

  testWidgets('See all of rows only Tracearr sees leads to Tracearr\'s '
      'Live', (tester) async {
    final visited = await pump(
      tester,
      configured: const [ServiceKey.tracearr],
      rows: [
        for (final title in ['A', 'B', 'C', 'D', 'E'])
          _row(
            'Luca',
            title,
            service: ServiceKey.plex,
            through: ServiceKey.tracearr,
          ),
      ],
    );

    await tester.tap(find.text('See all 5'));
    await tester.pumpAndSettle();
    expect(visited, ['/stack/tracearr/live']);
  });

  testWidgets('no person known, no door', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      configured: const [ServiceKey.plex, ServiceKey.tracearr],
      rows: [_row('Luca', 'Elephants Dream', service: ServiceKey.plex)],
    );
    expect(find.byType(InkResponse), findsNothing);
    handle.dispose();
  });

  testWidgets('the line a through row speaks keeps the mark when it is '
      'cut', (tester) async {
    final row = _row(
      'Luca',
      'Elephants Dream',
      service: ServiceKey.plex,
      through: ServiceKey.tracearr,
    );
    expect(
      nowPlayingLine(row.session, via: row.serverLabel),
      startsWith('Plex\u00A0· through Tracearr'),
    );
  });
}
