/// The Dashboard's third region: one list of everything waiting on a human.
///
/// ## Why one list and not six
///
/// The screen used to carry a Requests region: one kind, one service, its own
/// header, its own empty state, and nothing at all for the other five. So a
/// stalled torrent, a failing indexer and an expiring certificate had no place to
/// be *asked about*: each was a number on a card somewhere, and the user had to
/// know to go looking. A region per kind would have made six regions that are
/// empty most of the time, which is six headings to scroll past to learn that
/// nothing is wrong.
///
/// The question the region answers is "what needs me", and the answer does not
/// come sorted by which service happened to raise it. So it is one list, mixed
/// kinds, ranked by urgency:
///
///  * **faults before backlog.** A stalled download, a failing indexer, an
///    expiring certificate and a failed import are things that were meant to be
///    working and are not. A pending request is somebody
///    politely waiting: it is *backlog*, the same category as 34 missing films,
///    and the tone rule files backlog under neutral. It still belongs in this
///    region (it needs a decision, which is the whole criterion) and it belongs
///    under the faults.
///  * **oldest first inside a kind.** Two stalled downloads are the same kind of
///    problem; the one that has been stuck since breakfast is the one to look at.
///    An undated item sorts last within its kind rather than to the top, for the
///    same reason `sortRecentlyAdded` does it: an item that cannot be placed
///    honestly loses to one that can.
///
/// Nothing in here fetches. The provider merges what the page has already
/// loaded: see `dashboardDecisionsProvider`.
library;

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// Where decisions come from: each one read on its own.
///
/// One read per source rather than one read of all of them, because the region
/// is only as fast as what it waits for: Dockge publishes its stack list over a
/// socket with a ten-second deadline, and while the region was one `await` of
/// every source a slow Dockge held back the pending requests and the stalled
/// downloads that had answered in a few hundred milliseconds. Read apart, each
/// source's decisions arrive when it does.
enum DecisionSource {
  /// Seerr's requests nobody has approved.
  requests([ServiceKey.seerr]),

  /// Prowlarr's failing indexers.
  indexers([ServiceKey.prowlarr]),

  /// Nginx Proxy Manager's certificates close to expiry.
  certificates([ServiceKey.nginxProxyManager]),

  /// The transfers that stopped being transfers. One source and not eight: a
  /// stall is joined across an \*arr and the client moving its bytes, and read
  /// apart the same stall would be two decisions until the second arrived.
  queue([
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.lidarr,
    ServiceKey.readarr,
    ServiceKey.qbittorrent,
    ServiceKey.transmission,
    ServiceKey.sabnzbd,
    ServiceKey.nzbget,
  ]),

  /// The imports the \*arrs' history says failed.
  history([ServiceKey.radarr, ServiceKey.sonarr, ServiceKey.lidarr]),

  /// The storage servers' own alerts: TrueNAS's at warning or worse, and
  /// Unraid's flagged slots and unread notifications at warning or alert.
  storage([ServiceKey.truenas, ServiceKey.unraid]),

  /// The \*arrs' own health checks that report an error, and Bazarr's health
  /// issues (every one of which stops it working).
  health([
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.lidarr,
    ServiceKey.readarr,
    ServiceKey.bazarr,
  ]),

  /// Connections that answered with a refusal or a fault: a refused key, a
  /// gateway answering in a service's place, a server error. Read off the
  /// probes the stack's health already makes, so it asks nothing of its own
  /// and names no service as unread: a connection that did not answer at all
  /// is the red line above Needs you, never one of its faults.
  connections([]),

  /// Tracearr's violations of severity high that nobody has looked at. Not
  /// faults: a rule was broken, which is the person's to read, and nothing
  /// Cupola reaches stopped working. Read a page past [kNeedsYouViolationCap]
  /// so the count can say it is a floor.
  violations([ServiceKey.tracearr]);

  const DecisionSource(this.services);

  /// The services this source reads.
  final List<ServiceKey> services;
}

