@Tags(['e2e'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/home/domain/now_playing.dart';
import 'package:cupola/features/jellyfin/data/media_browser_client.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';

import '../test_helpers/settings_scope.dart';

/// S-09 against the macOS lab: *Now playing* in the Home, in a media server's
/// Overview and in the Stack, with one playback and with two, a pause and a
/// stop.
///
/// **The playbacks are real sessions on the lab's Jellyfin and on its Emby,
/// and the pause and the stop are the app's own.** The whole suite runs once
/// per server ([_Server]). Each playback is opened by
/// `test/e2e/testlab/jellyfin_play.py --listen` (or `emby_play.py`), which
/// reports `Playing` and then holds the WebSocket the server relays `Playstate`
/// over. That is not
/// decoration: both commands are remote control. `POST /Sessions/{id}/Playing/
/// Pause` and `/Stop` are answered 204 when they are *dispatched*, and the
/// state only changes because the client reports `Progress` or `Stopped` back.
/// So the test sends the command through the same methods the cards call
/// (`jellyfinClientForProvider(...).pauseSession` or the Emby twin,
/// `streamClientForProvider(...).stopSession`) and then re-reads the app's providers: a pause that only
/// reached the wire, or a stop the client ignored, fails here. A paired
/// helper run without `--listen` would have made both look fine while
/// changing nothing.
///
/// **What each surface means here, and where the boundary is.** The e2e tier
/// drives clients and providers, not pixels; the pixels are the design
/// catalog's and the journeys' business. So the three surfaces are asserted
/// through the one read each of them draws from:
///
///  * the Home's `Now playing` module reads [streamActivityProvider] (and
///    [streamActivityOfflineProvider] to tell silence from emptiness), and
///    renders each row with [nowPlayingTitle] and [nowPlayingLine];
///  * the Overview's slab reads [streamSessionsForProvider], which for the
///    lens connection collapses onto [jellyfinSessionsProvider] (or
///    [embySessionsProvider]);
///  * the Stack's matrix cell reads [serviceSignalPairProvider], whose head is
///    the `Streams` figure said as `1 streaming` / `2 streaming`.
///
/// The words a person sees are asserted through the same functions the widgets
/// call, so a change of phrasing moves both sides together.
///
/// **Counts are compared with the server, not hard-coded.** The lab's servers
/// are shared with the other e2e files, and `flutter test` runs files at the
/// same time: another suite's playback can be live while this one runs.
/// [_converged] therefore waits until the three surfaces list exactly the
/// sessions the server reports, which is S-09's own verification sentence
/// ("the sessions read from the server match the cards"). In a quiet lab that
/// count is one, then two, and the assertions below read it as such.
///
/// **Jellyfin and Emby only, and why.** L8's plan makes a Plex playback a spike, and
/// `test/e2e/testlab/plex_play.py` is that spike: one fixed client identity, no
/// device of its own, no pause, and no Stop from the app (`terminate` needs
/// Plex Pass, which this server reports it does not have). So the
/// one-playback and two-playback acceptance, which needs two devices, is
/// carried by the two servers whose clients can be played for real; the Plex
/// half of S-09 stays with the spike rather than being faked here.
///
/// Prerequisites: the lab is up and seeded (`test/e2e/testlab/bootstrap.sh`)
/// and `CUPOLA_TESTLAB_CREDENTIALS_FILE` points at its credentials.
/// `CUPOLA_TESTLAB_EMBY_URL` points the Emby half at another address than the
/// lab's published one (a disposable container).
///
/// ```bash
/// export CUPOLA_TESTLAB_CREDENTIALS_FILE="$PWD/.ai/scratch/zz_testlab/state/credentials.env"
/// flutter test test/e2e/testlab_stream_sessions_e2e_test.dart \
///   --tags e2e --run-skipped
/// ```
void main() {
  for (final server in _Server.values) {
    group(server.title, () => _suite(server));
  }
}

/// The whole of S-09 against one server.
void _suite(_Server server) {
  late _Lab lab;
  ProviderContainer? container;
  // Everything this file opened, killed before the sessions are ended: a
  // helper whose socket is still up would report `Progress` over a stop and
  // put the playback back.
  final playbacks = <_Playback>[];

  setUpAll(() async {
    lab = _Lab.load(server);
    await lab.waitForServer();
    // A rerun starts from the same server state this one found, even if an
    // earlier run died between a playback and its tearDown.
    await lab.stopEveryDevice();
    container = await lab.container();
  });

  tearDown(() async {
    for (final playback in playbacks) {
      await playback.end();
    }
    playbacks.clear();
    // Every test leaves the lab with no playback of its own: a half-run test
    // must not be the next test's first session.
    await lab.stopEveryDevice();
  });

  tearDownAll(() {
    container?.dispose();
    container = null;
  });

  test(
    'one playback appears in the Home, the Overview and the Stack',
    () async {
      final live = container!;
      final playback = await _open(lab, playbacks, device: _livingRoom);
      final id = playback.id;

      final surfaces = await _converged(live, lab, present: {id});
      final row = surfaces.home.singleWhere((row) => row.session.id == id);
      expect(row.service, server.service);
      expect(row.instanceId, lab.instanceId);
      // One connection, so a row names no connection beside the service.
      expect(row.connectionName, isNull);
      expect(row.session.title, _title);
      // The Home's "where": the app composes the playing client and the device,
      // so both halves of the CLI's identity are what a row reads.
      expect(row.session.deviceLabel, contains(playback.report['client']));
      expect(row.session.deviceLabel, contains(_livingRoom));
      expect(row.session.userName, playback.report['user']);
      expect(row.session.playMethod, StreamPlayMethod.directPlay);
      expect(row.session.isPaused, isFalse);
      // The row's two lines, composed by the module's own functions.
      expect(
        nowPlayingTitle(row.session),
        [playback.report['user'], _title].join(dotSeparator),
      );
      expect(nowPlayingLine(row.session), contains(_livingRoom));
      expect(nowPlayingLine(row.session), contains('left'));

      final overview = _byId(surfaces.overview, id);
      expect(overview, isNotNull);
      expect(overview!.deviceLabel, contains(_livingRoom));
      // The Overview reads the lens connection, so the service's own cache and
      // the page are the same answer, never two reads a beat apart.
      final lens = await lab.lensSessions(live);
      expect(
        lens.map((session) => session.id).toSet(),
        surfaces.overview.map((session) => session.id).toSet(),
      );

      final figure = surfaces.stack!.primary;
      // The cell's own words: a figure and the gerund it is read with.
      expect(surfaces.home.length, greaterThanOrEqualTo(1));
      expect(figure.value, '${surfaces.home.length}');
      expect(figure.label, 'streaming');
      expect(figure.tone, StatusTone.info);
    },
  );

  test('two playbacks on two devices count as two', () async {
    final live = container!;
    final first = await _open(lab, playbacks, device: _livingRoom);
    final second = await _open(lab, playbacks, device: _kitchen, title: _music);
    // Two devices, so two rows: both servers key a session on the device, and
    // one device cannot hold two titles at once.
    expect(first.id, isNot(second.id));
    expect(first.report['deviceId'], isNot(second.report['deviceId']));

    final surfaces = await _converged(
      live,
      lab,
      present: {first.id, second.id},
    );
    final home = surfaces.home;
    expect(home.length, greaterThanOrEqualTo(2));
    final byId = {for (final row in home) row.session.id: row.session};
    expect(byId[first.id]?.title, _title);
    expect(byId[second.id]?.title, _music);
    // Each device has its own row: two rows are two playbacks, not one read
    // twice.
    final labels = home.map((row) => row.session.deviceLabel).toList();
    expect(labels.where((label) => label.contains(_livingRoom)), hasLength(1));
    expect(labels.where((label) => label.contains(_kitchen)), hasLength(1));

    expect(_byId(surfaces.overview, first.id), isNotNull);
    expect(_byId(surfaces.overview, second.id), isNotNull);

    final figure = surfaces.stack!.primary;
    expect(figure.value, '${home.length}');
    expect(figure.label, 'streaming');
    expect(figure.tone, StatusTone.info);
  });

  test('the app pauses and resumes the playback the cards read', () async {
    final live = container!;
    final playback = await _open(lab, playbacks, device: _livingRoom);
    final id = playback.id;
    await _converged(live, lab, present: {id});

    // The pause the session card sends, on the session id the card carries.
    await lab.client(live).pauseSession(id);

    final paused = await _converged(
      live,
      lab,
      present: {id},
      holds: (surfaces) =>
          _sessionIn(surfaces.home.map((row) => row.session), id)?.isPaused ==
              true &&
          _byId(surfaces.overview, id)?.isPaused == true,
    );
    final row = paused.home.singleWhere((row) => row.session.id == id);
    expect(row.session.isPaused, isTrue);
    // The row says it: the device, then `Paused`, then what is left.
    expect(nowPlayingLine(row.session), contains(StateWord.paused.label));
    // A paused playback is still a playback: the Stack counts it.
    final figure = paused.stack!.primary;
    expect(figure.value, '${paused.home.length}');
    expect(figure.tone, StatusTone.info);

    // And the same control takes it back.
    await lab.client(live).unpauseSession(id);
    final resumed = await _converged(
      live,
      lab,
      present: {id},
      holds: (surfaces) =>
          _sessionIn(surfaces.home.map((row) => row.session), id)?.isPaused ==
              false &&
          _byId(surfaces.overview, id)?.isPaused == false,
    );
    expect(_byId(resumed.overview, id)?.isPaused, isFalse);
  });

  test('the app stops the playback, and the surfaces drop it', () async {
    final live = container!;
    final playback = await _open(lab, playbacks, device: _kitchen);
    final id = playback.id;
    await _converged(live, lab, present: {id});

    // The stop the session card sends. The server relays it to the client, the
    // client reports `Stopped`, and only then does the row leave `/Sessions`.
    await live
        .read(
          streamClientForProvider((service: server.service, instanceId: '')),
        )
        .stopSession(id);

    // The client obeyed: the helper heard the server's relay and left by
    // itself, with no kill from here. The phrase is waited for, not read after
    // the exit: a pipe can deliver the last lines after the process is gone.
    await playback.waitForTranscript('playstate Stop');
    final exit = await playback.waitForExit(const Duration(seconds: 20));
    expect(
      exit,
      0,
      reason:
          'the playback helper did not leave on its own:\n'
          '${playback.transcript}',
    );

    final surfaces = await _converged(live, lab, absent: {id});
    expect(_sessionIn(surfaces.home.map((row) => row.session), id), isNull);
    expect(_byId(surfaces.overview, id), isNull);
    final figure = surfaces.stack!.primary;
    expect(figure.value, '${surfaces.home.length}');
    expect(figure.label, 'streaming');
    // In a quiet lab the stop leaves nothing playing, and zero streams is a
    // true, live reading in the resting tone: not a fault, not an absence.
    if (surfaces.home.isEmpty) {
      expect(figure.value, '0');
      expect(figure.tone, StatusTone.neutral);
    }

    // The server may still list the device as connected; what ended is the
    // playback. The app's emptiness is "nothing is playing", never "the server
    // answered nothing at all".
    final stillPlaying = (await lab.list())
        .where((session) => session['deviceId'] == playback.report['deviceId'])
        .where((session) => session['playing'] == true);
    expect(stillPlaying, isEmpty, reason: 'that device has no playback left');
  });
}

/// The two dedicated devices every test uses. Distinct names are what make two
/// rows, and they are what the Home's second line reads.
const _livingRoom = 'Living room TV';
const _kitchen = 'Kitchen iPad';

/// What the two devices watch. Both are on the lab's seed: a film with a real
/// runtime, and a track from the Discovery album.
const _title = 'Big Buck Bunny';
const _music = 'One More Time';

/// How long a server-side change may take to reach the app's next read.
const _settleTimeout = Duration(seconds: 25);

/// How long a helper stays on the socket when a test dies without ending it.
/// Its process is killed in [tearDown] anyway; this only bounds the wall clock.
const _holdSeconds = 180;

Future<_Playback> _open(
  _Lab lab,
  List<_Playback> playbacks, {
  required String device,
  String title = _title,
  int position = 30,
}) async {
  final playback = await _Playback.open(
    lab,
    device: device,
    title: title,
    position: position,
  );
  playbacks.add(playback);
  return playback;
}

/// What the three surfaces hold at one moment.
typedef _Surfaces = ({
  List<StreamActivityRow> home,
  List<StreamSession> overview,
  ServiceSignalPair? stack,
});

StreamSession? _sessionIn(Iterable<StreamSession> sessions, String id) {
  for (final session in sessions) {
    if (session.id == id) return session;
  }
  return null;
}

StreamSession? _byId(List<StreamSession> sessions, String id) =>
    _sessionIn(sessions, id);

Future<List<StreamActivityRow>> _home(ProviderContainer container) =>
    container.read(streamActivityProvider.future);

Future<List<StreamSession>> _overview(ProviderContainer container, _Lab lab) =>
    container.read(
      streamSessionsForProvider((
        service: lab.server.service,
        instanceId: lab.instanceId,
      )).future,
    );

Future<ServiceSignalPair?> _stack(ProviderContainer container, _Lab lab) =>
    container.read(serviceSignalPairProvider(lab.server.service).future);

/// Reads the three surfaces and the server together until they agree.
///
/// [present] are the sessions this test opened and [absent] the ones it ended;
/// the counts are then checked against the server's own `/Sessions`, and the
/// Stack's figure against the rows the Home lists. Retried because a playback
/// is not on the next read in the same instant, and because another e2e file
/// sharing the lab may open or end one while this runs.
Future<_Surfaces> _converged(
  ProviderContainer container,
  _Lab lab, {
  Set<String> present = const {},
  Set<String> absent = const {},
  bool Function(_Surfaces surfaces)? holds,
}) async {
  final deadline = DateTime.now().add(_settleTimeout);
  var last = 'nothing read yet';
  while (true) {
    _refresh(container, lab);
    final home = await _home(container);
    final overview = await _overview(container, lab);
    final stack = await _stack(container, lab);
    final surfaces = (home: home, overview: overview, stack: stack);

    final playing = await lab.playingCount();
    final drawn = home.map((row) => row.session.id).toSet();
    final overviewIds = overview.map((session) => session.id).toSet();
    final expected = '$playing';
    last =
        'the Home lists $drawn, the Overview $overviewIds, the Stack reads '
        '${stack?.primary.value}, the server reports $expected';

    final agrees =
        present.difference(drawn).isEmpty &&
        present.difference(overviewIds).isEmpty &&
        absent.intersection(drawn).isEmpty &&
        absent.intersection(overviewIds).isEmpty &&
        home.length == playing &&
        overview.length == playing &&
        stack?.primary.value == expected &&
        (holds?.call(surfaces) ?? true);
    if (agrees) return surfaces;

    if (DateTime.now().isAfter(deadline)) {
      fail(
        'The surfaces did not match the server within '
        '${_settleTimeout.inSeconds}s: $last',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
}

/// The reads a session change invalidates in the app: both caches behind the
/// Overview and the Home, the KPI fold behind the Stack, and the derived
/// figures. The same set `refreshStreamSessions` and the Home's own retry
/// touch, plus the two providers that fold the figures.
void _refresh(ProviderContainer container, _Lab lab) {
  lab.invalidateSessions(container);
  container.invalidate(streamSessionsForProvider);
  container.invalidate(streamActivityProvider);
  container.invalidate(streamActivityOfflineProvider);
  container.invalidate(serviceKpiProvider);
  container.invalidate(serviceSignalPairProvider);
}

/// One playback on the lab's server, as the CLI reports it and holds it.
///
/// The helper is a process, not a call, because the socket has to outlive it:
/// a command is only acted on while the client is listening, and the app's
/// re-read is what this file asserts.
class _Playback {
  _Playback._(
    this.device,
    this.title,
    this.report,
    this._process,
    this._transcript,
  );

  final String device;
  final String title;

  /// The CLI's report of the session the server made: `id`, `deviceId`,
  /// `client`, `user`, `title`, `paused`, `playing`.
  final Map<String, Object?> report;

  final Process _process;
  final StringBuffer _transcript;

  /// The server's session id, the one a card carries and a command addresses.
  String get id => report['id']! as String;

  /// Everything the helper printed, for a failure that has to explain itself.
  String get transcript => _transcript.toString();

  /// The line the helper prints once its WebSocket is open. A command sent
  /// before it is a 204 the client never acts on.
  static const _listening = 'listening on';

  static Future<_Playback> open(
    _Lab lab, {
    required String device,
    required String title,
    required int position,
  }) async {
    final process = await Process.start('python3', [
      lab.scriptPath,
      '--device',
      device,
      '--title',
      title,
      '--position',
      '$position',
      // A household member is the one watching, and the account the lab
      // seeds for it. The app reads the sessions on its administrator key.
      '--user',
      'viewer',
      '--listen',
      '--hold',
      '$_holdSeconds',
      '--json',
    ], environment: lab.environment);
    final transcript = StringBuffer();
    final errors = StringBuffer();
    final ready = Completer<void>();
    Object? report;

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          transcript.writeln(line);
          // The start report is printed before the socket opens, so the first
          // complete JSON in the transcript is the session.
          report ??= _decodeOrNull(transcript.toString());
          if (line.contains(_listening) && !ready.isCompleted) {
            ready.complete();
          }
        });
    process.stderr.transform(utf8.decoder).listen(errors.write);

    try {
      await ready.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      fail(
        'The playback helper never held its socket on $device:\n'
        '$transcript$errors',
      );
    }
    // A local, because `report` is captured by the listener above and a
    // captured variable is not promoted by the type test.
    final parsed = report;
    if (parsed is! Map) {
      process.kill(ProcessSignal.sigkill);
      fail('The playback helper reported no session on $device:\n$transcript');
    }
    return _Playback._(
      device,
      title,
      parsed.cast<String, Object?>(),
      process,
      transcript,
    );
  }

  /// Whether the helper is still there, once it has ended by itself.
  Future<int> waitForExit(Duration timeout) =>
      _process.exitCode.timeout(timeout, onTimeout: () => -1);

  /// Waits for [needle] to appear in the transcript.
  ///
  /// The helper's stdout is a pipe, so its last words can land after the
  /// process has exited: asserting on the transcript is only meaningful once
  /// the line has been waited for.
  Future<void> waitForTranscript(
    String needle, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!_transcript.toString().contains(needle)) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'The playback helper never said "$needle" on $device ($title):\n'
          '$transcript',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Ends the helper process. The session is ended separately, by the CLI's
  /// own `--stop`: a killed socket cannot report anything, which is the point.
  Future<void> end() async {
    if (!_process.kill(ProcessSignal.sigterm)) return;
    await _process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}

/// The first complete JSON object in [text], or null while it is still open.
Object? _decodeOrNull(String text) {
  try {
    return jsonDecode(text.trim());
  } on FormatException {
    return null;
  }
}

/// The two media servers this suite runs against, and what differs between
/// them: where they answer, which helper plays on them, how the lab names their
/// credentials and how the app's providers are reached.
enum _Server {
  jellyfin(
    service: ServiceKey.jellyfin,
    title: 'Jellyfin',
    publishedUrl: 'http://127.0.0.1:8096',
    urlEnvironment: 'CUPOLA_TESTLAB_JELLYFIN_URL',
    script: 'test/e2e/testlab/jellyfin_play.py',
    tokenName: 'CUPOLA_TESTLAB_JELLYFIN_TOKEN',
    viewerName: 'CUPOLA_TESTLAB_JELLYFIN_USER_ID',
  ),
  emby(
    service: ServiceKey.emby,
    title: 'Emby',
    publishedUrl: 'http://127.0.0.1:8097',
    urlEnvironment: 'CUPOLA_TESTLAB_EMBY_URL',
    script: 'test/e2e/testlab/emby_play.py',
    tokenName: 'CUPOLA_TESTLAB_EMBY_TOKEN',
    viewerName: 'CUPOLA_TESTLAB_EMBY_USER_ID',
  );

  const _Server({
    required this.service,
    required this.title,
    required this.publishedUrl,
    required this.urlEnvironment,
    required this.script,
    required this.tokenName,
    required this.viewerName,
  });

  final ServiceKey service;
  final String title;

  /// The address the lab publishes the server on. The direct port, as the
  /// other provider-level e2e suites use; the Toxiproxy port exists for
  /// faults, and a session is the same session on either.
  final String publishedUrl;

  /// The variable a run points at another address with, for the helper and
  /// for this file alike (a disposable container).
  final String urlEnvironment;
  final String script;

  /// The lab's credential names for the app's connection: the token, and the
  /// user id the app reads the server as.
  final String tokenName;
  final String viewerName;

  /// Where the API lives under the address: Emby answers under `/emby`.
  String get basePath => this == _Server.emby ? '/emby' : '';

  /// How many seconds of silence make a session "not playing" for the app:
  /// Jellyfin is asked for a window, Emby is filtered on the answer.
  static const activeWindowSeconds = 180;
}

/// The lab: the app's settings for one server, and the playback CLI.
class _Lab {
  _Lab._(this.server, this._values, this._credentialsPath);

  final _Server server;

  /// The server's address: the lab's published one, unless the environment
  /// names another.
  String get url {
    final named = Platform.environment[server.urlEnvironment];
    return named == null || named.isEmpty ? server.publishedUrl : named;
  }

  final Map<String, String> _values;

  /// Where the bootstrap wrote the credentials. The playback CLI reads its own
  /// copy of that file, so pointing it at the same state directory keeps the
  /// two from talking to different labs.
  final String _credentialsPath;

  String get instanceId => ServiceInstance.primaryIdFor(server.service);

  String get scriptPath => File(server.script).absolute.path;

  Map<String, String> get environment => {
    'CUPOLA_TESTLAB_STATE_DIR': File(_credentialsPath).parent.path,
    server.urlEnvironment: url,
  };

  ServiceInstance connection() => ServiceInstance(
    id: instanceId,
    service: server.service,
    url: url,
    credential: _required(server.tokenName),
    viewerId: _required(server.viewerName),
  );

  /// The app's providers over settings holding the lab's server, with a real
  /// settings service behind them.
  Future<ProviderContainer> container() async {
    final overrides = await settingsScopeOverrides(
      customize: (settings) => settings.copyWithInstance(connection()),
    );
    return ProviderContainer(overrides: overrides);
  }

  /// The client the session card's commands go through, for the lens
  /// connection. Both servers' clients are the one shared client.
  MediaBrowserClient client(ProviderContainer container) => switch (server) {
    _Server.jellyfin => container.read(jellyfinClientForProvider('')),
    _Server.emby => container.read(embyClientForProvider('')),
  };

  /// Drops the app's own cache of this server's sessions, which the Overview
  /// and the Home both fold.
  void invalidateSessions(ProviderContainer container) => switch (server) {
    _Server.jellyfin => container.invalidate(jellyfinSessionsProvider),
    _Server.emby => container.invalidate(embySessionsProvider),
  };

  /// The lens connection's sessions, from the server's own provider.
  Future<List<StreamSession>> lensSessions(ProviderContainer container) =>
      switch (server) {
        _Server.jellyfin => container.read(jellyfinSessionsProvider.future),
        _Server.emby => container.read(embySessionsProvider.future),
      };

  /// Every session the server knows about, playing or connected and idle.
  Future<List<Map<String, Object?>>> list() async {
    final answer = await _run(['--list', '--json']);
    return (answer as List).cast<Map<String, Object?>>();
  }

  /// How many playbacks the server reports, read the way the app reads them:
  /// active within three minutes and carrying a `NowPlayingItem`.
  ///
  /// Not `list()`: that asks for every session the server still remembers, and
  /// the lab can carry one whose client went away, which has a title and no
  /// activity for hours. The app's own read already ignores those, so the count
  /// to agree with is this one. Jellyfin is asked for the window; Emby takes no
  /// such query, so the same window is applied to `LastActivityDate` here, the
  /// way its dialect applies it.
  Future<int> playingCount() async {
    final client = HttpClient();
    try {
      final isEmby = server == _Server.emby;
      final request = await client.getUrl(
        Uri.parse(
          isEmby
              ? '$url${server.basePath}/Sessions'
              : '$url/Sessions?activeWithinSeconds='
                    '${_Server.activeWindowSeconds}',
        ),
      );
      final token = _required(server.tokenName);
      if (isEmby) {
        request.headers.set('X-Emby-Token', token);
      } else {
        request.headers.set('Authorization', 'MediaBrowser Token="$token"');
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        fail('${server.title} answered ${response.statusCode} for /Sessions');
      }
      final sessions = jsonDecode(body);
      if (sessions is! List) {
        fail('${server.title} answered no session list for /Sessions');
      }
      final cutoff = DateTime.now().toUtc().subtract(
        const Duration(seconds: _Server.activeWindowSeconds),
      );
      return sessions.where((session) {
        if (session is! Map || session['NowPlayingItem'] is! Map) return false;
        if (!isEmby) return true;
        final at = DateTime.tryParse('${session['LastActivityDate']}');
        return at == null || !at.toUtc().isBefore(cutoff);
      }).length;
    } finally {
      client.close(force: true);
    }
  }

  /// Ends the playback on the devices this suite uses, through the CLI's own
  /// `--stop`. A device the server no longer holds answers `stopped: false`
  /// and exits zero, so this is idempotent rather than tolerant of a broken
  /// lab.
  Future<void> stopEveryDevice() async {
    for (final device in const [_livingRoom, _kitchen]) {
      await _run(['--device', device, '--stop', '--json']);
    }
  }

  /// Waits for the lab's server to answer the unauthenticated probe the
  /// settings screen uses, so a lab that is down fails with its own sentence
  /// rather than as a mystery in the first playback.
  Future<void> waitForServer() async {
    final client = HttpClient();
    try {
      for (var attempt = 0; attempt < 30; attempt++) {
        try {
          final request = await client.getUrl(
            Uri.parse('$url${server.basePath}/System/Info/Public'),
          );
          final response = await request.close();
          await response.drain<void>();
          if (response.statusCode == 200) return;
        } on IOException {
          // Not up yet.
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      client.close(force: true);
    }
    fail('${server.title} did not answer at $url: bring the lab up first');
  }

  /// Runs the playback CLI to completion and decodes its `--json` answer. The
  /// CLI never prints the token or the household member's password, so its
  /// error text is safe to carry into a failure.
  Future<Object?> _run(List<String> arguments) async {
    final script = File(scriptPath);
    if (!script.existsSync()) {
      fail('Missing $script: the playbacks of L8 are driven by it');
    }
    final result = await Process.run('python3', [
      script.path,
      ...arguments,
    ], environment: environment);
    if (result.exitCode != 0) {
      final error = '${result.stderr}'.trim();
      fail(
        '${server.script} ${arguments.join(' ')} failed with '
        '${result.exitCode}: $error',
      );
    }
    final text = '${result.stdout}'.trim();
    try {
      return jsonDecode(text);
    } on FormatException {
      fail('${server.script} ${arguments.join(' ')} printed no JSON: $text');
    }
  }

  static _Lab load(_Server server) {
    final path = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
    if (path == null || path.isEmpty) {
      fail(
        'CUPOLA_TESTLAB_CREDENTIALS_FILE must point to the bootstrap output '
        '(.ai/scratch/zz_testlab/state/credentials.env)',
      );
    }
    final file = File(path);
    if (!file.existsSync()) fail('Missing testlab credentials file: $path');
    final values = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      values[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return _Lab._(server, values, path);
  }

  String _required(String name) {
    final value = _values[name];
    if (value == null || value.isEmpty) {
      fail('The lab credentials have no $name: run the bootstrap again.');
    }
    return value;
  }
}
