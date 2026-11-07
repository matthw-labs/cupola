/// The canonical Media page against the households: who the title is, the
/// one lead, and every row spoken as one sentence.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/file_info_section.dart';
import 'package:cupola/core/widgets/machine_name.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_poster.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_identity.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_series_sections.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/operator_adds_via_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/profiles/profiles.dart';

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  WorldTitle title, {
  List<Override> overrides = const [],
  MediaKey? key,
  double height = 2400,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await pumpWithProfile(
    tester,
    profile,
    overrides: overrides,
    child: MediaPage(mediaKey: key ?? MediaKey.movie(title.tmdbId)),
    settle: false,
  );
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return harness;
}

/// The operator's choice of how a title nobody holds is added, fixed for a
/// test. The choice is kept on the device, so a test that is not about it
/// fixes it here instead of reading whatever a launch left behind.
class _AddsVia extends OperatorAddsViaNotifier {
  _AddsVia(this.via);

  final OperatorAddsVia via;

  @override
  OperatorAddsVia build() => via;
}

Override _addingVia(OperatorAddsVia via) =>
    operatorAddsViaProvider.overrideWith(() => _AddsVia(via));

/// Seerr knows [title] and nobody has asked for it: no media row.
Override _unrequested(WorldTitle title) =>
    mediaSeerrRecordProvider.overrideWith(
      (ref, source) async => MediaAnswer(
        MediaSeerrRecord(
          details: {
            'id': title.tmdbId,
            'title': title.title,
            'releaseDate': '${title.year}-01-10',
            'overview': 'A movie nobody has asked for.',
          },
        ),
        DateTime(2026, 10, 4),
      ),
    );

