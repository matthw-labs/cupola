import 'package:dio/dio.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Who answered a probe: the service configured, another service of the
/// stack, or something that is not the service at all.
///
/// A 2xx says that *something* answered at the address. Before this, that was
/// the whole of what the probe asked, so a Sonarr reached on Radarr's port, or
/// a proxy's page at an address missing its base path, read as Radarr
/// answering. [identifyProbeAnswer] reads the body the probe already has.
sealed class ProbeIdentity {
  const ProbeIdentity();

  /// The service configured answered.
  static const matches = ProbeMatches._();

  /// Something answered, and it is not the service configured, nor any other
  /// service Cupola knows.
  static const notThisService = ProbeNotThisService._();

  /// Another service of the stack answered at this address: a wrong port.
  const factory ProbeIdentity.otherService(ServiceKey service) =
      ProbeOtherService;
}

/// See [ProbeIdentity.matches].
final class ProbeMatches extends ProbeIdentity {
  const ProbeMatches._();
}

/// See [ProbeIdentity.otherService].
final class ProbeOtherService extends ProbeIdentity {
  const ProbeOtherService(this.service);

  /// The service that answered instead.
  final ServiceKey service;
}

/// See [ProbeIdentity.notThisService].
final class ProbeNotThisService extends ProbeIdentity {
  const ProbeNotThisService._();
}

/// Who answered [service]'s probe, read from [body]: the decoded answer of
/// its status route, or the text qBittorrent answers with.
///
/// **Never fail a genuine service.** Only a positive mismatch is flagged: an
/// arr whose `appName` names another arr is that arr, a body that is not the
/// service's shape at all is not the service. A field that is merely absent
/// in a body that otherwise has the service's shape (an older version, a
/// build that does not send it) gets the benefit of the doubt.
///
/// An exhaustive switch, so a new service declares how it is recognised.
/// The fields are the ones the clients already parse:
///
///  * Radarr, Sonarr, Lidarr, Readarr, Prowlarr: `system/status` carries
///    `appName` (`Radarr`, `Sonarr`, …) beside `version`.
///  * Seerr: `/api/v1/status` carries `version` and `commitTag`.
///  * Bazarr: `/api/system/status` nests everything under `data`, with
///    `bazarr_version`.
///  * Jellyfin and Emby: `/System/Info` and `/System/Info/Public` of the two
///    look alike (Jellyfin forked Emby) and are told apart by what each does
///    not share. Jellyfin sends `ProductName` (`Jellyfin Server`) and a single
///    `LocalAddress`; Emby 4.10 sends no `ProductName` and a `LocalAddresses`
///    list (and `HardwareAccelerationRequiresPremiere` on `/System/Info`).
///  * Tracearr: `/health` answers with the health of its own parts (`db`,
///    `redis`, and a `timescale` object on a recent one) and a `status` that
///    is `ok`, `degraded` or `maintenance`, and `/api/v1/public/health` with
///    `status: ok` and a `version`. Either shape is Tracearr; a `status`
///    alone is not, since half the services of the stack answer one.
///  * Plex: `/identity` and `/` are a `MediaContainer`.
///  * SABnzbd: `mode=version` answers `{"version": …}`.
///  * qBittorrent: `/api/v2/app/version` is text, `v` and a digit.
///  * Nginx Proxy Manager: `GET /api/` answers `{"status": "OK", "version"}`.
///  * NZBGet, Transmission, Unraid: the envelope is the proof (JSON-RPC's
///    `result` or `error`, Transmission's `result`, GraphQL's `data` or
///    `errors`); their clients already refuse any other envelope as the API
///    not being at the address.
///  * TrueNAS, Dockge: the WebSocket handshake and its framing are the proof,
///    so whatever their clients accepted is them.
ProbeIdentity identifyProbeAnswer(ServiceKey service, Object? body) {
  // An arr answering at another service's address says so by name, whatever
  // that service's own shape is.
  final named = _stackServiceNamedIn(body);
  if (named != null && named != service) {
    return ProbeIdentity.otherService(named);
  }
  return switch (service) {
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.readarr ||
    ServiceKey.prowlarr => _arr(service, body),
    ServiceKey.seerr => _hasAny(body, const ['version', 'commitTag']),
    ServiceKey.bazarr => _bazarr(body),
    ServiceKey.jellyfin => _jellyfin(body),
    ServiceKey.emby => _emby(body),
    ServiceKey.tracearr => _tracearr(body),
    ServiceKey.plex => _hasMap(body, 'MediaContainer'),
    ServiceKey.sabnzbd => _hasAny(body, const ['version']),
    ServiceKey.qbittorrent => _qbittorrent(body),
    ServiceKey.nginxProxyManager => _hasAny(body, const ['status', 'version']),
    ServiceKey.nzbget => _hasAny(body, const ['result', 'error']),
    ServiceKey.transmission => _hasAny(body, const ['result']),
    ServiceKey.unraid => _hasAny(body, const ['data', 'errors']),
    ServiceKey.truenas || ServiceKey.dockge => ProbeIdentity.matches,
  };
}

