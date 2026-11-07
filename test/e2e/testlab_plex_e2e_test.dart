@Tags(['e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';

import '../test_helpers/settings_scope.dart';

/// Plex's three rows of the flow catalogue, S-06 to S-08, read through the
/// app's own `PlexClient` against the claimed server on 127.0.0.1:32400.
///
/// ```
/// python3 test/e2e/testlab/testlab.py scenario apply plex-media
/// python3 test/e2e/testlab/plex_play.py
/// flutter test --tags e2e --run-skipped test/e2e/testlab_plex_e2e_test.dart
/// python3 test/e2e/testlab/testlab.py scenario teardown plex-media
/// ```
///
/// `setUpAll` applies the scenario and runs the playback spike itself, so the
/// file is repeatable on its own; the scenario is idempotent and the spike
/// ends the session it made. The two contract files under
/// `.ai/scratch/zz_testlab/state/` are what the assertions read ids from:
/// `plex-media.json` (libraries, the watched rows, on deck) and
/// `plex-play.json` (the session shape and what the server answered to a
/// terminate call).
///
/// What is a declared limit and not a missing assertion:
///
///  * **a movie on deck.** Plex writes `viewOffset` only from a real client
///    playback; on 1.43.4 the API cannot set it (`plex_media.py` carries the
///    evidence). The on-deck row this file proves is Plex's own next-up: the
///    episode after the one marked watched;
///  * **stopping a stream.** This server has no Plex Pass, so
///    `/status/sessions/terminate` is refused and the app offers no Stop
///    (`plexStopOfferedProvider`). S-07 proves the refusal through the app and
///    leaves the stream playing, which is the honest outcome, then ends it the
///    way a client does (`/:/timeline?state=stopped`);
///  * **a household Plex user.** The server is claimed with the owner's real
///    account and this lab never writes that account, so every read here is
///    the owner's own view. That is decision 16's single perspective, made
///    explicit by the lab rather than by a missing feature.
void main() {
  late _Lab lab;
  late Map<String, dynamic> media;
  late Map<String, dynamic> spike;
  late ProviderContainer container;

  setUpAll(() async {
    await _scenario('apply', 'plex-media');
    // The spike is S-07's evidence: it plays a real session, asks the server to
    // stop it, and ends it the way a client does. It leaves nobody playing, so
    // the S-07 test makes its own session when it gets there.
    await _spike();
    lab = _Lab.load();
    await lab.waitForPlex();
    media = lab.contract('plex-media.json');
    spike = lab.contract('plex-play.json');
    container = await lab.container();
  });

  tearDownAll(() async {
    await _stop();
    container.dispose();
    await _scenario('teardown', 'plex-media');
  });

  PlexClient client() => container.read(plexClientProvider);

  test('S-06: three libraries, on the forge folders', () async {
    final libraries = await container.read(plexLibrariesProvider.future);
    expect(
      libraries.map((library) => library.name),
      containsAll(<String>['Films', 'Series', 'Music']),
    );

    // The contract is written by the scenario from the server's own answer,
    // so a renamed or duplicated section fails here rather than passing by id.
    final declared = (media['libraries'] as List).cast<Map<String, dynamic>>();
    expect(libraries, hasLength(declared.length));
    for (final section in declared) {
      final actual = libraries.firstWhere(
        (library) => library.id == section['id'],
        orElse: () =>
            fail('the ${section['title']} section is not on the server'),
      );
      expect(actual.name, section['title']);
      expect(actual.kind, _kindOf(section['kind'] as String));
      expect(actual.isRefreshing, isFalse);
    }
    expect(libraries.map((library) => (library.name, library.kind)).toSet(), {
      ('Films', StreamLibraryKind.movies),
      ('Series', StreamLibraryKind.shows),
      ('Music', StreamLibraryKind.music),
    });
  });

  test('S-06: a movie, a show with its episodes, and a track', () async {
    final ids = _ids(media);

    final movies = await client().getLibraryPage(
      libraryId: ids['Films']!,
      sort: StreamLibrarySort.name,
    );
    final movie = movies.items.firstWhere(
      (item) => item.title == (media['items'] as Map)['movie']['title'],
      orElse: () => fail('the contract movie is not in Films'),
    );
    expect(movie.kind, StreamItemKind.movie);
    expect(movie.isPlayed, isTrue, reason: 'the scenario marked it watched');

    final series = await client().getLibraryPage(
      libraryId: ids['Series']!,
      sort: StreamLibrarySort.name,
    );
    final show = series.items.firstWhere(
      (item) => item.title == 'Breaking Bad',
      orElse: () => fail('Breaking Bad is not in Series'),
    );
    expect(show.kind, StreamItemKind.series);

    final seasons = await client().getChildren(show.id);
    expect(seasons, isNotEmpty, reason: 'a show has seasons');
    final episodes = await client().getEpisodes(show.id);
    expect(
      episodes.map((episode) => episode.episodeNumber),
      containsAll(<int>[1, 2]),
    );
    final pilot = episodes.firstWhere((episode) => episode.episodeNumber == 1);
    expect(pilot.title, (media['items'] as Map)['episode']['title']);
    expect(pilot.subtitle, 'Breaking Bad');
    expect(pilot.isPlayed, isTrue, reason: 'the scenario marked it watched');

    final music = await client().getLibraryPage(
      libraryId: ids['Music']!,
      sort: StreamLibrarySort.name,
    );
    final artist = music.items.firstWhere(
      (item) => item.title == 'Daft Punk',
      orElse: () => fail('Daft Punk is not in Music'),
    );
    // Plex's `artist` maps onto `album` so the browse can go deeper; the level
    // is named by its children, not by the enum.
    expect(artist.kind, StreamItemKind.album);
    final albums = await client().getChildren(artist.id);
    final album = albums.firstWhere(
      (item) => item.title == 'Discovery',
      orElse: () => fail('Discovery is not under Daft Punk'),
    );
    final tracks = await client().getChildren(album.id);
    expect(
      tracks.map((track) => track.title),
      contains((media['items'] as Map)['track']['title']),
    );
    expect(tracks.first.kind, StreamItemKind.track);
    expect(tracks.first.subtitle, 'Daft Punk');
  });

  test(
    'S-06: next up carries the next episode, recently watched the movie',
    () async {
      final onDeck = await client().getNextUp(count: 12);
      expect(onDeck, isNotEmpty, reason: 'the scenario missed s01e01');
      final next = onDeck.first;
      expect(next.kind, StreamItemKind.episode);
      expect(next.subtitle, 'Breaking Bad');
      expect(
        next.episodeNumber,
        (media['items'] as Map)['nextEpisode']['index'],
      );
      expect(next.isPlayed, isFalse);
      expect(
        next.resumeOffsetMs,
        isNull,
        reason: 'next up has no resume point, which is what next up keeps',
      );

      // The catalog says a movie on deck is not made here: Plex would need a real
      // playback to write `viewOffset`, and no API call can. The row is a
      // next-up, and the watched movie carries the other half instead.
      expect((media['limits'] as Map)['movieOnDeck'], isA<String>());

      final watched = await client().getRecentlyWatched(limit: 20);
      expect(
        watched.map((row) => row.item.id),
        contains((media['watched'] as Map)['movie']['ratingKey']),
      );
      // Plex reports `lastViewedAt` in epoch seconds; the model carries a
      // DateTime, so the two are compared in seconds.
      final movieRow = watched.firstWhere(
        (row) => row.item.id == (media['watched'] as Map)['movie']['ratingKey'],
      );
      expect(
        movieRow.playedAt.millisecondsSinceEpoch ~/ 1000,
        (media['watched'] as Map)['movie']['lastViewedAt'],
      );
    },
  );

  test('S-06: the device list and an empty playlist list', () async {
    final devices = await container.read(plexDevicesProvider.future);
    expect(devices, isNotEmpty, reason: 'the lab has spoken to this server');
    expect(
      devices.where((device) => device.clientIdentifier.isNotEmpty),
      isNotEmpty,
    );

    final player =
        (spike['consuming'] as Map<String, dynamic>)['machineIdentifier']
            as String;
    expect(
      devices.map((device) => device.clientIdentifier),
      contains(player),
      reason: 'the spike registered its own device row, not the app\'s',
    );

    final playlists = await container.read(plexPlaylistsProvider.future);
    expect(
      playlists,
      isEmpty,
      reason: 'the lab server holds no playlist: the tab draws "No playlists"',
    );
  });

  test('S-07: the server has no Plex Pass, so the app offers no Stop', () async {
    // Ask the lens family itself, not only the base provider: the Stop gate
    // watches that family, and its first read is a loading state whose silence
    // means "available" by design.
    final sheet = await container.read(plexCapabilitiesForProvider('').future);
    expect(
      sheet.myPlexSubscription,
      isFalse,
      reason:
          'the lab server reports no Plex Pass: stopping a stream is behind it',
    );
    expect(
      container.read(plexStopOfferedProvider('')),
      isFalse,
      reason: 'a control the server cannot honour is not drawn',
    );
  });

  test('S-07: the stop the app sends is refused, and names Plex Pass', () async {
    // One session, made by the spike's own command and left playing: the app's
    // stop is what this test is about.
    await _play();
    addTearDown(_stop);

    final sessions = await client().getSessions();
    final live = sessions.where((session) => session.id.isNotEmpty).toList();
    expect(
      live,
      isNotEmpty,
      reason: 'plex_play.py play left one session with a nested Session id',
    );
    final playing = live.first;

    // The refusal is the finding, not a failure: 401 here means Plex Pass, and
    // the client says so instead of sending the user to re-paste a token that
    // works. The session stays up, which the assertion after it proves.
    await expectLater(
      client().stopSession(playing.id),
      throwsA(
        isA<PlexException>()
            .having((error) => error.reason.name, 'reason', 'unauthorized')
            .having((error) => error.message, 'message', contains('Plex Pass')),
      ),
    );
    final after = await client().getSessions();
    expect(
      after.map((session) => session.id),
      contains(playing.id),
      reason: 'a refused stop leaves the stream playing',
    );

    // The spike's own evidence, in the words the catalog asks for: the session
    // carried the nested `Session.id` the app sends, the server answered 401,
    // and the session was ended by the client's own `state=stopped`.
    final terminate = spike['terminate'] as Map<String, dynamic>;
    expect(
      (spike['consuming'] as Map<String, dynamic>)['sessionId'],
      isNotEmpty,
    );
    expect(terminate['status'], 401);
    expect(terminate['allowed'], isFalse);
    expect(spike['stopped'], isTrue);
    expect((spike['after'] as Map)['sessions'], isEmpty);
  });

  test('S-08: playlists are read, never written', () async {
    // The catalog closes S-08 as a declared X: the client has no POST or PUT on
    // `/playlists`, so the app cannot offer the action. Held to the source so
    // the claim cannot drift while the test stays green.
    final source = File(
      'lib/features/plex/data/plex_client.dart',
    ).readAsStringSync().split('\n');
    final reads = <int>[
      for (var index = 0; index < source.length; index++)
        if (source[index].contains('/playlists')) index,
    ];
    expect(reads, isNotEmpty, reason: 'the read is what the tab draws');
    for (final index in reads) {
      final start = index - 3 < 0 ? 0 : index - 3;
      final stop = index + 3 > source.length ? source.length : index + 3;
      final window = source.sublist(start, stop).join('\n');
      for (final write in const ['.post(', '.put(', '.delete(', 'method:']) {
        expect(
          window.contains(write),
          isFalse,
          reason: 'the client writes /playlists through $write',
        );
      }
    }

    // And the surface a person sees offers no create either: the empty state is
    // the promise, and there is no button beside it.
    final screen = File(
      'lib/features/plex/presentation/plex_tab_screens.dart',
    ).readAsStringSync();
    expect(screen, contains("'No playlists'"));
    expect(screen, contains("'Create a Plex playlist to see it here.'"));
    expect(screen, isNot(contains('New playlist')));
    expect(
      await container.read(plexPlaylistsProvider.future),
      isEmpty,
      reason: 'the lab server holds no playlist to read',
    );
  });
}

StreamLibraryKind _kindOf(String kind) {
  switch (kind) {
    case 'movie':
      return StreamLibraryKind.movies;
    case 'show':
      return StreamLibraryKind.shows;
    case 'artist':
      return StreamLibraryKind.music;
    default:
      return StreamLibraryKind.other;
  }
}

Map<String, String> _ids(Map<String, dynamic> media) {
  return {
    for (final section
        in (media['libraries'] as List).cast<Map<String, dynamic>>())
      section['title'] as String: section['id'] as String,
  };
}

/// The scenario's own commands, through the lab's control plane so the test is
/// repeatable on its own. Same shape as the other testlab e2e files.
Future<void> _scenario(String action, String name) async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/testlab.py',
    'scenario',
    action,
    name,
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail(
      'testlab.py scenario $action $name failed: '
      '${result.stderr}\n${result.stdout}',
    );
  }
}

