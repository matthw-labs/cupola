import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/host_reach.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/emby/data/emby_client.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_status_probe.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';

/// A live reachability probe for one service.
///
/// The `select` is load-bearing rather than a micro-optimisation, because of
/// what this provider *is*: one family entry per service, each of which opens a
/// connection and waits out a 5–8 second timeout ([_loadVersion] builds a fresh
/// SABnzbd/NZBGet/Unraid client per call). Watching the whole
/// `SettingsModel` meant that every settings write (a theme-mode toggle
/// included) re-probed every service, and a single Save can write twice
/// because answering the cert-trust prompt writes again. Keyed on the service's
/// own connection details, only the service that actually changed re-probes.
/// The ids of every connection of [service], in order, as a stable value.
///
/// Joined and re-split rather than selected as a `List`: `instancesOf` builds a
/// fresh one on every call and lists compare by identity, so selecting one
/// would rebuild every consumer on every unrelated settings write.
final serviceInstanceIdsProvider = Provider.family<List<String>, ServiceKey>((
  ref,
  service,
) {
  final joined = ref.watch(
    currentSettingsProvider.select(
      (s) => s.instancesOf(service).map((i) => i.id).join(','),
    ),
  );
  return joined.isEmpty ? const [] : joined.split(',');
});

/// Health for a service folded across all of its connections.
///
/// [offline] is what the matrix needs and what a per-service probe cannot say:
/// with three Radarr and one unreachable, "online" is a lie and "offline" is a
/// different one. The cell reports the worst state it contains and how many are
/// in it, so a folded card never claims to be healthier than its worst
/// connection.
///
/// `offline` counts the connections that **did not answer**, and nothing else.
/// `faulted` counts the ones that answered with a refusal or a fault: a
/// refused key, a 5xx, which are amber, and which the band that names what
/// did not answer must never name. `stuck` counts the ones reached that never
/// replied: amber too, and answering no more than a dark one.
///
/// `onlyAtHome` counts the ones not asked because the app is away from home
/// and they have no address away: neutral, and none of the above.
typedef FoldedServiceHealth = ({
  int total,
  int offline,
  int faulted,
  int stuck,
  int checking,
  int onlyAtHome,
});

final foldedServiceHealthProvider =
    Provider.family<FoldedServiceHealth, ServiceKey>((ref, service) {
      final ids = ref.watch(serviceInstanceIdsProvider(service));
      var offline = 0;
      var faulted = 0;
      var stuck = 0;
      var checking = 0;
      var onlyAtHome = 0;
      var notSetUp = 0;
      for (final id in ids) {
        final summary = ref.watch(
          instanceSummaryProvider((service: service, instanceId: id)),
        );
        switch (summary) {
          case AsyncData(:final value) when value.isOnlyAtHome:
            onlyAtHome++;
          // Not asked, and not part of how the service stands: read off its
          // other connections.
          case AsyncData(:final value) when value.isNotSetUp:
            notSetUp++;
          case AsyncData(:final value):
            if (value.didNotAnswer) offline++;
            if (value.isStuck) {
              stuck++;
            } else if (value.isFault &&
                // A Seerr account that signed out was asked nothing and is
                // the person's step: beside a working connection it is no
                // fault.
                value.failureReason != ServiceFailureReason.sessionEnded) {
              faulted++;
            }
          case AsyncError(:final error):
            final reason = classifyConnectionFailure(error);
            if (reason == ServiceFailureReason.onlyAtHome) {
              onlyAtHome++;
            } else if (failureDidNotAnswer(reason)) {
              offline++;
            } else {
              faulted++;
            }
          default:
            checking++;
        }
      }
      return (
        total: ids.length - notSetUp,
        offline: offline,
        faulted: faulted,
        stuck: stuck,
        checking: checking,
        onlyAtHome: onlyAtHome,
      );
    });

