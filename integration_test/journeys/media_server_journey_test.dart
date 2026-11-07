/// The media servers, Now playing and Tracearr: S-01, S-02, S-06, S-03 and S-09,
/// and a journey of Tracearr's own.
///
/// The world: the Jellyfin, the Emby and the Plex of L8, with Films, Series and
/// Music on the same folders, a non-admin `cupola-viewer`, a watched movie and
/// an episode in Continue watching, and Plex's own on deck. Sessions are
/// opened by the lab's own players (`jellyfin_play.py --listen`, and
/// `emby_play.py --listen`), which are the only clients that obey the app's
/// remote pause and stop.
///
/// Jellyfin and Emby share their four journeys, written once over [_Server]:
/// the two servers draw the same screens and answer a few routes differently,
/// and the differences live in that one class (the base path, the header the
/// key travels in, the routes the app opens). A third server of that family
/// would be one more value of it.
///
/// What each journey proves, in the app's own words:
///
/// - **S-01**: the libraries the server holds are the ones the app draws, and a
///   title opens on its own page.
/// - **S-02**: the household users, the devices and the scheduled tasks the
///   server holds are the rows the tabs draw; the fourth tab (`Activity`) is
///   Now playing, not a log, and it draws the section.
/// - **S-06**: Plex's libraries, on deck, devices and playlists are drawn.
/// - **S-03**: a playback the server knows is a card with the app's controls;
///   pause, resume, message and stop are the app's own commands, and the
///   server's session changes with them.
/// - **S-09**: Now playing draws one and then two playbacks on the Home and on
///   the Jellyfin overview, and goes back to its idle line when they stop.
///
/// - **Tracearr** (no catalogue row yet, so no id): Tracearr, watching the Emby, draws what two playbacks make: two
///   streams in Live, and the violation of the rule that allows one in
///   Violations, opened to the sentence that says how many there were.
///
/// S-04 (`Resume in Jellyfin`, a hand-off to the platform's player), S-05 (the
/// client has no watch/task write), S-07 (Plex's stop needs Plex Pass) and S-08
/// (the Plex client has no playlist write) stay agent steps or impossibilities,
/// as the catalogue says.
///
/// **S-03 and S-09 need their playbacks opened on the host.** The app runs on
/// the iOS simulator, where starting a process is forbidden, so the lab's own
/// player is started outside the journey and this file only reads it and
/// commands it: `test/e2e/testlab/journey_sessions.py S-03` (or `S-09`, and
/// `--server emby` for Emby's) starts the right devices, runs this file, and
/// ends them on the way out. The test names are what the wrapper selects them
/// by, so the Jellyfin and the Emby ones differ in their wording.
///
/// **The Tracearr journey opens its own playbacks.** It asks the lab's control API to apply the
/// `tracearr-streams` scenario (two devices of the household member on the
/// Emby, which Tracearr watches and rules) and to take it down when the test
/// ends, so it needs no wrapper: the lab must be up with its control API.
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'testlab_journey_harness.dart';

/// A media server of the MediaBrowser family the journeys drive, and what
/// differs between its members: where its API sits, how its key travels, the
/// routes the app opens and the words the test names carry.
enum _Server {
  jellyfin(
    service: ServiceKey.jellyfin,
    title: 'Jellyfin',
    tokenName: 'CUPOLA_TESTLAB_JELLYFIN_TOKEN',
    basePath: '',
    overview: ServiceRoutes.jellyfinOverview,
    libraries: ServiceRoutes.jellyfinLibraries,
    users: ServiceRoutes.jellyfinUsers,
    devices: ServiceRoutes.jellyfinDevices,
    tasks: ServiceRoutes.jellyfinTasks,
    activity: ServiceRoutes.jellyfinActivity,
    s01: 'S-01 · the Jellyfin libraries and a title',
    s02: 'S-02 · the household users, devices and tasks Jellyfin holds',
    s03: 'S-03 · pause, resume, message and stop a Jellyfin playback',
    s09: 'S-09 · Now playing draws one and two playbacks, then its idle line',
  ),
  emby(
    service: ServiceKey.emby,
    title: 'Emby',
    tokenName: 'CUPOLA_TESTLAB_EMBY_TOKEN',
    basePath: '/emby',
    overview: ServiceRoutes.embyOverview,
    libraries: ServiceRoutes.embyLibraries,
    users: ServiceRoutes.embyUsers,
    devices: ServiceRoutes.embyDevices,
    tasks: ServiceRoutes.embyTasks,
    activity: ServiceRoutes.embyActivity,
    s01: 'S-01 · the Emby libraries and a title',
    s02: 'S-02 · the household users, devices and tasks Emby holds',
    s03: 'S-03 · pause, resume, message and stop an Emby playback',
    s09:
        'S-09 · Now playing draws one and two Emby playbacks, then its idle line',
  );

