import 'dart:math';

import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_owner_session.dart';

/// One configured connection to one server.
///
/// The unit the app is keyed on. [ServiceKey] answers *what kind of thing is
/// this*: its API, its icon, where its credential lives in its own UI, and a
/// [ServiceInstance] answers *which one*: this Radarr at this address with this
/// key, told apart from the other Radarr by a name the user chose.
///
/// ## Why the id is the route param for the first one
///
/// [id] is opaque, stable and generated once. The first instance of a service
/// takes the service's own [ServiceKeyExtension.routeParam] as its id, and
/// every later one takes `routeParam-xxxxxxxx`. That is not cosmetic: it is
/// what makes this change invisible to an existing install:
///
/// * every storage key on this class derives from [id], and for the first
///   instance each one reproduces **exactly** the key that service already
///   used (`radarr_url`, `secure_radarr_api_key`, `qbittorrent_username`,
///   `jellyfin_user_id`). No credential is ever read from one key and written
///   to another, which is the one migration that cannot be made safe: a
///   half-completed secret move loses the secret.
/// * a saved deep link to `/services/radarr` still names a real instance.
///
/// The id is never derived from the URL. An address is a thing the user edits;
/// an identity is not, and keying on the URL would break every saved link the
/// first time a server moved.
class ServiceInstance {
  /// Opaque, stable, generated once. See the class doc for why the first
  /// instance of a service is named after the service.
  final String id;

  /// Which kind of server this is.
  final ServiceKey service;

  /// The short name the user gave this instance: `4K`, `HD`, `Casa`.
  ///
  /// Empty for a service with only one instance, and that emptiness is the
  /// whole of the "you do not pay for the fold until you need it" rule: with no
  /// label there is no badge in the app bar, no suffix in a title, and no chip
  /// on a search row. Required from the second instance onwards, because two
  /// rows both called "Radarr" is the state this feature exists to prevent.
  final String label;

  final String url;

  /// The secret half of this instance's credential: an API key, a password or
  /// a token, depending on what the service issues. One slot rather than three
  /// because a connection has exactly one secret, and which vocabulary it goes
  /// by is the service's business; see [ServiceKeyExtension.credentialLabel].
  final String credential;

  /// The non-secret half, for the services that authenticate on a pair.
  /// Empty for the API-key services, which have none.
  final String username;

  /// Which person this connection reads and acts as, for the two services
  /// whose credential names nobody:
  /// Jellyfin's viewer, whose watch state the library is read through (see
  /// [ServiceKeyExtension.needsViewerSelection]), and the Seerr user an API
  /// key acts as ([seerrActsAs]).
  ///
  /// Per instance, not per install: two servers have two different user
  /// tables, and carrying one server's user id to the other binds every
  /// per-person query to an id that does not exist there.
  final String viewerId;

  /// What this connection presents to a gateway in front of the service, on
  /// every request it makes. [NoAccess] unless the user set one.
  ///
  /// Per connection rather than per origin, unlike a trusted certificate: see
  /// [ConnectionAccess]. Its non-secret half is stored beside the address
  /// ([accessStorageKey]) and its secrets in secure storage under keys derived
  /// from [id] ([accessSecretStorageKey], [accessHeaderStorageKey]), so
  /// removing the connection removes them.
  final ConnectionAccess access;

  /// Seerr only: the household member's own account this connection signs in
  /// with, or null for the instance's API key in [credential].
  ///
  /// A connection is one or the other, never both: with an account the
  /// credential is empty. Its non-secret half (the kind, the login, the name,
  /// the last permissions) is stored beside the address
  /// ([accountStorageKey]) and its session in secure storage
  /// ([sessionStorageKey]). An account whose session is empty is signed out:
  /// everything but the session is kept, so signing in again is one step.
  final SeerrAccountSignIn? account;

  /// Tracearr only: the owner's session, beside the public key in
  /// [credential] (never instead of it: the key always reads, the session
  /// only writes the two things the public API has no route for).
  ///
  /// Optional. Its non-secret half is stored beside the address
  /// ([ownerStorageKey]) and its token in secure storage
  /// ([ownerSessionStorageKey]), so removing the connection removes both. An
  /// owner whose token is empty is signed out: everything else is kept, so
  /// signing in again is one step.
  final TracearrOwnerSession? owner;

