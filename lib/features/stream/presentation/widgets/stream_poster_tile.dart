import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/media_poster_caption.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/stream_overview_provider.dart';

/// One poster in a Stream library grid.
///
/// Composed from the app's existing tile parts rather than through
/// `MediaBrowseScaffold`, which cannot host a media server: its `idExtractor` is
/// typed `int` and feeds both the Hero tag and the route param, but a Jellyfin id
/// is a GUID and a Plex `ratingKey` is documented as an opaque string that only
/// *often* looks numeric. Its `imagesExtractor` also wants an arr-shaped `images`
/// JSON array, and its filter chips are a closed All/Available/Missing/In-Queue
/// vocabulary in which a null status silently classifies every item as *Missing*.
/// The paged-grid idiom in `discover_see_all_screen.dart` is the seam that fits,
/// and it needed no changes to take string ids. Its Hero tags are built by
/// interpolation.
///
/// **The watch state is the point of the tile.** A bare poster wall is the thing
/// the Stream library exists not to be, so an in-progress item carries a resume bar
/// and a partly-watched series carries its unplayed count. Those are the facts only
/// a media server holds.
class StreamPosterTile extends ConsumerWidget {
  const StreamPosterTile({
    super.key,
    required this.service,
    required this.item,
    required this.index,
    this.instanceId = '',
  });

  final ServiceKey service;

  /// The connection the item is on; empty is the active one. What the tile
  /// reads its artwork through and what its page opens on.
  final String instanceId;
  final StreamItem item;

  /// Position in the full list, included in the Hero tag.
  ///
  /// Two items can carry the same id across a lens change, and a duplicated Hero
  /// tag throws at flight time rather than degrading: the same reason
  /// `MediaGrid` and the discover see-all screen both include it.
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(
      streamClientForProvider((service: service, instanceId: instanceId)),
    );

    final poster = item.posterPath == null
        ? null
        : client.imageFor(item.posterPath!, width: 260);
    final heroTag = 'stream_${service.name}_${item.id}_$index';

    final progress = item.resumeProgress;
    final unplayed = item.unplayedChildCount;

    return Semantics(
      label: item.title,
      value: _spokenState(item),
      button: true,
      excludeSemantics: true,
      child: PressableScale(
        // A movie opens on its own page, this server's copy leading.
        onTap: () =>
            context.openStreamItem(service, item, instanceId: instanceId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: heroTag,
                    transitionOnUserGestures:
                        MediaPosterCard.flightOnUserGestures,
                    child: ContentCard(
                      imageUrl: poster?.url,
                      httpHeaders: poster?.headers,
                      paneTag: heroTag,
                      fallbackIcon: streamItemGlyph(item.kind),
                      badge: unplayed != null && unplayed > 0
                          ? _UnplayedBadge(count: unplayed)
                          : null,
                    ),
                  ),
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ResumeBar(progress: progress),
                    ),
                ],
              ),
            ),
            const SizedBox(height: MediaPosterCaption.gap),
            MediaPosterCaption(
              title: item.title,
              subtitle: item.year == null ? '' : '${item.year}',
            ),
          ],
        ),
      ),
    );
  }

  /// What the tile says after its title.
  ///
  /// A resume bar and a count badge are both purely visual, so without this a
  /// screen-reader user gets an unlabelled poster and none of the state that makes
  /// the Stream library different from an arr's.
  static String? _spokenState(StreamItem item) {
    final parts = <String>[];
    final progress = item.resumeProgress;
    if (progress != null) {
      parts.add('${spokenPercent(progress * 100)} watched');
    } else if (item.isPlayed) {
      parts.add('Watched');
    }
    final unplayed = item.unplayedChildCount;
    if (unplayed != null && unplayed > 0) {
      parts.add('$unplayed not played');
    }
    final year = item.year;
    if (year != null) parts.add('$year');
    return parts.isEmpty ? null : parts.join(', ');
  }
}

class _UnplayedBadge extends StatelessWidget {
  const _UnplayedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall!
            .weight(FontWeight.w600)
            .copyWith(color: colorScheme.onPrimary),
      ),
    );
  }
}

/// The resume position, as a hairline across the poster's foot.
///
/// Deliberately not a `LinearProgressIndicator`: this is a static reading of where
/// someone stopped, not work in flight, and an indeterminate-capable widget invites
/// the animation the state does not have.
class _ResumeBar extends StatelessWidget {
  const _ResumeBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadius.md),
      ),
      child: SizedBox(
        height: 3,
        child: Row(
          children: [
            Expanded(
              flex: (progress * 1000).round().clamp(1, 1000),
              // The plate's ink: the bar sits on artwork, which is dark in both
              // themes, and where someone stopped is a reading, not a service's
              // colour.
              child: const ColoredBox(color: AppColors.plateInk),
            ),
            Expanded(
              flex: (1000 - (progress * 1000).round()).clamp(0, 999),
              child: ColoredBox(
                color: Theme.of(
                  context,
                ).colorScheme.scrim.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