  const _Server({
    required this.service,
    required this.title,
    required this.tokenName,
    required this.basePath,
    required this.overview,
    required this.libraries,
    required this.users,
    required this.devices,
    required this.tasks,
    required this.activity,
    required this.s01,
    required this.s02,
    required this.s03,
    required this.s09,
  });

  final ServiceKey service;

  /// The name the app draws for the server, and the failure messages use.
  final String title;

  /// The lab's credential name for what a reading authenticates with.
  final String tokenName;

  /// Where the API lives under the address: Emby answers under `/emby`.
  final String basePath;

  /// The tab roots the app opens for the server.
  final String overview;
  final String libraries;
  final String users;
  final String devices;
  final String tasks;
  final String activity;

  /// The journey names. They are what `journey_sessions.py` selects a server's
  /// session journeys by, so each is distinctive.
  final String s01;
  final String s02;
  final String s03;
  final String s09;

  /// The route of one title's page.
  String item(String id) => switch (this) {
    _Server.jellyfin => ServiceRoutes.jellyfinItem(id),
    _Server.emby => ServiceRoutes.embyItem(id),
  };
}

/// The title the lab's library holds first, by the kind the server names.
Future<String> _movieTitle(LabApp app, _Server server) async {
  final items = await _media(
    app,
    server,
    '/Items?IncludeItemTypes=Movie&Recursive=true&Limit=1',
  );
  return _firstName(server, items, 'movie');
}

/// The series the lab's first episode belongs to.
///
/// An episode's row draws the show and its place in it ("Breaking Bad · S1 E1"),
/// never the episode's own file name, so this is what a journey can look for.
Future<String> _episodeTitle(LabApp app, _Server server) async {
  final items = await _media(
    app,
    server,
    '/Items?IncludeItemTypes=Episode&Recursive=true&Limit=1',
  );
  final rows = items['Items'] as List? ?? const [];
  if (rows.isEmpty) fail('the ${server.title} library holds no episode');
  final episode = rows.first as Map;
  final series = episode['SeriesName'] as String?;
  return (series == null || series.isEmpty)
      ? episode['Name'] as String
      : series;
}

