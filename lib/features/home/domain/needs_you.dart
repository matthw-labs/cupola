/// Needs you: the one line at the top of the operator's Home that says what is
/// wrong, how many more things are, and the way in.
///
/// It reads what the Home already holds: the services whose every connection
/// stayed silent, and the decisions the stack is waiting on, less the requests.
/// A request is somebody waiting politely, blue and never amber; it has its own
/// module. What is left is a fault, something that was working and stopped.
///
/// **Who leads.** A service that did not answer first, because its own faults
/// cannot be seen while it is silent; then the largest group of equal faults,
/// because eighteen downloads that need the same import are the most work
/// waiting in one place. Equal sizes keep the order the decisions were ranked in
/// (`rankDecisions`: worst kind, then oldest). Connections that failed alike
/// are one group too, said in one sentence: thirteen servers reached and stuck
/// are `Seerr, Radarr and 11 others were reached but did not reply in time`,
/// never the first of them and `+12`.
///
/// **The way in.** The line never runs a remedy itself. Silence leads to Retry,
/// the one thing a person can do about a service that did not answer from here;
/// a fault leads to Review, which opens the place the fault is fixed today.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

@immutable
class NeedsYou {
  const NeedsYou._({
    required this.line,
    required this.more,
    this.moreIsFloor = false,
    this.silent = const [],
    this.lead,
  });

  /// The services that did not answer, when they lead. Empty when a fault does.
  final List<ServiceKey> silent;

  /// The fault that leads, when no service is silent: the first of them, when
  /// the line says several connections that failed alike.
  final DashboardDecision? lead;

  /// What the line says: `18 downloads need a manual import`, `Radarr did not
  /// answer at 20:53`.
  final String line;

  /// How many more things need the person, after the lead: the chip's `+2`.
  final int more;

  /// Whether [more] is the least there is: a read the faults come from
  /// stopped short, so past it there may be more.
  final bool moreIsFloor;

  /// The chip: `+2`, or `2+ more` when that is the least there is.
  String get moreLabel =>
      moreIsFloor ? '${Lexicon.floor(more)} more' : '+$more';

  /// Whether a silent service leads: red, and Retry.
  bool get leadsWithSilence => silent.isNotEmpty;

  /// The control's word.
  String get action =>
      leadsWithSilence ? servicesRetryLabel(silent.length) : 'Review';

  /// The one sentence a screen reader hears: `18 downloads need a manual
  /// import, and 2 more things need you. Review`.
  String get spoken {
    final count = moreIsFloor ? 'at least $more' : '$more';
    final rest = switch (more) {
      0 => '',
      1 when !moreIsFloor => ', and 1 more thing needs you',
      _ => ', and $count more things need you',
    };
    // A floor is heard as one: `at least 18 downloads`, never `18 plus`.
    return '${spokenCountPhrase(line)}$rest. $action';
  }
}

/// What Needs you says, or null when nothing does.
///
/// [silent] are the services whose every connection did not answer, found
/// silent by the probe that settled at [silentAt] and silent since
/// [silentSince] (the latest of them, when every one is known), and asked where
/// [silenceScope] says. [decisions] are the stack's,
/// already folded and ranked; [floor] when the walk of the queues, where every
/// group comes from, stopped before their end, so a group's count is at least
/// what it says; [moreFloor] when any read the faults come from stopped short,
/// so the count after the lead is at least what it says. [now] dates a
/// certificate's expiry.
NeedsYou? needsYouOf({
  required List<ServiceKey> silent,
  required List<DashboardDecision> decisions,
  required DateTime now,
  DateTime? silentAt,
  DateTime? silentSince,
  SilenceScope silenceScope = SilenceScope.asked,
  bool floor = false,
  bool moreFloor = false,
}) {
  final faults = [
    for (final decision in decisions)
      if (decision.isFault) decision,
  ];
  if (silent.isNotEmpty) {
    return NeedsYou._(
      silent: silent,
      line: servicesDidNotAnswer(
        [for (final service in silent) service.title],
        at: silentAt,
        since: silentSince,
        scope: silenceScope,
      ),
      more: faults.length,
      moreIsFloor: moreFloor,
    );
  }
  if (faults.isEmpty) return null;

  // Largest group first; the sort is decorated with the rank, because
  // `List.sort` is not stable and equal groups would trade places between
  // builds.
  final groups = _equalFaults(faults);
  final ranked =
      List.generate(
        groups.length,
        (index) => (index: index, group: groups[index]),
        growable: false,
      )..sort((a, b) {
        final bySize = b.group.size.compareTo(a.group.size);
        return bySize != 0 ? bySize : a.index.compareTo(b.index);
      });
  final lead = ranked.first.group;
  return NeedsYou._(
    lead: lead.members.first,
    line:
        lead.sentence ??
        needsYouLine(lead.members.single, now: now, floor: floor),
    more: faults.length - lead.members.length,
    moreIsFloor: moreFloor,
  );
}

