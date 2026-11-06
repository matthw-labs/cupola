import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/domain/stream_web_url.dart';
import 'package:cupola/features/stream/presentation/play_with.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/stream_overview_provider.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_poster_tile.dart';

/// One item on a media server, at any depth of the tree.
///
/// **One screen for film, show, season, episode, album and track.** A Jellyfin
/// `BaseItemDto` and a Plex `Metadata` element describe all of those with the same
/// fields, which is a real structural difference from the arr side: Radarr, Sonarr
/// and Lidarr each needed their own model and their own detail screen. So this is a
/// single recursive route: a show lists its seasons, a season lists its episodes,
/// and each of those pushes this same screen again.
class StreamItemScreen extends ConsumerWidget {
  const StreamItemScreen({
    super.key,
    required this.service,
    required this.itemId,
    this.instanceId,
  });

  final ServiceKey service;
  final String itemId;

  /// The connection the item is on (`?i=`): null, or one that is not a
  /// connection of [service], reads the one the visit has in view, and then
  /// the active one, which is what a link with no connection means.
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Checked before the item provider is read, not after. This page is now a
    // route inside the Libraries branch and a deep link can land on it with the
    // server never set up, and `jellyfinItemProvider` / `plexItemProvider`
    // carry no `retry: noProviderRetry`, so the "not configured" throw would be
    // a *failed* provider retrying on a backoff that no waiting resolves.
    // Letting `AsyncValueWidget` catch the throw draws the same pixels and
    // leaves that timer running.
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(service)) {
      return AmbientScaffold(
        accent: service.accent,
        appBar: GlassAppBar.inPage(pageTitle: service.title),
        body: SafeArea(
          child: TitledBody(
            title: service.title,
            child: NotConfiguredPlaceholder.forService(service),
          ),
        ),
      );
    }

    final connection = streamInstanceOf(ref, service, instanceId);
    final itemKey = (service: service, instanceId: connection, itemId: itemId);
    final itemAsync = ref.watch(streamItemForProvider(itemKey));

    final title = itemAsync.value?.title ?? service.title;
    return AmbientScaffold(
      accent: service.accent,
      appBar: GlassAppBar.inPage(pageTitle: title),
      body: SafeArea(
        bottom: false,
        child: TitledBody(
          title: title,
          child: AsyncValueWidget<StreamItem?>(
            value: itemAsync,
            serviceName: service.title,
            onRetry: () => refreshStreamItem(ref, itemKey),
            isEmpty: (item) => item == null,
            emptyBuilder: const AppEmptyState(
              icon: Icons.help_outline_rounded,
              title: 'Not on the server',
              message:
                  'This item is no longer in the library, or the account this '
                  'connection uses cannot see it.',
            ),
            data: (item) =>
                _Body(service: service, instanceId: connection, item: item!),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.service,
    required this.instanceId,
    required this.item,
  });

  final ServiceKey service;
  final String instanceId;
  final StreamItem item;

  /// The poster's width beside the words: the library grid's tile, a little
  /// narrower, so the page reads as the tile it was opened from.
  static const double _posterWidth = 112;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final client = ref.watch(
      streamClientForProvider((service: service, instanceId: instanceId)),
    );
    final art = item.posterPath == null
        ? null
        : client.imageFor(item.posterPath!, width: 360);
    final overview = item.overview?.trim();

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: theme.textTheme.headlineSmall),
        if (item.subtitle != null && item.subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              item.subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        _StateRow(item: item, accent: service.accent),
      ],
    );

    // Flush to the window, each block inset on its own: `SectionHeader` brings
    // its own inset, and inside a padded list it stood a step in from the
    // poster and the grid it heads.
    return ListView(
      padding: EdgeInsets.only(
        top: AppSpacing.md,
        bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Head(item: item, art: art, words: words),
              const SizedBox(height: AppSpacing.lg),
              _HandoffButton(
                service: service,
                instanceId: instanceId,
                item: item,
              ),
              if (overview != null && overview.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(overview, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (item.kind.hasChildren) ...[
          const SizedBox(height: AppSpacing.xl),
          _Children(service: service, instanceId: instanceId, itemId: item.id),
        ],
      ],
    );
  }
}

