import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Android half of the secure store.
///
/// `resetOnError` is the plugin's default `true`: a Keystore error on any read
/// deletes every secret and pin on the device and answers as if none had ever
/// been saved, so the app would quietly start with connections that lost their
/// keys and certificates that are trusted no more. Off, the error reaches the
/// load, where one unreadable secret marks its connection
/// ([ServiceInstance.unreadSecret]) and a store that refuses every read stops
/// the start on a page that offers to forget the keys, as a choice the person
/// makes ([SecureStorageUnavailable]).
const secureStorageAndroidOptions = AndroidOptions(
  // flutter_secure_storage 10.x migrates away from the old
  // encryptedSharedPreferences path. Keep migration enabled for existing
  // installs and write a backup during algorithm upgrades.
  migrateWithBackup: true,
  resetOnError: false,
);

SecureSettingsStore createSecureSettingsStore() {
  // Keep secrets (API keys/passwords) out of iCloud/device backups by pinning
  // Keychain accessibility to this device only. Without this the default
  // accessibility lets credentials sync to backups.
  const deviceOnly = KeychainAccessibility.first_unlock_this_device;
  // An isolated build (the testlab, or the dev identity from
  // scripts/run_dev.sh) names a keychain service and, where the entitlement
  // carries one, an access group of its own. The defines keep the testlab's
  // names while its task owns them. The default build compiles neither and
  // keeps the house's keychain untouched.
  const keychainService = String.fromEnvironment(
    'CUPOLA_TESTLAB_KEYCHAIN_SERVICE',
  );
  const keychainGroup = String.fromEnvironment('CUPOLA_TESTLAB_KEYCHAIN_GROUP');
  if (keychainService.isNotEmpty) {
    return FlutterSecureSettingsStore(
      FlutterSecureStorage(
        aOptions: AndroidOptions(migrateWithBackup: true),
        iOptions: IOSOptions(
          accessibility: deviceOnly,
          accountName: keychainService,
          groupId: keychainGroup.isEmpty ? null : keychainGroup,
        ),
        mOptions: MacOsOptions(
          accessibility: deviceOnly,
          accountName: keychainService,
          groupId: keychainGroup.isEmpty ? null : keychainGroup,
          // A Mac testlab build cannot carry a Keychain group without a
          // provisioning profile Apple will not issue for a bundle id it has
          // never seen. The data-protection Keychain refuses to work without
          // that entitlement; the file-based Keychain does not, and the
          // service name still gives the testlab its own items.
          usesDataProtectionKeychain: keychainGroup.isNotEmpty,
        ),
      ),
    );
  }
  return FlutterSecureSettingsStore(
    FlutterSecureStorage(
      aOptions: secureStorageAndroidOptions,
      iOptions: const IOSOptions(accessibility: deviceOnly),
      mOptions: const MacOsOptions(accessibility: deviceOnly),
    ),
  );
}

abstract interface class SecureSettingsStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});

  Future<void> deleteAll();
}

class FlutterSecureSettingsStore implements SecureSettingsStore {
  final FlutterSecureStorage _storage;

  const FlutterSecureSettingsStore(this._storage);

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }

  @override
  Future<void> deleteAll() {
    return _storage.deleteAll();
  }
}

/// Secure storage refused every read of a load: not one secret came back.
///
/// One unreadable secret marks its connection ([ServiceInstance.unreadSecret])
/// and the app starts without it; when none can be read the store itself is
/// down, and the start stops on a page that says so. [cause] is the first
/// read's own error, for its words behind Why?.
class SecureStorageUnavailable implements Exception {
  const SecureStorageUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'SecureStorageUnavailable($cause)';
}

class SettingsService {
  static const _kRegion = 'region';
  static const _kThemeMode = 'theme_mode';
  static const _kOnboardingComplete = 'onboarding_complete';

  /// The connections whose secrets [forgetSecrets] dropped, until each one's
  /// is pasted again: they load marked [UnreadSecret.credential], so each asks
  /// for its key rather than reading as never set up.
  static const _kForgottenSecrets = 'forgotten_secrets';

  /// Secure-storage key for the whole origin→fingerprint trust map (ADR-6).
  /// One entry, JSON-encoded, rather than one key per service; the map is
  /// keyed by TLS origin, not by `ServiceKey`, so there is no per-service key
  /// to hang it on.
  static const _kTrustedCertificates = 'secure_trusted_certificates';

  /// The ordered list of configured connections: `[{id, service, label}, ...]`.
  ///
  /// Every value a connection holds already lives under keys derived from its
  /// id, so this carries no addresses and no secrets; only which ids exist,
  /// what kind of server each is, and in what order the user put them. That is
  /// the part nothing else on disk can tell you: a primary is discoverable by
  /// walking the enum, but nothing announces that `radarr-a1b2c3d` is out
  /// there waiting to be read.
  ///
  /// Absent on an install that predates multi-instance, which is exactly the
  /// migration: [loadSettings] falls back to walking the enum and produces
  /// the same list it always did. The roster appears on the next save.
  static const _kInstanceRoster = 'service_instances';

  /// Which instance of each service the UI is currently looking through:
  /// `{serviceName: instanceId}`.
  ///
  /// Kept apart from the roster, and apart from [SettingsModel], because it is
  /// a *view* rather than configuration. Folding it into the settings blob
  /// would make changing lens look like a settings write, and a settings write
  /// re-probes every service, which is a connection storm for what is really a
  /// tab change.
  static const _kActiveInstances = 'active_instances';
  static const _kConnectionRoutes = 'connection_routes';

  /// Where TrueNAS's and Dockge's fingerprints lived under ADR-5, kept only
  /// so [_loadTrustedCertificates] can migrate an existing install once.
  static const _legacyTrueNasCertFingerprint = 'truenas_cert_fingerprint';
  static const _legacyDockgeCertFingerprint = 'dockge_cert_fingerprint';

