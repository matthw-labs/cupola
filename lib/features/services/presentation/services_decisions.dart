import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/services/presentation/kept_waiting_provider.dart';
import 'package:cupola/features/services/domain/arr_health.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/request_ordering.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/domain/unread_secret.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/unraid/domain/unraid_alerts.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/truenas/domain/models/alert.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/services/presentation/services_history.dart';
import 'package:cupola/features/services/presentation/services_probe.dart';
import 'package:cupola/features/services/presentation/services_queue.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

/// Decisions, and which sources answered for them.
typedef DashboardDecisions = ({
  List<DashboardDecision> decisions,
  SourceCoverage coverage,
});

/// One source's decisions: see [DecisionSource] for why each is read alone.
///
/// Reads what the page has already loaded: the requests it was going to show,
/// the queue the in-flight region reads, the history the recently-added rail
/// reads, and the three infrastructure providers the stack cards' KPIs already
/// watch. Nothing here is a new request; the region is a **view** of the page's
/// own data, which is why it can afford to be first on the screen.
///
/// Gated on its service being configured, and never throws: a failure is kept
/// in the coverage, classified, so the region can tell "nothing is waiting"
/// from "nobody could be asked". `retry: noProviderRetry` because the stack
/// source derives from Dockge's list, which carries it.
final dashboardDecisionSourceProvider =
    FutureProvider.family<DashboardDecisions, DecisionSource>((
      ref,
      source,
    ) async {
      switch (source) {
        case DecisionSource.requests:
          // Every Seerr, each answering for itself: a request waiting on the
          // second one is waiting on the user as much as one on the first.
          return _pendingRequestDecisions(ref);
        // Every connection of each, each answering for itself, like the
        // requests: a failing indexer on the second Prowlarr needs somebody as
        // much as one on the first, and its Test has to reach that Prowlarr.
        case DecisionSource.indexers:
          return _decisionsOnEveryConnection(
            ref,
            ServiceKey.prowlarr,
            (source) => _failingIndexerDecisions(ref, source),
          );
        case DecisionSource.certificates:
          return _decisionsOnEveryConnection(
            ref,
            ServiceKey.nginxProxyManager,
            (source) => _expiringCertificateDecisions(ref, source),
          );
        case DecisionSource.queue:
          // Not gated on one service: the faults come from whichever of eight
          // sources reported one, and the queue has already gated each of those
          // and kept which of them answered.
          final inFlight = await ref.watch(servicesInFlightProvider.future);
          // A stall kept waiting is out of every count of faults until its day
          // is up, or until it moves (`kept_waiting.dart`).
          final kept = ref.watch(keptWaitingProvider);
          final now = ref.read(stallClockProvider)();
          return (
            decisions: [
              for (final item in inFlight.faults)
                if (item.fault != InFlightFault.stalled ||
                    !isKeptWaiting(item, kept, now))
                  _queueFaultDecision(item),
            ],
            coverage: inFlight.coverage,
          );
        case DecisionSource.history:
          final history = await ref.watch(servicesArrHistoryProvider.future);
          return (
            decisions: history.entries
                .where((entry) => entry.outcome == ArrImportOutcome.failed)
                .map(_failedImportDecision)
                .toList(growable: false),
            coverage: history.coverage,
          );
        case DecisionSource.storage:
          final reads = await Future.wait([
            _decisionsOnEveryConnection(
              ref,
              ServiceKey.truenas,
              (source) => _storageAlertDecisions(ref, source),
            ),
            _decisionsOnEveryConnection(
              ref,
              ServiceKey.unraid,
              (source) => _unraidAlertDecisions(ref, source),
            ),
          ]);
          return (
            decisions: [for (final read in reads) ...read.decisions],
            coverage: SourceCoverage.merge([
              for (final read in reads) read.coverage,
            ]),
          );
        case DecisionSource.health:
          final reads = await Future.wait([
            for (final service in DecisionSource.health.services)
              _decisionsOnEveryConnection(
                ref,
                service,
                (source) => _healthDecisions(ref, source),
              ),
          ]);
          return (
            // The same check failing on several \*arrs is one fault.
            decisions: foldArrHealth([
              for (final read in reads) ...read.decisions,
            ]),
            coverage: SourceCoverage.merge([
              for (final read in reads) read.coverage,
            ]),
          );
        case DecisionSource.connections:
          return (
            decisions: _connectionFaultDecisions(ref),
            coverage: SourceCoverage.none,
          );
        case DecisionSource.violations:
          // Every Tracearr, each answering for itself: a violation on the
          // second one is as much the owner's as one on the first, and the
          // card must open the Tracearr it came off.
          return _decisionsOnEveryConnection(
            ref,
            ServiceKey.tracearr,
            (source) => _violationDecisions(ref, source),
          );
      }
    }, retry: noProviderRetry);

