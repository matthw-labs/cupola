@Tags(['e2e'])
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_version.dart';

/// Tracearr in the macOS lab, through Cupola's own client: its identity and
/// its public key, the two servers it watches, and what it makes of two
/// playbacks at once on the lab's Emby.
///
/// The lab's Tracearr (3.1.4, TimescaleDB and Redis in the one container) comes
/// out of the bootstrap with an owner, the `trr_pub_` key the app holds, the
/// lab's Jellyfin and Emby connected, and the rule `Too many streams at once`
/// with one stream allowed (`tracearr_first_run.py`, `tracearr_lab.py`). The
/// streams, the history and the violation are real: two devices of the
/// household member play on the Emby through `emby_play.py`, Tracearr polls the
/// Emby, and the rule fires when the second stream starts.
///
/// The file opens those playbacks itself (`tracearr_lab.py --play`, which waits
/// until Tracearr lists both streams and has recorded the violation) and ends
/// them when it is done (`--stop`), so it runs on its own:
///
/// ~~~bash
/// flutter test --tags e2e --run-skipped test/e2e/testlab_tracearr_e2e_test.dart
/// ~~~
///
/// The same two playbacks are what `testlab.py scenario apply tracearr-streams`
/// leaves running for the journeys; applying it first is harmless, because the
/// helper keeps a device that is already playing.
///
/// What a violation is, as the lab measured it: the rule's name, a severity, a
/// person, a server, and `data` holding the evidence, which also holds the
/// address the person streamed from. The app never reads that address, and
/// nothing here prints one.
///
/// `CUPOLA_TESTLAB_TRACEARR_URL` points the file at another address than the
/// lab's published one, which is how it runs against a disposable container;
/// `CUPOLA_TESTLAB_EMBY_URL` and `CUPOLA_TESTLAB_JELLYFIN_URL` do the same for
/// the playbacks' helper, and `CUPOLA_TESTLAB_TRACEARR_EMBY_URL` and
/// `CUPOLA_TESTLAB_TRACEARR_JELLYFIN_URL` name where Tracearr dials them.
void main() {
  late _Lab lab;
  late TracearrClient client;

  setUpAll(() async {
    lab = _Lab.load();
    await lab.waitForTracearr();
    client = TracearrClient(baseUrl: lab.url, apiKey: lab.apiKey);
    addTearDown(client.close);
  });

  group('the probe and the credential', () {
    test('the keyless health is Tracearr\'s own', () async {
      final body = await lab.getJson('/health');
      expect(body['mode'], 'ready');
      expect(body['db'], isTrue);
      expect(body['redis'], isTrue);
      // The two keys that tell Tracearr from any other service answering
      // /health: the database it ships with, and the mode it is in.
      expect(body['timescale'], isA<Map>());
    });

    test('the key proves itself and names the version', () async {
      final health = await client.checkCredentialAndVersion();

      expect(health.isOk, isTrue);
      final version = health.parsedVersion;
      expect(version, isNotNull, reason: 'Tracearr names its version');
      expect(version! >= kTracearrMin, isTrue, reason: '$version');
      expect(health.version, startsWith('v'));
    });

    test(
      'a wrong key is refused with a 401, not mistaken for a dark box',
      () async {
        final wrong = TracearrClient(
          baseUrl: lab.url,
          apiKey: 'trr_pub_not-the-lab-key',
        );
        addTearDown(wrong.close);

        await expectLater(
          wrong.checkCredentialAndVersion(),
          throwsA(
            isA<DioException>().having(
              (error) => error.response?.statusCode,
              'status',
              401,
            ),
          ),
        );
        // The keyless health still answers: the two outcomes stay apart.
        expect((await lab.getJson('/health'))['mode'], 'ready');
      },
    );

    test('the servers it watches are the lab\'s two, and up', () async {
      final servers = await client.getServers();

      expect(servers.tracearrVersion, startsWith('v'));
      final types = servers.servers.map((server) => server.type).toSet();
      expect(
        types,
        containsAll([TracearrServerType.jellyfin, TracearrServerType.emby]),
        reason: 'the seed connected both',
      );
      for (final server in servers.servers) {
        expect(
          server.isUp,
          isTrue,
          reason: '${server.name} reads as ${server.status}',
        );
        expect(server.historical, isFalse);
      }
    });
  });

  group('the owner', () {
    TracearrOwnerClient owner({String token = ''}) {
      final built = TracearrOwnerClient.forReach(
        reach: (url: lab.url, access: const NoAccess(), pin: null),
        token: token,
      );
      addTearDown(built.close);
      return built;
    }

    test('the ways in say a local sign-in exists', () async {
      final ways = await owner().readWays();

      expect(ways.local, isTrue);
      expect(ways.needsSetup, isFalse);
    });

    test('the lab\'s owner signs in and reads as the owner', () async {
      final bearer = await owner().signIn(
        login: lab.ownerEmail,
        password: lab.ownerPassword,
      );
      expect(bearer, isNotEmpty);

      final identity = await owner(token: bearer).whoAmI();
      expect(identity.isOwner, isTrue);
      expect((await owner(token: bearer).session()).alive, isTrue);
    });

    test('a wrong password is refused as one', () async {
      await expectLater(
        owner().signIn(login: lab.ownerEmail, password: 'not-the-password'),
        throwsA(
          isA<TracearrSignInRefused>().having(
            (refusal) => refusal.refusal,
            'refusal',
            TracearrSignInRefusal.wrongPassword,
          ),
        ),
      );
    });
  });

  group('during two playbacks at once', () {
    setUpAll(() async {
      await lab.helper('--play');
    });
    tearDownAll(() async {
      await lab.helper('--stop');
    });

    test('Live lists both streams, played by the household member', () async {
      final streams = await client.getStreams();
      final ours = streams.streams
          .where((stream) => lab.devices.contains(stream.device.player))
          .toList();

      expect(
        ours.map((stream) => stream.device.player).toSet(),
        lab.devices,
        reason: 'both devices stream',
      );
      expect(streams.summary.total, greaterThanOrEqualTo(2));
      for (final stream in ours) {
        expect(stream.person.name, lab.viewerName);
        expect(stream.server.type, TracearrServerType.emby);
        expect(stream.state, TracearrStreamState.playing);
        expect(stream.isPaused, isFalse);
      }
      expect(
        ours.map((stream) => stream.media.title),
        containsAll(['Big Buck Bunny', 'The Matrix']),
      );
    });

    test('a server\'s count of streams says the same', () async {
      final servers = await client.getServers();
      final emby = servers.servers.singleWhere(
        (server) => server.type == TracearrServerType.emby,
      );

      expect(emby.activeStreams, greaterThanOrEqualTo(2));
    });

    test('Violations holds the rule\'s, with its typed reading', () async {
      final page = await client.getViolations(pageSize: 50);
      final ours = page.items
          .where((violation) => violation.concurrentStreams != null)
          .toList();

      expect(ours, isNotEmpty, reason: 'two streams broke a limit of one');
      final violation = ours.first;
      expect(violation.rule.name, 'Too many streams at once');
      expect(violation.severity, TracearrSeverity.warning);
      expect(violation.person.name, lab.viewerName);
      expect(violation.server.type, TracearrServerType.emby);
      final reading = violation.concurrentStreams!;
      expect(reading.count, greaterThanOrEqualTo(2));
      expect(reading.limit, 1);
      // Another rule's reading is not this one's.
      expect(violation.impossibleTravel, isNull);
    });

    test('one violation reads the same by its id', () async {
      final page = await client.getViolations(pageSize: 50);
      final listed = page.items.firstWhere(
        (violation) => violation.concurrentStreams != null,
      );

      final read = await client.getViolation(listed.id);

      expect(read, isNotNull);
      expect(read!.id, listed.id);
      expect(read.rule.name, listed.rule.name);
      expect(read.concurrentStreams!.count, listed.concurrentStreams!.count);
      expect(read.concurrentStreams!.limit, 1);
      // Nobody has acted on it: the lab's rule has no action.
      expect(read.actions, isEmpty);
    });

    test('Violations narrows to the unseen, on the server', () async {
      final page = await client.getViolations(
        pageSize: 50,
        filter: const TracearrViolationFilter.unseen(),
      );

      expect(
        page.items.every((violation) => !violation.isAcknowledged),
        isTrue,
      );
    });

    test('a violation that is not there reads as null', () async {
      expect(
        await client.getViolation('00000000-0000-4000-8000-000000000000'),
        isNull,
      );
    });

    test('Stop answers for a stream that is not running any more', () async {
      // The route exists (this is not an older install), and no such stream
      // runs: the app must tell that apart from a failed stop.
      final result = await client.terminate(
        '00000000-0000-4000-8000-000000000000',
      );

      expect(result, isA<TracearrTerminateStreamGone>());
    });
  });

  group('after the playbacks end', () {
    setUpAll(() async {
      // Two playbacks, then none: the history is what Tracearr wrote down
      // when each stopped.
      await lab.helper('--play');
      await lab.helper('--stop');
    });

    test('History holds what the household member played', () async {
      final page = await client.getHistory(pageSize: 50);

      expect(page.items, isNotEmpty);
      final ours = page.items.where(
        (entry) => lab.devices.contains(entry.device.player),
      );
      expect(ours, isNotEmpty, reason: 'the two playbacks are in the history');
      for (final entry in ours) {
        expect(entry.isFinished, isTrue, reason: 'they were stopped');
        expect(entry.person.name, lab.viewerName);
        expect(entry.server.type, TracearrServerType.emby);
        expect(entry.media.title, isNotEmpty);
      }
    });

    test(
      'History narrows to a person on the server, not on the page',
      () async {
        final everyone = await client.getHistory(pageSize: 50);
        final person = everyone.items
            .firstWhere((entry) => entry.person.name == lab.viewerName)
            .person
            .id;
        expect(person, isNotNull);

        final page = await client.getHistory(
          pageSize: 50,
          filter: TracearrHistoryFilter(userId: person),
        );

        expect(page.items, isNotEmpty);
        expect(
          page.items.every((entry) => entry.person.id == person),
          isTrue,
          reason: 'the server applied the filter',
        );
      },
    );
  });

  group('ending a stream through Tracearr', () {
    setUpAll(() async {
      await lab.helper('--play');
    });
    tearDownAll(() async {
      await lab.helper('--stop');
    });

    test('Stop reaches the Emby, which ends that one playback', () async {
      final streams = await client.getStreams();
      final target = streams.streams.firstWhere(
        (stream) => stream.device.player == 'cupola-tracearr-b',
      );

      final result = await client.terminate(
        target.id,
        reason: 'Ended by the lab\'s e2e',
      );

      expect(result, isA<TracearrTerminated>());
      // The player obeys the server's Stop within its keepalive, and Tracearr
      // then stops listing the stream: the other one is untouched.
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      var stillListed = true;
      while (stillListed && DateTime.now().isBefore(deadline)) {
        final now = await client.getStreams();
        stillListed = now.streams.any(
          (stream) => stream.device.player == 'cupola-tracearr-b',
        );
        if (stillListed) await Future<void>.delayed(const Duration(seconds: 2));
      }
      expect(stillListed, isFalse, reason: 'the stream ended');
      expect(
        (await client.getStreams()).streams.any(
          (stream) => stream.device.player == 'cupola-tracearr-a',
        ),
        isTrue,
        reason: 'the other playback is left as it was',
      );
    });
  });
}

