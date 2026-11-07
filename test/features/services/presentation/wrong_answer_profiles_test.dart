/// Something other than the service answers at its address, and the app says
/// so: on the Stack, on the service's library and in its connection test.
///
/// The case behind "Radarr and Sonarr answering, with empty libraries": a web
/// page (a proxy's default page, an address missing its base path) answered
/// every request with a 200, the probe called any 2xx answering, and every
/// list read turned the page into `[]`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<ServiceSummary> _probe(
  ConfigProfile profile,
  ServiceKey service,
  String id,
) async {
  final harness = await ProfileHarness.start(profile);
  final container = harness.container(retry: (_, _) => null);
  return container.read(
    instanceSummaryProvider((service: service, instanceId: id)).future,
  );
}

/// What the connection test says about [id] on [profile].
Future<ServiceDiagnosis> _test(ConfigProfile profile, String id) async {
  await ProfileHarness.start(profile);
  return diagnoseInstance(
    profile.connection(id).instance,
    profile.settings,
    route: ConnectionRoute.home,
  );
}

Color _amber() {
  final scheme = AppTheme.darkTheme().colorScheme;
  return statusToneColor(scheme, StatusTone.warning);
}

void main() {
  group('a web page answering for an arr', () {
    test('is a fault on the probe, never answering', () async {
      final summary = await _probe(
        Profiles.p1.withBehaviour(
          WorldIds.radarr,
          ConnectionBehaviour.servesHtmlPage,
        ),
        ServiceKey.radarr,
        WorldIds.radarr,
      );

      expect(summary.isOnline, isFalse);
      expect(summary.status, ServiceSummaryStatus.fault);
    });

    final libraries = <(String, ServiceKey, String, String, Widget)>[
      (
        'Radarr',
        ServiceKey.radarr,
        WorldIds.radarr,
        'nas.home.arpa:7878',
        const MoviesScreen(showAppBar: false),
      ),
      (
        'Sonarr',
        ServiceKey.sonarr,
        WorldIds.sonarr,
        'nas.home.arpa:8989',
        const SeriesScreen(showAppBar: false),
      ),
      (
        'Lidarr',
        ServiceKey.lidarr,
        WorldIds.lidarr,
        'nas.home.arpa:8686',
        const MusicScreen(showAppBar: false),
      ),
    ];

    for (final (name, _, id, host, screen) in libraries) {
      testWidgets('the $name library says what answered, not that it is '
          'empty', (tester) async {
        final harness = await pumpWithProfile(
          tester,
          Profiles.p1.withBehaviour(id, ConnectionBehaviour.servesHtmlPage),
          child: screen,
        );

        expect(find.byType(ServiceOfflineState), findsOneWidget);
        expect(find.text('$name is not at this address'), findsOneWidget);
        expect(find.textContaining('library is empty'), findsNothing);
        final glyph = tester.widget<Icon>(
          find
              .descendant(
                of: find.byType(ServiceOfflineState),
                matching: find.byType(Icon),
              )
              .first,
        );
        expect(glyph.color, _amber());
        expect(
          find.text(
            'A web page answered at $host instead of $name.\n'
            'If $name sits under a path, add it: http://$host/'
            '${name.toLowerCase()}',
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Check the address'),
          findsOneWidget,
        );

        await harness.unmount(tester);
      });
    }

    testWidgets('Home, Settings and the library say one thing about it', (
      tester,
    ) async {
      final profile = Profiles.p1.withBehaviour(
        WorldIds.radarr,
        ConnectionBehaviour.servesHtmlPage,
      );
      final harness = await pumpWithProfile(
        tester,
        profile,
        child: const MoviesScreen(showAppBar: false),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MoviesScreen)),
      );
      // Asked in real time: the probe and the test run their own deadlines.
      final (summary, diagnosis) = (await tester.runAsync(
        () async => (
          await container.read(
            instanceSummaryProvider((
              service: ServiceKey.radarr,
              instanceId: WorldIds.radarr,
            )).future,
          ),
          await diagnoseInstance(
            profile.connection(WorldIds.radarr).instance,
            profile.settings,
            route: ConnectionRoute.home,
          ),
        ),
      ))!;

      final home = describeFailureOf(ServiceKey.radarr, summary.failure);
      final settings = describeConnection(
        ServiceKey.radarr,
        status: diagnosis.status,
        reason: diagnosis.reason,
        gateway: diagnosis.gateway,
      );
      const sentence =
          'A web page answered at nas.home.arpa:7878 instead of Radarr.\n'
          'If Radarr sits under a path, add it: http://nas.home.arpa:7878/radarr';

      // Home: the summary's own words.
      expect(home.headline, 'Radarr is not at this address');
      expect(home.label, 'API not at this address');
      expect(home.remedy, 'Check the address');
      expect(failureMessageOf(ServiceKey.radarr, summary.failure), sentence);
      // Settings: the same label and sentence.
      expect(settings.label, home.label);
      expect(diagnosis.messageFor(ServiceKey.radarr), sentence);
      // The library: the same headline, sentence and remedy on screen.
      expect(find.text(home.headline), findsOneWidget);
      expect(find.text(sentence), findsOneWidget);
      expect(find.widgetWithText(FilledButton, home.remedy!), findsOneWidget);

      await harness.unmount(tester);
    });

    test('a body that is not a page and does not decode is unreadable, on '
        'Home and in Settings alike', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/system/status',
        (_) => NetworkReply.text('{"appName": "Radarr", "vers'),
      );
      final container = harness.container(retry: (_, _) => null);
      final summary = await container.read(
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: WorldIds.radarr,
        )).future,
      );
      final diagnosis = await diagnoseInstance(
        Profiles.p1.connection(WorldIds.radarr).instance,
        Profiles.p1.settings,
        route: ConnectionRoute.home,
      );

      expect(summary.failureReason, ServiceFailureReason.invalidResponse);
      expect(
        describeFailureOf(ServiceKey.radarr, summary.failure).headline,
        describeUnreadable(ServiceKey.radarr),
      );
      expect(diagnosis.reason, ServiceFailureReason.invalidResponse);
      expect(
        diagnosis.messageFor(ServiceKey.radarr),
        failureMessageOf(ServiceKey.radarr, summary.failure),
      );
    });
  });

  group('SABnzbd\'s lists are a fault, not empty, when SABnzbd did not '
      'answer them', () {
    Future<Object> failureOf(
      ConfigProfile profile,
      ProviderListenable<Future<Object?>> provider, {
      void Function(ProfileNetwork network)? routes,
    }) async {
      final harness = await ProfileHarness.start(profile);
      routes?.call(harness.network);
      final container = harness.container(retry: (_, _) => null);
      try {
        await container.read(provider);
      } catch (error) {
        return error;
      }
      fail('expected the read to fail');
    }

    test('a web page answering the queue and the history', () async {
      final profile = Profiles.p1.withBehaviour(
        WorldIds.sabnzbd,
        ConnectionBehaviour.servesHtmlPage,
      );
      for (final provider in <ProviderListenable<Future<Object?>>>[
        sabnzbdQueueProvider.future,
        sabnzbdHistoryProvider.future,
      ]) {
        final error = await failureOf(profile, provider);

        expect(classifyConnectionFailure(error), ServiceFailureReason.notFound);
        expect(
          failureMessageOf(ServiceKey.sabnzbd, error),
          'A web page answered at nas.home.arpa:8085 instead of SABnzbd.\n'
          'If SABnzbd sits under a path, add it: '
          'http://nas.home.arpa:8085/sabnzbd',
        );
      }
    });

    test('an answer without SABnzbd\'s envelope', () async {
      final error = await failureOf(
        Profiles.p1,
        sabnzbdQueueProvider.future,
        routes: (network) => network.on(
          WorldIds.sabnzbd,
          'GET',
          '/api',
          (request) => request.query['mode'] == 'queue'
              ? NetworkReply.json(<String, Object?>{})
              : null,
        ),
      );

      expect(classifyConnectionFailure(error), ServiceFailureReason.notFound);
      expect(
        failureMessageOf(ServiceKey.sabnzbd, error),
        startsWith(
          "Something answered at nas.home.arpa:8085, but it isn't SABnzbd.",
        ),
      );
    });

    test('a genuine SABnzbd still reads its queue', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final container = harness.container(retry: (_, _) => null);

      final queue = await container.read(sabnzbdQueueProvider.future);

      expect(queue, isNotNull);
    });
  });

  group('the probe checks who answered', () {
    final otherOnRadarrsPort = Profiles.p1.withBehaviour(
      WorldIds.radarr,
      const ConnectionBehaviour.answersAsOtherService(ServiceKey.sonarr),
    );
    final pageForRadarr = Profiles.p1.withBehaviour(
      WorldIds.radarr,
      ConnectionBehaviour.servesHtmlPage,
    );

    test(
      'a Sonarr on Radarr\'s port is named, on Home and in Settings',
      () async {
        final summary = await _probe(
          otherOnRadarrsPort,
          ServiceKey.radarr,
          WorldIds.radarr,
        );
        final diagnosis = await _test(otherOnRadarrsPort, WorldIds.radarr);

        expect(summary.status, ServiceSummaryStatus.fault);
        expect(summary.failureReason, ServiceFailureReason.notFound);
        expect(
          summary.failure?.detail,
          'Sonarr answered at nas.home.arpa:7878, not Radarr.',
        );
        expect(diagnosis.reason, summary.failureReason);
        expect(
          diagnosis.messageFor(ServiceKey.radarr),
          summary.failure?.detail,
        );
      },
    );

    test('a web page names where it answered, with the path hint', () async {
      final summary = await _probe(
        pageForRadarr,
        ServiceKey.radarr,
        WorldIds.radarr,
      );
      final diagnosis = await _test(pageForRadarr, WorldIds.radarr);

      expect(summary.failureReason, ServiceFailureReason.notFound);
      expect(
        failureMessageOf(ServiceKey.radarr, summary.failure),
        'A web page answered at nas.home.arpa:7878 instead of Radarr.\n'
        'If Radarr sits under a path, add it: http://nas.home.arpa:7878/radarr',
      );
      expect(diagnosis.reason, ServiceFailureReason.notFound);
      expect(
        diagnosis.messageFor(ServiceKey.radarr),
        failureMessageOf(ServiceKey.radarr, summary.failure),
      );
    });

    test('JSON that is not Radarr\'s is something that is not Radarr', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/system/status',
        (_) => NetworkReply.json({'status': 'ok'}),
      );
      final container = harness.container(retry: (_, _) => null);
      final summary = await container.read(
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: WorldIds.radarr,
        )).future,
      );

      expect(summary.failureReason, ServiceFailureReason.notFound);
      expect(
        summary.failure?.detail,
        "Something answered at nas.home.arpa:7878, but it isn't Radarr.\n"
        'If Radarr sits under a path, add it: http://nas.home.arpa:7878/radarr',
      );
    });

    final special = <(String, ServiceKey, String, String)>[
      ('Seerr', ServiceKey.seerr, WorldIds.seerr, 'nas.home.arpa:5055'),
      (
        'qBittorrent',
        ServiceKey.qbittorrent,
        WorldIds.qbittorrent,
        'nas.home.arpa:8080',
      ),
      ('SABnzbd', ServiceKey.sabnzbd, WorldIds.sabnzbd, 'nas.home.arpa:8085'),
      (
        'Jellyfin',
        ServiceKey.jellyfin,
        WorldIds.jellyfin,
        'nas.home.arpa:8096',
      ),
    ];
    for (final (name, service, id, host) in special) {
      test(
        '$name: a web page reads the same on Home and in Settings',
        () async {
          final profile = Profiles.p1.withBehaviour(
            id,
            ConnectionBehaviour.servesHtmlPage,
          );
          final summary = await _probe(profile, service, id);
          final diagnosis = await _test(profile, id);

          expect(summary.failureReason, ServiceFailureReason.notFound);
          final home = failureMessageOf(service, summary.failure);
          expect(
            home,
            startsWith('A web page answered at $host instead of $name.'),
          );
          expect(diagnosis.reason, ServiceFailureReason.notFound);
          expect(diagnosis.messageFor(service), home);
        },
      );
    }

    test('Emby: a web page reads the same on Home and in Settings', () async {
      final profile = Profiles.p1
          .withConnection(WorldConnections.emby)
          .withBehaviour(WorldIds.emby, ConnectionBehaviour.servesHtmlPage);
      final summary = await _probe(profile, ServiceKey.emby, WorldIds.emby);
      final diagnosis = await _test(profile, WorldIds.emby);

      expect(summary.failureReason, ServiceFailureReason.notFound);
      final home = failureMessageOf(ServiceKey.emby, summary.failure);
      expect(
        home,
        startsWith(
          'A web page answered at tower.home.arpa:8096 instead of Emby.',
        ),
      );
      expect(diagnosis.reason, ServiceFailureReason.notFound);
      expect(diagnosis.messageFor(ServiceKey.emby), home);
    });

    test('Emby: a refused key is the key, never an Answering tile', () async {
      // Its public info is anonymous: a probe that read only that would paint
      // a wrong key green.
      final profile = Profiles.p1
          .withConnection(WorldConnections.emby)
          .withBehaviour(WorldIds.emby, PlainBehaviour.refusesKey);
      final summary = await _probe(profile, ServiceKey.emby, WorldIds.emby);
      final diagnosis = await _test(profile, WorldIds.emby);

      expect(summary.isOnline, isFalse);
      expect(summary.failureReason, ServiceFailureReason.unauthorized);
      expect(diagnosis.reason, ServiceFailureReason.unauthorized);
    });

    test('a genuine service still answers', () async {
      for (final (service, id) in [
        (ServiceKey.radarr, WorldIds.radarr),
        (ServiceKey.sonarr, WorldIds.sonarr),
        (ServiceKey.lidarr, WorldIds.lidarr),
        (ServiceKey.prowlarr, WorldIds.prowlarr),
        (ServiceKey.bazarr, WorldIds.bazarr),
        (ServiceKey.seerr, WorldIds.seerr),
        (ServiceKey.qbittorrent, WorldIds.qbittorrent),
        (ServiceKey.sabnzbd, WorldIds.sabnzbd),
        (ServiceKey.jellyfin, WorldIds.jellyfin),
        (ServiceKey.emby, WorldIds.emby),
      ]) {
        final profile = Profiles.p1.withConnection(WorldConnections.emby);
        final summary = await _probe(profile, service, id);
        final diagnosis = await _test(profile, id);

        expect(summary.isOnline, isTrue, reason: service.title);
        expect(diagnosis.isConnected, isTrue, reason: service.title);
      }
    });

    testWidgets('the Stack paints a Sonarr on Radarr\'s port amber, in the '
        'address\'s words', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3.withBehaviour(
          WorldIds.radarr,
          const ConnectionBehaviour.answersAsOtherService(ServiceKey.sonarr),
        ),
        child: const StackScreen(),
        surfaceSize: const Size(430, 2400),
      );

      final cell = find.byKey(const ValueKey('service-matrix-cell-radarr'));
      final label = find.descendant(
        of: cell,
        matching: find.text(failureLabel(ServiceFailureReason.notFound)),
      );
      expect(label, findsOneWidget);
      final scheme = AppTheme.darkTheme().colorScheme;
      expect(
        tester.widget<Text>(label).style?.color,
        statusToneColor(
          scheme,
          StatusTone.warning,
          surface: scheme.surfaceContainer,
        ),
      );
      expect(
        find.descendant(of: cell, matching: find.text('Answering')),
        findsNothing,
      );

      await harness.unmount(tester);
    });
  });

  group('a gateway in front of Radarr is named', () {
    final gateways = <(ConnectionBehaviour, AccessGatewayKind, String)>[
      (
        const ConnectionBehaviour.behindCloudflareAccess(),
        AccessGatewayKind.cloudflareAccess,
        'cupola-home.cloudflareaccess.com',
      ),
      (
        const ConnectionBehaviour.behindCloudflareAccess(
          mode: CloudflareAccessMode.unauthorized,
        ),
        AccessGatewayKind.cloudflareAccess,
        'nas.home.arpa',
      ),
      (
        const ConnectionBehaviour.behindSignInPage(),
        AccessGatewayKind.signInPage,
        'auth.example.net',
      ),
      (
        const ConnectionBehaviour.behindSignInPage(
          mode: SignInPageMode.sameHostForm,
        ),
        AccessGatewayKind.signInPage,
        'nas.home.arpa',
      ),
      (
        const ConnectionBehaviour.behindPasswordPrompt(),
        AccessGatewayKind.passwordPrompt,
        'nas.home.arpa',
      ),
    ];

    for (final (behaviour, kind, gatewayHost) in gateways) {
      test(
        '${behaviour.label}: the same words on Home and in Settings',
        () async {
          final profile = Profiles.p1.withBehaviour(WorldIds.radarr, behaviour);
          final summary = await _probe(
            profile,
            ServiceKey.radarr,
            WorldIds.radarr,
          );
          final diagnosis = await _test(profile, WorldIds.radarr);

          expect(summary.status, ServiceSummaryStatus.fault);
          expect(summary.failureReason, ServiceFailureReason.accessGateway);
          final gateway = summary.failure?.gateway;
          expect(gateway?.kind, kind);
          expect(gateway?.credentialsSent, isFalse);
          expect(gateway?.gatewayHost, gatewayHost);
          expect(gateway?.serviceHost, 'nas.home.arpa:7878');

          expect(diagnosis.reason, ServiceFailureReason.accessGateway);
          expect(diagnosis.gateway?.kind, kind);
          expect(
            diagnosis.messageFor(ServiceKey.radarr),
            connectionFailureMessage(
              ServiceKey.radarr,
              ServiceFailureReason.accessGateway,
              gateway: gateway,
            ),
          );
          // The service was never asked: the gateway answered for it.
          expect(
            FailureRemedy.forReason(
              ServiceKey.radarr,
              ServiceFailureReason.accessGateway,
              gateway: gateway,
            )?.retryHelps,
            isFalse,
          );
        },
      );
    }

    // The clients that wrap a failure in their own exception keep the
    // gateway as its cause, and none reads a gateway's 401 or 403 as its own
    // refusal (Plex's token, Transmission's whitelist, NPM's login,
    // qBittorrent's session, Jellyfin's narrower token).
    final clients = <(ServiceKey, ProfileConnection)>[
      (ServiceKey.qbittorrent, WorldConnections.qbittorrent),
      (ServiceKey.sabnzbd, WorldConnections.sabnzbd),
      (ServiceKey.jellyfin, WorldConnections.jellyfin),
      (ServiceKey.emby, WorldConnections.emby),
      (ServiceKey.plex, WorldConnections.plex),
      (ServiceKey.transmission, WorldConnections.transmission),
      (ServiceKey.nzbget, WorldConnections.nzbget),
      (ServiceKey.unraid, WorldConnections.unraid),
      (ServiceKey.nginxProxyManager, WorldConnections.npm),
      (ServiceKey.seerr, WorldConnections.seerr),
      (ServiceKey.bazarr, WorldConnections.bazarr),
    ];
    for (final (service, connection) in clients) {
      test('${service.title} behind Cloudflare Access is named, on Home and '
          'in Settings', () async {
        final profile = Profiles.p1
            .withConnection(connection)
            .withBehaviour(
              connection.id,
              const ConnectionBehaviour.behindCloudflareAccess(
                mode: CloudflareAccessMode.unauthorized,
              ),
            );
        final summary = await _probe(profile, service, connection.id);
        final diagnosis = await _test(profile, connection.id);

        expect(summary.failureReason, ServiceFailureReason.accessGateway);
        expect(
          summary.failure?.gateway?.kind,
          AccessGatewayKind.cloudflareAccess,
        );
        expect(diagnosis.reason, ServiceFailureReason.accessGateway);
        expect(diagnosis.gateway?.kind, AccessGatewayKind.cloudflareAccess);
      });
    }

    test('qBittorrent behind a password prompt: the proxy\'s, not its own '
        'refused sign-in', () async {
      final profile = Profiles.p1.withBehaviour(
        WorldIds.qbittorrent,
        const ConnectionBehaviour.behindPasswordPrompt(),
      );
      final summary = await _probe(
        profile,
        ServiceKey.qbittorrent,
        WorldIds.qbittorrent,
      );

      expect(summary.failureReason, ServiceFailureReason.accessGateway);
      expect(summary.failure?.gateway?.kind, AccessGatewayKind.passwordPrompt);
    });

    test('NZBGet signs in with Basic itself, so a Basic 401 is its own '
        'refusal', () async {
      final profile = Profiles.p1
          .withConnection(WorldConnections.nzbget)
          .withBehaviour(
            WorldConnections.nzbget.id,
            const ConnectionBehaviour.behindPasswordPrompt(),
          );
      final summary = await _probe(
        profile,
        ServiceKey.nzbget,
        WorldConnections.nzbget.id,
      );

      expect(summary.failureReason, ServiceFailureReason.unauthorized);
      expect(summary.failure?.gateway, isNull);
    });

    testWidgets('the Stack paints Cloudflare Access amber, by name', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3.withBehaviour(
          WorldIds.radarr,
          const ConnectionBehaviour.behindCloudflareAccess(
            mode: CloudflareAccessMode.unauthorized,
          ),
        ),
        child: const StackScreen(),
        surfaceSize: const Size(430, 2400),
      );

      final cell = find.byKey(const ValueKey('service-matrix-cell-radarr'));
      final label = find.descendant(
        of: cell,
        matching: find.text('Behind Cloudflare Access'),
      );
      expect(label, findsOneWidget);
      final scheme = AppTheme.darkTheme().colorScheme;
      expect(
        tester.widget<Text>(label).style?.color,
        statusToneColor(
          scheme,
          StatusTone.warning,
          surface: scheme.surfaceContainer,
        ),
      );
      // Not the key: the service never saw it.
      expect(
        find.descendant(of: cell, matching: find.text('Refused the key')),
        findsNothing,
      );

      await harness.unmount(tester);
    });

    final libraries = <(ConnectionBehaviour, String, String, String)>[
      (
        const ConnectionBehaviour.behindCloudflareAccess(
          mode: CloudflareAccessMode.unauthorized,
        ),
        'Cloudflare Access answered instead of Radarr',
        'Radarr is behind Cloudflare Access. Cupola needs a service token to '
            'reach it.',
        'Add a service token',
      ),
      (
        const ConnectionBehaviour.behindSignInPage(),
        'A sign-in page answered instead of Radarr',
        'Something in front of Radarr asks for a sign-in that Cupola cannot '
            'complete.',
        'Add access',
      ),
      (
        const ConnectionBehaviour.behindPasswordPrompt(),
        'A password prompt answered instead of Radarr',
        'Something in front of Radarr asks for a username and password.',
        'Add the password',
      ),
    ];
    for (final (behaviour, headline, sentence, remedy) in libraries) {
      testWidgets('the Radarr library, ${behaviour.label}: the cause, and '
          'its remedy in the amber fill', (tester) async {
        final harness = await pumpWithProfile(
          tester,
          Profiles.p1.withBehaviour(WorldIds.radarr, behaviour),
          child: const MoviesScreen(showAppBar: false),
        );

        final leaf = find.byType(ServiceOfflineState);
        expect(leaf, findsOneWidget);
        expect(find.text(headline), findsOneWidget);
        expect(find.textContaining(sentence), findsOneWidget);
        expect(find.textContaining('library is empty'), findsNothing);
        final button = find.widgetWithText(FilledButton, remedy);
        expect(button, findsOneWidget);
        final style = tester.widget<FilledButton>(button).style;
        final room = CupolaRoom.of(tester.element(leaf));
        expect(style?.backgroundColor?.resolve(const {}), room.toneAmberFill);
        // Asking the gateway the same thing again cannot help.
        expect(find.text('Retry'), findsNothing);
        final glyph = tester.widget<Icon>(
          find.descendant(of: leaf, matching: find.byType(Icon)).first,
        );
        expect(glyph.color, _amber());

        await harness.unmount(tester);
      });
    }

    testWidgets('the connection test says what Home says', (tester) async {
      // P3: one Radarr, so the form asks for no name before it tests.
      final profile = Profiles.p3.withBehaviour(
        WorldIds.radarr,
        const ConnectionBehaviour.behindCloudflareAccess(),
      );
      final harness = await pumpWithProfile(
        tester,
        profile,
        child: ServiceSettingsScreen(
          service: ServiceKey.radarr,
          instanceId: WorldIds.radarr,
          certificateProber: (_, {pinnedFingerprint = ''}) async => null,
          localNetworkProbe: (_, {timeout = Duration.zero}) async =>
              LocalNetworkAccess.unrestricted,
        ),
        surfaceSize: const Size(430, 2400),
      );

      await tester.tap(find.text('Test connection'));
      await harness.settle(tester);

      expect(
        find.semantics.byLabel(
          RegExp(
            r'^Connection test failed\. Radarr is behind Cloudflare Access\. '
            r'Cupola needs a service token to reach it\.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Behind Cloudflare Access'), findsWidgets);

      await harness.unmount(tester);
    });
  });
}

/// The headline the classification gives an answer nobody can read.
String describeUnreadable(ServiceKey service) => failureHeadline(
  ServiceFailureReason.invalidResponse,
  subject: service.title,
);