/// How many violations Needs you draws. The source reads one more, so that a
/// longer list reads as a floor (`5+`) and never as the total: the API pages
/// and gives none.
const int kNeedsYouViolationCap = 5;

/// What kind of thing is waiting.
///
/// Declaration order is the tiebreak between kinds of the same urgency, so it is
/// written worst-first: a transfer that stopped moving is more actionable than a
/// certificate with six days left on it.
enum DecisionKind {
  /// A download that has stopped moving. Action: open it in its client.
  stalledDownload,

  /// A download an \*arr has finished and will not import on its own: a
  /// queue record in `importBlocked`, or the older forks' `importPending`
  /// with a warning. Action: manual import.
  ///
  /// Its own kind rather than a stall, which is what it used to be filed as:
  /// the bytes are on disk, so "Open in qBittorrent" sent the user to the one
  /// place that cannot fix it.
  importBlocked,

  /// An \*arr history record whose import failed. Action: manual import.
  failedImport,

  /// A storage server's own alert: TrueNAS's at warning or worse (a disk
  /// reporting errors, a pool degraded), Unraid's flagged slot or unread
  /// notification at warning or alert. Action: open the alert, on the
  /// server's own page ([DashboardDecision.route]).
  storageAlert,

  /// A connection that answered, with a refusal or a fault: a refused key, a
  /// gateway in the way, a server error. Action: the remedy its cause names
  /// (`Paste the key again`, `Check the password`), or Retry where asking
  /// again can help.
  connectionFault,

  /// An \*arr health check at the error level: a root folder that is gone, a
  /// download client it cannot reach. Action: the \*arr's own page, where the
  /// check is fixed.
  serviceHealth,

  /// An indexer Prowlarr has marked as failing. Action: test it.
  failingIndexer,

  /// A certificate about to expire. Action: renew it.
  expiringCertificate,

  /// An unseen violation of severity high that Tracearr recorded. Blue and
  /// not a fault: the rule was broken by a person, and every service is still
  /// doing its job. Action: open it, where the owner acknowledges or
  /// dismisses it.
  ///
  /// After the faults and before the requests: a rule broken is further from
  /// "stopped working" than anything above, and more than somebody waiting.
  violation,

  /// A Seerr request nobody has approved or declined. Action: both.
  ///
  /// Last, and deliberately: it is the only *backlog* kind in the region.
  pendingRequest,
}

extension DecisionKindRank on DecisionKind {
  /// Whether this kind is a fault: something that was working and stopped.
  ///
  /// The tone rule's first arm, stated once here rather than re-derived at every
  /// row: faults are amber, backlog is neutral, and red is left to a connection
  /// that did not answer.
  bool get isFault => switch (this) {
    DecisionKind.pendingRequest || DecisionKind.violation => false,
    DecisionKind.stalledDownload ||
    DecisionKind.importBlocked ||
    DecisionKind.failedImport ||
    DecisionKind.storageAlert ||
    DecisionKind.connectionFault ||
    DecisionKind.serviceHealth ||
    DecisionKind.failingIndexer ||
    DecisionKind.expiringCertificate => true,
  };

  /// Whether what this kind's row and control open reads the lens, with no
  /// `?i=` to name a connection: Prowlarr's indexer page, a Dockge stack, NPM's
  /// certificates. A decision off another connection brings that connection
  /// under the lens before it opens one, as a stall does for its client.
  bool get opensUnderLens => switch (this) {
    DecisionKind.failingIndexer ||
    DecisionKind.expiringCertificate ||
    DecisionKind.storageAlert => true,
    DecisionKind.stalledDownload ||
    DecisionKind.importBlocked ||
    DecisionKind.failedImport ||
    DecisionKind.connectionFault ||
    DecisionKind.serviceHealth ||
    DecisionKind.violation ||
    DecisionKind.pendingRequest => false,
  };
}

