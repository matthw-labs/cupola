/// Emby, read through the app's own providers over the demo world's fake
/// server: the same wiring a real connection has (the transport, the viewer on
/// the instance, the `/emby` prefix), with nothing stubbed above the socket.
///
/// The fake answers in Emby's shapes (`/Users/Query`, `/Library/VirtualFolders/
/// Query`, `/Users/{id}/Items/Resume`, numeric ids, no `/Users/Me`), so a read
/// that still asked Jellyfin's route would be answered 404 here and fail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/demo/world/fakes/media_fakes.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/jellyfin_viewer_picker.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../test_helpers/profiles/profiles.dart';

final _withEmby = Profiles.p1.withConnection(WorldConnections.emby);

/// Anna's own token on the same server: refused the administrator's reads.
final _annaOnEmby = Profiles.p1.withConnection(
  ProfileConnection(
    WorldConnections.emby.instance.copyWith(viewerId: EmbyFake.annaId),
    behaviour: ConnectionBehaviour.readOnly,
  ),
);

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget child,
) async {
  final harness = await ProfileHarness.start(profile);
  await tester.binding.setSurfaceSize(const Size(430, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  await harness.settle(tester);
  return harness;
}

void main() {
  group('the administrator\'s key', () {
    test('the connection answers, the test names the version', () async {
      final harness = await ProfileHarness.start(_withEmby);
      final container = harness.container(retry: (_, _) => null);

      final diagnosis = await container.read(
        instanceDiagnosisProvider(WorldIds.emby).future,
      );

      expect(diagnosis.status, ServiceConnectionStatus.connected);
      expect(diagnosis.serverVersion, '4.10.2.0');
      // Every request went under /emby, with the token in its header.
      final paths = harness.network
          .requestsTo(WorldIds.emby)
          .map((r) => r.path);
      expect(paths, everyElement(startsWith('/emby/')));
    });

    test(
      'the sessions, libraries, users and kind come from Emby\'s routes',
      () async {
        final harness = await ProfileHarness.start(_withEmby);
        final container = harness.container(retry: (_, _) => null);

        final sessions = await container.read(embySessionsProvider.future);
        final libraries = await container.read(embyLibrariesProvider.future);
        final users = await container.read(embyUsersProvider.future);
        final kind = await container.read(embyCredentialKindProvider.future);

        // Anna's Sintel; the API key's own row, with nothing playing, is not a
        // stream.
        expect(sessions.map((s) => s.title), ['Sintel']);
        expect(libraries.map((l) => l.name), ['Movies', 'Series', 'Music']);
        expect(users.map((u) => u.name), [
          'Operator',
          WorldPeople.anna,
          WorldPeople.luca,
        ]);
        expect(kind, JellyfinCredentialKind.administrator);

        final paths = harness.network
            .requestsTo(WorldIds.emby)
            .map((r) => r.path);
        expect(paths, contains('/emby/Sessions'));
        expect(paths, contains('/emby/Library/VirtualFolders/Query'));
        expect(paths, contains('/emby/Users/Query'));
        expect(paths, isNot(contains('/emby/Users/Me')));
      },
    );

    test(
      'the viewer is the operator, and continue watching reads as them',
      () async {
        final harness = await ProfileHarness.start(_withEmby);
        final container = harness.container(retry: (_, _) => null);
        final server = streamBackendOf(ServiceKey.emby);

        final resume = await container
            .read(server.lensClient)
            .getContinueWatching(count: 12);

        expect(resume.map((i) => i.title), ['The Second Cycle']);
        expect(
          harness.network.requestsTo(WorldIds.emby).map((r) => r.path),
          contains('/emby/Users/${EmbyFake.operatorId}/Items/Resume'),
        );
      },
    );

    test('an item opens by its numeric id, and search finds it', () async {
      final harness = await ProfileHarness.start(_withEmby);
      final container = harness.container(retry: (_, _) => null);
      final server = streamBackendOf(ServiceKey.emby);

      final groups = await container.read(server.lensClient).search('sintel');
      final sintel = groups.first.items.single;
      // Held open: an `autoDispose` read cancels its request when nobody
      // listens, which a bare `read` does not.
      final provider = server.item(sintel.id);
      final keep = container.listen(provider, (_, _) {});
      addTearDown(keep.close);
      final opened = await container.read(provider.future);

      expect(sintel.title, 'Sintel');
      expect(int.tryParse(sintel.id), isNotNull);
      expect(opened?.title, 'Sintel');
      expect(
        harness.network.requestsTo(WorldIds.emby).map((r) => r.path),
        contains('/emby/Users/${EmbyFake.operatorId}/Items/${sintel.id}'),
      );
    });
  });

  group('a series', () {
    test('opens on its seasons, and a season on its episodes', () async {
      final harness = await ProfileHarness.start(_withEmby);
      final container = harness.container(retry: (_, _) => null);
      final client = container.read(
        streamBackendOf(ServiceKey.emby).lensClient,
      );

      final groups = await client.search('cosmos');
      final show = groups
          .expand((group) => group.items)
          .singleWhere((item) => item.kind == StreamItemKind.series);
      final seasons = await client.getChildren(show.id);
      final second = seasons.singleWhere((item) => item.seasonNumber == 2);
      final episodes = await client.getChildren(second.id);

      // The title page's "Contents" reads the same two routes: a series'
      // seasons, then a season's episodes by its own id.
      expect(
        seasons.map((season) => season.kind),
        everyElement(StreamItemKind.season),
      );
      expect(seasons, hasLength(2));
      expect(episodes, hasLength(3));
      expect(
        harness.network.requestsTo(WorldIds.emby).map((r) => r.path),
        containsAll([
          '/emby/Shows/${show.id}/Seasons',
          '/emby/Shows/${show.id}/Episodes',
        ]),
      );
    });
  });

  group('a household member\'s token', () {
    test('is read as a member, and its viewer is the one it holds', () async {
      final harness = await ProfileHarness.start(_annaOnEmby);
      final container = harness.container(retry: (_, _) => null);

      final kind = await container.read(
        embyCredentialKindForProvider(WorldIds.emby).future,
      );
      final viewers = await container.read(
        embyViewersForProvider(WorldIds.emby).future,
      );

      expect(kind, JellyfinCredentialKind.user);
      expect(
        container.read(embyLacksAdministratorForProvider(WorldIds.emby)),
        isTrue,
      );
      expect(viewers.map((v) => v.name), [WorldPeople.anna]);
    });

    test('the connection test accepts it', () async {
      final harness = await ProfileHarness.start(_annaOnEmby);
      final diagnosis = await harness
          .container(retry: (_, _) => null)
          .read(instanceDiagnosisProvider(WorldIds.emby).future);

      expect(diagnosis.status, ServiceConnectionStatus.connected);
    });
  });

  group('the screens, told it is Emby', () {
    testWidgets('the viewer picker lists Emby\'s people, not Jellyfin\'s', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(
          body: JellyfinViewerPicker(
            service: ServiceKey.emby,
            instanceId: WorldIds.emby,
          ),
        ),
      );

      expect(find.widgetWithText(ChoiceChip, 'Operator'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, WorldPeople.anna), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, WorldPeople.luca), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('Users lists them, from /Users/Query', (tester) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: JellyfinUsersScreen(service: ServiceKey.emby)),
      );

      expect(find.text(WorldPeople.luca), findsWidgets);
      expect(
        harness.network.requestsTo(WorldIds.emby).map((r) => r.path),
        contains('/emby/Users/Query'),
      );
      await harness.unmount(tester);
    });

    testWidgets('the Overview draws Anna\'s Sintel and the libraries', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _withEmby,
        const Scaffold(body: StreamOverviewScreen(service: ServiceKey.emby)),
      );

      expect(find.textContaining('Sintel'), findsWidgets);
      await harness.unmount(tester);
    });
  });
}
