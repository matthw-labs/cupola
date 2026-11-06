import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/network_change.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/emby/data/emby_client.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_status_probe.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/connection_unanswered.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/unread_secret.dart'
    show secureStoreName;
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';

/// Where a service's connection is checked, and how the result is described.
///
/// Onboarding grew a verifier that classifies *why* a connection failed while
/// settings kept a separate reachability-only check, so the same instance could
/// say "rejected the API key" during setup and a shrugging "could not reach it"
/// afterwards. Both now run through this file, and the health-endpoint table
/// lives once on the registry, as `ServiceKey.statusEndpoint`.

/// The outcome of a connection attempt: the status, why it failed, and the
/// certificate that explains the failure when one does.
///
/// Reachability alone leaves every failure looking identical, so the reason is
/// what lets the UI say "credentials rejected" instead of "check everything".
class ServiceDiagnosis {
  const ServiceDiagnosis(
    this.status, [
    this.reason,
    this.certificateProbe,
    this.detail,
  ]) : serverVersion = null,
       gateway = null,
       webPage = null,
       answered = null,
       connectionId = null;

  /// The full form, for the places that set a field the positional list cannot
  /// reach: Dart allows optional positionals or optional named, not both, and
  /// the positional shape above is what every call site already uses.
  const ServiceDiagnosis._all({
    required this.status,
    this.reason,
    this.certificateProbe,
    this.detail,
    this.serverVersion,
    this.gateway,
    this.webPage,
    this.answered,
    this.connectionId,
  });

  const ServiceDiagnosis.connected() : this(ServiceConnectionStatus.connected);

  /// The service answered, and named its own version on the way.
  ///
  /// Worth carrying because a green tick can still be the wrong answer: a
  /// TrueNAS older than the minimum authenticates, replies, and then leaves
  /// half the console empty. The version is what lets the test say so at the
  /// moment it is read, rather than leaving the user to find out inside the hub.
  const ServiceDiagnosis.connectedAs(String version)
    : this._all(
        status: ServiceConnectionStatus.connected,
        serverVersion: version,
      );

  const ServiceDiagnosis.notConfigured()
    : this(ServiceConnectionStatus.notConfigured);

  const ServiceDiagnosis.checking() : this(ServiceConnectionStatus.checking);

  /// Away from home, a connection with no address away: nothing was asked
  /// ([ServiceFailureReason.onlyAtHome]). Neutral, never a fault.
  const ServiceDiagnosis.onlyAtHome()
    : this(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.onlyAtHome,
      );

  /// The service answered, but could not be reached again to confirm.
  const ServiceDiagnosis.dropped()
    : this(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.unreachable,
      );

  /// The OS refused to let Cupola onto the local network, so the request never
  /// left the device. Not derived from an error; see
  /// [ServiceFailureReason.localNetworkBlocked].
  const ServiceDiagnosis.localNetworkBlocked()
    : this(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.localNetworkBlocked,
      );

  ServiceDiagnosis.failed(
    Object error, {
    ServiceFailureReason fallback = ServiceFailureReason.unknown,
  }) : this._all(
         status: ServiceConnectionStatus.disconnected,
         reason: classifyConnectionFailure(error, fallback: fallback),
         detail: connectionFailureDetail(error),
         gateway: accessGatewayOf(error),
         webPage: webPageAnswerOf(error),
         answered: wrongServiceAnswerOf(error)?.answered,
       );

  final ServiceConnectionStatus status;

  /// Null unless [status] is `disconnected`.
  final ServiceFailureReason? reason;

  /// Non-null only when the connection failed specifically because the server
  /// presents a certificate not trusted by the platform and not yet pinned;
  /// [UntrustedCertificateProbe.rotated] is what tells the UI whether this is
  /// a first-time trust or this origin's pin no longer matches (ADR-6).
  final UntrustedCertificateProbe? certificateProbe;

  /// The verbatim sentence the failure carried, when it carried one.
  ///
  /// Almost always null: a [ServiceFailureReason] plus the service's name is
  /// enough to write a better sentence than a client library would. The
  /// exception is a component that knows something the closed vocabulary cannot
  /// hold: `SameOriginRedirectInterceptor` refusing a cross-origin redirect
  /// knows *which* origin it was sent to, and `redirected` alone can only say
  /// "a redirect Cupola will not follow". Rendered in place of
  /// [connectionFailureMessage] when present, never alongside it.
  final String? detail;

  /// The version string the server reported during the test, for the services
  /// that say; null everywhere else. Raw and unparsed: turning it into words,
  /// and into a caveat where the version matters, is `describeServerVersion`'s
  /// job, so both surfaces that report a test say the same thing about it.
  final String? serverVersion;

  /// What answered in front of the service, when the test met a gateway
  /// ([ServiceFailureReason.accessGateway]): the words name it, as Home's do.
  final AccessGatewayAnswer? gateway;

  /// The web page that answered in the service's place, when the test met
  /// one: its sentence names where, as Home's and the library's do.
  final UnexpectedAnswer? webPage;

  /// The other service of the stack that answered at the address, when the
  /// test met one ([WrongServiceAnswer.answered]). What lets the form say
  /// `This is Emby` and offer that service's form, instead of only refusing.
  final ServiceKey? answered;

  /// Which connection this answer is about, when it comes from a fold across
  /// a service's connections ([diagnoseService]); null for an answer about
  /// the one connection it was asked of. What lets a row that speaks for
  /// two Radarrs say which of them is out of reach, instead of printing the
  /// second one's state beside the first one's address.
  final String? connectionId;

  /// This answer, said of connection [id].
  ServiceDiagnosis ofConnection(String id) => ServiceDiagnosis._all(
    status: status,
    reason: reason,
    certificateProbe: certificateProbe,
    detail: detail,
    serverVersion: serverVersion,
    gateway: gateway,
    webPage: webPage,
    answered: answered,
    connectionId: id,
  );

