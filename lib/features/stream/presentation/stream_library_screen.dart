import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_poster_tile.dart';

/// One library on a media server, whole.
///
/// **The library is the library** (decision `P-stream-library-browse`): it
/// opens on every title it holds, A to Z, and reads in the order the person
/// picks (`Sort · Name`, `Date added`, `Year`), all of it or only what is
/// `Unplayed`. What someone is partway through, is up to next or was just
/// added lives where watching is the subject: the server's Activity, and its
/// Overview for the glance. The page once opened on those as lenses so it
/// would not read as the arrs' list twice; a person who opens a library wants
/// to browse it.
///
/// The bar is the arrs' own (`MediaBrowseFilterChip`, `MediaBrowseSortControl`),
/// so a library on Radarr and one on Jellyfin read alike.
///
/// **Unplayed is a watch state.** A Jellyfin or Emby API key authenticates as
/// an administrator with no user attached, so it can read any household
/// member's state once told which; a Plex token *is* its user. Without a
/// viewer, Unplayed asks for one ([_NeedsViewer]); the whole shelf needs none.
class StreamLibraryScreen extends ConsumerStatefulWidget {
  const StreamLibraryScreen({
    super.key,
    required this.service,
    required this.libraryId,
    this.libraryTitle,
    this.instanceId,
  });

  final ServiceKey service;

  /// The connection the library is on (`?i=`): null, or one that is not a
  /// connection of [service], reads the one the visit has in view, and then
  /// the active one.
  final String? instanceId;
  final String libraryId;

  /// Carried as a query parameter so a deep link still resolves from the path
  /// alone; when present it spares the destination a fetch before its first frame.
  final String? libraryTitle;

  @override
  ConsumerState<StreamLibraryScreen> createState() =>
      _StreamLibraryScreenState();
}

class _StreamLibraryScreenState extends ConsumerState<StreamLibraryScreen> {
  /// The library's name, as the server gives it.
  String get _title => widget.libraryTitle ?? 'Library';

  late PagingController<int, StreamItem> _paging;
  StreamLibrarySort _sort = StreamLibrarySort.name;

  /// Only what the viewer has not finished.
  bool _unplayedOnly = false;

  /// Where the next request starts, or null once the server says there is no
  /// more. **The server's number, never `pagesFetched * _pageSize`.**
  ///
  /// Both facts a pager needs are things only the server knows, and the previous
  /// controller inferred both from the rows it happened to receive:
  /// `lastPageIsEmpty ? null : nextIntPageKey` ended the list on any empty page,
  /// which on Plex's on-deck lenses is a page whose rows simply all fell on the
  /// wrong side of the continue/next-up split: real items sat in the page after
  /// it. Reset with the controller, because the offset belongs to the lens.
  int? _nextStartIndex;

  /// Whether the *first* fetch of the current lens has been made.
  ///
  /// `getNextPageKey` cannot ask the state. A first call and a call after a
  /// completed page look the same through `PagingState` once the key stops being
  /// derivable from the page count.
  bool _started = false;

  /// Which controller [_nextStartIndex] and [_started] currently belong to.
  ///
  /// Those two live on the State rather than in `PagingState`, which means they
  /// are *shared* across a rebuild in a way per-controller state never was. A
  /// `PagingController.dispose` only detaches its result; the fetch it was
  /// awaiting keeps running, so without this fence a stale fetch resolved
  /// after a lens change and wrote its offset over the new lens's: tap A–Z while
  /// Continue's first page is in flight, and A–Z's list truncates at fifty rows
  /// because Continue finished with `hasMore == false`.
  int _fetchGeneration = 0;

  /// The in-flight fetch's token, so a lens change stops the request rather than
  /// only ignoring its answer.
  CancelToken? _fetchCancel;

  @override
  void initState() {
    super.initState();
    _paging = _buildController();
  }

  @override
  void dispose() {
    _fetchCancel?.cancel();
    _paging.dispose();
    super.dispose();
  }

