/// What Cupola says in a notification, and the memory that keeps it from
/// saying a thing twice.
///
/// A notification is a new fact or nothing, never a reminder: so what is
/// said is what is there now and was not there the last time anyone looked.
/// "Anyone looked" includes the person opening the app: a run in the
/// foreground records what the Home shows without saying it
/// ([outsideNoticesOf]`(speak: false)`), and the run in the background says
/// only what came since.
///
/// The words are the app's own: a fault is the line Needs you leads with
/// (`needsYouLine`), an arrival is the title Ready to watch draws. Red is
/// never said: a server out of reach is where the phone is, and Needs you
/// does not count it among its faults either.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/features/home/domain/needs_you.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';

/// The three things Cupola tells, each a switch in Settings and a channel on
/// Android.
enum OutsideNoticeKind {
  /// A fault Needs you counts: a download stuck, an import that waits, a disk
  /// or a key that fails.
  needsYou('Needs you', Duration(days: 1)),

  /// Something asked for that arrived.
  readyToWatch('Ready to watch', Duration(days: 30)),

  /// A rule Tracearr says someone broke, new since the last time Cupola read.
  /// Its own kind and not one of Needs you's: a violation is not a fault
  /// (nothing Cupola reaches stopped working), so it never counts there and
  /// is blue where it is drawn. Its first read is quiet by its own cursor
  /// (`OutsideSaid.flaggedSince`) and not by a baseline: what it reads is
  /// "since", never "everything there is".
  flagged('Flagged', Duration(days: 30), quietFirstRead: false);

  const OutsideNoticeKind(
    this.label,
    this.remembered, {
    this.quietFirstRead = true,
  });

  /// The notification's title and the channel's name.
  final String label;

  /// How long a thing said is remembered once it is gone: a fault that comes
  /// back within the day is the same fault (a stall that clears and stalls
  /// again is not news twice), and an arrival is said once a month at most.
  final Duration remembered;

  /// Whether the first read of the kind records what is there without saying
  /// it: true for a state read whole (faults, arrivals), false for a kind that
  /// reads only what came after a cursor of its own.
  final bool quietFirstRead;
}

/// One notification: its kind, what names it across runs, its words, and
/// where a tap opens.
@immutable
class OutsideNotice {
  const OutsideNotice({
    required this.kind,
    required this.id,
    required this.body,
    this.route,
    this.picture,
  });

  final OutsideNoticeKind kind;

  /// What names the thing across runs: a decision's id, a request's key.
  final String id;

  String get key => '${kind.name}:$id';

  String get title => kind.label;

  /// `Charge is stuck`, `Spring`.
  final String body;

  final String? route;

  /// A file name beside the snapshot: an arrival's poster.
  final String? picture;

  @override
  bool operator ==(Object other) =>
      other is OutsideNotice &&
      other.kind == kind &&
      other.id == id &&
      other.body == body &&
      other.route == route &&
      other.picture == picture;

  @override
  int get hashCode => Object.hash(kind, id, body, route, picture);

  @override
  String toString() => 'OutsideNotice(${kind.name}, $id, $body)';
}

/// What has been said or seen, by [OutsideNotice.key], with when it was last
/// there; which kinds have their first read behind them; and how far each
/// Tracearr connection has been read.
@immutable
class OutsideSaid {
  const OutsideSaid({
    this.seen = const {},
    this.baselined = const {},
    this.flaggedSince = const {},
  });

  /// Read from what [toJson] wrote. Anything it cannot read is nothing said,
  /// which costs a quiet first run at worst ([outsideNoticesOf]).
  factory OutsideSaid.fromJson(Object? json) {
    if (json is! Map || json['version'] != version) return const OutsideSaid();
    final seen = <String, DateTime>{};
    if (json['seen'] case final Map entries) {
      for (final MapEntry(:key, :value) in entries.entries) {
        final at = value is String ? DateTime.tryParse(value)?.toLocal() : null;
        if (key is String && at != null) seen[key] = at;
      }
    }
    final baselined = <OutsideNoticeKind>{
      if (json['baselined'] case final List names)
        for (final kind in OutsideNoticeKind.values)
          if (names.contains(kind.name)) kind,
    };
    final flaggedSince = <String, DateTime>{};
    if (json['flaggedSince'] case final Map cursors) {
      for (final MapEntry(:key, :value) in cursors.entries) {
        final at = value is String ? DateTime.tryParse(value)?.toLocal() : null;
        if (key is String && at != null) flaggedSince[key] = at;
      }
    }
    return OutsideSaid(
      seen: seen,
      baselined: baselined,
      flaggedSince: flaggedSince,
    );
  }

  /// Unchanged by the cursors: a file written before they existed has none,
  /// which reads as every connection's first run, a quiet one.
  static const version = 1;

  final Map<String, DateTime> seen;
  final Set<OutsideNoticeKind> baselined;