/// The page under a router, for the rows that lead somewhere: anything
/// under Settings draws its own location.
Future<(ProfileHarness, GoRouter)> _pumpRouted(
  WidgetTester tester,
  ConfigProfile profile,
  WorldTitle title, {
  MediaKey? key,
  String? focus,
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => MediaPage(
          mediaKey: key ?? MediaKey.movie(title.tmdbId),
          focus: focus,
        ),
      ),
      GoRoute(
        path: '/settings/service/:service',
        builder: (context, state) => Text('at ${state.uri}'),
      ),
      GoRoute(
        path: '/import/browse',
        builder: (context, state) => Text('at ${state.uri}'),
      ),
      GoRoute(
        path: '/import/review',
        builder: (context, state) => Text('at ${state.uri}'),
      ),
      GoRoute(
        path: ServiceRoutes.activityDownloadPath,
        builder: (context, state) => Text('at ${state.uri}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await _answer(tester);
  return (harness, router);
}

/// Lets the profile's servers answer.
Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  for (final (name, width, gutter) in [
    ('a phone', 390.0, AppSpacing.lg),
    // A page wider than the well: the column centred in it.
    ('a wide page', 1400.0, (1400 - AppBreakpoints.contentWell) / 2),
  ]) {
    testWidgets('on $name More like this runs across the page, its heading and '
        'first poster on the column\'s line', (tester) async {
      // Inside the column's margin the row's own margin doubled it, and the
      // posters were cut at the column's edge.
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.tearsOfSteel,
        width: width,
        height: 6000,
      );

      final heading = find.text('More like this');
      expect(heading, findsOneWidget);
      expect(tester.getTopLeft(heading).dx, gutter);
      final row = find.ancestor(
        of: find.text(WorldTitles.sintel.title).last,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.horizontal,
        ),
      );
      expect(tester.getRect(row).width, width);
      expect(tester.getTopLeft(find.byType(CatalogPoster).first).dx, gutter);

      await harness.unmount(tester);
    });
  }

  testWidgets('Manage reaches its heading on a series the list has not '
      'built down to yet', (tester) async {
    final harness = await _pump(
      tester,
      Profiles.p1,
      WorldTitles.cosmosLaundromat,
      key: MediaKey.tv(WorldTitles.cosmosLaundromat.tmdbId),
      height: 844,
    );
    final heading = find.byWidgetPredicate(
      (widget) => widget is MediaHeading && widget.text == 'Manage',
    );
    // The button, the only Manage while the heading is unbuilt: below the
    // seasons, past what the list builds ahead.
    final button = find.text('Manage');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(heading, findsNothing);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(heading.hitTestable(), findsOneWidget);
    await harness.unmount(tester);
  });

  testWidgets('P1, Tears of Steel: its title, Play on Jellyfin, its rows', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    expect(find.text('Tears of Steel'), findsOneWidget);
    expect(find.text('Play on Jellyfin'), findsOneWidget);
    // The marks: Jellyfin's copy is 2160p in HDR10.
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('HDR10'), findsOneWidget);
    expect(find.text('On your server'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Jellyfin\. .*Available$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Bazarr\. DE wanted$')),
      findsOneWidget,
    );
    expect(find.text('Manage'), findsWidgets);

    await harness.unmount(tester);
  });

  testWidgets('the collection says how much of it is on the server', (
    tester,
  ) async {
    final (harness, router) = await _pumpRouted(
      tester,
      Profiles.p1,
      WorldTitles.tearsOfSteel,
    );

    final band = find.bySemanticsLabel(
      'Blender Open Movies, 5 of 8 on your server',
    );
    await tester.ensureVisible(band);
    expect(band, findsOneWidget);
    expect(find.text('Collection'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P1, a series downloading: its downloads sit under the lead, and '
      'a row opens its own page beside the title', (tester) async {
    final (harness, router) = await _pumpRouted(
      tester,
      Profiles.p1,
      WorldTitles.cosmosLaundromat,
      key: MediaKey.tv(WorldTitles.cosmosLaundromat.tmdbId),
    );

    final rows = find.byType(DownloadRow);
    expect(rows, findsWidgets);
    // Its finished episodes Sonarr will not import are no downloads any more,
    // as on the Home: the copy's row names them, with Review the imports.
    expect(
      tester.widgetList<DownloadRow>(rows).map((row) => row.item.fault),
      isNot(contains(InFlightFault.needsImport)),
    );
    expect(find.textContaining('need import'), findsOneWidget);
    await tester.ensureVisible(rows.first);
    await tester.tap(rows.first);
    await _answer(tester);

    final at = router.state.uri;
    expect(at.path, ServiceRoutes.activityDownloadPath);
    expect(at.queryParameters['i'], WorldIds.sonarr);
    expect(at.queryParameters['id'], isNotEmpty);

    await harness.unmount(tester);
  });

  testWidgets('a requester never sees the downloads of a title: the queue is '
      'the operator\'s', (tester) async {
    final harness = await _pump(
      tester,
      Profiles.p1,
      WorldTitles.cosmosLaundromat,
      key: MediaKey.tv(WorldTitles.cosmosLaundromat.tmdbId),
      overrides: [audienceProvider.overrideWithValue(Audience.requester)],
    );

    expect(find.byType(DownloadRow), findsNothing);
    expect(find.textContaining('more in Activity'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P1, a title with nothing in the queue shows no download rows', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    expect(find.byType(DownloadRow), findsNothing);
    expect(find.textContaining('more in Activity'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P1, a copy that leads with its download says so once: Open '
      'download, and no row beside it', (tester) async {
    final (harness, router) = await _pumpRouted(
      tester,
      Profiles.p1,
      WorldTitles.bigBuckBunny,
    );

    // The copy panel speaks for its own download: no row repeats it.
    expect(find.byType(DownloadRow), findsNothing);
    final open = find.widgetWithText(OutlinedButton, 'Open download');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await _answer(tester);

    final at = router.state.uri;
    expect(at.path, ServiceRoutes.activityDownloadPath);
    expect(at.queryParameters['i'], WorldIds.radarr);

    await harness.unmount(tester);
  });

  testWidgets('Files & quality opens on each copy\'s file, read only then', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    expect(find.byType(FileInfoSection), findsNothing);
    await tester.tap(find.text('Files & quality'));
    await tester.pump();

    expect(find.byType(FileInfoSection), findsNWidgets(2));

    await harness.unmount(tester);
  });

  testWidgets('History opens on each copy\'s own imports', (tester) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('History'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.bySemanticsLabel(RegExp(r'^Imported\. 1080p Bluray\. ')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Imported\. 2160p Bluray\. ')),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('P4, without Seerr: one dimmed row that sets it up', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);

    expect(find.text('Set up Seerr'), findsOneWidget);
    // Watchlist is Seerr's: without one it steps aside, no dimmed copy.
    expect(find.text('Watchlist'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P7, Jellyfin silent: no Play, and its row offers Retry', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p7, WorldTitles.tearsOfSteel);

    expect(find.textContaining('Play on'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'^Jellyfin\. .*Did not answer.*Retry$')),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('a row not set up is the way to its form, pill and all', (
    tester,
  ) async {
    final (harness, _) = await _pumpRouted(
      tester,
      Profiles.p4,
      WorldTitles.tearsOfSteel,
    );

    await tester.tap(find.text('Set up Seerr'));
    await tester.pumpAndSettle();
    expect(
      find.text('at ${ServiceRoutes.setUp(ServiceKey.seerr)}'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Retry asks the silent connection again, and only it', (
    tester,
  ) async {
    final (harness, _) = await _pumpRouted(
      tester,
      Profiles.p7,
      WorldTitles.tearsOfSteel,
    );
    // By address and port: the household's services share a host.
    String at(ServiceKey service) => Uri.parse(
      harness.profile.settings.instancesOf(service).first.url,
    ).authority;
    int asked(ServiceKey service) => harness.network.requests
        .where((request) => request.uri.authority == at(service))
        .length;
    final jellyfin = asked(ServiceKey.jellyfin);
    final radarr = asked(ServiceKey.radarr);
    final bazarr = asked(ServiceKey.bazarr);
    expect(jellyfin, greaterThan(0));

    // Bazarr is silent too, and keeps its own Retry.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Jellyfin\. .*Retry$')));
    await _answer(tester);

    expect(asked(ServiceKey.jellyfin), greaterThan(jellyfin));
    expect(asked(ServiceKey.radarr), radarr);
    expect(asked(ServiceKey.bazarr), bazarr);

    await harness.unmount(tester);
  });

  testWidgets('Subtitles opens on what Bazarr has and still wants', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('Subtitles'));
    await tester.pump();
    expect(find.text('Wanted'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Add opens on the Radarr, its profile, folder and indexers', (
    tester,
  ) async {
    // P1 holds no Metropolis, and here nobody has asked for it: with the
    // operator adding straight to Radarr, the first Radarr leads, and the
    // sheet says what adding it there means.
    final harness = await _pump(
      tester,
      Profiles.p1,
      WorldTitles.metropolis,
      overrides: [
        _unrequested(WorldTitles.metropolis),
        _addingVia(OperatorAddsVia.arr),
      ],
    );
    final lead = find.widgetWithText(FilledButton, 'Add to Radarr');
    expect(lead, findsOneWidget);

    await tester.tap(lead);
    await _answer(tester);
    expect(find.text('Metropolis\u00A0· 1927'), findsOneWidget);
    expect(find.text('Instance'), findsOneWidget);
    expect(find.text('HD-1080p'), findsOneWidget);
    expect(find.text('/mnt/tank/media/films'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^11\.3.TB free$')), findsOneWidget);
    expect(find.text('Grabs it and upgrades it to HD-1080p'), findsOneWidget);
    expect(find.text('Asks your 2 indexers right away'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add and search'), findsOneWidget);

    // Unmonitored, Radarr never looks: the search goes with it.
    await tester.tap(find.text('Monitor'));
    await tester.pump();
    expect(find.text('Needs Monitor on'), findsOneWidget);
    expect(find.text('Add and search'), findsNothing);
    await tester.tap(find.text('Monitor'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Add and search'));
    await _answer(tester);
    final add = harness.network
        .requestsTo(WorldIds.radarr)
        .where((r) => r.method == 'POST' && r.uri.path == '/api/v3/movie')
        .single;
    expect(add.json, containsPair('tmdbId', WorldTitles.metropolis.tmdbId));
    expect(add.json, containsPair('qualityProfileId', 1));
    expect(add.json, containsPair('rootFolderPath', '/mnt/tank/media/films'));
    expect(add.json, containsPair('monitored', true));
    expect(add.json, containsPair('addOptions', {'searchForMovie': true}));
    expect(find.textContaining('Added to Radarr'), findsOneWidget);
    // The sheet is gone, and Radarr is asked again.
    expect(find.text('Instance'), findsNothing);
    expect(
      harness.network
          .requestsTo(WorldIds.radarr)
          .where((r) => r.method == 'GET' && r.uri.path == '/api/v3/movie'),
      hasLength(2),
    );

    await harness.unmount(tester);
  });

  testWidgets('through Seerr by default, Request leads on a title no Radarr '
      'holds, and its sheet offers Add to Radarr instead', (tester) async {
    final harness = await _pump(
      tester,
      Profiles.p1,
      WorldTitles.metropolis,
      overrides: [_unrequested(WorldTitles.metropolis)],
    );
    expect(find.widgetWithText(FilledButton, 'Add to Radarr'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Request'));
    await _answer(tester);
    expect(find.text('Request Metropolis'), findsOneWidget);

    // The other way, quiet at the foot of the request sheet: it closes this
    // sheet and opens the add sheet on Radarr.
    await tester.tap(find.widgetWithText(TextButton, 'Add to Radarr instead'));
    await _answer(tester);
    expect(find.text('Request Metropolis'), findsNothing);
    expect(find.text('Metropolis\u00A0· 1927'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add and search'), findsOneWidget);
    // One time only: the choice on the device is still Seerr.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MediaPage)),
    );
    expect(container.read(operatorAddsViaProvider), OperatorAddsVia.seerr);

    await harness.unmount(tester);
  });

  testWidgets('just requested and passed on by Seerr, the line under Requested '
      'says what Radarr says, as its row does', (tester) async {
    // Seerr reads Processing the moment it sends an approved request on,
    // whether or not Radarr took it: Radarr here holds no Metropolis.
    final harness = await _pump(
      tester,
      Profiles.p1,
      WorldTitles.metropolis,
      overrides: [
        mediaSeerrRecordProvider.overrideWith(
          (ref, source) async => MediaAnswer(
            MediaSeerrRecord(
              details: {
                'id': WorldTitles.metropolis.tmdbId,
                'title': WorldTitles.metropolis.title,
                'releaseDate': '${WorldTitles.metropolis.year}-01-10',
                'overview': 'A movie just requested.',
                'mediaInfo': {'status': 3},
              },
            ),
            DateTime(2026, 10, 4),
          ),
        ),
      ],
    );

    expect(find.widgetWithText(FilledButton, 'Requested'), findsOneWidget);
    // Each Radarr, the 4K one too, answered without it.
    expect(find.text('Not added yet'), findsWidgets);
    expect(find.text('Radarr is already tracking this.'), findsNothing);
    expect(find.text('Radarr has not added it yet.'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('straight to the arr, Add leads and its sheet offers Request '
      'through Seerr instead', (tester) async {
    final harness = await _pump(
      tester,
      Profiles.p1,
      WorldTitles.metropolis,
      overrides: [
        _unrequested(WorldTitles.metropolis),
        _addingVia(OperatorAddsVia.arr),
      ],
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add to Radarr'));
    await _answer(tester);
    expect(find.text('Metropolis\u00A0· 1927'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(TextButton, 'Request through Seerr instead'),
    );
    await _answer(tester);
    expect(find.text('Metropolis\u00A0· 1927'), findsNothing);
    expect(find.text('Request Metropolis'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Remove asks what goes with it, then asks Radarr', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);
    final row = find.textContaining(RegExp(r'^Remove from '));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Remove Tears of Steel from Radarr?'), findsOneWidget);
    expect(find.text('Radarr stops looking for it.'), findsOneWidget);
    expect(find.text("Don't add it again"), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Remove from Radarr'), findsOne);

    await tester.tap(find.textContaining('Also delete'));
    await tester.pump();
    final confirm = find.ancestor(
      of: find.textContaining(RegExp(r'^Remove and delete 1\.1.GB$')),
      matching: find.byType(FilledButton),
    );
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await _answer(tester);

    final delete = harness.network
        .requestsTo(WorldIds.radarr)
        .where((r) => r.method == 'DELETE')
        .single;
    expect(delete.uri.path, '/api/v3/movie/5');
    expect(delete.uri.queryParameters, {
      'deleteFiles': 'true',
      'addImportExclusion': 'false',
    });
    expect(find.text('Removed from Radarr'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Clear from Seerr asks, says what stays, then asks Seerr', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);
    final row = find.text('Clear from Seerr');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Clear Tears of Steel from Seerr?'), findsOneWidget);
    expect(
      find.textContaining('Nothing is removed from your server.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Clear from Seerr'));
    await _answer(tester);

    final delete = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.method == 'DELETE')
        .single;
    expect(delete.uri.path, '/api/v1/media/${WorldTitles.tearsOfSteel.tmdbId}');
    expect(find.text('Cleared from Seerr'), findsOneWidget);
    expect(
      harness.network.requests.where(
        (r) => r.method == 'DELETE' && r.server?.id != WorldIds.seerr,
      ),
      isEmpty,
    );

    await harness.unmount(tester);
  });

  testWidgets("an account that may not manage media says why, and Clear "
      "does nothing", (tester) async {
    final harness = await _pump(tester, Profiles.p9, WorldTitles.tearsOfSteel);
    final rows = find.textContaining(RegExp(r'^Clear from '));
    await tester.ensureVisible(rows.last);
    printOnFailure(
      [for (final e in rows.evaluate()) (e.widget as Text).data].join('\n'),
    );
    expect(rows, findsNWidgets(2));
    expect(find.textContaining("can't manage media."), findsOneWidget);
    await tester.tap(rows.last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Clear Tears of Steel from'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('a copy only Seerr reaches is removed through Seerr, with its '
      'files', (tester) async {
    final harness = await _pump(tester, Profiles.p5, WorldTitles.tearsOfSteel);
    final row = find.textContaining(RegExp(r'^Remove from '));
    await tester.ensureVisible(row);
    expect(find.text('Through Seerr, with its files'), findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('to remove it and delete its files'),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Remove and delete its files'),
    );
    await _answer(tester);

    final delete = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.method == 'DELETE')
        .single;
    expect(
      delete.uri.path,
      '/api/v1/media/${WorldTitles.tearsOfSteel.tmdbId}/file',
    );
    expect(delete.uri.queryParameters, {'is4k': 'false'});

    await harness.unmount(tester);
  });

  testWidgets('with two copies, Remove asks which, and says which stays', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p7, WorldTitles.tearsOfSteel);
    final row = find.text('Remove a copy');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pump();
    final fourK = find.bySemanticsLabel('Remove from Radarr\u00A0· 4K');
    expect(find.bySemanticsLabel('Remove from Radarr 1'), findsOneWidget);
    expect(fourK, findsOneWidget);

    await tester.tap(fourK);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Radarr\u00A0· 4K stops looking for it. Radarr 1 keeps its copy.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(
      harness.network.requests.where((r) => r.method == 'DELETE'),
      isEmpty,
    );

    await harness.unmount(tester);
  });

  testWidgets('a stuck copy leads with its fault and its remedy', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.bigBuckBunny);

    expect(find.text('Stuck at 47%'), findsOneWidget);
    expect(find.text('Radarr 1\u00A0· qBittorrent'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MachineName &&
            widget.name == 'Big.Buck.Bunny.2008.1080p.BluRay',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Try another download'),
      findsOneWidget,
    );
    expect(
      find.textContaining(RegExp(r"^Radarr 1 drops this one \(.+ so far\), ")),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove download'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from queue?'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a copy\'s profile and monitoring are changed where they are '
      'read', (tester) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);
    await tester.ensureVisible(find.text('Files & quality'));
    await tester.tap(find.text('Files & quality'));
    await _answer(tester);

    expect(find.text('Quality profile'), findsOneWidget);
    expect(find.text('HD-1080p'), findsOneWidget);
    expect(find.text('Grabs it and upgrades it to HD-1080p'), findsOneWidget);

    await tester.tap(find.text('Monitor'));
    await tester.pump();
    // It shows at once, and Radarr is told. (The world keeps nothing: the
    // copy read again after the write says what it always said.)
    expect(find.text('Radarr lists it and never looks for it'), findsOneWidget);
    await _answer(tester);
    final put = harness.network
        .requestsTo(WorldIds.radarr)
        .where((r) => r.method == 'PUT')
        .single;
    expect(put.uri.path, '/api/v3/movie/5');
    expect(put.json, containsPair('monitored', false));

    await harness.unmount(tester);
  });

  testWidgets('the requester asks for a movie that is not there', (
    tester,
  ) async {
    // In the world Anna has asked for Charge already: here Seerr knows
    // nothing of it yet.
    final harness = await _pump(
      tester,
      Profiles.p2,
      WorldTitles.charge,
      overrides: [
        mediaSeerrRecordProvider.overrideWith(
          (ref, source) async => MediaAnswer(
            const MediaSeerrRecord(
              details: {
                'id': 1011985,
                'title': 'Charge',
                'releaseDate': '2022-10-11',
                'overview': 'A Blender open movie.',
              },
            ),
            DateTime(2026, 10, 4),
          ),
        ),
      ],
    );
    final request = find.widgetWithText(FilledButton, 'Request');
    expect(request, findsOneWidget);
    expect(find.text('Not on the server yet.'), findsOneWidget);
    // No service name but Jellyfin and Plex, no Manage.
    expect(find.textContaining('Radarr'), findsNothing);
    expect(find.text('Manage'), findsNothing);

    await tester.tap(request);
    await _answer(tester);
    expect(find.text('Request Charge'), findsOneWidget);
    expect(find.text('Submit request'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a request that stands is said, and asks nothing', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p2, WorldTitles.metropolis);

    final lead = find.widgetWithText(FilledButton, 'Requested');
    expect(lead, findsOneWidget);
    expect(tester.widget<FilledButton>(lead).onPressed, isNull);
    // Deciding is the operator's.
    expect(find.text('Approve'), findsNothing);
    expect(
      find.textContaining(RegExp(r'^(Waiting for approval|On its way)\.$')),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Watchlist puts the title on the list of whom Seerr acts as', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);
    final watchlist = find.widgetWithText(OutlinedButton, 'Watchlist');
    expect(watchlist, findsOneWidget);

    await tester.tap(watchlist);
    await _answer(tester);
    final add = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.method == 'POST' && r.uri.path == '/api/v1/watchlist')
        .single;
    expect(add.json, {
      'tmdbId': WorldTitles.tearsOfSteel.tmdbId,
      'mediaType': 'movie',
      'title': 'Tears of Steel',
    });
    expect(find.text('On your watchlist'), findsWidgets);

    await harness.unmount(tester);
  });

  testWidgets('on the server by Seerr\'s word: watched in its player', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p2, WorldTitles.tearsOfSteel);

    final watch = find.widgetWithText(FilledButton, 'Watch on Jellyfin');
    expect(watch, findsOneWidget);
    expect(tester.widget<FilledButton>(watch).onPressed, isNotNull);
    expect(find.text('Request'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('without a media server of its own, the operator watches in '
      'the one Seerr is set up with', (tester) async {
    final (harness, _) = await _pumpRouted(
      tester,
      Profiles.p3,
      WorldTitles.tearsOfSteel,
    );

    final watch = find.widgetWithText(FilledButton, 'Watch on Jellyfin');
    expect(watch, findsOneWidget);
    expect(tester.widget<FilledButton>(watch).onPressed, isNotNull);
    expect(find.text('through Seerr'), findsWidgets);
    expect(find.text('Trailer'), findsNothing);

    await tester.tap(find.text('Add Jellyfin to Cupola'));
    await tester.pumpAndSettle();
    expect(
      find.text('at ${ServiceRoutes.setUp(ServiceKey.jellyfin)}'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Search releases asks which copy when there are two', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p7, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('Search releases'));
    await tester.pump();
    expect(
      find.bySemanticsLabel('Search releases on Radarr 1'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Search releases on Radarr\u00A0· 4K'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Search releases on one copy opens its releases', (tester) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('Search releases'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Releases'), findsWidgets);

    await harness.unmount(tester);
  });

  testWidgets('a request that waits is answered from the page', (tester) async {
    // Anna asked for Charge, and nobody holds it: the answer leads, not Add.
    final harness = await _pump(tester, Profiles.p1, WorldTitles.charge);

    expect(find.text('${WorldPeople.anna} asked for it'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Waiting for approval\u00A0· ')),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Add to Radarr'), findsNothing);
    // The line under the buttons would say it twice.
    expect(find.text('Waiting for approval.'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await _answer(tester);
    expect(find.text('Approve Charge'), findsOneWidget);
    await tester.tap(find.text('Approve request'));
    await _answer(tester);
    final approve = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.method == 'POST')
        .single;
    expect(approve.uri.path, '/api/v1/request/1/approve');

    await harness.unmount(tester);
  });

  testWidgets('Decline asks, then tells Seerr', (tester) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.metropolis);

    expect(find.text('${WorldPeople.luca} asked for it'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    await _answer(tester);
    expect(find.text('Decline this request?'), findsOneWidget);
    await tester.tap(find.text('Decline request'));
    await _answer(tester);
    final decline = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.method == 'POST')
        .single;
    expect(decline.uri.path, '/api/v1/request/2/decline');

    await harness.unmount(tester);
  });

  testWidgets('where it streams and when it came out, in the region set', (
    tester,
  ) async {
    // The household's region is Italy: TMDB's American list stays out.
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    expect(find.text('Where to watch'), findsOneWidget);
    expect(find.text('Italy'), findsNWidgets(2));
    expect(
      find.bySemanticsLabel('Stream: Netflix, Prime Video'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Buy or rent: Apple TV'), findsOneWidget);
    expect(find.textContaining('Hulu'), findsNothing);
    expect(find.text('Release dates'), findsOneWidget);
    expect(find.text('In cinemas'), findsOneWidget);
    expect(find.text('Wed 26 Sep 2012'), findsOneWidget);
    expect(find.text('Mon 12 Nov 2012'), findsOneWidget);
    // TMDB has no disc date for it here: no row.
    expect(find.text('Physical'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('without Seerr, nowhere to watch is claimed', (tester) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);

    expect(find.text('Where to watch'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('a file already on the server is imported into this copy', (
    tester,
  ) async {
    final (harness, router) = await _pumpRouted(
      tester,
      Profiles.p4,
      WorldTitles.tearsOfSteel,
    );
    await tester.ensureVisible(find.text('Files & quality'));
    await tester.tap(find.text('Files & quality'));
    await _answer(tester);

    final import = find.text('Import a file');
    await tester.ensureVisible(import);
    await tester.tap(import);
    await _answer(tester);
    final at = router.state.uri;
    expect(at.path, '/import/browse');
    expect(at.queryParameters, {
      'service': 'radarr',
      'targetId': '5',
      'i': WorldIds.radarr,
    });

    await harness.unmount(tester);
  });

  testWidgets('a title only a media server holds is still named, and played '
      'there', (tester) async {
    // A household with Jellyfin and nothing else: no Seerr to say who the
    // title is, no arr. The server's own item says it.
    final harness = await _pump(
      tester,
      ConfigProfile(
        id: 'Z1',
        title: 'Jellyfin alone',
        summary: 'Only a Jellyfin.',
        cases: const {},
        connections: [WorldConnections.jellyfin],
      ),
      WorldTitles.tearsOfSteel,
    );

    expect(find.text('Tears of Steel'), findsWidgets);
    expect(find.textContaining('2012'), findsWidgets);
    expect(find.text('Play on Jellyfin'), findsOneWidget);
    // No Seerr and no arr: no source here has a score to give.
    expect(find.text('Rotten Tomatoes'), findsNothing);

    await harness.unmount(tester);
  });

  group('a series', () {
    final cosmos = MediaKey.tv(WorldTitles.cosmosLaundromat.tmdbId);

    testWidgets('continues where the viewer is, and says what airs next', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );

      expect(find.text('Resume S2\u00A0E3'), findsOneWidget);
      expect(
        find.text('The Second Cycle\u00A0· 5\u00A0min\u00A0left'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Series\u00A0· 2015–\u00A0· 3\u00A0seasons'),
        findsOneWidget,
      );
      expect(
        find.textContaining('S3\u00A0E1\u00A0· premiere at'),
        findsOneWidget,
      );
      expect(find.text('Sonarr looks for it once it airs'), findsOneWidget);
      // Two scores: TMDB's, and Rotten Tomatoes' through Seerr.
      expect(find.text('88'), findsOneWidget);
      expect(find.text('IMDb'), findsNothing);
      // Manage, in the header and over its sections.
      expect(find.text('Manage'), findsNWidgets(2));

      await harness.unmount(tester);
    });

    testWidgets('shows its episodes a season at a time, and asks Sonarr for '
        'the missing', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );

      // The season Play continues.
      expect(find.text('The Second Cycle'), findsOneWidget);
      expect(find.text('Downloading 88%'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Episode 6, The Seventh Cycle. Missing'),
        findsOneWidget,
      );

      final search = find.text('Search the 5 missing');
      await tester.ensureVisible(search);
      await tester.tap(search);
      await _answer(tester);
      final asked = harness.network
          .requestsTo(WorldIds.sonarr)
          .where((r) => r.method == 'POST' && r.uri.path == '/api/v3/command')
          .single;
      expect(asked.json, containsPair('name', 'EpisodeSearch'));
      expect(
        asked.json,
        containsPair('episodeIds', [1016, 1017, 1018, 1019, 1020]),
      );
      expect(find.text('Sonarr is searching for the 5'), findsOneWidget);

      await tester.ensureVisible(find.text('Season 1'));
      await tester.tap(find.text('Season 1'));
      await tester.pumpAndSettle();
      expect(find.text('The Second Cycle'), findsNothing);
      expect(find.text('Episode 10'), findsOneWidget);
      // Nothing of the first season is missing.
      expect(find.textContaining('missing'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('sends a stuck upgrade to the review of Sonarr\'s imports', (
      tester,
    ) async {
      final (harness, router) = await _pumpRouted(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );

      expect(find.textContaining('12 upgrades need import'), findsOneWidget);
      final review = find.text('Review the imports');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await _answer(tester);
      final at = router.state.uri;
      expect(at.path, '/import/review');
      expect(at.queryParameters, {
        'service': 'sonarr',
        'targetId': '1',
        'i': WorldIds.sonarr,
      });

      await harness.unmount(tester);
    });

    testWidgets('opens an episode whole: where it plays, what Sonarr holds', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );
      await tester.ensureVisible(find.text('The Second Cycle'));
      await tester.tap(find.text('The Second Cycle'));
      await _answer(tester);

      expect(
        find.textContaining('Season 2\u00A0· Episode 3\u00A0· aired'),
        findsOneWidget,
      );
      expect(find.text('8.1'), findsOneWidget);
      expect(find.text('TMDB\u00A0· 37 votes'), findsOneWidget);
      expect(find.text('On Jellyfin'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
      expect(find.text('In Sonarr'), findsOneWidget);
      expect(find.text('1080p WEB'), findsOneWidget);
      expect(find.textContaining('imported today'), findsOneWidget);
      // At the profile's cutoff: nothing to search for, but a release can
      // still be chosen.
      expect(find.textContaining('Search for'), findsNothing);
      expect(find.text('Choose a release'), findsOneWidget);
      // Bazarr's languages for it.
      expect(
        find.text('English on disk\u00A0· Italian wanted'),
        findsOneWidget,
      );

      // The next one, a step away.
      await tester.tap(find.byTooltip('Next episode, E4'));
      await _answer(tester);
      expect(find.textContaining('Season 2\u00A0· Episode 4'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('searches for a file below the cutoff, and monitors in '
        'Sonarr', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );
      final first = find.text('Episode 1').first;
      await tester.ensureVisible(first);
      await tester.tap(first);
      await _answer(tester);

      expect(find.text('720p WEB'), findsOneWidget);
      expect(find.textContaining('Below the 1080p cutoff'), findsOneWidget);
      await tester.tap(find.text('Search for 1080p'));
      await _answer(tester);
      final search = harness.network
          .requestsTo(WorldIds.sonarr)
          .where((r) => r.method == 'POST' && r.uri.path == '/api/v3/command')
          .single;
      expect(search.json, containsPair('episodeIds', [1011]));

      await tester.ensureVisible(find.text('Monitored'));
      await tester.tap(find.text('Monitored'));
      await _answer(tester);
      final monitor = harness.network
          .requestsTo(WorldIds.sonarr)
          .where(
            (r) => r.method == 'PUT' && r.uri.path == '/api/v3/episode/monitor',
          )
          .single;
      expect(monitor.json, {
        'episodeIds': [1011],
        'monitored': false,
      });
      expect(find.text('Sonarr leaves it as it is'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('Manage holds Sonarr\'s files and seasons, and what Sonarr '
        'does about them', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );
      final files = find.text('Files & quality');
      await tester.ensureVisible(files);
      await _answer(tester);
      expect(find.text('13 files\u00A0· 720p WEB, 1080p WEB'), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'^Last imported S2\u00A0E3\u00A0· ')),
        findsOneWidget,
      );

      await tester.tap(files);
      await _answer(tester);
      expect(find.text('HD-1080p'), findsOneWidget);
      expect(
        find.text('Grabs new episodes and upgrades them to HD-1080p'),
        findsOneWidget,
      );
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('10 of 10 on disk\u00A0· 720p WEB'), findsOneWidget);
      expect(find.text('8 episodes\u00A0· not aired'), findsOneWidget);
      expect(find.text('Import a file'), findsOneWidget);

      // A season stops being looked for, and its episodes with it.
      final second = find.text('3 of 10 on disk\u00A0· 720p WEB, 1080p WEB');
      await tester.ensureVisible(second);
      await tester.tap(second);
      await _answer(tester);
      final put = harness.network
          .requestsTo(WorldIds.sonarr)
          .where((r) => r.method == 'PUT')
          .single;
      expect(put.uri.path, '/api/v3/series/1');
      expect(
        [
          for (final season in (put.json as Map)['seasons'] as List)
            (season['seasonNumber'], season['monitored']),
        ],
        [(1, true), (2, false), (3, true)],
      );

      await harness.unmount(tester);
    });

    testWidgets('a queue Sonarr could not read: no aired episode reads '
        'Missing', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
        overrides: [
          sonarrQueueSnapshotsForProvider.overrideWith(
            (ref, id) async => throw Exception('the queue did not answer'),
          ),
        ],
      );

      // A gap with no queue under it may be downloading: nothing is said
      // missing, and nothing is offered to search.
      expect(find.textContaining('Missing'), findsNothing);
      expect(find.textContaining('missing'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a file imported from Manage lands in the copy the page '
        'was opened on', (tester) async {
      // Agent 327 is on the anime Sonarr only.
      final (harness, router) = await _pumpRouted(
        tester,
        Profiles.p6,
        WorldTitles.agent327,
        key: MediaKey.tv(WorldTitles.agent327.tmdbId),
        focus: WorldIds.sonarrAnime,
        height: 3600,
      );
      final files = find.text('Files & quality');
      await tester.ensureVisible(files);
      await tester.tap(files);
      await _answer(tester);
      final import = find.text('Import a file');
      await tester.ensureVisible(import);
      await tester.tap(import);
      await _answer(tester);

      final at = router.state.uri;
      expect(at.path, '/import/browse');
      expect(at.queryParameters, containsPair('service', 'sonarr'));
      expect(at.queryParameters, containsPair('i', WorldIds.sonarrAnime));

      await harness.unmount(tester);
    });

    testWidgets('History names each event\'s episode, Subtitles each '
        'episode still wanting one, and Search releases opens a season that '
        'has aired', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );
      final history = find.text('History');
      await tester.ensureVisible(history);
      await tester.tap(history);
      await _answer(tester);
      expect(
        find.textContaining('Imported\u00A0· S2\u00A0E3\u00A0· 1080p WEB'),
        findsOneWidget,
      );

      final subtitles = find.text('Subtitles');
      await tester.ensureVisible(subtitles);
      expect(find.text('EN\u00A0· IT wanted on 3 episodes'), findsOneWidget);
      await tester.tap(subtitles);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('S2\u00A0E3, The Second Cycle: Italian wanted'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Search releases'));
      await tester.tap(find.text('Search releases'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Search releases for Season 2'),
        findsOneWidget,
      );
      // Nothing of the third has aired.
      expect(
        find.bySemanticsLabel('Search releases for Season 3'),
        findsNothing,
      );
      await tester.tap(find.bySemanticsLabel('Search releases for Season 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Releases'), findsWidgets);

      await harness.unmount(tester);
    });

    testWidgets('Automatic search asks Sonarr for every season, or a season '
        'it monitors that has aired', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );
      final row = find.text('Automatic search');
      await tester.ensureVisible(row);
      expect(
        find.text('Sonarr looks now for what it monitors'),
        findsOneWidget,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Search Every season'), findsOneWidget);
      expect(find.bySemanticsLabel('Search Season 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Search Season 2'), findsOneWidget);
      // Nothing of the third has aired.
      expect(find.bySemanticsLabel('Search Season 3'), findsNothing);

      List<Object?> commands() => [
        for (final r in harness.network.requestsTo(WorldIds.sonarr))
          if (r.method == 'POST' && r.uri.path == '/api/v3/command') r.json,
      ];

      await tester.tap(find.bySemanticsLabel('Search Every season'));
      await _answer(tester);
      expect(commands(), [
        {'name': 'SeriesSearch', 'seriesId': 1},
      ]);
      expect(find.text('Sonarr is searching for every season'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Search Season 2'));
      await _answer(tester);
      expect(commands().last, {
        'name': 'SeasonSearch',
        'seriesId': 1,
        'seasonNumber': 2,
      });

      await harness.unmount(tester);
    });

    testWidgets('Automatic search goes to the Sonarr that holds the copy', (
      tester,
    ) async {
      // Agent 327 is on the anime Sonarr only.
      final (harness, _) = await _pumpRouted(
        tester,
        Profiles.p6,
        WorldTitles.agent327,
        key: MediaKey.tv(WorldTitles.agent327.tmdbId),
        focus: WorldIds.sonarrAnime,
        height: 3600,
      );
      final row = find.text('Automatic search');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Search Season ')).first);
      await _answer(tester);

      bool asked(String id) => harness.network
          .requestsTo(id)
          .any((r) => r.method == 'POST' && r.uri.path == '/api/v3/command');
      expect(asked(WorldIds.sonarrAnime), isTrue);
      expect(asked(WorldIds.sonarr), isFalse);

      await harness.unmount(tester);
    });

    testWidgets('Remove asks what goes with it, then asks Sonarr', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );
      final row = find.text('Remove from Sonarr');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(
        find.text('Remove Cosmos Laundromat from Sonarr?'),
        findsOneWidget,
      );
      expect(find.text('Sonarr stops looking for it.'), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'^Also delete 8\.3.GB of files$')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Remove from Sonarr'));
      await _answer(tester);

      final delete = harness.network
          .requestsTo(WorldIds.sonarr)
          .where((r) => r.method == 'DELETE')
          .single;
      expect(delete.uri.path, '/api/v3/series/1');
      expect(delete.uri.queryParameters['deleteFiles'], 'false');
      expect(find.text('Removed from Sonarr'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a series nobody holds is added to Sonarr with the episodes '
        'it should look for', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.agent327,
        key: MediaKey.tv(WorldTitles.agent327.tmdbId),
        height: 2400,
        overrides: [_addingVia(OperatorAddsVia.arr)],
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add to Sonarr'));
      await _answer(tester);
      expect(find.text('All episodes'), findsOneWidget);
      expect(find.text('Every episode, aired and to come'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Episodes numbered by season, S01E02'), findsOneWidget);

      await tester.tap(find.text('All episodes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Future episodes').last);
      await tester.pumpAndSettle();
      expect(find.text('Only the ones that air from now'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add and search'));
      await _answer(tester);
      final add = harness.network
          .requestsTo(WorldIds.sonarr)
          .where((r) => r.method == 'POST' && r.uri.path == '/api/v3/series')
          .single;
      expect(add.json, containsPair('tvdbId', WorldTitles.agent327.tvdbId));
      expect(add.json, containsPair('seriesType', 'standard'));
      expect(
        add.json,
        containsPair('rootFolderPath', '/mnt/tank/media/series'),
      );
      expect(
        (add.json as Map)['addOptions'],
        containsPair('monitor', 'future'),
      );
      expect(
        (add.json as Map)['addOptions'],
        containsPair('searchForMissingEpisodes', true),
      );
      expect(find.textContaining('Added to Sonarr'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('without a media server of its own, Seerr\'s link opens it, '
        'and the row says which seasons are there', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p3,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );

      expect(
        find.widgetWithText(FilledButton, 'Watch on Jellyfin'),
        findsOneWidget,
      );
      expect(
        find.text('S1 available\u00A0· S2 partly available'),
        findsOneWidget,
      );
      expect(find.text('Add Jellyfin to Cupola'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('says where it streams in the region set', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 5200,
      );

      expect(find.text('Where to watch'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Stream: Netflix, Prime Video'),
        findsOneWidget,
      );
      // A series has no release dates of its own kinds.
      expect(find.text('Release dates'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('the requester asks for the seasons nobody has asked for', (
      tester,
    ) async {
      // Night Shift: the first season on the server, the third asked for by
      // Luca, the second by nobody.
      final harness = await _pump(
        tester,
        Profiles.p2,
        WorldTitles.nightShift,
        key: MediaKey.tv(WorldTitles.nightShift.tmdbId),
      );

      expect(find.text('Season 2 is not requested yet.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Request'));
      await _answer(tester);
      expect(find.text('Request Night Shift'), findsOneWidget);
      // One season left to ask for, and it says which.
      expect(find.widgetWithText(FilterChip, 'Season 2'), findsOneWidget);
      expect(find.byType(FilterChip), findsOneWidget);

      await tester.tap(find.text('Submit request'));
      await _answer(tester);
      final sent =
          harness.network
                  .requestsTo(WorldIds.seerr)
                  .where(
                    (r) =>
                        r.method == 'POST' && r.uri.path == '/api/v1/request',
                  )
                  .single
                  .json
              as Map;
      expect(sent['mediaType'], 'tv');
      expect(sent['mediaId'], WorldTitles.nightShift.tmdbId);
      expect(sent['seasons'], [2]);

      await harness.unmount(tester);
    });

    testWidgets('a season asked for is answered from the page, and Sonarr is '
        'read again', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.nightShift,
        key: MediaKey.tv(WorldTitles.nightShift.tmdbId),
        height: 3600,
      );

      expect(
        find.text('${WorldPeople.luca} asked for Season 3'),
        findsOneWidget,
      );
      final sonarrReads = harness.network.requestsTo(WorldIds.sonarr).length;
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await _answer(tester);
      await tester.tap(find.text('Approve request'));
      await _answer(tester);
      final approve = harness.network
          .requestsTo(WorldIds.seerr)
          .where((r) => r.method == 'POST')
          .single;
      expect(approve.uri.path, '/api/v1/request/8/approve');
      expect(
        harness.network.requestsTo(WorldIds.sonarr).length,
        greaterThan(sonarrReads),
      );

      await harness.unmount(tester);
    });

    testWidgets('graphs its episodes from TMDB\'s votes, and opens the best', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.cosmosLaundromat,
        key: cosmos,
        height: 3600,
      );

      expect(find.text('S1\u00A0· 7.8'), findsOneWidget);
      expect(find.text('S2\u00A0· 8.2'), findsOneWidget);
      // One cell width for every season, measured on the longest: a season
      // of few episodes is not drawn in fatter bars than its neighbour.
      final widths = {
        for (final cell
            in find
                .byWidgetPredicate((w) => w.runtimeType.toString() == '_Cell')
                .evaluate())
          (cell.renderObject! as RenderBox).size.width,
      };
      expect(widths, hasLength(1));
      expect(
        find.bySemanticsLabel(
          'Episodes graph. Best: S2\u00A0E6, 8.9. Season 2 is the stronger one',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Episodes graph'));
      await tester.tap(find.text('Episodes graph'));
      await _answer(tester);
      expect(find.text('Votes from TMDB, per episode.'), findsOneWidget);
      expect(find.text('S2\u00A0E6\u00A0· The Seventh Cycle'), findsOneWidget);
      expect(find.text('31 votes\u00A0· Missing'), findsOneWidget);
      expect(
        find.textContaining(
          'Season 2 is the stronger one\u00A0· 8.2 against 7.8\u00A0· 4 of its '
          'episodes have few votes',
        ),
        findsOneWidget,
      );

      // The best opens its own sheet.
      await tester.tap(find.text('S2\u00A0E6\u00A0· The Seventh Cycle'));
      await _answer(tester);
      expect(find.textContaining('Season 2\u00A0· Episode 6'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  group('as a real screen shows it', () {
    testWidgets('the quiet actions keep every word: on a phone their glyphs '
        'go before Watchlist is cut', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.tearsOfSteel,
      );

      final word = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.widgetWithText(OutlinedButton, 'Watchlist'),
          matching: find.text('Watchlist'),
        ),
      );
      expect(word.didExceedMaxLines, isFalse);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('with room to spare the glyphs stay', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.tearsOfSteel,
        width: 560,
      );

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('the scores share one line, whatever their labels take', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = await _pump(
        tester,
        Profiles.p1,
        WorldTitles.tearsOfSteel,
      );

      // The figure is the first line of the column its label closes.
      double figureTop(String source) => tester
          .getTopLeft(
            find
                .descendant(
                  of: find
                      .ancestor(
                        of: find.text(source),
                        matching: find.byType(Column),
                      )
                      .first,
                  matching: find.byType(Text),
                )
                .first,
          )
          .dy;
      // `Rotten Tomatoes` takes two lines at 390; its figure does not drop.
      expect(figureTop('Rotten Tomatoes'), figureTop('TMDB'));

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a Bazarr that does not follow the movie draws no row, and '
        'the heading does not count it', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network
        ..followFakeTime(tester.binding)
        ..on(
          WorldIds.bazarr,
          'GET',
          '/api/movies',
          (_) => NetworkReply.json({'data': <Object?>[], 'total': 0}),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: MediaPage(
              mediaKey: MediaKey.movie(WorldTitles.tearsOfSteel.tmdbId),
            ),
          ),
        ),
      );
      await _answer(tester);

      expect(find.bySemanticsLabel(RegExp(r'^Bazarr\.')), findsNothing);
      final drawn = <String>{
        for (final name in ['Jellyfin', 'Plex', 'Radarr', 'Seerr', 'Bazarr'])
          if (find.bySemanticsLabel(RegExp('^$name[ .]')).evaluate().isNotEmpty)
            name,
      };
      expect(drawn, isNot(contains('Bazarr')));
      expect(find.text('${drawn.length} services'), findsOneWidget);

      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a season track that scrolls opens on the chosen season, '
        'and leaves the page where it was', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final page = ScrollController();
      addTearDown(page.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: ListView(
              controller: page,
              padding: const EdgeInsets.all(20),
              children: [
                // In view, below the middle: a reveal that moved the page
                // would scroll it to centre the track.
                const SizedBox(height: 700),
                MediaEpisodes(
                  seasons: [
                    for (var number = 1; number <= 6; number++)
                      MediaSeason(number, const []),
                  ],
                  initialSeason: 6,
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(page.offset, 0, reason: 'the page did not move');
      final chosen = tester.getRect(find.text('Season 6'));
      expect(chosen.left, greaterThanOrEqualTo(0));
      expect(chosen.right, lessThanOrEqualTo(390));
    });

    test('a running time and a season count keep their words on their line', () {
      const movie = MediaIdentity(
        title: 'Fight Club',
        year: '1999',
        runtime: '2 h 19 min',
        directors: ['David Fincher'],
        genres: ['Drama'],
      );
      expect(
        movie.metaLine,
        'David Fincher\u00A0· 1999\u00A0· 2\u00A0h\u00A019\u00A0min\u00A0· Drama',
      );
      const series = MediaIdentity(
        title: 'Breaking Bad',
        series: (span: '2008–2013', seasons: 5),
      );
      expect(series.metaLine, 'Series\u00A0· 2008–2013\u00A0· 5\u00A0seasons');
    });
  });
}