  static const Map<ServiceKey, _ServiceStorageKeys> _serviceStorageKeys = {
    ServiceKey.seerr: _ServiceStorageKeys(
      url: 'seerr_url',
      legacyApiKey: 'seerr_api_key',
      secureApiKey: 'secure_seerr_api_key',
      legacyUrl: 'jellyseerr_url',
      legacyPlaintextApiKey: 'jellyseerr_api_key',
      legacySecureApiKey: 'secure_jellyseerr_api_key',
    ),
    ServiceKey.radarr: _ServiceStorageKeys(
      url: 'radarr_url',
      legacyApiKey: 'radarr_api_key',
      secureApiKey: 'secure_radarr_api_key',
    ),
    ServiceKey.sonarr: _ServiceStorageKeys(
      url: 'sonarr_url',
      legacyApiKey: 'sonarr_api_key',
      secureApiKey: 'secure_sonarr_api_key',
    ),
    ServiceKey.lidarr: _ServiceStorageKeys(
      url: 'lidarr_url',
      legacyApiKey: 'lidarr_api_key',
      secureApiKey: 'secure_lidarr_api_key',
    ),
    ServiceKey.qbittorrent: _ServiceStorageKeys(
      url: 'qbittorrent_url',
      legacyApiKey: '',
      secureApiKey: 'secure_qbittorrent_password',
      username: 'qbittorrent_username',
    ),
    ServiceKey.transmission: _ServiceStorageKeys(
      url: 'transmission_url',
      legacyApiKey: '',
      secureApiKey: 'secure_transmission_password',
      username: 'transmission_username',
    ),
    // Keyed `npm_*` to match `routeParam`, so a storage key, a route segment
    // and a fixture directory all spell the service the same way.
    ServiceKey.nginxProxyManager: _ServiceStorageKeys(
      url: 'npm_url',
      legacyApiKey: '',
      secureApiKey: 'secure_npm_password',
      username: 'npm_username',
    ),
    ServiceKey.bazarr: _ServiceStorageKeys(
      url: 'bazarr_url',
      legacyApiKey: '',
      secureApiKey: 'secure_bazarr_api_key',
    ),
    ServiceKey.truenas: _ServiceStorageKeys(
      url: 'truenas_url',
      legacyApiKey: '',
      secureApiKey: 'secure_truenas_api_key',
    ),
    ServiceKey.dockge: _ServiceStorageKeys(
      url: 'dockge_url',
      legacyApiKey: '',
      secureApiKey: 'secure_dockge_password',
      username: 'dockge_username',
    ),
    ServiceKey.prowlarr: _ServiceStorageKeys(
      url: 'prowlarr_url',
      legacyApiKey: '',
      secureApiKey: 'secure_prowlarr_api_key',
    ),
    ServiceKey.readarr: _ServiceStorageKeys(
      url: 'readarr_url',
      legacyApiKey: '',
      secureApiKey: 'secure_readarr_api_key',
    ),
    ServiceKey.sabnzbd: _ServiceStorageKeys(
      url: 'sabnzbd_url',
      legacyApiKey: '',
      secureApiKey: 'secure_sabnzbd_api_key',
    ),
    ServiceKey.nzbget: _ServiceStorageKeys(
      url: 'nzbget_url',
      legacyApiKey: '',
      secureApiKey: 'secure_nzbget_password',
      username: 'nzbget_username',
    ),
    ServiceKey.unraid: _ServiceStorageKeys(
      url: 'unraid_url',
      legacyApiKey: '',
      secureApiKey: 'secure_unraid_api_key',
    ),
    ServiceKey.jellyfin: _ServiceStorageKeys(
      url: 'jellyfin_url',
      legacyApiKey: '',
      secureApiKey: 'secure_jellyfin_api_key',
      userId: 'jellyfin_user_id',
    ),
    ServiceKey.plex: _ServiceStorageKeys(
      url: 'plex_url',
      legacyApiKey: '',
      secureApiKey: 'secure_plex_token',
      clientId: 'plex_client_id',
    ),
    // The viewer id is Jellyfin's pattern: an Emby API key has no user, so the
    // household member the lenses read as is chosen once and kept beside it.
    ServiceKey.emby: _ServiceStorageKeys(
      url: 'emby_url',
      legacyApiKey: '',
      secureApiKey: 'secure_emby_api_key',
      userId: 'emby_user_id',
    ),
  };

  final SharedPreferences _prefs;
  final SecureSettingsStore _secureStore;

  SettingsService(this._prefs, this._secureStore);

  Future<void> migrateFromPlaintext() async {
    for (final storageKeys in _serviceStorageKeys.values) {
      // Migrate legacy plaintext API keys from before the Seerr rename.
      if (storageKeys.legacyPlaintextApiKey != null) {
        final legacyPlaintext = _prefs.getString(
          storageKeys.legacyPlaintextApiKey!,
        );
        if (legacyPlaintext != null) {
          final normalized = legacyPlaintext.trim();
          if (normalized.isNotEmpty) {
            final existing = await _secureStore.read(
              key: storageKeys.secureApiKey,
            );
            if (existing == null || existing.isEmpty) {
              await _secureStore.write(
                key: storageKeys.secureApiKey,
                value: normalized,
              );
            }
          }
          await _prefs.remove(storageKeys.legacyPlaintextApiKey!);
        }
      }

      // Migrate current plaintext API keys to secure storage.
      final plaintextValue = _prefs.getString(storageKeys.legacyApiKey);
      if (plaintextValue == null) {
        continue;
      }

      final normalizedValue = plaintextValue.trim();
      final secureValue = await _secureStore.read(
        key: storageKeys.secureApiKey,
      );

      if (normalizedValue.isNotEmpty &&
          (secureValue == null || secureValue.isEmpty)) {
        await _secureStore.write(
          key: storageKeys.secureApiKey,
          value: normalizedValue,
        );
      }

      await _prefs.remove(storageKeys.legacyApiKey);
    }
  }