/// The path a service conventionally sits under behind a reverse proxy, for
/// the hint under "it isn't Radarr", or null for one that is not put under a
/// path (it has none to offer, or its address field takes another form).
String? conventionalBasePath(ServiceKey service) => switch (service) {
  ServiceKey.radarr => 'radarr',
  ServiceKey.sonarr => 'sonarr',
  ServiceKey.lidarr => 'lidarr',
  ServiceKey.readarr => 'readarr',
  ServiceKey.prowlarr => 'prowlarr',
  ServiceKey.bazarr => 'bazarr',
  ServiceKey.seerr => 'seerr',
  ServiceKey.jellyfin => 'jellyfin',
  ServiceKey.qbittorrent => 'qbittorrent',
  ServiceKey.sabnzbd => 'sabnzbd',
  ServiceKey.nzbget => 'nzbget',
  ServiceKey.tracearr => 'tracearr',
  // Emby's `/emby` is the API's own prefix, which its client adds, and not a
  // path to put in front of the address. Plex and Nginx Proxy Manager do not
  // run under a path; Transmission's
  // address already takes its RPC path; the three consoles are reached at
  // their own host.
  ServiceKey.plex ||
  ServiceKey.emby ||
  ServiceKey.nginxProxyManager ||
  ServiceKey.transmission ||
  ServiceKey.truenas ||
  ServiceKey.dockge ||
  ServiceKey.unraid => null,
};

/// The probe of [service] at [url] reached something else: another service
/// of the stack, or something that is not the service.
///
/// [ServiceFailureReason.notFound], which is what the vocabulary already
/// calls a base URL pointing at the wrong app, so the headline, the tone and
/// the remedy (`Check the address`) are the ones a wrong address always had,
/// and the sentence ([failureDetail]) says who answered.
class WrongServiceAnswer
    implements Exception, HasFailureReason, HasFailureDetail {
  /// [identity] is never [ProbeIdentity.matches].
  WrongServiceAnswer(this.expected, ProbeIdentity identity, {required this.url})
    : answered = switch (identity) {
        ProbeOtherService(:final service) => service,
        _ => null,
      },
      assert(identity is! ProbeMatches);

  /// The service configured at [url].
  final ServiceKey expected;

  /// The service that answered instead, or null for something that is not a
  /// service Cupola knows.
  final ServiceKey? answered;

  /// The configured address.
  final String url;

  @override
  ServiceFailureReason get reason => ServiceFailureReason.notFound;

  @override
  String get failureDetail {
    final host = expected.extractHost(url) ?? url;
    final other = answered;
    if (other != null) {
      return '${other.title} answered at $host, not ${expected.title}.';
    }
    final sentence =
        "Something answered at $host, but it isn't ${expected.title}.";
    final hint = basePathHint(expected, url);
    return hint == null ? sentence : '$sentence\n$hint';
  }

  @override
  String toString() =>
      'WrongServiceAnswer(${expected.name}, '
      '${answered?.name ?? 'notThisService'})';
}