  /// The address that reaches this server away from home, with what its
  /// gateway asks for, or null for a connection reached at [url] only.
  ///
  /// [url] stays the address the connection is saved and known by: the one
  /// a trusted certificate, a kept drawing (`LastKnownStore`) and a link name
  /// it by. Which of the two a request goes to is the route's business
  /// (`reachOf`), never this field's reader's. Stored beside the address at
  /// home ([awayUrlStorageKey], [awayAccessStorageKey]), its secrets in
  /// secure storage under keys derived from [id].
  final ConnectionAddress? away;

  /// The secret of this connection that secure storage would not hand over
  /// when the settings were read, or null when every one of them came back.
  ///
  /// Read, never saved: it is what this run found. While it is set the
  /// connection is not [isConfigured], so nothing is sent with a secret
  /// missing (a qBittorrent counts an empty password among the five tries its
  /// ban allows), and saving the settings leaves that secret where it is
  /// rather than writing the empty value back over it. Setting a new value of
  /// it, in [copyWith], clears it.
  final UnreadSecret? unreadSecret;

  const ServiceInstance({
    required this.id,
    required this.service,
    this.label = '',
    this.url = '',
    this.credential = '',
    this.username = '',
    this.viewerId = '',
    this.access = const NoAccess(),
    this.account,
    this.owner,
    this.away,
    this.unreadSecret,
  }) : assert(
         owner == null || service == ServiceKey.tracearr,
         'only a Tracearr connection signs in as an owner',
       ),
       assert(
         account == null || service == ServiceKey.seerr,
         'only a Seerr connection signs in with an account',
       ),
       assert(
         account == null || credential == '',
         'a Seerr connection is a key or an account, never both',
       );

  /// The id the first instance of [service] takes. See the class doc.
  static String primaryIdFor(ServiceKey service) => service.routeParam;

  /// Mints an id for a new instance of [service] that collides with nothing in
  /// [taken].
  ///
  /// Hands out the primary id first, so a service configured for the first time
  /// lands on the keys it would have used before this class existed. Only once
  /// that is spoken for does it start suffixing.
  static String mintId(
    ServiceKey service,
    Iterable<String> taken, {
    Random? random,
  }) {
    final primary = primaryIdFor(service);
    final used = taken.toSet();
    if (!used.contains(primary)) return primary;

    final rng = random ?? Random.secure();
    while (true) {
      final suffix = rng.nextInt(0xFFFFFFF).toRadixString(16).padLeft(7, '0');
      final candidate = '$primary-$suffix';
      if (!used.contains(candidate)) return candidate;
    }
  }

  /// Whether this instance holds the slot whose storage keys predate the
  /// multi-instance model.
  bool get isPrimarySlot => id == primaryIdFor(service);

  /// Where this instance's address lives in `SharedPreferences`.
  String get urlStorageKey => '${id}_url';

  /// Where the non-secret half of the credential lives.
  String get usernameStorageKey => '${id}_username';

  /// Where the chosen viewer lives, for the one service that needs one.
  String get viewerIdStorageKey => '${id}_user_id';

  /// Where the secret lives, in secure storage.
  ///
  /// The suffix belongs to the *service*: Plex issues a token, qBittorrent
  /// takes a password, the arrs mint an API key, so it comes from the registry
  /// rather than being flattened to one word here. That is what makes the
  /// primary instance's key byte-identical to the one already on disk.
  String get credentialStorageKey =>
      'secure_${id}_${service.credentialStorageSuffix}';

  /// Where the non-secret half of [access] lives in `SharedPreferences`: its
  /// kind, the Cloudflare Client ID, the proxy's username, the custom header
  /// names. Absent for [NoAccess], which is also what an install that predates
  /// access reads, so there is nothing to migrate.
  String get accessStorageKey => '${id}_access';

  /// Where the secret of [access] lives in secure storage: the Cloudflare
  /// Client Secret, or the proxy's password.
  String get accessSecretStorageKey => 'secure_${id}_access_secret';