  /// The lens the user last used for each service.
  ///
  /// Synchronous: `SharedPreferences` is already in memory by the time anything
  /// asks, and making this a `Future` would put an async gap in front of the
  /// first frame of every service screen.
  ///
  /// Entries naming a service this build does not have are dropped. An entry
  /// naming an instance that no longer exists is *kept* here and resolved away
  /// at read time. This class does not know what exists, and silently editing
  /// the user's last choice on load would lose it the moment a settings file
  /// was read before the instance list was.
  Map<ServiceKey, String> loadActiveInstances() {
    final raw = _prefs.getString(_kActiveInstances);
    if (raw == null || raw.isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};

      final lenses = <ServiceKey, String>{};
      decoded.forEach((name, id) {
        if (name is! String || id is! String || id.isEmpty) return;
        final service = ServiceKey.values
            .where((candidate) => candidate.name == name)
            .firstOrNull;
        if (service != null) lenses[service] = id;
      });
      return lenses;
    } on FormatException {
      return const {};
    }
  }

  Future<void> saveActiveInstances(Map<ServiceKey, String> lenses) async {
    if (lenses.isEmpty) {
      await _prefs.remove(_kActiveInstances);
      return;
    }
    await _prefs.setString(
      _kActiveInstances,
      jsonEncode({
        for (final entry in lenses.entries) entry.key.name: entry.value,
      }),
    );
  }

  /// The connections last reached at their address away from home, by id.
  ///
  /// Synchronous, as [loadActiveInstances] is: a cold start away from home
  /// goes straight to the address that answered last, before any probe. Only
  /// [ConnectionRoute.away] is stored; every other connection is at home. An
  /// id that names no connection any more is harmless: a route is only read
  /// for a connection that has an address away.
  Map<String, ConnectionRoute> loadConnectionRoutes() {
    final raw = _prefs.getString(_kConnectionRoutes);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return {
        for (final id in decoded)
          if (id is String && id.isNotEmpty) id: ConnectionRoute.away,
      };
    } on FormatException {
      return const {};
    }
  }

  Future<void> saveConnectionRoutes(Map<String, ConnectionRoute> routes) async {
    final away = [
      for (final MapEntry(:key, :value) in routes.entries)
        if (value == ConnectionRoute.away) key,
    ]..sort();
    if (away.isEmpty) {
      await _prefs.remove(_kConnectionRoutes);
    } else {
      await _prefs.setString(_kConnectionRoutes, jsonEncode(away));
    }
  }

  Future<bool> loadOnboardingComplete() async {
    return _prefs.getBool(_kOnboardingComplete) ?? false;
  }

  Future<void> saveOnboardingComplete() async {
    await _prefs.setBool(_kOnboardingComplete, true);
  }

  /// Wipes all Cupola-persisted data: SharedPreferences keys (service URLs,
  /// credentials, region, theme, onboarding flag, legacy keys) and every
  /// secure-storage entry. Clears secure storage first so a Keychain failure
  /// leaves prefs intact and the caller can surface an error.
  Future<void> clearAll() async {
    // Whatever is saved next starts from an empty disk.
    _swept = false;
    // Read before the wipe: the roster is the only thing that knows an extra
    // instance's id, and once it is gone its keys are unreachable by name.
    final roster = _readRoster();

    await _secureStore.deleteAll();

    // `deleteAll` on the macOS file-based Keychain can report success while
    // leaving the trust map behind: it is written without a synchronizable
    // attribute, and the plugin's "delete every item" query only tries the
    // two explicit synchronizable states. The map is integrity-critical, so a
    // wipe names it rather than trusting the sweep.
    await _secureStore.delete(key: _kTrustedCertificates);

    for (final entry in roster) {
      await _forgetInstance(
        ServiceInstance(id: entry.id, service: entry.service),
      );
    }
    await _prefs.remove(_kInstanceRoster);
    await _prefs.remove(_kActiveInstances);
    await _prefs.remove(_kConnectionRoutes);

    // A primary's access, address away and Seerr account, for the install whose roster
    // lost a write: the roster is what the loop above walked.
    for (final service in ServiceKey.values) {
      final primary = ServiceInstance(
        id: ServiceInstance.primaryIdFor(service),
        service: service,
      );
      await _prefs.remove(primary.accessStorageKey);
      await _prefs.remove(primary.awayUrlStorageKey);
      await _prefs.remove(primary.awayAccessStorageKey);
      await _prefs.remove(primary.accountStorageKey);
    }

    for (final storageKeys in _serviceStorageKeys.values) {
      await _prefs.remove(storageKeys.url);
      await _prefs.remove(storageKeys.legacyApiKey);
      if (storageKeys.legacyUrl != null) {
        await _prefs.remove(storageKeys.legacyUrl!);
      }
      if (storageKeys.legacyPlaintextApiKey != null) {
        await _prefs.remove(storageKeys.legacyPlaintextApiKey!);
      }
      if (storageKeys.username != null) {
        await _prefs.remove(storageKeys.username!);
      }
      if (storageKeys.userId != null) {
        await _prefs.remove(storageKeys.userId!);
      }
      // The client id goes too. It is not a credential, but leaving it behind
      // would tie a freshly set-up install to the device row the old one
      // registered on the user's Plex server.
      if (storageKeys.clientId != null) {
        await _prefs.remove(storageKeys.clientId!);
      }
    }

    // `_secureStore.deleteAll()` above already wipes the secure copy of the
    // trust map and of both legacy fingerprints; only a plaintext-prefs
    // fallback left by an older build needs an explicit remove here.
    await _prefs.remove(_legacyTrueNasCertFingerprint);
    await _prefs.remove(_legacyDockgeCertFingerprint);

    await _prefs.remove(_kRegion);
    await _prefs.remove(_kThemeMode);
    await _prefs.remove(_kOnboardingComplete);
    await _prefs.remove(_kForgottenSecrets);
    await _prefs.remove('hidden_tabs');
  }

  Future<SettingsModel> loadSettings() async {
    _unreadKeys.clear();
    _secretReads = 0;
    _secretFailures = 0;
    _firstReadError = null;
    final serviceSettings = await _loadServiceSettings();
    // The passwords come out of the same generic credential slot every other
    // service's key does (see [_loadServiceSettings]). The usernames need their
    // own pass, because they are the half of the pair that has no generic slot;
    // driving it off the storage table rather than naming each service means a
    // new credential service is one map entry rather than a line here that is
    // easy to forget and that nothing would fail without.
    final usernames = _loadUsernames();
    final trustedCertificates = await _loadTrustedCertificates(serviceSettings);
    // Every service that reads as a household member keeps one beside its
    // address (Jellyfin and Emby: an API key has no user behind it).
    final viewers = {
      for (final service in ServiceKey.values)
        if (_serviceStorageKeys[service]!.userId case final key?)
          service: _prefs.getString(key) ?? '',
    };
    final plexClientId = await _loadOrCreatePlexClientId();

    // Only the values with no `ServiceKey` to hang them on are named here;
    // everything per-service is folded in below, through the same registry that
    // produced it. Naming all 18 services a third time in a constructor literal
    // is the hazard `copyWithCredentials` was written to kill; see its doc.
    var model = SettingsModel(
      plexClientId: plexClientId,
      trustedCertificates: trustedCertificates,
      region: _loadRegion(),
      themeMode: AppThemeMode.fromName(_prefs.getString(_kThemeMode)),
    );
    for (final service in ServiceKey.values) {
      final (url, credential) = serviceSettings[service]!;
      model = model.copyWithService(service, url: url, apiKey: credential);

      // The guard is load-bearing, not cosmetic: `copyWithCredentials` asserts
      // the service has a username half, and `_loadUsernames` returns `''` for
      // exactly the services that do not: the ones whose `_ServiceStorageKeys`
      // entry has no `username`, i.e. the API-key services. Skipping the empty
      // case is what keeps that assert satisfied, and it drops nothing: `''` is
      // already the field's default.
      final username = usernames[service]!;
      if (username.isNotEmpty) {
        model = model.copyWithCredentials(service, username: username);
      }
    }

    // Applied after the loop rather than in the constructor, because the viewer
    // now belongs to a media server *instance* and the loop above is what
    // creates one. Setting it first would have nowhere to land, and doing it
    // here cannot conjure an instance out of nothing either: an unconfigured
    // server has no address, so `_upsertPrimary` declines to mint one and the
    // orphaned id is dropped rather than resurrected.
    for (final MapEntry(key: service, value: viewerId) in viewers.entries) {
      if (viewerId.isNotEmpty) model = model.copyWithViewer(service, viewerId);
    }

    final roster = _readRoster();
    final extras = await _loadExtraInstances(roster);
    final ordered = _ordered([...model.instances, ...extras], roster);
    // Each connection's access and Seerr account, from the keys its id
    // derives: one pass for the primaries and the extras alike, since neither
    // path above knows of them.
    final instances = [
      for (final instance in ordered)
        await _withAccount(
          instance.copyWith(
            access: await _loadAccess(instance),
            away: await _loadAway(instance),
          ),
        ),
    ];

    if (_firstReadError case final error?
        when _secretFailures == _secretReads) {
      throw SecureStorageUnavailable(error);
    }

    return model.copyWith(
      instances: List.unmodifiable([
        for (final instance in instances) _markUnread(instance),
      ]),
    );
  }

  /// Drops every secret in secure storage and keeps everything else:
  /// addresses, usernames, Home, the preferences. The way on when secure
  /// storage hands nothing over and asking again cannot help (a key store
  /// lost to a system update); each connection then asks for its secret
  /// again ([_kForgottenSecrets]).
  ///
  /// Throws what secure storage throws: a store that will not even be
  /// emptied is one Cupola cannot keep secrets in.
  Future<void> forgetSecrets() async {
    // What the next save finds on disk is no longer what the last one wrote.
    _swept = false;
    final ids = {
      for (final entry in _readRoster()) entry.id,
      for (final service in ServiceKey.values)
        if (_loadString(_serviceStorageKeys[service]!.url).isNotEmpty)
          ServiceInstance.primaryIdFor(service),
    };
    await _prefs.setStringList(_kForgottenSecrets, ids.toList()..sort());
    await _secureStore.deleteAll();
  }

  Set<String> _forgottenSecrets() =>
      (_prefs.getStringList(_kForgottenSecrets) ?? const []).toSet();

  /// [instance], marked with the secret this load could not read.
  ServiceInstance _markUnread(ServiceInstance instance) {
    // A sign-in service with no username ran without one (behind a proxy
    // that does the signing in), so it had no password to lose.
    if (instance.credential.isEmpty &&
        (instance.service.usesApiKey || instance.username.isNotEmpty) &&
        instance.account == null &&
        _forgottenSecrets().contains(instance.id)) {
      return instance.withUnreadSecret(UnreadSecret.credential);
    }
    if (_unreadKeys.isEmpty) return instance;
    final legacy = instance.isPrimarySlot
        ? _serviceStorageKeys[instance.service]!.legacySecureApiKey
        : null;
    if (_unreadKeys.contains(instance.credentialStorageKey) ||
        (legacy != null && _unreadKeys.contains(legacy))) {
      return instance.withUnreadSecret(UnreadSecret.credential);
    }
    final accessPrefixes = [
      'secure_${instance.id}_access',
      'secure_${instance.id}_away_access',
    ];
    if (_unreadKeys.any(
      (key) => accessPrefixes.any((prefix) => key.startsWith(prefix)),
    )) {
      return instance.withUnreadSecret(UnreadSecret.access);
    }
    return instance;
  }

  /// The roster as stored, or empty when there is none to read.
  ///
  /// Tolerant on purpose. A roster that will not parse, or that names a service
  /// this build does not have, must not take the user's whole configuration
  /// down with it: every value is still reachable through the keys derived from
  /// its id, and the enum walk in [loadSettings] finds the primaries regardless.
  /// A bad roster costs the *order* and any extra instances, and is repaired by
  /// the next save.
  List<({String id, ServiceKey service, String label})> _readRoster() {
    final raw = _prefs.getString(_kInstanceRoster);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final entries = <({String id, ServiceKey service, String label})>[];
      for (final row in decoded) {
        if (row is! Map) continue;
        final id = row['id'];
        final serviceName = row['service'];
        if (id is! String || id.isEmpty || serviceName is! String) continue;

        final service = ServiceKey.values
            .where((candidate) => candidate.name == serviceName)
            .firstOrNull;
        if (service == null) continue;

        final label = row['label'];
        entries.add((
          id: id,
          service: service,
          label: label is String ? label : '',
        ));
      }
      return entries;
    } on FormatException {
      return const [];
    }
  }

  /// The instances the enum walk cannot find: everything whose id is not the
  /// primary slot of its service.
  Future<List<ServiceInstance>> _loadExtraInstances(
    List<({String id, ServiceKey service, String label})> roster,
  ) async {
    final extras = <ServiceInstance>[];

    for (final entry in roster) {
      if (entry.id == ServiceInstance.primaryIdFor(entry.service)) continue;

      final skeleton = ServiceInstance(id: entry.id, service: entry.service);
      var url = _loadString(skeleton.urlStorageKey);
      final schemed = _schemeQualified(entry.service, url);
      if (schemed != null) {
        url = schemed;
        await _prefs.setString(skeleton.urlStorageKey, url);
      }

      extras.add(
        skeleton.copyWith(
          label: entry.label,
          url: url,
          credential: await _loadApiKey(skeleton.credentialStorageKey),
          username: _loadString(skeleton.usernameStorageKey),
          viewerId: _loadString(skeleton.viewerIdStorageKey),
        ),
      );
    }
    return extras;
  }

  /// [loaded] in the user's saved order, with anything the roster does not
  /// mention kept rather than dropped.
  ///
  /// Order is meaning here: the first instance of a service is the one a bare
  /// route resolves to, so it is restored from the roster rather than left to
  /// enum declaration order. The tail is the safety net: an instance present on
  /// disk but missing from the roster is a roster that lost a write, and the
  /// answer to that is to show the connection, not to hide it.
  List<ServiceInstance> _ordered(
    List<ServiceInstance> loaded,
    List<({String id, ServiceKey service, String label})> roster,
  ) {
    if (roster.isEmpty) return List.unmodifiable(loaded);

    final byId = {for (final instance in loaded) instance.id: instance};
    final ordered = <ServiceInstance>[];

    for (final entry in roster) {
      final instance = byId.remove(entry.id);
      if (instance == null) continue;
      // The label lives only in the roster; the value keys carry the rest.
      ordered.add(instance.copyWith(label: entry.label));
    }
    ordered.addAll(byId.values);
    return List.unmodifiable(ordered);
  }

  /// Whether a whole-model save has gone through in this process; see
  /// [saveSettings].
  bool _swept = false;

  /// Persists [settings].
  ///
  /// With [previous], the model the last successful save wrote, only what
  /// differs from it is written: a theme change no longer rewrites every
  /// connection's keys and secrets. Without it, or on the first save of the
  /// process whatever is passed, everything is written and the passes that
  /// only a whole save can do run: forgetting the primary slots nothing
  /// occupies, and clearing what a renamed service left under its old keys
  /// (which the load still falls back to, so only after the values are
  /// written under the new ones). A save that stops halfway leaves [previous]
  /// where it was, so the next one writes the same difference again.
  ///
  /// [previous] must be what was last written, never a model that has not been
  /// saved yet: the difference is all that is written.
  ///
  /// A save that throws leaves part of its difference on disk, so the next one
  /// is a whole save whatever it is given: otherwise a value that the failed
  /// save wrote and a later model no longer differs on would stay as written.
  Future<void> saveSettings(
    SettingsModel settings, {
    SettingsModel? previous,
  }) async {
    final base = _swept ? previous : null;
    _swept = false;
    await _write(settings, base);
    _swept = true;
  }

  Future<void> _write(SettingsModel settings, SettingsModel? base) async {
    final normalizedRegion = SettingsModel.normalizeRegion(settings.region);

    await _saveInstances(settings, previous: base);
    if (base == null ||
        SettingsModel.normalizeRegion(base.region) != normalizedRegion) {
      await _prefs.setString(_kRegion, normalizedRegion);
    }
    if (base == null || base.themeMode != settings.themeMode) {
      await _prefs.setString(_kThemeMode, settings.themeMode.name);
    }
    if (base == null) await _prefs.remove('hidden_tabs');

    if (base == null ||
        !mapEquals(base.trustedCertificates, settings.trustedCertificates)) {
      await _saveTrustedCertificates(settings.trustedCertificates);
    }

    // Deliberately *not* written from `settings`. The client id is owned by
    // `_loadOrCreatePlexClientId`, which mints it once; honouring an incoming
    // empty value here, which every `SettingsModel()` default carries, would
    // clear it on the next unrelated save and hand the user's Plex server a new
    // device row on the following load.
    if (settings.plexClientId.isNotEmpty &&
        (base == null || base.plexClientId != settings.plexClientId)) {
      final plexKeys = _serviceStorageKeys[ServiceKey.plex]!;
      await _prefs.setString(plexKeys.clientId!, settings.plexClientId);
    }
  }

  /// Every service's saved username, `''` for those that have none.
  ///
  /// Keyed by [ServiceKey] and complete for all of them, so [loadSettings] can
  /// index it with `!` for the credential services without deciding anywhere
  /// else which services those are: the presence of a `username` storage key
  /// is the whole of that decision.
  Map<ServiceKey, String> _loadUsernames() {
    return {
      for (final entry in _serviceStorageKeys.entries)
        entry.key: entry.value.username == null
            ? ''
            : _prefs.getString(entry.value.username!) ?? '',
    };
  }

  /// Writes every credential service's username, clearing the key when the
  /// value is empty so a removed connection leaves nothing behind.
  ///
  /// A username is not a secret and stays in [SharedPreferences] beside the
  /// URL; only the password half goes to the Keychain, via [_saveServiceApiKeys].

  /// Reads the persisted `X-Plex-Client-Identifier`, minting one on first use.
  ///
  /// Write-on-read is unusual but correct here and already precedented in this
  /// file by [_loadCertFingerprint]'s prefs→secure migration. The alternative:
  /// generating at connect time leaves a window where two concurrent requests
  /// each mint their own id, and Plex would record both as separate devices.
  ///
  /// Shaped as a v4 UUID because that is what every Plex client sends, but built
  /// from [Random.secure] rather than a `uuid` dependency: the project does not
  /// take new packages without approval, and nothing here needs more than 122
  /// random bits.
  Future<String> _loadOrCreatePlexClientId() async {
    final key = _serviceStorageKeys[ServiceKey.plex]!.clientId!;
    final existing = _prefs.getString(key)?.trim() ?? '';
    if (existing.isNotEmpty) return existing;

    final generated = _randomUuidV4();
    await _prefs.setString(key, generated);
    return generated;
  }

  static String _randomUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// Persists the whole trust-on-first-use map (ADR-6).
  ///
  /// Stored in secure storage rather than SharedPreferences: a fingerprint is
  /// not a secret, but it *is* integrity-critical: whoever can write one can
  /// pin their own certificate, after which `buildPinnedHttpClient` accepts
  /// it and every credential sent to that origin is captured. An empty map
  /// deletes the key outright rather than writing `'{}'`, so an install that
  /// never trusts anything never gains a secure-storage entry.
  Future<void> _saveTrustedCertificates(Map<String, String> value) async {
    if (value.isEmpty) {
      await _secureStore.delete(key: _kTrustedCertificates);
      return;
    }
    await _secureStore.write(
      key: _kTrustedCertificates,
      value: jsonEncode(value),
    );
  }

  /// Reads the trust map, migrating ADR-5's two per-service fingerprints
  /// (TrueNAS, Dockge) into ADR-6's origin-keyed map on an existing install.
  ///
  /// [serviceSettings] is the caller's already-loaded URLs, reused rather
  /// than re-read, since resolving a legacy fingerprint to an origin needs
  /// that service's saved URL. A legacy fingerprint whose URL is empty or
  /// unparseable as a TLS origin cannot be placed anywhere and is dropped;
  /// the user re-trusts on next connect (accepted in ADR-6, not a bug).
  /// Migration writes the new key and removes both legacy ones so it runs
  /// exactly once per install.
  Future<Map<String, String>> _loadTrustedCertificates(
    Map<ServiceKey, (String, String)> serviceSettings,
  ) async {
    final stored = await _loadApiKey(_kTrustedCertificates);
    if (stored.isNotEmpty) {
      try {
        final decoded = jsonDecode(stored) as Map<String, dynamic>;
        return decoded.map(
          (origin, fingerprint) => MapEntry(origin, fingerprint as String),
        );
      } catch (_) {
        // A future build's shape, or a hand-edited value: treated as no
        // trusted certificates rather than crashing startup.
        return {};
      }
    }

    const legacyKeysByService = {
      ServiceKey.truenas: _legacyTrueNasCertFingerprint,
      ServiceKey.dockge: _legacyDockgeCertFingerprint,
    };
    final migrated = <String, String>{};
    var foundLegacy = false;

    for (final entry in legacyKeysByService.entries) {
      final fingerprint = await _loadLegacyCertFingerprint(entry.value);
      if (fingerprint.isEmpty) continue;
      foundLegacy = true;

      final url = serviceSettings[entry.key]?.$1 ?? '';
      final origin = UrlUtils.certOrigin(url);
      if (origin != null) migrated[origin] = fingerprint;
    }

    if (foundLegacy) {
      await _saveTrustedCertificates(migrated);
      await _secureStore.delete(key: _legacyTrueNasCertFingerprint);
      await _secureStore.delete(key: _legacyDockgeCertFingerprint);
      await _prefs.remove(_legacyTrueNasCertFingerprint);
      await _prefs.remove(_legacyDockgeCertFingerprint);
    }

    return migrated;
  }

  /// Mirrors ADR-5's `_loadCertFingerprint` prefs→secure fallback, kept only
  /// so [_loadTrustedCertificates] can migrate a value an older build may
  /// have left in either store.
  Future<String> _loadLegacyCertFingerprint(String key) async {
    final secure = await _loadApiKey(key);
    if (secure.isNotEmpty) return secure;
    return _prefs.getString(key)?.trim() ?? '';
  }

  /// The only services whose stored scheme-less URL ever meant `http://`.
  ///
  /// Both clients prepended `http://` to a scheme-less address until 9128220
  /// ("default qBittorrent/Dockge to TLS") changed them to `https://`. Every
  /// other service either always resolved a scheme-less value to `https://`
  /// (SABnzbd, NZBGet, Unraid and TrueNAS all shipped with the https default) or
  /// never worked without a scheme at all: the \*arrs go through `ApiClient`,
  /// which handed the raw value to `BaseOptions.baseUrl`, and Dio's own setter
  /// throws `ArgumentError` on `sonarr.lan:8989`.
  ///
  /// So this set is the exact blast radius of that one commit, and it is what
  /// keeps [_schemeQualified] from being a downgrade; see its doc.
  static const Set<ServiceKey> _cleartextByDefaultBeforeTls = {
    ServiceKey.qbittorrent,
    ServiceKey.dockge,
  };

  /// One-shot migration for a stored service URL saved before addresses were
  /// normalised on the way in, returning the rewritten value, or null when there
  /// is nothing to migrate.
  ///
  /// Older builds wrote the address field verbatim, and qBittorrent's own field
  /// had no validator at all, so a perfectly working install can hold
  /// `192.168.1.5:8080`. Nothing writes such a value any more: both the settings
  /// form and onboarding run [UrlUtils.normalizeBaseUrl] before saving, so a
  /// scheme-less value in storage is by definition pre-normalisation data.
  ///
  /// It is rewritten to **`http://`**, and only for
  /// [_cleartextByDefaultBeforeTls]. The direction is the whole point of the
  /// migration for those two: their clients prepended `http://` themselves, so
  /// the stored value ran over cleartext, and once the app-wide rule became
  /// `https://` that same value silently started meaning a different address and
  /// died in the TLS handshake with no fallback. Writing the scheme the config
  /// actually ran on preserves what the user set up, and the settings form warns
  /// about cleartext to a non-local host if they ever open it.
  ///
  /// Applying it to every service was the bug this scoping fixes: for everything
  /// else a scheme-less value has always resolved to `https://`, so rewriting it
  /// destroyed a working TLS config, sending the TrueNAS API key over `ws://`
  /// and the Dockge login over cleartext, and orphaning the origin's trusted
  /// certificate, since [UrlUtils.certOrigin] returns null for an `http://` URL
  /// and the pin is stored under `https://host:443`.
  ///
  /// Returns null, leaving the value untouched, when the service is not one of
  /// the two, when the URL already carries a scheme, is empty, or does not
  /// resolve to a host once one is added, since there is then no working
  /// configuration to preserve.
  static String? _schemeQualified(ServiceKey service, String url) {
    if (!_cleartextByDefaultBeforeTls.contains(service)) return null;
    return _httpQualified(url);
  }

  static String? _httpQualified(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    // The same "has a scheme" test the clients apply, and deliberately not a
    // general scheme regex: `sonarr.lan:8989` matches one of those, which is the
    // whole reason a host and a scheme cannot be told apart by the colon alone.
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }
    // Some other scheme entirely: never a working Cupola address, and not
    // this migration's business to rewrite.
    if (trimmed.contains('://')) return null;

    final candidate = 'http://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) return null;
    return candidate;
  }

  Future<Map<ServiceKey, (String, String)>> _loadServiceSettings() async {
    final settingsByService = <ServiceKey, (String, String)>{};

    for (final service in ServiceKey.values) {
      final storageKeys = _serviceStorageKeys[service]!;

      // Load URL, falling back to legacy key if the new key is empty.
      var url = _loadString(storageKeys.url);
      if (url.isEmpty && storageKeys.legacyUrl != null) {
        url = _loadString(storageKeys.legacyUrl!);
      }

      final schemed = _schemeQualified(service, url);
      if (schemed != null) {
        url = schemed;
        // Written back so the rewrite happens once rather than on every load,
        // the same one-shot shape `_loadTrustedCertificates` uses for ADR-5's
        // fingerprints. `_saveServiceUrls` would eventually persist it too, but
        // only if the user saves something, and a config that has stopped
        // connecting is exactly the one nobody opens settings for.
        await _prefs.setString(storageKeys.url, url);
      }

      // Load the credential, falling back to the legacy secure key.
      //
      // One read per service, whatever the auth model: a credential-
      // authenticated service keeps its *password* under `secureApiKey`, which
      // is exactly what `SettingsModel.apiKeyFor` returns for it. Special-casing
      // those three here was a third copy of a decision the registry already
      // owns, and it bought nothing: the read it skipped had to happen in
      // `loadSettings` instead.
      var apiKey = await _loadApiKey(storageKeys.secureApiKey);
      if (apiKey.isEmpty && storageKeys.legacySecureApiKey != null) {
        apiKey = await _loadApiKey(storageKeys.legacySecureApiKey!);
      }

      settingsByService[service] = (url, apiKey);
    }

    return settingsByService;
  }

  String _loadString(String key) {
    return _prefs.getString(key) ?? '';
  }

  String _loadRegion() {
    return SettingsModel.normalizeRegion(
      _prefs.getString(_kRegion) ??
          PlatformDispatcher.instance.locale.countryCode,
    );
  }

  /// Writes every connection to the keys derived from its id, forgets the ones
  /// that are gone, and records the roster.
  ///
  /// Replaces three per-service passes that each walked the enum. They could
  /// only ever see one connection per service, which is the limitation this
  /// whole change exists to remove.
  Future<void> _saveInstances(
    SettingsModel settings, {
    required SettingsModel? previous,
  }) async {
    final written = {
      for (final instance in previous?.instances ?? const <ServiceInstance>[])
        instance.id: instance,
    };
    for (final instance in settings.instances) {
      // What is on disk already is what this instance is: its keys are
      // independent of the others, so nothing else needs its write.
      if (previous != null && written[instance.id] == instance) continue;
      await _prefs.setString(instance.urlStorageKey, instance.url);
      // A secret this run could not read is left where it is: written back,
      // the empty value it loaded as would delete it.
      if (instance.unreadSecret != UnreadSecret.credential) {
        await _saveApiKey(instance.credentialStorageKey, instance.credential);
      }
      await _writeOrRemove(instance.usernameStorageKey, instance.username);
      await _writeOrRemove(instance.viewerIdStorageKey, instance.viewerId);
      await _writeOrRemove(
        instance.awayUrlStorageKey,
        instance.away?.url ?? '',
      );
      if (instance.unreadSecret != UnreadSecret.access) {
        await _saveAccess(instance);
        await _saveAccessAt(
          _awayAccessKeys(instance),
          instance.away?.access ?? const NoAccess(),
        );
      }
      await _saveAccount(instance);
    }

    final live = {for (final instance in settings.instances) instance.id};

    // A forgotten secret pasted again, or its connection gone: off the list.
    final forgotten = _forgottenSecrets();
    if (forgotten.isNotEmpty) {
      final still = {
        for (final instance in settings.instances)
          if (forgotten.contains(instance.id) &&
              instance.unreadSecret == UnreadSecret.credential)
            instance.id,
      };
      if (still.isEmpty) {
        await _prefs.remove(_kForgottenSecrets);
      } else if (still.length != forgotten.length) {
        await _prefs.setStringList(_kForgottenSecrets, still.toList()..sort());
      }
    }

    // Everything the previous roster knew about and this one does not. Without
    // this pass a removed connection's API key stays in the keychain for the
    // life of the install: invisible, unreachable, and still a secret.
    final gone = {
      for (final entry in _readRoster())
        if (!live.contains(entry.id)) entry.id: entry.service,
      for (final instance in previous?.instances ?? const <ServiceInstance>[])
        if (!live.contains(instance.id)) instance.id: instance.service,
    };
    for (final entry in gone.entries) {
      await _forgetInstance(
        ServiceInstance(id: entry.key, service: entry.value),
      );
    }

    // Only a whole save does what follows; a partial one has no business
    // sweeping what it did not touch.
    if (previous != null) {
      if (!_sameRoster(previous.instances, settings.instances)) {
        await _writeRoster(settings.instances);
      }
      return;
    }

    // Primary slots with nothing in them. They predate the roster, so no
    // roster entry proves they were ever written; the enum is their only
    // record, and leaving a stale address here would have the legacy walk in
    // [loadSettings] resurrect a connection the user removed.
    for (final service in ServiceKey.values) {
      final primaryId = ServiceInstance.primaryIdFor(service);
      if (live.contains(primaryId)) continue;
      await _forgetInstance(ServiceInstance(id: primaryId, service: service));

      final storageKeys = _serviceStorageKeys[service]!;
      if (storageKeys.legacyApiKey.isNotEmpty) {
        await _prefs.remove(storageKeys.legacyApiKey);
      }
    }

    // Renamed-service leftovers, cleared once the new keys carry the value.
    for (final storageKeys in _serviceStorageKeys.values) {
      if (storageKeys.legacyUrl != null) {
        await _prefs.remove(storageKeys.legacyUrl!);
      }
      if (storageKeys.legacySecureApiKey != null) {
        await _secureStore.delete(key: storageKeys.legacySecureApiKey!);
      }
    }

    await _writeRoster(settings.instances);
  }

  /// Removes every value belonging to [instance].
  ///
  /// Deliberately does not touch `plex_client_id`: that key is not derived from
  /// an instance and does not belong to one. It identifies the install, and
  /// clearing it would hand the user's Plex server a new device row.
  Future<void> _forgetInstance(ServiceInstance instance) async {
    await _prefs.remove(instance.urlStorageKey);
    await _prefs.remove(instance.usernameStorageKey);
    await _prefs.remove(instance.viewerIdStorageKey);
    await _secureStore.delete(key: instance.credentialStorageKey);
    await _saveAccess(instance.copyWith(access: const NoAccess()));
    await _prefs.remove(instance.awayUrlStorageKey);
    await _saveAccessAt(_awayAccessKeys(instance), const NoAccess());
    // A refused sign-in is kept as a mark derived from the password: it goes
    // with the connection like the password itself.
    if (instance.service == ServiceKey.qbittorrent) {
      await _secureStore.delete(key: qbittorrentRefusalKey(instance.id));
    }
    // A removed Seerr connection must not leave a live session in the
    // keychain.
    await _saveAccount(instance.copyWith(clearAccount: true));
  }

  // === Seerr accounts ======================================================
  //
  // A Seerr connection signed in with an account keeps its kind, login, user
  // id, name and last permissions in `SharedPreferences` under
  // `<id>_account`, as JSON, and the session alone in secure storage under
  // `secure_<id>_session`. No password and no Plex token, ever. A connection
  // without `<id>_account` signs in with its key, as every connection did
  // before accounts: no migration.

  /// Writes [instance]'s account, or removes it and its session when it has
  /// none.
  Future<void> _saveAccount(ServiceInstance instance) async {
    final account = instance.account;
    if (account == null) {
      await _prefs.remove(instance.accountStorageKey);
      await _secureStore.delete(key: instance.sessionStorageKey);
      return;
    }
    await _prefs.setString(
      instance.accountStorageKey,
      jsonEncode({
        'kind': account.kind.name,
        'login': account.login,
        'userId': account.userId,
        'displayName': account.displayName,
        'permissions': account.permissions,
        if (account.checkedAt case final checkedAt?)
          'checkedAt': checkedAt.toUtc().toIso8601String(),
      }),
    );
    if (account.session.isEmpty) {
      await _secureStore.delete(key: instance.sessionStorageKey);
    } else {
      await _secureStore.write(
        key: instance.sessionStorageKey,
        value: account.session,
      );
    }
  }

  /// [instance] with its stored Seerr account, when it has one. An account
  /// that does not parse (a kind a later build wrote, an edit by hand) costs
  /// the account and never the connection; a key stored beside an account is
  /// dropped, because a connection is one or the other.
  Future<ServiceInstance> _withAccount(ServiceInstance instance) async {
    if (instance.service != ServiceKey.seerr) return instance;
    final raw = _prefs.getString(instance.accountStorageKey);
    if (raw == null || raw.isEmpty) return instance;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return instance;
    }
    if (decoded is! Map) return instance;
    final kind = SeerrAccountKind.byName(decoded['kind'] as String?);
    if (kind == null) return instance;
    String text(Object? value) => value is String ? value : '';
    int number(Object? value) => value is int ? value : 0;
    final checkedAt = decoded['checkedAt'];
    return instance.copyWith(
      credential: '',
      account: SeerrAccountSignIn(
        kind: kind,
        login: text(decoded['login']),
        userId: number(decoded['userId']),
        displayName: text(decoded['displayName']),
        permissions: number(decoded['permissions']),
        checkedAt: checkedAt is String ? DateTime.tryParse(checkedAt) : null,
        session: await _loadApiKey(instance.sessionStorageKey),
      ),
    );
  }

  /// Where the qBittorrent sign-in refused for connection [id] is kept in
  /// secure storage (`SecureQbittorrentRefusalStore`).
  static String qbittorrentRefusalKey(String id) =>
      'qbittorrent_refused_sign_in_$id';

  // === Access ==============================================================
  //
  // The non-secret half of a connection's access goes to `SharedPreferences`
  // under `<id>_access`, as JSON: its kind, and the Cloudflare Client ID, the
  // proxy's username or the custom header names. Every secret goes to secure
  // storage under keys derived from the id, the way the credential does. An
  // install that predates access has no `<id>_access` key and reads NoAccess,
  // so there is no migration.

  /// Writes [instance]'s access at home, removing whatever its previous
  /// access left behind: a secret the new kind does not use, a header the
  /// list no longer has.
  Future<void> _saveAccess(ServiceInstance instance) =>
      _saveAccessAt(_homeAccessKeys(instance), instance.access);

  /// Writes [access] under [keys], removing whatever the access stored there
  /// before left behind.
  Future<void> _saveAccessAt(_AccessKeys keys, ConnectionAccess access) async {
    final previousHeaders = _storedAccessHeaderNames(keys).length;

    final Map<String, Object> public;
    String? secret;
    var headerValues = const <String>[];
    switch (access) {
      case NoAccess():
        public = const {};
      case CloudflareServiceToken(:final clientId, :final clientSecret):
        public = {'kind': access.kind.name, 'clientId': clientId.trim()};
        secret = clientSecret.trim();
      case ProxyPassword(:final username, :final password):
        public = {'kind': access.kind.name, 'username': username};
        secret = password;
      case CustomHeaders(:final entries):
        public = {
          'kind': access.kind.name,
          'names': [for (final entry in entries) entry.name.trim()],
        };
        headerValues = [for (final entry in entries) entry.value];
    }

    // Secrets first, the non-secret record last. The record is what says how
    // many header values there are to find again, so an interrupted write that
    // had already rewritten it would leave the values it no longer names behind
    // for good; this way a save started again still sees them and finishes.
    if (secret == null || secret.isEmpty) {
      await _secureStore.delete(key: keys.secret);
    } else {
      await _secureStore.write(key: keys.secret, value: secret);
    }
    for (final (index, value) in headerValues.indexed) {
      final key = keys.header(index);
      if (value.isEmpty) {
        await _secureStore.delete(key: key);
      } else {
        await _secureStore.write(key: key, value: value);
      }
    }
    for (var index = headerValues.length; index < previousHeaders; index++) {
      await _secureStore.delete(key: keys.header(index));
    }
    if (public.isEmpty) {
      await _prefs.remove(keys.public);
    } else {
      await _prefs.setString(keys.public, jsonEncode(public));
    }
  }

  /// [instance]'s access at home as stored, [NoAccess] when there is none or
  /// it does not parse: a value a later build wrote, or one edited by hand,
  /// costs the access and never the connection.
  Future<ConnectionAccess> _loadAccess(ServiceInstance instance) =>
      _loadAccessAt(_homeAccessKeys(instance));

  /// [instance]'s address away from home, or null when it has none. Its
  /// access reads as the one at home does.
  Future<ConnectionAddress?> _loadAway(ServiceInstance instance) async {
    final url = _loadString(instance.awayUrlStorageKey).trim();
    if (url.isEmpty) return null;
    return ConnectionAddress(
      url: url,
      access: await _loadAccessAt(_awayAccessKeys(instance)),
    );
  }

  Future<ConnectionAccess> _loadAccessAt(_AccessKeys keys) async {
    final public = _storedAccess(keys);
    if (public == null) return const NoAccess();
    String text(Object? value) => value is String ? value : '';

    switch (AccessKind.byName(text(public['kind']))) {
      case AccessKind.cloudflare:
        return CloudflareServiceToken(
          clientId: text(public['clientId']),
          clientSecret: await _loadApiKey(keys.secret),
        );
      case AccessKind.password:
        return ProxyPassword(
          username: text(public['username']),
          password: await _loadApiKey(keys.secret),
        );
      case AccessKind.custom:
        final names = _storedAccessHeaderNames(keys);
        return CustomHeaders([
          for (final (index, name) in names.indexed)
            (name: name, value: await _loadApiKey(keys.header(index))),
        ]);
      case AccessKind.none:
      case null:
        return const NoAccess();
    }
  }

  Map<String, Object?>? _storedAccess(_AccessKeys keys) {
    final raw = _prefs.getString(keys.public);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  /// The custom header names stored under [keys], which is also how many
  /// header values secure storage holds there.
  List<String> _storedAccessHeaderNames(_AccessKeys keys) {
    final names = _storedAccess(keys)?['names'];
    if (names is! List) return const [];
    return [for (final name in names) name is String ? name : ''];
  }

  _AccessKeys _homeAccessKeys(ServiceInstance instance) => (
    public: instance.accessStorageKey,
    secret: instance.accessSecretStorageKey,
    header: instance.accessHeaderStorageKey,
  );

  _AccessKeys _awayAccessKeys(ServiceInstance instance) => (
    public: instance.awayAccessStorageKey,
    secret: instance.awayAccessSecretStorageKey,
    header: instance.awayAccessHeaderStorageKey,
  );

  /// Whether [a] and [b] would be recorded as the same roster: the same
  /// connections, in the same order, under the same labels.
  bool _sameRoster(List<ServiceInstance> a, List<ServiceInstance> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id ||
          a[index].service != b[index].service ||
          a[index].label != b[index].label) {
        return false;
      }
    }
    return true;
  }

  Future<void> _writeRoster(List<ServiceInstance> instances) async {
    if (instances.isEmpty) {
      await _prefs.remove(_kInstanceRoster);
      return;
    }
    await _prefs.setString(
      _kInstanceRoster,
      jsonEncode([
        for (final instance in instances)
          {
            'id': instance.id,
            'service': instance.service.name,
            'label': instance.label,
          },
      ]),
    );
  }

  Future<void> _writeOrRemove(String key, String value) async {
    if (value.isEmpty) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(key, value);
  }

  /// The keys secure storage would not hand over during the current load,
  /// out of [_secretReads] asked; see [loadSettings].
  final Set<String> _unreadKeys = {};
  int _secretReads = 0;
  int _secretFailures = 0;
  Object? _firstReadError;

  /// A secret, or `''` when there is none, or when secure storage would not
  /// hand it over: that key is recorded in [_unreadKeys] rather than thrown,
  /// so one unreadable entry costs its connection and not the whole start.
  Future<String> _loadApiKey(String key) async {
    _secretReads++;
    try {
      return await _secureStore.read(key: key) ?? '';
    } catch (error) {
      _unreadKeys.add(key);
      _secretFailures++;
      _firstReadError ??= error;
      return '';
    }
  }

  Future<void> _saveApiKey(String key, String value) async {
    final normalizedValue = value.trim();

    if (normalizedValue.isEmpty) {
      await _secureStore.delete(key: key);
      return;
    }

    await _secureStore.write(key: key, value: normalizedValue);
  }
}

