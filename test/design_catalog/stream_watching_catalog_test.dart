@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/plex/presentation/plex_tab_screens.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_watching.dart';

import '../test_helpers/profiles/profiles.dart';
import 'catalog.dart';
import 'emby_world.dart';

/// What a media server says about watching: Continue watching (On deck on
/// Plex), Next up and Recently added, whole in the server's Activity and as a
/// rail each on its Overview. Read from the demo world's fake Emby and Plex.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Widget rails(ServiceKey service, String instanceId) => EmbyWorldScope(
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final shelf in streamWatchingShelvesOf(service))
            if (shelf != StreamWatchingShelf.nextUp)
              StreamWatchingRail(
                service: service,
                instanceId: instanceId,
                shelf: shelf,
              ),
        ],
      ),
    ),
  );

  catalogCard(
    'StreamWatching',
    overrides: () => startEmbyWorld(
      Profiles.p1
          .withConnection(WorldConnections.emby)
          .withConnection(WorldConnections.plex),
    ),
    scenes: [
      CatalogScene(
        'JellyfinActivityScreen(service: emby) · who is watching now, then '
        'Continue watching and Next up as rows with how far in, and Recently '
        'added as posters',
        (_) => const EmbyWorldScope(
          child: JellyfinActivityScreen(
            service: ServiceKey.emby,
            instanceId: WorldIds.emby,
          ),
        ),
        width: 390,
        height: 900,
        id: 'emby-activity',
      ),
      CatalogScene(
        'PlexActivitiesScreen · On deck (in progress and up next at once) '
        'and Recently added, with no Next up of its own',
        (_) => const EmbyWorldScope(
          child: PlexActivitiesScreen(instanceId: WorldIds.plex),
        ),
        width: 390,
        height: 900,
        id: 'plex-activities',
      ),
      CatalogScene(
        'StreamWatchingRail · the Overview\'s glance on Emby: Continue '
        'watching as wide pictures with their bar, Recently added as posters',
        (_) => rails(ServiceKey.emby, WorldIds.emby),
        width: 390,
        height: 560,
        id: 'emby-rails',
      ),
      CatalogScene(
        'StreamWatchingRail · on Plex: On deck and Recently added',
        (_) => rails(ServiceKey.plex, WorldIds.plex),
        width: 390,
        height: 560,
        id: 'plex-rails',
      ),
      CatalogScene(
        'StreamWatchingRail · text at 200%: the rails grow to hold their '
        'captions',
        (_) => rails(ServiceKey.emby, WorldIds.emby),
        width: 390,
        height: 820,
        textScale: catalogTextScale,
        id: 'emby-rails-200',
      ),
    ],
  );
}
