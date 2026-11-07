import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_slab.dart';

import 'package:cupola/features/stream/presentation/stream_watching.dart';

import '../../test_helpers/settings_scope.dart';

/// The Overview of a media server, on both servers.
///
/// One screen parameterised by `ServiceKey`, so most of what is asserted here is
/// asserted twice, and the two cases where the servers genuinely differ (the On
/// deck rail and the Server region, both Plex-only) are asserted as *absences*
/// on Jellyfin, because an empty region there would be a claim the client never
/// made.
void main() {
  testWidgets('Jellyfin draws the regions the mobile board keeps', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.jellyfin);

    expect(find.byType(ServiceKpiPeek), findsOneWidget);
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Now playing', 'Continue watching', 'Recently added', 'Libraries'],
    );

    // Plex's word for the first shelf is its own.
    expect(find.text('On deck'), findsNothing);
    // And the board's other Jellyfin regions are absent rather than stubbed:
    // no `/ScheduledTasks`, no `/System/ActivityLog/Entries`.
    expect(find.text('Scheduled tasks'), findsNothing);
    expect(find.textContaining('Mb/s'), findsNothing);
  });

  testWidgets('Plex draws its own two regions on top of the shared ones', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.plex);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Now playing', 'On deck', 'Recently added', 'Libraries', 'Server'],
    );
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.plex);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      [
        // Now playing leads to the tab that lists the playbacks.
        'opens the Plex Activities tab',
        // On deck and what was added are whole in Activities.
        'opens the Plex Activities tab',
        'opens the Plex Activities tab',
        'opens the Plex Libraries tab',
        // Server has nowhere to go: Plex's bar has no tab that owns connection
        // settings, and a link named after a tab that does not exist is a
        // promise the app cannot keep.
        null,
      ],
    );
  });

  testWidgets('one playback is drawn large, with what is left and the '
      'controls Jellyfin allows', (tester) async {
    await _pump(
      tester,
      service: ServiceKey.jellyfin,
      sessions: [_session('a', 'Anna', 'Sintel')],
    );

    expect(find.byType(StreamSessionFeature), findsOneWidget);
    expect(find.byType(StreamSessionLine), findsNothing);
    expect(find.text('Anna\u00A0· Sintel'), findsOneWidget);
    expect(find.text('9\u00A0min left'), findsOneWidget);
    expect(find.byTooltip('Pause this playback'), findsOneWidget);
    expect(find.byTooltip('Send a message to this player'), findsOneWidget);
    expect(find.byTooltip('Stop this playback'), findsOneWidget);
    // The wide picture is the server's own, through its key.
    final picture = tester.widget<StreamSessionFeature>(
      find.byType(StreamSessionFeature),
    );
    expect(picture.picture?.url, contains('/Images/Backdrop/0'));
    expect(picture.picture?.headers, isNotEmpty);
    // The way to the tab that lists the playbacks.
    expect(
      tester
          .widget<SectionHeader>(
            find.widgetWithText(SectionHeader, 'Now playing'),
          )
          .semanticHint,
      'opens the Jellyfin Activity tab',
    );
  });

  testWidgets('several playbacks are drawn as lines, one sentence each', (
    tester,
  ) async {
    await _pump(
      tester,
      service: ServiceKey.plex,
      sessions: [
        _session('a', 'Giulia', 'Spring'),
        _session('b', 'Tom', 'Big Buck Bunny'),
      ],
    );

    expect(find.byType(StreamSessionFeature), findsNothing);
    expect(find.byType(StreamSessionLine), findsNWidgets(2));
    expect(find.text('Giulia\u00A0· Spring'), findsOneWidget);
    expect(find.text('Tom\u00A0· Big Buck Bunny'), findsOneWidget);
    // Plex stops and nothing else: no pause, no message.
    expect(find.byTooltip('Pause this playback'), findsNothing);
    expect(find.byTooltip('Stop this playback'), findsNWidgets(2));
    expect(
      find.semantics.byLabel('Spring'),
      findsOneWidget,
      reason: 'a line speaks once, by its title',
    );
  });

  testWidgets('playbacks do not overflow at an accessibility reading size', (
    tester,
  ) async {
    for (final sessions in [
      [_session('a', 'Anna', 'Sintel')],
      [_session('a', 'Giulia', 'Spring'), _session('b', 'Tom', 'Elephants')],
    ]) {
      await _pump(
        tester,
        service: ServiceKey.jellyfin,
        sessions: sessions,
        textScaleFactor: 2.0,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the Libraries header counts rooms and names the one scanning', (
    tester,
  ) async {
    await _pump(
      tester,
      service: ServiceKey.plex,
      libraries: [
        _library(name: 'Movies', refreshing: true),
        _library(name: 'TV'),
        _library(name: 'Music'),
      ],
    );

    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Libraries'),
    );
    expect(header.subtitle, '3 libraries\u00A0· Movies scanning');
  });

  testWidgets('a scan in progress speaks one sentence', (tester) async {
    await _pump(
      tester,
      service: ServiceKey.jellyfin,
      libraries: [_library(name: 'Films', refreshing: true)],
    );

    // One node for the whole row, with the layout's dots read as pauses, not
    // three fragments a screen reader walks separately.
    expect(find.semantics.byLabel('Films, Movies, Scanning'), findsOneWidget);
  });

  testWidgets('a library list that never answered reads `—` and never 0', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.jellyfin, failLibraries: true);

    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Libraries'),
    );
    // Never "0 libraries" over a question nobody got an answer to: the reading
    // a user would act on is the opposite one.
    expect(header.subtitle, '—');
    expect(find.textContaining('0 libraries'), findsNothing);
    // The failed region says so in its own slot…
    expect(find.byType(InlineErrorRetry), findsOneWidget);
    // …and Now playing above it still drew.
    expect(find.text('Now playing'), findsOneWidget);
  });

  testWidgets('a Jellyfin server at rest still names its rooms', (
    tester,
  ) async {
    await _pump(
      tester,
      service: ServiceKey.jellyfin,
      libraries: [
        _library(name: 'Films'),
        _library(name: 'Kids TV'),
      ],
    );

    // Nothing playing and no scan running is the *majority* state of a home
    // server, so it is the typical view of this page rather than the
    // pathological one. `getLibraries` already answered names and kinds, so
    // the region says what is on the shelf instead of only whether a broom is
    // being pushed across it.
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Kids TV'), findsOneWidget);
    // Jellyfin exposes no per-library scan timestamp, so null means "not
    // reported" and "never scanned" at once. The region says neither.
    expect(find.textContaining('never'), findsNothing);
    // The count is still reported, because that one is free.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Libraries'),
    );
    expect(header.subtitle, '2 libraries');
  });

  testWidgets('a server that answered and holds nothing says so, whatever '
      'the probe is doing', (tester) async {
    // The probe still in flight (or reading offline) no longer turns an
    // answered empty shelf into "The server did not answer": the libraries
    // read throws on its own failure, so an empty list is only ever an answer.
    await _pump(tester, service: ServiceKey.jellyfin, answering: false);

    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Libraries'),
    );
    // The empty note says it in words; a count of nothing over it would say
    // it twice (the Overview draws no `0` under a heading).
    expect(header.subtitle, isNull);
    expect(find.text('No libraries on this server'), findsOneWidget);
    expect(find.text('The server did not answer'), findsNothing);
  });

  testWidgets('a server that answered and holds nothing says so', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.jellyfin);

    // The other half of the same pair: the probe landed, the server is up, and
    // an empty shelf is a fact it genuinely stated.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Libraries'),
    );
    // The empty note says it in words; a count of nothing over it would say
    // it twice (the Overview draws no `0` under a heading).
    expect(header.subtitle, isNull);
    expect(find.text('No libraries on this server'), findsOneWidget);
  });

  testWidgets('a Plex server that did not mention Plex Pass reads —', (
    tester,
  ) async {
    await _pump(
      tester,
      service: ServiceKey.plex,
      capabilities: _capabilities(subscription: null),
    );

    // `GET /` answered, and simply did not carry the attribute. An em dash says
    // the server was asked; "Not on this server" would be a claim it never
    // made, and it is the claim that decides whether a stop control appears.
    expect(
      find.semantics.byLabel('Plex Pass, stopping a stream needs it, —'),
      findsOneWidget,
    );
  });

  testWidgets('a Plex server that answered says what it answered', (
    tester,
  ) async {
    await _pump(
      tester,
      service: ServiceKey.plex,
      capabilities: _capabilities(subscription: true, multiuser: true),
    );

    expect(find.text('Living room'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    // Stated only because the server said `multiuser`, and stated as the
    // limitation it causes rather than as trivia, with a figure in the figure
    // slot, so the row reads and speaks like the three above it instead of
    // putting a bare noun phrase where a datum goes.
    expect(find.text('Owner only'), findsOneWidget);
    expect(
      find.semantics.byLabel(
        'Plex Home, Cupola reads the owner’s watch state, Owner only',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the On deck rail names the episode and how far in', (
    tester,
  ) async {
    await _pump(
      tester,
      service: ServiceKey.plex,
      onDeck: [
        // As Plex sends an episode: its own name, and the series beside it.
        _item(
          id: '12',
          title: 'Hello, Ms. Cobel',
          subtitle: 'Severance',
          progress: 0.3,
        ),
      ],
    );

    expect(find.text('Severance'), findsOneWidget);
    expect(find.textContaining('Hello, Ms. Cobel'), findsOneWidget);
    // How far in is the bar under the picture.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('a Plex with nothing part-watched rests', (tester) async {
    await _pump(tester, service: ServiceKey.plex);

    expect(find.text('Nothing part-watched'), findsOneWidget);
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      service: ServiceKey.plex,
      textScaleFactor: 3.0,
      libraries: [
        _library(
          name: 'Documentaries, Concerts And Everything Else We Keep',
          refreshing: true,
        ),
      ],
      onDeck: [
        _item(
          id: '12',
          title:
              'A Series With An Extremely Long Title That Nobody Abbreviates',
          subtitle: 'S02E05\u00A0· Woe’s Hollow',
          progress: 0.42,
        ),
      ],
      capabilities: _capabilities(subscription: true),
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.jellyfin, configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.jellyfin);
    // Nothing behind the door was built, which is the point: the client
    // providers throw "not configured", and a provider that throws is a
    // *failed* provider retrying on a backoff for a condition no waiting
    // changes. The sessions providers carry `retry: noProviderRetry` precisely
    // so a dark server is not hammered; reaching them here would undo it.
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required ServiceKey service,
  List<StreamLibrary> libraries = const [],
  List<StreamSession> sessions = const [],
  List<StreamItem> onDeck = const [],
  PlexServerCapabilities? capabilities,
  bool failLibraries = false,
  bool configured = true,
  bool answering = true,
  double textScaleFactor = 1.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final settings = configured
      ? (service == ServiceKey.jellyfin
            ? settingsWith(
                jellyfinUrl: 'http://jelly.lan:8096',
                jellyfinApiKey: 'key',
                jellyfinUserId: 'viewer-1',
              )
            : settingsWith(
                plexUrl: 'http://plex.lan:32400',
                plexToken: 'token',
              ))
      : const SettingsModel();

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch a deliberately failing region
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        // Both sessions providers: the page reads one of them, and overriding
        // the other costs nothing while keeping the harness symmetrical.
        jellyfinSessionsProvider.overrideWith((ref) async => sessions),
        plexSessionsProvider.overrideWith((ref) async => sessions),
        jellyfinLibrariesProvider.overrideWith((ref) async {
          if (failLibraries) throw Exception('libraries failed');
          return libraries;
        }),
        plexLibrariesProvider.overrideWith((ref) async {
          if (failLibraries) throw Exception('libraries failed');
          return libraries;
        }),
        streamWatchingProvider.overrideWith(
          (ref, key) async => switch (key.shelf) {
            StreamWatchingShelf.continueWatching => onDeck,
            _ => const <StreamItem>[],
          },
        ),
        // A sheet that answered, by default one that sends no flags.
        plexCapabilitiesProvider.overrideWith(
          (ref) async => capabilities ?? _capabilities(),
        ),
        // The reachability probe the identity line reads.
        serviceSummaryProvider.overrideWith(
          (ref, key) async => ServiceSummary(
            service: key,
            status: answering
                ? ServiceSummaryStatus.online
                : ServiceSummaryStatus.offline,
            host: 'media.lan',
            version: answering ? '10.10.6' : null,
          ),
        ),
        // The readout rail is not what these tests are about, and it reads the
        // sessions and libraries through providers of its own.
        serviceKpiProvider.overrideWith(
          (ref, key) async => const <ServiceKpi>[],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: StreamOverviewScreen(service: service, topPadding: 0),
      ),
    ),
  );
  if (sessions.isEmpty) {
    await tester.pumpAndSettle();
    return;
  }
  // A playback's picture shimmers while it loads, for as long as it loads.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

StreamSession _session(String id, String user, String title) => StreamSession(
  id: id,
  userName: user,
  title: title,
  subtitle: null,
  deviceLabel: 'Living room TV',
  posterPath: '/Items/$id/Images/Primary',
  backdropPath: '/Items/$id/Images/Backdrop/0',
  playMethod: StreamPlayMethod.directPlay,
  transcodeReasons: const [],
  bitrate: null,
  bitrateIsNominal: true,
  progress: 0.5,
  isPaused: false,
  remaining: const Duration(minutes: 9),
);

StreamLibrary _library({
  required String name,
  bool refreshing = false,
  DateTime? scannedAt,
}) => StreamLibrary(
  id: name,
  name: name,
  kind: StreamLibraryKind.movies,
  itemCount: null,
  lastScannedAt: scannedAt,
  isRefreshing: refreshing,
);

StreamItem _item({
  required String id,
  required String title,
  String? subtitle,
  double? progress,
}) => StreamItem(
  id: id,
  title: title,
  subtitle: subtitle,
  kind: StreamItemKind.episode,
  posterPath: null,
  year: null,
  runtimeMs: progress == null ? null : 1000,
  isPlayed: false,
  resumeOffsetMs: progress == null ? null : (progress * 1000).round(),
  unplayedChildCount: null,
);

PlexServerCapabilities _capabilities({bool? subscription, bool? multiuser}) =>
    PlexServerCapabilities(
      friendlyName: 'Living room',
      machineIdentifier: 'abc',
      version: '1.41.6',
      myPlexUsername: 'matt',
      myPlexSubscription: subscription,
      multiuser: multiuser,
      transcoderActiveVideoSessions: 0,
    );
