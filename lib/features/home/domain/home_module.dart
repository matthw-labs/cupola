/// The modules the Home is made of, declared once.
///
/// One registry, like `serviceTabs`: every module says whose Home it is on,
/// where it stands by default, whether it starts on, whether the person may
/// hide it, and which services feed it. The Home draws from it, Edit Home lists
/// it, and the saved layout (`HomeLayout`) is read against it, so a module
/// added here reaches a Home that was arranged before it existed at its own
/// default place.
///
/// The enum's names are what a saved layout stores: renaming one drops it from
/// every layout written before, and it comes back at its default place.
library;

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Where a module stands on its Home.
enum HomePlacement {
  /// In the person's order, from its default place.
  ordered,

  /// After every other module, whatever the layout says: Set up next, which
  /// speaks of the Home itself.
  last,
}

/// One module of a Home, in its default order.
///
/// The declaration order is the default order of each person's Home: the
/// operator's modules first, then the requester's. A person reorders and hides
/// their own; nothing else is added.
enum HomeModule {
  /// The fault in the lead, how many more, the way in. First by default, and a
  /// person may move it; it is never hidden, since it is only there when
  /// something is wrong.
  needsYou(
    audience: Audience.operator,
    label: 'Needs you',
    line: 'First by default, and only there when something is wrong',
    hideable: false,
  ),

  /// Up to three slides, moving on by themselves: what somebody was
  /// watching, the newest arrival, what comes out today. The room takes its
  /// light from the slide in front.
  featured(
    audience: Audience.operator,
    label: 'Featured',
    line: 'What you were watching, what is new and what is out today',
    services: [
      ServiceKey.jellyfin,
      ServiceKey.plex,
      ServiceKey.radarr,
      ServiceKey.sonarr,
    ],
  ),

  /// What somebody started and did not finish.
  ///
  /// [services] is spelled out because an enum argument is const; the guard
  /// `test/features/home/domain/home_module_services_test.dart` holds it to
  /// `mediaServers`.
  continueWatching(
    audience: Audience.operator,
    label: 'Continue watching',
    line: 'What you started and did not finish',
    services: [ServiceKey.jellyfin, ServiceKey.plex],
  ),

  /// What comes out or airs from today to three days on.
  comingUp(
    audience: Audience.operator,
    label: 'Coming up',
    line: 'What comes out or airs in the next few days',
    services: [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.readarr,
    ],
  ),

  /// What the libraries gained in the last seven days.
  arrived(
    audience: Audience.operator,
    label: 'Arrived',
    line: 'New in your libraries in the last 7 days',
    services: [ServiceKey.radarr, ServiceKey.sonarr, ServiceKey.lidarr],
  ),

  /// What is moving now.
  downloads(
    audience: Audience.operator,
    label: 'Downloads',
    line: 'What is moving now, from every queue',
    services: [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.readarr,
      ServiceKey.qbittorrent,
      ServiceKey.transmission,
      ServiceKey.sabnzbd,
      ServiceKey.nzbget,
    ],
    needs: 'Needs Radarr, Sonarr or a download client',
  ),

  /// The requests that wait for an answer.
  requests(
    audience: Audience.operator,
    label: 'Requests',
    line: 'Requests waiting for your approval',
    services: [ServiceKey.seerr],
  ),

  /// Who is watching what, and on which screen.
  ///
  /// [services] is spelled out because an enum argument is const; the guard
  /// `test/features/home/domain/home_module_services_test.dart` holds it to
  /// `sessionServices`.
  nowPlaying(
    audience: Audience.operator,
    label: 'Now playing',
    line: 'Who is watching, and on which screen',
    services: [ServiceKey.jellyfin, ServiceKey.plex],
  ),

  /// Every service's light on one slab: the Stack tab, folded. Off until the
  /// person switches it on, since the header already answers.
  stackHealth(
    audience: Audience.operator,
    label: 'Stack health',
    line: 'Every service’s light on one slab',
    defaultOn: false,
  ),

