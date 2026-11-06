@Tags(['catalog'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

void main() {
  catalogCard(
    'NotConfiguredPlaceholder',
    // A Seerr account that signed out: the one connection of the household's
    // Seerr, its session gone.
    overrides: () async => settingsScopeOverrides(
      customize: (_) => const SettingsModel(
        instances: [
          ServiceInstance(
            id: 'seerr',
            service: ServiceKey.seerr,
            url: 'http://nas.home.arpa:5055',
            account: SeerrAccountSignIn(
              kind: SeerrAccountKind.local,
              login: 'anna@home.arpa',
              userId: 2,
              displayName: 'Anna',
              permissions: 32,
            ),
          ),
        ],
      ),
    ),
    scenes: [
      CatalogScene(
        'NotConfiguredPlaceholder.forService(radarr) · deep-links to '
        '/settings/service/radarr, for a service dashboard',
        (_) => NotConfiguredPlaceholder.forService(ServiceKey.radarr),
        width: 320,
      ),
      CatalogScene(
        'NotConfiguredPlaceholder(serviceName:) · the generic form, for a '
        'caller that only holds a name: lands on /settings',
        (_) => const NotConfiguredPlaceholder(serviceName: 'Bazarr'),
        width: 320,
      ),
      CatalogScene(
        'NotConfiguredPlaceholder.forService(seerr) · a Seerr account that '
        'signed out is set up: it reads Signed out of Seerr, blue, and Sign '
        'in again opens its own form, never Set up Seerr',
        (_) => NotConfiguredPlaceholder.forService(ServiceKey.seerr),
        width: 320,
      ),
      CatalogScene(
        'UnreadSecretState · a saved key the Keychain would not hand over: '
        'amber, what happened on this device, Paste the key again into its '
        'form, never Set up Radarr',
        (_) => UnreadSecretState(
          instance: const ServiceInstance(
            id: 'radarr',
            service: ServiceKey.radarr,
            url: 'http://nas.home.arpa:7878',
          ).withUnreadSecret(UnreadSecret.credential),
        ),
        width: 320,
      ),
      CatalogScene(
        'JellyfinUsersScreen(service: emby) · a household member\'s key: '
        'calm, not a fault. Needs an Emby administrator, what the key can '
        'still do, and Update the key to the connection\'s form',
        (_) => const JellyfinUsersScreen(service: ServiceKey.emby),
        width: 320,
        height: 420,
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWithServices(const [ServiceKey.emby]),
          ),
          mediaBrowserProvidersOf(
            ServiceKey.emby,
          ).lacksAdministratorFor.overrideWith((ref, instanceId) => true),
        ],
      ),
      CatalogScene(
        'Text at 200% · forService(radarr) and the signed-out Seerr form, '
        'at twice the reading size',
        (_) => Column(
          children: [
            NotConfiguredPlaceholder.forService(ServiceKey.radarr),
            NotConfiguredPlaceholder.forService(ServiceKey.seerr),
          ],
        ),
        width: 320,
        textScale: catalogTextScale,
      ),
    ],
  );
}
