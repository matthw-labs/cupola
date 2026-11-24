/// The ways out of a stuck download, taken: one executor for its card in
/// Needs you and its row in the Home's Downloads, so the same download does
/// the same thing and says the same note in both places.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/api/base_arr_service.dart' show ArrActivityMixin;
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/activity/data/acted_faults.dart';
import 'package:cupola/features/activity/data/queue_retry.dart';
import 'package:cupola/features/activity/domain/download_page.dart'
    show downloadClientOf;
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/domain/stuck_download_fault.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart'
    show connectionArrServiceProvider;
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show bringUnderLens;
import 'package:cupola/features/services/presentation/kept_waiting_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart'
    show writeFailureReason;
import 'package:cupola/features/settings/domain/service_key.dart';

/// Takes [stuckActionsFor]'s ways out for the widget that offers them.
///
/// Once one was taken, [actedFaultsProvider] holds what happened under
/// [stuckDownloadKey] until Activity or the Home is read again; Keep waiting's
/// note carries Undo ([undoKeepWaiting]).
mixin StuckActionTaker<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// The way out whose write is running, for its fill to say so.
  StuckAction? takingAction;

  /// The download's `keptWaitingKey`, which its note is kept under.
  String get stuckDownloadKey;

  Future<void> takeStuckAction(
    StuckAction action,
    ServiceQueueItem item,
  ) async {
    switch (action) {
      case StuckAction.openClient:
        final target = item.clientService ?? item.service;
        await bringUnderLens(
          ref,
          target,
          item.clientService == null ? item.instanceId : item.clientInstanceId,
        );
        if (!mounted) return;
        context.go(ServiceRoutes.forService(target));
        return;
      case StuckAction.keepWaiting:
        final now = ref.read(stallClockProvider)();
        final kept = ref
            .read(keptWaitingProvider.notifier)
            .keep(item, now: now);
        _acted(item, action, keptWaitingNote(kept.until, now: now));
        return;
      case StuckAction.remove:
        final ask = removeConfirmation(item);
        final answer = await showAppConfirmDialog(
          context: context,
          title: ask.title,
          message: ask.message,
          confirmLabel: ask.confirm,
          icon: Icons.delete_outline_rounded,
        );
        if (!answer.confirmed || !mounted) return;
        await _write(
          action,
          item,
          service: item.service,
          failure: "Could not remove ${item.sentenceTitle}'s download",
          call: () => _arr(item).removeFromQueue(
            int.parse(item.id),
            removeFromClient: true,
            blocklist: false,
          ),
        );
      case StuckAction.tryAnotherDownload:
        await _write(
          action,
          item,
          service: item.service,
          failure: 'Could not try another download',
          call: () => retryQueueDownload(
            _arr(item),
            int.parse(item.id),
            expectedDownloadId: item.downloadId,
          ),
        );
      case StuckAction.lookForPeers:
        await _write(
          action,
          item,
          service: ServiceKey.qbittorrent,
          failure: 'Could not ask the trackers again',
          call: () {
            final torrent = downloadClientOf(item)!;
            return ref
                .read(qbittorrentServiceForProvider(torrent.instanceId))
                .reannounce([torrent.id]);
          },
        );
    }
  }

  /// Keep waiting taken back: the stall counts again, and its remedy is
  /// drawn again.
  void undoKeepWaiting(ServiceQueueItem item) {
    ref.read(keptWaitingProvider.notifier).release(item);
    ref.read(actedFaultsProvider.notifier).forget(stuckDownloadKey);
  }

  ArrActivityMixin _arr(ServiceQueueItem item) => ref.read(
    connectionArrServiceProvider((_typeOf(item.service), item.instanceId)),
  );

  /// The call, its failure said with its cause, and the note once it is done.
  Future<void> _write(
    StuckAction action,
    ServiceQueueItem item, {
    required ServiceKey service,
    required String failure,
    required Future<void> Function() call,
  }) async {
    setState(() => takingAction = action);
    try {
      await call();
    } catch (error) {
      if (mounted) {
        setState(() => takingAction = null);
        if (error is QueueRetrySearchFailed) {
          _acted(item, action, 'Blocklisted\u00A0· Search could not start');
        }
        SnackBarHelper.error(
          context,
          error is QueueRetryException
              ? error.message
              : '$failure. ${writeFailureReason(service, error)}',
          cause: error is QueueRetrySearchFailed ? error.cause : error,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => takingAction = null);
    _acted(item, action, stuckActionNote(action, item));
  }

  void _acted(ServiceQueueItem item, StuckAction action, String note) {
    ref
        .read(actedFaultsProvider.notifier)
        .act(stuckDownloadKey, item: item, action: action, note: note);
    // The queue again, now that it changed: the fault goes, or stays and says
    // what it is. Keep waiting changes no queue, only what counts as a fault.
    if (action != StuckAction.keepWaiting) {
      for (final source in homeDownloadsSources) {
        ref.invalidate(source);
      }
    }
    ref.invalidate(dashboardDecisionSourceProvider(DecisionSource.queue));
  }
}

ServiceType _typeOf(ServiceKey service) => switch (service) {
  ServiceKey.sonarr => ServiceType.series,
  ServiceKey.lidarr => ServiceType.music,
  _ => ServiceType.movies,
};
