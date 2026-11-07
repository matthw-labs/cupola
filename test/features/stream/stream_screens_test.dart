import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/cross_service_action.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/presentation/stream_libraries_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';

import '../../test_helpers/settings_scope.dart';

final _configured = settingsWith(
  jellyfinUrl: 'http://jelly.local:8096',
  jellyfinApiKey: 'key',
  jellyfinUserId: 'viewer-1',
);

StreamSession _session({
  String id = 's1',
  String user = 'Matt',
  String title = 'The Fellowship of the Ring',
  StreamPlayMethod method = StreamPlayMethod.directPlay,
  List<String> reasons = const [],
  int? bitrate = 24305112,
  bool nominal = true,
  double? progress = 0.34,
  bool paused = false,
}) => StreamSession(
  id: id,
  userName: user,
  title: title,
  subtitle: null,
  deviceLabel: 'Infuse on Apple TV',
  posterPath: null,
  playMethod: method,
  transcodeReasons: reasons,
  bitrate: bitrate,
  bitrateIsNominal: nominal,
  progress: progress,
  isPaused: paused,
);

const _library = StreamLibrary(
  id: 'lib-1',
  name: 'Films',
  kind: StreamLibraryKind.movies,
  itemCount: 412,
  lastScannedAt: null,
  isRefreshing: false,
);

/// The Overview's session region, hosted the way the Overview will host it.
///
/// **A section and a screen instead of one board.** The single Stream page was
/// split by the tab model: the libraries became the Libraries tab and the
/// sessions became a section the Overview composes. The rules asserted below did
/// not move with them: a transcode is still amber, an idle room is still a
/// quiet line, so these cases pump the piece that now owns each rule rather
/// than a page that no longer exists.
Widget _nowPlayingHost(ServiceKey service) => Scaffold(
  body: Consumer(
    builder: (context, ref, _) => ListView(
      children: [
        StreamNowPlayingSection(
          service: service,
          sessions: service == ServiceKey.jellyfin
              ? ref.watch(jellyfinSessionsProvider)
              : ref.watch(plexSessionsProvider),
        ),
      ],
    ),
  ),
);

Future<void> _pumpNowPlaying(
  WidgetTester tester, {
  List<StreamSession> sessions = const [],
  SettingsModel? settings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => (settings ?? _configured),
        ),
        jellyfinSessionsProvider.overrideWith((ref) async => sessions),
      ],
      child: MaterialApp(home: _nowPlayingHost(ServiceKey.jellyfin)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpLibraries(
  WidgetTester tester, {
  List<StreamLibrary> libraries = const [_library],
  SettingsModel? settings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => (settings ?? _configured),
        ),
        jellyfinLibrariesProvider.overrideWith((ref) async => libraries),
      ],
      child: const MaterialApp(
        home: StreamLibrariesScreen(service: ServiceKey.jellyfin),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _plexConfigured = settingsWith(
  plexUrl: 'http://plex.local:32400',
  plexToken: 'token',
);

/// A Plex server whose capability sheet the test chooses.
///
/// `null` is the shape that matters most here: the sheet has not resolved yet,
/// or the build simply does not send `myPlexSubscription`.
Future<void> _pumpPlexNowPlaying(
  WidgetTester tester, {
  List<StreamSession> sessions = const [],
  PlexServerCapabilities? capabilities,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => _plexConfigured),
        plexSessionsProvider.overrideWith((ref) async => sessions),
        // Null is a sheet that has not answered yet.
        plexCapabilitiesProvider.overrideWith(
          (ref) => capabilities == null
              ? Completer<PlexServerCapabilities>().future
              : Future.value(capabilities),
        ),
      ],
      child: MaterialApp(home: _nowPlayingHost(ServiceKey.plex)),
    ),
  );
  await tester.pumpAndSettle();
}

PlexServerCapabilities _capabilities({bool? subscription}) =>
    PlexServerCapabilities(
      friendlyName: 'tower',
      machineIdentifier: 'abc',
      version: '1.41',
      myPlexUsername: 'matt',
      myPlexSubscription: subscription,
      multiuser: true,
      transcoderActiveVideoSessions: 0,
    );

/// The colour the tone authority resolves for [tone] on a filled card.
///
/// Read through `statusToneColor` rather than compared with a literal: the rule
/// under test is "the delivery method is drawn in its semantic tone", and the
/// tone's actual value moves with the theme and with the contrast walk. A hex
/// here would be asserting the palette instead of the rule.
Color _toneOn(WidgetTester tester, Finder anchor, StatusTone tone) {
  final colorScheme = Theme.of(tester.element(anchor)).colorScheme;
  return statusToneColor(
    colorScheme,
    tone,
    surface: colorScheme.surfaceContainer,
  );
}

