# HomeModule

One module of the Home in the slab every module shares, the operator's modules of content (Continue watching, Coming
up, Arrived, Downloads, Requests, Now playing; Featured, which has no slab, is
[FeaturedPager](../FeaturedPager/README.md)), the three a person adds in Edit Home (Stack health, Storage, Discover
shelf), the requester's (Ready to watch, Your requests, Trending this week, Coming soon), and the two pieces of the
operator's Home that are not modules of content: Needs you, first by default and movable in Edit Home, and Set up next at the foot. A module decides
its state; the frame draws it,
so no module invents its own way of loading, failing or asking for a service.

Rendered from `lib/features/home/presentation/widgets/home_module_frame.dart` (`HomeModuleFrame`),
`lib/features/home/presentation/widgets/needs_you_banner.dart` (`NeedsYouLine`, its words from
`lib/features/home/domain/needs_you.dart`) and `lib/features/home/presentation/widgets/set_up_next_module.dart`
(`SetUpNextModule`, `EditHomeRow`, its suggestions from `lib/features/home/domain/set_up_next.dart`),
`downloads_module.dart` (`HomeDownloadsModule`, `DownloadRow`, words in `lib/features/home/domain/downloads.dart`),
`requests_module.dart` (`HomeRequestsModule`, its rows `DecisionRow` in
`lib/features/services/presentation/dashboard_sections.dart`), `now_playing_module.dart` (`HomeNowPlayingModule`,
words in `lib/features/home/domain/now_playing.dart`), `continue_watching_module.dart` (`HomeContinueWatchingModule`,
`ContinueWatchingRow`, words in `lib/features/home/domain/continue_watching.dart`, read by
`lib/features/home/data/resume.dart`), `coming_up_module.dart` (`HomeComingUpModule`, its rows `CalendarRow.home`, see
[CalendarAgenda](../CalendarAgenda/README.md), words in `lib/features/home/domain/coming_up.dart`),
`arrived_module.dart` (`HomeArrivedModule`, `ArrivedCard`, words in `lib/features/home/domain/arrived.dart`),
`stack_health_module.dart` (`HomeStackHealthModule`, `StackLightMark`, words in
`lib/features/home/domain/stack_lights.dart`, read by `lib/features/home/data/stack_lights.dart`), `storage_module.dart`
(`HomeStorageModule`, `StoragePoolRow`, words in `lib/features/home/domain/storage.dart`, read by
`lib/features/home/data/storage.dart`), `discover_shelf_module.dart` (`HomeDiscoverShelfModule`, its shelf
`DiscoverCarousel`), `ready_to_watch_module.dart` (`HomeReadyToWatchModule`) and `your_requests_module.dart`
(`HomeYourRequestsModule`), their words in `lib/features/requests/domain/my_requests.dart`, and
`home_module_parts.dart` (`HomeModuleLink`,
`HomeCoverageNote`, `HomeRowArt`, `HomeRowBar`), by
`test/design_catalog/home_module_catalog_test.dart`. Which modules a person's Home has, in what order, is the registry
`HomeModule` (`lib/features/home/domain/home_module.dart`) read through the person's saved layout; see
[EditHome](../EditHome/README.md).

The Home is drawn at 390, and what a wider page does with its modules is decided by the page's width alone, never by
the platform (`HomeMode`, `lib/features/home/domain/home_arrangement.dart`):

- **One column** under 780: the phone's, and wider than the reading well, 720 (`AppBreakpoints.wellInset`), the well
  centred, Featured as wide as the well and every module under it at the well's measure. Beside a title open on a
  tablet it keeps the phone's 440 column.
- **Pairs** from 780, two modules at the phone's measure (an iPad upright, a 1100 window): the page's whole width; two
  short modules next to each other in the person's order (Coming up, Downloads, Requests, Stack health, Storage, Set up
  next) share a row, halves of the width; every other module keeps the width.
- **Two columns** from 960 (a tablet on its side, a window from about 1200): Needs you across the top, then what is
  happening on the left (7 parts: Featured, Continue watching, Arrived, Now playing, Ready to watch, Your requests) and
  what waits on the right (5 parts: the short modules above), each in the person's order, the shelves across the page
  under them. `BalancedColumns` lays the two out and evens them by what each module drew: a module with nothing to say
  draws nothing, so while the taller column's last module, moved to the end of the shorter one, brings their heights
  closer, it moves; a column keeps one of its own. The modules keep their own gutters, so the columns need no gap.

