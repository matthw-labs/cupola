# StreamLibrary

One library on a media server (Jellyfin, Plex, Emby), whole: every title it holds, in the order the person picks, all of it or only what is unplayed. What someone is partway through, is up to next or was just added is not here: it lives in the server's Activity and on its Overview ([StreamWatching](../StreamWatching/README.md); decision `P-stream-library-browse`).

Rendered from `lib/features/stream/presentation/stream_library_screen.dart` (tiles from `lib/features/stream/presentation/widgets/stream_poster_tile.dart`, the bar's controls from `lib/core/widgets/media_browse_scaffold.dart`) by `test/design_catalog/stream_library_catalog_test.dart`, against the demo world's fake Emby.

- **Page**: an `AmbientScaffold` in the service's lamp under a `GlassAppBar.inPage`, then `PageTitle`: the library's name, and under it the whole library's count in its own unit (*368 movies*, *42 shows*, `streamLibraryCountLine`), which the grid, read a page at a time, never says. No count while it is read or when the server gives none. A service not set up draws `NotConfiguredPlaceholder.forService` under the title, and no page is asked for.
- **The bar** (`_ShelfBar`): padding `space-lg` left, `space-sm` on the other sides. Two chips, *All* (the default) and *Unplayed*, are the arrs' own `MediaBrowseFilterChip` in ink, and the sort control at the end of the row is their `MediaBrowseSortControl`: *Name* (the default), *Date added*, *Year* (`StreamLibrarySort`). So a library on Radarr and one on Jellyfin read alike. A choice restarts the paging from the first page.
- **The wall**: a paged grid (`PagedGridView`, 50 a page) of captioned tiles, padding `space-xs` top and `space-lg` sides, with the nav bar's clearance at the foot. Columns come from `MediaGrid.columnsFor` over the width less the gutters, never fewer than 3; `gridGap` between tiles.
- **A tile** (`StreamPosterTile`): a 2 : 3 `ContentCard` under its Hero with the server's artwork, the kind's glyph when there is none, then `space-xs` and its caption (`MediaPosterCaption`, the arrs' own: the title in `label-small` 600 `on-surface`, the year in `label-small` `on-surface-variant`, one line each, ellipsised), so a poster with no artwork is still named. A cell is the poster and the caption measured at the reading size (`MediaPosterCaption.gridDelegate`), so at 200% the caption grows and is never cut. The watch state is the point of the tile: an item in progress carries a 3pt resume bar at its foot (`plateInk` over a 55% scrim), a series partly watched its unplayed count as an ink badge.
- **States**: *Unplayed* on Jellyfin or Emby with no household member chosen is not empty, since nothing was asked: it reads *Choose whose watch state to show* with *Pick a viewer*, which opens the connection's settings (a Plex token is its own viewer). An empty answer reads *This library is empty*, or under *Unplayed* *Everything has been played* with *Show all*. A first page that failed is `AppErrorState` naming the service; a later page that failed keeps the rows above and puts an `InlineErrorRetry` under them (*…the rest of this library did not load*).

Semantics: a tile is one button named by its title, its value the watch state and the year (*62% watched, 2010*); the bar and the badge are excluded. The chips carry a selected state; the sort control's hint rides on its child.

Do: keep the shelves of watching off this page. Don't: let a page that failed read as an empty library.

## States in the catalog

- An Emby movie library, whole and A to Z.
- *Unplayed* chosen (on this Emby nobody has played a movie, so every one stays).
- The same library in a 1280 desktop window.
- Text at 200%.
