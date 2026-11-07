import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/home/domain/continue_watching.dart';
import 'package:cupola/features/home/presentation/widgets/continue_watching_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/jellyfin/data/media_browser_client.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/stream_overview_provider.dart';

/// What a media server says about watching, beside who is watching now: the
/// shelves that left the library page (decision `P-stream-library-browse`).
///
/// Drawn whole in the server's Activity, the detail, and as a rail each on its
/// Overview, the glance. Plex keeps its own word for the first: its on deck is
/// what is in progress and what is up next at once, so it has no separate
/// Next up.
enum StreamWatchingShelf {
  continueWatching,
  nextUp,
  recentlyAdded;

  /// The shelf's heading on [service].
  String titleOn(ServiceKey service) => switch (this) {
    continueWatching when service == ServiceKey.plex => 'On deck',
    continueWatching => 'Continue watching',
    nextUp => 'Next up',
    recentlyAdded => 'Recently added',
  };

  /// Whether the shelf is a watch state, which on Jellyfin and Emby needs the
  /// household member it is read for.
  bool get isPerViewer => this != recentlyAdded;
}

/// The shelves [service] draws, in the order a person asks them.
List<StreamWatchingShelf> streamWatchingShelvesOf(ServiceKey service) =>
    service == ServiceKey.plex
    ? const [
        StreamWatchingShelf.continueWatching,
        StreamWatchingShelf.recentlyAdded,
      ]
    : StreamWatchingShelf.values;

/// The tab a shelf's heading leads to: the server's Activity.
ServiceTab streamWatchingTabOf(ServiceKey service) =>
    service == ServiceKey.plex ? ServiceTab.activities : ServiceTab.activity;

/// One shelf of one connection.
typedef StreamWatchingKey = ({
  ServiceKey service,
  String instanceId,
  StreamWatchingShelf shelf,
});

/// How many rows a shelf asks for: what the Activity draws whole, and the
/// Overview's rail the first of.
const int streamWatchingLimit = 12;

/// A shelf, read from its connection, each title once.
///
/// Throws what the client throws: a server that did not answer, and on
/// Jellyfin or Emby `JellyfinViewerRequired` for a watch state with no
/// household member chosen, which the shelf draws as the question it is.
final streamWatchingProvider = FutureProvider.autoDispose
    .family<List<StreamItem>, StreamWatchingKey>((ref, key) async {
      final client = ref.watch(
        streamClientForProvider((
          service: key.service,
          instanceId: key.instanceId,
        )),
      );
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      final items = switch (key.shelf) {
        StreamWatchingShelf.continueWatching =>
          await client.getContinueWatching(
            count: streamWatchingLimit,
            cancelToken: cancelToken,
          ),
        StreamWatchingShelf.nextUp => await client.getNextUp(
          count: streamWatchingLimit,
          cancelToken: cancelToken,
        ),
        StreamWatchingShelf.recentlyAdded => await client.getRecentlyAdded(
          count: streamWatchingLimit,
          cancelToken: cancelToken,
        ),
      };
      return streamOnDeckPreview(items, limit: streamWatchingLimit);
    }, retry: noProviderRetry);

/// What a shelf says when it holds nothing: the server answered, and this is
/// its ordinary state, never a fault.
String streamWatchingEmptyLine(StreamWatchingShelf shelf) => switch (shelf) {
  StreamWatchingShelf.continueWatching => 'Nothing part-watched',
  StreamWatchingShelf.nextUp => 'Nothing up next',
  StreamWatchingShelf.recentlyAdded => 'Nothing added lately',
};

/// What is lost when a shelf did not load, for the failure line.
String _consequenceOf(StreamWatchingShelf shelf, ServiceKey service) =>
    switch (shelf) {
      StreamWatchingShelf.recentlyAdded => 'what was added is not shown',
      _ => '${shelf.titleOn(service).toLowerCase()} is not shown',
    };