/// One connection, named by what it is as well as by which one.
///
/// The service travels with the id so a probe for a connection that has since
/// been removed can still say what kind of thing it was. Keyed on the id alone,
/// the "gone" branch had nothing to answer with and named `ServiceKey.radarr`:
/// a Plex cell removed mid-flight reported an offline *Radarr*.
typedef InstanceRef = ({ServiceKey service, String instanceId});

/// A live reachability probe for one *connection*.
///
/// Keyed by connection, because two Radarr behind two addresses are two
/// different answers to "is it up" and the matrix has to be able to say which
/// one is down. [serviceSummaryProvider] is the per-service view of this.
final instanceSummaryProvider =
    FutureProvider.family<ServiceSummary, InstanceRef>((ref, key) async {
      // Watch the narrow key; read the whole model for the work. The
      // per-client branches in [_loadVersion] each reach for their own fields,
      // and none of them is anything but a projection of the key below. The
      // route is part of the key: a probe that found home silent asks again
      // at the address away once the route moves there.
      final route = ref.watch(connectionRouteProvider(key.instanceId));
      final reached = ref.watch(
        currentSettingsProvider.select(
          (s) => _connectionOfInstance(s, key.instanceId, route),
        ),
      );
      final settings = ref.read(currentSettingsProvider);
      final instance = settings.instanceById(key.instanceId);
      if (instance == null) {
        return _offlineSummary(key.service, host: '');
      }
      // Away from home, a connection reached only there is not asked: the
      // route already says what a timeout would, and silence it could not
      // have broken is not red.
      if (instance.away == null &&
          instance.isConfigured &&
          ref.watch(awayFromHomeProvider)) {
        return ServiceSummary(
          service: key.service,
          status: ServiceSummaryStatus.onlyAtHome,
          host: key.service.extractHost(instance.url) ?? '',
          version: null,
          failure: const ClassifiedFailure(ServiceFailureReason.onlyAtHome),
        );
      }
      // Neither address answered the route probe's last knock: a silence
      // here is said of both. Watched only for a connection with an address
      // away, and before the probe's first await.
      final unanswered = instance.away == null
          ? null
          : ref.watch(unansweredConnectionProvider(key.instanceId));
      final summary = await _loadServiceSummary(ref, instance, settings, (
        url: reached.url,
        access: reached.access,
        pin: reached.certFingerprint,
      ));
      return unanswered != null &&
              summary.failureReason == ServiceFailureReason.unreachable
          ? ServiceSummary.failed(
              key.service,
              host: summary.host,
              error: unanswered,
            )
          : summary;
    });

/// The health of the connection [service] is currently seen through.
///
/// Delegates rather than probing: a screen asking "is Prowlarr up" means the
/// Prowlarr it is reading, which is the lens's, not whichever happens to be
/// first. Two dozen call sites keep their shape and quietly become lens-aware.
final serviceSummaryProvider =
    FutureProvider.family<ServiceSummary, ServiceKey>((ref, service) async {
      final instance = ref.watch(activeInstanceProvider(service));
      if (instance == null) {
        return _offlineSummary(
          service,
          host:
              service.extractHost(
                ref.read(currentSettingsProvider).urlFor(service),
              ) ??
              '',
        );
      }
      return ref.watch(
        instanceSummaryProvider((
          service: service,
          instanceId: instance.id,
        )).future,
      );
    });

/// What a download client's page bands over its rows: the probe's failure,
/// or, while the probe has not said so yet, the failure of the [list] the page
/// polls, over rows already read. The list is read every three seconds and the
/// probe's own deadline is longer: without this a stopped client's sections
/// each said their list was not shown, and the rows read before went with
/// them.
ServiceSummary? clientPageFailure(
  ServiceKey service, {
  required AsyncValue<ServiceSummary> summary,
  required AsyncValue<Object?> list,
}) {
  final probed = summary.whenOrNull(data: (s) => s.isOnline ? null : s);
  if (probed != null) return probed;
  if (!list.hasError || !list.hasValue) return null;
  return ServiceSummary.failed(
    service,
    host: summary.whenOrNull(data: (s) => s.host) ?? '',
    error: list.error!,
  );
}