  /// Where the value of custom header [index] lives in secure storage.
  String accessHeaderStorageKey(int index) =>
      'secure_${id}_access_header_$index';

  /// Where [away]'s address lives in `SharedPreferences`.
  String get awayUrlStorageKey => '${id}_away_url';

  /// Where the non-secret half of [away]'s access lives, as [accessStorageKey]
  /// holds the one at home.
  String get awayAccessStorageKey => '${id}_away_access';

  /// Where the secret of [away]'s access lives in secure storage.
  String get awayAccessSecretStorageKey => 'secure_${id}_away_access_secret';

  /// Where the value of [away]'s custom header [index] lives in secure
  /// storage.
  String awayAccessHeaderStorageKey(int index) =>
      'secure_${id}_away_access_header_$index';

  /// The address at home, as an address: [url] and [access].
  ConnectionAddress get home => ConnectionAddress(url: url, access: access);

  /// The address [route] goes to: [away] when the route says so and there is
  /// one to go to, [home] otherwise. The choice `reachOf` makes, kept here so
  /// a reader that needs the address without its pin makes the same one.
  ConnectionAddress addressOn(ConnectionRoute route) {
    final away = this.away;
    return route == ConnectionRoute.away && away != null && away.url.isNotEmpty
        ? away
        : home;
  }

  /// Every address this connection is reached at: [url], then [away]'s when
  /// it has one. What a trusted certificate, an access header and a kept
  /// picture are matched against, since either may be the one in use.
  List<String> get addresses => [
    for (final address in [url, ?away?.url])
      if (address.isNotEmpty) address,
  ];

  /// Where the non-secret half of [account] lives in `SharedPreferences`, as
  /// JSON. Absent for a connection that signs in with its key, which is also
  /// what every install before accounts reads: nothing to migrate.
  String get accountStorageKey => '${id}_account';

  /// Where [account]'s session lives in secure storage.
  String get sessionStorageKey => 'secure_${id}_session';

  /// Where the non-secret half of [owner] lives in `SharedPreferences`, as
  /// JSON. Absent for a connection with no owner session.
  String get ownerStorageKey => '${id}_owner';

  /// Where [owner]'s token lives in secure storage.
  String get ownerSessionStorageKey => 'secure_${id}_owner_session';

  /// Whether this is a Tracearr whose owner signed in once and holds no
  /// session now: ended, or signed out.
  bool get ownerSignedOut => owner != null && !owner!.isSignedIn;

  /// How this Seerr connection signs in: its [account], or its API key.
  SeerrSignIn get seerrSignIn => account ?? SeerrApiKeySignIn(credential);

  /// The Seerr user this connection's API key acts as, sent as `X-API-User`,
  /// or empty for the key's own: the server's owner, user 1.
  ///
  /// Seerr has one API key, with an administrator's rights, and every request
  /// it signs is that user's: its watchlist, the requests it makes. A
  /// household with two administrators names the one holding this phone here.
  /// Only an administrator is offered, so the gate's operator stays true. An
  /// account acts as itself, so this is empty for one whatever [viewerId]
  /// holds.
  String get seerrActsAs =>
      service == ServiceKey.seerr && account == null ? viewerId : '';

  /// Whether this is a Seerr account that holds no session: signed out.
  bool get isSignedOut => account != null && !account!.isSignedIn;

  /// Whether this instance is set up enough to be worth talking to.
  ///
  /// A credential-authenticated service can legitimately run with no auth at
  /// all behind a reverse proxy, so only the address is strictly required
  /// there. Which services those are is the registry's answer, never a list
  /// repeated at the call site.
  ///
  /// A Seerr account is set up while it holds a session: signed out, it keeps
  /// its address and its login and reads as not set up until it signs in
  /// again.
  bool get isConfigured {
    if (unreadSecret != null) return false;
    if (!service.usesApiKey) return url.isNotEmpty;
    final account = this.account;
    if (account != null) return url.isNotEmpty && account.isSignedIn;
    return url.isNotEmpty && credential.isNotEmpty;
  }

  /// Whether this connection is reached somewhere else than [prior] was: the
  /// address at home, the one away, or what a gateway in front of either asks
  /// for. A name, a key or a viewer is not a move: the certificate a server
  /// presents belongs to the address.
  bool reachesDifferentlyFrom(ServiceInstance prior) =>
      url != prior.url || access != prior.access || away != prior.away;

