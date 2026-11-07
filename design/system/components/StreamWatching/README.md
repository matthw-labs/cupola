# StreamWatching

What a media server says about watching, beside who is watching now: *Continue watching* (*On deck* on Plex), *Next up* and *Recently added*. Drawn whole in the server's Activity (`StreamWatchingSection`) and as a rail each on its Overview, the glance (`StreamWatchingRail`). These shelves left the library page, which is the library and nothing else ([StreamLibrary](../StreamLibrary/README.md); decision `P-stream-library-browse`).

Rendered from `lib/features/stream/presentation/stream_watching.dart`, as `lib/features/jellyfin/presentation/jellyfin_tab_screens.dart` (Jellyfin and Emby's Activity) and `lib/features/plex/presentation/plex_tab_screens.dart` (Plex's Activities) compose it, by `test/design_catalog/stream_watching_catalog_test.dart`, against the demo world's fake Emby and Plex.

- **The shelves** (`streamWatchingShelvesOf`): Jellyfin and Emby draw all three; Plex draws *On deck* and *Recently added*, since its on deck is what is in progress and what is up next at once. Each reads 12 titles (`streamWatchingLimit`), each title once.
- **In the Activity** (`StreamWatchingSection`), under *Now playing*: a `SectionHeader` with the shelf's name and no chevron, then, inside `space-lg` gutters, *Continue watching* and *Next up* as the Home's own `ContinueWatchingRow` (the picture, the series and the episode, how much is left and the bar), and *Recently added* as a grid of 2 : 3 `MediaPosterCard`s, three to a row on a phone (`MediaGrid.columnsFor`), `gridGap` apart. Loading is three skeleton rows.
- **On the Overview** (`StreamWatchingRail`): a `ServiceOverviewSection.bleed` whose heading leads to the Activity tab (*Activity*, *Activities* on Plex). *Continue watching* and *On deck* are wide tiles, a 176 × 99 picture with a 4pt bar `space-xs` under it; *Recently added* is 96 × 138 posters; each with two caption lines in the meta role (title, then the episode or the year). At most 10 a rail. The rail's height is its parts', grown by the reading size so the captions are never clipped. *Next up* stays in the Activity. Loading is a skeleton row the rail's height.
- **States**: a watch state (*Continue watching*, *Next up*) on Jellyfin or Emby with no household member chosen reads *Choose whose watch state to show* with *Pick a viewer*, never an empty shelf. An empty shelf says so in its own words, quiet and never a fault: *Nothing part-watched*, *Nothing up next*, *Nothing added lately*. A shelf that did not load is one `InlineErrorRetry.flush` naming what is not shown (*…what was added is not shown*) under the heading that still stands.

Semantics: a poster is one button named by its title with the year as its value; a `ContinueWatchingRow` speaks one sentence. The rail's heading is a door that names the tab it opens.

Do: keep each shelf reading the connection the visit has in view. Don't: put these shelves back on the library page.

## States in the catalog

- Emby's Activity: *Now playing*, then the three shelves.
- Plex's Activities: *Now playing*, *On deck* and *Recently added*.
- The Overview's rails on Emby and on Plex.
- The rails with text at 200%.