/// Faults Needs you weighs as one: a decision `groupDecisions` already
/// folded, or connections that failed alike, with the [sentence] that says
/// them together.
typedef _EqualFaults = ({
  List<DashboardDecision> members,
  int size,
  String? sentence,
});

/// [faults] in their order, the connection faults one sentence can say
/// together gathered under the first of them.
///
/// Keyed as the modules' sentences are (`coverageFailureSentence`): on the
/// reason, and on the credential only where it is named, so two refused keys
/// group and a key and a sign-in refused do not.
List<_EqualFaults> _equalFaults(List<DashboardDecision> faults) {
  final buckets = <Object, List<DashboardDecision>>{};
  for (final fault in faults) {
    (buckets[_sharedSentenceKey(fault) ?? fault] ??= []).add(fault);
  }
  return [
    for (final MapEntry(:key, value: members) in buckets.entries)
      (
        members: members,
        size: members.fold(0, (sum, member) => sum + member.count),
        sentence: switch (key) {
          (final ServiceFailureReason reason, final String credential)
              when members.length > 1 =>
            failureGroupHeadline(
              reason,
              // As many names as a module's sentence carries.
              subjects: servicesNamed([
                for (final member in members)
                  serviceWithConnection(
                    member.service,
                    member.connectionName,
                    joiner: ' ',
                  ),
              ], maxNamed: 2),
              credential: credential,
            ),
          _ => null,
        },
      ),
  ];
}

/// What a connection fault shares with the others its sentence can be said
/// with, or null when it is said alone.
(ServiceFailureReason, String)? _sharedSentenceKey(DashboardDecision fault) {
  final reason = fault.failureReason;
  if (fault.kind != DecisionKind.connectionFault || reason == null) return null;
  if (failureGroupHeadline(reason, subjects: '') == null) return null;
  return (
    reason,
    reason == ServiceFailureReason.unauthorized
        ? refusedCredentialOf(fault.service)
        : kRefusedCredential,
  );
}

/// The sentence one fault leads Needs you with.
///
/// A sentence and not a row's title and detail: the line is read once, in one
/// breath, and `Big Buck Bunny · Stuck · qBittorrent` is a row's way of
/// speaking. A group says how many and what they share.
String needsYouLine(
  DashboardDecision decision, {
  required DateTime now,
  bool floor = false,
}) {
  final count = floor ? Lexicon.floor(decision.count) : '${decision.count}';
  if (decision.count > 1) {
    return switch (decision.kind) {
      DecisionKind.importBlocked => '$count downloads need a manual import',
      DecisionKind.stalledDownload =>
        decision.transferFailed
            ? '$count downloads failed'
            : '$count downloads are stuck',
      // Never grouped (see `groupDecisions`); said anyway, so the switch is
      // total.
      DecisionKind.failedImport => '$count imports failed',
      DecisionKind.storageAlert => '$count storage alerts',
      DecisionKind.connectionFault => '$count connections have a fault',
      DecisionKind.serviceHealth => '$count health checks are failing',
      DecisionKind.failingIndexer => '$count indexers are failing',
      DecisionKind.expiringCertificate => '$count certificates are expiring',
      DecisionKind.violation => '$count violations need a look',
      DecisionKind.pendingRequest => '$count requests wait for approval',
    };
  }
  final title = decision.title;
  return switch (decision.kind) {
    DecisionKind.importBlocked => '$title needs a manual import',
    DecisionKind.stalledDownload =>
      decision.transferFailed ? 'Could not download $title' : '$title is stuck',
    DecisionKind.failedImport => 'Could not import $title',
    // Each of these titles is already a sentence: TrueNAS's alert in plain
    // words, the fault's headline, the \*arr's own check.
    DecisionKind.storageAlert || DecisionKind.connectionFault => title,
    // Every \*arr the check fails on, with its connection: `Radarr, Sonarr
    // and Lidarr: No indexer is watching for new releases`.
    DecisionKind.serviceHealth => '${decision.detail}: $title',
    DecisionKind.failingIndexer => 'The $title indexer is failing',
    DecisionKind.expiringCertificate => _certificateLine(
      title,
      decision.occurredAt,
      now,
    ),
    // Blue, so Needs you's lead never says one (it leads with faults), but a
    // sentence stays total: the rule and whose it was.
    DecisionKind.violation => '$title by ${decision.detail}',
    DecisionKind.pendingRequest => '$title waits for approval',
  };
}

/// `The certificate for nas.home.arpa expires in 6 days`. The decision dates
/// a certificate by its expiry.
String _certificateLine(String host, DateTime? expiresOn, DateTime now) {
  final subject = 'The certificate for $host';
  if (expiresOn == null) return '$subject is expiring';
  final days = expiresOn.difference(now).inDays;
  if (days < 0) return '$subject expired';
  if (days == 0) return '$subject expires today';
  if (days == 1) return '$subject expires tomorrow';
  return '$subject expires in $days days';
}
