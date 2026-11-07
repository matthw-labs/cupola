/// Set up next: the services that would add the most to the operator's Home,
/// in one module at its foot.
///
/// One module, never a wall: a Home that lacks four services does not draw
/// four empty modules each asking for one. A module whose service is missing
/// is simply not drawn, and this names the service once, with what it would
/// add, at most [setUpNextLimit] of them, then the whole list.
///
/// Only what is missing and only what adds: each line says what the service
/// brings that the person does not have now, so the order is how much it
/// brings. A Plex stands for Jellyfin (both play and both say who is
/// watching); any one of the four download clients stands for the rest.
///
/// What another connection already knows comes first: a Radarr in Seerr's
/// settings is one tap from joining, its address and key filled in, which no
/// other line can say.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How many services the module names before `All services`.
const setUpNextLimit = 3;

/// One line of Set up next.
typedef SetUpSuggestion = ({
  /// The service to set up, or null for a kind of service ("a download
  /// client"), which leads to the list of every service.
  ServiceKey? service,

  /// `Set up Seerr`.
  String title,

  /// What it adds: `Requests, Discover, ratings and cast`; for a server
  /// another connection knows, where it was heard of: `Seerr knows it · key
  /// found`.
  String line,

  /// The server another connection knows, for a line that adds it rather
  /// than sets a service up from nothing.
  ConnectionCandidate? found,
});

/// What Set up next suggests, given which services have a connection and
/// what other connections know ([found], still to be added): the known
/// servers first, then the services missing, in the order of what each adds.
/// A service a known server stands for is not suggested again from nothing.
/// Empty when nothing is missing: the module is then not drawn.
List<SetUpSuggestion> setUpNextOf(
  bool Function(ServiceKey) isSetUp, {
  List<ConnectionCandidate> found = const [],
}) {
  final known = {for (final candidate in found) candidate.service};
  bool any(List<ServiceKey> services) =>
      services.any((service) => isSetUp(service) || known.contains(service));
  return [
    for (final candidate in found)
      (
        service: candidate.service,
        title: 'Add ${candidate.displayName}',
        line: candidate.knownLine,
        found: candidate,
      ),
    if (!any(const [ServiceKey.seerr]))
      (
        service: ServiceKey.seerr,
        title: Lexicon.setUp(ServiceKey.seerr.title),
        line: 'Requests, Discover, ratings and cast',
        found: null,
      ),
    if (!any(mediaServers))
      (
        service: ServiceKey.jellyfin,
        title: Lexicon.setUp(ServiceKey.jellyfin.title),
        line: 'Play, Continue watching and Now playing',
        found: null,
      ),
    if (!any(const [
      ServiceKey.qbittorrent,
      ServiceKey.transmission,
      ServiceKey.sabnzbd,
      ServiceKey.nzbget,
    ]))
      (
        service: null,
        title: Lexicon.setUp('a download client'),
        line: 'Speeds, and why a download is stuck',
        found: null,
      ),
    if (!any(const [ServiceKey.radarr]))
      (
        service: ServiceKey.radarr,
        title: Lexicon.setUp(ServiceKey.radarr.title),
        line: 'Movies: what arrives, what downloads, what comes out',
        found: null,
      ),
    if (!any(const [ServiceKey.sonarr]))
      (
        service: ServiceKey.sonarr,
        title: Lexicon.setUp(ServiceKey.sonarr.title),
        line: 'Series: new episodes, downloads and air times',
        found: null,
      ),
    if (!any(const [ServiceKey.bazarr]))
      (
        service: ServiceKey.bazarr,
        title: Lexicon.setUp(ServiceKey.bazarr.title),
        line: 'Subtitles on every title page',
        found: null,
      ),
  ];
}
