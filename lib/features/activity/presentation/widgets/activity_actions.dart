import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/activity/data/queue_retry.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_request_update.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/seerr_approve_target_read.dart';
import 'package:cupola/features/discover/presentation/widgets/approve_request_sheet.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The write actions the Activity surfaces can perform on a queue or blocklist
/// record.
///
/// Activity was a read-only feed: it could tell you a download had stalled and
/// then offered no way to do anything about it, so the resolution path for every
/// problem it surfaced was to leave and open the service's web UI. These close
/// that loop.
///
/// Each one confirms first, neutrally, with a verb that says what will happen,
/// never in red, which means unreachable and nothing else. It reports the outcome, and bumps [activityRefreshVersionProvider] so every
/// bucket re-reads rather than leaving a removed row on screen.
///
/// ## Every write takes the connection it acts on
///
/// These used to resolve the service through the **lens**: whichever Radarr
/// the user last looked at. That was correct only while the feed showed one
/// server. Now that /activity merges every connection, the lens and the row are
/// different facts, and \*arr record ids are per server: each one numbers its
/// queue from one, so `id: 7` names a different download on each Sonarr.
/// Sending a removal to the lens would delete somebody else's download and
/// report success. So the caller passes the row's own `instanceId` and it
/// resolves through [connectionArrServiceProvider]; an empty id still means
/// "the lens", which is what the per-service Activity screen wants.
///
/// The same is true of the two request actions, for the same reason in Seerr's
/// vocabulary: a request id is per instance, so approving id 42 through the
/// lens approves a different person's request on a different server, and
/// reports success. They resolve through `seerrServiceForProvider`.
class ActivityActions {
  ActivityActions._();

  /// Removes a queue record, optionally blocklisting the release.
  ///
  /// The two toggles are the two decisions the \*arr API actually exposes, and
  /// they mean different things: deleting from the client frees the disk,
  /// blocklisting stops the same release being grabbed again on the next search.
  /// Blocklisting alone is the "this release is bad, find another" move.
  static Future<void> removeFromQueue(
    BuildContext context,
    WidgetRef ref, {
    required ServiceType serviceType,
    required String instanceId,
    required int recordId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Remove from queue?',
      message: title,
      icon: Icons.delete_outline_rounded,
      confirmLabel: 'Remove and delete files',
      // The button names both decisions as they stand, so what it says is what
      // the tap sends.
      confirmLabelFor: (checked) =>
          switch ((checked('removeFromClient'), checked('blocklist'))) {
            (true, true) => 'Remove, delete files and blocklist',
            (true, false) => 'Remove and delete files',
            (false, true) => 'Remove and blocklist',
            (false, false) => 'Remove from queue',
          },
      options: const [
        AppConfirmOption(
          key: 'removeFromClient',
          label: 'Delete from download client',
          subtitle:
              'Also removes the files that have been downloaded so far. This '
              'cannot be undone.',
          initialValue: true,
        ),
        AppConfirmOption(
          key: 'blocklist',
          label: 'Blocklist this release',
          subtitle: 'Stops it being grabbed again, so a search finds another.',
        ),
      ],
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      service: serviceType.service,
      action: () => ref
          .read(connectionArrServiceProvider((serviceType, instanceId)))
          .removeFromQueue(
            recordId,
            removeFromClient: result.option('removeFromClient'),
            blocklist: result.option('blocklist'),
          ),
      successMessage: result.option('blocklist')
          ? 'Removed and blocklisted'
          : 'Removed from queue',
      failureMessage: 'Could not remove from queue',
    );
  }

  /// Blocklists the release, keeping any files, and requests another search.
  static Future<void> blocklistAndRetry(
    BuildContext context,
    WidgetRef ref, {
    required ServiceType serviceType,
    required String instanceId,
    required int recordId,
    required String title,
    String? downloadId,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Try another download?',
      message:
          '$title will be blocklisted, and a new search will be requested. '
          'Any files already downloaded stay in your download client.',
      icon: Icons.refresh_rounded,
      confirmLabel: 'Try another download',
      enterConfirms: true,
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      service: serviceType.service,
      action: () => retryQueueDownload(
        ref.read(connectionArrServiceProvider((serviceType, instanceId))),
        recordId,
        expectedDownloadId: downloadId,
      ),
      successMessage: 'Retry requested. Downloaded files kept.',
      failureMessage: 'Could not try another download',
    );
  }