String _firstName(_Server server, Map items, String kind) {
  final rows = items['Items'] as List? ?? const [];
  if (rows.isEmpty) fail('the ${server.title} library holds no $kind');
  return (rows.first as Map)['Name'] as String;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final server in _Server.values) {
    _mediaBrowserJourneys(binding, server);
  }

  testWidgets('S-06 · the Plex libraries, on deck, devices and playlists', (
    tester,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final app = await LabApp.asOperator(
      tester,
      services: const {ServiceKey.plex},
    );

    final sections = await _plexContainer(app, '/library/sections');
    final titles = [
      for (final directory in sections['Directory'] as List? ?? const [])
        if ((directory as Map)['title'] case final String title) title,
    ];
    expect(titles, isNotEmpty, reason: 'the lab seeded Plex libraries');

    await app.go(tester, ServiceRoutes.plexLibraries);
    for (final title in titles) {
      await app.surface.see(title);
    }

    final onDeck = await _plexContainer(app, '/library/onDeck');
    final deck = (onDeck['Metadata'] as List? ?? const []);
    await app.go(tester, ServiceRoutes.plexOnDeck);
    await app.surface.see('On deck');
    if (deck.isNotEmpty) {
      await app.surface.see((deck.first as Map)['title'] as String);
    }

    await app.go(tester, ServiceRoutes.plexDevices);
    await app.surface.see('Devices');
    await app.go(tester, ServiceRoutes.plexPlaylists);
    await app.surface.see('Playlists');
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('Tracearr draws two live streams and the violation they raise', (
    tester,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final lab = Lab.load();
    await lab.command(['scenario', 'apply', 'tracearr-streams']);
    addTearDown(
      () => lab.command(['scenario', 'teardown', 'tracearr-streams']),
    );
    final app = await LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.tracearr, ServiceKey.emby},
    );

    // What Tracearr lists, read straight to it: the two titles the scenario
    // plays, and who plays them.
    final live = await _tracearr(app, '/api/v2/public/streams');
    final rows = (live['data'] as List).cast<Map>();
    final titles = [
      for (final row in rows)
        if (row['media_title'] case final String title) title,
    ];
    expect(
      titles,
      containsAll(['Big Buck Bunny', 'The Matrix']),
      reason: 'the scenario plays two titles',
    );

    await app.go(tester, ServiceRoutes.tracearrLive);
    await app.surface.seePart('2 streams');
    for (final title in titles) {
      await app.surface.seePart(title);
    }

    // The rule allows one stream: the second one is a violation, and its page
    // says so in numbers, never in an address.
    await app.go(tester, ServiceRoutes.tracearrViolations);
    await app.surface.see('Too many streams at once');
    await app.tapIn(tester, find.text('Too many streams at once').first);
    // The page lays the reading out as what it saw: the count, and the limit.
    await app.surface.see('What it saw');
    await app.surface.see('2 streams at once');
    await app.surface.see('The limit is 1');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// One reading of Tracearr's public API, straight to it and not through the
/// fault layer, with the key the lab issued.
Future<Map> _tracearr(LabApp app, String path) async {
  final key = app.credentials.require('CUPOLA_TESTLAB_TRACEARR_KEY');
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('${LabEndpoints.directUrlOf(ServiceKey.tracearr)}$path'),
    );
    request.headers.set('Authorization', 'Bearer $key');
    request.headers.set('Accept', 'application/json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      fail('Tracearr $path answered ${response.statusCode}: $body');
    }
    return jsonDecode(body) as Map;
  } finally {
    client.close(force: true);
  }
}