/// The artwork and the words beside it, the way the item's own tile showed
/// it: a poster for a show or a season, a square for an album or a track, the
/// frame across the page for an episode, whose picture is a still.
///
/// With no artwork a show or an album keeps its plate, with the glyph of what
/// it is, so the page has the same shape whatever the server holds; an
/// episode without a still goes straight to its words. At a large reading size
/// the words go under the poster rather than into a third of the width.
class _Head extends StatelessWidget {
  const _Head({required this.item, required this.art, required this.words});

  final StreamItem item;
  final StreamImageSource? art;
  final Widget words;

  @override
  Widget build(BuildContext context) {
    final card = ContentCard(
      imageUrl: art?.url,
      httpHeaders: art?.headers,
      fallbackIcon: streamItemGlyph(item.kind),
    );
    // Decoration: the title beside it says what it shows.
    Widget plate(double aspectRatio) => ExcludeSemantics(
      child: AspectRatio(aspectRatio: aspectRatio, child: card),
    );

    if (item.kind == StreamItemKind.episode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (art != null) ...[
            plate(16 / 9),
            const SizedBox(height: AppSpacing.lg),
          ],
          words,
        ],
      );
    }

    final square =
        item.kind == StreamItemKind.album || item.kind == StreamItemKind.track;
    final poster = SizedBox(
      width: _Body._posterWidth,
      child: plate(square ? 1 : 2 / 3),
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          poster,
          const SizedBox(height: AppSpacing.lg),
          words,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        poster,
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: words),
      ],
    );
  }
}

/// Watch state, as chips.
///
/// This is the whole reason a Stream detail page is not a duplicate of Radarr's:
/// where the arr answers "do I own it", this answers "have *you* watched it, and
/// where did you stop".
///
/// **One perspective, never the household's.** The earlier wording here said
/// "has anyone watched it", which is a claim neither server supports: on Plex the
/// token *is* the user and there is no other viewpoint to read (decision 16), and
/// on Jellyfin the admin key must name a household member, so what comes back is
/// the configured viewer's state alone. A chip reading "Watched" means watched by
/// the person this connection speaks for.
class _StateRow extends StatelessWidget {
  const _StateRow({required this.item, required this.accent});

  final StreamItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final progress = item.resumeProgress;
    final unplayed = item.unplayedChildCount;
    final runtime = _runtimeLabel(item.runtimeMs);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (progress != null)
          TagChip(
            text: '${formatPercent(progress * 100)} watched',
            color: accent,
            icon: Icons.play_circle_outline_rounded,
          )
        else if (item.isPlayed)
          TagChip(
            text: 'Watched',
            color: accent,
            icon: Icons.check_circle_outline_rounded,
          ),
        if (unplayed != null && unplayed > 0)
          GenreChip(genre: '$unplayed not played'),
        if (runtime != null) GenreChip(genre: runtime),
        if (item.year != null) GenreChip(genre: '${item.year}'),
      ],
    );
  }

  /// Runtime from milliseconds: the unit `StreamItem` normalises to, because the
  /// two servers disagree natively (Jellyfin counts .NET ticks, Plex milliseconds
  /// for duration but epoch seconds for dates).
  static String? _runtimeLabel(int? ms) {
    if (ms == null || ms <= 0) return null;
    final label = formatRuntimeMinutes((ms / 60000).round());
    return label.isEmpty ? null : label;
  }
}

/// The handoff out to the real client.
///
/// **Named "Open in …", never "Play".** Cupola does not decode video, and once a
/// resume position has been shown on this very page a button labelled Play promises
/// playback this app cannot deliver: the tap would land the user on another app's
/// home screen having lost the position they were just looking at. Naming the door
/// makes it an honest door.
///
/// It also takes the **service accent** here rather than a host page's, because
/// this *is* the service's own screen. On a Radarr or Sonarr detail page the same
/// affordance must take the host's accent instead: `ArrMediaExtrasSection` already
/// settled that a section belongs to the screen it is rendered in, and one accent
/// lights a screen at a time.
class _HandoffButton extends ConsumerWidget {
  const _HandoffButton({
    required this.service,
    required this.instanceId,
    required this.item,
  });

