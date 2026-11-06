/// What Cupola says when Tracearr flags a rule broken: the cursor that keeps a
/// read to what is new, and the words of the notification.
///
/// Tracearr watches the media servers all day and all night; Cupola reads
/// `violations?since=` only when the system wakes it. So the question a run
/// asks is never "what is there" but "what came after the last thing I read",
/// and the answer is kept **per connection**, in the server's own clock
/// (`OutsideSaid.flaggedSince`): a phone whose clock runs ahead of the server's
/// would otherwise skip the violations that fall in the gap, and one that runs
/// behind would say the same one twice.
///
/// A notice says the rule, the person and when. A violation also carries
/// places and addresses in its free-form data; those never reach a notice, a
/// log or a failure, and the model hands none of them out
/// (`TracearrViolation.toString`).
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart'
    show joinDisplayParts;
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart'
    show serviceWithConnection;
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart'
    show tracearrPersonOf;

/// The cursor of a connection that holds no violation at all: the start of
/// time, so the first one it ever records is read as new.
final DateTime flaggedFromTheStart = DateTime.fromMillisecondsSinceEpoch(
  0,
  isUtc: true,
);

/// Where a connection's first read starts: the newest violation it holds now,
/// whatever its age, so switching Flagged on says nothing of what is already
/// there. [newest] is the connection's latest violation (a page of one).
///
/// A connection holding **none** starts from [flaggedFromTheStart], which is
/// also "from now": nothing existed to skip. One that holds some but none with
/// a time starts nowhere (null): the start of time would bring every old
/// violation up as news at the next read, so it stays on its first run until
/// a read can place itself.
DateTime? flaggedStartOf(Iterable<TracearrViolation> newest) {
  DateTime? latest;
  var held = false;
  for (final violation in newest) {
    held = true;
    final at = violation.createdAt;
    if (at != null && (latest == null || at.isAfter(latest))) latest = at;
  }
  return held ? latest : flaggedFromTheStart;
}

/// What a read `since` [cursor] brings that is news, newest first, and where
/// the next read starts.
///
/// Only what is **strictly newer** than the cursor: Tracearr's `since` may
/// answer the violation the cursor was taken from again (an inclusive bound,
/// a timestamp it keeps to the microsecond and sends to the millisecond), and
/// that one has been read. A violation somebody has already acknowledged is
/// read too and not said: a person who looked at it needs no word of it. One
/// with no time cannot be placed after anything, so it is not news.
({List<TracearrViolation> fresh, DateTime cursor}) flaggedFreshOf(
  Iterable<TracearrViolation> read,
  DateTime cursor,
) {
  final newer = [
    for (final violation in read)
      if (violation.createdAt case final at? when at.isAfter(cursor)) violation,
  ]..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
  return (
    fresh: [
      for (final violation in newer)
        if (!violation.isAcknowledged) violation,
    ],
    cursor: newer.isEmpty ? cursor : newer.first.createdAt!,
  );
}

/// The notification for [fresh] on one Tracearr connection, or null when
/// there is none.
///
/// One violation says itself: the rule, the person and when
/// (`Too many streams · Anna · 4 min ago`), and a tap opens it. Several are
/// one notice, so a burst is a single line and not a stack: how many, and
/// whose, and a tap opens the connection's Violations tab. [more] is a read
/// that stopped on a full page, so the count is a floor (`50+`).
///
/// [name] is the connection's name once its service has two, so the notice
/// says which Tracearr. [instanceId] rides in the route (`?i=`), so a tap
/// opens the one the violation came off.
OutsideNotice? flaggedNotice(
  List<TracearrViolation> fresh, {
  required String instanceId,
  required String? name,
  required DateTime now,
  bool more = false,
}) {
  if (fresh.isEmpty) return null;
  final which = name == null
      ? null
      : serviceWithConnection(ServiceKey.tracearr, name, joiner: ' ');
  if (fresh.length == 1 && !more) {
    final violation = fresh.single;
    final at = violation.createdAt;
    final rule = violation.rule.name.trim();
    return OutsideNotice(
      kind: OutsideNoticeKind.flagged,
      id: violation.id,
      body: joinDisplayParts([
        rule.isEmpty ? 'Violation' : rule,
        tracearrPersonOf(violation.person),
        // Never ahead of the phone: the time is Tracearr's clock, which may run
        // a little in front of this one, and "in 2 min" for a violation that
        // has just happened would read as a promise.
        if (at != null)
          formatRelativeDateTime(at.isAfter(now) ? now : at, now: now),
        which,
      ]),
      route: ServiceRoutes.tracearrViolation(
        violation.id,
        instanceId: instanceId,
      ),
    );
  }
  final people = <String>[];
  for (final violation in fresh) {
    final person = tracearrPersonOf(violation.person);
    if (!people.contains(person)) people.add(person);
  }
  final left = people.length - 2;
  final count = more ? Lexicon.floor(fresh.length) : '${fresh.length}';
  return OutsideNotice(
    kind: OutsideNoticeKind.flagged,
    // The newest names the group: a later read has a later newest, so a group
    // is never mistaken for the one before it.
    id: 'group-${fresh.first.id}',
    body: joinDisplayParts([
      '$count new violations',
      people.take(2).join(', ') + (left > 0 ? ' +$left' : ''),
      which,
    ]),
    route: ServiceRoutes.tracearrViolationsOn(instanceId),
  );
}
