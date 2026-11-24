import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/media/domain/media_copy_panel.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Where the lead stands when a Radarr copy needs something: what is
/// happening to it, and what can be done from here.
///
/// It reads what the copy's row does not carry: the download's record while
/// there is one, and whether a search for it is running, asked again while it
/// runs. [onChanged] is told after anything here changed the copy, so the
/// page reads it again.
class MediaCopyPanelCard extends ConsumerWidget {
  const MediaCopyPanelCard({
    super.key,
    required this.connection,
    required this.name,
    required this.movie,
    required this.status,
    required this.onChanged,
    this.onOpenDownload,
  });

  final ServiceInstance connection;

  /// The connection's name in a sentence: `Radarr 4K`.
  final String name;
  final RadarrMovie movie;
  final MediaStatusInfo status;
  final VoidCallback onChanged;

  /// Opens the download this copy is, on its own page, when the queue holds
  /// it. Null when there is none to open.
  final VoidCallback? onOpenDownload;

  ({String connectionId, int movieId}) get _copy =>
      (connectionId: connection.id, movieId: movie.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloading = status.pipeline != null;
    final record = downloading
        ? ref.watch(mediaRadarrQueueProvider(_copy)).value?.firstOrNull
        : null;
    // A search ending changes what the copy holds: the page reads it again.
    ref.listen(mediaRadarrSearchProvider(_copy), (previous, next) {
      if (previous?.value != null && next.hasValue && next.value == null) {
        onChanged();
      }
    });
    final searchedAt = downloading
        ? null
        : ref.watch(mediaRadarrSearchProvider(_copy)).value;
    final panel = mediaCopyPanel(
      name: name,
      status: status,
      monitored: movie.monitored,
      record: record,
      searchedAt: searchedAt,
    );
    return _Panel(
      panel: panel,
      onAction: (action) => _act(context, ref, action, record),
      onOpenDownload: onOpenDownload,
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    MediaCopyAction action,
    Map<String, dynamic>? record,
  ) async {
    final radarr = ref.read(radarrServiceForProvider(connection.id));
    final recordId = intOrNull(record?['id']);
    final release = stringOrNull(record?['title']) ?? movie.title;
    switch (action) {
      case MediaCopyAction.tryAnother when recordId != null:
        await ActivityActions.blocklistAndRetry(
          context,
          ref,
          serviceType: ServiceType.movies,
          instanceId: connection.id,
          recordId: recordId,
          title: release,
          downloadId: stringOrNull(record?['downloadId']),
        );
        onChanged();
      case MediaCopyAction.removeDownload when recordId != null:
        await ActivityActions.removeFromQueue(
          context,
          ref,
          serviceType: ServiceType.movies,
          instanceId: connection.id,
          recordId: recordId,
          title: release,
        );
        onChanged();
      case MediaCopyAction.finishImport:
        final folder = manualImportFolderFromOutputPath(
          stringOrNull(record?['outputPath']),
        );
        await context.push(
          manualImportLocation(
            folder == null ? manualImportReviewPath : manualImportBrowsePath,
            ServiceKey.radarr,
            targetId: movie.id,
            folderPath: folder,
            instanceId: connection.id,
          ),
        );
        onChanged();
      case MediaCopyAction.automaticSearch:
        try {
          await radarr.searchMovie(movie.id);
          ref.invalidate(mediaRadarrSearchProvider(_copy));
        } catch (error) {
          if (context.mounted) {
            SnackBarHelper.error(
              context,
              'Could not ask $name to search',
              detail: error,
            );
          }
        }
      case MediaCopyAction.chooseRelease:
        await showReleaseSearch(
          context,
          ref,
          ReleaseSearchTarget.movie(
            movieId: movie.id,
            label: truncateTitle(movie.title),
          ).stampedWith(connection.id),
        );
      case MediaCopyAction.monitor:
        try {
          await radarr.updateMovieMonitored(movie.id, true);
          onChanged();
        } catch (error) {
          if (context.mounted) {
            SnackBarHelper.error(
              context,
              'Could not monitor it in $name',
              detail: error,
            );
          }
        }
      // The download's record has not arrived: nothing to act on yet.
      case MediaCopyAction.tryAnother || MediaCopyAction.removeDownload:
        break;
    }
  }
}

/// The panel itself: a slab with the headline, the source and the status,
/// the sentence, the release, the bar, then the actions.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.panel,
    required this.onAction,
    this.onOpenDownload,
  });

  final MediaCopyPanel panel;
  final ValueChanged<MediaCopyAction> onAction;
  final VoidCallback? onOpenDownload;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    Color tone(StatusTone tone) =>
        statusToneColor(scheme, tone, surface: room.door);
    final fault = panel.tone;
    final actions = panel.actions;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: room.door,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (fault != null) ...[
                Icon(
                  fault == StatusTone.error
                      ? Icons.cloud_off_rounded
                      : Icons.warning_amber_rounded,
                  size: 20,
                  color: tone(fault),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    panel.headline,
                    style: AppType.section.copyWith(
                      color: fault == null ? room.ink : tone(fault),
                    ),
                  ),
                ),
              ),
              if (panel.busy)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (panel.source case final source?)
            Text(
              source,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          if (panel.status case final status?) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: tone(StatusTone.info),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    status,
                    style: AppType.label.copyWith(color: tone(StatusTone.info)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            panel.sentence,
            style: AppType.meta
                .weight(FontWeight.w400)
                .copyWith(color: room.inkSecondary),
          ),
          if (panel.release case final release?) ...[
            const SizedBox(height: AppSpacing.sm),
            MachineName.release(release),
          ],
          if (panel.progress case final progress?) ...[
            const SizedBox(height: AppSpacing.md),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: AppRadius.borderRadiusXs,
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 4,
                  backgroundColor: room.fillControl,
                  valueColor: AlwaysStoppedAnimation(tone(StatusTone.info)),
                ),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            // An amber fault's remedy is the one amber fill; anything else
            // here is quiet.
            if (fault == StatusTone.warning)
              FilledButton(
                onPressed: () => onAction(actions.first),
                style: remedyFillStyle(context),
                child: Text(actions.first.label),
              )
            else
              OutlinedButton.icon(
                onPressed: () => onAction(actions.first),
                icon: Icon(_iconOf(actions.first), size: 18),
                label: Text(actions.first.label),
              ),
            if (panel.consequence case final consequence?) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                consequence,
                style: AppType.meta
                    .weight(FontWeight.w400)
                    .copyWith(color: room.inkTertiary),
              ),
            ],
            for (final action in actions.skip(1)) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => onAction(action),
                icon: Icon(_iconOf(action), size: 18),
                label: Text(action.label),
              ),
            ],
          ],
          // The download's own page, quiet, after the panel's ways out.
          if (onOpenDownload case final open?) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: open,
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              label: const Text('Open download'),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconOf(MediaCopyAction action) => switch (action) {
    MediaCopyAction.tryAnother => Icons.refresh_rounded,
    MediaCopyAction.removeDownload => Icons.delete_outline_rounded,
    MediaCopyAction.finishImport => Icons.drive_file_move_rounded,
    MediaCopyAction.automaticSearch => Icons.search_rounded,
    MediaCopyAction.chooseRelease => Icons.list_rounded,
    MediaCopyAction.monitor => Icons.bookmark_add_outlined,
  };
}
