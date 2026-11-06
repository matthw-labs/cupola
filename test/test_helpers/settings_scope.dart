import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/network/host_reach.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import 'fake_secure_settings_store.dart';

/// The pieces needed to make `settingsProvider` readable in a test.
///
/// `sharedPreferencesProvider` and `initialSettingsProvider` throw unless
/// overridden (they are wired in `main.dart`), and `SettingsNotifier.build`
/// watches both, so any screen that asks `settings.isServiceConfigured(...)`
/// needs all of this. The Activity screen does, because it distinguishes "this
/// service is not set up" from "this service did not answer".
///
/// Most tests want [settingsScopeOverrides] instead, which returns the four
/// overrides ready to spread. This record form is for the call sites that also
/// need one of the pieces afterwards: `scope.prefs` to assert on what was
/// persisted, say.
typedef SettingsScope = ({
  SharedPreferences prefs,
  SecureSettingsStore secureStore,
  SettingsModel settings,
});

Future<SettingsScope> settingsScope({
  List<ServiceKey> configured = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return (
    prefs: prefs,
    secureStore: FakeSecureSettingsStore(),
    settings: settingsWithServices(configured),
  );
}

/// The four startup overrides a settings-reading test needs, ready to spread:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     ...await settingsScopeOverrides(configured: activityServiceKeys),
///     // …the test's own overrides
///   ],
/// );
/// ```
///
/// [customize] runs on the model built from [configured], for the tests that
/// need a specific URL or key rather than the generated placeholders. It exists
/// because a container rejects two overrides of the same provider, so such a
/// test cannot spread these and then re-override `initialSettingsProvider`.
///
/// [hostReach] answers whether a host a probe timed out on is there; by
/// default none is, so no test opens a socket.
Future<List<Override>> settingsScopeOverrides({
  List<ServiceKey> configured = const [],
  SettingsModel Function(SettingsModel settings)? customize,
  HostReach hostReach = _neverReached,
}) async {
  final scope = await settingsScope(configured: configured);
  final settings = customize?.call(scope.settings) ?? scope.settings;

  return [
    sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
    secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
    initialSettingsProvider.overrideWith((ref) => settings),
    initialOnboardingCompletedProvider.overrideWith((ref) => true),
    hostReachProvider.overrideWithValue(hostReach),
  ];
}

Future<bool> _neverReached(Uri url) async => false;

/// A [SettingsModel] where each of [configured] has both a URL and an API key,
/// which is what `isServiceConfigured` requires for the API-key services.
///
/// Goes through `copyWithService` rather than a hand-written `switch`, so every
/// service in the registry is covered. The `switch` this replaced knew four of
/// them and silently returned an unconfigured model for the rest, which is how
/// a test could ask for a configured Bazarr, get a not-configured one, and pass
/// for the wrong reason.
///
/// For the credential-authenticated services the generic slot `copyWithService`
/// writes is the password, which is where they keep their credential, and
/// `isServiceConfigured` only requires a URL of them anyway. A test that needs a
/// username as well should reach for `copyWithCredentials`.
SettingsModel settingsWithServices(List<ServiceKey> configured) {
  var settings = const SettingsModel();

  for (final service in configured) {
    settings = settings.copyWithService(
      service,
      url: 'https://${service.name}.test',
      apiKey: '${service.name}-key',
    );
  }

  return settings;
}

/// The four services that can appear in the global Activity feed.
const activityServiceKeys = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.seerr,
];