/// One thing waiting on a decision, already reduced to what the row paints.
///
/// Flat and service-agnostic on purpose. A union of six models would make the
/// row switch on a type to find a title; this way the merge happens once, in the
/// provider, and the row is one widget.
class DashboardDecision {
  const DashboardDecision({
    required this.kind,
    required this.id,
    required this.service,
    required this.title,
    required this.detail,
    required this.occurredAt,
    this.route,
    this.requiresService,
    this.posterUrl = '',
    this.actionId,
    this.count = 1,
    this.instanceId = '',
    this.connectionName,
    this.actionInstanceId = '',
    this.reason,
    this.renewable = true,
    this.transferFailed = false,
    this.remedy,
    this.failureReason,
    this.downloadKeys = const [],
    this.subject,
    this.members = const [],
  });

  final DecisionKind kind;

  /// The remedy a [DecisionKind.connectionFault]'s cause names
  /// (`failureRemedy`), or null where Retry is the remedy. Null on every
  /// other kind, whose control is the kind's own.
  final String? remedy;

  /// The classification a [DecisionKind.connectionFault]'s words come from,
  /// where they come from it alone: equal faults on many connections can then
  /// be said once (`failureGroupHeadline`). Null where the words name more
  /// than the reason (a gateway that answered in front, a secret this device
  /// would not hand over), and on every other kind.
  final ServiceFailureReason? failureReason;

  /// Unique within its kind: used for the row's key and for nothing else.
  final String id;

  /// Which service raised it. Owns the row's glyph and its accent.
  final ServiceKey service;

  /// The item, in the user's words: a film, a stack, an indexer, a hostname.
  final String title;

  /// The line under the title. Already `·`-joined for the eye; the row
  /// re-separates it for the ear.
  final String detail;

  /// When it started being a problem. Null when the source has no timestamp,
  /// which sorts it last inside its kind rather than pretending it just
  /// happened.
  final DateTime? occurredAt;

  /// Where the row body leads. The row body links to the item; the trailing
  /// control is the decision, and the two are never the same destination.
  final String? route;

  /// The service the *decision* acts on, when it is not [service].
  ///
  /// A stalled qBittorrent transfer surfaced by Radarr is the specimen: the row
  /// belongs to Radarr and the control opens qBittorrent. When this service is
  /// not configured the control is drawn dimmed but stays tappable, keeps its
  /// target and gains a hint: never `Semantics(enabled: false)`, which would
  /// take the fact off the screen reader's path along with the control.
  final ServiceKey? requiresService;

  /// The id the *action* needs, where the action is a call rather than a jump:
  /// the Seerr request to approve, the Prowlarr indexer to test, the library
  /// item a manual import is for. Null when the kind's control only navigates.
  ///
  /// Separate from [id], which is a string scoped by kind and exists to key a
  /// widget. Folding the two would mean parsing an integer back out of
  /// `seerr-1423` at the one call site that must not get it wrong.
  final int? actionId;

  /// Artwork, when the source has some. Empty is normal: a stack and an indexer
  /// have no poster, and the row draws its service glyph instead.
  final String posterUrl;

  /// How many items this row stands for. One, except for a row
  /// [groupDecisions] folded identical faults into.
  final int count;

  /// The connection the row was read from, and the one an action that opens
  /// a flow bound to one (the import wizard, Approve) is bound to. Empty
  /// means "whatever the lens is on".
  final String instanceId;

  /// What tells [instanceId] apart from the service's other connections, by
  /// the app's one rule, or null while the service has only the one.
  final String? connectionName;

  /// The connection of [actionTarget] the control opens: the arr's for an
  /// import, the client's for a stall. Empty means "whatever the lens is on".
  final String actionInstanceId;

  /// Why it is waiting, in one clause, when its source said: `Disk full`,
  /// `Password needed`, the client's own message. Already the first clause
  /// of [detail]; kept apart so a folded row ([groupDecisions]) can carry it
  /// when every member shares it. Null when the source gave no cause.
  final String? reason;

