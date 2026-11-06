# FeaturedPager

The Home's one authored moment: up to three titles, one in front, each with its wide artwork, its line and its two
ways forward, moving on by itself and stopping whenever a person is in the middle of something.

Rendered from `lib/features/home/presentation/widgets/featured_pager.dart` (`FeaturedPager`, `FeaturedPage`,
`FeaturedAction`, `FeaturedSkeleton`), by `test/design_catalog/featured_pager_catalog_test.dart`. On the Home it is
`HomeFeaturedModule` (`lib/features/home/presentation/widgets/featured_module.dart`), its slides chosen by
`lib/features/home/domain/featured.dart` from what `lib/features/home/data/featured.dart` reads.

## The slides

At most three, in this order, each only with wide artwork and never a title twice:

- **What somebody was watching**: the first title in progress on a Jellyfin, Plex or Emby, `Continue watching · S2 E3 · 5
  min left`; `Resume` opens it in its server's own client, `Details` its page.
- **The newest arrival**: the newest movie or series imported in the last seven days (an album stays in Arrived),
  `New on your server · 2 h ago · Radarr 4K`; `Play` where a media server says it holds it, else `Details` alone. On a phone a Jellyfin or Emby title's Play asks which app plays it (each server's own: Emby's app and its browser, never a Jellyfin player), unless one was remembered (`playWith`).
- **Out today**: a movie out today or an episode that airs today, `Out on digital today · downloading 62%`, `S3 E1 ·
  premiere · airs today at 21:00`; `Details` leads, `Queue` beside it while it downloads.

A source that did not answer gives no slide and no failure: the module that shows it whole names it. Nothing to
feature: the module is absent and the next one moves up.

The requester's Ready to watch is the same pager with one slide (`HomeReadyToWatchModule`, see
[HomeModule](../HomeModule/README.md)): a line above the title with its dot (`FeaturedPage.eyebrow`, `● Ready to watch
· since 18:40`, in `meta` 600, the dot on its first line), the group named for the module (`FeaturedPager.label`).

## Parts

- **The art box**: the slide's artwork, `AppRadius.slab`, 214 tall on the phone and growing with the well
  (`artHeightFor`, as the Media page's backdrop). Its glow (`AppElevation.hero`) is the slide's light. Tapping it opens
  the slide's page.
- **The copy**: the title in `feature` (two lines, three at a large reading size), the line in `body` and `inkSecondary`,
  then the lit button (`mediaLeadStyle`: the slide's tinted fill in the dark room, its tinted primary under white, the
  ink while no light is known) and the quiet outlined one, 104 wide at least. At a large reading size the two buttons
  go one under the other.
- **The control**, beside the title (in a row of its own under the art at a large reading size), one 44pt button: the pause glyph and a pill per slide, the one in front 24 wide
  and filling with the slide's light as its time runs, the others 6pt dots.
- **With a screen reader or Reduce Motion**, under the art: a 44pt button per slide (`Show slide 2 of 3`) and the
  control, which reads Play.

## Movement

One slide every `motion.dwell` (6 s). The artwork crossfades over `motion.image-xfade` (900 ms) and drifts from
`motion.kenburns.from` to `motion.kenburns.to` across `motion.kenburns` (14 s, alternating), each slide on its own
clock, which runs only while it is in front. The copy crossfades over `motion.text-xfade` (700 ms), rising
`motion.text-xfade.rise` (10). The room takes its light from the slide in front over `motion.light` (1.5 s).

It stops while a finger is down anywhere on it and for `motion.dwell.hold` (1.2 s) after; while less than half of it
is on screen; while the page is not the one in front or the app is away; and with the control. With a screen reader
or Reduce Motion it starts paused; Reduce Motion also drops the drift and the rise, and every crossfade takes 150 ms.
One slide: no control, nothing moves.

**Touch safety.** A button acts on the slide that was in front when the finger came down: a touch in the first half
of a change brings the slide that was leaving back, and it is that slide's action that runs.

## Semantics

The pager is a group named `Featured`. The art box is one button that says the slide in one sentence (`Spring, new
on your server, 2 h ago, Radarr 4K`) and opens it; the title and the line are silenced under it; the two buttons say
their labels. The control says `Pause featured, 1 of 3` or `Play featured, 1 of 3`. A slide behind the one in front
is out of the tree.

## States in the catalog

Each sheet is drawn in the dark and the light room, lit by the slide in front: continue watching in front; the newest
arrival with Play; out today with Queue; one slide no server holds; screen reader or Reduce Motion; loading; text at
200%.

## Do / don't

- Do take the light from the picture the slide has drawn: it is read from the same cache, so a server that wants its
  credential for artwork still lights the room.
- Do light a cold start from its first frame: until the picture is drawn and read again, the slide is lit by the light
  the same picture lit the room with last time (`keptTitleLight`, kept beside the Home's drawings, never for an address
  that carries a credential). Read half a second in, the button turned from ink to the title's colour under the eye.
- Don't draw a failure here: Featured features what answered.
- Don't let a slide move under a finger, or a button act on a slide the person did not see.
