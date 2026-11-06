import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_admin_placeholder.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/stream_overview_provider.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';

/// The first tab of a media server's service home: Jellyfin's and Plex's both.
///
/// **One screen, two services**, like every other surface in this folder: the
/// only per-service input is [service], and the difference between the two
/// servers lives in what their clients can answer, never in a fork of the page.
/// The two boards are genuinely not the same board, and where they differ the
/// difference is real here too: Plex draws an On deck rail and a Server region
/// that Jellyfin has no endpoint for, and neither server draws anything the
/// other one merely *might* have.
///
/// Overview alone carries the identity block and the readouts; every other tab
/// is a view of one kind of record, and then the regions in the order the
/// *mobile* boards put them, which is the order that survives the narrow width:
/// who is watching, what is half-watched, what the shelf is doing, and (Plex)
/// what the box says about itself.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both floated above this page
/// as glass bands so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// ## What the board asks for and this page does not draw
///
/// The full list, with the exact endpoint boundary for each, is in the library
/// comment of `stream_overview_provider.dart`. The short of it: no bandwidth
/// figure (neither server measures egress), no Recently added rail (no
/// server-wide recent endpoint, and `StreamItem` has no `addedAt` to sort by),
/// and no Jellyfin Continue watching (`/Users/{id}/Items/Resume` is not part
/// of the current client). Tasks, Users, Devices, Playlists and the supported
/// live-session activity views are dedicated tabs rather than duplicate
/// Overview regions. Unsupported figures remain absent rather than fabricated.
///
/// Sections load and fail independently. A server answering `/Sessions` but not
/// its library list still draws the rest, and the one that could not load says
/// so in its own slot rather than taking the page with it.
///
/// **One connection per page.** The page reads the connection the visit has in
/// view (`streamInstanceOf`: what a link opened the service on, else the lens),
/// and every region below reads it, the identity line and the figures
/// included: a page whose header names one connection and whose figures come
/// from another is the one thing it must not be.
class StreamOverviewScreen extends ConsumerWidget {
  const StreamOverviewScreen({
    super.key,
    required this.service,
    this.topPadding = _hostedTopPadding,
    this.instanceId,
  });

  /// The room the two glass bands above this page occupy.
  ///
  /// Composed from the same two constants the router composes its own from, so
  /// a screen built outside the router (a test, a preview) reserves the right
  /// space instead of tucking its first region under the tab bar.
  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Jellyfin or Plex.
  final ServiceKey service;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  /// The `?i=` of the location the page was built for. A tab's root reads
  /// the connection the visit has in view first (`streamInstanceOf`, not
  /// pinned) and this where the visit has none; null, or one that names no
  /// connection of [service], reads the lens.
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    assert(
      service.isMediaServer,
      'StreamOverviewScreen only serves media servers',
    );