  /// By Tracearr connection id, the time of the newest violation Cupola has
  /// read there, in **Tracearr's own clock** (the `created_at` it sent): the
  /// next read asks for what came `since` it. Never the phone's clock, which
  /// may be ahead of the server's and would skip what happened in between.
  /// A connection with none starts from what it holds at its first run.
  final Map<String, DateTime> flaggedSince;

  Map<String, Object?> toJson() => {
    'version': version,
    'seen': {
      for (final MapEntry(:key, :value) in seen.entries)
        key: value.toUtc().toIso8601String(),
    },
    'baselined': [for (final kind in baselined) kind.name],
    'flaggedSince': {
      for (final MapEntry(:key, :value) in flaggedSince.entries)
        key: value.toUtc().toIso8601String(),
    },
  };

  @override
  bool operator ==(Object other) =>
      other is OutsideSaid &&
      mapEquals(other.seen, seen) &&
      setEquals(other.baselined, baselined) &&
      mapEquals(other.flaggedSince, flaggedSince);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      seen.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(baselined),
    Object.hashAllUnordered(
      flaggedSince.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// What to say now, and what is remembered after it.
typedef OutsideHeard = ({List<OutsideNotice> say, OutsideSaid said});

/// The notifications of a run at [now], against what was [said].
///
/// [current] is what each kind's read holds now, or null for a kind whose
/// read did not answer: nothing of it is said and nothing of it forgotten,
/// since an answer that did not come is not the thing going away.
///
/// A kind switched off forgets what it said, so switching it on again is a
/// first read, which records what is there without a word: switching on
/// Needs you must not bring a dozen old faults at once. [speak] false is a
/// run the person is looking at (the app in the foreground): it records and
/// says nothing.
///
/// [flaggedSince] is where each Tracearr connection has been read up to once
/// this run is done, or null for a run that did not touch the cursors. A
/// cursor only moves forward: a run racing another one keeps the later of
/// the two. Switching Flagged off forgets them, so switching it on again
/// starts from what Tracearr holds then.
OutsideHeard outsideNoticesOf({
  required Map<OutsideNoticeKind, List<OutsideNotice>?> current,
  required OutsideSaid said,
  required Set<OutsideNoticeKind> enabled,
  required DateTime now,
  required bool speak,
  Map<String, DateTime>? flaggedSince,
}) {
  final seen = Map.of(said.seen);
  final baselined = Set.of(said.baselined);
  final say = <OutsideNotice>[];

  for (final kind in OutsideNoticeKind.values) {
    bool mine(String key) => key.startsWith('${kind.name}:');
    if (!enabled.contains(kind)) {
      seen.removeWhere((key, _) => mine(key));
      baselined.remove(kind);
      continue;
    }
    final notices = current[kind];
    if (notices == null) continue;
    final first = kind.quietFirstRead && !baselined.contains(kind);
    for (final notice in notices) {
      if (speak && !first && !seen.containsKey(notice.key)) say.add(notice);
      seen[notice.key] = now;
    }
    baselined.add(kind);
    seen.removeWhere(
      (key, at) => mine(key) && now.difference(at) > kind.remembered,
    );
  }
  final cursors = <String, DateTime>{};
  if (enabled.contains(OutsideNoticeKind.flagged)) {
    for (final MapEntry(:key, :value)
        in (flaggedSince ?? said.flaggedSince).entries) {
      final other = said.flaggedSince[key];
      cursors[key] = other != null && other.isAfter(value) ? other : value;
    }
  }
  return (
    say: say,
    said: OutsideSaid(seen: seen, baselined: baselined, flaggedSince: cursors),
  );
}

/// Needs you's faults as notifications: one per fault, in its line.
List<OutsideNotice> needsYouNotices(
  List<DashboardDecision> decisions, {
  required DateTime now,
}) => [
  for (final decision in decisions)
    if (decision.isFault)
      OutsideNotice(
        kind: OutsideNoticeKind.needsYou,
        id: decision.id,
        body: needsYouLine(decision, now: now),
        route: decision.route,
      ),
];

/// The arrivals among [requests] as notifications: what Ready to watch would
/// draw. [idOf] names a request across runs (`seerrRequestKey`), [routeOf]
/// says where its tap opens and [pictureOf] gives its poster's file.
List<OutsideNotice> readyToWatchNotices(
  MyRequests requests, {
  required String Function(MyRequest mine) idOf,
  String? Function(MyRequest mine)? routeOf,
  String? Function(MyRequest mine)? pictureOf,
}) => [
  for (final mine in requests.ready)
    OutsideNotice(
      kind: OutsideNoticeKind.readyToWatch,
      id: idOf(mine),
      body: mine.title,
      route: routeOf?.call(mine),
      picture: pictureOf?.call(mine),
    ),
];
