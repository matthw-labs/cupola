import 'package:cupola/features/settings/domain/service_key.dart';

import 'package:cupola/demo/world/config_profile.dart';
import 'package:cupola/demo/world/fake_socket.dart';
import 'package:cupola/demo/world/fakes/arr_fakes.dart';
import 'package:cupola/demo/world/fakes/client_fakes.dart';
import 'package:cupola/demo/world/fakes/infra_fakes.dart';
import 'package:cupola/demo/world/fakes/media_fakes.dart';
import 'package:cupola/demo/world/profile_network.dart';
import 'package:cupola/demo/world/world.dart';
import 'package:cupola/demo/world/world_life.dart';

/// A decoded JSON object, the shape every canned answer is built from.
typedef JsonMap = Map<String, Object?>;

/// What one request needs to know about the server it reached.
class ServerContext {
  ServerContext({required this.network, required this.server});

  final ProfileNetwork network;
  final ProfileServer server;

  ConnectionBehaviour get behaviour => server.behaviour;
  ConfigProfile get profile => network.profile;

  /// What relative times are measured from: the network's fixed moment, or
  /// its clock once the world lives (a world that moves on keeps "2 h ago"
  /// two hours ago).
  DateTime get now => network.life == null ? network.now : network.currentTime;

  /// The world's life, or null when it answers from its profile as written.
  WorldLife? get life => network.life;

  /// Every download, as the world stands now.
  List<WorldDownload> get downloads => life?.downloads ?? profile.downloads;

  /// The usenet clients whose whole queue is paused.
  Set<String> get pausedQueues => life?.pausedQueues ?? profile.pausedQueues;

  /// [age] before [now], as the ISO-8601 UTC string every service here sends.
  String ago(Duration age) => now.subtract(age).toUtc().toIso8601String();

  /// [age] before [now], but never before [now]'s local midnight: a record the
  /// world calls today stays today when the suite runs just after midnight.
  String agoToday(Duration age) {
    final sinceMidnight = now.difference(
      DateTime(now.year, now.month, now.day),
    );
    return ago(age < sinceMidnight ? age : sinceMidnight);
  }

  /// [lead] after [now].
  String ahead(Duration lead) => now.add(lead).toUtc().toIso8601String();
}

/// One service's side of the wire: its canned answers, and the shape each of
/// the behaviours takes for it.
///
/// The refusal shapes are the load-bearing part. A 401 from Radarr, a
/// `200 Fails.` from qBittorrent, `{"status": false, "error": "API Key
/// Incorrect"}` from SABnzbd and a `false` login from TrueNAS are four spellings
/// of one fact, and the app's classifiers are written against each spelling:
/// so each fake answers in its service's own.
abstract class ServiceFake {
  const ServiceFake();

  /// Routes a live server answers with no credential: the status probes that
  /// still say "online" behind a refused key, which is the gap between the
  /// Dashboard's probe and every other screen.
  bool isPublic(NetworkRequest request) => false;

  /// Whether [request] changes something. Most services write with anything
  /// but GET; the RPC-over-POST ones override this.
  bool isWrite(NetworkRequest request) => request.method != 'GET';

  /// Reads a non-admin credential may not make. Only Jellyfin and Plex have a
  /// non-admin token to model; everyone else reads everything or nothing.
  bool isAdminRead(NetworkRequest request) => false;

  /// How this service refuses a credential it does not accept.
  NetworkReply refuseKey(NetworkRequest request) =>
      NetworkReply.json({'message': 'Unauthorized'}, status: 401);

  /// How this service refuses a write the credential may not make.
  NetworkReply refuseWrite(NetworkRequest request) =>
      NetworkReply.json({'message': 'Forbidden'}, status: 403);

