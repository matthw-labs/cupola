# NowPlaying

Who is watching, on a media server's Overview (Jellyfin, Plex, Emby): one slab of the room, lit by the first title, with the way to the tab that lists the playbacks.

Rendered from `lib/features/stream/presentation/widgets/stream_session_slab.dart` (`StreamSessionFeature`, `StreamSessionLine`), as `StreamNowPlayingSection.slab` in `lib/features/stream/presentation/widgets/stream_now_playing_section.dart` composes it, by `test/design_catalog/now_playing_catalog_test.dart`. Names, screens and figures are sample data.

## The slab

- A `ServiceOverviewSection` headed *Now playing*, linked to the tab that lists the playbacks: Jellyfin's and Emby's *Activity ›*, Plex's *Activities ›* (`opens the Jellyfin Activity tab`, or Emby's). It glows with the light of its first title (`SlabLight`), read from the public poster the arrs hold for it (`streamSessionPosterProvider`); a title no arr holds leaves it unlit.
- **One playback** (`StreamSessionFeature`): the title's wide picture across the slab (16:9, `radius-md`): the server's backdrop or an episode's still through its key, else the public poster, else the server's poster, cropped to fill. Then `space-md`, *Anna · Sintel* (`nowPlayingTitle`: who, the title and an episode's code) in `title-medium` 600, two lines at most; `space-xs`; the screen in `body-small` in the secondary ink and, beside it, a 6pt dot and how the file goes out in `label-medium` 600, both in the delivery's tone (`StreamSession.deliveryTone`: green for a direct play or stream, amber for a transcode, with the server's reasons after a `·`; *Paused* first while the player holds it). Then `space-sm`, the bar (3pt, `radius-xs`, the ink on `fill.track`: watching is not a status) and *9 min left* in `label-medium` tabular in the secondary ink. Under it the controls the server allows, right-aligned.
- **Several** (`StreamSessionLine`, one per playback, a hairline and `space-md` either side between them): a 112 × 63 thumbnail of the same picture beside the words (title in `title-small` 600 on one line, the screen on its own line, the delivery under it), then the bar and what is left across the slab, then the controls.
- **Controls** (`StreamSessionActions`, shared with the Activity tab's cards): Pause or Resume and Message on Jellyfin and Emby, Stop on all three (on Plex only with Plex Pass, absent otherwise); each a 48pt `IconButton` in the secondary ink with its tooltip as its name. None drawn when the server allows none. A Plex card on the Activities tab (`StreamSessionCard`) also carries `Open this person in Tracearr` first among them, a 48pt `IconButton`, where Tracearr is set up and knows the viewer (Plex has no Users tab to hold that door, as Jellyfin's and Emby's do); the slab never draws it.
- **Nobody watching**: the quiet line, *Nobody is watching right now* and a dashed rule. A Plex token of a shared account: the blue owner-only note. A read that failed: its own line in the slab, as every Overview section.

## Freshness

The figure in the room's head (*1 stream*), this slab and the room's light read **one** answer: the sessions provider of the connection in view. While the Overview (or the Activity tab) is the page on screen, it is read again every 15 s (`streamSessionsPollProvider`, gated on `PageActivity`), so the three move together without a pull; and at once on opening when the answer in the cache is one the page did not just read (the Home's, of any age). Stack runs the same poll for every media server connection while it is on screen, so a row's *2 streaming* is never older than that.

## Semantics

Each playback is one node: its title as the label and the sentence `Anna, Sintel, Direct play, on Living room TV, 40% in, 9 min left` as its value; the picture and the parts are silenced. Each control stays its own button.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- One playback on Jellyfin, with every control.
- Two playbacks on Plex, Stop alone, one transcoding.
- One playback at 200%.

## Do / don't

- Do light the slab only from a public picture; the server's own artwork travels with its key and lights nothing.
- Don't sum the playbacks' bitrates into a total: neither server reports throughput.
- Don't read the sessions through a second provider for a figure: two caches of one read is how the figure and the slab came to disagree.