  /// For an expiring certificate: whether Nginx Proxy Manager can renew it,
  /// which it can for a Let's Encrypt one only. An uploaded certificate can
  /// only be replaced, by whoever issued it, so its row offers no Renew.
  /// True for every other kind, where it means nothing.
  final bool renewable;

  /// For a stalled download: whether the client gave up on it rather than
  /// stopped moving it. The row's detail already says `Failed`; this is what
  /// a sentence about the transfer reads, so it never calls a failure stuck.
  final bool transferFailed;

  /// For a stalled download, the key its transfer is known by across reads
  /// (`keptWaitingKey`); a folded row carries every member's. Activity draws
  /// one card per key, since each stuck download has a way out of its own.
  /// Empty on every other kind.
  final List<String> downloadKeys;

  /// What the fault is about inside its service, where a remedy needs it:
  /// the disk a TrueNAS alert names (`sdd`), whose pool a scrub repairs; the
  /// check an \*arr's health names (`IndexerRssCheck`), which its words and
  /// its folding go by.
  final String? subject;

  /// The faults folded into this one, each on its own connection: the same
  /// health check failing on Radarr, Sonarr and Lidarr is one fault, and
  /// each member's control opens its own \*arr. Empty for a fault that
  /// stands alone, and for a group [groupDecisions] folded, whose control is
  /// the same for every member.
  final List<DashboardDecision> members;

  bool get isFault => kind.isFault;

  /// The service the trailing control would open: [requiresService] when the
  /// decision acts on another service, otherwise the one that raised it.
  ///
  /// What [decisionActionLabel] should be told. Told nothing, a stall raised by
  /// a Radarr that named no known client said "Open in client" and then opened
  /// Radarr.
  ServiceKey get actionTarget => requiresService ?? service;
}

/// Whether [kind] folds into one row when several share a remedy.
///
/// Only the kinds whose control is a *jump* (to the client, to the import
/// wizard) can: the jump is the same for every item in the group. Test, Start
/// and Approve act on one indexer, one stack, one request, and a grouped row
/// would have nothing to call them on.
bool _groups(DecisionKind kind) => switch (kind) {
  DecisionKind.stalledDownload || DecisionKind.importBlocked => true,
  DecisionKind.failedImport ||
  DecisionKind.storageAlert ||
  DecisionKind.connectionFault ||
  DecisionKind.serviceHealth ||
  DecisionKind.failingIndexer ||
  DecisionKind.expiringCertificate ||
  DecisionKind.violation ||
  DecisionKind.pendingRequest => false,
};

/// Folds identical faults into one row: `18 need a manual import · Sonarr`.
///
/// Identical means the same kind, raised by the same service on the same
/// connection, with the same remedy target. Eighteen blocked imports on one
/// Sonarr are one decision: go and import them, and drawing them as eighteen
/// rows spent the phone's three slots on the first three of them while saying
/// nothing about the other fifteen.
///
/// A lone item stays itself, poster and title intact. A group keeps the oldest
/// member's age, so it ranks where its worst member would have, and the
/// [DashboardDecision.count] every count surface sums.
List<DashboardDecision> groupDecisions(List<DashboardDecision> decisions) {
  final buckets = <Object, List<DashboardDecision>>{};
  final order = <Object>[];
  for (final decision in decisions) {
    final Object key = _groups(decision.kind)
        ? (
            decision.kind,
            decision.service,
            decision.instanceId,
            decision.requiresService,
            decision.actionInstanceId,
          )
        : decision;
    final bucket = buckets[key];
    if (bucket == null) {
      buckets[key] = [decision];
      order.add(key);
    } else {
      bucket.add(decision);
    }
  }

  return [
    for (final key in order)
      if (buckets[key]!.length == 1)
        buckets[key]!.single
      else
        _groupOf(buckets[key]!),
  ];
}

