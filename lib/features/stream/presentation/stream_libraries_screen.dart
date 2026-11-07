import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_admin_placeholder.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/stream_overview_provider.dart';

/// The Libraries tab of a media server: the rooms on the box, as destinations.
///
/// One screen for both Jellyfin and Plex, like every other Stream surface: it is
/// written against `StreamServerClient`, so the only per-service input is the
/// [service] key. Two services, one family, two different bars: the difference
/// lives in `tabsFor`, not here.
///
/// **Entering the collection through a room rather than through a global title
/// list** is what keeps this from reading as a second copy of Radarr's library.
/// The browse each row pushes lands on a watch-state lens, never on A–Z; see
/// `StreamLibraryScreen`.
///
/// **`isServiceConfigured` is checked before any provider is read**, not after.
/// A tab is arrived at routinely, including on a server that was never set up,
/// and a `FutureProvider` that throws "not configured" is a *failed* provider:
/// it schedules a retry with backoff for a condition no waiting changes, and it
/// surfaces in tests as a pending timer. Letting `AsyncValueWidget` catch the
/// throw would draw the same pixels and leave that timer running.
///
/// **No per-library item count, and that absence is honest rather than lazy.**
/// Both servers can answer a count only as its own request per library
/// (`/Items?limit=0`, `X-Plex-Container-Size=0`), and the design puts that cost
/// here rather than on the Overview, but nothing calls
/// `StreamServerClient.getLibraryItemCount` yet, so the card says what the one
/// `getLibraries` response actually contains. A fabricated zero is the one thing
/// it must not say.
///
/// **One connection per page**: the one the visit has in view
/// (`streamInstanceOf`), else the lens. Every room opens on it.
class StreamLibrariesScreen extends ConsumerWidget {
  const StreamLibrariesScreen({
    super.key,
    required this.service,
    this.showAppBar = true,
    this.topPadding = 0,
    this.instanceId,
  });

  final ServiceKey service;
  final bool showAppBar;
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
      'StreamLibrariesScreen only serves media servers',
    );
    final settings = ref.watch(currentSettingsProvider);

    return AmbientScaffold(
      accent: service.accent,
      appBar: showAppBar ? GlassAppBar(title: Text(service.title)) : null,
      // The inset is consumed here with or without an app bar: with one the
      // `Scaffold` has already taken it off the body, and without one (the tab
      // shell) the band above consumes it and the tab bar sits an inset lower
      // than `topPadding` says.
      body: SafeArea(
        bottom: false,
        child: settings.isServiceConfigured(service)
            ? _LibrariesBody(
                service: service,
                topPadding: topPadding,
                instanceId: streamInstanceOf(
                  ref,
                  service,
                  instanceId,
                  pinned: false,
                ),
              )
            : NotConfiguredPlaceholder.forService(service),
      ),
    );
  }
}

/// The list itself, built only once the service is configured.
class _LibrariesBody extends ConsumerWidget {
  const _LibrariesBody({
    required this.service,
    required this.topPadding,
    required this.instanceId,
  });

  final ServiceKey service;
  final double topPadding;

  /// The connection whose rooms these are; empty is the lens.
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `/Library/VirtualFolders` is elevated on Jellyfin: a household member's
    // token is refused it, and an empty list would read as a server with no
    // libraries. Emby's own route is not (`librariesNeedAdministrator`).
    if (service.librariesNeedAdministrator &&
        ref.watch(
          mediaBrowserProvidersOf(service).lacksAdministratorFor(instanceId),
        )) {
      return JellyfinAdminPlaceholder(
        service: service,
        what: 'libraries',
        topPadding: topPadding,
        connectionId: streamConnectionIdOf(ref, service, instanceId),
      );
    }
    final key = (service: service, instanceId: instanceId);
    final librariesAsync = ref.watch(streamLibrariesForProvider(key));
    // The lens's collapse onto the plain provider, which holds the answer the
    // family re-reads, so a Retry asks both.
    void reload() {
      ref.invalidate(streamLibrariesForProvider(key));
      ref.invalidate(streamBackendOf(service).libraries);
    }

    // The tab is this one read, so a cold failure is the server's leaf.
    if (librariesAsync.hasError && !librariesAsync.hasValue) {
      return Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: ServiceOfflineState.failure(
          service: service,
          instanceId: instanceId,
          error: librariesAsync.error!,
          onRetry: reload,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => reload(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          0,
          topPadding,
          0,
          // The nav bar floats over content and grows with the reading size, so
          // a constant here leaves the last library unreachable at large text.
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          const SizedBox(height: AppSpacing.sm),
          _LibrariesSection(
            service: service,
            instanceId: instanceId,
            libraries: librariesAsync,
            onRetry: reload,
          ),
        ],
      ),
    );
  }
}

