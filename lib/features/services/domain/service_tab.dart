import 'package:cupola/features/settings/domain/service_key.dart';

/// Every view a service can show, and the word the app uses for it.
///
/// One closed vocabulary rather than a string per surface, because four things
/// have to agree about a tab and they are written in four different files: the
/// bar draws its label, the router mounts its branch, the breadcrumb prints it
/// as the third crumb, and a deep link spells it as a path segment. When those
/// were independent the breadcrumb title-cased whatever segment it found and
/// printed `Vms` and `Rss`, neither of which is how anyone writes them, and
/// neither of which any other surface said.
///
/// [segment] is the URL spelling and [label] the human one; they differ only
/// where English does.
enum ServiceTab {
  overview('overview', 'Overview'),

  // ── Seerr ────────────────────────────────────────────────────────────────
  requests('requests', 'Requests'),
  issues('issues', 'Issues'),
  users('users', 'Users'),

  // ── The \*arr family ──────────────────────────────────────────────────────
  library('library', 'Library'),
  calendar('calendar', 'Calendar'),
  queue('queue', 'Queue'),
  wanted('wanted', 'Wanted'),
  history('history', 'History'),

  // ── Bazarr ───────────────────────────────────────────────────────────────
  series('series', 'Series'),
  movies('movies', 'Movies'),
  providers('providers', 'Providers'),

  // ── Download clients ─────────────────────────────────────────────────────
  rss('rss', 'RSS'),
  labels('labels', 'Labels'),
  session('session', 'Session'),
  servers('servers', 'Servers'),
  feeds('feeds', 'Feeds'),
  messages('messages', 'Messages'),

  // ── Prowlarr ─────────────────────────────────────────────────────────────
  indexers('indexers', 'Indexers'),
  stats('stats', 'Stats'),

  // ── Stream ───────────────────────────────────────────────────────────────
  libraries('libraries', 'Libraries'),
  devices('devices', 'Devices'),
  tasks('tasks', 'Tasks'),
  activity('activity', 'Activity'),
  activities('activities', 'Activities'),
  playlists('playlists', 'Playlists'),

  // ── Tracearr ─────────────────────────────────────────────────────────────
  // Its Users and History are the shared tabs above; these two are its own.
  // `Live`, not Activity: in Cupola Activity is the tab of a media server's
  // sessions, and these are streams in flight with their bandwidth.
  live('live', 'Live'),
  violations('violations', 'Violations'),

  // ── Infrastructure ───────────────────────────────────────────────────────
  stacks('stacks', 'Stacks'),
  terminal('terminal', 'Terminal'),
  array('array', 'Array'),
  docker('docker', 'Docker'),
  vms('vms', 'VMs'),
  notifications('notifications', 'Notifications'),
  shares('shares', 'Shares'),
  proxyHosts('proxy-hosts', 'Proxy hosts'),
  certificates('certificates', 'Certificates'),
  accessLists('access-lists', 'Access lists'),
  auditLog('audit-log', 'Audit log');

  const ServiceTab(this.segment, this.label);

  /// The path segment, e.g. `on-deck` in `/dashboard/plex/on-deck`.
  final String segment;

  /// The word the bar and the breadcrumb print.
  final String label;

  static final Map<String, ServiceTab> _bySegment = {
    for (final tab in values) tab.segment: tab,
  };

  /// Resolves a path segment back to its tab, for the breadcrumb and for a
  /// deep link that names a tab the service does not have.
  static ServiceTab? fromSegment(String segment) => _bySegment[segment];
}