DashboardDecision _groupOf(List<DashboardDecision> members) {
  final first = members.first;
  final count = members.fold<int>(0, (sum, member) => sum + member.count);

  DateTime? oldest;
  for (final member in members) {
    final at = member.occurredAt;
    if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
  }

  // Carried only when every member agrees: a manual import seeded with the
  // first member's folder or filed under its film would import the other
  // eighteen into the wrong place.
  T? shared<T>(T? Function(DashboardDecision member) read) {
    final value = read(first);
    return members.every((member) => read(member) == value) ? value : null;
  }

  return DashboardDecision(
    kind: first.kind,
    id: [
      'group',
      first.kind.name,
      first.service.routeParam,
      first.instanceId,
      first.requiresService?.routeParam ?? '',
      first.actionInstanceId,
    ].join('-'),
    service: first.service,
    title: _groupTitle(first.kind, count),
    // The members' cause, first as it is on each of their own rows, when they
    // all share it: `Disk full · Radarr 4K · Elephants Dream, Sintel`. When
    // they differ, no one member's cause stands for the rest, and the count
    // in the title is all the row says.
    detail: joinDisplayParts([
      shared((member) => member.reason),
      serviceWithConnection(first.service, first.connectionName, joiner: ' '),
      _titlesSummary([for (final member in members) member.title]),
    ]),
    reason: shared((member) => member.reason),
    occurredAt: oldest,
    // The service that raised them, where the whole group is listed. No one
    // member's page stands for the rest.
    route: ServiceRoutes.forService(first.service),
    requiresService: first.requiresService,
    actionId: shared((member) => member.actionId),
    count: count,
    instanceId: first.instanceId,
    connectionName: first.connectionName,
    actionInstanceId: first.actionInstanceId,
    transferFailed: members.every((member) => member.transferFailed),
    downloadKeys: [for (final member in members) ...member.downloadKeys],
  );
}

String _groupTitle(DecisionKind kind, int count) => switch (kind) {
  DecisionKind.importBlocked => needsManualImportClause(count),
  DecisionKind.stalledDownload => '$count stuck downloads',
  // Never grouped: see [_groups]. Named anyway so the switch stays total.
  DecisionKind.failedImport => '$count failed imports',
  DecisionKind.storageAlert => '$count storage alerts',
  DecisionKind.connectionFault => '$count connections with a fault',
  DecisionKind.serviceHealth => '$count failing health checks',
  DecisionKind.failingIndexer => '$count failing indexers',
  DecisionKind.expiringCertificate => '$count expiring certificates',
  DecisionKind.violation => '$count violations',
  DecisionKind.pendingRequest => '$count requests waiting for approval',
};

/// `Shogun, The Bear and 16 more`: the first two names, and how many others.
String _titlesSummary(List<String> titles) {
  final distinct = <String>[];
  for (final title in titles) {
    if (!distinct.contains(title)) distinct.add(title);
  }
  if (distinct.length <= 2) return distinct.join(', ');
  return '${distinct.take(2).join(', ')} and ${distinct.length - 2} more';
}

/// Faults before backlog, oldest first inside a kind.
///
/// Stable by construction: the sort is decorated with the source index, because
/// `List.sort` is not stable and several undated items would otherwise
/// come back in a different order on each build, which reads on screen as rows
/// shuffling for no reason.
List<DashboardDecision> rankDecisions(
  List<DashboardDecision> decisions, {
  int? cap,
}) {
  final decorated =
      List.generate(
        decisions.length,
        (index) => (index: index, decision: decisions[index]),
        growable: false,
      )..sort((a, b) {
        final byKind = a.decision.kind.index.compareTo(b.decision.kind.index);
        if (byKind != 0) return byKind;

        final atA = a.decision.occurredAt;
        final atB = b.decision.occurredAt;
        if (atA != null && atB != null) {
          final byAge = atA.compareTo(atB);
          if (byAge != 0) return byAge;
        } else if (atA == null && atB != null) {
          return 1;
        } else if (atA != null && atB == null) {
          return -1;
        }

        return a.index.compareTo(b.index);
      });

  final ranked = decorated
      .map((entry) => entry.decision)
      .toList(growable: false);
  if (cap == null || cap >= ranked.length) return ranked;
  return ranked.take(cap < 0 ? 0 : cap).toList(growable: false);
}