A shelf of posters (Trending this week, Coming soon, the Discover shelf) runs across the page in every mode, its
heading and first poster on the column's line (`HomeWell`), so its posters scroll to the page's edge: cut at the well's
edge with the page empty beside it, a shelf reads as broken. Where a pointer reaches the page, a shelf's heading and
Arrived's carry back and forward at their end while the row runs past the window (`RailArrows`, `HomeModuleFrame.rail`).

## The five states

- **Loading** (`HomeModuleFrame.loading`): the module's name in the section role over the shape of its rows (two
  list rows unless the module passes its own skeleton, a poster row for Arrived). Never a spinner in the middle of the
  Home. Spoken `Loading downloads`.
- **Ready** (the default constructor): the name, the line under it in `meta` and `inkSecondary` (`2 wait for you`,
  `3 moving · 1 stuck · 40.4 MB/s`), an optional quiet link at the end of the heading, the rows. Rows are
  rows of the slab, a hairline between them, never cards inside it.
- **Nothing to say**: no frame. The module draws nothing and the next one moves up: the Home has no empty boxes. Only
  when every source answered: a source that did not answer is not an empty one.
- **Its sources did not answer** (`HomeModuleFrame.silent`): the module keeps its place and says which service and why
  through the classification (`coverageFailureSentence`), as a `FaultBand.section` (red, a source did not answer) or
  `FaultBand.partial` (amber, it answered with a fault), with Retry. What was last known may sit above it, at full ink (a cold start's last drawing, see *Last known* below): nothing is dimmed for being unreachable.
- **Away from home, its service only works there**: the same frame, but a grey `meta` line in place of the band, and no
  Retry, since nothing was asked: `Lidarr only works at home.`, and over the last drawing `Lidarr only works at home.
  As of 20:41.` (`LastKnownWords`, put there by `LastKnownMark`). A module whose other sources answered names the one
  left out the same way, over its rows (`HomeCoverageNote`). The header counts it apart: `7 of 7 answering · 6 only at
  home`.
- **Its service is not set up** (`HomeModuleFrame.needsService`): no slab yet, a dashed `edge` outline in its place,
  the service's mark in a 36pt tile, its headline (`Set up TrueNAS to see your storage`) over what it would show, and
  `Set up TrueNAS` as a quiet pill at the end, the whole outline one target. At a large reading size the pill goes under
  the words. Only for a module the person switched on in Edit Home; a module on by default whose service is missing is
  not drawn, and Set up next names the service once.

## Last known

At a cold start a module that keeps a last drawing draws it at once instead of its skeleton, through
`watchOrLastKnown` (`lib/features/home/data/home_last_known.dart`), and the Home says it once, under the header:
`As of 20:53 · checking now` (`HomeAsOfLine`; `As of yesterday 20:53`, `As of Wednesday 20:53`, then `As of Tue 29 Sep`),
`As of 20:53` alone once only failures are left, gone when the last module is live; the line folds away rather than
vanishing. The drawing is at full ink, with its own figures: times are made again against the moment of drawing (a
card the week left behind is gone), and a figure that runs (progress, time left, speed) is not drawn as if it still
ran. Continue watching is the one that draws where each title stopped, its bar and its time left, as they were: a stop is a
fact as of then, not a figure that runs. Requests draws its rows with Approve and Decline in place and the count it drew
(`50+` stays a floor, never a total), a request answered since is not drawn, and a requester known only by an email
address goes unnamed until the live answer comes. A module whose live read fails keeps the drawing over its failure
(`HomeModuleFrame.silent` with a child). What is kept, where, and for which connections is `LastKnownStore`'s (`lib/core/last_known/last_known_store.dart`): no
credential, no response body, dropped when the server, the person or the viewer changes. Needs you, the header's health
and Now playing never draw from it.

Featured draws its last slides with their two ways forward, `Play` included (what a media server held when it was
read; the server answers if it no longer does), and the room is lit by the slide in front from the first frame. A slide
of today is gone once today is another day, an arrival once the week has left it behind, and a download of today says no
figure (`Out on digital today · downloading`). Continue watching steps aside for the title a drawing leads with, as it
does for a live one.

Coming up draws differently from Arrived in one respect: a thing in the download queue is drawn as the state it was in
(`Out today · downloading`), with no percentage and no time it would finish, and its tone drained to neutral (the stale
queue row's rule: the state stays, the figure and the colour go); a thing whose day or time has come since the read
reads `aired` or `out today`, not `not aired`.

Downloads draws differently from Arrived, because it is where a drawing could lie most: each row keeps how far it got,
and its bar stays where it stopped, drained to a neutral with the figure in the secondary ink (the stale queue row's
rule, `DownloadQueueTile.sampleAge`); the time left and the speed are not drawn; no row is stuck, amber or offers a
remedy (a download that was stuck is a plain row until the live read says otherwise), and the footnote of blocked imports
is not drawn. The line under the name counts what moved and what waited (`3 moving · 1 queued`) only for a read every
queue answered whole, and `Nothing is downloading` is drawn only for such a read with no row, and not once an import is
known to have finished after it.

The slab is `slab`, `AppRadius.slab`, a `hair` edge, padding `gutter` × `slabY`, `md` between modules. A module about titles may hand the frame its first title's light (`HomeModuleFrame(light:)`, the `TitleLight.art` of a public picture): the slab then glows with it (`SlabLight`: the picture laid over the slab from 40 past its sides and 80 above its top, 360 tall, at 0.5, clipped to its corners, coming up over `motion.light`). Coming up and Downloads do.

## Needs you

One line, one target, first on the operator's Home by default (the person may move it) and absent when nothing is wrong (the header's `12 of 12
answering` already answers) or before anything answered (no space is held for it).

- A service that did not answer leads, the glyph red: `Radarr did not answer at 20:53`, and the line is its Retry
  (`Retry both` for two). Its faults cannot be seen while it is silent.
- Otherwise the largest group of equal faults leads, the glyph amber: `18 downloads need a manual import`; a single
  fault is a sentence about it (`Big Buck Bunny is stuck`, `The media indexer is failing`, `The certificate for
  nas.home.arpa expires in 6 days`). The line is Review, which opens the place that fault is fixed today.
- Connections that failed alike are one group, weighed as many as they are and said in one sentence, the way a module
  says them: `Seerr, Radarr and 11 others were reached but did not reply in time`, never the first of them and `+12`.
  Keyed on the reason, and on the credential only where it is named (two refused keys are one sentence, a key and a
  sign-in are two); a fault whose words name more than its reason (a gateway in front) is said alone.
- `+2` when more things need the person. A request waiting for approval is not a fault: it is never in Needs you.
- `door` under a `hair` edge, `AppRadius.button`, at least 52pt tall. At a large reading size the count and the
  way in go under the sentence.

## Continue watching, Coming up, Arrived

- **Continue watching**: up to three titles started and not finished, on every Jellyfin, Plex and Emby. A row is a 112×63
  picture (the episode's still, a movie's art), the series in `row` 600 (a movie's title), `S2 E3 · The Second Cycle`
  (a movie's year), `5 min left` in ink, and an ink bar: how far somebody got is not a status. At a large reading size
  the words go under the picture. The line under the name is the server. A Jellyfin or Emby set up with a server key and
  nobody chosen asks once, in an outlined row: `Which Jellyfin user are you?` (`Which Emby user are you?` on an Emby) · `A server key sees every user; pick yours
  once`, to that connection's form where the picker is. Absent when nothing is in progress and every server answered,
  and when its only title is already Featured's first slide (while Featured is on the Home).
- **Coming up**: what comes out or airs from today to three days on, three rows (`CalendarRow.home`: the day leading,
  an episode's time opening its status), then `Calendar` in the heading to the calendar's page. Tones as the calendar
  has them: downloading blue, not out yet and not aired neutral, never amber. Nothing in the window is a calm line,
  `Nothing comes out or airs by Friday` · `The calendar has the rest of the month.`, never an absence; absent only
  without an arr that dates things. A connection that did not answer is named over the rows.
- **Arrived**: one card per title imported in the last seven days, the newest first: a 200 pt card of 16:9 art (the
  title's fanart, else its poster), the title, then `2 h ago · Radarr 4K` (the connection only while the service has
  two). A movie on two Radarrs is one card; a series is a card when it is new to the library, not with each new
  episode; an album is one card. The line under the name is `Last 7 days · 4 new`, never "this week"; with a library
  silent, who the count is from, `Last 7 days · 2 from Radarr`, and the silent one named over the rail. A failed import
  is not an arrival: Needs you has it. Absent when nothing arrived and every library answered.

## Downloads, Requests, Now playing

Each row is the 36×54 art (`HomeRowArt`: the poster, or the service's plate), the title in `row` 600 and a quiet line
under it, a hairline between rows. A 4pt bar (`HomeRowBar`) says how far something got.

- **Downloads**: four rows at most, no sizes. A moving download says `88% · 1 min` beside its title in blue
  (downloading is information), its release under it in mono (a machine string, exactly as named), a blue bar. A
  stalled or failed one is chosen first and drawn last, its value amber (`Stuck at 47%`, `Failed`), its bar amber, and
  under it the remedy Needs you chooses for it, taken the same way (`stuckActionsFor`, `StuckActionTaker`): `Try another
  download` in the amber fill with a 44pt More (`Remove`, `Keep waiting`), `Look for peers again` where qBittorrent can
  ask (somebody sharing it has the whole file, or no arr asked for it), `Open in Transmission` where only its client is
  known. Once one was taken, the note Needs you's card says (`Dropped · Radarr is looking for another download`, Keep
  waiting's with Undo) stays in its place until the Home is read again; a stall kept waiting offers no remedy until its
  day is up. The line under the name counts `3 moving · 1 stuck · 1 queued` and
  the clients' speed (`1 queued` alone when that is all there is): a download waiting its turn at its client is queued,
  not moving, and has no row here. The speed is `—` while a client that is set up did not answer; with no client, `Speeds come from your download client`
  under the rows. A blocked import is not a download: the footnote names it once (`18 need a manual import · in Needs
  you`). Nothing moving is `Nothing is downloading` with `The last download finished at 18:52.`, and the link reads
  `Activity`. At a large reading size the value goes under the title. The module is read again every 30 s while the
  Home is on screen.
- **Requests**: `2 wait for you`, from Seerr's own count. A row says who and when (`Anna · 2 h ago`); under it
  `Approve` in the ink fill and `Decline` outlined, the same width: the pair every list of waiting requests draws
  ([RequestAnswerControls](../RequestAnswerControls/README.md), `.row`, busy while an answer is on its way). Neither
  takes a tone: a request is not a fault. Approved or declined, here or from any other list, the row says what happened
  (`Approved · sent to Radarr`, `Declined`) without its buttons, in its place, until the Home is read again; a request
  answered from another list leaves the module at once. `See all requests` when more wait than the rows show.
- **Now playing**: one row per playback, a disc with the viewer's initial, `Anna · Sintel` (an episode by its code),
  `Living room TV · 9 min left` (`Paused` while the player holds it), an ink bar: watching is not a status. The line
  under the name is the server (`Jellyfin`). Absent when nobody watches; a server that did not answer keeps it in place.
  Read again every 30 s while the Home is seen.
  - **With Tracearr** the list is one: a playback the server and Tracearr both describe is one row, the server's (what
    Tracearr adds: its reasons for a transcode where the server gave none, the person's picture in the disc over the
    initial). A playback only Tracearr sees (a server Cupola is not connected to) is appended and leads its line with
    `Plex · through Tracearr`, so a line cut at the end keeps the mark; it has no Stop, Play or Watch, and a tap opens
    Tracearr's Live. The header names the servers once, the through ones after the others (`Jellyfin · Plex · through
    Tracearr`). Tracearr alone makes the module exist (`Needs Jellyfin, Plex, Emby or Tracearr` in Edit Home).
  - **Tracearr silent**: the servers' rows stay, and one line over them says `Tracearr did not answer.` and
    `What only Tracearr sees is not shown.` (red, as any server that did not answer; amber for a refused key).
  - **A Plex row's disc** is also the way to the person's page in Tracearr, where Tracearr knows them (Plex has no
    Users tab to hold that door; a screen reader gets it as `Open Luca in Tracearr`, an action of the row). Every row
    keeps one 44pt slot for its disc, 36pt of it the disc and 8pt the gap before the text, and the door takes the whole
    slot as its target, so a row with a door has its text where the rows without one have it. The person is found by
    the viewer's id on the server; a name is tried only for a session that carries no id.
  - **See all N** opens the first media server's own page among the rows, the list it counts; Tracearr's Live only when
    every row is one only Tracearr sees.

## Stack health, Storage, Discover shelf

Off until the person switches them on in Edit Home: the header already says how many services answer, and the rest
lives a tab away. Each sits after Now playing.

- **Stack health**: `Stack`, the line `12 of 12 answering · 3 faults` (`Checking 12` before anything answered), then
  every configured service as its monochrome mark (`ServiceKey.icon`) in a 44pt `fillStrong` tile, the Stack's order,
  six to a row on the phone. Each mark has one 9pt light at its corner: green answering, amber a fault (a refused key, a
  connection silent beside one that answered, or a fault Needs you holds for it), amber too when every connection was
  reached and none replied in time (`timed out`, never among the answering), red when every connection did not answer,
  a hollow ring while it is asked. A light eases on once (`motion.standard`) and keeps its colour while the
  probe is read again. Faults are counted one per amber light, so the figure, the lights and the names under them agree
  (Needs you is where the faults themselves are counted); the line says `1 of 4 answering · 2 timed out`. Under the
  marks: a service that did not answer, red, with Retry; otherwise the ones that timed out in one amber sentence with
  Retry (`Radarr and Sonarr were reached but did not reply in time.`); otherwise `Faults: Sonarr, qBittorrent and
  TrueNAS` in amber, five names and then `and 2 others`; while nothing has answered,
  `Asking each service`. The marks are one target, to Stack. Switched on, it never steps aside.
- **Storage**: `Storage`, the line `TrueNAS` (the servers it read), then each pool, up to four: its name and share in
  `row` (`tank` · `72%`), a 6pt bar in ink on `fillStrong` (usage is not a state), `31.2 of 43.6 TB` and its state
  (`Healthy · scrubbed Sunday`, `Degraded`, a dot green or amber), and under it each disk in trouble on an amber wash
  with a chevron (`Disk sdd reports 8 errors`, `Disk 3 is disabled`). A pool TrueNAS does not call healthy is read
  again with its topology, the only answer that names the disk. An Unraid array is one pool, `Array`. The pool is one
  target, to its page. Read again every 60 s while the Home is seen. Without TrueNAS or Unraid it asks for TrueNAS.
- **Discover shelf**: no slab. Seerr's `Trending this week` as Discover draws it (`DiscoverCarousel`, its posters
  [CatalogPoster](../CatalogPoster/README.md)), the library's state on every poster, its heading the way into
  Discover. Never a count. Without Seerr it asks for Seerr: `Set up Seerr to discover movies and series`. A shelf that
  has its posters keeps them when it is asked again and when that read fails (`DiscoverCarousel`: no skeleton, no
  line in their place); only a shelf with nothing known says `Seerr did not answer, so this row is missing.` and
  Retry.

## The requester's Home

Everything comes from her own Seerr session; no fault, no service named but her player.

- **Ready to watch** (`HomeReadyToWatchModule`): her Featured, drawn by [FeaturedPager](../FeaturedPager/README.md)
  with one slide. The newest thing she asked for that arrived in the last seven days: `● Ready to watch · since
  18:40` above the title, `You asked for it on Sunday · TMDB 7.1` under it, `Watch on Jellyfin` (Seerr's link to it in
  the player its server is set up with, `Watch on Plex`, `Watch on Emby`, `Watch` when Seerr does not say) and `Details`. The room takes
  the title's light. A second arrival is one line under it, `Also ready · Sintel` · `On the server since Wednesday`.
  Nothing arrived: the module is absent and Your requests leads. At a cold start it draws what it last drew (see
  *Last known*): the same title, so the room keeps its light, and Watch where it was; an arrival the week has left
  behind is cut again, and a drawing with nothing left is the skeleton until her Seerr answers.
- **Your requests** (`HomeYourRequestsModule`): `Your requests`, `3 on the way`, up to three
  [RequesterRequestRow](../RequesterRequestRow/README.md)s, what moves first, then what waits, then a no of the last
  seven days; `All your requests` to her tab. Nothing on its way: `Nothing on its way` · `Find something to ask for in
  Discover.` and `Discover`. At a cold start the rows are the last drawing's, read as the list reads after a
  failure: no `62%` and no `Ready around 21:10`, since a drawing does not run, so a download reads `On its way` ·
  `Being fetched`; a time is said again against the moment of drawing (`Asked 3 h ago`), a no the week has left behind
  is gone, and a drawing with nothing left to list is the skeleton, never `Nothing on its way`.
- **Trending this week** and **Coming soon**: Seerr's shelves as Discover draws them, the heading the way into
  Discover and into her calendar; Coming soon says each poster's day (`Fri 2 Oct`), no region and no count. Both keep
  the posters they have under a reload or a failure (the heading's line is the page's, above), and at a cold start
  draw the posters they last drew until the answer comes: each with what Seerr held of it, never a download's ring
  (a title on its way reads `On its way`), and Coming soon cut again to the titles not out yet.
- **The server**: one line above everything when any of her reads did not come back, `Can't reach the server since
  20:41` (the time the server first did not answer, none when the app did not see it stop) and `Retry`, or `You were signed out` and `Sign in again`; the modules under it keep what they last knew and
  draw no failure of their own.

## Set up next and Edit Home

- **Set up next** (`SetUpNextModule`): at most three lines, then `All services`. First what another connection already
  knows (`foundCandidatesProvider`: every Seerr and Prowlarr, each server once): `Add Radarr 4K`, its line led by a key,
  `Seerr knows it · key found` (`Prowlarr knows it · paste its key`), opening the service's form filled in from the
  source (`ServiceRoutes.addFound`). Then the services the stack lacks, each with what it adds (`Set up Jellyfin · Play,
  Continue watching and Now playing`), ordered by how much; a service a known server stands for is not suggested again.
  A Plex or an Emby stands for Jellyfin, any download client for the four. Each row carries its service's mark in a 36pt tile.
  Absent when nothing is missing. Each row opens its form in Settings, whose way back leads to the Home.
- **EditHomeRow**: the last thing on the operator's Home, a dashed `edge` around `Edit Home · Reorder and hide
  modules`, opening `/home/edit`.

## Semantics

A module's heading is one header node: its name and the line under it (`Requests, 2 wait for you`). Needs you is one
button whose label is the whole sentence, the way in at its end (`18 downloads need a manual import, and 2 more things
need you. Review`), announced when it appears. Each Set up next row is one button, its line as the value.

## States in the catalog

Each sheet is drawn in the dark and the light room: the frame ready, loading, silent and needing a service; Needs
you led by a group, by one fault and by a silent service; Set up next over Radarr, Sonarr and Seerr, and with what Seerr and Prowlarr know first; Downloads moving
with one stuck and one queued, with qBittorrent silent, and with nothing moving; Requests with one row answered; Now playing with two
playbacks; Continue watching with two titles and asking who you are; Coming up over three days, and with Lidarr silent
and nothing by Friday; Arrived over a week, with Radarr 4K silent, and as last drawn at a cold start under the Home's line; Stack health with three faults, with Radarr
silent, and checking; Storage with a disk in trouble, and with TrueNAS silent; Storage and Discover shelf asking for
their services; the Edit Home row; text at 200% with Downloads, with Stack health, Storage and Discover shelf asking for
Seerr, and with Continue watching, Coming up and Arrived. The requester's Ready to watch and Your requests are drawn on
the [RequesterRequestRow](../RequesterRequestRow/README.md) sheet.

## Do / don't

- Do let a module draw nothing when it has nothing to say, and only then.
- Don't put a card inside the slab, or a second Retry under a silent module.
- Don't paint Approve green or Decline red: neither is a state. Red is a service that did not answer.
- Don't paint a full pool amber: only a state takes colour, and 90% used is a figure.
- Don't say `Set up X` twice on one Home: a missing service is named by Set up next, once.