/// The [WrongServiceAnswer] [error] carries, or null: directly, inside the
/// [DioException] an interceptor rejected with, or under a client's own
/// exception ([HasFailureCause]); found wherever [accessGatewayOf] looks.
WrongServiceAnswer? wrongServiceAnswerOf(Object? error) {
  Object? current = unwrapFailure(error);
  for (var depth = 0; depth < 4 && current != null; depth++) {
    switch (current) {
      case final WrongServiceAnswer wrong:
        return wrong;
      case final DioException dio:
        current = dio.error;
      case final HasFailureCause wrapper:
        current = wrapper.failureCause;
      default:
        return null;
    }
  }
  return null;
}

/// Throws unless [body] is [service]'s own answer. See [identifyProbeAnswer].
///
/// A web page read as text (the clients that ask for no JSON get one as a
/// string) throws the same [UnexpectedAnswer] a JSON client meets, so it
/// reads the same everywhere ([webPageSentence]). Anything else that is not
/// the service throws [WrongServiceAnswer].
void requireProbeIdentity(
  ServiceKey service,
  Object? body, {
  required String url,
}) {
  final identity = identifyProbeAnswer(service, body);
  if (identity is ProbeMatches) return;
  if (body is String) {
    final page = UnexpectedAnswer(
      body: body,
      host: service.extractHost(url),
      baseUrl: url,
    );
    if (page.isWebPage) throw page;
  }
  throw WrongServiceAnswer(service, identity, url: url);
}

/// What a web page answering in [service]'s place says, wherever it met the
/// request (the probe, the connection test, a library read): `A web page
/// answered at radarr.example.com instead of Radarr.`, and under it the path
/// hint when the address has no path ([basePathHint]).
///
/// The sentence under `Radarr is not at this address` (the web page's reason
/// is [ServiceFailureReason.notFound]), with `Check the address` as its remedy.
String webPageSentence(ServiceKey service, UnexpectedAnswer page) {
  final host = page.host;
  final where = host == null || host.isEmpty ? '' : ' at $host';
  final sentence = 'A web page answered$where instead of ${service.title}.';
  final url = page.baseUrl;
  final hint = url == null ? null : basePathHint(service, url);
  return hint == null ? sentence : '$sentence\n$hint';
}

/// "If Radarr sits under a path, add it: https://example.com/radarr", when
/// the configured address [url] has no path to be missing one; null when it
/// has one, or [service] is not put under a path.
String? basePathHint(ServiceKey service, String url) {
  final slug = conventionalBasePath(service);
  if (slug == null) return null;
  final normalized = UrlUtils.normalizeBaseUrl(url);
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  final origin = uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
  return 'If ${service.title} sits under a path, add it: $origin/$slug';
}

ProbeIdentity _arr(ServiceKey service, Object? body) {
  if (body is! Map) return ProbeIdentity.notThisService;
  final appName = body['appName'];
  if (appName is String && appName.trim().isNotEmpty) {
    // Named, and not a service of the stack (a Whisparr, a fork): not this.
    return appName.trim().toLowerCase() == service.title.toLowerCase()
        ? ProbeIdentity.matches
        : ProbeIdentity.notThisService;
  }
  return _hasAny(body, const ['version']);
}

ProbeIdentity _bazarr(Object? body) {
  if (body is! Map) return ProbeIdentity.notThisService;
  return body['data'] is Map
      ? ProbeIdentity.matches
      : ProbeIdentity.notThisService;
}

/// Jellyfin names itself in `ProductName`, and the field decides when it is
/// there. Without it, Emby's shape ([_looksLikeEmby]) is another service, and
/// a body that is neither gets the benefit of the doubt, as it always had.
ProbeIdentity _jellyfin(Object? body) {
  if (body is! Map) return ProbeIdentity.notThisService;
  final product = body['ProductName'];
  if (product is String && product.trim().isNotEmpty) {
    final name = product.toLowerCase();
    if (name.contains('jellyfin')) return ProbeIdentity.matches;
    // A build or a proxy that does say it is Emby.
    return name.contains('emby')
        ? ProbeIdentity.otherService(ServiceKey.emby)
        : ProbeIdentity.notThisService;
  }
  if (_looksLikeEmby(body)) return ProbeIdentity.otherService(ServiceKey.emby);
  return _hasAny(body, const ['Version', 'Id', 'ServerName']);
}