/// The bar, per service, in the order it is drawn.
///
/// Read off the nineteen service home boards. Three rules hold over the whole
/// table and are asserted by its tests rather than left to review:
///
///  * every list starts with [ServiceTab.overview]: opening a service always
///    lands there, and it is the only tab carrying the identity block and the
///    readouts;
///  * at most six entries, because past six the bar stops being a bar;
///  * no duplicates within a service.
///
/// TrueNAS is absent on purpose, and that absence is the contract: ten sections
/// are too many for a bar, so it keeps the console it already has. Everything
/// else in the stack follows the tab model.
const Map<ServiceKey, List<ServiceTab>> serviceTabs = {
  ServiceKey.seerr: [
    ServiceTab.overview,
    ServiceTab.requests,
    ServiceTab.issues,
    ServiceTab.users,
  ],
  ServiceKey.radarr: _arrTabs,
  ServiceKey.sonarr: _arrTabs,
  // Artists and Albums merged into one segmented Library, which is what freed
  // the sixth slot for History (decision 24).
  ServiceKey.lidarr: _arrTabs,
  // Full parity with the other three (decision 13). Upstream being archived
  // makes the v1 API a frozen target, not a moving one.
  ServiceKey.readarr: _arrTabs,
  ServiceKey.bazarr: [
    ServiceTab.overview,
    ServiceTab.wanted,
    ServiceTab.series,
    ServiceTab.movies,
    // History and Blacklist are one tab with a pill, so the cap holds
    // (decision 22).
    ServiceTab.history,
    ServiceTab.providers,
  ],
  ServiceKey.qbittorrent: [
    ServiceTab.overview,
    ServiceTab.queue,
    ServiceTab.rss,
  ],
  ServiceKey.transmission: [
    ServiceTab.overview,
    ServiceTab.queue,
    ServiceTab.labels,
    ServiceTab.session,
  ],
  // Apps is a section of Prowlarr's own Settings page, not a tab
  // (decision 26, bonus rule 2).
  ServiceKey.prowlarr: [
    ServiceTab.overview,
    ServiceTab.indexers,
    ServiceTab.history,
    ServiceTab.stats,
  ],
  // Config likewise moves to that service's Settings page (decision 27).
  ServiceKey.sabnzbd: [
    ServiceTab.overview,
    ServiceTab.queue,
    ServiceTab.history,
    ServiceTab.servers,
  ],
  ServiceKey.nzbget: [
    ServiceTab.overview,
    ServiceTab.queue,
    ServiceTab.history,
    ServiceTab.feeds,
    ServiceTab.messages,
  ],
  ServiceKey.jellyfin: [
    ServiceTab.overview,
    ServiceTab.libraries,
    ServiceTab.users,
    ServiceTab.devices,
    ServiceTab.tasks,
    ServiceTab.activity,
  ],
  // Emby's bar is Jellyfin's, tab for tab: the two servers answer the same
  // administration reads (users, devices, scheduled tasks, sessions).
  ServiceKey.emby: [
    ServiceTab.overview,
    ServiceTab.libraries,
    ServiceTab.users,
    ServiceTab.devices,
    ServiceTab.tasks,
    ServiceTab.activity,
  ],
  // The guardian's room: what is playing, what was played, who, and what broke
  // a rule. Five tabs, in the order a person asks them.
  ServiceKey.tracearr: [
    ServiceTab.overview,
    ServiceTab.live,
    ServiceTab.history,
    ServiceTab.users,
    ServiceTab.violations,
  ],
  // Five tabs: the drawn set (decision 17), with On deck moved into
  // Activities beside who is watching (decision `P-stream-library-browse`).
  ServiceKey.plex: [
    ServiceTab.overview,
    ServiceTab.libraries,
    ServiceTab.activities,
    ServiceTab.devices,
    ServiceTab.playlists,
  ],
  // The agent picker is the app-bar connection lens, not a tab (decision 41).
  ServiceKey.dockge: [
    ServiceTab.overview,
    ServiceTab.stacks,
    ServiceTab.terminal,
  ],
  ServiceKey.unraid: [
    ServiceTab.overview,
    ServiceTab.array,
    ServiceTab.docker,
    ServiceTab.vms,
    ServiceTab.notifications,
    ServiceTab.shares,
  ],
  ServiceKey.nginxProxyManager: [
    ServiceTab.overview,
    ServiceTab.proxyHosts,
    ServiceTab.certificates,
    ServiceTab.accessLists,
    ServiceTab.auditLog,
  ],
};

/// The four \*arr share a bar exactly, which is the point: the same record
/// types in the same order, so a user who learns Radarr has learned Sonarr.
const List<ServiceTab> _arrTabs = [
  ServiceTab.overview,
  ServiceTab.library,
  ServiceTab.calendar,
  ServiceTab.queue,
  ServiceTab.wanted,
  ServiceTab.history,
];

/// The bar for [service], or null where the service does not have one.
///
/// Null is TrueNAS and nothing else, and callers must handle it rather than
/// defaulting to an empty bar: an empty bar is a service whose tabs failed to
/// load, which is a different thing from a console.
List<ServiceTab>? tabsFor(ServiceKey service) => serviceTabs[service];

/// The tab [path] is on, when it is on one of [service]'s.
///
/// Derived from the path, like the breadcrumb and for the same reason: a deep
/// link, a restored window and a cold start all arrive carrying nothing but a
/// location, so anything that reads the selection from state instead would be
/// wrong for the first frame of all three.
///
/// Returns null for a tab the service does not have, rather than the tab: a
/// link naming another service's view is not a place on this one.
ServiceTab? serviceTabOf(ServiceKey service, String path) {
  final segments = Uri.parse(path).pathSegments;
  if (segments.length < 3 || segments[1] != service.routeParam) return null;
  final tab = ServiceTab.fromSegment(segments[2]);
  if (tab == null || !(tabsFor(service)?.contains(tab) ?? false)) return null;
  return tab;
}

/// Whether [path] is a tab's own root rather than a page pushed from it.
///
/// The one question the service shell's app-bar band has to ask. The band is
/// drawn above every branch navigator, so unlike the tab bar (which a pushed
/// page simply covers), it cannot be hidden by the page that wants it gone, and
/// has to hide itself. Two back chevrons in one corner is what this answers.
bool isServiceTabRoot(ServiceKey service, String path) =>
    serviceTabOf(service, path) != null &&
    Uri.parse(path).pathSegments.length == 3;
