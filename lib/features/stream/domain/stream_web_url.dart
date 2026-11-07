import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The media server's own web client, deep-linked to item [itemId], or null
/// when there is no address to build one from: Plex needs its server's
/// [serverId] (its machine id), and a service that is not a media server has no
/// web client to open an item in.
///
/// [serverId] is what the server calls itself: Plex's machine id, Emby's
/// public-info `Id`. Jellyfin's link needs none. Emby's link works without it
/// (the web client knows the server that served it), so a server that did not
/// say stays a working link.
///
/// A web URL rather than an app scheme: neither Jellyfin nor Plex publishes a
/// documented, reliably-registered scheme across iOS, Android and macOS, and a
/// scheme that silently fails is worse than a browser that works. On a phone
/// the installed app usually claims the URL anyway through universal links.
Uri? streamItemWebUrl({
  required ServiceKey service,
  required String baseUrl,
  required String itemId,
  String? serverId,
}) {
  final root = UrlUtils.normalizeBaseUrl(baseUrl);
  if (root.isEmpty) return null;
  if (!service.isMediaServer) return null;
  return switch (service) {
    ServiceKey.jellyfin => Uri.tryParse(
      '$root/web/index.html#!/details?id=$itemId',
    ),
    ServiceKey.plex => _plexWebUrl(root, itemId, serverId),
    // Emby's web client lives under `/web`, not `/emby`: `root` carries no
    // API base path.
    ServiceKey.emby => _embyWebUrl(root, itemId, serverId),
    // Plex's spelling is the one a media server left unnamed here would have
    // been given, and it is wrong for any other: each names its own.
    _ => throw UnimplementedError('${service.name} has no web client link'),
  };
}

Uri? _plexWebUrl(String root, String itemId, String? machineId) {
  if (machineId == null || machineId.isEmpty) return null;
  final key = Uri.encodeComponent('/library/metadata/$itemId');
  return Uri.tryParse(
    '$root/web/index.html#!/server/$machineId/details?key=$key',
  );
}

Uri? _embyWebUrl(String root, String itemId, String? serverId) {
  final id = Uri.encodeQueryComponent(itemId);
  final server = serverId == null || serverId.isEmpty
      ? ''
      : '&serverId=${Uri.encodeQueryComponent(serverId)}';
  return Uri.tryParse('$root/web/index.html#!/item?id=$id$server');
}