  PagingController<int, StreamItem> _buildController() {
    _fetchGeneration++;
    _nextStartIndex = 0;
    _started = false;
    return PagingController<int, StreamItem>(
      getNextPageKey: (_) => _started ? _nextStartIndex : 0,
      fetchPage: _fetchPage,
    );
  }

  /// Rebuilds the list from its first page, abandoning whatever is in flight.
  void _restart() {
    final previous = _paging;
    _fetchCancel?.cancel();
    _fetchCancel = null;
    setState(() => _paging = _buildController());
    previous.dispose();
  }

  /// Another order, or another shelf, is a new list, not a filter over the
  /// old one.
  ///
  /// Each is a different server query with its own ordering, so the paging
  /// controller is rebuilt rather than refreshed; reusing it would append page
  /// 1 of one order onto page 3 of another and produce a list that is neither.
  void _select({StreamLibrarySort? sort, bool? unplayedOnly}) {
    final nextSort = sort ?? _sort;
    final nextUnplayed = unplayedOnly ?? _unplayedOnly;
    if (nextSort == _sort && nextUnplayed == _unplayedOnly) return;
    setState(() {
      _sort = nextSort;
      _unplayedOnly = nextUnplayed;
    });
    _restart();
  }

  /// One screenful of rows, which is not the same thing as one server page.
  ///
  /// The loop is the fix for the on-deck split. `PagedLayoutBuilder` reports
  /// `noItemsFound` the moment the accumulated item count is zero, regardless
  /// of `hasNextPage`, and then never builds an item, so nothing ever triggers
  /// the next fetch. A server page that filtered down to nothing therefore has
  /// to be walked past *here*, before the controller is told about it, or the
  /// grid shows "Nothing in progress" over a library that has plenty.
  ///
  /// Only while nothing has been collected: once there is a row to show, the
  /// grid takes over and asks for the rest as the user scrolls.
  Future<List<StreamItem>> _fetchPage(int startIndex) async {
    final generation = _fetchGeneration;
    // Read once: the loop below awaits, and the order can change under it.
    final sort = _sort;
    final unplayedOnly = _unplayedOnly;
    final client = _client;
    final cancelToken = CancelToken();
    _fetchCancel = cancelToken;

    final collected = <StreamItem>[];
    var offset = startIndex;
    var hasMore = true;

    for (var attempt = 0; attempt < _maxPagesPerFetch; attempt++) {
      final page = await client.getLibraryPage(
        libraryId: widget.libraryId,
        sort: sort,
        unplayedOnly: unplayedOnly,
        startIndex: offset,
        limit: _pageSize,
        cancelToken: cancelToken,
      );

      // Checked before anything is thrown or written: a fetch whose controller
      // has been replaced must not raise the *old* lens's failure into the new
      // one's state, must not ask for another page, and must not touch the
      // shared offset. A disposed controller drops the returned list.
      if (generation != _fetchGeneration) return const [];

      // Thrown rather than returned empty: `PagingController` catches it into
      // `state.error`, which is what puts a retry on screen instead of the
      // affirmative "the server reports no items here". The clients keep their
      // degrade-to-`[]` convention; the *envelope* is what carries the failure.
      if (page.failed) throw const StreamLibraryPageFailure();
      if (page.needsViewer) throw const StreamLibraryViewerRequired();

      collected.addAll(page.items);
      // "There is more" is only usable if the place to ask for it has moved.
      // Jellyfin computes `nextStartIndex` from the rows it *sent* while
      // `hasMore` compares it against `TotalRecordCount`, so an endpoint that
      // filters rows away server-side (`/UserItems/Resume` with
      // `excludeActiveSessions`, `/Shows/NextUp` with `enableRewatching: false`)
      // answers with zero rows, an unmoved offset and `hasMore: true`. Trusting
      // that pair re-requested the same offset forever: the loop burns its five
      // attempts, the controller appends an empty page, `PagingStatus` stays
      // `ongoing`, and `PagedLayoutBuilder` fires the next fetch straight back.
      final advanced = page.nextStartIndex > offset;
      offset = page.nextStartIndex;
      hasMore = page.hasMore && advanced;
      _started = true;
      if (collected.isNotEmpty || !hasMore) break;
    }

    _nextStartIndex = hasMore ? offset : null;
    return collected;
  }