  /// How full the pools are, and whether a disk needs the person.
  storage(
    audience: Audience.operator,
    label: 'Storage',
    line: 'Pools and disks, from TrueNAS or Unraid',
    services: [ServiceKey.truenas, ServiceKey.unraid],
    defaultOn: false,
  ),

  /// One shelf of Discover, with the library's state on every poster.
  discoverShelf(
    audience: Audience.operator,
    label: 'Discover shelf',
    line: 'Trending this week, from Seerr',
    services: [ServiceKey.seerr],
    defaultOn: false,
  ),

  /// The services that would add to this Home.
  setUpNext(
    audience: Audience.operator,
    label: 'Set up next',
    line: 'The services that would add to this page',
    placement: HomePlacement.last,
  ),

  /// The requester's Featured: the newest thing she asked for that arrived
  /// in the last seven days, with the way to watch it.
  readyToWatch(
    audience: Audience.requester,
    label: 'Ready to watch',
    line: 'The newest thing you asked for that arrived',
    services: [ServiceKey.seerr],
  ),

  /// What she asked for that is still on its way, and when it will be
  /// ready.
  yourRequests(
    audience: Audience.requester,
    label: 'Your requests',
    line: 'What you asked for, and when it will be ready',
    services: [ServiceKey.seerr],
  ),

  /// Seerr's shelf of the week, with her state on every poster.
  trending(
    audience: Audience.requester,
    label: 'Trending this week',
    line: 'What people are watching this week',
    services: [ServiceKey.seerr],
  ),

  /// What comes out soon.
  comingSoon(
    audience: Audience.requester,
    label: 'Coming soon',
    line: 'Movies and series with a release date ahead',
    services: [ServiceKey.seerr],
  );

  const HomeModule({
    required this.audience,
    required this.label,
    required this.line,
    this.placement = HomePlacement.ordered,
    this.hideable = true,
    this.services = const [],
    this.defaultOn = true,
    this.needs,
  });

  /// Whose Home it is on.
  final Audience audience;

  /// Its name: the module's heading, and its row in Edit Home.
  final String label;

  /// What it shows, in one line under its name in Edit Home.
  final String line;

  /// Where it stands.
  final HomePlacement placement;

  /// Whether Edit Home may switch it off. Needs you may not: it is there only
  /// when something is wrong, and then it is the point of the page.
  final bool hideable;

  /// Whether a Home starts with it on. The ones a person adds by choice (the
  /// lights of the stack, the storage, a shelf of Discover) do not.
  final bool defaultOn;

  /// The services that feed it. Empty when it reads the whole stack.
  final List<ServiceKey> services;

  /// What Edit Home says in place of [line] when none of [services] is set
  /// up, where naming them one by one would not fit a line. Null: the names.
  final String? needs;

  /// What Edit Home says of it while none of its services is set up:
  /// `Needs TrueNAS or Unraid`. Null for a module that reads the whole stack.
  String? get needsLine {
    if (services.isEmpty) return null;
    if (needs case final phrase?) return phrase;
    final names = [for (final service in services) service.title];
    return 'Needs ${_orList(names)}';
  }

  /// Whether Edit Home may move it. Set up next stands at the foot and stays
  /// there.
  bool get movable => placement == HomePlacement.ordered;

  /// Every module of [audience]'s Home, in its default order.
  static List<HomeModule> of(Audience audience) => [
    for (final module in values)
      if (module.audience == audience) module,
  ];

  /// The modules [audience] orders, in their default order.
  static List<HomeModule> orderedOf(Audience audience) => [
    for (final module in of(audience))
      if (module.movable) module,
  ];

  /// `Radarr`, `Radarr or Sonarr`, `Radarr, Sonarr or Lidarr`.
  static String _orList(List<String> names) => switch (names.length) {
    1 => names.single,
    _ => '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}',
  };

  /// The module this [name] stored, or null for a name no module has.
  static HomeModule? byName(String name) {
    for (final module in values) {
      if (module.name == name) return module;
    }
    return null;
  }
}