  /// What the UI should actually say about this outcome.
  ///
  /// One accessor rather than `detail ?? connectionFailureMessage(...)` repeated
  /// at each surface: the settings screen and the onboarding walk both report
  /// the same test, and them disagreeing is exactly the drift this codebase
  /// keeps paying for elsewhere.
  String messageFor(ServiceKey service) => failureMessageOf(
    service,
    ClassifiedFailure(
      reason ?? ServiceFailureReason.unknown,
      detail: detail,
      gateway: gateway,
      webPage: webPage,
    ),
  );

  bool get isConnected => status == ServiceConnectionStatus.connected;

  bool get isDisconnected => status == ServiceConnectionStatus.disconnected;

  bool get isConfigured => status != ServiceConnectionStatus.notConfigured;

  /// This diagnosis of a connection neither of whose addresses answered the
  /// route probe ([unanswered] says where): a silence is said of both
  /// ([ServiceFailureReason.unreachableAtBoth]), naming the two addresses;
  /// any other outcome is its own.
  ServiceDiagnosis saidOfBoth(ConnectionUnanswered unanswered) =>
      reason == ServiceFailureReason.unreachable
      ? ServiceDiagnosis._all(
          status: status,
          reason: ServiceFailureReason.unreachableAtBoth,
          detail: unanswered.failureDetail,
        )
      : this;

  ServiceDiagnosis withCertificateProbe(UntrustedCertificateProbe? probe) =>
      ServiceDiagnosis._all(
        status: status,
        reason: reason,
        certificateProbe: probe,
        detail: detail,
        serverVersion: serverVersion,
        gateway: gateway,
        webPage: webPage,
        answered: answered,
        connectionId: connectionId,
      );

  /// This failure, with what probing its address found, which then is its
  /// reason: a certificate nobody trusts ([ServiceFailureReason.tls], with
  /// the certificate to offer), or a port that serves plain http. Either says
  /// more than the failure did, whose words were about a handshake that broke
  /// off or ran out of time.
  ServiceDiagnosis withFinding(TlsFinding? finding) => switch (finding) {
    null => this,
    UntrustedCertificate(:final probe) => ServiceDiagnosis._all(
      status: ServiceConnectionStatus.disconnected,
      reason: ServiceFailureReason.tls,
      certificateProbe: probe,
      connectionId: connectionId,
    ),
    PlainHttpPort() => ServiceDiagnosis._all(
      status: ServiceConnectionStatus.disconnected,
      reason: ServiceFailureReason.plainHttp,
      connectionId: connectionId,
    ),
  };
}

