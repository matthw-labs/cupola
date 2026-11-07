/// Emby where it meets the rest of the app: who is watching, Seerr's word
/// and Cupola's own on a title, the requester who watches in it, and the search.
///
/// Over the demo world's fake network, so every read goes through the same
/// transport a real Emby connection has.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/demo/world/fakes/media_fakes.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/home/presentation/widgets/now_playing_module.dart';
import 'package:cupola/features/media/domain/media_lead.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_row_view.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';

import '../../test_helpers/profiles/profiles.dart';
import '../media/media_test_helpers.dart';

/// Seerr set up with Emby, and no media server of Cupola's own.
final _seerrOnEmby = Profiles.p3.withConnection(
  WorldConnections.seerr.withSeerrMediaServer(SeerrMediaServer.emby),
);

/// The same household with Emby in Cupola, the operator's key.
final _seerrOnEmbyWithEmby = _seerrOnEmby.withConnection(WorldConnections.emby);

/// Anna, who asks through her Seerr account, with her own Emby token: a
/// player she watches in, never a stack she runs.
final _annaWithEmby = Profiles.p2.withConnection(
  ProfileConnection(
    WorldConnections.emby.instance.copyWith(viewerId: EmbyFake.annaId),
    behaviour: ConnectionBehaviour.readOnly,
  ),
);

MediaRowView _view(MediaRow row) => mediaRowView(
  row,
  title: (connection) => connection.service.title,
  now: DateTime(2026, 10, 5),
)!;

void main() {
  group('Seerr set up with Emby', () {
    test('without Emby in Cupola: Emby through Seerr, and a way to add it, '
        'and Watch on Emby leads', () async {
      final rows = (await settledRows(
        _seerrOnEmby,
        WorldTitles.tearsOfSteel,
      )).rows;

      final claim = rows.first as MediaServerThroughSeerrRow;
      expect(claim.server, ServiceKey.emby);
      final view = _view(claim);
      expect(
        (view.name, view.via, view.state, view.action),
        ('Emby', 'through Seerr', 'Available', 'Add Emby to Cupola'),
      );

      final lead = resolveMediaLead(rows, audience: Audience.operator);
      expect(lead, isA<MediaLeadWatch>());
      expect((lead as MediaLeadWatch).server, ServiceKey.emby);
      expect(
        SeerrMediaServer.watchLabel(SeerrMediaServer.emby),
        'Watch on Emby',
      );
    });

    test('a series in part reads the seasons Seerr has on Emby', () async {
      final rows = (await settledRows(
        _seerrOnEmby,
        WorldTitles.cosmosLaundromat,
      )).rows;

      final view = _view(rows.whereType<MediaServerThroughSeerrRow>().single);
      expect(view.name, 'Emby');
      expect(view.detail, 'S1 available\u00A0· S2 partly available');
    });

    test('with Emby in Cupola: its own row, by the title\'s ids, and '
        'Seerr\'s link stands in for nothing', () async {
      final rows = (await settledRows(
        _seerrOnEmbyWithEmby,
        WorldTitles.tearsOfSteel,
      )).rows;

      expect(rows.whereType<MediaServerThroughSeerrRow>(), isEmpty);
      final emby = rows
          .whereType<MediaConnectionRow<Object?>>()
          .where((row) => row.service == ServiceKey.emby)
          .single;
      expect(emby.reading, isA<MediaReadingAnswered<Object?>>());
      expect(
        resolveMediaLead(rows, audience: Audience.operator),
        isNot(isA<MediaLeadWatch>()),
      );
    });
  });

  group('who is watching', () {
    test('the merged Now playing lists Anna\'s Sintel on Emby', () async {
      final harness = await ProfileHarness.start(
        Profiles.p3.withConnection(WorldConnections.emby),
      );
      final container = harness.container(retry: (_, _) => null);

      final rows = await container.read(streamActivityProvider.future);

      expect(rows.map((r) => r.service), [ServiceKey.emby]);
      expect(rows.single.session.title, 'Sintel');
      expect(rows.single.session.userName, WorldPeople.anna);
    });

    testWidgets('the Home\'s Now playing names Emby', (tester) async {
      final harness = await ProfileHarness.start(
        Profiles.p3.withConnection(WorldConnections.emby),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: HomeNowPlayingModule()),
          ),
        ),
      );
      await harness.settle(tester);

      expect(find.text('Now playing'), findsOne);
      expect(find.text('Emby'), findsOne);
      expect(find.textContaining('Sintel'), findsOne);
      await harness.unmount(tester);
    });

    test('the Stack\'s figures count Emby\'s streams and libraries', () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withConnection(WorldConnections.emby),
      );
      final container = harness.container(retry: (_, _) => null);

      final kpis = await container.read(
        serviceKpiProvider(ServiceKey.emby).future,
      );
      final figures = {for (final kpi in kpis) kpi.label: kpi};

      expect(figures['Streams']!.value, '1');
      expect(figures['Libraries']!.value, '3');
    });

    test('a household member\'s Emby still counts its libraries', () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withConnection(
          ProfileConnection(
            WorldConnections.emby.instance.copyWith(viewerId: EmbyFake.annaId),
            behaviour: ConnectionBehaviour.readOnly,
          ),
        ),
      );
      final container = harness.container(retry: (_, _) => null);

      final kpis = await container.read(
        serviceKpiProvider(ServiceKey.emby).future,
      );
      final figures = {for (final kpi in kpis) kpi.label: kpi};

      // Emby lets a member read the library list, so nothing is withheld.
      expect(figures['Libraries']!.value, '3');
      expect(figures['Libraries']!.note, isNull);
    });
  });

  group('the requester who watches in Emby', () {
    test('is still the requester: a player is no stack', () async {
      final harness = await ProfileHarness.start(_annaWithEmby);
      expect(harness.container().read(audienceProvider), Audience.requester);
      expect(harness.network.requests, isEmpty);
    });

    test('her search still asks Seerr alone', () async {
      final harness = await ProfileHarness.start(_annaWithEmby);
      final legs = harness.container().read(globalSearchLegsProvider);

      expect(legs.map((leg) => leg.instance.service), [ServiceKey.seerr]);
    });

    test('the title on Emby reads as Emby, her player', () async {
      final rows = (await settledRows(
        _annaWithEmby,
        WorldTitles.tearsOfSteel,
      )).rows;

      final emby = rows.whereType<MediaConnectionRow<Object?>>().where(
        (row) => row.service == ServiceKey.emby,
      );
      expect(emby, hasLength(1));
    });
  });

  group('the global search', () {
    test('has an Emby leg, like Jellyfin\'s', () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withConnection(WorldConnections.emby),
      );
      final legs = harness.container().read(globalSearchLegsProvider);

      expect(
        legs.map((leg) => leg.instance.service),
        contains(ServiceKey.emby),
      );
    });
  });
}