/// The Activity's shelf: its heading, then its rows whole.
///
/// What is in progress and what is up next are rows with their picture and
/// how far in (the Home's own `ContinueWatchingRow`, so the two read alike);
/// what was added is a grid of posters.
class StreamWatchingSection extends ConsumerWidget {
  const StreamWatchingSection({
    super.key,
    required this.service,
    required this.instanceId,
    required this.shelf,
  });

  final ServiceKey service;

  /// The connection read; empty is the lens.
  final String instanceId;
  final StreamWatchingShelf shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (service: service, instanceId: instanceId, shelf: shelf);
    final value = ref.watch(streamWatchingProvider(key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: shelf.titleOn(service), showChevron: false),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: switch (value) {
            AsyncValue(:final error?) when !value.hasValue =>
              error is JellyfinViewerRequired
                  ? _ViewerQuestion(service: service, instanceId: instanceId)
                  : InlineErrorRetry.flush(
                      message: sectionFailureMessage(
                        service,
                        error,
                        consequence: _consequenceOf(shelf, service),
                      ),
                      error: error,
                      service: service,
                      instanceId: instanceId,
                      onRetry: () =>
                          ref.invalidate(streamWatchingProvider(key)),
                    ),
            AsyncValue(:final value?) when value.isEmpty =>
              ServiceOverviewEmpty(
                icon: shelf == StreamWatchingShelf.recentlyAdded
                    ? Icons.new_releases_outlined
                    : Icons.play_circle_outline_rounded,
                label: streamWatchingEmptyLine(shelf),
              ),
            AsyncValue(:final value?) =>
              shelf == StreamWatchingShelf.recentlyAdded
                  ? _PosterGrid(
                      service: service,
                      instanceId: instanceId,
                      items: value,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < value.length; i++)
                          ContinueWatchingRow(
                            row: (
                              service: service,
                              instanceId: instanceId,
                              connectionName: null,
                              item: value[i],
                            ),
                            divided: i > 0,
                          ),
                      ],
                    ),
            _ => AppSkeleton.listRows(count: 3, rowHeight: 87),
          },
        ),
      ],
    );
  }
}

/// A watch state with nobody to read it for: the question, and the way to
/// answer it. Not a fault and not an empty shelf.
class _ViewerQuestion extends StatelessWidget {
  const _ViewerQuestion({required this.service, required this.instanceId});

  final ServiceKey service;
  final String instanceId;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.person_outline_rounded,
            size: 18,
            color: room.inkSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Choose whose watch state to show',
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              visualDensity: VisualDensity.standard,
            ),
            onPressed: () => context.push(
              instanceId.isEmpty
                  ? ServiceRoutes.settingsFor(service)
                  : ServiceRoutes.settingsForConnection(service, instanceId),
            ),
            child: const Text('Pick a viewer'),
          ),
        ],
      ),
    );
  }
}

/// What was added, as posters, three to a row on a phone.
class _PosterGrid extends ConsumerWidget {
  const _PosterGrid({
    required this.service,
    required this.instanceId,
    required this.items,
  });

  final ServiceKey service;
  final String instanceId;
  final List<StreamItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(
      streamClientForProvider((service: service, instanceId: instanceId)),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = MediaGrid.columnsFor(constraints.maxWidth, 3);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          itemCount: items.length,
          gridDelegate: MediaPosterCaption.gridDelegate(
            context,
            width: constraints.maxWidth,
            columns: columns,
          ),
          itemBuilder: (context, index) => _Poster(
            service: service,
            instanceId: instanceId,
            item: items[index],
            image: _posterOf(client, items[index]),
            // Its own namespace: the library grid of a sibling branch draws
            // the same titles, and two live Heroes sharing a tag assert.
            heroTag:
                'stream_activity_${service.name}_${items[index].id}_$index',
          ),
        );
      },
    );
  }
}

StreamImageSource? _posterOf(StreamServerClient client, StreamItem item) {
  final path = item.posterPath;
  return path == null || path.isEmpty
      ? null
      : client.imageFor(path, width: 360);
}