class _ServiceStorageKeys {
  final String url;
  final String legacyApiKey;
  final String secureApiKey;

  /// Legacy URL key for backward compatibility (Jellyseerr → Seerr rename).
  final String? legacyUrl;

  /// Legacy plaintext API key from before the rename.
  final String? legacyPlaintextApiKey;

  /// Legacy secure API key from before the rename.
  final String? legacySecureApiKey;

  /// Prefs key for the username (used by qBittorrent and Dockge).
  final String? username;

  /// Prefs key for the chosen viewer's user id (Jellyfin).
  ///
  /// A selection, not a credential: it says whose watch state the library reads
  /// through. Changes whenever the user picks a different household member.
  final String? userId;

  /// Prefs key for the persisted per-install client identifier (Plex).
  ///
  /// Machine-generated exactly once and then immutable: the opposite lifecycle
  /// to [userId]. Regenerating it registers a new device against the user's
  /// server, so it must survive every launch, update and settings edit.
  final String? clientId;

  const _ServiceStorageKeys({
    required this.url,
    required this.legacyApiKey,
    required this.secureApiKey,
    this.legacyUrl,
    this.legacyPlaintextApiKey,
    this.legacySecureApiKey,
    this.username,
    this.userId,
    this.clientId,
  });
}

/// Where one address's access lives: its non-secret half in
/// `SharedPreferences`, its secret and its header values in secure storage.
typedef _AccessKeys = ({
  String public,
  String secret,
  String Function(int index) header,
});
