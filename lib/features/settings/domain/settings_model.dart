import 'package:flutter/material.dart' show ThemeMode;

import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

enum AppThemeMode {
  system(label: 'System'),
  light(label: 'Light'),
  dark(label: 'Dark');

  const AppThemeMode({required this.label});

  final String label;

  static final Map<String, AppThemeMode> _modesByName = {
    for (final mode in values) mode.name: mode,
  };

  ThemeMode get materialThemeMode {
    return switch (this) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };
  }

  static AppThemeMode fromName(String? value) =>
      _modesByName[value] ?? AppThemeMode.dark;
}

/// Everything Cupola persists, keyed on connections rather than on services.
///
/// ## The shape, and why it changed
///
/// This used to be forty-one flat fields: `radarrUrl`, `radarrApiKey`,
/// `sonarrUrl`, and so on: one pair per service, with a private registry
/// mapping a [ServiceKey] onto the right two. That shape said a service *is* a
/// connection, and it cannot hold a second Radarr: there is exactly one
/// `radarrUrl` and nowhere to put the other one.
///
/// So [instances] is now the single source of truth and everything else reads
/// through it. The flat names survive as **getters**; see the "legacy
/// projections" section, because a hundred call sites across the app read
/// `settings.radarrUrl`, several of them inside Riverpod `select`s where a
/// stable scalar is the whole point. They resolve to the *first* instance of
/// their service, which is what they always meant.
///
/// Two values deliberately stay off [instances], and the distinction is not
/// cosmetic:
///
/// * [plexClientId] identifies this **install**, not any server. Minted once,
///   never regenerated, shared by every Plex instance; a second id would
///   register a second device against the user's server.
/// * [trustedCertificates] is keyed by TLS **origin**, not by service or
///   instance, per ADR-6: a certificate belongs to the host that presents it,
///   so two instances behind one reverse proxy share one trust decision and
///   cannot diverge.
class SettingsModel {
  /// Every configured connection, in the user's own order.
  ///
  /// Order is meaning here: the first instance of a service is the one a bare
  /// `/services/radarr` resolves to and the one a write defaults to offering.
  /// It is **not** identity. Ids are stable, so reordering changes which
  /// instance is primary without moving a single stored value.
  final List<ServiceInstance> instances;

  /// Opaque per-install identifier sent as `X-Plex-Client-Identifier`.
  ///
  /// Generated once and then persisted forever: **not** per launch, and not
  /// per instance. Plex registers a new "device" against the user's server for
  /// every distinct identifier it sees, so a value regenerated on startup would
  /// litter their admin panel with a permanent row per app launch. Not a
  /// secret, so it lives in plain `SharedPreferences` beside the URLs.
  final String plexClientId;

  /// Trusted self-signed/untrusted TLS certificates (trust-on-first-use),
  /// keyed by [UrlUtils.certOrigin] rather than by service: a certificate
  /// belongs to the host that presents it, not to any one service reached
  /// through it, so two services behind the same reverse proxy share one
  /// trust decision. Value is the lowercase SHA-256 fingerprint of the
  /// trusted certificate's DER encoding. An origin with no entry gets
  /// standard certificate verification. Integrity-critical: this is the
  /// value that says "this exact certificate is the one to trust", so it is
  /// kept in secure storage, never in plain `SharedPreferences`.
  final Map<String, String> trustedCertificates;

  final String region;
  final AppThemeMode themeMode;

  const SettingsModel({
    this.instances = const [],
    this.plexClientId = '',
    this.trustedCertificates = const {},
    this.region = 'US',
    this.themeMode = AppThemeMode.dark,
  });

  static String normalizeRegion(String? region) {
    final normalized = region?.trim().toUpperCase() ?? '';
    return normalized.isEmpty ? 'US' : normalized;
  }