/// Emby sends no `ProductName` (4.10 does not, whatever the first reading of
/// its API assumed), so it is recognised by the shape it does have: a
/// `LocalAddresses` **list** (Jellyfin's is the single `LocalAddress`), and
/// `HardwareAccelerationRequiresPremiere` on `/System/Info`.
///
/// An empty list still counts: a server with no address of its own to
/// advertise is the common case, and the key is the proof.
ProbeIdentity _emby(Object? body) {
  if (body is! Map) return ProbeIdentity.notThisService;
  final product = body['ProductName'];
  if (product is String && product.trim().isNotEmpty) {
    final name = product.toLowerCase();
    if (name.contains('emby')) return ProbeIdentity.matches;
    return name.contains('jellyfin')
        ? ProbeIdentity.otherService(ServiceKey.jellyfin)
        : ProbeIdentity.notThisService;
  }
  // Without a name, Jellyfin's own fields are the other way to know: a body
  // with its single `LocalAddress` or its wizard flag is not Emby's.
  if (!_looksLikeEmby(body) &&
      (body.containsKey('LocalAddress') ||
          body.containsKey('StartupWizardCompleted'))) {
    return ProbeIdentity.otherService(ServiceKey.jellyfin);
  }
  return _hasAny(body, const ['Version', 'Id', 'ServerName']);
}

/// Tracearr's two health answers, the keyless `/health` and the public API's.
///
/// A `status` alone proves nothing (Nginx Proxy Manager and the arrs say
/// `OK`). What does is the health of Tracearr's own parts. The keyless route
/// answers HTTP 200 with `degraded` when the database or Redis is down and
/// `maintenance` (no `timescale`) while it starts or restores, so there any
/// string status counts: a down Tracearr is still Tracearr. The authenticated
/// public shape carries no parts, so it keeps `ok` and a `version` as proof.
ProbeIdentity _tracearr(Object? body) {
  if (body is! Map) return ProbeIdentity.notThisService;
  final ownParts =
      body['timescale'] is Map || (body['db'] is bool && body['redis'] is bool);
  if (ownParts) {
    return body['status'] is String
        ? ProbeIdentity.matches
        : ProbeIdentity.notThisService;
  }
  return body['status'] == 'ok' && body['version'] is String
      ? ProbeIdentity.matches
      : ProbeIdentity.notThisService;
}

bool _looksLikeEmby(Map<Object?, Object?> body) =>
    body['LocalAddresses'] is List ||
    body.containsKey('HardwareAccelerationRequiresPremiere');

ProbeIdentity _qbittorrent(Object? body) {
  if (body is! String) return ProbeIdentity.notThisService;
  final text = body.trim();
  if (text.isEmpty) return ProbeIdentity.matches;
  return RegExp(r'^v?\d').hasMatch(text)
      ? ProbeIdentity.matches
      : ProbeIdentity.notThisService;
}

ProbeIdentity _hasAny(Object? body, List<String> keys) {
  if (body is! Map) return ProbeIdentity.notThisService;
  return keys.any(body.containsKey)
      ? ProbeIdentity.matches
      : ProbeIdentity.notThisService;
}

ProbeIdentity _hasMap(Object? body, String key) {
  if (body is! Map) return ProbeIdentity.notThisService;
  return body[key] is Map
      ? ProbeIdentity.matches
      : ProbeIdentity.notThisService;
}

/// The service of the stack a body names as its `appName`: the arrs' status
/// routes do, and so a wrong port that lands on one says which.
ServiceKey? _stackServiceNamedIn(Object? body) {
  if (body is! Map) return null;
  final appName = body['appName'];
  if (appName is! String) return null;
  final name = appName.trim().toLowerCase();
  if (name.isEmpty) return null;
  for (final service in ServiceKey.values) {
    if (service.title.toLowerCase() == name) return service;
  }
  return null;
}