  static const int _pageSize = 50;

  /// How many server pages one fetch may walk while it has nothing to show.
  ///
  /// A bound rather than "until something turns up": the loop above only runs
  /// while the fetch is empty-handed, and on the lenses that can filter a page
  /// away (Plex's on-deck split) the underlying list is small, so five pages (250 rows)
  /// is far past any real case. Unbounded, one pathological library
  /// could walk itself end to end inside a single fetch.
  static const int _maxPagesPerFetch = 5;

  /// The connection this browse reads: the one `?i=` names, else the one the
  /// visit has in view, else the active one. Read where a fetch starts, so a
  /// connection removed meanwhile reads as the active one.
  String get _connection =>
      streamInstanceNow(ref, widget.service, widget.instanceId);

  StreamServerClient get _client => ref.read(
    streamClientForProvider((service: widget.service, instanceId: _connection)),
  );

  /// `368 movies` under the library's name: the whole library, which the
  /// grid, read a page at a time, never says. Nothing while it is read or when
  /// the server does not say.
  Widget? _countLine(WidgetRef ref, String connection) {
    final count = ref
        .watch(
          streamLibraryItemCountProvider((
            service: widget.service,
            instanceId: connection,
            itemId: widget.libraryId,
          )),
        )
        .value;
    if (count == null) return null;
    final libraries = ref
        .watch(
          streamLibrariesForProvider((
            service: widget.service,
            instanceId: connection,
          )),
        )
        .value;
    final kind = libraries
        ?.where((library) => library.id == widget.libraryId)
        .firstOrNull
        ?.kind;
    return Text(streamLibraryCountLine(count, kind, widget.service));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.service.accent;

    // Checked before the grid is built, and therefore before the paging
    // controller is ever asked for a page. This browse is a route inside the
    // Libraries branch now and a deep link can land on it with the server never
    // set up; without this the first fetch fails on a client that cannot exist,
    // and what the user gets is a Retry that can never succeed.
    if (!ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(widget.service)) {
      return AmbientScaffold(
        accent: accent,
        appBar: GlassAppBar.inPage(pageTitle: _title),
        body: SafeArea(
          child: TitledBody(
            title: _title,
            child: NotConfiguredPlaceholder.forService(widget.service),
          ),
        ),
      );
    }

    // Choosing a household member is the one action [_NeedsViewer] offers, and
    // it happens on another route. Nothing here reads settings otherwise: the
    // client is fetched with `ref.read` inside the fetch, so coming back landed
    // on a controller still parked in `firstPageError`, which
    // `PagedLayoutBuilder` never retries: the panel kept telling the user to
    // choose a viewer they had just chosen. A Plex token is its own viewer, so
    // only a service that needs one to be chosen listens.
    final connection = streamInstanceOf(ref, widget.service, widget.instanceId);
    if (widget.service.needsViewerSelection) {
      // The viewer of the connection being browsed, not the first one's.
      ref.listen<String?>(
        currentSettingsProvider.select(
          (s) => connection.isEmpty
              ? s.primaryOf(widget.service)?.viewerId ?? ''
              : s.instanceById(connection)?.viewerId,
        ),
        (_, _) => _restart(),
      );
    }

    return AmbientScaffold(
      accent: accent,
      appBar: GlassAppBar.inPage(pageTitle: _title),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageTitle(_title, summary: _countLine(ref, connection)),
            _ShelfBar(
              sort: _sort,
              unplayedOnly: _unplayedOnly,
              onSort: (sort) => _select(sort: sort),
              onUnplayed: (unplayed) => _select(unplayedOnly: unplayed),
            ),
            Expanded(
              child: PagingListener<int, StreamItem>(
                controller: _paging,
                builder: (context, state, fetchNextPage) => _LibraryGrid(
                  service: widget.service,
                  instanceId: connection,
                  unplayedOnly: _unplayedOnly,
                  state: state,
                  fetchNextPage: fetchNextPage,
                  onShowAll: () => _select(unplayedOnly: false),
                  onChooseViewer: () => context.push(
                    connection.isEmpty
                        ? ServiceRoutes.settingsFor(widget.service)
                        : ServiceRoutes.settingsForConnection(
                            widget.service,
                            connection,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page did not load. Deliberately an `Exception` rather than an `Error`:
/// `PagingController` rethrows anything that is not one, on the reasoning that a
/// non-exception is a bug rather than a remote failure.
class StreamLibraryPageFailure implements Exception {
  const StreamLibraryPageFailure();

  @override
  String toString() => 'The server did not answer.';
}

/// The lens is per-viewer and no household member has been chosen.
class StreamLibraryViewerRequired implements Exception {
  const StreamLibraryViewerRequired();

  @override
  String toString() => 'No viewer selected.';
}

/// The library's bar: the whole shelf or only what is unplayed, and the order
/// it is read in. The arrs' own controls, so the two kinds of library read
/// alike; the sort sits at the end of the row, as theirs does.
class _ShelfBar extends StatelessWidget {
  const _ShelfBar({
    required this.sort,
    required this.unplayedOnly,
    required this.onSort,
    required this.onUnplayed,
  });

  final StreamLibrarySort sort;
  final bool unplayedOnly;
  final ValueChanged<StreamLibrarySort> onSort;
  final ValueChanged<bool> onUnplayed;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          MediaBrowseFilterChip(
            label: 'All',
            color: ink,
            selected: !unplayedOnly,
            onTap: () => onUnplayed(false),
          ),
          MediaBrowseFilterChip(
            label: 'Unplayed',
            color: ink,
            selected: unplayedOnly,
            onTap: () => onUnplayed(true),
          ),
          const Spacer(),
          MediaBrowseSortControl(
            label: sort.label,
            options: [
              for (final value in StreamLibrarySort.values) value.label,
            ],
            selected: sort.index,
            onSelected: (index) => onSort(StreamLibrarySort.values[index]),
          ),
        ],
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.service,
    required this.instanceId,
    required this.unplayedOnly,
    required this.state,
    required this.fetchNextPage,
    required this.onShowAll,
    required this.onChooseViewer,
  });

  final ServiceKey service;
  final String instanceId;
  final bool unplayedOnly;
  final PagingState<int, StreamItem> state;
  final VoidCallback fetchNextPage;
  final VoidCallback onShowAll;
  final VoidCallback onChooseViewer;

  @override
  Widget build(BuildContext context) {
    // The column count comes from the space this grid is actually handed, and
    // it is resolved by the one helper every other grid uses.
    //
    // What was here before claimed the Column Floor Rule and implemented its
    // opposite. `SliverGridDelegateWithMaxCrossAxisExtent` rounds the count
    // *up*, `ceil(extent / (max + spacing))`, so a 640pt well answered five
    // columns of 118pt posters, under the 130pt floor, where four would have
    // been 151. A maximum extent cannot express a minimum; only a fixed count
    // computed against the floor can.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = MediaGrid.columnsFor(
          constraints.maxWidth - (AppSpacing.lg * 2),
          3,
        );
        return _pagedGrid(context, columns);
      },
    );
  }

  Widget _pagedGrid(BuildContext context, int columns) {
    return PagedGridView<int, StreamItem>(
      state: state,
      fetchNextPage: fetchNextPage,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: AppSpacing.gridGap,
        mainAxisSpacing: AppSpacing.gridGap,
      ),
      builderDelegate: PagedChildBuilderDelegate<StreamItem>(
        itemBuilder: (context, item, index) => StreamPosterTile(
          service: service,
          instanceId: instanceId,
          item: item,
          index: index,
        ),
        noItemsFoundIndicatorBuilder: (context) =>
            _EmptyShelf(unplayedOnly: unplayedOnly, onShowAll: onShowAll),
        // Nothing arrived *and* something went wrong. The default here is the
        // package's generic tile; this has to be the state that never says the
        // library is empty, because at this point we do not know that.
        firstPageErrorIndicatorBuilder: (context) =>
            state.error is StreamLibraryViewerRequired
            ? _NeedsViewer(service: service, onChooseViewer: onChooseViewer)
            : AppErrorState(
                error: state.error ?? const StreamLibraryPageFailure(),
                serviceName: service.title,
                service: service,
                onRetry: fetchNextPage,
              ),
        // A failure partway down used to truncate the grid silently: no
        // spinner, no message, no way to ask again. The rows already fetched
        // stay; this is the footer under them.
        // Worded from the classification like every other section that did
        // not load, so a refused key reads as one and offers its remedy.
        newPageErrorIndicatorBuilder: (context) {
          final error = state.error ?? const StreamLibraryPageFailure();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: InlineErrorRetry(
              message: sectionFailureMessage(
                service,
                error,
                consequence: 'the rest of this library did not load',
              ),
              error: error,
              service: service,
              onRetry: fetchNextPage,
            ),
          );
        },
      ),
    );
  }
}