/// Probes [service]'s lens connection again for a page's poll tick, unless
/// the last probe is still out. [serviceSummaryProvider] only delegates, so
/// reading it again rereads the probe's last answer; this asks the server.
void readProbeAgainUnlessInFlight(Ref ref, ServiceKey service) {
  final instance = ref.read(activeInstanceProvider(service));
  if (instance == null) return;
  ref.readAgainUnlessInFlight([
    instanceSummaryProvider((service: service, instanceId: instance.id)),
  ]);
}

/// Everything a status probe reads about one service, as a single comparable
/// value.
///
/// A record, so `select` gets structural equality for free. The password is not
/// a separate field on purpose: `SettingsModel.passwordFor` *is* `apiKeyFor` for
/// the credential-authenticated services, so [apiKey] already covers it. The
/// address, its pin and its access are the route's ([reachOf]): every read
/// and every poster built from this goes where the connection answers now.
typedef _ServiceConnection = ({
  bool configured,
  String url,
  String apiKey,
  String username,
  String? certFingerprint,
  ConnectionAccess access,

  /// A Seerr account's session: signing in again probes again.
  String session,
});

/// One configured connection a merged Home region reads, and what its rows
/// and its coverage are stamped with.
///
/// [name] is the connection's name by the app's one rule, null while its
/// service has a single connection; [connection] is what the reads need of it
/// (the poster URLs carry its address and key).
typedef MergeConnection = ({
  ServiceKey service,
  String instanceId,
  String? name,
  bool isLens,
  _ServiceConnection connection,
});

/// Every configured connection of [service], in the user's order, for a
/// region that reads them all.
///
/// Home folds every connection of a service, the way its header does: a
/// stall, a failed import or a request on the second Radarr is the user's as
/// much as one on the first. Each connection is watched on its own narrow
/// key, so editing one re-reads it and a theme toggle re-reads nothing. The
/// lens is watched too, because which connection the shared lens providers
/// stand for moves with it.
List<MergeConnection> watchMergeConnections(Ref ref, ServiceKey service) {
  final ids = ref.watch(serviceInstanceIdsProvider(service));
  final lens = ref.watch(activeInstanceProvider(service))?.id ?? '';
  final merged = <MergeConnection>[];
  for (final id in ids) {
    final route = ref.watch(connectionRouteProvider(id));
    final connection = ref.watch(
      currentSettingsProvider.select(
        (s) => _connectionOfInstance(s, id, route),
      ),
    );
    if (!connection.configured) continue;
    merged.add((
      service: service,
      instanceId: id,
      name: ref.watch(connectionNameProvider(id)),
      isLens: id == lens,
      connection: connection,
    ));
  }
  return merged;
}

_ServiceConnection _connectionOfInstance(
  SettingsModel settings,
  String instanceId,
  ConnectionRoute route,
) {
  final instance = settings.instanceById(instanceId);
  if (instance == null) {
    return (
      configured: false,
      url: '',
      apiKey: '',
      username: '',
      certFingerprint: null,
      access: const NoAccess(),
      session: '',
    );
  }
  final reach = reachOf(settings, instance, route);
  return (
    configured: instance.isConfigured,
    url: reach.url,
    apiKey: instance.credential,
    username: instance.username,
    certFingerprint: reach.pin,
    access: reach.access,
    session: instance.account?.session ?? '',
  );
}

typedef ServiceStatusClientFactory =
    ApiClient Function({
      required String baseUrl,
      required String apiKey,
      String? pinnedCertFingerprint,
      Map<String, String> accessHeaders,
    });

final serviceStatusClientFactoryProvider = Provider<ServiceStatusClientFactory>(
  (ref) =>
      ({
        required String baseUrl,
        required String apiKey,
        String? pinnedCertFingerprint,
        Map<String, String> accessHeaders = const {},
      }) => ApiClient(
        baseUrl: baseUrl,
        apiKey: apiKey,
        pinnedCertFingerprint: pinnedCertFingerprint,
        accessHeaders: accessHeaders,
      ),
);

