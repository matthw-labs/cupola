import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Who the app is for on this device: the person who runs the stack, or a
/// household member who asks it for movies and series.
///
/// Never asked: it follows from what is set up. A requester's app has no
/// control room, no service names and no operator's controls; the operator's
/// app is the one there has always been.
enum Audience { operator, requester }

/// One saved connection, as [audienceOf] reads it: its service, and for Seerr
/// what the connection may do (`null` reads as the API key).
typedef AudienceConnection = ({ServiceKey service, SeerrGrant? seerr});

/// Who the app is for, given every saved connection.
///
/// **Requester** when at least one Seerr connection is an account whose role
/// is requester, and every other connection is one of these: another
/// requester's Seerr account, Jellyfin, Plex, or Emby. The three players are the
/// ones a household member watches with; they decide nothing for the household.
///
/// **Operator** in every other case: a Seerr API key, a Seerr account that
/// manages requests, any other service at all, or no Seerr.
///
/// Read from the saved permissions, so it is right on the first frame. Pass
/// a signed-out account too: signing out does not make anyone the operator.
///
/// Jellyfin, Plex and Emby stay neutral whatever their credential is. Whether a
/// Jellyfin or Emby token is an admin's is known only after a probe, and who the app
/// is for cannot wait on one. A requester's Seerr account beside an admin
/// Jellyfin key is still a requester: accepted.
Audience audienceOf(Iterable<AudienceConnection> connections) {
  var requester = false;
  for (final connection in connections) {
    switch (connection.service) {
      case ServiceKey.seerr:
        final grant = connection.seerr ?? const SeerrGrant.apiKey();
        if (grant.isApiKey || grant.role == SeerrRole.manager) {
          return Audience.operator;
        }
        requester = true;
      case ServiceKey.jellyfin || ServiceKey.plex || ServiceKey.emby:
        continue;
      case ServiceKey.radarr ||
          ServiceKey.sonarr ||
          ServiceKey.lidarr ||
          ServiceKey.qbittorrent ||
          ServiceKey.transmission ||
          ServiceKey.bazarr ||
          ServiceKey.truenas ||
          ServiceKey.dockge ||
          ServiceKey.prowlarr ||
          ServiceKey.readarr ||
          ServiceKey.sabnzbd ||
          ServiceKey.nzbget ||
          ServiceKey.unraid ||
          ServiceKey.nginxProxyManager:
        return Audience.operator;
    }
  }
  return requester ? Audience.requester : Audience.operator;
}