/// Unplayed on a Jellyfin or Emby server with no household member chosen.
///
/// **Not an empty state, because the library is not empty**: nothing has been
/// asked of the server at all. An API key authenticates as an administrator
/// with no user attached, so "unplayed" has no subject until one is named, and
/// the control that names it lives in settings.
class _NeedsViewer extends StatelessWidget {
  const _NeedsViewer({required this.service, required this.onChooseViewer});

  final ServiceKey service;
  final VoidCallback onChooseViewer;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.person_outline_rounded,
      accentColor: service.accent,
      title: 'Choose whose watch state to show',
      message:
          'What is unplayed is per person, and ${service.title} needs to be '
          'told which one. All works either way.',
      action: FilledButton(
        onPressed: onChooseViewer,
        child: const Text('Pick a viewer'),
      ),
    );
  }
}

/// A shelf with nothing on it: a library the server reports empty, or one
/// where the viewer has played everything, which offers the whole shelf back.
class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.unplayedOnly, required this.onShowAll});

  final bool unplayedOnly;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: unplayedOnly
          ? Icons.visibility_off_outlined
          : Icons.video_library_outlined,
      title: unplayedOnly
          ? 'Everything has been played'
          : 'This library is empty',
      message: unplayedOnly
          ? 'Nothing left unwatched in this library.'
          : 'The server reports no items here.',
      action: unplayedOnly
          ? FilledButton(onPressed: onShowAll, child: const Text('Show all'))
          : null,
    );
  }
}

/// `368 movies`, `86 series`, `1 album`: a library's count in the unit it
/// browses in, as the server counts it (a music library is albums on
/// Jellyfin, artists on Plex); `items` for a library of another kind.
String streamLibraryCountLine(
  int count,
  StreamLibraryKind? kind,
  ServiceKey service,
) {
  final (one, many) = switch (kind) {
    StreamLibraryKind.movies => ('movie', 'movies'),
    StreamLibraryKind.shows => ('series', 'series'),
    StreamLibraryKind.music when service == ServiceKey.plex => (
      'artist',
      'artists',
    ),
    StreamLibraryKind.music => ('album', 'albums'),
    StreamLibraryKind.photos ||
    StreamLibraryKind.other ||
    null => ('item', 'items'),
  };
  return '$count ${count == 1 ? one : many}';
}
