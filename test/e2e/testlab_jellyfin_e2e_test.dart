@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';

import '../test_helpers/settings_scope.dart';

/// Jellyfin in the macOS lab, through Cupola's own client: the flow catalogue's
/// S-01 to S-05, plus the two-session state S-09 reads.
///
/// The library and the watch states come from the `jellyfin-media` scenario:
///
/// ~~~bash
/// python3 test/e2e/testlab/testlab.py scenario apply jellyfin-media
/// flutter test --tags e2e --run-skipped test/e2e/testlab_jellyfin_e2e_test.dart
/// ~~~
///
/// A playback session is not something this file can fake: it is opened by
/// `test/e2e/testlab/jellyfin_play.py`, a real Jellyfin client that reports
/// `/Sessions/Playing` and holds the WebSocket that carries the server's
/// remote control. The app's pause and stop are then measured by re-reading
/// `/Sessions`, which is the only thing that proves a command acted instead of
/// being merely dispatched (a 204 means "relayed", not "paused").
///
/// The S-03 session plays the watched film on purpose, and never the episode
/// with the resume point: Jellyfin writes a new position on every stop, so a
/// session on the episode would move the 30% the S-04 fixture asserts. A film
/// that is already watched keeps its played flag at any position.
void main() {
  late _Lab lab;
  late JellyfinClient client;
  late JellyfinClient memberClient;
  late ProviderContainer memberContainer;
  late String viewerId;

  setUpAll(() async {
    lab = _Lab.load();
    await lab.waitForJellyfin();

    final probe = JellyfinClient(
      baseUrl: _Lab.jellyfinUrl,
      apiKey: lab.adminToken,
    );
    try {
      final users = await probe.getUsers();
      final viewer = users.where((user) => user.name == lab.viewerName);
      expect(
        viewer,
        isNotEmpty,
        reason: 'the lab has no Jellyfin user named ${lab.viewerName}',
      );
      viewerId = viewer.first.id;
    } finally {
      probe.close();
    }

    final adminContainer = await lab.container(
      token: lab.adminToken,
      viewerId: viewerId,
    );
    addTearDown(adminContainer.dispose);
    client = adminContainer.read(jellyfinClientProvider);

    final member = await lab.signInViewer();
    memberContainer = await lab.container(
      token: member.token,
      viewerId: viewerId,
    );
    addTearDown(memberContainer.dispose);
    memberClient = memberContainer.read(jellyfinClientProvider);
  });

  group('S-01 libraries and a title page', () {
    test('three libraries stand on the folders the lab mounts', () async {
      final libraries = await client.getLibraries();
      final byName = {for (final library in libraries) library.name: library};

      expect(byName.keys, containsAll(const ['Films', 'Series', 'Music']));
      expect(byName['Films']!.kind, StreamLibraryKind.movies);
      expect(byName['Series']!.kind, StreamLibraryKind.shows);
      expect(byName['Music']!.kind, StreamLibraryKind.music);

      for (final name in const ['Films', 'Series', 'Music']) {
        expect(
          byName[name]!.id,
          isNotEmpty,
          reason: '$name has an id to browse by',
        );
      }

      // The count is the library's own unit, so a TV library answers in shows
      // and not in the episodes recursive browsing would sweep up.
      expect(await client.getLibraryItemCount(byName['Films']!.id), 4);
      expect(await client.getLibraryItemCount(byName['Series']!.id), 1);
      expect(await client.getLibraryItemCount(byName['Music']!.id), 1);
    });

    test('a movie opens on its own page, with a runtime and an id', () async {
      final libraries = await client.getLibraries();
      final films = libraries.singleWhere((library) => library.name == 'Films');
      final page = await client.getLibraryPage(
        libraryId: films.id,
        sort: StreamLibrarySort.name,
        limit: 50,
      );

      expect(page.failed, isFalse, reason: 'the Name-ordered page answered');
      final movie = page.items.singleWhere(
        (item) => item.title == 'Big Buck Bunny',
      );
      expect(movie.kind, StreamItemKind.movie);

      final detail = await client.getItem(movie.id);
      expect(detail, isNotNull, reason: 'the title page has a server item');
      expect(detail!.id, movie.id);
      expect(detail.title, 'Big Buck Bunny');
      expect(detail.kind, StreamItemKind.movie);
      expect(detail.runtimeMs, greaterThan(60000));
    });

    test('the series and the album are browsable the same way', () async {
      final libraries = await client.getLibraries();
      final series = libraries.singleWhere(
        (library) => library.name == 'Series',
      );
      final music = libraries.singleWhere((library) => library.name == 'Music');

      final shows = await client.getLibraryPage(
        libraryId: series.id,
        sort: StreamLibrarySort.name,
        limit: 50,
      );
      expect(shows.failed, isFalse);
      final show = shows.items.singleWhere(
        (item) => item.title == 'Breaking Bad',
      );
      expect(show.kind, StreamItemKind.series);

      final episodes = await client.getEpisodes(show.id);
      expect(episodes.length, 2);
      // By number, not by title: a Jellyfin that cannot reach its metadata
      // providers names episodes from the file, so the name is a cache of the
      // lab and the season and the number are the facts.
      expect(
        episodes.where(
          (episode) => episode.seasonNumber == 1 && episode.episodeNumber == 2,
        ),
        hasLength(1),
      );

      final albums = await client.getLibraryPage(
        libraryId: music.id,
        sort: StreamLibrarySort.name,
        limit: 50,
      );
      expect(albums.failed, isFalse);
      final album = albums.items.singleWhere(
        (item) => item.title == 'Discovery',
      );
      expect(album.kind, StreamItemKind.album);

      final tracks = await client.getChildren(album.id);
      expect(tracks.length, 14);
      expect(tracks.map((track) => track.title), contains('One More Time'));
    });
  });

  group('S-02 household, devices, tasks and activity', () {
    test(
      'the administrator reads users, devices and scheduled tasks',
      () async {
        expect(
          await client.getCredentialKind(),
          JellyfinCredentialKind.administrator,
        );

        final users = await client.getUsers();
        final byName = {for (final user in users) user.name: user};
        expect(byName.keys, containsAll([lab.viewerName, 'cupola-admin']));
        expect(byName['cupola-admin']!.isAdministrator, isTrue);
        expect(byName[lab.viewerName]!.isAdministrator, isFalse);
        expect(byName[lab.viewerName]!.isDisabled, isFalse);

        // Devices is a paged envelope, and the envelope has to come off before
        // the rows map: an empty list here would hide every client that ever
        // signed in.
        final devices = await client.getDevices();
        expect(devices, isNotEmpty);
        expect(devices.every((device) => device.name.isNotEmpty), isTrue);
        expect(
          devices.map((device) => device.appName),
          contains('Cupola'),
          reason: 'the bootstrap signed in as Cupola',
        );

        final tasks = await client.getScheduledTasks();
        expect(tasks, isNotEmpty);
        expect(
          tasks.every((task) => task.id.isNotEmpty && task.name.isNotEmpty),
          isTrue,
        );
        expect(
          tasks.map((task) => task.name),
          contains('Scan Media Library'),
          reason: 'the job a library scan queues is in the list',
        );
        expect(
          tasks.any((task) => task.lastStatus == 'Completed'),
          isTrue,
          reason: 'a job has run in this lab',
        );
      },
    );

    test(
      'activity is the live session list the client already reads',
      () async {
        final sessions = await client.getSessions();
        expect(sessions, isA<List<StreamSession>>());
        // Every row the board draws is an item somebody is playing: a connected
        // client with nothing playing is not activity.
        for (final session in sessions) {
          expect(session.id, isNotEmpty);
          expect(session.title, isNotEmpty);
          expect(session.deviceLabel, isNotEmpty);
        }
      },
    );

    test(
      'a household member token holds its own view and loses the rest',
      () async {
        expect(
          await memberClient.getCredentialKind(),
          JellyfinCredentialKind.user,
        );

        await memberContainer.read(jellyfinCredentialKindProvider.future);
        expect(
          memberContainer.read(jellyfinLacksAdministratorProvider),
          isTrue,
        );

        // The elevated reads are refused as a permission, never as an empty
        // list: the tabs are withheld, so no surface claims "no devices".
        final refused = isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status',
          403,
        );
        await expectLater(memberClient.getLibraries(), throwsA(refused));
        await expectLater(memberClient.getDevices(), throwsA(refused));
        await expectLater(memberClient.getScheduledTasks(), throwsA(refused));

        // Jellyfin 12 answers `/Users` to a household member, unlike the 10.x the
        // client's comment was written against. The tab is still withheld,
        // because `jellyfinLacksAdministratorProvider` decides it by policy and
        // not by asking whether the call would happen to succeed.
        final users = await memberClient.getUsers();
        expect(users.map((user) => user.name), contains(lab.viewerName));

        expect(
          (await memberClient.getViewers()).map((viewer) => viewer.name),
          contains(lab.viewerName),
        );
        expect(await memberClient.getSessions(), isA<List<StreamSession>>());
      },
    );
  });

  group('S-03 pause and stop a real session', () {
    test('the app pauses, resumes and stops a viewer\'s playback', () async {
      final helper = _PlayHelper(lab, device: 'e2e-iphone');
      addTearDown(helper.dispose);
      await helper.start(title: 'Big Buck Bunny', user: 'viewer');

      final session = await _waitForSession(client, 'e2e-iphone');
      expect(session.userName, lab.viewerName);
      expect(session.title, 'Big Buck Bunny');
      expect(session.isPaused, isFalse);
      expect(session.playMethod, StreamPlayMethod.directPlay);
      expect(session.progress, isNotNull);

      // The socket, not just the session: a command sent before the client is
      // listening is answered 204 and lost.
      await _waitFor(
        () async => helper.output,
        (text) => text.contains('listening on'),
        what: 'the helper to hold its WebSocket',
      );

      // A pause is two facts: the server relays it over the client's
      // WebSocket, and the client answers with a paused report.
      await client.pauseSession(session.id);
      final paused = await _waitFor(
        () => _sessionOrNull(client, session.id),
        (row) => row != null && row.isPaused,
        what: 'the session to read paused',
      );
      expect(paused!.isPaused, isTrue);
      await _waitFor(
        () async => helper.output,
        (text) => text.contains('playstate Pause'),
        what: 'the client to report the pause',
      );

      await client.unpauseSession(session.id);
      final resumed = await _waitFor(
        () => _sessionOrNull(client, session.id),
        (row) => row != null && !row.isPaused,
        what: 'the session to read playing again',
      );
      expect(resumed!.isPaused, isFalse);
      await _waitFor(
        () async => helper.output,
        (text) => text.contains('playstate Unpause'),
        what: 'the client to report the resume',
      );

      await client.stopSession(session.id);
      await _waitFor(
        () => _sessionOrNull(client, session.id),
        (row) => row == null,
        what: 'the stopped session to leave the list',
      );
      await _waitFor(
        () async => helper.output,
        (text) => text.contains('playstate Stop'),
        what: 'the client to report the stop',
      );
    });

    test('the app sends a message the player receives', () async {
      final helper = _PlayHelper(lab, device: 'e2e-message');
      addTearDown(helper.dispose);
      await helper.start(title: 'Big Buck Bunny', user: 'viewer');

      final session = await _waitForSession(client, 'e2e-message');
      await _waitFor(
        () async => helper.output,
        (text) => text.contains('listening on'),
        what: 'the helper to hold its WebSocket',
      );

      await client.sendMessage(session.id, text: 'Cupola says hello');
      await _waitFor(
        () async => helper.output,
        (text) => text.contains('message: Cupola says hello'),
        what: 'the client to receive the message',
      );
    });

    test(
      'a stop on an id the server does not know surfaces as an error',
      () async {
        await expectLater(
          client.stopSession('00000000000000000000000000000000'),
          throwsA(isA<DioException>()),
        );
      },
    );
  });

  group('S-04 progress and watched', () {
    test(
      'continue watching carries the episode at a third of its length',
      () async {
        final rows = await client.getContinueWatching();
        final episode = rows.singleWhere(
          (item) =>
              item.kind == StreamItemKind.episode &&
              item.seasonNumber == 1 &&
              item.episodeNumber == 2,
        );

        expect(episode.isPlayed, isFalse);
        expect(episode.resumeOffsetMs, greaterThan(0));
        expect(episode.resumeProgress, closeTo(0.30, 0.05));
        expect(episode.seriesId, isNotNull);
      },
    );

    test('the watched film is recent and reads watched', () async {
      final watched = await client.getRecentlyWatched(limit: 10);
      expect(watched, isNotEmpty);
      final film = watched.singleWhere(
        (row) => row.item.title == 'Big Buck Bunny',
      );
      expect(film.item.kind, StreamItemKind.movie);
      expect(film.item.isPlayed, isTrue);
      expect(
        film.playedAt.isAfter(DateTime.now().subtract(const Duration(days: 1))),
        isTrue,
        reason: 'the fixture was watched in this lab, not years ago',
      );
    });

    test('the series reports the episodes it has not played', () async {
      final libraries = await client.getLibraries();
      final series = libraries.singleWhere(
        (library) => library.name == 'Series',
      );
      final page = await client.getLibraryPage(
        libraryId: series.id,
        sort: StreamLibrarySort.name,
        limit: 50,
      );
      final show = page.items.singleWhere(
        (item) => item.title == 'Breaking Bad',
      );
      final episodes = await client.getEpisodes(show.id);

      // The badge: neither episode is finished. A resume point is not a watched
      // episode, so the count is both of them.
      expect(episodes.length, 2);
      expect(show.unplayedChildCount, episodes.length);
      expect(
        episodes.where((episode) => episode.isPlayed),
        isEmpty,
        reason: 'the fixture is part-watched, not watched',
      );
    });
  });

  group('S-05 the contract is read-only', () {
    test('the client has no mark watched and no run task', () {
      // S-05 is declared X in the catalogue: the app offers no such action, and
      // there is no method here to call even if a screen wanted one. A dynamic
      // call is the one runtime proof of an absence in Dart.
      final dynamic writable = client;
      expect(() => writable.markWatched('any-id'), throwsNoSuchMethodError);
      expect(() => writable.setPlayed('any-id', true), throwsNoSuchMethodError);
      expect(
        () => writable.runScheduledTask('any-id'),
        throwsNoSuchMethodError,
      );
    });
  });

  group('S-09 two sessions', () {
    test(
      'two devices are two sessions, and a pause touches only one',
      () async {
        final livingRoom = _PlayHelper(lab, device: 'e2e-living-room');
        final tablet = _PlayHelper(lab, device: 'e2e-tablet');
        addTearDown(livingRoom.dispose);
        addTearDown(tablet.dispose);

        await livingRoom.start(title: 'Big Buck Bunny', user: 'viewer');
        final first = await _waitForSession(client, 'e2e-living-room');
        await tablet.start(title: 'One More Time', user: 'viewer');
        final second = await _waitForSession(client, 'e2e-tablet');

        expect(first.id, isNot(second.id));
        expect(first.deviceLabel, isNot(second.deviceLabel));
        expect(first.title, 'Big Buck Bunny');
        expect(second.title, 'One More Time');
        expect(first.userName, lab.viewerName);
        expect(second.userName, lab.viewerName);

        for (final helper in [livingRoom, tablet]) {
          await _waitFor(
            () async => helper.output,
            (text) => text.contains('listening on'),
            what: 'every helper to hold its WebSocket',
          );
        }

        await client.pauseSession(first.id);
        await _waitFor(
          () => _sessionOrNull(client, first.id),
          (row) => row != null && row.isPaused,
          what: 'the living room to read paused',
        );
        final untouched = await _sessionOrNull(client, second.id);
        expect(untouched, isNotNull);
        expect(untouched!.isPaused, isFalse);

        for (final session in [first.id, second.id]) {
          await client.stopSession(session);
          await _waitFor(
            () => _sessionOrNull(client, session),
            (row) => row == null,
            what: 'session $session to leave the list',
          );
        }
      },
    );
  });
}

