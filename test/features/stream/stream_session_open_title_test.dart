/// A playback's card opens the title it plays: through the ids the server
/// holds for it, else on the server's own page; a playback that names no
/// title is words, not a button.
library;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';

import '../../test_helpers/settings_scope.dart';

/// A media server that answers only the title's ids, with [answer].
class _Server implements StreamServerClient {
  _Server(this.answer);

  final MediaKey? answer;
  final asked = <String>[];

  @override
  Future<MediaKey?> getTitleKey(
    String titleId, {
    CancelToken? cancelToken,
  }) async {
    asked.add(titleId);
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StreamSession _session({String? titleId = 'jf-movie-1'}) => StreamSession(
  id: 's1',
  userName: 'anna',
  title: 'Sintel',
  subtitle: null,
  deviceLabel: 'Living room',
  posterPath: null,
  playMethod: StreamPlayMethod.directPlay,
  transcodeReasons: const [],
  bitrate: null,
  bitrateIsNominal: false,
  progress: 0.4,
  isPaused: false,
  titleId: titleId,
);

Future<void> _pump(
  WidgetTester tester, {
  required StreamSession session,
  required StreamServerClient client,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: StreamSessionCard(
            session: session,
            accent: Colors.white,
            onOpenTitle: canOpenStreamSession(session)
                ? () => context.openStreamSession(
                    ServiceKey.jellyfin,
                    session,
                    instanceId: 'jellyfin',
                  )
                : null,
          ),
        ),
      ),
      GoRoute(
        path: '/media/movie/:id',
        builder: (context, state) => Text('movie ${state.uri}'),
      ),
      GoRoute(
        path: '${ServiceRoutes.jellyfinItemBase}/:id',
        builder: (context, state) => Text('item ${state.uri}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await settingsScopeOverrides(
          configured: const [ServiceKey.jellyfin],
        ),
        streamClientForProvider.overrideWith((ref, key) => client),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a tap on the playback opens its title\'s page', (tester) async {
    final server = _Server(const MediaKey.movie(45745));
    await _pump(tester, session: _session(), client: server);

    await tester.tap(find.text('Sintel'));
    await tester.pumpAndSettle();

    expect(server.asked, ['jf-movie-1']);
    expect(find.text('movie /media/movie/45745?i=jellyfin'), findsOneWidget);
  });

  testWidgets('a title the server holds no ids for opens the server\'s own '
      'page', (tester) async {
    await _pump(tester, session: _session(), client: _Server(null));

    await tester.tap(find.text('Sintel'));
    await tester.pumpAndSettle();

    expect(
      find.text('item ${ServiceRoutes.jellyfinItemBase}/jf-movie-1?i=jellyfin'),
      findsOneWidget,
    );
  });

  testWidgets('the readout is one button that says where it goes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, session: _session(), client: _Server(null));

    final node = tester.getSemantics(find.bySemanticsLabel('Sintel'));
    expect(node.hint, StreamSessionReadout.openHint);
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('a playback that names no title is words, not a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final server = _Server(null);
    await _pump(tester, session: _session(titleId: null), client: server);

    final node = tester.getSemantics(find.bySemanticsLabel('Sintel'));
    expect(node.flagsCollection.isButton, isFalse);
    await tester.tap(find.text('Sintel'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(server.asked, isEmpty);
    expect(find.text('Sintel'), findsOneWidget);
    handle.dispose();
  });
}
