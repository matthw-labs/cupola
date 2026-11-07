/// Tracearr, read through the app's own providers over the demo world's fake
/// server: the same wiring a real connection has (the transport, the bearer
/// key, the lens), with nothing stubbed above the socket.
///
/// The household is the point: Tracearr's streams are Anna's Sintel on the
/// Jellyfin and on the Emby, and Luca's Elephants Dream on the Plex, with the
/// ids those servers give the items themselves, so the Now playing that merges
/// them later finds the same session twice.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_overview_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

import '../../test_helpers/profiles/profiles.dart';

final _household = Profiles.p1
    .withConnection(WorldConnections.plex)
    .withConnection(WorldConnections.emby)
    .withConnection(WorldConnections.tracearr);

void main() {
  test('the connection answers and names the version', () async {
    final harness = await ProfileHarness.start(_household);
    final container = harness.container(retry: (_, _) => null);

    final diagnosis = await container.read(
      instanceDiagnosisProvider(WorldIds.tracearr).future,
    );

    expect(diagnosis.status, ServiceConnectionStatus.connected);
    expect(diagnosis.serverVersion, '3.1.4');
    // The key went as a bearer token on the authenticated read, and the
    // keyless route was never what proved it.
    final requests = harness.network.requestsTo(WorldIds.tracearr);
    expect(requests.map((r) => r.path), contains('/api/v1/public/health'));
    for (final request in requests) {
      expect(request.headers['authorization'], startsWith('Bearer '));
      expect(request.headers.containsKey('x-api-key'), isFalse);
    }
  });

  test('a refused key is a refusal, with the keyless route still up', () async {
    final harness = await ProfileHarness.start(
      _household.withBehaviour(
        WorldIds.tracearr,
        ConnectionBehaviour.refusesKey,
      ),
    );
    final container = harness.container(retry: (_, _) => null);

    final diagnosis = await container.read(
      instanceDiagnosisProvider(WorldIds.tracearr).future,
    );

    expect(diagnosis.status, ServiceConnectionStatus.disconnected);
    expect(diagnosis.reason?.name, 'unauthorized');
  });

  test('another service answering at its address is not Tracearr', () async {
    final harness = await ProfileHarness.start(
      _household.withBehaviour(
        WorldIds.tracearr,
        const ConnectionBehaviour.answersAsOtherService(ServiceKey.jellyfin),
      ),
    );
    final container = harness.container(retry: (_, _) => null);

    final diagnosis = await container.read(
      instanceDiagnosisProvider(WorldIds.tracearr).future,
    );

    expect(diagnosis.status, ServiceConnectionStatus.disconnected);
    expect(diagnosis.reason?.name, 'notFound');
  });

  test(
    'its streams are the household\'s, with the servers\' own ids',
    () async {
      final harness = await ProfileHarness.start(_household);
      final container = harness.container(retry: (_, _) => null);

      final streams = await container.read(tracearrLiveProvider.future);
      final jellyfin = await container.read(jellyfinSessionsProvider.future);
      final emby = await container.read(embySessionsProvider.future);
      final plex = await container.read(plexSessionsProvider.future);

      expect(streams.streams.map((s) => s.person.name), [
        WorldPeople.anna,
        WorldPeople.luca,
        WorldPeople.anna,
      ]);
      expect(streams.summary.total, 3);
      expect(streams.summary.directPlays, 3);
      expect(streams.streams.map((s) => s.server.type), [
        TracearrServerType.jellyfin,
        TracearrServerType.plex,
        TracearrServerType.emby,
      ]);

      // Each stream is a session the server's own fake holds: same person, same
      // title, same item id on the same kind of server.
      for (final (type, sessions) in [
        (TracearrServerType.jellyfin, jellyfin),
        (TracearrServerType.plex, plex),
        (TracearrServerType.emby, emby),
      ]) {
        final stream = streams.streams.singleWhere(
          (s) => s.server.type == type,
        );
        final session = sessions.singleWhere((s) => s.title.isNotEmpty);
        expect(stream.media.title, session.title, reason: type.name);
        expect(stream.person.name, session.userName, reason: type.name);
        expect(stream.media.ids.ratingKey, session.titleId, reason: type.name);
      }
    },
  );

  test('Now playing says each of the three playbacks once: the servers\' own '
      'rows, enriched by Tracearr\'s', () async {
    final harness = await ProfileHarness.start(_household);
    final container = harness.container(retry: (_, _) => null);

    final rows = await container.read(streamActivityProvider.future);

    // Six descriptions (three servers' and Tracearr's three) are three rows.
    expect(rows, hasLength(3));
    expect(rows.every((row) => !row.isThrough), isTrue);
    expect(rows.every((row) => row.tracearr != null), isTrue);
    expect(rows.map((row) => row.service).toSet(), {
      ServiceKey.jellyfin,
      ServiceKey.plex,
      ServiceKey.emby,
    });
    expect(await container.read(streamActivityOfflineProvider.future), isEmpty);
  });

  test('a Tracearr that watches a server Cupola does not hold adds it as a '
      'row through Tracearr', () async {
    // Cupola has the Jellyfin and the Plex, and not the Emby Tracearr watches.
    final harness = await ProfileHarness.start(
      Profiles.p1
          .withConnection(WorldConnections.plex)
          .withConnection(WorldConnections.tracearr),
    );
    final container = harness.container(retry: (_, _) => null);

    final rows = await container.read(streamActivityProvider.future);

    expect(rows, hasLength(3));
    final through = rows.singleWhere((row) => row.isThrough);
    expect(through.service, ServiceKey.emby);
    expect(through.serverLabel, 'Emby\u00A0· through Tracearr');
    expect(through.session.userName, WorldPeople.anna);
  });

  test(
    'the servers, today, people and the history are read as given',
    () async {
      final harness = await ProfileHarness.start(_household);
      final container = harness.container(retry: (_, _) => null);

      final servers = await container.read(tracearrServersProvider.future);
      final today = await container.read(tracearrTodayProvider.future);
      final users = await container.read(tracearrUsersProvider.future);
      final health = await container.read(tracearrHealthProvider.future);

      expect(servers.servers.map((s) => s.name), [
        'nas',
        'basement-nas',
        'tower',
      ]);
      expect(servers.servers.every((s) => s.isUp), isTrue);
      expect(servers.version?.toString(), '3.1.4');
      expect(today.todayPlays, 4);
      expect(users.items.map((u) => u.displayName), [
        WorldPeople.anna,
        WorldPeople.luca,
      ]);
      expect(health.isOk, isTrue);
    },
  );

  test(
    'the unseen violations are two, and the latest three are all of them',
    () async {
      final harness = await ProfileHarness.start(_household);
      final container = harness.container(retry: (_, _) => null);

      final unseen = await container.read(
        tracearrUnseenViolationsProvider.future,
      );
      final latest = await container.read(
        tracearrLatestViolationsProvider.future,
      );
      final week = await container.read(tracearrTopWeekProvider.future);

      expect(unseen.items.map((v) => v.rule.name), [
        'Concurrent streams',
        'Unknown device',
      ]);
      expect(unseen.hasMore, isFalse);
      expect(latest.items, hasLength(3));
      expect(week!.map((t) => t.title), ['Sintel', 'Cosmos Laundromat']);
    },
  );

  test('the rail\'s Streams counts the rows the session plumbing reads '
      'from Tracearr', () async {
    final harness = await ProfileHarness.start(_household);
    final container = harness.container(retry: (_, _) => null);

    final kpis = await container.read(
      serviceKpiProvider(ServiceKey.tracearr).future,
    );
    final sessions = await container.read(
      streamSessionsForProvider((
        service: ServiceKey.tracearr,
        instanceId: '',
      )).future,
    );

    expect(kpis.firstWhere((k) => k.label == 'Streams').value, '3');
    expect(sessions, hasLength(3));
  });

  test('the rail reads the four figures Tracearr itself gives', () async {
    final harness = await ProfileHarness.start(_household);
    final container = harness.container(retry: (_, _) => null);

    final kpis = await container.read(
      serviceKpiProvider(ServiceKey.tracearr).future,
    );

    expect(
      {for (final k in kpis) k.label: k.value},
      {
        'Streams': '3',
        'Today': '4 plays\u00A0· 1\u00A0h 30\u00A0min',
        'Unseen': '2',
        'Servers': '3 of 3',
      },
    );
  });

  test('the rail counts the streams Live draws, so an event that moves the '
      'list moves the figure with it', () async {
    final harness = await ProfileHarness.start(_household);
    final container = harness.container(retry: (_, _) => null);
    final rail = serviceKpiProvider(ServiceKey.tracearr);
    // The rail is on screen beside the Playing section that reads Live.
    container.listen(rail, (_, _) {});
    final live = await container.read(tracearrLiveProvider.future);
    String streamsNow(List<ServiceKpi> kpis) =>
        kpis.firstWhere((k) => k.label == 'Streams').value;
    expect(streamsNow(await container.read(rail.future)), '3');

    container
        .read(tracearrLiveProvider.notifier)
        .apply(TracearrStreamStopped(id: live.streams.first.id));

    expect(
      container.read(tracearrLiveProvider).requireValue.streams,
      hasLength(2),
    );
    // The rail re-folds on the next turn of the loop, not in the same one.
    await container.pump();
    expect(streamsNow(await container.read(rail.future)), '2');
  });
}