  /// Removes a release from the blocklist so it can be grabbed again.
  static Future<void> removeFromBlocklist(
    BuildContext context,
    WidgetRef ref, {
    required ServiceType serviceType,
    required String instanceId,
    required int recordId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Remove from blocklist?',
      message: '$title becomes eligible to be grabbed again.',
      icon: Icons.playlist_add_check_rounded,
      confirmLabel: 'Remove from blocklist',
      enterConfirms: true,
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      service: serviceType.service,
      action: () => ref
          .read(connectionArrServiceProvider((serviceType, instanceId)))
          .deleteBlocklistItem(recordId),
      successMessage: 'Removed from blocklist',
      failureMessage: 'Could not remove from blocklist',
    );
  }

  /// Approves a request that is waiting on somebody.
  ///
  /// This closes the loop the screen has always half-shown: `resolveRequestStatus`
  /// already tones a pending request `warning` precisely to say it needs a
  /// person, and until now the only way to be that person was to leave for the
  /// Seerr web UI.
  ///
  /// The confirmation says where the request goes ([SeerrApproveTarget]): the
  /// server by name, and in one clause when Cupola has no connection to it.
  /// It used to say "the service that handles it" whichever that was, a 4K
  /// server and one known only to Seerr included. [request] is the record
  /// when the caller holds it; otherwise it is read from Seerr by
  /// [requestId] first.
  ///
  /// Answers what a row may say once it went through (`Approved · sent to
  /// Radarr`), or null when it did not: refused, overtaken or cancelled.
  static Future<String?> approveRequest(
    BuildContext context,
    WidgetRef ref, {
    required String instanceId,
    required int requestId,
    required String title,
    SeerrRequest? request,
  }) async {
    if (!_decides(context, ref, instanceId)) return null;
    // Captured before any wait: the approval outlives the control that
    // started it, and the notifier is the container's, not the widget's.
    final approvals = ref.read(requestAnswersInFlightProvider.notifier);
    final key = (instanceId: instanceId, requestId: requestId);
    // A second tap while an answer to this request is still being read or
    // sent does nothing.
    var owned = approvals.begin(key, RequestAnswerPhase.checking);
    if (!owned) return null;
    try {
      final settings = ref.read(currentSettingsProvider);
      final read = await readSeerrApproveTarget(
        ref,
        instanceId: instanceId,
        requestId: requestId,
        request: request,
      );
      // Idle behind the sheet or the dialog, which are modal: the control is
      // not busy while a person decides.
      approvals.end(key);
      owned = false;
      if (!context.mounted) return null;

      String connectionTitle(ServiceInstance connection) => settings
          .connectionTitle(connection.id, connection.service, joiner: ' ');
      final readRequest = read.request;
      final target = read.target;
      final servers = read.servers;
      ApproveChoice? choice;
      final String approved;
      if (readRequest != null &&
          target != null &&
          target.server != null &&
          servers != null) {
        // Where it goes is known: the person may send it elsewhere first.
        final connections = settings.configuredInstancesOf(target.arr);
        choice = await showApproveRequestSheet(
          context,
          instanceId: instanceId,
          title: title,
          request: readRequest,
          target: target,
          servers: servers,
          connections: connections,
          connectionTitle: connectionTitle,
        );
        if (choice == null) return null;
        approved = target
            .sentTo(
              choice.server,
              connections: connections,
              profileId: choice.profileId,
              rootFolder: choice.rootFolder,
            )
            .approvedLine(connectionTitle: connectionTitle);
      } else {
        final confirmation = _approveConfirmation(
          read,
          title: title,
          connectionTitle: connectionTitle,
        );
        approved = confirmation.approved;
        final result = await showAppConfirmDialog(
          context: context,
          title: 'Approve this request?',
          message: confirmation.message,
          icon: Icons.check_circle_outline_rounded,
          confirmLabel: 'Approve request',
          enterConfirms: true,
        );
        if (!result.confirmed) return null;
      }

      if (!context.mounted) return null;
      owned = approvals.begin(key, RequestAnswerPhase.approving);
      if (!owned) return null;

      final done = await _run(
        context,
        ref,
        service: ServiceKey.seerr,
        action: () async {
          final service = ref.read(seerrServiceForProvider(instanceId));
          if (choice case (:final server, :final profileId, :final rootFolder)
              when readRequest != null &&
                  target != null &&
                  approveChoiceChanges(target, choice)) {
            // Sent elsewhere first, then approved: Seerr hands the request
            // on at the approval, with what it carries then.
            await service.updateRequest(
              requestId,
              seerrRequestUpdateBody(
                readRequest,
                server: server,
                profileId: profileId,
                rootFolder: rootFolder,
              ),
            );
          }
          await service.approveRequest(requestId);
        },
        successMessage: 'Request approved',
        failureMessage: 'Could not approve this request',
        invalidateRequests: true,
      );
      return done ? approved : null;
    } finally {
      // Only an approval this call still holds: never another tap's.
      if (owned) approvals.end(key);
    }
  }

