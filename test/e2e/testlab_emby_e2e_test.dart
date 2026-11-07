@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/emby/data/emby_client.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';

import '../test_helpers/settings_scope.dart';

/// Emby in the macOS lab, through Cupola's own client: the same flow
/// catalogue rows as the Jellyfin file (S-01 to S-05 and the two-session
/// state S-09), on the same media, read as Emby answers them.
///
/// The library and the watch states come from the `emby-media` scenario:
///
/// ~~~bash
/// python3 test/e2e/testlab/testlab.py scenario apply emby-media
/// flutter test --tags e2e --run-skipped test/e2e/testlab_emby_e2e_test.dart
/// ~~~
///
/// The connection is what a person saves: the API key the lab made through
/// `POST /Auth/Keys`, which belongs to no user, plus the viewer the app reads
/// the server as (`cupola-viewer`, the household member the watch states are
/// kept for). The household member's own token is the second connection, for
/// what Emby withholds from a person who is not an administrator.
///
/// Where Emby parts from Jellyfin, and what this file therefore asserts
/// differently:
///
///  * a member's token may read the libraries (`/Library/VirtualFolders/Query`
///    is open to everyone) where Jellyfin answers 403, while users, devices and
///    tasks are refused the same way;
///  * the key has no user, so the probe is identified by the body's shape and
///    the credential kind is read from what `/Users/Query` answers;
///  * item ids are short numbers, and the pause and the stop are measured on
///    `/Sessions` for the same reason they are on Jellyfin: a 204 means the
///    command was relayed, not that the player obeyed it.
///
/// A playback session is not something this file can fake: it is opened by
/// `test/e2e/testlab/emby_play.py`, a real Emby client that reports
/// `/Sessions/Playing` and holds the WebSocket that carries the server's
/// remote control. The S-03 session plays the watched movie on purpose, never
/// the episode with the resume point: a stop writes a new position, so a
/// session on the episode would move the 30% S-04 asserts.
///
/// `CUPOLA_TESTLAB_EMBY_URL` points the file at another address than the lab's
/// published one, which is how it runs against a disposable container.
void main() {
  late _Lab lab;
  late EmbyClient client;
  late EmbyClient memberClient;
  late ProviderContainer memberContainer;
  late String viewerId;

  setUpAll(() async {
    lab = _Lab.load();
    await lab.waitForEmby();

    final probe = EmbyClient(baseUrl: lab.url, apiKey: lab.apiKey);
    try {
      final users = await probe.getUsers();
      final viewer = users.where((user) => user.name == lab.viewerName);
      expect(
        viewer,
        isNotEmpty,
        reason: 'the lab has no Emby user named ${lab.viewerName}',
      );
      viewerId = viewer.first.id;
    } finally {
      probe.close();
    }

    final adminContainer = await lab.container(
      token: lab.apiKey,
      viewerId: viewerId,
    );
    addTearDown(adminContainer.dispose);
    client = adminContainer.read(embyClientProvider);

    final member = await lab.signInViewer();
    memberContainer = await lab.container(
      token: member.token,
      viewerId: member.userId,
    );
    addTearDown(memberContainer.dispose);
    memberClient = memberContainer.read(embyClientProvider);
  });

  group('the probe and the credential', () {
    test('the public answer is Emby\'s, and carries a version', () async {
      final probe = EmbyClient(baseUrl: lab.url, apiKey: lab.apiKey);
      addTearDown(probe.close);

      expect(await probe.probeVersion(), startsWith('4.'));
      expect(await probe.publicServerId(), isNotEmpty);
    });

    test('the key proves itself and names the version', () async {
      expect(await client.verifyCredential(), isTrue);
      expect(await client.checkCredentialAndVersion(), startsWith('4.'));
    });

    test(
      'a wrong key is refused, and is not mistaken for a dark box',
      () async {
        final wrong = EmbyClient(baseUrl: lab.url, apiKey: 'not-the-lab-key');
        addTearDown(wrong.close);

        expect(await wrong.verifyCredential(), isFalse);
        // The server answered, so the public probe still reads a version: the
        // two outcomes stay apart.
        expect(await wrong.probeVersion(), isNotNull);
      },
    );

    test('a Jellyfin client does not take Emby for its server', () async {
      // Emby answers the root as it answers `/emby`, and its body carries no
      // product name: the identity check is what keeps the two apart.
      final jellyfin = JellyfinClient(baseUrl: lab.url, apiKey: lab.apiKey);
      addTearDown(jellyfin.close);

      expect(await jellyfin.probeVersion(), isNull);
      await expectLater(
        jellyfin.checkCredentialAndVersion(),
        throwsA(anything),
      );
    });

    test('the administrator\'s key reads as an administrator', () async {
      expect(
        await client.getCredentialKind(),
        JellyfinCredentialKind.administrator,
      );
    });
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

      // The count is the library's own unit: shows for a TV library, not the
      // episodes recursive browsing would sweep up.
      expect(await client.getLibraryItemCount(byName['Films']!.id), 4);
      expect(await client.getLibraryItemCount(byName['Series']!.id), 1);
      expect(await client.getLibraryItemCount(byName['Music']!.id), 1);
    });

    test('a movie opens on its own page, with a runtime and an id', () async {
      final libraries = await client.getLibraries();
      final films = libraries.singleWhere((library) => library.name == 'Films');
      final page = await client.getLibraryPage(
        libraryId: films.id,
        lens: StreamLibraryLens.all,
        limit: 50,
      );

      expect(page.failed, isFalse, reason: 'the A to Z page answered');
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

    test('the title page reads with no viewer too', () async {
      // `GET /Items/{id}` is a 404 on Emby; with no viewer the page is read
      // through `/Items?Ids=`, which is the route a connection that is only a
      // key has.
      final keyOnly = EmbyClient(baseUrl: lab.url, apiKey: lab.apiKey);
      addTearDown(keyOnly.close);
      final libraries = await keyOnly.getLibraries();
      final films = libraries.singleWhere((library) => library.name == 'Films');
      final page = await keyOnly.getLibraryPage(
        libraryId: films.id,
        lens: StreamLibraryLens.all,
        limit: 50,
      );
      final movie = page.items.singleWhere(
        (item) => item.title == 'Big Buck Bunny',
      );

      final detail = await keyOnly.getItem(movie.id);
      expect(detail, isNotNull);
      expect(detail!.title, 'Big Buck Bunny');
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
        lens: StreamLibraryLens.all,
        limit: 50,
      );
      expect(shows.failed, isFalse);
      final show = shows.items.singleWhere(
        (item) => item.title == 'Breaking Bad',
      );
      expect(show.kind, StreamItemKind.series);

      final episodes = await client.getEpisodes(show.id);
      expect(episodes.length, 2);
      // By number, not by title: an Emby that cannot reach its metadata
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
        lens: StreamLibraryLens.all,
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

    test('search finds a title through the item query', () async {
      // `/Search/Hints` answers an empty list on Emby 4.10 even where items
      // match, so the dialect searches `/Items`.
      final groups = await client.search('Big Buck');
      final titles = [
        for (final group in groups)
          for (final item in group.items) item.title,
      ];
      expect(titles, contains('Big Buck Bunny'));
    });
  });

  group('S-02 household, devices, tasks and activity', () {
    test(
      'the administrator reads users, devices and scheduled tasks',
      () async {
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

        final tasks = await client.getScheduledTasks();
        expect(tasks, isNotEmpty);
        expect(
          tasks.every((task) => task.id.isNotEmpty && task.name.isNotEmpty),
          isTrue,
        );
      },
    );

    test(
      'activity is the live session list the client already reads',
      () async {
        final sessions = await client.getSessions();
        expect(sessions, isA<List<StreamSession>>());
        // Every row the board draws is an item somebody is playing: a
        // connected client with nothing playing, and the key's own session,
        // are not activity.
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

        await memberContainer.read(embyCredentialKindProvider.future);
        expect(memberContainer.read(embyLacksAdministratorProvider), isTrue);

        // The elevated reads are refused as a permission, never as an empty
        // list: the tabs are withheld, so no surface claims "no devices".
        final refused = isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status',
          403,
        );
        await expectLater(memberClient.getUsers(), throwsA(refused));
        await expectLater(memberClient.getDevices(), throwsA(refused));
        await expectLater(memberClient.getScheduledTasks(), throwsA(refused));

        // The libraries are not elevated on Emby: a member reads the ones her
        // policy exposes, which on this lab is all three.
        expect(
          (await memberClient.getLibraries()).map((library) => library.name),
          containsAll(const ['Films', 'Series', 'Music']),
        );

        // With no `/Users/Me` to ask, the member is the viewer the connection
        // already holds, read by id.
        expect((await memberClient.getViewers()).map((viewer) => viewer.name), [
          lab.viewerName,
        ]);
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

    test('the watched movie is recent and reads watched', () async {
      final watched = await client.getRecentlyWatched(limit: 10);
      expect(watched, isNotEmpty);
      final film = watched.singleWhere(
        (row) => row.item.title == 'Big Buck Bunny',
      );
      expect(film.item.kind, StreamItemKind.movie);
      expect(film.item.isPlayed, isTrue);
      // Emby leaves the played date out of a list unless it is asked for, so a
      // movie with no date would drop out of this row instead of reading old.
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
        lens: StreamLibraryLens.all,
        limit: 50,
      );
      final show = page.items.singleWhere(
        (item) => item.title == 'Breaking Bad',
      );
      final episodes = await client.getEpisodes(show.id);

      // The badge: neither episode is finished. A resume point is not a
      // watched episode, so the count is both of them.
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
Future<StreamSession?> _sessionOrNull(EmbyClient client, String id) async {
  final sessions = await client.getSessions();
  for (final session in sessions) {
    if (session.id == id) return session;
  }
  return null;
}

/// The first session whose device label names [device], polled until it opens.
Future<StreamSession> _waitForSession(
  EmbyClient client,
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

/// The playback helper as a process: `emby_play.py --listen`, which is the only
/// half of a client Emby needs to hold a session and obey a command.
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
    final script = File('${lab.repoRoot}/test/e2e/testlab/emby_play.py');
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
        'CUPOLA_TESTLAB_EMBY_URL': lab.url,
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

/// The lab as the bootstrap and the `emby-media` scenario left it.
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

  /// Emby on the address the lab publishes, unless the environment names
  /// another (a disposable container).
  String get url {
    final named = Platform.environment['CUPOLA_TESTLAB_EMBY_URL'];
    return named == null || named.isEmpty ? 'http://127.0.0.1:8097' : named;
  }

  String _value(String name) {
    final value = _values[name];
    if (value == null || value.isEmpty) {
      fail('The lab credentials have no $name: run the bootstrap again.');
    }
    return value;
  }

  /// The API key the app holds: no user owns it.
  String get apiKey => _value('CUPOLA_TESTLAB_EMBY_TOKEN');
  String get viewerName => _value('CUPOLA_TESTLAB_EMBY_REQUESTER_USERNAME');
  String get _viewerPassword =>
      _value('CUPOLA_TESTLAB_EMBY_REQUESTER_PASSWORD');

  /// The state directory the helper reads: the credentials file's own folder.
  String get stateDir => File(credentialsPath).parent.path;

  /// The package root, where the flutter test was started.
  String get repoRoot => Directory.current.path;

  /// A container over one Emby connection, with the app's real providers.
  Future<ProviderContainer> container({
    required String token,
    required String viewerId,
  }) async {
    final instance = ServiceInstance(
      id: ServiceInstance.primaryIdFor(ServiceKey.emby),
      service: ServiceKey.emby,
      url: url,
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
  /// Cupola has no sign-in for Emby (the connection holds a key or a token),
  /// so the sign-in is this test's: `POST /emby/Users/AuthenticateByName` with
  /// the password the bootstrap generated, kept in the chmod-600 file and never
  /// printed.
  Future<({String token, String userId, String name})> signInViewer() async {
    final http = HttpClient();
    try {
      final request = await http.postUrl(
        Uri.parse('$url/emby/Users/AuthenticateByName'),
      );
      request.headers.set(
        'X-Emby-Authorization',
        'MediaBrowser Client="Cupola Lab E2E", Device="Cupola Lab E2E", '
            'DeviceId="cupola-testlab-emby-e2e", Version="1.0"',
      );
      request.headers.contentType = ContentType.json;
      // An exact length: Emby answers a chunked body with a 400 that blames a
      // missing name, which is what `write` alone would send.
      final payload = utf8.encode(
        jsonEncode({'Username': viewerName, 'Pw': _viewerPassword}),
      );
      request.contentLength = payload.length;
      request.add(payload);
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

  Future<void> waitForEmby() async {
    for (var attempt = 0; attempt < 60; attempt++) {
      try {
        final http = HttpClient();
        try {
          final request = await http.getUrl(
            Uri.parse('$url/emby/System/Info/Public'),
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
    fail('The lab Emby did not answer at $url');
  }
}