/// The journeys Jellyfin and Emby share: S-01, S-02, S-03 and S-09, for one
/// [server].
void _mediaBrowserJourneys(
  IntegrationTestWidgetsFlutterBinding binding,
  _Server server,
) {
  testWidgets(server.s01, (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final app = await LabApp.asOperator(tester, services: {server.service});

    final folders = await _mediaList(app, server, '/Library/VirtualFolders');
    final names = [
      for (final folder in folders)
        if ((folder as Map)['Name'] case final String name) name,
    ];
    expect(
      names,
      containsAll(['Films', 'Series', 'Music']),
      reason: 'the lab seeded three libraries',
    );

    await app.go(tester, server.libraries);
    await app.surface.see('Libraries');
    for (final name in names) {
      await app.surface.see(name);
    }

    // The title's own page, opened on its own route: the libraries list
    // opens this page for the same item.
    final items = await _media(
      app,
      server,
      '/Items?IncludeItemTypes=Movie&Recursive=true&Limit=1',
    );
    final film = (items['Items'] as List).first as Map;
    await app.go(tester, server.item(film['Id'] as String));
    await app.surface.see(film['Name'] as String);
    await app.surface.seePart(server.title);
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets(server.s02, (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final app = await LabApp.asOperator(tester, services: {server.service});

    final users = await _mediaList(app, server, '/Users');
    final viewer = users
        .cast<Map>()
        .map((user) => user['Name'])
        .whereType<String>()
        .where((name) => name == 'cupola-viewer');
    expect(viewer, isNotEmpty, reason: 'the lab seeded the viewer account');

    await app.go(tester, server.users);
    await app.surface.see('Users');
    await app.surface.see('${users.length} users');
    await _scrollUntil(tester, 'cupola-viewer');
    await app.surface.see('cupola-viewer');

    final devices = await _mediaList(app, server, '/Devices');
    final deviceNames = [
      for (final device in devices)
        if ((device as Map)['Name'] case final String name)
          if (name.trim().isNotEmpty) name,
    ];
    await app.go(tester, server.devices);
    await app.surface.see('Devices');
    await app.surface.see('${devices.length} devices');
    expect(
      deviceNames.where(app.surface.draws),
      isNotEmpty,
      reason:
          'the Devices tab draws none of the names the server holds: '
          '${app.surface.texts().join(' | ')}',
    );

    final tasks = await _mediaList(app, server, '/ScheduledTasks');
    final taskNames = [
      for (final task in tasks)
        if ((task as Map)['Name'] case final String name)
          if (name.trim().isNotEmpty) name,
    ];
    await app.go(tester, server.tasks);
    await app.surface.see('Tasks');
    expect(
      taskNames.where(app.surface.draws),
      isNotEmpty,
      reason:
          'the Tasks tab draws none of the names the server holds: '
          '${app.surface.texts().join(' | ')}',
    );

    // The app's fourth tab is the server's live sessions read: its own
    // words, not a log's.
    await app.go(tester, server.activity);
    await app.surface.see('Activity');
    await app.surface.see('Now playing');
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets(server.s03, (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final app = await LabApp.asOperator(tester, services: {server.service});
    final device = 'cupola-s03';
    final film = await _movieTitle(app, server);
    await _waitForSession(tester, app, server, device);
    await app.go(tester, server.overview);
    await app.surface.see('Now playing');
    await app.surface.seePart(film);

    // The controls sit at the card's edge, under the bottom bar at this
    // height: lift the page before touching them.
    await tester.dragFrom(const Offset(200, 400), const Offset(0, -240));
    await settle(tester, const Duration(milliseconds: 800));

    // Pause: the app's command, and the server's own state behind it.
    await tester.tap(find.byTooltip('Pause this playback'));
    await app.surface.waitFor(find.byTooltip('Resume this playback'));
    expect(
      await _isPaused(app, server, device),
      isTrue,
      reason: 'the server did not pause the session',
    );

    await tester.tap(find.byTooltip('Resume this playback'));
    await app.surface.waitFor(find.byTooltip('Pause this playback'));
    expect(
      await _isPaused(app, server, device),
      isFalse,
      reason: 'the server did not resume the session',
    );

    // A message is the app's prompt, then the server's own channel.
    await tester.tap(find.byTooltip('Send a message to this player'));
    await app.surface.see('Send');
    await tester.enterText(
      find.byType(TextField).last,
      'Dinner in ten minutes',
    );
    await settle(tester, const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await app.surface.seePart('Message sent to');

    // Stop: the question, the answer, and the session gone from the server.
    await tester.tap(find.byTooltip('Stop this playback'));
    await app.surface.see('Stop playback?');
    await tester.tap(find.widgetWithText(FilledButton, 'Stop playback'));
    await _waitForNoSession(tester, app, server, device);
    await app.go(tester, server.overview);
    await app.surface.see('Nobody is watching right now');
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets(server.s09, (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final app = await LabApp.asOperator(tester, services: {server.service});
    final first = 'cupola-s09a';
    final second = 'cupola-s09b';
    final film = await _movieTitle(app, server);
    final episode = await _episodeTitle(app, server);
    await _waitForSession(tester, app, server, first);

    // One session, on the room's page and on the Home.
    await app.go(tester, server.overview);
    await app.surface.see('Now playing');
    await app.surface.seePart(film);
    await app.go(tester, ServiceRoutes.home);
    await app.surface.seePart(film);

    // A second one: both are on the room's page and on the Home.
    await _waitForSession(tester, app, server, second);
    await app.go(tester, server.overview);
    await app.surface.seePart(film);
    await app.surface.seePart(episode);
    await app.go(tester, ServiceRoutes.home);
    await app.surface.seePart(film);
    await app.surface.seePart(episode);

    // Both stop: the room says nobody is watching.
    await _stopOnServer(app, server, first);
    await _stopOnServer(app, server, second);
    await _waitForNoSession(tester, app, server, first);
    await _waitForNoSession(tester, app, server, second);
    await app.go(tester, server.overview);
    await app.surface.see('Nobody is watching right now');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Ends the session on [device] on the server, the way the app's Stop does.
Future<void> _stopOnServer(LabApp app, _Server server, String device) async {
  final session = await _sessionOf(app, server, device);
  final id = session?['Id'] as String?;
  if (id == null) return;
  await _mediaRequest(
    app,
    server,
    '/Sessions/$id/Playing/Stop',
    method: 'POST',
  );
}

Future<void> _waitForSession(
  WidgetTester tester,
  LabApp app,
  _Server server,
  String device,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    if (await _sessionOf(app, server, device) != null) return;
    await settle(tester, const Duration(milliseconds: 500));
  }
  fail(
    'the ${server.title} server never saw the session on $device. Start it '
    'with "test/e2e/testlab/journey_sessions.py S-03" (or "S-09"), adding '
    '"--server emby" for Emby.',
  );
}

Future<void> _waitForNoSession(
  WidgetTester tester,
  LabApp app,
  _Server server,
  String device,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(deadline)) {
    if (await _sessionOf(app, server, device) == null) return;
    await settle(tester, const Duration(milliseconds: 500));
  }
  fail('the ${server.title} server still holds the session on $device');
}

Future<bool> _isPaused(LabApp app, _Server server, String device) async {
  final session = await _sessionOf(app, server, device);
  final state = session?['PlayState'] as Map?;
  return state?['IsPaused'] == true;
}

Future<Map?> _sessionOf(LabApp app, _Server server, String device) async {
  final sessions = await _mediaList(app, server, '/Sessions');
  final slug = device
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  for (final entry in sessions) {
    final session = entry as Map;
    // A stopped device stays listed for a while, idle: Emby keeps its session
    // with no `NowPlayingItem`. Only a playback is the session we look for.
    if (session['NowPlayingItem'] == null) continue;
    // `--device` is the DeviceName the helper presents; the DeviceId is its
    // namespaced slug, so both identify the same session.
    final name = session['DeviceName'] as String?;
    final id = session['DeviceId'] as String?;
    if (name == device || id == 'cupola-play-$slug') return session;
  }
  return null;
}

Future<List> _mediaList(LabApp app, _Server server, String path) async {
  final answer = await _mediaRequest(app, server, path);
  if (answer is List) return answer;
  // `/Devices` answers with the server's paged container, not a bare list.
  if (answer is Map && answer['Items'] is List) return answer['Items'] as List;
  return const [];
}

Future<Map> _media(LabApp app, _Server server, String path) async {
  final answer = await _mediaRequest(app, server, path);
  if (answer is Map) return answer;
  fail(
    '${server.title} answered $path with ${answer.runtimeType}, not an object',
  );
}

/// One reading of the server, straight to it and not through the fault layer.
///
/// Jellyfin takes its token in the `Authorization` header, with a client
/// identity; Emby reads the key from `X-Emby-Token` and sits under `/emby`.
Future<Object?> _mediaRequest(
  LabApp app,
  _Server server,
  String path, {
  String method = 'GET',
}) async {
  final token = app.credentials.require(server.tokenName);
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse(
        '${LabEndpoints.directUrlOf(server.service)}${server.basePath}$path',
      ),
    );
    switch (server) {
      case _Server.jellyfin:
        request.headers.set(
          'Authorization',
          'MediaBrowser Client="Cupola", Device="journey", '
              'DeviceId="cupola-journey-reader", Version="test", '
              'Token="$token"',
        );
      case _Server.emby:
        request.headers.set('X-Emby-Token', token);
    }
    request.headers.set('Accept', 'application/json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      fail('${server.title} $path answered ${response.statusCode}: $body');
    }
    return body.isEmpty ? null : jsonDecode(body);
  } finally {
    client.close(force: true);
  }
}

Future<Map> _plexContainer(LabApp app, String path) async {
  final token = app.credentials.require('CUPOLA_TESTLAB_PLEX_TOKEN');
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('${LabEndpoints.directUrlOf(ServiceKey.plex)}$path'),
    );
    request.headers.set('X-Plex-Token', token);
    request.headers.set('Accept', 'application/json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      fail('Plex $path answered ${response.statusCode}: $body');
    }
    final json = jsonDecode(body) as Map;
    return (json['MediaContainer'] as Map?) ?? json;
  } finally {
    client.close(force: true);
  }
}

/// Scrolls the page's own list until [text] is on the screen.
Future<void> _scrollUntil(WidgetTester tester, String text) async {
  final target = find.text(text);
  if (target.evaluate().isNotEmpty) return;
  // A card that is still arriving is not a reason to drag: give the page the
  // moment its provider needs, then look again.
  await settle(tester, const Duration(seconds: 2));
  if (target.evaluate().isNotEmpty) return;
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;
  try {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: scrollables.last,
      maxScrolls: 40,
    );
  } on StateError {
    fail('The page never drew "$text". It drew: ${_texts(tester)}');
  }
  await settle(tester, const Duration(milliseconds: 600));
}

/// Every line the surface draws, for a failure that has to say what it saw.
String _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? '')
    .where((data) => data.isNotEmpty)
    .join(' | ');