  final ServiceKey service;

  /// The connection the item is on; empty is the active one.
  final String instanceId;
  final StreamItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The connection the page was opened on, else the one the lens is on,
    // else the first saved: with two Jellyfins the item on screen came from
    // one of them, and the handoff has to open that server.
    // At the address that connection is reached at now: away from home, the
    // one at home would not open.
    final connectionId = _connectionId(ref);
    final baseUrl = connectionId == null
        ? ''
        : ref.watch(connectionReachProvider(connectionId))?.url ?? '';

    // Plex's web client addresses an item by server identity as well as by key, so
    // without the machine identifier there is no URL to build. The button is absent
    // rather than broken.
    final machineId = switch (service) {
      ServiceKey.plex =>
        ref
            .watch(plexCapabilitiesForProvider(instanceId))
            .value
            ?.machineIdentifier,
      // Emby's link names the server too, but works without it.
      ServiceKey.emby => ref.watch(embyServerIdProvider(instanceId)).value,
      _ => null,
    };
    if (baseUrl.isEmpty) return const SizedBox.shrink();
    if (service == ServiceKey.plex &&
        (machineId == null || machineId.isEmpty)) {
      return const SizedBox.shrink();
    }

    final resuming = item.isInProgress;
    final label = resuming
        ? 'Resume in ${service.title}'
        : 'Open in ${service.title}';

    return FilledButton.icon(
      onPressed: () => _open(context, ref, baseUrl, machineId),
      icon: Icon(
        resuming ? Icons.play_arrow_rounded : Icons.open_in_new_rounded,
      ),
      label: Text(label),
    );
  }

  String? _connectionId(WidgetRef ref) => instanceId.isNotEmpty
      ? instanceId
      : ref.watch(activeInstanceProvider(service))?.id ??
            ref.watch(currentSettingsProvider).primaryOf(service)?.id;

  /// Opens the item on this connection: in the app the viewer chooses, on a
  /// phone, for Jellyfin (`playWith`); in the browser otherwise.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String baseUrl,
    String? machineId,
  ) {
    final settings = ref.read(currentSettingsProvider);
    final server =
        (instanceId.isEmpty ? null : settings.instanceById(instanceId)) ??
        ref.read(activeInstanceProvider(service)) ??
        settings.primaryOf(service);
    if (server == null) return Future.value();
    return playWith(
      context,
      ref,
      server: server,
      itemId: item.id,
      title: item.title,
      webUrl: _webUrl(baseUrl, machineId),
    );
  }

  /// The server's own web client, deep-linked to this item: see
  /// [streamItemWebUrl].
  Uri? _webUrl(String baseUrl, String? machineId) => streamItemWebUrl(
    service: service,
    baseUrl: baseUrl,
    itemId: item.id,
    serverId: machineId,
  );
}

/// Seasons, episodes or tracks.
///
/// Rendered as the same poster grid the library browse uses, so a season inside a
/// show looks like what it is (one more thing you can enter) rather than as a
/// list row that happens to navigate.
class _Children extends ConsumerWidget {
  const _Children({
    required this.service,
    required this.instanceId,
    required this.itemId,
  });

  final ServiceKey service;
  final String instanceId;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenKey = (
      service: service,
      instanceId: instanceId,
      itemId: itemId,
    );
    final childrenAsync = ref.watch(streamChildrenForProvider(childrenKey));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Contents', showChevron: false),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AsyncValueWidget<List<StreamItem>>.section(
            value: childrenAsync,
            service: service,
            consequence: 'what is inside is not shown',
            onRetry: () => refreshStreamChildren(ref, childrenKey),
            isEmpty: (list) => list.isEmpty,
            emptyBuilder: const AppEmptyState.compact(
              icon: Icons.inbox_outlined,
              title: 'Nothing inside',
            ),
            data: (list) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: list.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130 + AppSpacing.gridGap,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: AppSpacing.gridGap,
                mainAxisSpacing: AppSpacing.gridGap,
              ),
              itemBuilder: (context, index) => StreamPosterTile(
                service: service,
                instanceId: instanceId,
                item: list[index],
                index: index,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
