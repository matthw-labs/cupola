@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_library_screen.dart';

import '../test_helpers/profiles/profiles.dart';
import 'catalog.dart';
import 'emby_world.dart';

/// One library on a media server, whole: every title it holds, the order the
/// person picks, all of it or only what is unplayed. Read from the demo
/// world's fake Emby, so the app's own client, provider and parser draw it.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Widget movies() => const EmbyWorldScope(
    child: StreamLibraryScreen(
      service: ServiceKey.emby,
      instanceId: WorldIds.emby,
      libraryId: '3',
      libraryTitle: 'Movies',
    ),
  );

  catalogCard(
    'StreamLibrary',
    overrides: () =>
        startEmbyWorld(Profiles.p1.withConnection(WorldConnections.emby)),
    scenes: [
      CatalogScene(
        'StreamLibraryScreen · an Emby movie library, whole and A to Z: the '
        'count line, All and Unplayed, the sort control, the poster wall',
        (_) => movies(),
        width: 390,
        height: 844,
        id: 'library-whole',
      ),
      CatalogScene(
        'StreamLibraryScreen · Unplayed chosen, for the viewer the '
        'connection reads: on this Emby nobody has played a movie yet, so '
        'every one is still there',
        (_) => movies(),
        width: 390,
        height: 844,
        id: 'library-unplayed',
        act: (tester, scene) async {
          await tester.tap(
            find.descendant(of: scene, matching: find.text('Unplayed')),
          );
        },
      ),
      CatalogScene(
        'StreamLibraryScreen · in a 1280 desktop window',
        (_) => movies(),
        width: 1280,
        height: 800,
        platform: CatalogPlatform.desktop,
        id: 'library-desktop',
      ),
      CatalogScene(
        'StreamLibraryScreen · text at 200%: the chips and the sort control '
        'keep their words, the wall keeps three columns',
        (_) => movies(),
        width: 390,
        height: 844,
        textScale: catalogTextScale,
        id: 'library-200',
      ),
    ],
  );
}