/// One source's decisions, read on every configured connection of [service].
///
/// They used to be read through the lens alone, because their controls (Test,
/// Start, Renew) called the lens: a stack that exited on the second Dockge
/// never reached Home. Each connection is its own source now, as each Seerr
/// is for the requests: one that fails is named under the region and takes
/// only its own decisions with it, and every decision carries the connection
/// it came off, so its control acts on that server.
Future<DashboardDecisions> _decisionsOnEveryConnection(
  Ref ref,
  ServiceKey service,
  Future<List<DashboardDecision>> Function(MergeConnection source) load,
) async {
  Future<DashboardDecisions> from(MergeConnection source) async {
    try {
      return (
        decisions: await load(source),
        coverage: SourceCoverage.answeredBy(
          service,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    } catch (error) {
      // Degrades to no decisions: a region that answers "what needs me" must
      // not itself become the thing that needs you, but says who failed.
      return (
        decisions: const <DashboardDecision>[],
        coverage: SourceCoverage.failure(
          service,
          error,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    }
  }

  final sources = watchMergeConnections(ref, service);
  if (sources.isEmpty) {
    return (
      decisions: const <DashboardDecision>[],
      coverage: SourceCoverage.none,
    );
  }
  final results = await Future.wait([
    for (final source in sources) from(source),
  ]);
  return (
    decisions: results
        .expand((result) => result.decisions)
        .toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
}

/// Everything waiting on a human, from every source, merged and ranked as each
/// source answers.
///
/// Synchronous over the sources' states rather than an `await` of all of them:
/// the decisions of the sources that answered are here as soon as they are,
/// and a source still out is [SourceCoverage.pending] rather than a wait. A
/// source being read again keeps its last answer while it is: `value`, not
/// `asData`, so a Dockge push does not blank the region between two lists.
final dashboardDecisionsProvider = Provider<DashboardDecisions>(
  (ref) => _mergedDecisions(ref, DecisionSource.values),
);

/// The decisions of [DecisionSource.faultSources] alone, for the notification
/// of Needs you in the background.
///
/// Not [dashboardDecisionsProvider] with the violations dropped afterwards:
/// that one watches every source, which starts the read of Tracearr's
/// violations even when nothing will say them. Here the violations source is
/// never watched, so a run with Flagged off asks Tracearr nothing, and one
/// with it on asks once (`tracearrViolationsSinceProvider`).
final dashboardFaultDecisionsProvider = Provider<DashboardDecisions>(
  (ref) => _mergedDecisions(ref, DecisionSource.faultSources),
);

DashboardDecisions _mergedDecisions(Ref ref, Iterable<DecisionSource> sources) {
  final decisions = <DashboardDecision>[];
  final parts = <SourceCoverage>[];
  for (final source in sources) {
    final read = ref.watch(dashboardDecisionSourceProvider(source));
    final value = read.value;
    if (value != null) {
      decisions.addAll(value.decisions);
      parts.add(value.coverage);
    } else if (read.hasError) {
      // The sources catch their own failures; this is one that escaped, and it
      // is still a source that could not be read rather than an empty one.
      parts.add(
        SourceCoverage.merge([
          for (final service in source.services)
            SourceCoverage.failure(service, read.error),
        ]),
      );
    } else {
      parts.add(SourceCoverage.pendingOf(source.services));
    }
  }

  // Folded before ranking, so a group ranks where its oldest member would have.
  return (
    decisions: rankDecisions(groupDecisions(decisions)),
    coverage: SourceCoverage.merge(parts),
  );
}

/// The requests waiting on a person, from every configured Seerr.
///
/// Each connection is its own source: one that does not answer is named under
/// the region and takes nobody else's requests with it. A request carries the
/// connection it came off, because a Seerr request id is per server and the
/// row's Approve has to reach the Seerr that holds it.
Future<DashboardDecisions> _pendingRequestDecisions(Ref ref) async {
  Future<DashboardDecisions> from(MergeConnection source) async {
    // The gate of this Seerr: a requester decides nothing, so her waiting
    // requests are no decision of hers; an account of the operator's that
    // may not approve keeps the row, its answers dimmed. Who asked is named
    // only where the connection sees everyone's requests.
    final gate = ref.watch(roleGateOfProvider(source.instanceId));
    final decides = gate.operatorAction(SeerrAbility.approve).isDrawn;
    final namesWho = gate.showsRequesterNames;
    try {
      // Only the requests waiting, one page: the module counts them from
      // Seerr's own total ([pendingRequestCountProvider]), never the rows.
      final requests = await ref.watch(
        pendingRequestsForProvider(source.instanceId).future,
      );
      return (
        decisions: [
          for (final request in requests)
            // `isAwaitingApproval` keys off the request's own status, never
            // `displayStatus`: a request for media that already exists
            // reports "Available" while nobody has approved it. See
            // `request_ordering.dart`.
            if (decides && isAwaitingApproval(request))
              pendingRequestDecision(
                request,
                instanceId: source.instanceId,
                name: source.name,
                isLens: source.isLens,
                namesWho: namesWho,
              ),
        ],
        coverage: SourceCoverage.answeredBy(
          ServiceKey.seerr,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    } catch (error) {
      return (
        decisions: const <DashboardDecision>[],
        coverage: SourceCoverage.failure(
          ServiceKey.seerr,
          error,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    }
  }

  final results = await Future.wait([
    for (final source in watchMergeConnections(ref, ServiceKey.seerr))
      from(source),
  ]);
  return (
    decisions: results
        .expand((result) => result.decisions)
        .toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
}

/// [request], waiting on a person, as the decision its row draws: who asked,
/// and on which Seerr once there are two; the row adds when (`askedAgo`),
/// which a read cannot keep current. [namesWho] where the connection sees
/// everyone's requests.
DashboardDecision pendingRequestDecision(
  SeerrRequest request, {
  required String instanceId,
  required String? name,
  required bool isLens,
  required bool namesWho,
}) => DashboardDecision(
  kind: DecisionKind.pendingRequest,
  id: 'seerr-$instanceId-${request.id}',
  service: ServiceKey.seerr,
  title: request.media?.title ?? 'Unknown media',
  detail: joinDisplayParts([
    if (name != null)
      serviceWithConnection(ServiceKey.seerr, name, joiner: ' '),
    if (namesWho) request.requestedBy?.displayName,
  ]),
  occurredAt: parseAddedTimestamp(request.createdAt),
  actionId: request.id,
  instanceId: instanceId,
  connectionName: name,
  posterUrl: ImageUtils.buildTmdbPosterUrl(request.media?.posterPath),
  // Discover resolves through the lens end to end, so a request off another
  // Seerr opens that Seerr's own requests list, which honours `?i=`, rather
  // than a media page asking the lens.
  route: isLens
      ? _seerrRequestRoute(request)
      : _seerrRequestsListRoute(instanceId),
);

/// How many requests wait for the operator's answer, across every Seerr
/// they may answer on: Seerr's own count of each, never the length of the
/// page read. [floor] when a Seerr gave no count and its page was full.
/// Null while a Seerr is read, and when one did not answer.
final pendingRequestCountProvider = FutureProvider<({int count, bool floor})?>((
  ref,
) async {
  var count = 0;
  var floor = false;
  for (final source in watchMergeConnections(ref, ServiceKey.seerr)) {
    final gate = ref.watch(roleGateOfProvider(source.instanceId));
    if (!gate.operatorAction(SeerrAbility.approve).isDrawn) continue;
    final List<SeerrRequest> requests;
    try {
      requests = await ref.watch(
        pendingRequestsForProvider(source.instanceId).future,
      );
    } catch (_) {
      return null;
    }
    final total = requests is SeerrRequestList ? requests.total : null;
    count += total ?? requests.length;
    if (total == null && requests is SeerrRequestList && requests.isPartial) {
      floor = true;
    }
  }
  return (count: count, floor: floor);
}, retry: noProviderRetry);

/// The requests list of one Seerr connection, the one destination that
/// honours a connection in its link.
String _seerrRequestsListRoute(String instanceId) =>
    ServiceRoutes.activityRequestsOf(instanceId);

String _seerrRequestRoute(SeerrRequest request) {
  final media = request.media;
  final id = media?.tmdbId ?? media?.id;
  if (id == null || id <= 0) return ServiceRoutes.seerr;
  return ServiceRoutes.mediaRoot(
    request.type == 'tv' ? MediaKey.tv(id) : MediaKey.movie(id),
  );
}

Future<List<DashboardDecision>> _failingIndexerDecisions(
  Ref ref,
  MergeConnection source,
) async {
  // `/indexerstatus` returns only the indexers with an active problem, so this
  // list *is* the fault list: no filtering, and no counting against the total.
  final results = await Future.wait([
    ref.watch(prowlarrIndexerStatusForProvider(source.instanceId).future),
    ref.watch(prowlarrIndexersForProvider(source.instanceId).future),
  ]);
  final statuses = results[0] as List<ProwlarrIndexerStatus>;
  final indexers = results[1] as List<ProwlarrIndexer>;
  final names = {for (final indexer in indexers) indexer.id: indexer.name};

  return [
    for (final status in statuses)
      DashboardDecision(
        kind: DecisionKind.failingIndexer,
        // With the connection: two Prowlarr both number their indexers from
        // one.
        id: 'prowlarr-${source.instanceId}-${status.indexerId}',
        service: ServiceKey.prowlarr,
        title: names[status.indexerId] ?? 'Indexer ${status.indexerId}',
        detail: joinDisplayParts([
          'Failing',
          // Which Prowlarr, once there are two to tell apart.
          serviceWithConnection(ServiceKey.prowlarr, source.name, joiner: ' '),
          status.disabledTill == null ? null : 'disabled for now',
        ]),
        instanceId: source.instanceId,
        connectionName: source.name,
        actionInstanceId: source.instanceId,
        // The *first* failure, not the most recent one: an indexer that has been
        // failing since breakfast outranks one that failed a minute ago, and the
        // most recent failure of a long outage is always a minute ago.
        occurredAt:
            parseAddedTimestamp(status.initialFailure) ??
            parseAddedTimestamp(status.mostRecentFailure),
        actionId: status.indexerId,
        route: ServiceRoutes.prowlarrIndexer(status.indexerId),
      ),
  ];
}

/// TrueNAS's alerts that need somebody (warning or worse, not dismissed),
/// in plain words where the app knows the alert ([trueNasAlertHeadline]).
Future<List<DashboardDecision>> _storageAlertDecisions(
  Ref ref,
  MergeConnection source,
) async {
  final alerts = await TrueNasService(
    ref.watch(truenasClientForProvider(source.instanceId)),
  ).getAlerts();
  return [
    for (final alert in alerts)
      if (!alert.dismissed && alert.needsAttention)
        DashboardDecision(
          kind: DecisionKind.storageAlert,
          id: 'truenas-${source.instanceId}-${alert.id}',
          service: ServiceKey.truenas,
          title: trueNasAlertHeadline(alert),
          detail: serviceWithConnection(
            ServiceKey.truenas,
            source.name,
            joiner: ' ',
          ),
          // TrueNAS's own sentence, for Why?; the disk, for its pool's scrub.
          reason: alert.message.trim().isEmpty ? null : alert.message.trim(),
          subject: trueNasDiskErrors(alert)?.disk,
          occurredAt: switch (alert.datetimeMs) {
            final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
            null => null,
          },
          route: ServiceRoutes.truenasDashboard,
          instanceId: source.instanceId,
          connectionName: source.name,
          actionInstanceId: source.instanceId,
        ),
  ];
}

/// What an Unraid server says needs somebody ([unraidAlerts]): the slots its
/// array flagged, which lead to the array, and its unread notifications at
/// warning or alert, which lead to its notifications.
Future<List<DashboardDecision>> _unraidAlertDecisions(
  Ref ref,
  MergeConnection source,
) async {
  final client = ref.watch(unraidClientForProvider(source.instanceId));
  final (array, notifications) = await (
    client.getArray(),
    client.getNotifications(),
  ).wait;
  return [
    for (final alert in unraidAlerts(
      array: array,
      notifications: notifications,
    ))
      DashboardDecision(
        kind: DecisionKind.storageAlert,
        id: 'unraid-${source.instanceId}-${alert.id}',
        service: ServiceKey.unraid,
        title: alert.title,
        detail: serviceWithConnection(
          ServiceKey.unraid,
          source.name,
          joiner: ' ',
        ),
        reason: alert.reason,
        occurredAt: alert.occurredAt,
        route: alert.isDisk
            ? ServiceRoutes.unraidArray
            : ServiceRoutes.unraidNotifications,
        instanceId: source.instanceId,
        connectionName: source.name,
        actionInstanceId: source.instanceId,
      ),
  ];
}

/// An \*arr's health checks at the error level, in the app's words where it
/// knows the check (`arr_health.dart`) and in the \*arr's own otherwise; its
/// own stay behind Why?. A warning or a notice (an update out, an indexer slow
/// to answer) is news for its own page, not a fault.
Future<List<DashboardDecision>> _healthDecisions(
  Ref ref,
  MergeConnection source,
) async {
  if (source.service == ServiceKey.bazarr) {
    return _bazarrHealthDecisions(ref, source);
  }
  final ArrActivityMixin arr = switch (source.service) {
    ServiceKey.radarr => ref.watch(radarrServiceForProvider(source.instanceId)),
    ServiceKey.sonarr => ref.watch(sonarrServiceForProvider(source.instanceId)),
    ServiceKey.readarr => ref.watch(
      readarrServiceForProvider(source.instanceId),
    ),
    _ => ref.watch(lidarrServiceForProvider(source.instanceId)),
  };
  final checks = await arr.getHealth();
  final name = serviceWithConnection(source.service, source.name, joiner: ' ');
  return [
    for (final check in checks)
      if (check.isError && check.message.isNotEmpty)
        DashboardDecision(
          kind: DecisionKind.serviceHealth,
          id:
              'health-${source.service.routeParam}-${source.instanceId}-'
              '${check.source}-${check.message.hashCode}',
          service: source.service,
          title: arrHealthWords(check.source)?.headline ?? check.message,
          detail: name,
          reason: check.message,
          subject: check.source,
          // The \*arr does not date a check.
          occurredAt: null,
          route: ServiceRoutes.forService(source.service),
          instanceId: source.instanceId,
          connectionName: source.name,
          actionInstanceId: source.instanceId,
        ),
  ];
}

/// Bazarr's health issues, each a fault: without a languages profile, or
/// with a library folder it cannot use, Bazarr fetches nothing. The headline
/// is the app's where the check is known, Bazarr's own words stay behind Why?.
Future<List<DashboardDecision>> _bazarrHealthDecisions(
  Ref ref,
  MergeConnection source,
) async {
  final issues = await ref
      .watch(bazarrServiceForProvider(source.instanceId))
      .getHealthIssues();
  final name = serviceWithConnection(source.service, source.name, joiner: ' ');
  return [
    for (final issue in issues)
      DashboardDecision(
        kind: DecisionKind.serviceHealth,
        id:
            'health-${source.service.routeParam}-${source.instanceId}-'
            '${issue.object.hashCode}-${issue.issue.hashCode}',
        service: source.service,
        title: issue.headline,
        detail: name,
        reason: issue.issue.isEmpty ? null : issue.issue,
        subject: 'bazarr:${issue.object}',
        // Bazarr does not date an issue.
        occurredAt: null,
        route: ServiceRoutes.forService(source.service),
        instanceId: source.instanceId,
        connectionName: source.name,
        actionInstanceId: source.instanceId,
      ),
  ];
}

/// Every connection whose probe answered with a refusal or a fault, as the
/// fault its classification names. Read off the summaries the stack's health
/// already asks for, so it adds no request; a connection still being asked
/// is not here yet, and one that did not answer is the red line, not this.
List<DashboardDecision> _connectionFaultDecisions(Ref ref) {
  final settings = ref.watch(currentSettingsProvider);
  return [
    // A secret this device would not hand over: no probe goes out for that
    // connection, so its fault is read off the settings, not off an answer.
    for (final instance in settings.instances)
      if (instance.unreadSecret != null)
        unreadSecretDecision(instance, settings.connectionName(instance.id)),
    for (final service in ServiceKey.values)
      for (final id in ref.watch(serviceInstanceIdsProvider(service)))
        if (_answeredWithFault(
              ref.watch(
                instanceSummaryProvider((service: service, instanceId: id)),
              ),
            )
            case final failure?)
          _connectionFaultDecision(
            service,
            id,
            settings.connectionName(id),
            failure,
          ),
  ];
}

/// The failure of a probe that answered with a refusal or a fault, or null:
/// answered and well, did not answer, still asking, or a Seerr session that
/// ended, which is the person's step and blue.
ClassifiedFailure? _answeredWithFault(AsyncValue<ServiceSummary> summary) {
  switch (summary) {
    case AsyncData(:final value):
      final reason = value.failureReason;
      if (!value.isFault ||
          reason == null ||
          reason == ServiceFailureReason.sessionEnded) {
        return null;
      }
      return value.failure ?? ClassifiedFailure(reason);
    case AsyncError(:final error):
      final failure = ClassifiedFailure.of(error);
      // Silence, a session that ended and a connection only at home are no
      // fault of the answer.
      return failureIsFault(failure.reason) ? failure : null;
    default:
      return null;
  }
}

/// The fault of a connection whose secret could not be read, in its own
/// words ([UnreadSecretWords]) and with the remedy to its form.
DashboardDecision unreadSecretDecision(ServiceInstance instance, String? name) {
  final words = UnreadSecretWords.of(instance, connectionName: name);
  return DashboardDecision(
    kind: DecisionKind.connectionFault,
    id: 'connection-${instance.id}',
    service: instance.service,
    title: words.headline,
    detail: words.sentence,
    occurredAt: null,
    route: words.route,
    instanceId: instance.id,
    connectionName: name,
    actionInstanceId: instance.id,
    remedy: words.remedy,
  );
}

DashboardDecision _connectionFaultDecision(
  ServiceKey service,
  String instanceId,
  String? name,
  ClassifiedFailure failure,
) {
  final credential = refusedCredentialOf(service);
  final subject = serviceWithConnection(service, name, joiner: ' ');
  return DashboardDecision(
    kind: DecisionKind.connectionFault,
    id: 'connection-$instanceId',
    service: service,
    title: failureHeadline(
      failure.reason,
      subject: subject,
      credential: credential,
      gateway: failure.gateway,
    ),
    detail: failureLabel(
      failure.reason,
      credential: credential,
      gateway: failure.gateway,
    ),
    // A probe dates nothing; the fault is as old as the reading.
    occurredAt: null,
    route: ServiceRoutes.settingsForConnection(service, instanceId),
    instanceId: instanceId,
    connectionName: name,
    actionInstanceId: instanceId,
    remedy: failureRemedy(
      failure.reason,
      credential: credential,
      gateway: failure.gateway,
    ),
    // A gateway's words name what answered in front, which no group shares.
    failureReason: failure.gateway == null ? failure.reason : null,
  );
}

Future<List<DashboardDecision>> _expiringCertificateDecisions(
  Ref ref,
  MergeConnection source,
) async {
  final certificates = await ref.watch(
    npmCertificatesForProvider(source.instanceId).future,
  );
  final now = DateTime.now();
  return [
    for (final certificate in certificates)
      if (certificate.isExpiringSoon(now))
        DashboardDecision(
          kind: DecisionKind.expiringCertificate,
          id: 'npm-cert-${source.instanceId}-${certificate.id}',
          service: ServiceKey.nginxProxyManager,
          title: certificate.domainNames.isEmpty
              ? certificate.niceName
              : certificate.domainNames.first,
          // An uploaded certificate does not renew: the row names it as one,
          // so a control without Renew reads as the truth rather than a gap.
          // It drops the service's name: beside "Open certificates", which is
          // wider than Renew, any longer line lost its last words to the
          // ellipsis on a 390pt phone, and the glyph already names the service.
          // Which of two it is on stays, by the connection's own name alone.
          detail: joinDisplayParts([
            _certificateExpiry(certificate, now),
            if (certificate.isLetsEncrypt)
              serviceWithConnection(
                ServiceKey.nginxProxyManager,
                source.name,
                joiner: ' ',
              )
            else
              source.name,
          ]),
          renewable: certificate.isLetsEncrypt,
          instanceId: source.instanceId,
          connectionName: source.name,
          actionInstanceId: source.instanceId,
          // The expiry date, standing in for "when did this start needing me".
          // Ordering by it puts the certificate closest to lapsing first, which
          // is what "oldest first" means for a deadline.
          occurredAt: certificate.expiresOn,
          route: ServiceRoutes.forService(ServiceKey.nginxProxyManager),
        ),
  ];
}

/// Tracearr's unseen violations of severity high, as the decisions Needs you
/// draws: the rule, the person and when, never a place or an address.
///
/// Blue and not a fault (`DecisionKind.violation`), and read one past the cap
/// so the count can say it is a floor. The route carries the connection it
/// came off, so the card opens that Tracearr's own page for it.
Future<List<DashboardDecision>> _violationDecisions(
  Ref ref,
  MergeConnection source,
) async {
  final page = await ref.watch(
    tracearrFlaggedProvider(source.instanceId).future,
  );
  return [
    for (final violation in page.items)
      // Belt and braces over the server's filter: only what is still unseen
      // and as bad as it gets is a decision.
      if (!violation.isAcknowledged &&
          violation.severity == TracearrSeverity.high)
        DashboardDecision(
          kind: DecisionKind.violation,
          id: 'tracearr-violation-${source.instanceId}-${violation.id}',
          service: ServiceKey.tracearr,
          title: violation.rule.name.trim().isEmpty
              ? 'Violation'
              : violation.rule.name.trim(),
          detail: joinDisplayParts([
            tracearrPersonOf(violation.person),
            // Which Tracearr, once there are two to tell apart.
            if (source.name != null)
              serviceWithConnection(
                ServiceKey.tracearr,
                source.name,
                joiner: ' ',
              ),
          ]),
          occurredAt: violation.createdAt,
          instanceId: source.instanceId,
          connectionName: source.name,
          route: ServiceRoutes.tracearrViolation(
            violation.id,
            instanceId: source.instanceId,
          ),
        ),
  ];
}

String _certificateExpiry(NpmCertificate certificate, DateTime now) {
  final noun = certificate.isLetsEncrypt
      ? 'Certificate'
      : 'Uploaded certificate';
  final expiresOn = certificate.expiresOn;
  if (expiresOn == null) return '$noun expiring';
  final days = expiresOn.difference(now).inDays;
  if (days < 0) return '$noun expired';
  if (days == 0) return '$noun expires today';
  if (days == 1) return '$noun expires tomorrow';
  return '$noun expires in $days days';
}

/// The decision a faulted transfer becomes, by what its fault is.
///
/// A blocked import is a manual import, filed under the library item and seeded
/// with the download's folder, on the connection the record came off. A stall
/// or a failure is a jump into the client. Before the fault had a kind, all
/// three were the second.
DashboardDecision _queueFaultDecision(ServiceQueueItem item) {
  if (item.fault == InFlightFault.needsImport) {
    return DashboardDecision(
      kind: DecisionKind.importBlocked,
      // With the connection: two Radarr both number their queues from one.
      id: 'import-blocked-${item.service.routeParam}-${item.instanceId}-${item.id}',
      service: item.service,
      // Read in a sentence (`… needs a manual import`), so a pack is named
      // by its episodes, not by the row's count of them.
      title: item.subject ?? item.title,
      // The shape `_failedImportDecision` prints, so the two import faults read
      // alike. No client: the bytes are on disk, and the client is not where
      // this is fixed. The connection is named when there are two.
      detail: joinDisplayParts([
        'Import blocked',
        serviceWithConnection(item.service, item.connectionName, joiner: ' '),
        item.warning,
      ]),
      occurredAt: item.stalledSince,
      route: item.route,
      actionId: item.mediaId,
      instanceId: item.instanceId,
      connectionName: item.connectionName,
      actionInstanceId: item.instanceId,
    );
  }

  final isClientRow = item.clientService == item.service;
  return DashboardDecision(
    kind: DecisionKind.stalledDownload,
    // The cause, when the source gave one: what a folded row of several keeps
    // if they all share it.
    reason: item.warning,
    id: 'stall-${item.service.routeParam}-${item.instanceId}-${item.id}',
    service: item.service,
    title: item.title,
    detail: joinDisplayParts([
      item.warning ??
          switch (item.fault) {
            InFlightFault.failed => 'Failed',
            InFlightFault.stalled ||
            InFlightFault.needsImport ||
            null => StateWord.stuck.label,
          },
      item.detail == item.warning ? null : item.detail,
      // Which arr asked for it, once there are two to tell apart. A client's
      // own row is already named by its client label.
      if (!isClientRow && item.connectionName != null)
        serviceWithConnection(item.service, item.connectionName, joiner: ' '),
      item.clientLabel,
    ]),
    occurredAt: item.stalledSince,
    route: item.route,
    instanceId: item.instanceId,
    connectionName: item.connectionName,
    // The client the control opens, on the connection moving the bytes.
    actionInstanceId: item.clientInstanceId,
    // The decision acts on the client, which may not be a service this user has
    // set up at all: an \*arr can name a download client Cupola has no
    // connection to. The control stays drawn and tappable either way; see the
    // row.
    requiresService: _clientServiceFor(item),
    transferFailed: item.fault == InFlightFault.failed,
    downloadKeys: [keptWaitingKey(item)],
  );
}

/// Which service the "open this transfer" control would jump to.
///
/// Null when the row already *is* the client: qBittorrent's own stalled torrent
/// opens in qBittorrent, which is not a cross-service jump and owes no hint.
/// An \*arr row joined to its client's row knows the client exactly; otherwise
/// the \*arr's own name for it is all there is.
ServiceKey? _clientServiceFor(ServiceQueueItem item) {
  final client = item.clientService;
  if (client != null) return client == item.service ? null : client;
  if (item.service == ServiceKey.qbittorrent) return null;
  return switch (item.clientLabel.toLowerCase()) {
    final label when label.contains('qbittorrent') => ServiceKey.qbittorrent,
    final label when label.contains('sab') => ServiceKey.sabnzbd,
    final label when label.contains('nzbget') => ServiceKey.nzbget,
    final label when label.contains('transmission') => ServiceKey.transmission,
    _ => null,
  };
}

DashboardDecision _failedImportDecision(ArrHistoryEntry entry) =>
    DashboardDecision(
      kind: DecisionKind.failedImport,
      // With the connection: each arr numbers its history from one.
      id: 'import-${entry.service.routeParam}-${entry.instanceId}-${entry.id}',
      service: entry.service,
      title: entry.title,
      detail: joinDisplayParts([
        'Import failed',
        serviceWithConnection(entry.service, entry.connectionName, joiner: ' '),
        entry.reason,
      ]),
      occurredAt: entry.at,
      // The library item a manual import would be filed under. Zero (a failed
      // grab of something the \*arr never added) leaves the wizard to ask.
      actionId: entry.mediaId <= 0 ? null : entry.mediaId,
      // The connection the record came off: the wizard files into that
      // server's library, under that server's id for the film.
      instanceId: entry.instanceId,
      connectionName: entry.connectionName,
      actionInstanceId: entry.instanceId,
      posterUrl: entry.posterUrl,
      route: entry.mediaId <= 0
          ? ServiceRoutes.forService(entry.service)
          : switch (entry.service) {
              ServiceKey.radarr when (entry.tmdbId ?? 0) > 0 =>
                ServiceRoutes.mediaRoot(
                  MediaKey.movie(entry.tmdbId!),
                  focus: entry.instanceId,
                ),
              ServiceKey.radarr => ServiceRoutes.radarrMovie(
                entry.mediaId,
                instanceId: entry.instanceId,
              ),
              ServiceKey.sonarr when (entry.tmdbId ?? 0) > 0 =>
                ServiceRoutes.mediaRoot(
                  MediaKey.tv(entry.tmdbId!),
                  focus: entry.instanceId,
                ),
              ServiceKey.sonarr => ServiceRoutes.sonarrSeries(
                entry.mediaId,
                instanceId: entry.instanceId,
              ),
              ServiceKey.lidarr => ServiceRoutes.lidarrArtist(
                entry.mediaId,
                instanceId: entry.instanceId,
              ),
              _ => ServiceRoutes.forService(entry.service),
            },
    );