/// One poster that opens its title, named as one button.
class _Poster extends StatelessWidget {
  const _Poster({
    required this.service,
    required this.instanceId,
    required this.item,
    required this.image,
    required this.heroTag,
  });

  final ServiceKey service;
  final String instanceId;
  final StreamItem item;
  final StreamImageSource? image;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () =>
          context.openStreamItem(service, item, instanceId: instanceId),
      semanticLabel: item.title,
      semanticValue: item.year == null ? null : '${item.year}',
      excludeChildSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: MediaPosterCard(
              heroTag: heroTag,
              imageUrl: image?.url,
              imageHeaders: image?.headers,
              fallbackIcon: streamItemGlyph(item.kind),
            ),
          ),
          const SizedBox(height: MediaPosterCaption.gap),
          MediaPosterCaption(
            title: item.title,
            subtitle: item.year == null ? '' : '${item.year}',
          ),
        ],
      ),
    );
  }
}

/// The Overview's glance at one shelf: a rail under its heading, which leads
/// to the Activity where the shelf is whole.
///
/// In progress and up next are wide pictures with how far in; what was added
/// is posters. A shelf that cannot be read for want of a viewer, or that is
/// empty, says so in one quiet line rather than leaving a gap.
class StreamWatchingRail extends ConsumerWidget {
  const StreamWatchingRail({
    super.key,
    required this.service,
    required this.instanceId,
    required this.shelf,
  });

  final ServiceKey service;
  final String instanceId;
  final StreamWatchingShelf shelf;

  /// How many the rail shows of what the shelf read.
  static const int length = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (service: service, instanceId: instanceId, shelf: shelf);
    final value = ref.watch(streamWatchingProvider(key));
    final wide = shelf != StreamWatchingShelf.recentlyAdded;
    final tab = streamWatchingTabOf(service);

    return ServiceOverviewSection.bleed(
      service: service,
      title: shelf.titleOn(service),
      destination: tabsFor(service)?.contains(tab) ?? false ? tab : null,
      child: switch (value) {
        AsyncValue(:final error?) when !value.hasValue =>
          error is JellyfinViewerRequired
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: _ViewerQuestion(
                    service: service,
                    instanceId: instanceId,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: InlineErrorRetry.flush(
                    message: sectionFailureMessage(
                      service,
                      error,
                      consequence: _consequenceOf(shelf, service),
                    ),
                    error: error,
                    service: service,
                    instanceId: instanceId,
                    onRetry: () => ref.invalidate(streamWatchingProvider(key)),
                  ),
                ),
        AsyncValue(:final value?) when value.isEmpty => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ServiceOverviewEmpty(
            icon: wide
                ? Icons.play_circle_outline_rounded
                : Icons.new_releases_outlined,
            label: streamWatchingEmptyLine(shelf),
          ),
        ),
        AsyncValue(:final value?) => _Rail(
          service: service,
          instanceId: instanceId,
          shelf: shelf,
          items: value.take(length).toList(growable: false),
        ),
        _ => AppSkeleton.posterRow(height: wide ? 99 : 138),
      },
    );
  }
}

class _Rail extends ConsumerWidget {
  const _Rail({
    required this.service,
    required this.instanceId,
    required this.shelf,
    required this.items,
  });

  final ServiceKey service;
  final String instanceId;
  final StreamWatchingShelf shelf;
  final List<StreamItem> items;

  /// A wide tile: a 16:9 picture, the bar, and two caption lines.
  static const Size _wide = Size(176, 99);

  /// A poster tile.
  static const Size _poster = Size(96, 138);

  /// The progress bar's height (`HomeRowBar`).
  static const double _bar = 4;