  /// The join: `Radarr` with no label, `Radarr · 4K` with one.
  ///
  /// **Formatting only. It cannot answer whether the label should be shown.**
  /// A label outlives the sibling that made it necessary: derive one for the
  /// original Radarr when a second is added, remove the second, and the survivor
  /// still carries `4K` while every badge, chip and section heading has gone
  /// quiet again because they all ask `hasMultipleInstances` first. Reading this
  /// getter directly therefore printed "Added to Radarr · 7878" for the only
  /// Radarr there is.
  ///
  /// Call [SettingsModel.connectionTitle] instead wherever a sentence names a
  /// connection; it applies the same rule as the rest of the app.
  String get displayTitle =>
      label.isEmpty ? service.title : '${service.title}\u00A0· $label';

  /// [clearAccount] takes the account off, back to the key; setting an
  /// [account] is the other way.
  ServiceInstance copyWith({
    String? label,
    String? url,
    String? credential,
    String? username,
    String? viewerId,
    ConnectionAccess? access,
    SeerrAccountSignIn? account,
    bool clearAccount = false,
    TracearrOwnerSession? owner,
    bool clearOwner = false,
    ConnectionAddress? away,
    bool clearAway = false,
  }) {
    return ServiceInstance(
      id: id,
      service: service,
      label: label ?? this.label,
      url: url ?? this.url,
      credential: credential ?? this.credential,
      username: username ?? this.username,
      viewerId: viewerId ?? this.viewerId,
      access: access ?? this.access,
      account: clearAccount ? null : account ?? this.account,
      owner: clearOwner ? null : owner ?? this.owner,
      away: clearAway ? null : away ?? this.away,
      // Only a new value of the secret that could not be read replaces it.
      // An edit that carries the empty one along (the address changed, the
      // key field untouched) keeps the mark, and with it the stored secret,
      // which a keychain that was only locked hands over next time.
      unreadSecret: switch (unreadSecret) {
        UnreadSecret.credential when credential?.isNotEmpty ?? false => null,
        UnreadSecret.access
            when (access != null && access != this.access) ||
                (away != null && away.access != this.away?.access) =>
          null,
        final kept => kept,
      },
    );
  }

  /// A copy marked with the secret secure storage would not hand over; see
  /// [unreadSecret].
  ServiceInstance withUnreadSecret(UnreadSecret secret) => ServiceInstance(
    id: id,
    service: service,
    label: label,
    url: url,
    credential: credential,
    username: username,
    viewerId: viewerId,
    access: access,
    account: account,
    owner: owner,
    away: away,
    unreadSecret: secret,
  );

  @override
  bool operator ==(Object other) {
    return other is ServiceInstance &&
        other.id == id &&
        other.service == service &&
        other.label == label &&
        other.url == url &&
        other.credential == credential &&
        other.username == username &&
        other.viewerId == viewerId &&
        other.access == access &&
        other.account == account &&
        other.owner == owner &&
        other.away == away &&
        other.unreadSecret == unreadSecret;
  }

  @override
  int get hashCode => Object.hash(
    id,
    service,
    label,
    url,
    credential,
    username,
    viewerId,
    access,
    account,
    owner,
    away,
    unreadSecret,
  );

  /// The kind of access only, never its values; an account by its kind and
  /// name, never its session.
  @override
  String toString() =>
      'ServiceInstance($id, ${service.name}, label: "$label", url: "$url", '
      'access: ${access.kind.name}'
      '${account == null ? '' : ', account: $account'}'
      '${owner == null ? '' : ', owner: $owner'}'
      '${away == null ? '' : ', away: $away'}'
      '${unreadSecret == null ? '' : ', unread: ${unreadSecret!.name}'})';
}

/// Which of a connection's secrets secure storage would not hand over.
enum UnreadSecret {
  /// The API key, password or token: the connection's own credential.
  credential,

  /// What a gateway in front of the service asks for: a Cloudflare service
  /// token, a proxy password, a custom header's value; at home or away.
  access,
}