/// A session by id, or null once it is gone: the one read every wait uses.
Future<StreamSession?> _sessionOrNull(JellyfinClient client, String id) async {
  final sessions = await client.getSessions();
  for (final session in sessions) {
    if (session.id == id) return session;
  }
  return null;
}

/// The first session whose device label names [device], polled until it opens.
Future<StreamSession> _waitForSession(
  JellyfinClient client,
  String device, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  String seen = 'no session';
  while (DateTime.now().isBefore(deadline)) {
    final sessions = await client.getSessions();
    for (final session in sessions) {
      if (session.deviceLabel.contains(device)) return session;
    }
    seen = sessions.map((session) => session.deviceLabel).join(', ');
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  fail('No session for $device within ${timeout.inSeconds}s (seen: $seen)');
}

/// Poll [read] until [holds], or say what was still true.
Future<T> _waitFor<T>(
  Future<T> Function() read,
  bool Function(T value) holds, {
  required String what,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  late T value;
  while (DateTime.now().isBefore(deadline)) {
    value = await read();
    if (holds(value)) return value;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('The server never showed $what within ${timeout.inSeconds}s');
}

/// The playback helper as a process: `jellyfin_play.py --listen`, which is the
/// only half of a client Jellyfin needs to hold a session and obey a command.
///
/// Its stdout is kept, because a `Playstate` line in it is the evidence that
/// the server relayed the command to the client rather than only answering the
/// app's 204. Its stderr never carries a credential: the helper prints a
/// refusal by username.
class _PlayHelper {
  _PlayHelper(this.lab, {required this.device});

  final _Lab lab;
  final String device;
  final List<String> _output = [];
  Process? _process;

  /// Everything the helper has printed so far.
  String get output => _output.join('\n');

  Future<void> start({
    required String title,
    required String user,
    int holdSeconds = 120,
  }) async {
    final script = File('${lab.repoRoot}/test/e2e/testlab/jellyfin_play.py');
    expect(
      script.existsSync(),
      isTrue,
      reason: 'the helper is in the checkout',
    );
    final process = await Process.start(
      'python3',
      [
        script.path,
        '--device',
        device,
        '--title',
        title,
        '--user',
        user,
        '--listen',
        '--hold',
        '$holdSeconds',
      ],
      workingDirectory: lab.repoRoot,
      environment: {
        'CUPOLA_TESTLAB_STATE_DIR': lab.stateDir,
        'CUPOLA_TESTLAB_JELLYFIN_URL': _Lab.jellyfinUrl,
      },
    );
    _process = process;
    process.stdout.transform(utf8.decoder).listen(_output.add);
    process.stderr.transform(utf8.decoder).listen(_output.add);
  }

  Future<void> dispose() async {
    final process = _process;
    if (process == null) return;
    _process = null;
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
  }
}

/// The lab as the bootstrap and the `jellyfin-media` scenario left it.
class _Lab {
  _Lab._(this._values, this.credentialsPath);

  factory _Lab.load() {
    final named = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
    final path = named == null || named.isEmpty
        ? '.ai/scratch/zz_testlab/state/credentials.env'
        : named;
    final file = File(path);
    if (!file.existsSync()) {
      fail(
        'No lab credentials at $path: run test/e2e/testlab/bootstrap.sh, or '
        'point CUPOLA_TESTLAB_CREDENTIALS_FILE at its credentials file.',
      );
    }
    final values = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      values[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return _Lab._(values, file.absolute.path);
  }

  final Map<String, String> _values;
  final String credentialsPath;

  static const jellyfinUrl = 'http://127.0.0.1:8096';

  String _value(String name) {
    final value = _values[name];
    if (value == null || value.isEmpty) {
      fail('The lab credentials have no $name: run the bootstrap again.');
    }
    return value;
  }

  String get adminToken => _value('CUPOLA_TESTLAB_JELLYFIN_TOKEN');
  String get viewerName => _value('CUPOLA_TESTLAB_JELLYFIN_REQUESTER_USERNAME');
  String get _viewerPassword =>
      _value('CUPOLA_TESTLAB_JELLYFIN_REQUESTER_PASSWORD');

  /// The state directory the helper reads: the credentials file's own folder.
  String get stateDir => File(credentialsPath).parent.path;

  /// The package root, where the flutter test was started.
  String get repoRoot => Directory.current.path;

  /// A container over one Jellyfin connection, with the app's real providers.
  Future<ProviderContainer> container({
    required String token,
    required String viewerId,
  }) async {
    final instance = ServiceInstance(
      id: ServiceInstance.primaryIdFor(ServiceKey.jellyfin),
      service: ServiceKey.jellyfin,
      url: jellyfinUrl,
      credential: token,
      viewerId: viewerId,
    );
    final overrides = await settingsScopeOverrides(
      customize: (settings) => settings.copyWithInstance(instance),
    );
    return ProviderContainer(overrides: overrides);
  }

  /// A household member's own token, the way the app's settings would hold one.
  ///
  /// Jellyfin has no app-side sign-in in Cupola (the connection holds a token),
  /// so the sign-in is this test's: `POST /Users/AuthenticateByName` with the
  /// password the bootstrap generated, kept in the chmod-600 file and never
  /// printed.
  Future<({String token, String userId, String name})> signInViewer() async {
    final http = HttpClient();
    try {
      final request = await http.postUrl(
        Uri.parse('$jellyfinUrl/Users/AuthenticateByName'),
      );
      request.headers.set(
        'Authorization',
        'MediaBrowser Client="Cupola Lab E2E", Device="Cupola Lab E2E", '
            'DeviceId="cupola-testlab-jellyfin-e2e", Version="1.0"',
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({'Username': viewerName, 'Pw': _viewerPassword}),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 200, reason: '$viewerName signs in');
      final json = jsonDecode(body) as Map<String, dynamic>;
      final user = json['User'] as Map<String, dynamic>;
      return (
        token: json['AccessToken'] as String,
        userId: user['Id'] as String,
        name: user['Name'] as String,
      );
    } finally {
      http.close(force: true);
    }
  }

  Future<void> waitForJellyfin() async {
    for (var attempt = 0; attempt < 60; attempt++) {
      try {
        final http = HttpClient();
        try {
          final request = await http.getUrl(
            Uri.parse('$jellyfinUrl/System/Info/Public'),
          );
          final response = await request.close();
          await response.drain<void>();
          if (response.statusCode == 200) return;
        } finally {
          http.close(force: true);
        }
      } on IOException {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    fail('The lab Jellyfin did not answer at $jellyfinUrl');
  }
}