  /// Two lines in the meta role, 18 each, and 2 for the rounding a large
  /// reading size lays them out with (measured: 0.4pt over at the clamp).
  static const double _captions = 38;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(
      streamClientForProvider((service: service, instanceId: instanceId)),
    );
    final wide = shelf != StreamWatchingShelf.recentlyAdded;
    final picture = wide ? _wide : _poster;
    return SizedBox(
      // The picture, the bar and its gap for a wide tile, the gap, and two
      // caption lines in the meta role (13/18), grown by the reading size so
      // the captions are not clipped.
      height: TextScaleMetrics.boxHeight(
        context,
        base:
            picture.height +
            (wide ? AppSpacing.xs + _bar : 0) +
            AppSpacing.xs +
            _captions,
        textHeight: _captions,
      ),
      // Laid out at the clamp the box grew by, or the rail is sized for one
      // scale and painted at another.
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: ListView.separated(
          controller: RailArrows.controllerOf(context),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AppSpacing.carouselGap),
          itemBuilder: (context, index) => _RailTile(
            service: service,
            instanceId: instanceId,
            item: items[index],
            size: picture,
            wide: wide,
            image: _imageOf(client, items[index], wide: wide),
            heroTag:
                'stream_overview_${shelf.name}_${service.name}_'
                '${items[index].id}_$index',
          ),
        ),
      ),
    );
  }

  /// A wide tile takes the item's own picture (an episode's still, which the
  /// servers serve wide) and a movie its backdrop; a poster tile its poster.
  static StreamImageSource? _imageOf(
    StreamServerClient client,
    StreamItem item, {
    required bool wide,
  }) {
    if (!wide) return _posterOf(client, item);
    final isEpisode = item.kind == StreamItemKind.episode;
    final path = isEpisode
        ? (item.posterPath ?? item.backdropPath)
        : (item.backdropPath ?? item.posterPath);
    return path == null || path.isEmpty
        ? null
        : client.imageFor(path, width: 528);
  }
}

/// The tile's spoken value, or none when there is nothing to say.
String? _spoken(List<String?> parts) {
  final spoken = joinSpokenParts(parts);
  return spoken.isEmpty ? null : spoken;
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.service,
    required this.instanceId,
    required this.item,
    required this.size,
    required this.wide,
    required this.image,
    required this.heroTag,
  });

  final ServiceKey service;
  final String instanceId;
  final StreamItem item;
  final Size size;
  final bool wide;
  final StreamImageSource? image;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final title = wide ? resumeTitle(item) : item.title;
    final detail = wide
        ? joinDisplayParts([resumeDetail(item), ?resumeLeft(item)])
        : (item.year == null ? '' : '${item.year}');
    final progress = wide ? item.resumeProgress : null;

    return SizedBox(
      width: size.width,
      child: PressableScale(
        onTap: () =>
            context.openStreamItem(service, item, instanceId: instanceId),
        semanticLabel: title,
        semanticValue: _spoken([
          if (detail.isNotEmpty) spokenFromDotted(detail),
          if (progress != null) '${(progress * 100).round()} percent watched',
        ]),
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.fromSize(
              size: size,
              child: wide
                  ? ClipRRect(
                      borderRadius: AppRadius.borderRadiusSm,
                      child: image == null
                          ? ColoredBox(
                              color: room.fillQuiet,
                              child: Icon(
                                service.icon,
                                size: 20,
                                color: room.inkSecondary,
                              ),
                            )
                          : ContentCard(
                              imageUrl: image!.url,
                              httpHeaders: image!.headers,
                            ),
                    )
                  : MediaPosterCard(
                      heroTag: heroTag,
                      imageUrl: image?.url,
                      imageHeaders: image?.headers,
                    ),
            ),
            if (progress != null) ...[
              const SizedBox(height: AppSpacing.xs),
              // Ink: how far somebody got is not a status.
              HomeRowBar(value: progress, color: room.ink),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta
                  .weight(FontWeight.w600)
                  .copyWith(color: room.ink),
            ),
            if (detail.isNotEmpty)
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta.copyWith(color: room.inkSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