    // Checked **before** any provider is reached. `jellyfinClientProvider` and
    // `plexClientProvider` both throw "<service> not configured", and letting
    // `AsyncValueWidget` catch that throw would draw the same pixels while
    // leaving failed providers behind it, each scheduling a retry with backoff
    // for a condition no amount of waiting changes, which surfaces in tests as
    // a pending timer and on device as a battery cost. It matters more here
    // than elsewhere: the sessions providers deliberately carry
    // `retry: noProviderRetry` precisely because a dark media server must not
    // be hammered, and reaching them unconfigured would be the one path that
    // re-introduces what that flag exists to prevent.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(service),
      ),
    );

    return AmbientScaffold(
      accent: service.accent,
      body: SafeArea(
        bottom: false,
        child: configured
            ? _OverviewBody(
                service: service,
                topPadding: topPadding,
                instanceId: streamInstanceOf(
                  ref,
                  service,
                  instanceId,
                  pinned: false,
                ),
              )
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to this server's own connection form
            // rather than to the settings index.
            : NotConfiguredPlaceholder.forService(service),
      ),
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({
    required this.service,
    required this.topPadding,
    required this.instanceId,
  });

  final ServiceKey service;
  final double topPadding;

  /// The connection every region reads; empty is the lens.
  final String instanceId;

  bool get _isPlex => service == ServiceKey.plex;

  /// The figures of the connection the page reads: the lens's own fold when it
  /// is the lens, and that connection's when it is another.
  ///
  /// `serviceKpiForProvider` is null only for a connection that cannot be read
  /// on its own, which neither media server is; read as no figures, which the
  /// peek draws as dashes, never as zeros.
  AsyncValue<List<ServiceKpi>> _kpisOf(WidgetRef ref) {
    if (instanceId.isEmpty) return ref.watch(serviceKpiProvider(service));
    return ref
        .watch(
          serviceKpiForProvider((service: service, instanceId: instanceId)),
        )
        .whenData((kpis) => kpis ?? const <ServiceKpi>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read once here rather than inside the section: the sessions region is a
    // shared widget that takes the value, because *it* must not decide which
    // server it is talking to and must not be the thing that first reaches a
    // provider on an unconfigured service.
    final connection = (service: service, instanceId: instanceId);
    // Read again while the room is seen: its figure, Now playing and light
    // all read this one answer, so they move together.
    ref.watchWhileLive(context, streamSessionsPollProvider(connection));
    final sessions = ref.watch(streamSessionsForProvider(connection));
    final libraries = ref.watch(streamLibrariesForProvider(connection));

    void refresh() {
      invalidateServiceReadout(ref, service);
      // The connection's own reads, then the lens's: the lens's collapse onto
      // the plain providers, which hold the answer the others re-read.
      ref.invalidate(
        serviceKpiForProvider((service: service, instanceId: instanceId)),
      );
      ref.invalidate(streamSessionsForProvider(connection));
      ref.invalidate(streamLibrariesForProvider(connection));
      final backend = streamBackendOf(service);
      ref.invalidate(backend.sessions);
      ref.invalidate(backend.libraries);
      // The regions only Plex draws.
      if (_isPlex) {
        ref.invalidate(plexOnDeckProvider);
        ref.invalidate(plexOnDeckForProvider(instanceId));
        ref.invalidate(plexCapabilitiesProvider);
        ref.invalidate(plexCapabilitiesForProvider(instanceId));
      }
    }

    // **One** state for a server that is dark, not one per region. Sessions
    // and the library list are the two reads both servers answer; when both
    // failed with nothing retained there is no region left to draw, and three
    // stacked error wells each saying the same thing about the same box was a
    // page shouting. The identity line and the readouts stay above it: the
    // host, and "—" where a figure had no answer.
    final serverDark =
        sessions.hasError &&
        !sessions.hasValue &&
        libraries.hasError &&
        !libraries.hasValue;

    return RefreshIndicator(
      onRefresh: () async {
        refresh();
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // One scroll view for the whole page: the regions are one column of
      // reading, not four independently scrolling panes.
      child: ServiceOverviewScroll(
        topPadding: topPadding,
        children: [
          ServiceOverviewIdentity(service: service, instanceId: instanceId),
          ...sectionsOrOneLine(
            ref,
            service,
            ownSilence: true,
            instanceId: instanceId,
            [
              ServiceKpiPeek.room(kpis: _kpisOf(ref), service: service),
              if (serverDark)
                ServiceOfflineState.failure(
                  service: service,
                  instanceId: instanceId,
                  error: sessions.error!,
                  onRetry: refresh,
                )
              else ...[
                // Who is watching, first and on both servers: it is the one fact
                // only a media server holds, and the only region on this page
                // that is about people rather than about files.
                StreamNowPlayingSection.slab(
                  service: service,
                  instanceId: instanceId,
                  sessions: sessions,
                ),
                if (service.speaksMediaBrowser &&
                    ref.watch(
                      jellyfinLacksAdministratorForProvider(instanceId),
                    ))
                  const JellyfinOwnPlaybackNote(),
                const SizedBox(height: AppSpacing.lg),
                if (_isPlex) _OnDeckSection(instanceId: instanceId),
                _LibrariesSection(service: service, instanceId: instanceId),
                if (_isPlex) _ServerSection(instanceId: instanceId),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── On deck (Plex only) ────────────────────────────────────────────────────

/// What is half-watched, across every library.
///
/// **Plex only, and the asymmetry is the honest reading of the two clients.**
/// `PlexClient.getContinueWatching` calls `/hubs/continueWatching`, which
/// answers for the whole server in one request; Jellyfin's equivalent
/// (`/Users/{id}/Items/Resume`) is not implemented, and its per-library
/// `continueWatching` lens is not a substitute: it would be one request per
/// library and would still have nothing to order the merged result by.
///
/// The header states no count. The hub is asked for exactly as many rows as the
/// rail draws, so there is no remainder to report, and a figure counted inside
/// a capped response and then printed as a total is the defect this batch has
/// found four times.
///
/// **It says nothing about *whose* deck this is**, although the board's caption
/// does (`nadia · S2 E5`). A Plex token is one person: every row here is the
/// owner's own, `/library/*` takes no impersonation parameter, and naming a
/// household member beside a poster would invent a perspective the server never
/// offered.
class _OnDeckSection extends ConsumerWidget {
  const _OnDeckSection({required this.instanceId});

  /// The Plex connection the rail reads; empty is the lens.
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(plexOnDeckForProvider(instanceId));

    return ServiceOverviewSection.bleed(
      service: ServiceKey.plex,
      title: 'On deck',
      destination: ServiceTab.onDeck,
      child: AsyncValueWidget<List<StreamItem>>.bleedSection(
        value: items,
        service: ServiceKey.plex,
        instanceId: instanceId,
        consequence: 'what is on deck is not shown',
        loadingLabel: 'Loading what is on deck',
        onRetry: () {
          ref.invalidate(plexOnDeckForProvider(instanceId));
          ref.invalidate(plexOnDeckProvider);
        },
        skeleton: AppSkeleton.posterRow(height: 138),
        isEmpty: (list) => list.isEmpty,
        emptyBuilder: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ServiceOverviewEmpty(
            icon: Icons.play_circle_outline_rounded,
            label: 'Nothing part-watched',
          ),
        ),
        data: (list) => _OnDeckRail(items: list, instanceId: instanceId),
      ),
    );
  }
}

class _OnDeckRail extends ConsumerWidget {
  const _OnDeckRail({required this.items, required this.instanceId});

  final List<StreamItem> items;
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(
      streamClientForProvider((
        service: ServiceKey.plex,
        instanceId: instanceId,
      )),
    );

    return SizedBox(
      // 138pt poster, the gap, and two caption lines, grown by the reading
      // size so the captions are not clipped at an accessibility text size.
      height: TextScaleMetrics.boxHeight(context, base: 176, textHeight: 34),
      // The box grew by the *clamped* scale, so the text has to be laid out at
      // the same clamp: unclamped, the rail is sized for 1.6x and painted at
      // 3.0x, which is an overflow stripe.
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
          itemBuilder: (context, index) => _OnDeckTile(
            item: items[index],
            instanceId: instanceId,
            index: index,
            poster: items[index].posterPath == null
                ? null
                : client.imageFor(items[index].posterPath!, width: 260),
          ),
        ),
      ),
    );
  }
}

/// One poster on the rail.
///
/// **Not `StreamPosterTile`, and the reason is the Hero tag.** That widget tags
/// its poster `stream_<service>_<id>_<index>`, and the On deck *tab* is alive in
/// a sibling branch of the same shell drawing the same items with the same tags.
/// Two live Heroes sharing a tag is an assertion at flight time, not a
/// degraded animation. Radarr's Overview rail carries its own namespace for
/// exactly this reason. The tile is otherwise deliberately plain: the resume bar
/// and unplayed badge belong to the grid where a row of them can be compared,
/// and here the caption already says how far in the viewer is.
///
/// **The [index] is in the tag for the second half of the same rule.** The
/// namespace settles the collision *between* rails and does nothing about one
/// *inside* this rail, which is a real shape rather than a theoretical one:
/// `streamOnDeckPreview` now drops a repeated `ratingKey`, and the index is the
/// belt to that braces: a duplicated Hero tag throws at flight time instead of
/// degrading, and one interpolation is a cheap price for never asserting.
class _OnDeckTile extends StatelessWidget {
  const _OnDeckTile({
    required this.item,
    required this.instanceId,
    required this.index,
    required this.poster,
  });

  final StreamItem item;

  /// The connection the rail was read from, which the title opens on.
  final String instanceId;

  /// Position on the rail, included in the Hero tag; see the class comment.
  final int index;

  final StreamImageSource? poster;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final caption = streamOnDeckCaption(item);
    final heroTag = 'stream_overview_ondeck_plex_${item.id}_$index';

    return SizedBox(
      width: 96,
      child: PressableScale(
        onTap: () => context.openStreamItem(
          ServiceKey.plex,
          item,
          instanceId: instanceId,
        ),
        // A poster is an image with no name of its own; the tile announces the
        // title and its state as one button rather than as two fragments.
        semanticLabel: item.title,
        semanticValue: caption.isEmpty ? null : spokenFromDotted(caption),
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 138,
              child: MediaPosterCard(
                heroTag: heroTag,
                imageUrl: poster?.url,
                imageHeaders: poster?.headers,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.weight(FontWeight.w600)
                  .copyWith(color: colorScheme.onSurface),
            ),
            if (caption.isNotEmpty)
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Libraries ──────────────────────────────────────────────────────────────

/// The shelf: which rooms are on the server, and what is happening to them.
///
/// **A peek, not the list.** The Libraries tab one tap away draws every room as
/// a destination; this draws three of them as a readout, with the census over
/// the top. Naming them costs nothing: one `getLibraries` response already
/// answered names and kinds, and it is what keeps a page the user lands on
/// every time they open the service from being a header over a single "no scan
/// running" note, which on a home server is the majority state rather than the
/// edge case. Only the per-library item counts are refused (decision 21: one
/// request per library, and that cost belongs to the tab).
///
/// The header's census comes from the whole list and the rows are capped, so a
/// full rescan reads `9 scanning` above three rows rather than reporting three.
///
/// **An empty list is an empty shelf, and a dark server is a failure.** Both
/// clients used to swallow their own failure into `[]`, and this region leaned
/// on the reachability probe to guess which of the two it had been handed. They
/// throw now, so the failure lands in the region's own slot with a Retry and an
/// empty list is only ever the server's answer.
class _LibrariesSection extends ConsumerWidget {
  const _LibrariesSection({required this.service, required this.instanceId});

  final ServiceKey service;

  /// The connection whose shelf this is; empty is the lens.
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `/Library/VirtualFolders` is elevated on Jellyfin, so a household
    // member's token is refused it: the Libraries tab says so calmly, and so
    // does this region, rather than drawing the refusal as a fault.
    if (service.speaksMediaBrowser &&
        ref.watch(jellyfinLacksAdministratorForProvider(instanceId))) {
      return ServiceOverviewSection(
        service: service,
        title: 'Libraries',
        subtitle: '—',
        destination: ServiceTab.libraries,
        child: const ServiceOverviewEmpty(
          icon: Icons.admin_panel_settings_outlined,
          label: jellyfinNeedsAdministratorTitle,
        ),
      );
    }
    final libraries = ref.watch(
      streamLibrariesForProvider((service: service, instanceId: instanceId)),
    );
    // One `now` for the whole region, so two rows built microseconds apart
    // cannot disagree about which side of a boundary they are on.
    final now = DateTime.now();

    return ServiceOverviewSection(
      service: service,
      title: 'Libraries',
      // "—" while the list is in flight and after it failed. A "0 libraries"
      // printed over an unanswered question is a claim nobody made, and it is
      // the claim a user would act on, by going to look for libraries that are
      // there.
      subtitle:
          streamLibrariesCensus(libraries: libraries.asData?.value) ?? '—',
      destination: ServiceTab.libraries,
      child: AsyncValueWidget<List<StreamLibrary>>.section(
        value: libraries,
        service: service,
        instanceId: instanceId,
        consequence: 'its libraries are not shown',
        loadingLabel: 'Loading the libraries',
        onRetry: () {
          ref.invalidate(
            streamLibrariesForProvider((
              service: service,
              instanceId: instanceId,
            )),
          );
          ref.invalidate(streamBackendOf(service).libraries);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (list) => list.isEmpty,
        // Only a server that answered reaches this: a dark one is the error
        // branch above, never an empty list.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.video_library_outlined,
          label: 'No libraries on this server',
        ),
        data: (list) => Column(
          children: [
            for (final row in streamShelfRows(list, now: now))
              _ShelfRow(row: row),
          ],
        ),
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.row});

  final StreamShelfRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`: a scan in progress is
    // **informational**: the server is doing what it was told to do, and a
    // library at rest is neutral. Neither is a fault, and amber here would put
    // a working library in the colour of a broken import.
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: row.spoken,
      leading: Icon(row.icon, size: 18, color: tone),
      title: row.title,
      detail: row.detail,
    );
  }
}

// ─── Server (Plex only) ─────────────────────────────────────────────────────

/// What the box says about itself, from the one call that asks it: `GET /`.
///
/// **Plex only.** Jellyfin's equivalent facts are already in the identity block
/// above (host, version, answering), and `JellyfinClient` fetches nothing
/// beyond them, so a second region there would be the same line twice.
///
/// Three of the board's six rows are here and three are not: remote access and
/// the mapped port, the transcoder's hardware, the cache size and the uptime all
/// live in `GET /:/prefs` and `GET /statistics/resources`, which this client
/// never calls. The version is not repeated: the identity block owns it.
///
/// **Value first, label second**, the inversion the qBittorrent Session region
/// uses: this region has no subject, so the figure is the content and the label
/// is the chrome.
class _ServerSection extends ConsumerWidget {
  const _ServerSection({required this.instanceId});

  /// The Plex connection that describes itself; empty is the lens.
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(plexCapabilitiesForProvider(instanceId));

    return ServiceOverviewSection(
      service: ServiceKey.plex,
      title: 'Server',
      // No link: every fact here is a connection setting, and Plex's bar has no
      // tab that owns them: a link named after a tab that does not exist is a
      // promise the app cannot keep.
      // A Plex that did not answer is the failure, in its words and tone: the
      // sheet used to come back null for any failure, and this section read
      // a dark server as one that "did not describe itself".
      child: AsyncValueWidget<PlexServerCapabilities>.section(
        value: capabilities,
        service: ServiceKey.plex,
        instanceId: instanceId,
        consequence: 'what the server says about itself is not shown',
        loadingLabel: 'Loading what the server says about itself',
        onRetry: () {
          ref.invalidate(plexCapabilitiesForProvider(instanceId));
          ref.invalidate(plexCapabilitiesProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        data: (value) => _ServerRows(capabilities: value),
      ),
    );
  }
}

class _ServerRows extends StatelessWidget {
  const _ServerRows({required this.capabilities});

  final PlexServerCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    // A field the response omitted reads "—": the call answered, so saying
    // nothing at all would hide that the server was asked. `plexBool` keeps the
    // three-way distinction alive for exactly this: `myPlexSubscription`
    // absent is not the same claim as `myPlexSubscription: false`.
    final pass = switch (capabilities.myPlexSubscription) {
      true => 'Active',
      false => 'Not on this server',
      null => '—',
    };

    return Column(
      children: [
        _ServerRow(
          icon: Icons.dns_outlined,
          value: capabilities.displayName ?? '—',
          label: 'Server name',
        ),
        _ServerRow(
          icon: Icons.workspace_premium_outlined,
          value: pass,
          // Named with its consequence rather than as trivia: this flag is why
          // the stop control on a session card is there or is not.
          label: 'Plex Pass\u00A0· stopping a stream needs it',
        ),
        _ServerRow(
          icon: Icons.person_outline_rounded,
          value: capabilities.myPlexUsername ?? '—',
          label: 'Plex account',
        ),
        // Only when the server said so. `multiuser` absent means the build did
        // not report it, and "owner only" would be a guess about someone's
        // household, while `true` explains something the user will otherwise
        // notice as a defect: every watch state Cupola shows for Plex is the
        // owner's, because a token is one person and `/library/*` takes no
        // impersonation parameter.
        if (capabilities.multiuser == true)
          const _ServerRow(
            icon: Icons.groups_outlined,
            // A figure, like every other row here, and not a noun phrase in the
            // figure slot with the whole statement underneath it: that pair
            // reads as a datum with a sentence below it and *speaks* as a
            // qualifier arriving before the thing it qualifies, which is the
            // exact failure the spoken order below exists to prevent.
            value: 'Owner only',
            label: 'Plex Home\u00A0· Cupola reads the owner’s watch state',
          ),
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ServiceOverviewRow(
      // Label then value, spoken: the reverse of the visual order, which leads
      // with the figure for scanning. Read aloud, "Active" before "Plex Pass"
      // is an answer arriving before its question.
      spoken: joinSpokenParts([spokenFromDotted(label), value]),
      leading: Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
      title: value,
      detail: label,
    );
  }
}