/// The spike: a real session, the server's answer to a stop, and the clean up.
Future<void> _spike() async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/plex_play.py',
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail('plex_play.py failed: ${result.stderr}\n${result.stdout}');
  }
}

/// One playback session, left playing: S-07 stops it through the app.
Future<void> _play() async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/plex_play.py',
    'play',
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail('plex_play.py play failed: ${result.stderr}\n${result.stdout}');
  }
}

/// A refused stop cannot take the session down, so the spike ends it.
Future<void> _stop() async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/plex_play.py',
    'stop',
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail('plex_play.py stop failed: ${result.stderr}\n${result.stdout}');
  }
}

/// The lab's credentials and contract files, and the app's settings.
class _Lab {
  _Lab._(this._values, this._directory);

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
    return _Lab._(values, file.parent);
  }

  final Map<String, String> _values;
  final Directory _directory;

  static const plexUrl = 'http://127.0.0.1:32400';

  String _value(String name) {
    final value = _values[name];
    if (value == null || value.isEmpty) {
      fail('The lab credentials have no $name: run the bootstrap again.');
    }
    return value;
  }

  /// The scenario's contract, read from beside the credentials file.
  Map<String, dynamic> contract(String name) {
    final file = File('${_directory.path}/$name');
    if (!file.existsSync()) {
      fail(
        'No $name under ${_directory.path}: run the plex-media scenario and '
        'plex_play.py first.',
      );
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  ServiceInstance plexConnection() => ServiceInstance(
    id: ServiceInstance.primaryIdFor(ServiceKey.plex),
    service: ServiceKey.plex,
    url: plexUrl,
    credential: _value('CUPOLA_TESTLAB_PLEX_TOKEN'),
  );

  /// One container holding the real client, on the owner's token, with a
  /// client identifier of its own so its device row is never the app's.
  Future<ProviderContainer> container() async {
    final overrides = await settingsScopeOverrides(
      customize: (settings) => settings
          .copyWithInstance(plexConnection())
          .copyWith(plexClientId: 'cupola-testlab-plex-e2e'),
    );
    return ProviderContainer(overrides: overrides);
  }

  Future<void> waitForPlex() async {
    for (var attempt = 0; attempt < 90; attempt++) {
      try {
        if (await _rawStatus() == 200) return;
      } on IOException {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    fail('The lab Plex did not come up at $plexUrl');
  }

  Future<int> _rawStatus() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$plexUrl/identity'));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }
}