/// The lab as the bootstrap and the seed left it.
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

  /// The two devices `tracearr_lab.py` plays on, by the name Emby gives them.
  final Set<String> devices = const {'cupola-tracearr-a', 'cupola-tracearr-b'};

  /// Tracearr on the address the lab publishes, unless the environment names
  /// another (a disposable container).
  String get url {
    final named = Platform.environment['CUPOLA_TESTLAB_TRACEARR_URL'];
    return named == null || named.isEmpty ? 'http://127.0.0.1:3010' : named;
  }

  String _value(String name) {
    final value = _values[name];
    if (value == null || value.isEmpty) {
      fail('The lab credentials have no $name: run the bootstrap again.');
    }
    return value;
  }

  /// The public key the app holds.
  String get apiKey => _value('CUPOLA_TESTLAB_TRACEARR_KEY');
  String get ownerEmail => _value('CUPOLA_TESTLAB_TRACEARR_OWNER_EMAIL');
  String get ownerPassword => _value('CUPOLA_TESTLAB_TRACEARR_OWNER_PASSWORD');

  /// The household member the playbacks are by.
  String get viewerName => _value('CUPOLA_TESTLAB_EMBY_REQUESTER_USERNAME');

  /// The state directory the helper reads: the credentials file's own folder.
  String get stateDir => File(credentialsPath).parent.path;

  /// The package root, where the flutter test was started.
  String get repoRoot => Directory.current.path;

  Future<Map<String, dynamic>> getJson(String path) async {
    final http = HttpClient();
    try {
      final request = await http.getUrl(Uri.parse('$url$path'));
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 200, reason: path);
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      http.close(force: true);
    }
  }

  /// Runs `tracearr_lab.py` with [flag] (`--play` or `--stop`) and fails with
  /// its own words when it fails. Its output carries no secret.
  Future<void> helper(String flag) async {
    final script = File('$repoRoot/test/e2e/testlab/tracearr_lab.py');
    expect(
      script.existsSync(),
      isTrue,
      reason: 'the helper is in the checkout',
    );
    final result = await Process.run(
      'python3',
      [script.path, flag],
      workingDirectory: repoRoot,
      environment: {
        'CUPOLA_TESTLAB_STATE_DIR': stateDir,
        'CUPOLA_TESTLAB_CREDENTIALS_FILE': credentialsPath,
        'CUPOLA_TESTLAB_TRACEARR_URL': url,
      },
    );
    if (result.exitCode != 0) {
      fail('tracearr_lab.py $flag failed: ${result.stderr} ${result.stdout}');
    }
  }

  Future<void> waitForTracearr() async {
    for (var attempt = 0; attempt < 120; attempt++) {
      try {
        final http = HttpClient();
        try {
          final request = await http.getUrl(Uri.parse('$url/health'));
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          if (response.statusCode == 200 && body.contains('"mode":"ready"')) {
            return;
          }
        } finally {
          http.close(force: true);
        }
      } on IOException {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    fail('The lab Tracearr was not ready at $url');
  }
}