  /// The reply the connection's behaviour forces, or null to answer normally.
  ///
  /// [ConnectionBehaviour.didNotAnswer] and [ConnectionBehaviour.timesOut]
  /// never reach here: they fail at dial time, before a request exists.
  NetworkReply? gate(NetworkRequest request, ServerContext context) {
    switch (context.behaviour) {
      case PlainBehaviour.refusesKey:
        return isPublic(request) ? null : refuseKey(request);
      case PlainBehaviour.readOnly:
        if (isWrite(request) || isAdminRead(request)) {
          return refuseWrite(request);
        }
        return null;
      // In front of every route, public ones included: the page is what is
      // at the address, whichever path was asked for.
      case PlainBehaviour.servesHtmlPage:
        return NetworkReply.html(proxyDefaultPage);
      // Answered by the other service's fake, which is the whole behaviour.
      case AnswersAsOtherService():
      // The network answers for a gateway before any service is asked
      // (`gatewayReply`); a request it lets through reaches the service.
      case BehindCloudflareAccess():
      case BehindSignInPage():
      case BehindPasswordPrompt():
      // Seerr's own states, which only its fake reads (`SeerrFake.gate`).
      case SeerrBehaviour():
      case PlainBehaviour.answers:
      case PlainBehaviour.didNotAnswer:
      case PlainBehaviour.timesOut:
      case PlainBehaviour.untrustedTls:
      case PlainBehaviour.plainHttpPort:
      case PlainBehaviour.closesHandshake:
        return null;
    }
  }

  /// The world's canned answer, or null when this fake has none (served 404
  /// and logged in `ProfileNetwork.unanswered`).
  NetworkReply? answer(NetworkRequest request, ServerContext context);

  /// The reply as it leaves the server, whoever wrote it: [gate], a test's
  /// route or [answer]. Seerr adds the cookies its middleware sets on every
  /// answer here. Most services send the reply as it is.
  NetworkReply finish(
    NetworkRequest request,
    ServerContext context,
    NetworkReply reply,
  ) => reply;

  /// The server half of a WebSocket upgrade, for the two services that speak
  /// one. Null refuses the upgrade.
  WebSocketPeer? upgrade(NetworkRequest request, ServerContext context) => null;
}

ServiceFake serviceFakeFor(ServiceKey service) => switch (service) {
  ServiceKey.radarr => const RadarrFake(),
  ServiceKey.sonarr => const SonarrFake(),
  ServiceKey.lidarr => const LidarrFake(),
  ServiceKey.readarr => const ReadarrFake(),
  ServiceKey.prowlarr => const ProwlarrFake(),
  ServiceKey.bazarr => const BazarrFake(),
  ServiceKey.seerr => const SeerrFake(),
  ServiceKey.jellyfin => const JellyfinFake(),
  ServiceKey.plex => const PlexFake(),
  ServiceKey.emby => const EmbyFake(),
  ServiceKey.qbittorrent => const QbittorrentFake(),
  ServiceKey.transmission => const TransmissionFake(),
  ServiceKey.sabnzbd => const SabnzbdFake(),
  ServiceKey.nzbget => const NzbgetFake(),
  ServiceKey.truenas => const TrueNasFake(),
  ServiceKey.dockge => const DockgeFake(),
  ServiceKey.unraid => const UnraidFake(),
  ServiceKey.nginxProxyManager => const NpmFake(),
};

/// Whether [request] is [method] [path] exactly.
bool route(NetworkRequest request, String method, String path) =>
    request.method == method && request.path == path;

/// An arr-style paged envelope over [records], honouring `page`/`pageSize`.
Map<String, Object?> pagedEnvelope(
  NetworkRequest request,
  List<Map<String, Object?>> records,
) {
  final page = int.tryParse(request.query['page'] ?? '') ?? 1;
  final pageSize = int.tryParse(request.query['pageSize'] ?? '') ?? 20;
  final start = ((page - 1) * pageSize).clamp(0, records.length);
  final end = (start + pageSize).clamp(0, records.length);
  return {
    'page': page,
    'pageSize': pageSize,
    'sortKey': 'date',
    'sortDirection': 'descending',
    'totalRecords': records.length,
    'records': records.sublist(start, end),
  };
}
