/// The words of a fault's card in Needs you, for every kind but a stuck
/// download (`stuck_download_fault.dart`): a headline that is a sentence,
/// what it means where the app can say, which service raised it, and the
/// service's own words under Why?.
library;

import 'package:cupola/features/activity/domain/stuck_download_fault.dart'
    show sentence;
import 'package:cupola/features/services/domain/arr_health.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart'
    show serviceWithConnection;

/// A card's words: [headline] in large type, [explanation] under it, then
/// [source] small, and [why] behind Why? when the service gave a cause.
typedef FaultWords = ({
  String headline,
  String? explanation,
  String source,
  String? why,
});

/// The words of [decision]'s card.
FaultWords faultWordsOf(DashboardDecision decision) {
  final source = serviceWithConnection(
    decision.service,
    decision.connectionName,
    joiner: ' ',
  );
  final count = decision.count;
  final why = decision.reason?.trim();
  return switch (decision.kind) {
    DecisionKind.importBlocked => (
      headline: count > 1
          ? '$count downloads need a manual import'
          : '${decision.title} needs a manual import',
      explanation: count > 1
          ? "$source finished them and won't import them on its own."
          : "$source finished it and won't import it on its own.",
      source: source,
      why: why == null || why.isEmpty ? null : sentence(why),
    ),
    DecisionKind.failedImport => (
      headline: '${decision.title} did not import',
      explanation: '$source downloaded it and could not place the file.',
      source: source,
      why: why == null || why.isEmpty ? null : sentence(why),
    ),
    DecisionKind.failingIndexer => (
      headline: '${decision.title} is failing',
      explanation: decision.detail.contains('disabled for now')
          ? 'Prowlarr has stopped searching it for now.'
          : null,
      source: source,
      why: null,
    ),
    // The server's own sentence behind Why?, when the headline is the app's.
    DecisionKind.storageAlert => (
      headline: _withoutStop(decision.title),
      explanation: null,
      source: source,
      why: why == null || why.isEmpty || _withoutStop(why) == decision.title
          ? null
          : sentence(why),
    ),
    DecisionKind.connectionFault => (
      headline: _withoutStop(decision.title),
      explanation: null,
      source: source,
      why: null,
    ),
    // The app's words where it knows the check, and every \*arr it fails
    // on under them; the \*arrs' own behind Why?.
    DecisionKind.serviceHealth => _healthWords(decision),
    // The hostname, and its expiry with the service under it.
    DecisionKind.expiringCertificate ||
    DecisionKind.stalledDownload ||
    DecisionKind.violation ||
    DecisionKind.pendingRequest => (
      headline: decision.title,
      explanation: null,
      source: decision.detail,
      why: null,
    ),
  };
}

/// The amber fill's label on [decision]'s card: `Review 18` for a group of
/// blocked imports where the wizard exists, the kind's own control otherwise.
String faultActionLabel(DashboardDecision decision) {
  final label = decisionActionLabel(
    decision.kind,
    target: decision.actionTarget,
    renewable: decision.renewable,
    remedy: decision.remedy,
  );
  if (decision.kind == DecisionKind.importBlocked &&
      decision.actionTarget.supportsManualImport) {
    return decision.count > 1 ? 'Review ${decision.count}' : 'Review';
  }
  // Which \*arr, once the check fails on more than one.
  if (decision.kind == DecisionKind.serviceHealth) {
    return openHealthCheckLabel(decision.members.firstOrNull ?? decision);
  }
  return label;
}

FaultWords _healthWords(DashboardDecision decision) {
  final words = arrHealthWords(decision.subject ?? '');
  final why = decision.reason?.trim();
  return (
    headline: _withoutStop(words?.headline ?? decision.title),
    explanation: words?.explanation,
    source: decision.detail,
    why: words == null || why == null || why.isEmpty ? null : why,
  );
}

/// The amber fill's label on a health check's card, and its other \*arrs'
/// quieter ways out: `Open in Radarr 4K`.
String openHealthCheckLabel(DashboardDecision decision) =>
    'Open in ${decision.detail}';

/// A headline is set large and ends without a full stop, as a title does.
String _withoutStop(String text) {
  final trimmed = text.trim();
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}