  SettingsModel copyWith({
    List<ServiceInstance>? instances,
    String? plexClientId,
    Map<String, String>? trustedCertificates,
    String? region,
    AppThemeMode? themeMode,
  }) {
    return SettingsModel(
      instances: instances ?? this.instances,
      plexClientId: plexClientId ?? this.plexClientId,
      trustedCertificates: trustedCertificates ?? this.trustedCertificates,
      region: region ?? this.region,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  ThemeMode get resolvedThemeMode => themeMode.materialThemeMode;

  // === Instances ===========================================================

  /// Every instance of [service], in order. Empty when none is configured.
  List<ServiceInstance> instancesOf(ServiceKey service) => instances
      .where((instance) => instance.service == service)
      .toList(growable: false);

  /// The instance a bare reference to [service] means: the first one.
  ///
  /// Null when the service has none, which is different from having one that
  /// is blank, and the two are told apart by [isServiceConfigured].
  ServiceInstance? primaryOf(ServiceKey service) {
    for (final instance in instances) {
      if (instance.service == service) return instance;
    }
    return null;
  }

  ServiceInstance? instanceById(String id) {
    for (final instance in instances) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  /// Every instance that is set up enough to be worth talking to.
  List<ServiceInstance> get configuredInstances => instances
      .where((instance) => instance.isConfigured)
      .toList(growable: false);

  /// Every instance of [service] that is set up enough to be worth talking to.
  ///
  /// The per-service counterpart of [configuredInstances], and the list every
  /// surface that *offers a choice* has to use. [instancesOf] includes the slot
  /// a half-finished form is sitting in, which is right for the settings screen
  /// (the user is looking at it) and wrong everywhere else.
  List<ServiceInstance> configuredInstancesOf(ServiceKey service) => instances
      .where((instance) => instance.service == service && instance.isConfigured)
      .toList(growable: false);

  /// Whether [service] has more than one connection worth reading: the
  /// question every surface asks before it decides to show a label at all.
  ///
  /// Counts the **configured** ones, not the slots. Counting slots meant that
  /// starting to add a second connection lit the badge, the app-bar label and
  /// every provenance chip across the app before that connection had an address
  /// (announcing a fold the user could not yet use, and naming the new slot by
  /// its id because it had no label yet either).
  ///
  /// A Seerr account that signed out still counts: it is one of the
  /// connections, and the lens may rest on it.
  bool hasMultipleInstances(ServiceKey service) =>
      instancesOf(service)
          .where((instance) => instance.isConfigured || instance.isSignedOut)
          .length >
      1;

  /// Returns a copy with [instance] written in: replacing the entry with the
  /// same id, or appended when there is none.
  ///
  /// Appending rather than inserting keeps the user's order intact, and keeps
  /// the first instance of a service first, which is what makes "primary" a
  /// stable answer across an edit to some other service.
  SettingsModel copyWithInstance(ServiceInstance instance) {
    final updated = List<ServiceInstance>.of(instances);
    final index = updated.indexWhere((other) => other.id == instance.id);
    if (index >= 0) {
      updated[index] = instance;
    } else {
      updated.add(instance);
    }
    return copyWith(instances: updated);
  }

  /// Returns a copy without the instance [id], and without the per-instance
  /// values that belonged to it.
  ///
  /// Does **not** touch [trustedCertificates]: a pin belongs to an origin that
  /// another instance may still be reached at, and deciding that is
  /// [copyWithoutUnusedCertificate]'s job. Call it after this, so "still
  /// configured" describes the state being saved.
  SettingsModel copyWithoutInstance(String id) {
    final updated = instances
        .where((instance) => instance.id != id)
        .toList(growable: false);
    if (updated.length == instances.length) return this;
    return copyWith(instances: updated);
  }

  /// The instance [service]'s next connection should take, minted against the
  /// ids already in use so it can never collide with one.
  ServiceInstance newInstanceFor(ServiceKey service) => ServiceInstance(
    id: ServiceInstance.mintId(service, instances.map((i) => i.id)),
    service: service,
  );

  // === Per-service access, resolved through the first instance =============

  /// Writes to [service]'s first instance, creating it when there is none.
  ///
  /// The one path that mints a primary, which is why it lives here rather than
  /// at the call sites: a new service configured for the first time has to land
  /// on the id whose storage keys predate this class, or its credential would
  /// be written somewhere the previous version never looked.
  SettingsModel _upsertPrimary(
    ServiceKey service, {
    String? url,
    String? credential,
    String? username,
    String? viewerId,
  }) {
    final existing = primaryOf(service);
    if (existing != null) {
      return copyWithInstance(
        existing.copyWith(
          url: url,
          credential: credential,
          username: username,
          viewerId: viewerId,
        ),
      );
    }

    final candidate =
        ServiceInstance(
          id: ServiceInstance.mintId(service, instances.map((i) => i.id)),
          service: service,
        ).copyWith(
          url: url,
          credential: credential,
          username: username,
          viewerId: viewerId,
        );

    // Nothing worth recording, so record nothing. Without this guard the load
    // path mints an instance for all nineteen services on every start. It
    // walks the whole enum writing whatever it found, and finds `''` for the
    // sixteen the user never set up. An instance list that is never empty makes
    // "does this service have one" unanswerable, and persists sixteen blanks
    // to prove it.
    if (candidate.url.isEmpty &&
        candidate.credential.isEmpty &&
        candidate.username.isEmpty &&
        candidate.viewerId.isEmpty) {
      return this;
    }
    return copyWithInstance(candidate);
  }

  /// Returns the URL configured for [service]'s first instance.
  String urlFor(ServiceKey service) => primaryOf(service)?.url ?? '';

  /// Returns the API key configured for [service]'s first instance.
  String apiKeyFor(ServiceKey service) => primaryOf(service)?.credential ?? '';

  /// The username configured for [service], or `''` for the services that
  /// authenticate with an API key and so have none.
  String usernameFor(ServiceKey service) => primaryOf(service)?.username ?? '';

  /// The password configured for [service], or `''` for the services that
  /// authenticate with an API key and so have none.
  ///
  /// A credential-authenticated service keeps its password in the generic
  /// credential slot [apiKeyFor] reads, exactly as the Plex token does, so the
  /// registry capability is the whole of the decision here, rather than a
  /// second copy of the "is it one of these three" list.
  String passwordFor(ServiceKey service) {
    return service.usesApiKey ? '' : apiKeyFor(service);
  }

  /// Returns a copy with the URL and/or API key updated for [service]'s first
  /// instance.
  SettingsModel copyWithService(
    ServiceKey service, {
    String? url,
    String? apiKey,
  }) {
    return _upsertPrimary(service, url: url, credential: apiKey);
  }

  /// Returns a copy with [service]'s URL, username and/or password updated.
  ///
  /// The credential-authenticated counterpart to [copyWithService]. Asserts
  /// rather than silently no-ops on an API-key service, because passing one
  /// here is a programming error: the caller meant [copyWithService], and
  /// quietly dropping the write is how a credential goes missing.
  SettingsModel copyWithCredentials(
    ServiceKey service, {
    String? url,
    String? username,
    String? password,
  }) {
    assert(
      !service.usesApiKey,
      '${service.name} authenticates with an API key, use copyWithService.',
    );
    return _upsertPrimary(
      service,
      url: url,
      credential: password,
      username: username,
    );
  }

  /// Returns a copy with the chosen viewer updated for [service]'s first
  /// instance. Jellyfin only; see [ServiceKeyExtension.needsViewerSelection].
  SettingsModel copyWithViewer(ServiceKey service, String viewerId) {
    return _upsertPrimary(service, viewerId: viewerId);
  }

  /// What to call the connection [id] in a sentence: `Radarr`, `Radarr · 4K`,
  /// or `Radarr 2` for a connection the user never named.
  ///
  /// The sentence form of [connectionName], which holds the rule every surface
  /// follows: a connection is named **only when there is more than one of its
  /// service to tell apart**. With a single Radarr this is "Radarr" whatever
  /// label the instance happens to be carrying, and it very often is carrying
  /// one, because a label derived when a second connection was added outlives
  /// that connection's removal.
  ///
  /// [fallback] names the service for an id that matches nothing, which is what
  /// a link or a queued job from a connection since removed still holds.
  ///
  /// [joiner] is `' · '` where the title stands alone (a chip, a heading) and
  /// `' '` inside a sentence or a button label, where a separator would read
  /// as punctuation: "Goes to Radarr 4K", "Open in Radarr 4K".
  String connectionTitle(
    String id,
    ServiceKey fallback, {
    String joiner = dotSeparator,
  }) {
    final instance = instanceById(id);
    if (instance == null) return fallback.title;
    return serviceWithConnection(
      instance.service,
      connectionName(id),
      joiner: joiner,
    );
  }

  /// What tells the connection [id] apart from the other connections of its
  /// service, or null when nothing needs telling apart.
  ///
  /// The one rule for naming a connection, which every badge, chip, lane and
  /// sentence reads: with one configured connection of a service, nothing at
  /// all; with two or more, the name the user gave it, else `Radarr 2` from its
  /// place among that service's connections. Never the raw id, never a blank,
  /// and never the bare service name, which is what the two of them would
  /// otherwise both be called.
  ///
  /// By place rather than by host because two connections of one service
  /// usually share a host, so the host alone would name both the same; and a
  /// place is stable for as long as the user's own order is. A name is
  /// normally there: the settings form derives one for the first connection
  /// when a second is added. This is for every way of arriving at two without
  /// one: a restored backup, a label cleared by hand, a connection whose
  /// sibling was added on a version that did not ask.
  ///
  /// Null for an id that matches nothing, which is what a link or a queued job
  /// from a connection since removed still holds.
  String? connectionName(String id) {
    final instance = instanceById(id);
    if (instance == null) return null;
    if (!hasMultipleInstances(instance.service)) return null;
    final label = instance.label.trim();
    if (label.isNotEmpty) return label;
    final siblings = instancesOf(instance.service);
    final place = siblings.indexWhere((sibling) => sibling.id == id) + 1;
    return '${instance.service.title} $place';
  }

  /// The address on [route], the credential and that address's access of the
  /// connection [id], or two empty strings and no access when it names none.
  ///
  /// What a screen showing one connection's library keys its artwork on: it
  /// is that server's, at the address that reaches it now under that server's
  /// key, and across the gateway in front of that address with its access, so
  /// a pasted token re-keys the posters at once rather than at the next read,
  /// and so does the route moving. [route] is the connection's
  /// (`connectionRouteProvider`): a selector cannot watch it, so the screen
  /// does and closes over it. As a record, so a `select` over it settles:
  /// editing another connection changes nothing here.
  (String, String, ConnectionAccess) artworkKeyOf(
    String id,
    ConnectionRoute route,
  ) {
    final instance = instanceById(id);
    final address = instance?.addressOn(route);
    return (
      address?.url ?? '',
      instance?.credential ?? '',
      address?.access ?? const NoAccess(),
    );
  }

  /// Each address that has access to send, with the headers its gateway asks
  /// for: what `ConnectionAccessRegistry` holds for the artwork built from an
  /// address and a key.
  ///
  /// Both addresses of a connection, each with its own access: a poster built
  /// from the address away crosses the gateway in front of it, and one built
  /// at home sends nothing a gateway away asks for.
  List<({String url, Map<String, String> headers})>
  get accessHeadersByAddress => [
    for (final instance in instances)
      for (final address in [instance.home, ?instance.away])
        if (address.url.isNotEmpty && !address.access.isEmpty)
          (url: address.url, headers: address.access.headers()),
  ];

  /// Whether any instance of [service] is set up enough to talk to.
  bool isServiceConfigured(ServiceKey service) =>
      instancesOf(service).any((instance) => instance.isConfigured);

  /// Whether [service] has a connection somebody set up: one it can talk to,
  /// or a Seerr account that signed out and keeps its address and login.
  ///
  /// The question a `Set up X` door asks, where [isServiceConfigured] is the
  /// one a provider asks: a signed-out Seerr is not set up enough to talk to,
  /// and it is not a service nobody set up either.
  bool hasServiceConnection(ServiceKey service) => instancesOf(service).any(
    (instance) =>
        instance.isConfigured ||
        instance.isSignedOut ||
        instance.unreadSecret != null,
  );

  /// The connection of [service] a screen stands on whose secret could not be
  /// read, or null: [lensId]'s when it names one of [service]'s, otherwise,
  /// when none of [service] is configured, the first such one. Such a screen
  /// says so, with the way to paste it again, never `Set up Radarr`.
  ServiceInstance? unreadConnectionOf(ServiceKey service, {String? lensId}) {
    final instances = instancesOf(service);
    final lens = instances.where((i) => i.id == lensId).firstOrNull;
    if (lens != null) return lens.unreadSecret != null ? lens : null;
    if (instances.any((instance) => instance.isConfigured)) return null;
    return instances
        .where((instance) => instance.unreadSecret != null)
        .firstOrNull;
  }

  /// The signed-out Seerr account a screen of [service] stands on in place
  /// of a configured connection, or null.
  ///
  /// [lensId]'s connection when it names one of [service]'s and that one is
  /// signed out; otherwise, when no connection of [service] is configured, the
  /// first signed-out one. Such a screen reads signed out, with its way back
  /// (`Sign in again`), never `Set up Seerr`.
  ServiceInstance? signedOutConnectionOf(ServiceKey service, {String? lensId}) {
    final instances = instancesOf(service);
    final lens = instances.where((i) => i.id == lensId).firstOrNull;
    if (lens != null) return lens.isSignedOut ? lens : null;
    if (instances.any((instance) => instance.isConfigured)) return null;
    return instances.where((instance) => instance.isSignedOut).firstOrNull;
  }

  // === Certificates (ADR-6) ================================================

  /// The trusted fingerprint for the TLS origin [rawUrl] belongs to, or null
  /// when nothing is pinned there (or [rawUrl] cannot carry a certificate at
  /// all; see [UrlUtils.certOrigin]).
  String? pinForUrl(String rawUrl) {
    final origin = UrlUtils.certOrigin(rawUrl);
    if (origin == null) return null;
    final pin = trustedCertificates[origin];
    return (pin == null || pin.isEmpty) ? null : pin;
  }

  /// Returns a copy with the trusted fingerprint for [url]'s origin set to
  /// [fingerprint]. Every service sharing that origin is trusted or forgotten
  /// together; see [servicesSharingOriginOf].
  ///
  /// An empty [fingerprint] **removes** the entry rather than storing an
  /// empty string, which is what makes it "forget" this origin: [pinForUrl]
  /// treats a missing key and an empty value as the same "not pinned", but
  /// only removal actually shrinks the stored map.
  ///
  /// A no-op (returns `this`) when [url] cannot resolve to a TLS origin.
  SettingsModel copyWithTrustedCertificate({
    required String url,
    required String fingerprint,
  }) {
    final origin = UrlUtils.certOrigin(url);
    if (origin == null) return this;

    final updated = Map<String, String>.of(trustedCertificates);
    final trimmed = fingerprint.trim();
    if (trimmed.isEmpty) {
      updated.remove(origin);
    } else {
      updated[origin] = trimmed.toLowerCase();
    }
    return copyWith(trustedCertificates: updated);
  }

  /// Returns a copy that forgets [priorUrl]'s pinned certificate unless some
  /// instance *still configured in this copy* is reached at that origin.
  ///
  /// The one guard for every path that stops using an address: removing a
  /// connection, editing a URL to point somewhere else, because all of them
  /// need the same answer and getting it wrong is a security bug in both
  /// directions. Forgetting unconditionally breaks Radarr's trust in the
  /// reverse proxy when Sonarr is removed from behind it; never forgetting
  /// leaves a pin keyed to an origin nothing uses any more, and since
  /// [pinForUrl] is keyed purely by origin, the next service pointed at that
  /// address would silently reuse it with no trust prompt.
  ///
  /// Asks [instancesSharingOriginOf] rather than [servicesSharingOriginOf], and
  /// that is the whole difference between correct and nearly correct here: two
  /// instances of one service behind the same proxy are two users of that pin,
  /// and a per-service answer collapses them into one. Removing either would
  /// then forget a certificate the other still needs.
  ///
  /// Call it *after* writing the new (or cleared) values, so "still
  /// configured" describes the state being saved rather than the one being
  /// left. A no-op for an empty [priorUrl] or one that carries no TLS origin.
  SettingsModel copyWithoutUnusedCertificate(String priorUrl) {
    if (priorUrl.trim().isEmpty) return this;
    final stillUsed = instancesSharingOriginOf(
      priorUrl,
    ).any((instance) => instance.isConfigured);
    if (stillUsed) return this;
    return copyWithTrustedCertificate(url: priorUrl, fingerprint: '');
  }

  /// [copyWithoutUnusedCertificate] for every address [prior] was reached
  /// at: a connection removed, or moved, stops using its address away as much
  /// as its address at home, and each of the two is its own origin.
  SettingsModel copyWithoutUnusedCertificatesOf(ServiceInstance? prior) {
    var updated = this;
    for (final address in prior?.addresses ?? const <String>[]) {
      updated = updated.copyWithoutUnusedCertificate(address);
    }
    return updated;
  }

  /// Every instance reached at the same TLS origin as [rawUrl], at home or
  /// away from home: the set one trust decision on that origin actually
  /// covers.
  ///
  /// Both addresses count, because each is an origin a request goes to: a
  /// certificate trusted for the tunnel a connection is reached through away
  /// from home is that connection's as much as the one at home, and forgetting
  /// it because the address at home moved would leave the next request away
  /// refusing a certificate the person had trusted.
  List<ServiceInstance> instancesSharingOriginOf(String rawUrl) {
    final origin = UrlUtils.certOrigin(rawUrl);
    if (origin == null) return const [];
    return instances
        .where(
          (instance) => instance.addresses.any(
            (address) => UrlUtils.certOrigin(address) == origin,
          ),
        )
        .toList(growable: false);
  }

  /// Every configured service reached at the same TLS origin as [rawUrl], with
  /// no service named twice.
  ///
  /// The naming half of [instancesSharingOriginOf], for the screens that warn
  /// "forgetting this certificate also affects…": a list of instances would
  /// say "Radarr, Radarr" where the user thinks in servers. Correctness paths
  /// take the instance list; sentences take this one.
  List<ServiceKey> servicesSharingOriginOf(String rawUrl) {
    final seen = <ServiceKey>{};
    for (final instance in instancesSharingOriginOf(rawUrl)) {
      seen.add(instance.service);
    }
    return seen.toList(growable: false);
  }

  // === Legacy projections ==================================================
  //
  // The forty-one names this class used to store, kept as reads onto the first
  // instance of each service. Around a hundred call sites use them, several
  // inside Riverpod `select`s where the point is a stable scalar, and rewriting
  // all of them to `urlFor(ServiceKey.radarr)` would be churn with no reader
  // served. New code should reach for [instancesOf] or [primaryOf]; these say
  // "the first one" without being able to say anything else.

  /// Which Jellyfin user's watch state the library is read through.
  ///
  /// Required rather than optional, and the reason is structural: a Jellyfin API
  /// key authenticates as Administrator with **no user attached** (an empty
  /// `UserId` claim), so it can see every session but cannot answer "have I
  /// watched this". Resume positions, next-up and unplayed filters are all
  /// user-scoped, so the library has to be entered through a person chosen from
  /// `/Users`. Plex has no equivalent field because its token *is* the user and
  /// `/library/*` takes no impersonation parameter. That asymmetry is a real
  /// property of the two APIs, not a gap here.
  String get jellyfinUserId => primaryOf(ServiceKey.jellyfin)?.viewerId ?? '';
}

/// [service] and the connection [name] as one phrase: `Radarr · 4K`, the
/// service alone when [name] is null or empty, and the name alone when it
/// already starts with the service (`Radarr 2`, a derived name, or a label the
/// user typed as `Radarr Old`), which would otherwise read `Radarr · Radarr 2`.
///
/// [joiner] is ` · ` for a phrase that stands on its own and a space for one
/// set inside a line whose clauses are already joined with ` · ` (`Sonarr
/// Anime`), where a second dot would read as a second clause.
String serviceWithConnection(
  ServiceKey service,
  String? name, {
  String joiner = dotSeparator,
}) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return service.title;
  if (trimmed.toLowerCase().startsWith('${service.title.toLowerCase()} ')) {
    return trimmed;
  }
  return '${service.title}$joiner$trimmed';
}