  /// Whether the Seerr [instanceId] names lets this app decide on its
  /// requests, said on a toast when it does not: the account may not approve
  /// there. Every Approve and Decline in the app comes through here, so a
  /// control drawn before the account's permissions changed cannot send a
  /// decision the server would refuse.
  static bool _decides(BuildContext context, WidgetRef ref, String instanceId) {
    final verdict = ref
        .read(roleGateProvider(instanceId))
        .operatorAction(SeerrAbility.approve);
    if (verdict.acts) return true;
    final reason = verdict.reason;
    if (reason != null) SnackBarHelper.info(context, reason);
    return false;
  }

  /// What the approve confirmation says when there is no server to show in
  /// the sheet, from what [read] got within one [seerrTargetReadLimit], and
  /// what the row says once it is approved.
  static ({String message, String approved}) _approveConfirmation(
    SeerrApproveRead read, {
    required String title,
    required String Function(ServiceInstance connection) connectionTitle,
  }) {
    final target = read.target;
    if (target == null) {
      // Not even its kind is known: the approval still goes where Seerr
      // sends it, and that is all that can be said.
      return (
        message:
            '$title goes to the server Seerr sends it to and starts '
            'downloading.',
        approved: 'Approved',
      );
    }
    return (
      message: target.confirmation(title, connectionTitle: connectionTitle),
      approved: target.approvedLine(connectionTitle: connectionTitle),
    );
  }

  /// Declines a request, leaving the media alone. True when it went
  /// through.
  ///
  /// Busy like an approval: while the decline is sent, and while an answer to
  /// the same request is on its way, a second tap does nothing.
  static Future<bool> declineRequest(
    BuildContext context,
    WidgetRef ref, {
    required String instanceId,
    required int requestId,
    required String title,
  }) async {
    if (!_decides(context, ref, instanceId)) return false;
    // Captured before any wait, like the approval's.
    final answers = ref.read(requestAnswersInFlightProvider.notifier);
    final key = (instanceId: instanceId, requestId: requestId);
    if (answers.isInFlight(key)) return false;
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Decline this request?',
      message:
          '$title will not be downloaded. The request stays on record as '
          'declined.',
      icon: Icons.cancel_outlined,
      confirmLabel: 'Decline request',
    );

    if (!result.confirmed) return false;
    if (!context.mounted) return false;
    if (!answers.begin(key, RequestAnswerPhase.declining)) return false;