/// Verifies [service] against the credentials passed in, rather than the saved
/// ones, so a form can test what is typed before committing it.
///
/// [clientIdentifier] is Plex's persisted `X-Plex-Client-Identifier` and is
/// ignored by every other service. It is read from settings rather than minted
/// here because Plex registers a new device row against the user's server for
/// each distinct value it sees.
///
/// [access] is what the connection presents to a gateway in front of the
/// service, sent on every request of the test as it is on every other.
Future<ServiceDiagnosis> diagnoseCredentials(
  ServiceKey service, {
  required String url,
  String apiKey = '',
  String username = '',
  String password = '',
  String certFingerprint = '',
  String clientIdentifier = '',
  ConnectionAccess access = const NoAccess(),
}) async {
  final accessHeaders = access.headers();
  final pin = certFingerprint.trim().isEmpty ? null : certFingerprint.trim();
  final user = username.trim().isEmpty ? null : username.trim();
  final pass = password.isEmpty ? null : password;
  final urlTrimmed = url.trim();

  if (service == ServiceKey.dockge) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = DockgeClient(
      baseUrl: urlTrimmed,
      username: user,
      password: pass,
      certFingerprint: pin,
      accessHeaders: accessHeaders,
    );
    try {
      final ok = await client.ping().timeout(const Duration(seconds: 8));
      // A rejected login throws with `unauthorized`, so `false` here means the
      // socket dropped after authenticating: a connection fault, not a wrong
      // password. Reporting it as "credentials rejected" sent users to re-type a
      // password that was fine.
      return ok
          ? const ServiceDiagnosis.connected()
          : const ServiceDiagnosis.dropped();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      await client.close();
    }
  }

  if (service == ServiceKey.nzbget) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = NzbgetClient(
      url: urlTrimmed,
      username: user,
      password: pass,
      certFingerprint: pin,
      accessHeaders: accessHeaders,
    );
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  if (service == ServiceKey.nginxProxyManager) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = NpmClient(
      url: urlTrimmed,
      identity: user,
      secret: pass,
      certFingerprint: pin,
      accessHeaders: accessHeaders,
    );
    // Checks both halves: `GET /api/` proves an NPM is there, and the login
    // proves the credential. Only the first would go green for a wrong
    // password, since the admin port answers 200 with its SPA for almost any
    // request.
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 10),
      close: client.close,
    );
  }

  if (service == ServiceKey.transmission) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = TransmissionClient(
      url: urlTrimmed,
      username: user,
      password: pass,
      certFingerprint: pin,
      accessHeaders: accessHeaders,
    );
    // `session-get` in one round trip forces the CSRF handshake, validates
    // the Basic credentials, and proves the rpc/host whitelists admit this
    // device: the three ways a reachable Transmission still refuses to talk.
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  // Named, not inferred. This used to read `if (!service.usesApiKey)`, which is
  // a *negative capability* rather than an identity, so every future
  // credential-authenticated service was silently routed here, and Transmission
  // would have had its password POSTed as form data to
  // `/api/v2/auth/login` on the Transmission host. It 404s, so the failure
  // would have looked like a broken client rather than a broken dispatcher.
  // `_diagnoseOverApiClient` now fails closed for anything that reaches it
  // unrouted, which is the other half of that guard.
  if (service == ServiceKey.qbittorrent) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = QbittorrentClient(
      url: urlTrimmed,
      username: user,
      password: pass,
      certFingerprint: pin,
      accessHeaders: accessHeaders,
    );
    // Two round trips (login + version), so allow more than a single hop.
    return _probe(
      client.getVersion,
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  if (urlTrimmed.isEmpty || apiKey.trim().isEmpty) {
    return const ServiceDiagnosis.notConfigured();
  }

  if (service == ServiceKey.seerr) {
    return diagnoseSeerr(
      ServiceInstance(
        id: '',
        service: service,
        url: urlTrimmed,
        credential: apiKey.trim(),
        access: access,
      ),
      reach: (url: urlTrimmed, access: access, pin: pin),
    );
  }

  if (service == ServiceKey.sabnzbd) {
    final client = SabnzbdClient(
      url: urlTrimmed,
      apiKey: apiKey.trim(),
      certFingerprint: pin,
      accessHeaders: accessHeaders,
    );
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  if (service == ServiceKey.unraid) {
    final client = UnraidClient(
      url: urlTrimmed,
      apiKey: apiKey.trim(),
      certFingerprint: pin,
      accessHeaders: accessHeaders,
    );
    return _probe(
      client.testConnection,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  if (service == ServiceKey.truenas) {
    final client = TrueNasWsClient(
      baseUrl: urlTrimmed,
      apiKey: apiKey.trim(),
      certFingerprint: pin,
      accessHeaders: accessHeaders,
    );
    try {
      // `core.ping` stays the verdict: it is the cheapest call that proves the
      // socket, the login and the API key all at once.
      await client.call('core.ping').timeout(const Duration(seconds: 6));
      // The version is a second hop on the socket that is already open and
      // authenticated, and it is deliberately *not* allowed to change the
      // verdict: a server that pings is connected whether or not it will name
      // itself. Hence the swallowed failure: the outcome loses one line, not
      // its green tick.
      String? version;
      try {
        version = stringOrNull(
          await client
              .call('system.version')
              .timeout(const Duration(seconds: 4)),
        );
      } catch (_) {
        version = null;
      }
      return version == null || version.trim().isEmpty
          ? const ServiceDiagnosis.connected()
          : ServiceDiagnosis.connectedAs(version.trim());
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      await client.close();
    }
  }

  // The media servers authenticate with a header the shared `ApiClient`
  // does not send: `Authorization: MediaBrowser Token=` for Jellyfin,
  // `X-Emby-Token` for Emby, `X-Plex-Token` for Plex, and all their health
  // endpoints in the table above are anonymous. Verified through the generic branch, *any* non-empty string
  // therefore came back 2xx and the tile went green while every real call 401ed.
  // Their own clients are what actually present the credential.
  if (service == ServiceKey.jellyfin || service == ServiceKey.emby) {
    // Two constructions, not a factory: each client is opened where its pin
    // and access are visible (`access_headers_guard_test`).
    final MediaBrowserClient client = service == ServiceKey.emby
        ? EmbyClient(
            baseUrl: urlTrimmed,
            apiKey: apiKey.trim(),
            pinnedCertFingerprint: pin,
            accessHeaders: accessHeaders,
          )
        : JellyfinClient(
            baseUrl: urlTrimmed,
            apiKey: apiKey.trim(),
            pinnedCertFingerprint: pin,
            accessHeaders: accessHeaders,
          );
    bool accepted;
    String? version;
    try {
      // `/System/Info`, the authenticated twin of the public probe, and who
      // answered is checked with the credential. An Emby answers a
      // Jellyfin's routes (and a Jellyfin the legacy `/emby` ones) and
      // accepts the key, so a bare yes read as a connection to the wrong
      // server; this path throws `WrongServiceAnswer` for it, which the form
      // turns into `This is Emby`. Any transport refusal is explained below,
      // as it is for the bare check.
      try {
        version = await client.checkCredentialAndVersion().timeout(
          const Duration(seconds: 6),
        );
        accepted = true;
      } on DioException {
        accepted = false;
      }
      // The version is a second read, the Dashboard probe's own (`Version` on
      // the anonymous endpoint), and like TrueNAS's it is not allowed to change
      // the verdict: a server that accepted the key is connected whether or not
      // it names itself, and `probeVersion` answers null rather than throwing.
      if (accepted && version == null) {
        version = await client.probeVersion().timeout(
          const Duration(seconds: 4),
          onTimeout: () => null,
        );
      }
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
    if (accepted) {
      final named = version?.trim();
      return named == null || named.isEmpty
          ? const ServiceDiagnosis.connected()
          : ServiceDiagnosis.connectedAs(named);
    }
    return _explainCredentialRefusal(
      service,
      url: urlTrimmed,
      pin: pin,
      accessHeaders: accessHeaders,
    );
  }

  if (service == ServiceKey.plex) {
    final client = PlexClient(
      url: urlTrimmed,
      token: apiKey.trim(),
      clientIdentifier: clientIdentifier.trim(),
      pinnedCertFingerprint: pin,
      accessHeaders: accessHeaders,
    );
    try {
      // Unlike Jellyfin's, this one already separates the two questions: it
      // answers false only for an actual refusal and rethrows a `PlexException`
      // carrying its own `ServiceFailureReason` for anything else, including
      // the JWT it refuses to send at all, which is an unauthorized the user has
      // to fix by pasting a different *kind* of token. So no second probe.
      final accepted = await client.verifyCredential().timeout(
        const Duration(seconds: 6),
      );
      return accepted
          ? const ServiceDiagnosis.connected()
          : const ServiceDiagnosis(
              ServiceConnectionStatus.disconnected,
              ServiceFailureReason.unauthorized,
            );
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
  }

  // A media server's status route is anonymous, so one that reached the generic
  // branch would read any key as answering: each has its own arm above.
  assert(!service.isMediaServer, '${service.name} has no credential check');
  return _diagnoseOverApiClient(
    service,
    url: urlTrimmed,
    apiKey: apiKey,
    pin: pin,
    accessHeaders: accessHeaders,
  );
}

/// Tests a Seerr connection the way the Dashboard's probe reads it: one
/// authenticated request, because `/status` is public and would read any key
/// as answering, then who answered.
///
/// [instance] signs in its own way, the key or an account's session
/// (`seerrClientFor`); [reach] is the address asked, with its access and the
/// certificate trusted for its origin (null: the address at home, no pin).
Future<ServiceDiagnosis> diagnoseSeerr(
  ServiceInstance instance, {
  ConnectionReach? reach,
}) async {
  final client = seerrClientFor(instance, reach: reach);
  try {
    await SeerrService(
      client,
    ).testConnection().timeout(const Duration(seconds: 5));
    await readServiceStatus(
      client,
      ServiceKey.seerr,
      url: (reach?.url ?? instance.url).trim(),
    );
    return const ServiceDiagnosis.connected();
  } catch (e) {
    return ServiceDiagnosis.failed(e);
  } finally {
    client.close();
  }
}

/// The envelope every single-call probe above shares: run it under this
/// service's own deadline, turn anything thrown into a classified failure, and
/// close the client whichever way it went.
///
/// [timeout] is a parameter rather than a constant because the deadlines are
/// per-service and deliberate: a client that logs in before it can answer
/// needs more than one hop's worth of headroom.
///
/// [close] is a `FutureOr` so the one asynchronous `close` (TrueNAS, which has a
/// socket to shut down) and the synchronous Dio ones share this path without
/// either being rewritten: awaiting a non-future would still be correct, but the
/// explicit test keeps the sync branches exactly as they were.
Future<ServiceDiagnosis> _probe(
  Future<void> Function() run, {
  required Duration timeout,
  required FutureOr<void> Function() close,
}) async {
  try {
    await run().timeout(timeout);
    return const ServiceDiagnosis.connected();
  } catch (e) {
    return ServiceDiagnosis.failed(e);
  } finally {
    final closing = close();
    if (closing is Future) await closing;
  }
}

/// Reachability and status classification over the shared [ApiClient], which
/// has been pin-aware since ADR-6. This is the branch the pinning scope used
/// to carve out. [pin] threads straight through; when it is null this is
/// byte-identical to the pre-ADR-6 unpinned client.
Future<ServiceDiagnosis> _diagnoseOverApiClient(
  ServiceKey service, {
  required String url,
  required String apiKey,
  required String? pin,
  Map<String, String> accessHeaders = const {},
}) async {
  // Fails closed on a routing bug. An empty entry in
  // [ServiceKey.statusEndpoint] means "this service is verified through its own
  // client", and every one of those has a branch above. If a new service
  // reaches here without one, the request below would be `GET ''`: a plain
  // fetch of the base URL, which most of these servers answer 200 for with
  // their own web UI, *whatever* credential was supplied. That is a green
  // "Answering" tile for a wrong password: the exact bug that shipped once for
  // Jellyfin and Plex. Reporting the service as unreachable is wrong too, but
  // it is wrong in the direction that gets noticed and cannot mislead anyone
  // into thinking a bad credential works.
  // Seerr has a branch of its own above, with its own client.
  assert(service != ServiceKey.seerr, 'Seerr is verified by seerrClientFor');
  final endpoint = service.statusEndpoint;
  if (endpoint.isEmpty) {
    return const ServiceDiagnosis(
      ServiceConnectionStatus.disconnected,
      ServiceFailureReason.unknown,
    );
  }

  final client = ApiClient(
    baseUrl: url,
    apiKey: apiKey.trim(),
    pinnedCertFingerprint: pin,
    accessHeaders: accessHeaders,
  );
  try {
    // The Dashboard probe's own reading: the status route, and who answered
    // it. A 2xx from something that is not the service is not a pass.
    await readServiceStatus(client, service, url: url);
    return const ServiceDiagnosis.connected();
  } catch (e) {
    return ServiceDiagnosis.failed(e);
  } finally {
    client.close();
  }
}

/// Turns "the credential was not accepted" into a verdict, for a service whose
/// own client cannot say *why* it said no.
///
/// Asks the credential-free endpoint whether the box is even there. If it
/// answers, the address is right and the credential is the thing that was
/// refused; if it does not, the original failure was never about the key and
/// the reachability verdict (unreachable, TLS, wrong base path) is the honest
/// one to report. Costs a second round trip only on the failure path.
Future<ServiceDiagnosis> _explainCredentialRefusal(
  ServiceKey service, {
  required String url,
  required String? pin,
  Map<String, String> accessHeaders = const {},
}) async {
  final reachability = await _diagnoseOverApiClient(
    service,
    url: url,
    apiKey: '',
    pin: pin,
    accessHeaders: accessHeaders,
  );
  if (!reachability.isConnected) return reachability;
  return const ServiceDiagnosis(
    ServiceConnectionStatus.disconnected,
    ServiceFailureReason.unauthorized,
  );
}

/// Verifies **every** configured connection of [service] and reports the worst
/// answer among them.
///
/// Folded rather than answered off the first instance, and that is the whole of
/// what this function had to learn: the surfaces that read it (the Connections
/// row, the Settings home list) speak in services and now also print how many
/// connections a service has. "Answering · radarr.lan · 2 connections" while the
/// second Radarr is switched off is a green row for a stack with a dead server
/// in it, and it is green on the one screen the user would go to in order to fix
/// it. `ServiceMatrixCell` already folds its pip the same way, through
/// [foldedServiceHealthProvider].
///
/// The cost is one probe per connection instead of one per service. That is the
/// honest price of the count beside it: before, the second connection was never
/// asked at all.
///
/// [diagnose] answers for one connection, [diagnoseInstance] unless a caller
/// has a better way to ask: the readouts that run unattended pass one that
/// reads qBittorrent through its connection's own client
/// ([diagnoseSavedInstance]). Called for every connection before anything is
/// awaited.
Future<ServiceDiagnosis> diagnoseService(
  ServiceKey service,
  SettingsModel settings, {
  Future<ServiceDiagnosis> Function(ServiceInstance instance)? diagnose,
}) async {
  // A Seerr account whose session ended is not set up, and still not a
  // connection to forget: it reads signed out.
  final instances = [
    for (final instance in settings.instancesOf(service))
      if (instance.isConfigured || instance.isSignedOut) instance,
  ];
  if (instances.isEmpty) return const ServiceDiagnosis.notConfigured();

  final pending = [
    for (final instance in instances)
      diagnose?.call(instance) ??
          diagnoseInstance(instance, settings, route: ConnectionRoute.home),
  ];
  final answers = await Future.wait(pending);
  return worstDiagnosis([
    for (final (i, answer) in answers.indexed)
      answer.ofConnection(instances[i].id),
  ]);
}

/// The diagnosis a folded readout should show: the one the user most needs to
/// act on.
///
/// Ordered by how much attention the state wants rather than by enum order, so
/// a single unreachable connection is never hidden behind a sibling that is up.
ServiceDiagnosis worstDiagnosis(List<ServiceDiagnosis> results) {
  var worst = results.first;
  for (final result in results.skip(1)) {
    if (_attention(result) > _attention(worst)) worst = result;
  }
  return worst;
}

int _attention(ServiceDiagnosis diagnosis) => switch (diagnosis.status) {
  // Only at home is not a fault: below anything that needs a hand, above a
  // sibling that answers, so the row still says one of them is out of reach.
  ServiceConnectionStatus.disconnected
      when diagnosis.reason == ServiceFailureReason.onlyAtHome =>
    1,
  ServiceConnectionStatus.disconnected => 3,
  ServiceConnectionStatus.notConfigured => 2,
  ServiceConnectionStatus.checking => 1,
  ServiceConnectionStatus.connected => 0,
};

/// Diagnoses one specific connection.
///
/// The form that matters once a service can have more than one: [diagnoseService]
/// folds every connection into one answer, which is right for a row that names
/// the service and wrong for a form that is editing exactly one of them.
/// [settings] is still
/// needed for the two values that are not the instance's own: the pin, which
/// belongs to a TLS origin, and the Plex client id, which belongs to the install.
///
/// [route] says which of the connection's addresses is asked ([reachOf]), and
/// every caller says it: [ConnectionRoute.home] for a form testing what is
/// typed (the address in the field is the one to verify), the connection's
/// own route for a readout of a saved one ([diagnoseSavedInstance]), which
/// reports whether the connection answers where the app reaches it.
Future<ServiceDiagnosis> diagnoseInstance(
  ServiceInstance instance,
  SettingsModel settings, {
  required ConnectionRoute route,
}) {
  // Signed out: nothing to ask the server, the person has a step to take.
  if (instance.isSignedOut) {
    return Future.value(
      const ServiceDiagnosis(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.sessionEnded,
      ),
    );
  }
  if (!instance.isConfigured) {
    return Future.value(const ServiceDiagnosis.notConfigured());
  }
  final service = instance.service;
  final reach = reachOf(settings, instance, route);
  // An account has no key to hand over: the connection signs in its own way.
  if (service == ServiceKey.seerr && instance.account != null) {
    return diagnoseSeerr(instance, reach: reach);
  }
  return diagnoseCredentials(
    service,
    url: reach.url,
    // The credential sits in one slot and which vocabulary it answers to is the
    // registry's call, exactly as it is in storage.
    apiKey: service.usesApiKey ? instance.credential : '',
    username: instance.username,
    password: service.usesApiKey ? '' : instance.credential,
    certFingerprint: reach.pin ?? '',
    clientIdentifier: settings.plexClientId,
    access: reach.access,
  );
}

/// Diagnoses one **saved** connection for a readout nobody asked to re-test:
/// the Settings rows, which re-run on launch, on every settings write and on a
/// refresh.
///
/// [diagnoseInstance] for every service but qBittorrent, which is asked
/// through its connection's own client ([qbittorrentClientForProvider]). A
/// throwaway client sent the login again each time, so with a wrong password
/// every re-run of these readouts, a theme toggle included, counted toward
/// qBittorrent's ban of the address. The shared client holds a refused
/// sign-in until the credentials change or a user's Retry or test lifts it,
/// and it is not this readout's to close.
///
/// A form testing what is typed keeps [diagnoseInstance]: that is the person
/// asking, once per press, about values that may not be saved yet.
///
/// Asked where the connection is reached now: the route is watched, so a
/// readout that read `Unreachable` at home asks again at the address away
/// once the route moves there.
Future<ServiceDiagnosis> diagnoseSavedInstance(
  Ref ref,
  ServiceInstance instance,
  SettingsModel settings,
) {
  // Away from home, a connection reached only there is not asked: the route
  // already says what a timeout would.
  if (instance.away == null &&
      instance.isConfigured &&
      ref.watch(awayFromHomeProvider)) {
    return Future.value(const ServiceDiagnosis.onlyAtHome());
  }
  final route = watchConnectionRoute(
    ref,
    instance.id,
    hasAway: instance.away != null,
  );
  // Neither address answered the route probe's last knock: a silence here is
  // said of both. Watched only for a connection with an address away.
  final unanswered = instance.away == null
      ? null
      : ref.watch(unansweredConnectionProvider(instance.id));
  final Future<ServiceDiagnosis> diagnosis;
  if (instance.service == ServiceKey.qbittorrent && instance.isConfigured) {
    final client = ref.watch(qbittorrentClientForProvider(instance.id));
    // Two round trips (login + version) on a cold client.
    diagnosis = _probe(
      client.getVersion,
      timeout: const Duration(seconds: 8),
      close: () {},
    );
  } else {
    diagnosis = diagnoseInstance(instance, settings, route: route);
  }
  return unanswered == null
      ? diagnosis
      : diagnosis.then((result) => result.saidOfBoth(unanswered));
}

/// Whether a blocked local network could still explain this failure.
///
/// The mirror of [certProbeWorthwhile], and it rules out one more: a TLS failure
/// proves the packets reached a server, so the OS was never in the way. What is
/// left: nothing answered, nothing answered in time, or nothing attributable.
/// That is exactly how a permission the user has not granted looks from the socket.
bool localNetworkCouldExplain(ServiceFailureReason? reason) => switch (reason) {
  ServiceFailureReason.unauthorized ||
  ServiceFailureReason.addressRefused ||
  // Nothing was sent: the secret never left the device's storage.
  ServiceFailureReason.secretUnread ||
  ServiceFailureReason.sessionEnded ||
  ServiceFailureReason.csrfRefused ||
  ServiceFailureReason.notFound ||
  ServiceFailureReason.redirected ||
  ServiceFailureReason.accessGateway ||
  ServiceFailureReason.serverError ||
  ServiceFailureReason.invalidResponse ||
  ServiceFailureReason.tls ||
  ServiceFailureReason.plainHttp ||
  ServiceFailureReason.noSecureConnection ||
  // Refused before dialling: the OS was never asked for anything.
  ServiceFailureReason.insecureTransport ||
  // Already attributed; asking again would only re-confirm it.
  ServiceFailureReason.localNetworkBlocked ||
  // Not asked, away from home: nothing was dialled.
  ServiceFailureReason.onlyAtHome => false,
  _ => true,
};

/// Runs [diagnose] and, when it fails the way a blocked local network fails,
/// asks the OS whether that is what happened.
///
/// The order is the whole design. Cupola never asks first: on iOS the *failing
/// connection is what raises the system alert*, so by the time this asks, the
/// alert the user must answer is already on screen, and asking only after a
/// failure means a public server timing out can never raise a Local Network
/// prompt out of nowhere. Three outcomes, three different truths:
///
/// * `justGranted`: the user allowed it while we were asking. The failed
///   connection was dialled through a closed gate, so its verdict is void and
///   the test is simply run again. This is the retest the user used to have to
///   work out for themselves.
/// * `denied`: report the permission, not the address. The old copy sent people
///   to re-check a hostname and port that were right all along.
/// * anything else: keep the original failure untouched. Claiming a permission
///   problem on a hunch would be the same bug in the other direction.
///
/// [timeout] is how long the OS gets to answer. Pass something generous where a
/// human is watching (they are reading an alert), and something short on a
/// background refresh, where the only answer worth having is one the OS already
/// holds.
Future<ServiceDiagnosis> diagnoseThroughLocalNetworkGate(
  Future<ServiceDiagnosis> Function() diagnose, {
  required String url,
  Duration timeout = const Duration(seconds: 20),
  LocalNetworkProbe probe = probeLocalNetworkAccess,
}) async {
  final first = await diagnose();
  if (!first.isDisconnected || !localNetworkCouldExplain(first.reason)) {
    return first;
  }
  final access = await probe(url, timeout: timeout);
  return switch (access) {
    LocalNetworkAccess.justGranted => await diagnose(),
    LocalNetworkAccess.denied => const ServiceDiagnosis.localNetworkBlocked(),
    LocalNetworkAccess.granted ||
    LocalNetworkAccess.unrestricted ||
    LocalNetworkAccess.unknown => first,
  };
}

/// Whether probing the address could still explain this failure
/// ([probeUntrustedCertificate]).
///
/// An untrusted certificate surfaces as `tls`, and as `unreachable`/`unknown`
/// when the handshake fails before a reason can be attributed. A port that
/// serves plain http surfaces as `noSecureConnection` when it closes the
/// handshake, and as `unreachable` when it waits it out. Anything the
/// server answered (a rejected key, a 404, a 500, a redirect nobody could
/// follow) rules the certificate out: the response proves the handshake
/// already completed, so probing for an untrusted certificate costs a round
/// trip to learn nothing.
bool certProbeWorthwhile(ServiceFailureReason? reason) => switch (reason) {
  ServiceFailureReason.unauthorized ||
  ServiceFailureReason.addressRefused ||
  // Nothing was sent: the secret never left the device's storage.
  ServiceFailureReason.secretUnread ||
  ServiceFailureReason.sessionEnded ||
  ServiceFailureReason.csrfRefused ||
  ServiceFailureReason.notFound ||
  ServiceFailureReason.redirected ||
  ServiceFailureReason.accessGateway ||
  ServiceFailureReason.serverError ||
  ServiceFailureReason.invalidResponse ||
  // Nothing left the device, so there is no handshake to inspect: the probe
  // opens its own socket to the same blocked address and can only time out.
  ServiceFailureReason.localNetworkBlocked ||
  // Refused before dialling, and the probe would dial the very address the
  // refusal was protecting the key from.
  ServiceFailureReason.insecureTransport ||
  // Not asked, away from home: the probe would dial the address at home
  // the route already found silent.
  ServiceFailureReason.onlyAtHome ||
  // The port answered in plain http: no certificate was sent, and the probe
  // would meet the same reply.
  ServiceFailureReason.plainHttp => false,
  _ => true,
};

/// Verifies one connection against [settings] and, when it fails in a way a
/// certificate could explain, attaches the probe so the UI can offer to trust
/// it. Every service can reach this since ADR-6; there is no
/// pinning-capability gate left to check. Never trusts anything itself.
///
/// Takes the instance rather than the service: the caller is a form editing one
/// connection, and probing the origin of a *different* one would put the trust
/// prompt in front of the user for a certificate they were not asked about.
Future<ServiceDiagnosis> diagnoseInstanceWithCertProbe(
  ServiceInstance instance,
  SettingsModel settings, {
  CertificateProber probe = probeUntrustedCertificate,
}) async {
  // The form's own address, the one in its field.
  final diagnosis = await diagnoseInstance(
    instance,
    settings,
    route: ConnectionRoute.home,
  );
  if (!diagnosis.isDisconnected || !certProbeWorthwhile(diagnosis.reason)) {
    return diagnosis;
  }
  final url = instance.url;
  final finding = await probe(
    url,
    pinnedFingerprint: settings.pinForUrl(url) ?? '',
  );
  return diagnosis.withFinding(finding);
}

/// The sentence under a failure of [service], from the failure itself: what
/// [error] knew beyond its reason (a web page that answered in the service's
/// place, a gateway, a sentence of its own), and the reason's words
/// otherwise.
///
/// The one sentence the Dashboard's summary, the connection test and a
/// library's failure state say about one failure, which is why each hands
/// over the failure (the exception, or the `ClassifiedFailure` that kept it)
/// rather than its reason.
String failureMessageOf(ServiceKey service, Object? error) {
  final page = webPageAnswerOf(error);
  if (page != null) return webPageSentence(service, page);
  return connectionFailureDetail(error) ??
      connectionFailureMessage(
        service,
        classifyConnectionFailure(error),
        gateway: accessGatewayOf(error),
      );
}

/// User-facing copy for a failed verification. Each cause names the thing the
/// user can actually change. Prefer [failureMessageOf], which reads what the
/// failure knew; this is the reason's own words.
///
/// [gateway] is what answered in front of the service for an
/// [ServiceFailureReason.accessGateway] ([accessGatewayOf] the failure).
String connectionFailureMessage(
  ServiceKey service,
  ServiceFailureReason? reason, {
  AccessGatewayAnswer? gateway,
}) {
  switch (reason) {
    case ServiceFailureReason.unreachable:
      return 'Nothing answered at this address. Check the address and port, '
          'and that ${service.title} is running and reachable from this '
          'device.';
    case ServiceFailureReason.unreachableAtBoth:
      return 'Nothing answered at either saved address: ${service.title} may '
          'be down, or this device may have no network.';
    case ServiceFailureReason.timeout:
      return 'The server was reached, then did not answer in time. Retry, or '
          'look at ${service.title} if it is still starting up.';
    case ServiceFailureReason.tls:
      // Never suggest downgrading to http:// here. A certificate that fails
      // to verify is the same signal an interception attack produces, and
      // every service can now offer the right answer (ADR-6): verify again
      // and confirm the certificate when Cupola offers to trust it.
      return 'The HTTPS certificate could not be verified. If '
          '${service.title} uses a self-signed certificate, test again and '
          'confirm the certificate when Cupola offers to trust it.';
    case ServiceFailureReason.plainHttp:
      // TrueNAS revokes a key sent over http, so its only way out is the
      // HTTPS port; for the others an http:// address at home is as good.
      return service == ServiceKey.truenas
          ? 'This port serves plain http, not https. Use the HTTPS port in '
                "TrueNAS's GUI settings: 443 unless it was changed."
          : 'This port serves plain http, not https. Use the port '
                '${service.title} serves https on, or http:// for an address '
                'used only at home.';
    case ServiceFailureReason.noSecureConnection:
      return 'The secure connection broke off before a certificate arrived. '
          'Check that this port serves https.';
    case ServiceFailureReason.addressRefused:
      return '${service.title} refused this address. Allow it in its settings, '
          'then check the connection.';
    case ServiceFailureReason.unauthorized:
      // The why, not the what again: the title above it already says the key
      // was refused, so this says where the right one comes from.
      return service.usesApiKey
          ? '${service.title} answered, and does not accept this '
                '${service.credentialLabel}. Copy it again from '
                "${service.title}'s own settings."
          : '${service.title} answered, and does not accept this username and '
                'password.';
    case ServiceFailureReason.sessionEnded:
      return 'This account was signed out of ${service.title}. Sign in again '
          'to keep asking for movies and series.';
    case ServiceFailureReason.onlyAtHome:
      return '${service.title} has no address away, so Cupola reaches it '
          'only on your home Wi-Fi.';
    case ServiceFailureReason.secretUnread:
      return "${secureStoreName()} didn't hand over the saved "
          '${service.credentialLabel}. Paste it again.';
    case ServiceFailureReason.csrfRefused:
      return '${service.title} refused the security token it had just handed '
          'out. Nothing changed. Retry in a moment.';
    case ServiceFailureReason.notFound:
      return 'Reached the server, but the ${service.title} API is not at this '
          'address. Check for a missing or wrong base path.';
    case ServiceFailureReason.redirected:
      // The generic form. A refusal from `SameOriginRedirectInterceptor`
      // carries its own sentence naming the origin it was sent to, and
      // `messageFor` shows that instead; this is what is left when only the
      // reason survived: an unfollowable 3xx from a client that does not
      // explain itself.
      return 'Reached the server, but it answered with a redirect Cupola '
          'will not follow. A reverse proxy in front of ${service.title} is '
          'the usual cause, point Cupola at the address the proxy sends '
          'the request to, or stop it redirecting the API.';
    case ServiceFailureReason.accessGateway:
      return accessGatewaySentence(gateway, subject: service.title);
    case ServiceFailureReason.serverError:
      return '${service.title} answered with a server error. Check the '
          'instance and its logs.';
    case ServiceFailureReason.invalidResponse:
      return 'Something answered at this address, but not with anything '
          'Cupola can read as ${service.title}. A reverse proxy page, or '
          'another app on this port, is the usual cause.';
    case ServiceFailureReason.insecureTransport:
      return 'The address starts with http://, so Cupola did not send the '
          '${service.credentialLabel} over it. Change it to https://.';
    case ServiceFailureReason.localNetworkBlocked:
      // Names the device, not the server, and never mentions the address: the
      // request never left this phone, so everything in the form is still
      // unproven rather than wrong. `remedy` spells out the route in the words
      // the running OS uses for it.
      return 'This device is blocking Cupola from reaching your local '
          'network, so ${service.title} was never dialled. '
          '${LocalNetworkPermission.remedy}';
    case ServiceFailureReason.unknown:
    case null:
      return 'The request did not complete. Double-check the address and '
          'credentials.';
  }
}

/// [instance] as far as asking it goes. A Seerr account is asked with its
/// session: signing in, signing out and an ended session move it, while the
/// permissions and the time `/auth/me` last answered are what it said, not
/// what it is asked with, and reading them again must not test it again.
ServiceInstance? _askedWith(ServiceInstance? instance) {
  final account = instance?.account;
  if (instance == null || account == null) return instance;
  return instance.copyWith(
    account: SeerrAccountSignIn(
      kind: account.kind,
      login: account.login,
      userId: account.userId,
      session: account.session,
    ),
  );
}

/// What one saved connection's verdict is read from: the connection itself,
/// the certificate pinned for its origin, and the install's Plex client id.
///
/// The two readouts below watched the whole [SettingsModel], so every settings
/// write (a theme toggle, another service's edit) re-tested every connection
/// over the network, and signed in again where a service signs in with a
/// password. Watched through this, a connection is asked again only when
/// something it is asked with changes.
typedef _DiagnosisInputs = ({
  ServiceInstance? instance,
  ConnectionReach? home,
  ConnectionReach? away,
  String plexClientId,
});

/// Both addresses with their pins: which of the two is asked is the route's,
/// watched beside this ([diagnoseSavedInstance]).
_DiagnosisInputs _diagnosisInputs(SettingsModel settings, String instanceId) {
  final instance = settings.instanceById(instanceId);
  return (
    instance: _askedWith(instance),
    home: instance == null
        ? null
        : reachOf(settings, instance, ConnectionRoute.home),
    away: instance?.away == null
        ? null
        : reachOf(settings, instance!, ConnectionRoute.away),
    plexClientId: settings.plexClientId,
  );
}

/// The connection state of one **connection**, refreshed whenever its saved
/// address or credentials change.
///
/// What a form editing a named connection has to read. [serviceDiagnosisProvider]
/// folds every connection of a service into its worst answer, which is right for
/// a row that speaks in services and wrong under a form whose fields belong to
/// exactly one server: it would report "Answering" over the second Radarr's
/// address because the first one is up.
///
/// Carries the same "no local-network gate" caveat as the per-service provider
/// below, and for the same reason.
final instanceDiagnosisProvider =
    FutureProvider.family<ServiceDiagnosis, String>((ref, instanceId) async {
      // Asked again when the phone's network changes: what answered on Wi-Fi
      // may not on the mobile network, and the reverse.
      ref.watch(networkChangesProvider);
      // Watch the connection's own inputs; read the whole model for the work.
      ref.watch(
        currentSettingsProvider.select((s) => _diagnosisInputs(s, instanceId)),
      );
      final settings = ref.read(currentSettingsProvider);
      final instance = settings.instanceById(instanceId);
      if (instance == null) return const ServiceDiagnosis.notConfigured();
      return diagnoseSavedInstance(ref, instance, settings);
    });

/// The connection state of a single service, folded across every connection it
/// has, so the answer is never better than its worst one. See [diagnoseService].
final serviceDiagnosisProvider =
    FutureProvider.family<ServiceDiagnosis, ServiceKey>((ref, service) async {
      // Asked again when the phone's network changes, as above.
      ref.watch(networkChangesProvider);
      // Which connections, joined into a string because a fresh list never
      // compares equal. Each one's own inputs are watched by its own diagnosis
      // below, which this one reads rather than asks again.
      // A Seerr account that signed out is among them: it reads signed out.
      ref.watch(
        currentSettingsProvider.select(
          (s) => s
              .instancesOf(service)
              .where((i) => i.isConfigured || i.isSignedOut)
              .map((i) => i.id)
              .join(','),
        ),
      );
      final settings = ref.read(currentSettingsProvider);
      // Deliberately *not* through `diagnoseThroughLocalNetworkGate`. This runs
      // unattended, on launch, and for every configured service at once, and
      // resolving the permission is not a passive question: on iOS it can put an
      // alert on screen, and it costs a Bonjour round trip per service. Neither
      // belongs in a background refresh nobody asked for.
      //
      // The cost is that a service blocked by the permission reads `Unreachable`
      // in the list rather than naming the permission. It is named the moment the
      // user does the obvious thing (open the service and test it), which is
      // where the fix lives anyway.
      //
      // One probe per connection, shared with the form that edits it: this
      // folds the answers [instanceDiagnosisProvider] already holds instead of
      // asking each server a second time, and signing in a second time where a
      // service counts failed sign-ins.
      return diagnoseService(
        service,
        settings,
        diagnose: (instance) =>
            ref.watch(instanceDiagnosisProvider(instance.id).future),
      );
    });