/// How many rows the region shows, by size class.
///
/// Three numbers rather than a formula: the cap is a judgment about how much
/// triage fits above the stack, not a function of pixels. Pure: it takes the
/// two facts a breakpoint would give it rather than a `BuildContext`, so the
/// rule is testable without pumping a widget.
int decisionCapFor({required bool desktopShell, required bool compact}) {
  if (!desktopShell) return 3;
  return compact ? 2 : 4;
}

/// What the trailing control on a row is called.
///
/// One table rather than a string per call site: the verb is the decision, and a
/// row whose button says something different from what the screen reader
/// announces is the defect this file exists to make impossible.
String decisionActionLabel(
  DecisionKind kind, {
  ServiceKey? target,
  bool renewable = true,
  String? remedy,
}) => switch (kind) {
  DecisionKind.stalledDownload => 'Open in ${target?.title ?? 'client'}',
  // The wizard exists for three arrs. Anywhere else the honest control is
  // the service's own page, and it says so rather than promising a wizard
  // that would refuse to start.
  DecisionKind.importBlocked =>
    target == null || target.supportsManualImport
        ? 'Manual import'
        : 'Open in ${target.title}',
  DecisionKind.failedImport => 'Fix',
  DecisionKind.storageAlert => 'Open alert',
  // The remedy the cause names, or Retry where the same request can still
  // succeed: the classification's words, never the row's own.
  DecisionKind.connectionFault => remedy ?? 'Retry',
  DecisionKind.serviceHealth => 'Open in ${target?.title ?? 'the service'}',
  DecisionKind.failingIndexer => 'Test',
  // `Renew` opens the Certificates tab, where renewal sits beside its
  // confirmation: the call reaches Let's Encrypt, and a renewal fired from
  // a row on Home is one mis-tap from spending the account's rate limits.
  // Only a Let's Encrypt certificate renews; an uploaded one is replaced,
  // so its control opens the certificates under their own name and never
  // says Renew. Not "Open in Nginx Proxy Manager": the row's own detail
  // names the service, and the long name pushed the control off a phone row.
  DecisionKind.expiringCertificate => renewable ? 'Renew' : 'Open certificates',
  // The row is the door: the violation's own page is where it is read and,
  // by the owner, answered.
  DecisionKind.violation => 'Review',
  // Two controls, not one: see the row.
  DecisionKind.pendingRequest => 'Approve',
};

/// The toast a decision control opens when its target service is not set up.
///
/// The control stays in the tree, stays tappable and keeps its 44pt target
/// (`CrossServiceAction`, whose default hint is `requires <Service>`); this is
/// what it says instead of working.
String decisionUnavailableToast(DecisionKind kind, ServiceKey required) {
  final what = switch (kind) {
    DecisionKind.stalledDownload => 'open this transfer',
    DecisionKind.importBlocked => 'import these files',
    DecisionKind.failedImport => 'fix this import',
    DecisionKind.storageAlert => 'open this alert',
    DecisionKind.connectionFault => 'fix this connection',
    DecisionKind.serviceHealth => 'open this check',
    DecisionKind.failingIndexer => 'test this indexer',
    DecisionKind.expiringCertificate => 'renew this certificate',
    DecisionKind.violation => 'open this violation',
    DecisionKind.pendingRequest => 'answer this request',
  };
  return '${Lexicon.setUp(required.title)} to $what.';
}

/// The services the faults among [decisions] stand on: each fault's own, and
/// each \*arr a health check is folded across ([DashboardDecision.members]).
///
/// Stack health lights them amber and the Stack's bands do not count them
/// clean, so neither says a service is fine while Needs you holds a fault on
/// it.
Set<ServiceKey> faultedServices(Iterable<DashboardDecision> decisions) => {
  for (final decision in decisions)
    if (decision.isFault) ...[
      decision.service,
      for (final member in decision.members) member.service,
    ],
};