/// [reach] is where the connection is asked: the address its route is on,
/// with that address's access and pin. The host the summary names stays the
/// connection's own address, the one it is known by.
Future<ServiceSummary> _loadServiceSummary(
  Ref ref,
  ServiceInstance instance,
  SettingsModel settings,
  ConnectionReach reach,
) async {
  final service = instance.service;
  final host = service.extractHost(instance.url) ?? '';
  // The connection this probe is about, by the instance it was built for and
  // never "the active one" read again later, and the clock it will note
  // into, taken now: a probe invalidated while its request is in flight is
  // disposed by the time the answer lands, and a disposed `ref` can no longer
  // be read. The answer is still an answer, and is still noted.
  final silence = ref.read(silenceClockProvider);
  final silenceOf = silenceKey(service, instance.id);
  final hostReach = ref.read(hostReachProvider);
  if (!instance.isConfigured) {
    // Nothing is asked of a connection that is not set up, so nothing
    // answered and nothing was silent: a silence kept from before it was
    // emptied is not this connection's any more.
    silence.noteAnswered(silenceOf);
    // Signed out is not a dark box: nothing was asked, and the one step left
    // is the person's own. Read as the ended session, blue.
    if (instance.isSignedOut) {
      return ServiceSummary.failed(
        service,
        host: host,
        error: const SeerrSessionEnded(),
      );
    }
    // Nor is a secret this device would not hand over: nothing was asked,
    // and it says what happened here, amber, never `did not answer`.
    if (instance.unreadSecret != null) {
      return ServiceSummary.failed(
        service,
        host: host,
        error: const ClassifiedFailure(ServiceFailureReason.secretUnread),
      );
    }
    // Saved without its key: not asked, so not silent either. Read as
    // `did not answer`, it put a connection nobody had asked into the
    // Stack's count of the dark ones.
    return ServiceSummary(
      service: service,
      status: ServiceSummaryStatus.notSetUp,
      host: host,
      version: null,
    );
  }

  final String? version;
  try {
    version = await _loadVersion(ref, settings, instance, reach);
  } catch (error) {
    // Classified, never flattened: a refused key is the service answering, and
    // painting it with the same red as a box that is switched off sent people
    // to check a cable when the fix was the key in the form.
    //
    // The probe's own deadline passed: a host that is not there, or a server
    // that took the connection and never replied, which is a fault of the
    // server and amber, as the reads say it (13/10). One connection tells
    // them apart.
    final stuck =
        error is TimeoutException &&
        await hostReach(Uri.tryParse(reach.url) ?? Uri());
    final failed = ServiceSummary.failed(
      service,
      host: host,
      error: stuck
          ? const ClassifiedFailure(ServiceFailureReason.timeout)
          : error,
    );
    // The one place the app asks whether a server answers, so the one place
    // that notes since when it did not. A client closed under the probe by a
    // settings change asked nobody, and notes nothing.
    if (!isClosedClientFailure(error)) {
      silence.noteProbe(silenceOf, failed.failureReason);
    }
    return failed;
  }

  silence.noteAnswered(silenceOf);
  return ServiceSummary(
    service: service,
    status: ServiceSummaryStatus.online,
    host: host,
    version: version,
  );
}

ServiceSummary _offlineSummary(ServiceKey service, {required String host}) {
  return ServiceSummary(
    service: service,
    status: ServiceSummaryStatus.offline,
    host: host,
    version: null,
  );
}

