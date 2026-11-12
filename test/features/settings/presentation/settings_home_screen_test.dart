import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_signature.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/settings_home_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  group('SettingsHomeScreen', () {
    testWidgets('renders the main settings sections', (tester) async {
      await _pumpSettingsHome(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      // Security is new, and it is always there: trusted certificates used to
      // be reachable only from a Connections row that appears when something
      // is already pinned, which on a phone made the pane unreachable until it
      // had content.
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('the connections summary counts against the registry', (
      tester,
    ) async {
      // It used to say "No services set up yet", which answers "is anything
      // set up" and not "how much of the stack is". The denominator is every
      // service Cupola can talk to, the same number the count chip on the
      // connections list prints, read from the registry rather than typed.
      await _pumpSettingsHome(tester);

      expect(
        find.text('0 of ${ServiceKey.values.length} set up'),
        findsOneWidget,
      );
    });

    testWidgets('the connections summary counts what is set up', (
      tester,
    ) async {
      await _pumpSettingsHome(
        tester,
        settings: settingsWith(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
        ),
        diagnosis: const ServiceDiagnosis.connected(),
      );

      // "answering" is `describeConnection`'s own word for a healthy
      // connection; the summary must not coin a second one ("connected",
      // "online") for the same state.
      expect(
        find.text('1 of ${ServiceKey.values.length} set up\u00A0· 1 answering'),
        findsOneWidget,
      );
    });

    testWidgets('healthy services stay off this screen', (tester) async {
      // This many services means a list of the working ones is an inventory
      // nobody reads. Only trouble earns a row here.
      await _pumpSettingsHome(
        tester,
        settings: settingsWith(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
          sonarrUrl: 'https://sonarr.local:8989',
          sonarrApiKey: 'sonarr-key',
        ),
        diagnosis: const ServiceDiagnosis.connected(),
      );

      expect(
        find.text('2 of ${ServiceKey.values.length} set up\u00A0· 2 answering'),
        findsOneWidget,
      );
      expect(find.text('Radarr'), findsNothing);
      expect(find.text('Sonarr'), findsNothing);
    });

    testWidgets('a failing service is promoted with its cause', (tester) async {
      await _pumpSettingsHome(
        tester,
        settings: settingsWith(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
        ),
        diagnosis: ServiceDiagnosis.failed(_UnauthorizedFailure()),
      );

      // A refused key answered: counted, as the Stack counts it, and named.
      expect(
        find.text('1 of ${ServiceKey.values.length} set up\u00A0· 1 answering'),
        findsOneWidget,
      );
      // The failing services are grouped by the state they are in and named,
      // and the state is spelled exactly as `describeConnection` spells it.
      expect(find.text('Radarr'), findsOneWidget);
      expect(find.text('Refused the key'), findsOneWidget);
    });

    testWidgets('tapping a promoted failure opens that service', (
      tester,
    ) async {
      await _pumpSettingsHome(
        tester,
        settings: settingsWith(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
        ),
        diagnosis: ServiceDiagnosis.failed(_UnauthorizedFailure()),
      );

      await tester.tap(find.text('Radarr'));
      await tester.pumpAndSettle();

      expect(find.text('ServicePage:radarr'), findsOneWidget);
    });

    testWidgets('formats the selected region label', (tester) async {
      await _pumpSettingsHome(tester, settings: settingsWith(region: 'gb'));

      expect(find.text('United Kingdom (GB)'), findsOneWidget);
    });

    testWidgets('the summary row opens the connections list', (tester) async {
      await _pumpSettingsHome(tester);

      await tester.tap(find.text('0 of ${ServiceKey.values.length} set up'));
      await tester.pumpAndSettle();

      expect(find.text('ConnectionsPage'), findsOneWidget);
    });

    group('semantics', () {
      testWidgets('a promoted service speaks its connection state', (
        tester,
      ) async {
        // The indicator is a bare glyph (a cloud, a key, a spinner), so
        // without a label for it the connection state is simply unreadable:
        // the subtitle beside it is only the host.
        await _pumpSettingsHome(
          tester,
          settings: settingsWith(
            radarrUrl: 'https://radarr.local:7878',
            radarrApiKey: 'radarr-key',
          ),
          diagnosis: const ServiceDiagnosis(
            ServiceConnectionStatus.disconnected,
            ServiceFailureReason.unreachable,
          ),
        );

        // The summary groups by state, so the row names the services and the
        // state and leaves the host to the connections list, but the state
        // itself is still spoken, because on screen it is carried by a glyph
        // and a tint and nothing else.
        expect(
          find.semantics.byLabel('Radarr, Did not answer'),
          isSemantics(
            isButton: true,
            hasTapAction: true,
            hint: 'opens the Radarr connection settings',
          ),
        );
        expect(find.semantics.byLabel('radarr.local:7878'), findsNothing);
      });

      testWidgets('section labels are headings, read without the caps', (
        tester,
      ) async {
        await _pumpSettingsHome(tester);

        expect(find.semantics.byLabel('General'), isSemantics(isHeader: true));
        expect(
          find.semantics.byLabel('Connections'),
          isSemantics(isHeader: true),
        );
        // Drawn as it is read: there is no uppercase voice to spell out.
        expect(find.text('General'), findsOneWidget);
      });
    });

    testWidgets('tapping Region navigates to the region screen', (
      tester,
    ) async {
      await _pumpSettingsHome(tester);

      await tester.tap(find.text('Region'));
      await tester.pumpAndSettle();

      expect(find.text('RegionPage'), findsOneWidget);
    });

    testWidgets('renders tappable settings cards', (tester) async {
      await _pumpSettingsHome(tester);

      expect(find.byType(SettingsCard), findsAtLeastNWidgets(6));
      // Connections, General, Security, About, Danger Zone.
      expect(find.byType(SettingsGroupCard), findsNWidgets(5));

      await tester.scrollUntilVisible(find.text('Send feedback'), 300);
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Send feedback'), findsOneWidget);
    });

    testWidgets('the licence page is signed and carries the trademark '
        'notice', (tester) async {
      await _pumpSettingsHome(tester);

      await tester.scrollUntilVisible(find.text('Licenses & trademarks'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Licenses & trademarks'));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text(kAppName), findsOneWidget);
      expect(find.text(kAppRelease), findsOneWidget);
      expect(find.byType(CupolaMark), findsOneWidget);
      // Unraid's policy prescribes this sentence for every app using the name.
      expect(
        find.textContaining('Unraid® is a registered trademark of Lime'),
        findsOneWidget,
      );
      expect(find.textContaining('trademarks of Plex'), findsOneWidget);
    });

    testWidgets('reset tile shows Danger Zone section', (tester) async {
      await _pumpSettingsHome(tester);

      await tester.scrollUntilVisible(find.text('Danger zone'), 300);
      await tester.pumpAndSettle();

      expect(find.text('Danger zone'), findsOneWidget);
      expect(find.text('Reset app data'), findsOneWidget);
    });

    testWidgets('confirming reset clears data and restarts onboarding', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = FakeSecureSettingsStore();
      final service = SettingsService(prefs, secureStore);
      await service.saveSettings(
        settingsWith(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
          region: 'IT',
          themeMode: AppThemeMode.dark,
        ),
      );
      await service.saveOnboardingComplete();
      final initialSettings = await service.loadSettings();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
          secureSettingsStoreProvider.overrideWith((ref) => secureStore),
          initialSettingsProvider.overrideWith((ref) => initialSettings),
          initialOnboardingCompletedProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(settingsProvider).urlFor(ServiceKey.radarr),
        'https://radarr.local:7878',
      );
      expect(container.read(onboardingCompletedProvider), isTrue);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/settings',
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (_, _) => const SettingsHomeScreen(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Reset app data'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset app data'));
      await tester.pumpAndSettle();

      expect(find.text('Reset all data?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Reset app data'));
      await tester.pumpAndSettle();

      expect(
        container.read(settingsProvider).urlFor(ServiceKey.radarr),
        isEmpty,
      );
      expect(
        container.read(settingsProvider).apiKeyFor(ServiceKey.radarr),
        isEmpty,
      );
      expect(container.read(settingsProvider).themeMode, AppThemeMode.dark);
      expect(container.read(onboardingCompletedProvider), isFalse);
      expect(await secureStore.read(key: 'secure_radarr_api_key'), isNull);
    });

    testWidgets('canceling reset keeps data intact', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = FakeSecureSettingsStore();
      final service = SettingsService(prefs, secureStore);
      await service.saveSettings(
        settingsWith(radarrUrl: 'https://radarr.local:7878'),
      );
      await service.saveOnboardingComplete();
      final initialSettings = await service.loadSettings();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
          secureSettingsStoreProvider.overrideWith((ref) => secureStore),
          initialSettingsProvider.overrideWith((ref) => initialSettings),
          initialOnboardingCompletedProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/settings',
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (_, _) => const SettingsHomeScreen(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Reset app data'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset app data'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Reset all data?'), findsNothing);
      expect(
        container.read(settingsProvider).urlFor(ServiceKey.radarr),
        'https://radarr.local:7878',
      );
      expect(container.read(onboardingCompletedProvider), isTrue);
    });

    group('Set up another device', () {
      testWidgets('is not offered with nothing set up', (tester) async {
        await _pumpSettingsHome(tester);

        expect(find.text('Set up another device'), findsNothing);
      });

      testWidgets('is offered with a connection, in the group before About, '
          'and opens the code', (tester) async {
        await _pumpSettingsHome(
          tester,
          settings: settingsWith(
            radarrUrl: 'https://radarr.local:7878',
            radarrApiKey: 'radarr-key',
          ),
        );

        expect(find.text('Set up another device'), findsOneWidget);
        expect(find.text('Copy everything to a new phone'), findsOneWidget);
        expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
        // Under Trusted certificates in its group, and above About.
        final row = tester.getTopLeft(find.text('Set up another device')).dy;
        expect(
          tester.getTopLeft(find.text('Trusted certificates')).dy,
          lessThan(row),
        );
        expect(tester.getTopLeft(find.text('About')).dy, greaterThan(row));

        await tester.tap(find.text('Set up another device'));
        await tester.pumpAndSettle();
        expect(find.text('AnotherDevicePage'), findsOneWidget);
      });

      testWidgets('is heard with what it does', (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpSettingsHome(
          tester,
          settings: settingsWith(
            radarrUrl: 'https://radarr.local:7878',
            radarrApiKey: 'radarr-key',
          ),
        );

        expect(
          find.bySemanticsLabel(
            RegExp('^Set up another device, Copy everything to a new phone'),
          ),
          findsOneWidget,
        );
        handle.dispose();
      });
    });

    group('the signature', () {
      testWidgets('ends the operator\'s index, after Danger zone, and speaks '
          'once', (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpSettingsHome(tester);

        expect(find.byType(SettingsSignature), findsOneWidget);
        expect(find.text(OnePunchline.claim), findsOneWidget);
        expect(find.text(kAppIdentityLine), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(SettingsSignature)).dy,
          greaterThan(tester.getTopLeft(find.text('Reset app data')).dy),
        );
        expect(
          find.semantics.byLabel(SettingsSignature.spoken),
          findsOneWidget,
        );
        handle.dispose();
      });

      testWidgets('ends the requester\'s index too', (tester) async {
        await _pumpSettingsHome(tester, audience: Audience.requester);

        expect(find.text('Set up a service'), findsOneWidget);
        expect(find.byType(SettingsSignature), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(SettingsSignature)).dy,
          greaterThan(tester.getTopLeft(find.text('Set up a service')).dy),
        );
      });
    });

    group('Revisit onboarding', () {
      Future<(ProviderContainer, GoRouter, SettingsService)> pumpRevisit(
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final secureStore = FakeSecureSettingsStore();
        final service = SettingsService(prefs, secureStore);
        await service.saveSettings(
          settingsWith(
            radarrUrl: 'https://radarr.local:7878',
            radarrApiKey: 'radarr-key',
          ),
        );
        await service.saveOnboardingComplete();
        final initialSettings = await service.loadSettings();

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
            secureSettingsStoreProvider.overrideWith((ref) => secureStore),
            initialSettingsProvider.overrideWith((ref) => initialSettings),
            initialOnboardingCompletedProvider.overrideWith((ref) => true),
          ],
        );
        addTearDown(container.dispose);

        final router = GoRouter(
          initialLocation: '/settings',
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsHomeScreen(),
            ),
            GoRoute(
              path: ServiceRoutes.welcome,
              builder: (_, _) => const Scaffold(body: Text('WelcomePage')),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Revisit onboarding'), 300);
        await tester.pumpAndSettle();
        return (container, router, service);
      }

      testWidgets('asks first, and says what it opens and what it leaves', (
        tester,
      ) async {
        await pumpRevisit(tester);

        await tester.tap(find.text('Revisit onboarding'));
        await tester.pumpAndSettle();

        expect(find.text('Revisit onboarding?'), findsOneWidget);
        expect(
          find.text(
            "You'll see the Welcome again. Nothing about your services or "
            'settings is changed or removed.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('opens the Welcome on top, and leaves the flag and every '
          'connection alone', (tester) async {
        final (container, router, service) = await pumpRevisit(tester);

        await tester.tap(find.text('Revisit onboarding'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, 'Revisit onboarding'),
        );
        await tester.pumpAndSettle();

        expect(router.state.uri.path, ServiceRoutes.welcome);
        expect(find.text('WelcomePage'), findsOneWidget);
        // The flag is what keeps the app on its tabs: it stays on, in memory
        // and on disk, so nothing sends the person anywhere but back.
        expect(container.read(onboardingCompletedProvider), isTrue);
        expect(await service.loadOnboardingComplete(), isTrue);
        expect(
          container.read(settingsProvider).urlFor(ServiceKey.radarr),
          'https://radarr.local:7878',
        );
        expect(
          container.read(settingsProvider).apiKeyFor(ServiceKey.radarr),
          'radarr-key',
        );

        // Pushed, not replaced: Back returns to Settings.
        router.pop();
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/settings');
      });

      testWidgets('cancelling opens nothing', (tester) async {
        final (container, router, _) = await pumpRevisit(tester);

        await tester.tap(find.text('Revisit onboarding'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(router.state.uri.path, '/settings');
        expect(find.text('WelcomePage'), findsNothing);
        expect(container.read(onboardingCompletedProvider), isTrue);
      });
    });
  });
}

Future<void> _pumpSettingsHome(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  ServiceDiagnosis? diagnosis,
  Audience? audience,
}) async {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsHomeScreen(),
        routes: [
          GoRoute(
            path: 'region',
            builder: (_, _) => const Scaffold(body: Text('RegionPage')),
          ),
          GoRoute(
            path: 'connections',
            builder: (_, _) => const Scaffold(body: Text('ConnectionsPage')),
          ),
          GoRoute(
            path: 'another-device',
            builder: (_, _) => const Scaffold(body: Text('AnotherDevicePage')),
          ),
          GoRoute(
            path: 'service/:service',
            builder: (context, state) {
              final service = state.pathParameters['service'] ?? 'unknown';
              return Scaffold(body: Text('ServicePage:$service'));
            },
          ),
        ],
      ),
    ],
  );

  addTearDown(router.dispose);

  // A tall viewport so every section of this lazy ListView is built and
  // counted, independent of scroll position.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        if (audience != null)
          shellAudienceProvider.overrideWith(() => _FixedAudience(audience)),
        if (diagnosis != null)
          serviceDiagnosisProvider.overrideWith((ref, service) async {
            return diagnosis;
          }),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// An error that already knows why it failed, the way the service clients do.
class _UnauthorizedFailure implements HasFailureReason {
  @override
  ServiceFailureReason get reason => ServiceFailureReason.unauthorized;
}

/// The shell drawn for one audience, whatever the connections say.
class _FixedAudience extends ShellAudienceNotifier {
  _FixedAudience(this._audience);

  final Audience _audience;

  @override
  Audience build() => _audience;
}