/// Asserts that [name] is on screen as a control a screen reader can reach and
/// can name.
///
/// Checked on the semantics node rather than on the widget: an icon-only button
/// carries its name in `SemanticsNode.tooltip`, which is what both screen
/// readers speak, and the whole point of the check is that the node exists at
/// all: the card's readout sits under `excludeSemantics`, which is exactly the
/// thing that used to swallow these.
void expectReachableControl(WidgetTester tester, String name) {
  final finder = find.byTooltip(name);
  expect(finder, findsOneWidget, reason: '"$name" must be on screen');
  expect(
    tester.getSemantics(finder),
    isSemantics(tooltip: name, isButton: true, hasTapAction: true),
  );
}

void expectNoControl(String name) => expect(
  find.byTooltip(name),
  findsNothing,
  reason: '"$name" must be absent',
);

void main() {
  group('Now playing', () {
    testWidgets('idle is a quiet line, not an error and not an empty state', (
      tester,
    ) async {
      await _pumpNowPlaying(tester);

      // Nobody watching is the majority state on a home server and the normal
      // daily condition, so it must not read as a failure.
      expect(find.text('Nobody is watching right now'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
    });

    testWidgets('never prints an aggregate outbound total', (tester) async {
      await _pumpNowPlaying(
        tester,
        sessions: [
          _session(bitrate: 8000000),
          _session(id: 's2', user: 'Sara', bitrate: 12000000),
        ],
      );

      // Neither server reports measured throughput, so summing the two rows and
      // presenting 20 Mbps as the box's egress would be a fabricated figure. The
      // per-session values are shown; no total exists anywhere on the page.
      expect(find.textContaining('20\u00A0Mbps'), findsNothing);
      expect(find.byType(StreamSessionCard), findsNWidgets(2));
    });

    testWidgets('a nominal rate is hedged rather than stated as measured', (
      tester,
    ) async {
      await _pumpNowPlaying(tester, sessions: [_session(bitrate: 8400000)]);

      // "~" carries the same hedge the spoken form says as "about": this is the
      // file's own bitrate, not what is on the wire.
      expect(find.text('~8.4\u00A0Mbps'), findsOneWidget);
      expect(find.text('8.4\u00A0Mbps'), findsNothing);
    });

    testWidgets('a transcode names why, in the warning tone', (tester) async {
      await _pumpNowPlaying(
        tester,
        sessions: [
          _session(
            method: StreamPlayMethod.transcode,
            reasons: const ["client can't decode HEVC"],
            nominal: false,
          ),
        ],
      );

      // The focal moment of the whole surface: both web UIs bury this, and it is
      // the fact that turns "the box is busy" into something actionable.
      expect(find.text("client can't decode HEVC"), findsOneWidget);
      expect(find.text('Transcode'), findsOneWidget);

      // CHANGED: this used to assert the raw `AppColors.warning` constant. The
      // card no longer paints a palette entry; it paints the tone
      // `StreamSession.deliveryTone` resolves, walked for contrast against the
      // card's own fill, because raw warning measures 1.39:1 on paper and is
      // effectively invisible in daylight. The *rule* is unchanged: a transcode
      // is amber.
      final reason = tester.widget<Text>(find.text("client can't decode HEVC"));
      expect(
        reason.style?.color,
        _toneOn(tester, find.text('Transcode'), StatusTone.warning),
      );
    });

    testWidgets('a direct play is green, not merely not-amber', (tester) async {
      await _pumpNowPlaying(tester, sessions: [_session()]);

      // CHANGED from "is not painted as a problem", which passed while the
      // label sat in neutral `onSurfaceVariant` and said nothing at all. Direct
      // play is the complete-and-working arm of the tone rule and is drawn in
      // it: the board's good state has to be legible as good.
      final label = tester.widget<Text>(find.text('Direct play'));
      expect(
        label.style?.color,
        _toneOn(tester, find.text('Direct play'), StatusTone.success),
      );
      expect(
        label.style?.color,
        isNot(_toneOn(tester, find.text('Direct play'), StatusTone.warning)),
      );
    });

    testWidgets('a direct stream is not a fault', (tester) async {
      await _pumpNowPlaying(
        tester,
        sessions: [
          _session(
            method: StreamPlayMethod.directStream,
            reasons: const ['container rewrap to MKV'],
          ),
        ],
      );

      // Amber means a fault, and a rewrap is not one: the video is untouched.
      // It carries an explanation, which is why the reason cannot be the gate.
      final label = tester.widget<Text>(find.text('Direct stream'));
      expect(
        label.style?.color,
        _toneOn(tester, find.text('Direct stream'), StatusTone.success),
      );
    });

    testWidgets('every session control is reachable by a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpNowPlaying(tester, sessions: [_session()]);

      // The card wraps its four text lines in one `excludeSemantics` node so
      // they are read as a sentence rather than as fragments, and that node
      // used to swallow the stop button with them, leaving a control that was
      // on screen, tappable by a pointer and absent from the traversal. The
      // readout is one node; the controls are their own.
      expectReachableControl(tester, 'Stop this playback');
      expectReachableControl(tester, 'Pause this playback');
      expectReachableControl(tester, 'Send a message to this player');
      handle.dispose();
    });

    testWidgets('session controls are never capability-gated', (tester) async {
      // A non-administrator Jellyfin token is only ever shown sessions it may
      // control, so there is no refusal to gate against; dimming these would
      // dim controls that work. A shared account's Plex token is refused the
      // sessions themselves, so a session on screen is one the owner's token
      // read. Neither draws a capability gate on a session control.
      final handle = tester.ensureSemantics();
      for (final pump in [
        () => _pumpNowPlaying(tester, sessions: [_session()]),
        () => _pumpPlexNowPlaying(tester, sessions: [_session()]),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await pump();
        expect(find.byType(CapabilityGatedAction), findsNothing);
        final stop = find.byTooltip('Stop this playback');
        if (stop.evaluate().isEmpty) continue;
        expect(tester.getSemantics(stop).hint, isEmpty);
        expect(
          find.ancestor(of: stop, matching: find.byType(Opacity)),
          findsNothing,
        );
      }
      handle.dispose();
    });

    testWidgets('a paused session offers resume, named for what it does', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpNowPlaying(tester, sessions: [_session(paused: true)]);

      // "Pause" on an already-paused session is the one label that can be read
      // two ways; the control is named for the tap, not for the state.
      expectReachableControl(tester, 'Resume this playback');
      expectNoControl('Pause this playback');
      handle.dispose();
    });

    testWidgets('the transcode reason survives an accessibility text size', (
      tester,
    ) async {
      // The reason is the longest string on the card and the one an earlier
      // single-line design would have ellipsised first, which would have eaten
      // exactly the string the surface exists to show.
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            jellyfinSessionsProvider.overrideWith(
              (ref) async => [
                _session(
                  method: StreamPlayMethod.transcode,
                  reasons: const [
                    'client cannot decode HEVC\u00A0· audio downmix to stereo',
                  ],
                ),
              ],
            ),
          ],
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: MaterialApp(home: _nowPlayingHost(ServiceKey.jellyfin)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('client cannot decode HEVC\u00A0· audio downmix to stereo'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in the light theme without exception', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            jellyfinSessionsProvider.overrideWith(
              (ref) async => [_session(method: StreamPlayMethod.transcode)],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme(),
            home: _nowPlayingHost(ServiceKey.jellyfin),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('the Libraries tab', () {
    testWidgets('the Libraries tab counts rooms, never their contents', (
      tester,
    ) async {
      await _pumpLibraries(
        tester,
        libraries: const [
          _library,
          StreamLibrary(
            id: 'lib-2',
            name: 'Shows',
            kind: StreamLibraryKind.shows,
            // Carried by the model and deliberately not drawn: nothing calls
            // `getLibraryItemCount`, so a figure here would be invented.
            itemCount: 86,
            lastScannedAt: null,
            isRefreshing: false,
          ),
        ],
      );

      // Decision 21: a per-library count is one extra round trip each, so what
      // this list says is how many rooms there are, free out of the single
      // `getLibraries` response. The count itself is unbuilt, and an unbuilt
      // figure prints nothing rather than 0. The scanning half of that line is
      // asserted on `streamLibrariesSummary` itself, because a live scan spins
      // an indicator that never settles.
      expect(find.text('2 libraries'), findsOneWidget);
      expect(find.textContaining('items'), findsNothing);
    });

    testWidgets('an unconfigured server placeholders rather than erroring', (
      tester,
    ) async {
      // A tab is arrived at routinely on a server that was never set up, and
      // the check has to happen *before* the libraries provider is read: a
      // `FutureProvider` that throws "not configured" is a failed provider
      // retrying on a backoff no waiting resolves, which shows up here as a
      // pending timer at teardown.
      await _pumpLibraries(tester, settings: const SettingsModel());

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.text('Films'), findsNothing);
      expect(find.textContaining('Jellyfin'), findsWidgets);
    });
  });

  group('Plex is stop-alone, and the owner\'s own', () {
    testWidgets('pause and message are absent, because Plex cannot do them', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPlexNowPlaying(
        tester,
        sessions: [_session()],
        capabilities: _capabilities(subscription: true),
      );

      // Pause and message are Jellyfin remote-control commands relayed over the
      // socket the server already holds. Plex's player routes address the client
      // directly on the LAN, so the board keeps stop alone (absent, not dimmed):
      // a dimmed control promises a way to enable it and there is none.
      expectReachableControl(tester, 'Stop this playback');
      expectNoControl('Pause this playback');
      expectNoControl('Send a message to this player');
      handle.dispose();
    });

    testWidgets('a server that never mentions Plex Pass keeps its stop', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPlexNowPlaying(
        tester,
        sessions: [_session()],
        capabilities: _capabilities(subscription: null),
      );

      // `PlexServerCapabilities.canTerminateSessions` treats silence as
      // available on purpose, so a missing attribute hides the button on
      // nobody's server by mistake; the terminate call explains itself if it
      // comes back 401. The board used to re-derive the gate as
      // `myPlexSubscription != true` and disagree with it.
      expectReachableControl(tester, 'Stop this playback');
      handle.dispose();
    });

    testWidgets('the stop is there before the capability sheet answers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPlexNowPlaying(
        tester,
        sessions: [_session()],
        capabilities: null,
      );

      // Same defect, second population: while the sheet was unresolved the
      // control was absent and then appeared a beat later, which on a live list
      // reads as a glitch.
      expectReachableControl(tester, 'Stop this playback');
      handle.dispose();
    });

    testWidgets('a Plex Pass-less server offers no stop at all', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPlexNowPlaying(
        tester,
        sessions: [_session()],
        capabilities: _capabilities(subscription: false),
      );

      // The one case where absence is right: Plex answers a terminate on a
      // server without Plex Pass with a 401 that has nothing to do with the
      // token, which would send the user off to re-paste a credential that was
      // fine.
      expectNoControl('Stop this playback');
      handle.dispose();
    });
  });

  group('the delivery tone', () {
    test('transcode is the only fault arm', () {
      // The tone rule's five arms: amber is a fault and nothing else. A
      // re-encode is the one delivery state that costs a CPU and can stutter; a
      // rewrap and a direct play are the stack working.
      expect(
        _session(method: StreamPlayMethod.transcode).deliveryTone,
        StatusTone.warning,
      );
      expect(
        _session(method: StreamPlayMethod.directStream).deliveryTone,
        StatusTone.success,
      );
      expect(
        _session(method: StreamPlayMethod.directPlay).deliveryTone,
        StatusTone.success,
      );
    });

    test('nothing here is ever red', () {
      // Red is reserved for unreachable. A server describing a transcode is a
      // server answering, and answering rather well.
      for (final method in StreamPlayMethod.values) {
        expect(
          _session(method: method).deliveryTone,
          isNot(StatusTone.error),
          reason: '$method must not read as an outage',
        );
      }
    });
  });

  group('the Libraries summary', () {
    test('says how many rooms there are, never what is in them', () {
      expect(
        streamLibrariesSummary(total: 1, scanningName: null, scanningCount: 0),
        '1 library',
      );
      expect(
        streamLibrariesSummary(total: 5, scanningName: null, scanningCount: 0),
        '5 libraries',
      );
    });

    test('names the one library being scanned, counts several', () {
      // Naming the first of three would imply the other two are idle, which on
      // a full rescan is the opposite of what is happening.
      expect(
        streamLibrariesSummary(
          total: 5,
          scanningName: 'Films',
          scanningCount: 1,
        ),
        '5 libraries\u00A0· Films scanning',
      );
      expect(
        streamLibrariesSummary(total: 5, scanningName: null, scanningCount: 3),
        '5 libraries\u00A0· 3 scanning',
      );
    });
  });

  group('the library sort vocabulary', () {
    test('Name is first, so a library opens on the whole shelf A to Z', () {
      // The page opens on `StreamLibrarySort.values.first`'s shelf: a library
      // is browsed, not a list of what needs watch history to render.
      expect(StreamLibrarySort.values.first, StreamLibrarySort.name);
    });

    test('each order is worded for the sort control', () {
      expect(
        [for (final sort in StreamLibrarySort.values) sort.label],
        ['Name', 'Date added', 'Year'],
      );
    });
  });
}