Future<String?> _loadVersion(
  Ref ref,
  SettingsModel settings,
  ServiceInstance instance,
  ConnectionReach reach,
) async {
  final service = instance.service;
  if (service == ServiceKey.qbittorrent) {
    // The connection's own client, never a throwaway one. A probe that built
    // its own sent the login again on every refresh, so with a wrong password
    // each pull counted toward qBittorrent's ban of the address. The shared
    // client holds a refused sign-in until the credentials change or a user's
    // Retry lifts it, and it is not this probe's to close.
    final client = ref.watch(qbittorrentClientForProvider(instance.id));
    // Login-then-version is two hops on a cold client, so this gets the same
    // headroom as Transmission's 409 handshake pair.
    return _versionOrNull(
      client.getVersion,
      timeout: const Duration(seconds: 8),
      close: () {},
    );
  }

  // The two long-lived clients, and the two that used to lie. Their providers
  // are built from the flat projections (the FIRST instance of the service),
  // so probing the second connection through them asked the first one whether
  // it was up and painted the answer on the second one's cell: a box that was
  // switched off reading green, and `foldedServiceHealthProvider` counting zero
  // offline. The branches below build a throwaway client from `instance`,
  // which is what makes a per-connection probe per-connection; these two now
  // do the same, and close it either way like the rest. (qBittorrent, above,
  // and the three download clients below read their connection's own client,
  // which is per connection too.)
  if (service == ServiceKey.truenas) {
    final client = TrueNasWsClient(
      baseUrl: reach.url,
      apiKey: instance.credential,
      certFingerprint: reach.pin,
      accessHeaders: reach.access.headers(),
    );
    return _versionOrNull(
      () async => (await TrueNasService(client).getSystemInfo()).version ?? '',
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  if (service == ServiceKey.dockge) {
    final client = DockgeClient(
      baseUrl: reach.url,
      username: instance.username.isEmpty ? null : instance.username,
      password: instance.credential.isEmpty ? null : instance.credential,
      certFingerprint: reach.pin,
      accessHeaders: reach.access.headers(),
    );
    return _versionOrNull(
      () async => await DockgeService(client).fetchVersion() ?? '',
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  if (service == ServiceKey.sabnzbd) {
    // The connection's own client, as qBittorrent's probe reads: the Queue
    // page asks this every three seconds, and a client built for each ask was
    // a new `Dio` and a new TLS handshake each time. Its address, access and
    // pin are the route's, from `watchTransport`, so a route that moves
    // rebuilds the client and this probe with it. Not this probe's to close.
    final client = ref.watch(sabnzbdClientForProvider(instance.id));
    // Keyed, not `mode=version`: that one needs no key, and a probe that
    // cannot see a wrong key paints it as answering. Two hops, hence the room.
    return _versionOrNull(
      client.checkKeyAndVersion,
      timeout: const Duration(seconds: 6),
      close: () {},
    );
  }

  // The media servers, through their own clients: each authenticates with
  // a header the shared `ApiClient` does not send, and each one's status route
  // is anonymous, so the generic branch below read any token as answering.
  if (service == ServiceKey.jellyfin || service == ServiceKey.emby) {
    final MediaBrowserClient client = service == ServiceKey.emby
        ? EmbyClient(
            baseUrl: reach.url,
            apiKey: instance.credential,
            pinnedCertFingerprint: reach.pin,
            accessHeaders: reach.access.headers(),
          )
        : JellyfinClient(
            baseUrl: reach.url,
            apiKey: instance.credential,
            pinnedCertFingerprint: reach.pin,
            accessHeaders: reach.access.headers(),
          );
    return _versionOrNull(
      () async => await client.checkCredentialAndVersion() ?? '',
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  if (service == ServiceKey.plex) {
    final client = PlexClient(
      url: reach.url,
      token: instance.credential,
      clientIdentifier: settings.plexClientId,
      pinnedCertFingerprint: reach.pin,
      accessHeaders: reach.access.headers(),
    );
    return _versionOrNull(
      () async => await client.checkCredentialAndVersion() ?? '',
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  // Past both arms above, so none is left: a media server on the generic
  // branch below would be read as answering whatever key it is given.
  assert(!service.isMediaServer, '${service.name} has no credential probe');

  if (service == ServiceKey.nzbget) {
    // The connection's own client, for the reason SABnzbd's is.
    final client = ref.watch(nzbgetClientForProvider(instance.id));
    return _versionOrNull(
      client.version,
      timeout: const Duration(seconds: 5),
      close: () {},
    );
  }

  if (service == ServiceKey.transmission) {
    // The connection's own client, for the reason SABnzbd's is, and for one
    // more: it keeps the session id the 409 handshake taught it, and a 401
    // it was refused with, so a wrong password is asked once and not on every
    // tick of the page's poll (the daemon's anti-brute-force counts them).
    final client = ref.watch(transmissionClientForProvider(instance.id));
    // Two hops on a cold client: the 409 handshake, then the real call, so
    // this gets the same headroom as qBittorrent's login-then-version pair.
    return _versionOrNull(
      client.version,
      timeout: const Duration(seconds: 8),
      close: () {},
    );
  }

  if (service == ServiceKey.nginxProxyManager) {
    final client = NpmClient(
      url: reach.url,
      identity: instance.username.isEmpty ? null : instance.username,
      secret: instance.credential.isEmpty ? null : instance.credential,
      certFingerprint: reach.pin,
      accessHeaders: reach.access.headers(),
    );
    // `GET /api/` is unauthenticated, so on its own it read a wrong password
    // as answering. The token exchange is what proves the account, and it is
    // paid once per probe: this provider is keyed on the connection's own
    // fields, so it re-runs when this connection changes or is re-checked, not
    // on every settings write.
    return _versionOrNull(
      client.checkCredentialAndVersion,
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  if (service == ServiceKey.unraid) {
    final client = UnraidClient(
      url: reach.url,
      apiKey: instance.credential,
      certFingerprint: reach.pin,
      accessHeaders: reach.access.headers(),
    );
    return _versionOrNull(
      client.version,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  final url = reach.url;
  if (service == ServiceKey.seerr) {
    // Seerr's own client: the key or the account's session, never a client
    // that knows only the key.
    final client = ref.watch(seerrClientFactoryProvider)(
      instance,
      reach: reach,
      // A session the probe finds ended is emptied, as any request's is.
      events: seerrAccountEvents(ref, instance.id),
    );
    try {
      // Seerr's status endpoint is public. Probe one authenticated request
      // first, otherwise a wrong API key paints the dashboard green while
      // Activity and Overview fail with 403 later.
      await SeerrService(
        client,
      ).testConnection().timeout(const Duration(seconds: 5));
      return await readServiceStatus(client, service, url: url);
    } finally {
      client.close();
    }
  }

  final createClient = ref.watch(serviceStatusClientFactoryProvider);
  final client = createClient(
    baseUrl: url,
    apiKey: instance.credential,
    pinnedCertFingerprint: reach.pin,
    accessHeaders: reach.access.headers(),
  );

  try {
    // Who answered, not only that something did: the reading the connection
    // test shares, so Home and Settings name the same answer.
    return await readServiceStatus(client, service, url: url);
  } finally {
    client.close();
  }
}

/// The envelope the per-client version reads share: one call under this
/// service's own deadline, an empty string reported as no version at all, and
/// the client closed whichever way it went.
///
/// Nothing is caught here, on purpose. A throw is what tells
/// [_loadServiceSummary] the service is offline, so swallowing it would report
/// an unreachable box as online with a blank version. The qBittorrent branch
/// used to do exactly that: it caught everything and returned null, so a
/// refusing or unreachable qBittorrent still showed ONLINE while the other five
/// clients reported offline. All six now share this envelope.
///
/// [close] is a `FutureOr` so a client with an asynchronous shutdown could share
/// this path without the synchronous Dio ones changing shape.
Future<String?> _versionOrNull(
  Future<String> Function() read, {
  required Duration timeout,
  required FutureOr<void> Function() close,
}) async {
  try {
    final version = await read().timeout(timeout);
    return version.isNotEmpty ? version : null;
  } finally {
    final closing = close();
    if (closing is Future) await closing;
  }
}