/// A [SettingsModel] built from the flat per-service names the model used to
/// store, for the eighty-odd fixtures that were written against them.
///
/// It lives here rather than on [SettingsModel] on purpose. Those names are the
/// shape that could not hold a second Radarr, and production has no business
/// with them any more, but a fixture saying `radarrUrl: 'http://nas:7878'` is
/// still the clearest way to say what a test is about, and rewriting eighty of
/// them into instance literals would be churn that serves no reader.
///
/// Values that stay empty write nothing, so the returned model carries an
/// instance only for the services a test actually named.
SettingsModel settingsWith({
  List<ServiceInstance> instances = const [],
  String seerrUrl = '',
  String seerrApiKey = '',
  String radarrUrl = '',
  String radarrApiKey = '',
  String sonarrUrl = '',
  String sonarrApiKey = '',
  String lidarrUrl = '',
  String lidarrApiKey = '',
  String bazarrUrl = '',
  String bazarrApiKey = '',
  String truenasUrl = '',
  String truenasApiKey = '',
  String prowlarrUrl = '',
  String prowlarrApiKey = '',
  String readarrUrl = '',
  String readarrApiKey = '',
  String sabnzbdUrl = '',
  String sabnzbdApiKey = '',
  String unraidUrl = '',
  String unraidApiKey = '',
  String jellyfinUrl = '',
  String jellyfinApiKey = '',
  String embyUrl = '',
  String embyApiKey = '',
  String qbittorrentUrl = '',
  String qbittorrentUsername = '',
  String qbittorrentPassword = '',
  String transmissionUrl = '',
  String transmissionUsername = '',
  String transmissionPassword = '',
  String npmUrl = '',
  String npmUsername = '',
  String npmPassword = '',
  String dockgeUrl = '',
  String dockgeUsername = '',
  String dockgePassword = '',
  String nzbgetUrl = '',
  String nzbgetUsername = '',
  String nzbgetPassword = '',
  String plexUrl = '',
  String plexToken = '',
  String jellyfinUserId = '',
  String embyUserId = '',
  String plexClientId = '',
  Map<String, String> trustedCertificates = const {},
  String region = 'US',
  AppThemeMode themeMode = AppThemeMode.system,
}) {
  var settings = SettingsModel(
    instances: instances,
    plexClientId: plexClientId,
    trustedCertificates: trustedCertificates,
    region: region,
    themeMode: themeMode,
  );
  settings = _api(settings, ServiceKey.seerr, seerrUrl, seerrApiKey);
  settings = _api(settings, ServiceKey.radarr, radarrUrl, radarrApiKey);
  settings = _api(settings, ServiceKey.sonarr, sonarrUrl, sonarrApiKey);
  settings = _api(settings, ServiceKey.lidarr, lidarrUrl, lidarrApiKey);
  settings = _api(settings, ServiceKey.bazarr, bazarrUrl, bazarrApiKey);
  settings = _api(settings, ServiceKey.truenas, truenasUrl, truenasApiKey);
  settings = _api(settings, ServiceKey.prowlarr, prowlarrUrl, prowlarrApiKey);
  settings = _api(settings, ServiceKey.readarr, readarrUrl, readarrApiKey);
  settings = _api(settings, ServiceKey.sabnzbd, sabnzbdUrl, sabnzbdApiKey);
  settings = _api(settings, ServiceKey.unraid, unraidUrl, unraidApiKey);
  settings = _api(settings, ServiceKey.jellyfin, jellyfinUrl, jellyfinApiKey);
  settings = _api(settings, ServiceKey.emby, embyUrl, embyApiKey);
  settings = _cred(
    settings,
    ServiceKey.qbittorrent,
    qbittorrentUrl,
    qbittorrentUsername,
    qbittorrentPassword,
  );
  settings = _cred(
    settings,
    ServiceKey.transmission,
    transmissionUrl,
    transmissionUsername,
    transmissionPassword,
  );
  settings = _cred(
    settings,
    ServiceKey.nginxProxyManager,
    npmUrl,
    npmUsername,
    npmPassword,
  );
  settings = _cred(
    settings,
    ServiceKey.dockge,
    dockgeUrl,
    dockgeUsername,
    dockgePassword,
  );
  settings = _cred(
    settings,
    ServiceKey.nzbget,
    nzbgetUrl,
    nzbgetUsername,
    nzbgetPassword,
  );
  settings = _api(settings, ServiceKey.plex, plexUrl, plexToken);
  if (jellyfinUserId.isNotEmpty) {
    settings = settings.copyWithViewer(ServiceKey.jellyfin, jellyfinUserId);
  }
  if (embyUserId.isNotEmpty) {
    settings = settings.copyWithViewer(ServiceKey.emby, embyUserId);
  }
  return settings;
}

SettingsModel _api(
  SettingsModel settings,
  ServiceKey service,
  String url,
  String apiKey,
) {
  if (url.isEmpty && apiKey.isEmpty) return settings;
  return settings.copyWithService(service, url: url, apiKey: apiKey);
}

SettingsModel _cred(
  SettingsModel settings,
  ServiceKey service,
  String url,
  String username,
  String password,
) {
  if (url.isEmpty && username.isEmpty && password.isEmpty) return settings;
  return settings.copyWithCredentials(
    service,
    url: url,
    username: username,
    password: password,
  );
}