/// The libraries, as destinations, and as a count of *rooms*, never of what is
/// in them.
///
/// Decision 21: a per-library item count is its own round trip on both servers
/// (`/Items?limit=0`, `X-Plex-Container-Size=0`), so six libraries would be six
/// extra requests on every load. What one `getLibraries` response can say for
/// free is how many rooms there are and which one is scanning, and that is what
/// this draws. The count itself is still unbuilt; see the class comment on
/// [StreamLibrariesScreen].
class _LibrariesSection extends ConsumerWidget {
  const _LibrariesSection({
    required this.service,
    required this.instanceId,
    required this.libraries,
    required this.onRetry,
  });

  final ServiceKey service;
  final String instanceId;
  final AsyncValue<List<StreamLibrary>> libraries;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The header carries the page inset itself.
        SectionHeader(
          title: 'Libraries',
          // Null until the list lands, so the header never prints "0
          // libraries" over a region that is still loading. A figure whose
          // source has not answered is not zero. A list that failed with
          // nothing retained says so with an em dash; a retained one keeps
          // the census of the rows still drawn under the fault band.
          subtitle: libraries.hasError && !libraries.hasValue
              ? '—'
              : _summaryOf(libraries.value),
          showChevron: false,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AsyncValueWidget<List<StreamLibrary>>(
            value: libraries,
            serviceName: service.title,
            instanceId: instanceId,
            onRetry: onRetry,
            isEmpty: (list) => list.isEmpty,
            emptyBuilder: const AppEmptyState.compact(
              icon: Icons.video_library_outlined,
              title: 'No libraries yet',
              message: 'This server has no libraries set up.',
            ),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final library in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _LibraryRow(
                      service: service,
                      instanceId: instanceId,
                      library: library,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The header's line, or null while the list has not landed.
  static String? _summaryOf(List<StreamLibrary>? list) {
    if (list == null) return null;
    final scanning = list.where((library) => library.isRefreshing).toList();
    return streamLibrariesSummary(
      total: list.length,
      scanningName: scanning.length == 1 ? scanning.first.name : null,
      scanningCount: scanning.length,
    );
  }
}

/// One library, as a destination.
///
/// Entering the collection through a *room on the server* rather than through a
/// global title list is what keeps the Stream browse from reading as a second copy
/// of Radarr's library; see `StreamLibraryLens` and the idle-month test.
class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.service,
    required this.instanceId,
    required this.library,
  });

  final ServiceKey service;

  /// The connection the room is on, which its browse opens on (`?i=`); empty
  /// is the lens, and then the location carries none.
  final String instanceId;
  final StreamLibrary library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = ServiceRoutes.streamLibrary(
      service,
      library.id,
      title: library.name,
      instanceId: instanceId,
    );

    return AppCard.filled(
      // A library row is a full-width card with plenty of surface, so the ink
      // ripple still reads as a touch spreading rather than as a selection: the
      // Ripple-Needs-Room Rule's threshold is not crossed here.
      onTap: () => context.push(route),
      semanticLabel: library.name,
      semanticValue: streamLibraryValue(
        kindLabel: library.kind.label,
        lastScannedLabel: _scannedLabel(library.lastScannedAt),
        isRefreshing: library.isRefreshing,
      ),
      semanticHint: 'Browse this library',
      child: Row(
        children: [
          Icon(
            streamLibraryGlyph(library.kind),
            size: 20,
            color: ServiceTheme.onTint(
              service.accent,
              surface: theme.colorScheme.surfaceContainer,
              tintAlpha: 0,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  library.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                if (_subtitleFor(library) case final subtitle
                    when subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (library.isRefreshing)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  /// The line under the library name.
  ///
  /// Composed from whatever the server actually said. Jellyfin exposes no
  /// per-library scan timestamp, only a global scheduled task, so the scan half
  /// is simply absent there rather than printed as "unknown", which would imply
  /// the server was asked and declined.
  ///
  /// **No item count here (decision 21).** `StreamLibrary.itemCount` is null out
  /// of both `getLibraries` calls and always was, so the branch that printed it
  /// was unreachable code describing a page this is not: the count is a separate
  /// request per library and belongs to the pushed Libraries page, where a card
  /// can render complete and let its number arrive afterwards. Putting it back
  /// here would make opening a service cost one request per library.
  ///
  /// The kind is left out when the library is already named after it
  /// (`Movies` · `Movies`), as the Overview's shelf does.
  static String _subtitleFor(StreamLibrary library) {
    final kind = library.kind.label;
    final named = kind.toLowerCase() == library.name.trim().toLowerCase();
    final parts = <String>[if (!named) kind];
    if (library.isRefreshing) {
      parts.add('Scanning');
    } else {
      final scanned = _scannedLabel(library.lastScannedAt);
      if (scanned != null) parts.add(scanned);
    }
    return parts.join(dotSeparator);
  }

  static String? _scannedLabel(DateTime? at) {
    if (at == null) return null;
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inDays >= 1) {
      final days = elapsed.inDays;
      return 'Scanned $days ${days == 1 ? 'day' : 'days'} ago';
    }
    if (elapsed.inHours >= 1) {
      return 'Scanned ${withUnit(elapsed.inHours, 'h')} ago';
    }
    return 'Scanned just now';
  }
}