    try {
      return await _run(
        context,
        ref,
        service: ServiceKey.seerr,
        action: () => ref
            .read(seerrServiceForProvider(instanceId))
            .declineRequest(requestId),
        successMessage: 'Request declined',
        failureMessage: 'Could not decline this request',
        invalidateRequests: true,
      );
    } finally {
      answers.end(key);
    }
  }

  /// Runs a mutation, reports it, and refreshes the feed.
  ///
  /// The failure message names what did not happen rather than echoing a Dio
  /// exception: `'Search failed: $error'` was the previous house style and it
  /// surfaced transport internals to someone who wanted to know whether their
  /// download was gone.
  static Future<bool> _run(
    BuildContext context,
    WidgetRef ref, {
    required ServiceKey service,
    required Future<void> Function() action,
    required String successMessage,
    required String failureMessage,

    /// Seerr requests arrive through a separately cached provider, so bumping
    /// the feed version alone re-runs the merge over the same stale list. The
    /// whole family goes, not just the acted-on connection: the lens's own
    /// entry collapses onto the plain provider, so the two have to be dropped
    /// together or the feed re-reads one of them stale.
    bool invalidateRequests = false,
  }) async {
    try {
      await action();
      if (context.mounted) SnackBarHelper.success(context, successMessage);
    } on SeerrRequestConflict catch (conflict) {
      // Deliberately not a `return`: the action did not fail, it was overtaken.
      // The stale thing is the list on screen, so this falls through to the
      // refresh below instead of leaving a row the server no longer agrees with.
      if (context.mounted) SnackBarHelper.error(context, '$conflict');
      _refresh(ref, invalidateRequests: invalidateRequests);
      return false;
    } catch (error) {
      // Why, in the classified words: a refusal is not an outage, and the
      // toast used to guess "may be unreachable" for both.
      if (context.mounted) {
        SnackBarHelper.error(
          context,
          error is QueueRetryException
              ? error.message
              : '$failureMessage. ${writeFailureReason(service, error)}',
          cause: error is QueueRetrySearchFailed ? error.cause : error,
        );
        if (error is QueueRetrySearchFailed) {
          _refresh(ref, invalidateRequests: invalidateRequests);
        }
      }
      return false;
    }
    _refresh(ref, invalidateRequests: invalidateRequests);
    return true;
  }

  /// Every list the write may have changed, read again.
  static void _refresh(WidgetRef ref, {required bool invalidateRequests}) {
    if (invalidateRequests) {
      invalidateSeerrRequests(ref.container);
    }
    ref.read(activityRefreshVersionProvider.notifier).state++;
  }
}

/// One answer, named by the Seerr it is sent to and the request's id there.
typedef RequestAnswerKey = ({String instanceId, int requestId});

/// Where an answer to a request is between its tap and its reply.
enum RequestAnswerPhase {
  /// Reading where the request goes, before the confirmation opens.
  checking('Checking where it goes'),

  /// The approval itself, sent and not yet answered.
  approving('Approving'),

  /// The decline itself, sent and not yet answered.
  declining('Declining');

  const RequestAnswerPhase(this.spoken);

  /// What a screen reader hears of the busy control.
  final String spoken;

  /// Whether the Approve control is the busy one: the two phases of an
  /// approval, as against a decline.
  bool get isApproval => this != declining;
}

/// The answers in flight, and how far each has got.
///
/// What makes the tapped control busy at once, the other one of the pair
/// quiet, and a second tap a no-op: an approval used to read for up to eight
/// seconds with nothing on screen, and every tap meanwhile started another
/// read and, in the end, another confirmation.
class RequestAnswersInFlight
    extends Notifier<Map<RequestAnswerKey, RequestAnswerPhase>> {
  @override
  Map<RequestAnswerKey, RequestAnswerPhase> build() => const {};

  /// Whether an answer to [key] is on its way, in any phase.
  bool isInFlight(RequestAnswerKey key) => state.containsKey(key);

  /// Marks [key] as at [phase]. False, and nothing changes, when it is
  /// already in flight.
  bool begin(RequestAnswerKey key, RequestAnswerPhase phase) {
    if (state.containsKey(key)) return false;
    state = {...state, key: phase};
    return true;
  }

  /// Marks [key] as done. Safe to call when it is not in flight.
  void end(RequestAnswerKey key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
  }
}

final requestAnswersInFlightProvider =
    NotifierProvider<
      RequestAnswersInFlight,
      Map<RequestAnswerKey, RequestAnswerPhase>
    >(RequestAnswersInFlight.new);
