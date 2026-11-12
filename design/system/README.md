**The room takes its light from the title.** Cupola is a native client for a self-hosted media stack and the machines under it: nineteen services, five platforms. The artwork of whatever leads a screen lights the room behind it, the way a television's ambient light spills onto the wall; everything else is quiet. The interface itself is monochrome: colour reaches it from two sources only, **the content** (as light) and **the state of things** (as five tones). Never from decoration, never from a service's brand.

Calm at rest, tactile on touch, honest when something breaks. These rules, the tokens and the pictures the app's own widgets render (the design catalog) are the specification, and every value quoted here is the one the code ships. The values live in `design/tokens/` and are generated into the app and into `tokens.json`. Edit them there, never here. Where the code does not yet do what the direction asks, the line says **Today** and **Direction** plainly.

## Principles

In order of precedence: when two collide, the higher one wins.

1. **An answer before a list.** Every top-level screen answers its question in the first 390×600 pt.
2. **Content before mechanism.** Titles and artwork lead; the service name is metadata.
3. **Colour is information.** Light means content, a tone means state, and nothing else is coloured. A switch that is on is not green, a watched episode is not green, a service mark in a list is monochrome.
4. **Every fault carries its remedy**, grouped (`18 need a manual import · Review`) and within thumb reach.
5. **One primary action per screen**, chosen by the state and by who is looking.
6. **Promise only what works.** A figure without a source is `—`; a background check says when it ran (`Checked 2 h ago`), because the OS decides when that is. Better to delete a control than ship one that fails.
7. **One authored moment per screen**, not an entrance on everything. Every animation has its Reduce Motion answer.

## Who Cupola is

Cupola says who it is in two sentences, and only these two: the claim, **A Cupola over your server.**, on the Welcome, and the promise, **Nothing left in the dark.**, on the close of the way in, said only when everything the visit tried has joined. A cupola is the lantern on a roof that lets light into the room below; the app is that lantern over the person's server, and the promise is what the light is for. The rest of the system already speaks this way: the two rooms, dark and paper, the lamp that is the neutral light of today, the ring that lights with what answered. The sentences live once in the code (`OnePunchline.claim`, `OnePunchline.promise`); the README, the store and every other place that says who Cupola is quote them exactly, and `test/core/identity/signature_guard_test.dart` holds it.

- **Few signature points, each chosen.** The launch screen (the mark on the room's ground), the Welcome (the claim), the close (the promise and `Enter Cupola`), the foot of Settings on a phone (the mark, the claim, `Cupola <release> · Apache-2.0`, the release with its beta suffix), the licence page (the mark and the version), the README and the store. Nowhere else: an empty state, an error or a notification says what is true, never who Cupola is.
- **Cupola names itself only when it is the one acting or refusing:** *Cupola does not trust this certificate*, *Cupola did not send the key over http*. Never *we*, *our* or *I*: the first person belongs to the person (`I have a Seerr account`, `Hide what I have`).
- **It never sells.** No *seamless*, *powerful*, *simply*, *just*, *magic*, no *Welcome to Cupola*; the claim is the one sentence about itself, and it is a fact about where the app stands.
- **It promises only what it keeps** (principle 6), in a permission prompt as anywhere: the prompt says what the permission is for, never what the app will never do. *Cupola never contacts plex.tv* was false the day a Seerr sign-in went through it.

## Words

**Plain, warm, short.** Say what happened in the words of the person reading; the service's own term waits under *Why?*. People, then things. One line per fact: a count and a verb beat a paragraph.

- **English only, on purpose.** No localization layer; copy is written once, in American English (`color`, `catalog`, `canceled`, `-ize`), and `test/core/theme/lexicon_guard_test.dart` holds the spelling.
- **Sentence case everywhere**: headers, buttons, tabs, empty states, section labels, figure labels and badges. There is no uppercase voice: the labels that wore `label.eyebrow` now set the `micro` role in sentence case, and no site uses the eyebrow any more; do not add one. Only what is itself an abbreviation keeps its capitals (`EN`, `MKV`, `H264`).
- **A verb on every button**, and the verb says what will happen: `Try another download`, `Remove and delete files`, `Scrub tank`.
- **Name the service, not the mechanism**: `Open in qBittorrent`, *Sonarr lists nothing under Specials yet.*
- **No emoji, no exclamation marks, no apology, no marketing voice.** An empty state says what is true and, if useful, what to try.

**The lexicon, the formats, the requester's words and the words of another device**, with the **Never** list, are in [words.md](words.md): one word per state, the same on every screen, held to the code by `test/tool/brand_book_guard_test.dart`.

## Colour

A near-black room, lit from the content. Dark is the primary theme; light is **the day room**, a complete parallel palette rather than an inversion. Both are fixed: platform Dynamic Color is never harmonised in (**The Fixed Palette Rule**).

**The room.** `CupolaRoom.of(context)` carries the room as drawn (translucent lines, fills and inks); the colour scheme carries the same values flattened on the ground, so a contrast can be measured against any surface.

| `color.room.*` | Dark | Day | What it is |
|---|---|---|---|
| `ground` | `#0A0A0D` | paper `#F6F4EF` | The floor (`surface`). Nothing sits under it. |
| `slab` | `#121218` | `#FFFFFF` | A section, a card, grouped rows (`surface-container`), always with its `line.hair` edge; on paper also a soft lift. |
| `raised` | `#17171D` | `#FFFFFF` | Sheets and dialogs (`surface-container-high` in the dark). |
| `door` | `#16161C` | `#FFFFFF` | Discover's doors and tiles, and every group, slab and banner a page sets on its ground: a place you walk into, white paper in the day room. Never `fill.quiet`, which in the day room is a step below the ground (`test/core/theme/group_surface_guard_test.dart`). |
| `enamel` | `#1A1A1F` | `#FFFFFF` | Floating bars only (tab bar, rail, compact bar, selection bar), at `opacity.glass-surface` 0.95. |
| `menu` | `#1D1D24` | `#FFFFFF` | Popovers. The day room lifts menus by shadow, not by tone. |
| `toast` | `#202028` | `#16151A` | The toast (`inverse-surface`); in the day room the ink reversed. |
| `scrim` | ground at 70% | ink at 40% | Behind a sheet or dialog. |

**Ink** is four steps and never more: `ink.primary` (`#F7F6F2` · `#16151A`) for text and the ink button; `ink.secondary` (white 72% · ink 70%; flat `on-surface-variant`); `ink.tertiary` (white 60% · ink 65%; flat `dim-text`), which still clears 4.5:1 on a slab and 5.4:1 on paper; `ink.disabled` (38%) for disabled controls only. `ink.on-ink` is the label on the ink button and on any bright fill. Tertiary text in code is `CupolaThemeColors.of(context).dimText`, never `AppColors.onSurfaceDimDark`, which is the dark value in both themes.

**Lines and fills.** `line.hair` (white 7% · black 6%) is a slab's edge and a divider; `line.edge` (10%) a control's edge and a field at rest; `line.focus` (the secondary ink) the focus ring, 2pt wide and 2pt outside the control so it shows on the ink button too, and a focused field's edge. `fill.quiet` (6% · 5%) under chips at rest, fields and the segmented track; `fill.control` (8%) under ghost and icon buttons; `fill.strong` (12%) the selected tab pill and a switch track at rest; `fill.track` (12%) a progress track; `fill.skeleton` (8%) a skeleton block, swept by `fill.skeleton-glint` (white 14% · white 55%), a band always brighter than its block, so loading passes as light in both rooms. **The interactive colour is the ink**: `primary` is `ink.primary` in both rooms, so a selected chip, a selected segment and the ink button are ink fills with `on-ink` labels (`test/core/theme/chip_label_test.dart`: the chip theme resolves its label colour by state, since a FilterChip reads no other).

### The five tones

A closed set: nothing outside state borrows a tone (**The Closed Tone Rule**). Every status also carries a word or a glyph: colour is never the only channel.

| Tone | Dark | Day | Means | Never means |
|---|---|---|---|---|
| **Green** `tone.green` | `#5FE39A`, dot `#34D17F` | `#0F7A45` | available, complete, healthy | on, selected, watched |
| **Amber** `tone.amber` | `#F7C23A` | `#8F5E00` | a **fault**: failing, stuck, errored, stopped unexpectedly, expiring, answered but refused | the backlog, anything stopped on purpose |
| **Red** `tone.red` | `#FF8A7A`, dot `#FF6B5B` | `#B8322A` | **did not answer: unreachable, and nothing else** | a failed download, a missing file, a rejected release, a refused key, a destructive action |
| **Blue** `tone.blue` | `#9DB8FF` | `#2F5BD3` | queued, in progress, informational, waiting on someone | — |
| **Neutral** `tone.neutral` | white 72%, hollow dot | ink 65% | the **backlog**: missing, wanted, cutoff unmet, not aired, not out yet, deliberately stopped, deleted | — |

- **Painting the backlog amber is the commonest way this breaks.** In a media stack a list of things to fetch is the resting state, not damage. Only an unexpected stop is amber.
- **Green is quiet.** In a status line and on a poster mark the dot carries green and the words stay in secondary ink, because healthy is the normal condition. Blue, amber and red colour their words.
- **Only amber has a fill, and only on the remedy of a fault**: `tone.amber-fill` under `tone.amber-ink` `#2A1E00` (day: `#F2B531`). A fault chip may sit on `tone.amber-wash` (12% · 18%).
- **A destructive action is never red.** A delete, a stop, a reset is a neutral control whose verb says exactly what will happen; if it cannot be undone, one neutral sentence says so (*This cannot be undone.*). No red fill, glyph or banner, on the confirmation or on the button that opens it. A destructive row may sit apart and carry a firmer haptic; it never changes colour. `test/core/theme/neutral_destructive_test.dart` holds this: no button style or dialog in `lib/` is built with red, no delete control is red, and every confirm label is a verb with its object.
- **Fill byte versus ink.** The tone bytes are fills (dots, bars, washes) and a fill keeps its byte. As text, a tone goes through `statusToneColor(scheme, tone, surface:, tintAlpha:)`, which walks it until it clears 4.5:1 on the ground it actually lands on, wash included. The dark room's tones clear the bar untouched; only paper walks. Never paint `AppColors.success/warning/error/info` or a room tone as text directly. `test/core/theme_light_contrast_test.dart` measures every ink on every surface in both themes, keeps each fill on its own byte, and keeps the recovery ink off the red; `test/core/widgets/accent_ink_contrast_test.dart` measures the shared widgets against the composite they sit on.
- **The Luminance Rule.** A label on an opaque fill takes `ServiceTheme.foregroundOn(fill)`: white or `ink-on-bright`, whichever measures higher. `test/core/theme_test.dart` holds every filled scheme pair to it, and holds tertiary and secondary text to AA in both rooms.

### The title light

The light is derived from the artwork, never picked, and a room with none keeps the neutral lamp. How it is derived, what leads each room, and how the chrome and the veils take it: [light.md](light.md).

### Service accents are data, not paint

Each service keeps its accent in the registry (`ServiceKey.brandAccent`, `color.service.*`), and nothing in the interface paints it: not the nav bar, not a wash, not a button, not a mark. What a surface is handed for a service is `ServiceKey.accent`, which is the lamp for every service (a light where it lights, the room's ink where `ServiceTheme.onTint` is asked for a label) and `test/core/theme/monochrome_accent_test.dart` allows the brand colour to be read only where the colour is itself the information (a chart series). Seven of the nineteen brand colours sit within a few degrees of a tone (Radarr, SABnzbd, Plex and Unraid beside the fault amber, Transmission and Readarr beside red, NZBGet beside green), so a healthy service read as a fault. A service is recognised by the shape of its mark and by its name. The accents stay measured apart from the tones (`test/core/theme_test.dart`: *the fault tone is not a service accent*). The section accents and the legacy indigo were retired and their tokens removed, so nothing paints them either.

**Plates** (`plate-*`) stand in for missing artwork and are dark in both themes; artwork is not palette, and a missing poster is not a white hole on paper (*the plate palette is the same in both themes*, `theme_light_contrast_test.dart`).

**The day room** keeps every rule: paper for the floor, white slabs with a hairline and a soft shadow, the title still lighting the room at about a third of the strength but never a slab (a slab's light, `SlabLight`, is the night room's: by day the slab stays white paper), tones darkened until they pass on paper, shadows in ink rather than black.

## Typography

Three families, all OFL and bundled, so the type is the same on all five platforms.

- **Bricolage Grotesque** (`type.family.display`; `opsz` 12–96, `wdth` 75–100, `wght` 200–800): titles, section headings and figures. Voiced, and used sparingly. Its default instance is 96 pt ExtraBold at full width, so **every role sets all three axes**: `wght`, `wdth`, and `opsz` equal to the size (`AppTheme.variations`). Flutter never applies an optical size by itself. The narrow widths (90–96%) are the voice: they fit *Cosmos Laundromat* on one line at 42.
- **Onest** (`type.family.text`, `wght` 100–900): everything read that is not a title or a figure. It has tabular figures.
- **Geist Mono** (`type.family.mono`, `wght` 100–900): machine strings only: release names, paths, hashes, keys, logs, the terminal, exactly as returned, and the legend of a physical key (`⌘K`), with a slashed zero. Figures are never mono: a size, a rate, a percentage, a clock or a count takes `.tabular` in the text face, and `test/core/theme/mono_face_guard_test.dart` fails on a figure in mono and lists every use of the face. Never the bare `monospace` alias, which is proportional on Apple platforms.

Geist Mono and Apple Symbols follow in every fallback list and carry the glyphs the faces lack (⇧ ⏎ ∞ ⌘ ⌥). Other scripts fall back per glyph to the system face: a decision, not a surprise.

| Role `type.role.*` | Face | Size / line | Weight · width | Material slot or helper | Use |
|---|---|---|---|---|---|
| `figure-hero` | Bricolage | 44 / 44 | 600 · 90% | `displayLarge` | One hero readout per room. |
| `media` | Bricolage | 42 / 41 | 600 · 90% | `displayMedium` | A title on its Media page. |
| `screen` | Bricolage | 36 / 36 | 600 · 92% | `displaySmall`, `headlineLarge` | Tab-root titles. |
| `room` | Bricolage | 30 / 31 | 600 · 92% | `headlineMedium` | Pushed screens and service rooms. |
| `feature` | Bricolage | 26 / 27 | 600 · 92% | `headlineSmall` | A featured title, a sheet title. |
| `section` | Bricolage | 21 / 24 | 600 · 96% | `titleLarge`, `subtitle`, `panelHeader` | Section headings, the app-bar title. |
| `figure` · `figure-s` | Bricolage | 24 / 24 · 20 / 20 | 600 · 92% | `AppType.figure`, `figureSmall` | KPI figures; times and figures in rows. |
| `body` | Onest | 15 / 22 | 400 | `bodyLarge`, `bodyMedium` | Paragraphs, input text. |
| `button` · `row` · `label` | Onest | 16 / 20 · 15 / 20 · 14 / 18 | 600 | `titleMedium` · `rowTitle` · `labelLarge` | The primary button; a row that is a name; small buttons, links, chips. |
| `meta` · `caption` | Onest | 13 / 18 · 12 / 16 | 500 | `bodySmall`, `data` · `labelMedium` | Secondary lines and the answer in a row; captions, badges. |
| `micro` | Onest | 11 / 14 | 600 | `labelSmall`, `AppTheme.chrome` | Tab labels, poster marks. **The floor.** |
| `mono` | Geist Mono | 13 / 18 | 450 | `AppType.mono`, `.mono` | Machine strings. |

- **The Weight Ceiling Rule: nothing is heavier than 600.** The display face speaks through width and optical size, not weight. `test/core/theme/weight_ceiling_test.dart` scans `lib/` for heavier weights (its allow-list is empty) and for weights changed through `fontWeight:` instead of `.weight()`.
- **Never a bare `TextStyle(fontSize:)`**, and never `copyWith(fontWeight:)`: neither reaches the `wght` axis, so the text renders the file's default instance. Use a role, then `.weight()`, which moves `wght` and keeps `wdth` and `opsz`. `test/core/theme/type_axes_test.dart` walks every slot of the text theme, asserts each names its axes, and measures that the real faces reach them.
- **The 11 px floor.** Nothing renders smaller than `micro`; `AppTheme.chrome` clamps to it. Where geometry cannot take 11, the geometry grows.
- **The Tabular Rule.** Anything that updates in place or lines up in a column (speeds, times, sizes, percentages, counts) is tabular (`.tabular`; the figure roles already are). Prose keeps proportional figures.
- **The answer is never smaller than its label**: `data` sits above `caption` on purpose.
- Tracking is authored per role in em and is the same in both rooms.
- **A page's name is in the page.** A pushed page and Settings say their name at the top of their own content, in the `room` role, with a line under it when there is a state worth one sentence (Settings: how many services are set up, how many are not, and whether this device is at home; a stack: how it runs) (`PageTitle`). The bar over them holds only the way back and the page's actions, and takes the name small, in the `section` role, once the page has scrolled it under (`GlassAppBar.inPage`). A body that is not a list (an empty state, a failure, a form) sits under the name (`TitledBody`). A service room names itself in its band, and a tab root in the `screen` role.
- **Truncation.** A row title and its status line take one line each, the ellipsis at the end; a title takes two lines at most, broken between words, never mid-word; a single word longer than its line scales down. Release names take one line in a row and wrap after their dots on a detail page. Prose stops at 640.
- **Machine names.** A row about a copy carries its machine name under the title, mono, one line, ellipsis in the middle; a row about a title never does. The ellipsis keeps the front (what the copy is) and the back (the group and the extension, which is always whole), and the name is never cleaned up into a title. On a detail page it is whole, wraps after its dots and has a copy button; the name its card is about leads, in the ink, and anything beside it (what it was released as, its folder, which is a path and so mono too) is secondary, in the tertiary ink, as a name under a row's title is. Everywhere it copies exactly, with the toast *Copied*. `MachineName` draws it ([its card](components/MachineName/README.md)).

## Space and layout

The 390 pt phone is the product. The scale (`space.scale`) is 2 · 4 · 6 · 8 · 10 · 12 · 14 · 16 · 20 · 24 · 28 · 32 · 40 · 56, and a value off it is a defect; the older ladder (`space.xs` … `space.xxxl`) resolves onto it.

- `gutter` 16 is the page gutter and a slab's padding; `slab-y` 14 a slab's vertical padding; `row` 10 a row's vertical padding; `l` 12 the rail, grid and row gaps; `section` 28 the space above a section heading; `top` 56 a screen's top margin under the status bar. The 2, 6, 10 and 14 steps live inside components.
- Media grids are three posters wide on a phone (about 111 at 390, the floor winning over the width), and add a column only while every tile keeps 130 (`MediaGrid.columnsFor`); detail bodies stop at 720, prose at 640, the content well at `breakpoint.content-well` 1140.
- **The tablet opens a title beside the list.** From `touch-split` 1024 a touch window keeps the page a title was opened from in `split-list` 440, the widest phone, and draws the title's page beside it; Back closes it, and a title opened inside it is the pane's own history. The location is the phone's, so a link, Back and a rotation mean the same thing; between 840 and 1024, and on the desktop, the title takes the page. The poster it was opened from wears a ring in ink a hair outside its edge (`ContentCard`), and the title's light comes up from the list's side.
- **The Reduction Rule.** A narrower window shows fewer items at full size, never smaller ones. No token has a compact twin.
- Breakpoints are window regimes, never a device check: `nav-compact` 360 · `desktop-mobile` 720 (a desktop window below it paints the touch shell under a bare drag strip) · `touch-rail` 840 (a touch window at or above it moves the bar to a side rail) · `touch-split` 1024 (a touch window at or above it opens a title beside the page it came from) · `desktop-compact` 1100 · `reading-well` 720 (the widest a page of one column grows, an artist's or an author's, centred in a wider window) · a desktop window no smaller than 360×450. A frame at `landscape-aspect` 1.2 or wider sets two things side by side. Phones are portrait.
- **Targets.** A finger's target is `size.touch` 44 even where the drawing is smaller: a 36 chip sits inside 44; the area grows, the drawing does not (`test/core/widgets/touch_target_test.dart` measures the rendered box). Pointer-only desktop chrome may go to 38–40 and never below (`test/core/theme/desktop_pointer_target_test.dart`). Flutter picks `VisualDensity.compact` by itself on macOS, Windows and Linux, which silently takes 8 off `minimumSize`: every button theme and `HeaderActionRow` pin `VisualDensity.standard`, and a new button style that sets `minimumSize` pins it too.
- Sizes: `button-l` 52 (the primary) · `button-m` 44 · `field` 52 · `search` 48 · `chip` 36 · `tabbar` 62 · icons 20 and 24 · a row thumbnail 36×54.
- **Text grows.** Boxes grow with the reading size instead of clipping (`TextScaleMetrics`, `test/core/text_scale_test.dart`): compact boxes follow it to 1.6×, single-line chrome to 1.3× and then elide. Every screen holds up to a reading size of 200%, the size the catalog renders; past it (iOS goes to 310%) nothing is promised. **Direction:** display roles stop at 1.35×, as large titles do on iOS, and a row whose title passes 22 stacks.
- **Navigation.** The operator's tabs are Home · Discover · Activity · Stack, the requester's Home · Discover · Requests (`NavTab.barFor`). On a phone the bar is as wide as the page, a column per tab, each a glyph over its name, the lit one a pill filling its column ([FloatingBottomNavBar](components/FloatingBottomNavBar/README.md)); Activity's glyph is the pulse line (`vital_signs`). Settings is in neither bar: it opens from Stack's gear, from the requester's account button, from ⌘, and from the foot of the desktop sidebar. On a tablet the bar stands on its side, a floating pill at the leading edge ([FloatingNavRail](components/FloatingNavRail/README.md)); a desktop window has a sidebar of the sections with their keys and, for the operator, every service with a light only where it needs a look ([DesktopNavRail](components/DesktopNavRail/README.md)). The requester's window has no deck, no command deck, no inspector and no service. Discover took the Search tab's place, browsed at rest and searched by typing; Stack is where every service lives (`/stack/{key}`). A service room carries its own tab bar (`tabsFor`), and TrueNAS, with ten sections, has none by design.
- **Home.** The first tab is today: the day as its title (`Thursday 8`), and under it the month and how many services answered, a link to Stack. Then the person's modules, from one registry (`HomeModule`) in the order the person keeps (Edit Home, `/home/edit`, and Settings › Home): each draws in the shared slab and its five states, or steps aside when it has nothing to say, so the Home has no empty boxes. The operator's opens with Needs you, one line for what is wrong and the way in, and ends with Set up next and the Edit Home row; each person's layout is their own. Downloads and Now playing are read again every 30 s while the Home is on screen, Storage every 60 s, and only then. Stack health, Storage and Discover shelf start off: a person adds them in Edit Home. The requester's opens with Ready to watch and Your requests, then Seerr's two shelves, and says one failure above them all. See [HomeModule](components/HomeModule/README.md), [EditHome](components/EditHome/README.md) and [RequesterRequestRow](components/RequesterRequestRow/README.md).

## Shape

The radius scale names the object: `thumb` 8 (a row thumbnail, a checkbox) · `chip` 12 (a tile, a fault chip, a stale band) · `poster` 14 · `control` 14 (the medium button, a segmented track, a stepper, an icon button) · `button` 16 (the large button, a banner, a toast) · `field` 16 · `door` 20 · `group` 22 (grouped rows) · `slab` 26 (a section and a dialog) · `sheet` 30 (sheet tops and the floating bar) · `pill`. Small objects take `hair` 3, `xs` 4 or `sm2` 10. The older ladder (`sm`, `md`, `lg`, `xl`, `full`) resolves onto these.

- **Corners are continuous**: a rounded superellipse (`RoundedSuperellipseBorder`) wherever a shape takes an `OutlinedBorder`. **Today** a `BorderRadius` on a `BoxDecoration` is still circular.
- **A pill is a chip, a tab, a segment or a metadata tag**, drawn at half its height. A button or a card is never a pill.
- A row of choices keeps its corner in both states: selection is carried by fill and ink, never by the corner.
- **Edges are hairlines**: `line.hair` on a slab, `line.edge` on a control at rest. Never two edges on one object.
- Status dots are 8 px circles; the neutral dot is hollow.

## Elevation and depth

The room is lit from the title, not from a lamp above, so it is flat: slabs, groups, rows, buttons, chips, doors and tiles cast nothing in the dark room (`elevation.level-1` is 0 there) and lift softly on paper. **Only two things glow and only what floats casts a shadow.**

- `shadow.poster`: a poster in the colour of its own light, 0 16 30 −12.
- `shadow.hero` (the hero artwork): a wide glow of its light, 0 30 70 −16, over a tight contact shadow.
- `shadow.float` (the bar, menus, toasts): 0 10 30. The floating bar adds a 1 px edge light (`shadow.glass`).
- `shadow.sheet`: a sheet, cast upwards: 0 −12 40.
- `level-2` and `level-3` remain for the older call sites: the poster geometry in the shadow ink, and the float. Each layer's opacity is per theme; the day room's shadows are ink, not black.
- **The No-Blur-Under-Scroll Rule.** Nothing blurs the content behind it: a live blur cost 15–25 ms per scroll frame on a mid-range Android phone. Floating bars are lit enamel (`room.enamel` at 0.95, with a 14% sheen of the room in front at the top: *The title light*) and heroes deepen a gradient scrim (`opacity.hero-scrim-rest` 0.85 → `hero-scrim-deep` 0.35) instead.

## Motion

One ease carries almost everything: `motion.curve.standard` (0.2, 0.8, 0.2, 1), a fast start and a long settle. Durations are named for what moves.

| Role `motion.*` | Duration | Curve | What moves | Reduce Motion |
|---|---|---|---|---|
| `press` | 180 ms | standard | A pressed target dips to `press.scale` 0.96, with a light haptic. | unchanged |
| `standard` | 320 ms | standard | State changes, expand, select. | a 150 ms fade |
| `emphasized` | 420 ms | standard | The pager, the segmented thumb, the chip rail. | a 150 ms fade |
| `enter` | 520 ms | standard | An entrance: rises 12 and fades; siblings 40 ms apart, past six together. | no rise |
| `sheet-in` · `sheet-out` | 380 · 240 ms | (0.05, 0.7, 0.1, 1) · (0.3, 0, 0.8, 0.15) | Sheets and dialogs. | a fade |
| `shared` | 450 ms | standard | The poster flies onto its Media page. | a cross-fade |
| `progress` | 600 ms | standard | A bar moves to a new value. | a jump |
| `text-xfade` · `image-xfade` | 700 · 900 ms | standard · ease | Carousel copy (rising 10) and art. | unchanged, manual |
| `roll` | 900 ms | easeOutCubic | A figure rolls once from `—` to its value. | the final figure |
| `light` | 1500 ms | ease | The room light moves to a new title; the new light enters over the old, since a symmetric fade darkens the room halfway. | a jump |
| `shimmer` | 1600 ms loop | linear | A skeleton sweep. | the flat base |
| `dwell` | 6000 ms | linear | A carousel slide; the pager fills; a pause control stays visible; after a touch the slide holds `dwell.hold` (1200 ms). | no auto-advance |
| `breathe` | 8000 ms | ease-in-out | One slab's light per screen, 0.42 ↔ 0.55. | still |
| `kenburns` | 14000 ms | ease-in-out | Carousel art drifts 1.02 → 1.12. | still |

- **One authored moment per screen**: the flight onto a Media page, the list rising on Home. Everything else changes state without an entrance.
- **Events, not loops.** A glint or a pulse fires once per new sample, so a stuck feed stops moving. Figures roll once from `—` and never count up from 0.
- **Continuous motion stops** off screen, in the background, under the Portal, with a screen reader running and under Reduce Motion. **Direction:** breathe, Ken Burns and the pager fill run on one gated 12 Hz ambient clock. **Today** that clock does not exist: the Home's Featured ([FeaturedPager](components/FeaturedPager/README.md)) runs `dwell`, `kenburns`, the two crossfades and `light` on its own ticker, stopped under those same conditions and under a finger, and nothing uses `breathe` yet; most call sites still read the older ladder (`AppAnimation.durationXs` … `durationXl`), which now resolves onto the roles, and the poster flight rides the pushed route's own transition rather than `shared`.
- `duration.confirmation-hold` 1600 ms: a success check replaces a button's icon for that long, then reverts.
- **The Portal's physics are hand-tuned** (`PortalPhysics`, `lib/features/shell/presentation/service_portal.dart`) and are never normalised to the motion tokens: the values are the design.

## Configurations

Pages read across services (a Media page shows one title through Seerr, Jellyfin, Radarr and Bazarr at once) and every household configures a different subset. Every cross-service row therefore declares its source and what it draws in six cases, before it is built. **The core rule: a missing service costs its own row, never the page.**

| Case | What it is | What the row draws | Its words |
|---|---|---|---|
| **a · Not set up** | Cupola has no address for it and nothing else knows it. | One dimmed, tappable row per surface that opens the service's setup form, or nothing where the row is detail. | `Not set up` · `Set up Seerr` |
| **b · Known through another service** | Not set up in Cupola, but Seerr (or Prowlarr, Bazarr) knows it. | That service's claim, attributed, with one quiet way to set it up, prefilled from it. | `through Seerr` · `Add Sonarr to Cupola · key found` · `address found · paste its key` |
| **c · Did not answer** | Set up, and nothing replied. The only red on any screen. | Who and since when, the last known value under it with its time, `Retry`. | `Did not answer since 20:41` · `Retry` |
| **d · Not allowed** | A read-only key, a non-admin token, or a requester looking. | The write stays, dimmed, with the service's own reason. | `This TrueNAS key can read` · `Nothing changed` · `yours only` |
| **e · More than one** | Several instances of one service: Radarr and Radarr 4K. | Every row, figure and action names its instance. | `Radarr 4K · 2160p Remux` · `Goes to Radarr 4K` |
| **f · Not verified** | Jellyfin or Plex has something with that title, but its ids do not match. | Nothing: no row, no link, no Play. | — |

**The twelve rules.**

1. A missing service costs its own row, never the page.
2. Every cross-service row declares its source and what it draws in a–f before it is built.
3. Check configuration before asking. Case a is decided without a provider call: a screen checks `isServiceConfigured` before it reaches its providers, because a `FutureProvider` that throws retries with backoff for a condition no waiting changes (and one derived from a provider with `retry: noProviderRetry` carries it too). It draws one dimmed, tappable `Set up X` row per surface (44 pt, naming the service, opening its setup form), or nothing where the row is detail.
4. Red means `Did not answer` and nothing else: name who and when, and keep the last known value under it with its time. A refusal, or a failure that did answer, is amber with its remedy.
5. An empty answer and an unasked source never look alike: `Not on Jellyfin` or `No results` only after it answered.
6. A total covers only the sources that answered and names the one missing. A figure whose source did not answer reads `—`, never 0, and never a count taken inside a capped or paged response. An average over fewer than 20 votes is no figure either (`ratingWorthShowing`).
7. An unverified match is no match: no link, no Play, and no claim that the title is missing.
8. With several instances, every row, figure and action names its instance. Home, Activity and Stack count all of them; a service room reads one through the instance lens; no action falls back to the lens or to the first instance silently.
9. What is known through another service is shown as that service's claim, attributed (*Seerr sends it to Sonarr*), with one quiet way to set it up, prefilled. It is never drawn as set up and never hidden, and it never shows episode files, missing counts, queue control, blocklist or search.
10. The requester never sees a service name, a fault or an operator action. When the server does not answer: one line, its time when the app saw it stop answering, `Retry`.
11. A write the credential may not make stays visible, dimmed, with the service's own reason; a refused write says nothing changed. Never hidden, never blamed on reachability. The one exception: an option the viewer may not use at all (4K for a requester who may not ask for it) is left out.
12. One situation, one set of words on every surface: the lexicon above.

A connection reachable only at home says `Only at home` while away and is never asked, so it never reads `Did not answer`; without any address away the app cannot tell away from a server that is down, and reads as case c. capability probes exist only for Unraid, TrueNAS, Nginx Proxy Manager and Plex; and nothing is drawn from another service's knowledge (case b). The households in `test/test_helpers/profiles/` (P1 full household to P7 degraded and away, checked by `test/core/profiles/`) are the fixtures: a cross-service screen test runs the profiles its surface touches.

## Failure states

Did-not-answer and not-set-up are normal daily conditions. Four levels, one vocabulary:

- **Did not answer**: the room keeps its identity, tabs and last-known readout under a `Did not answer since 20:41` line and `Retry`. Last-known data keeps full-strength ink (**The Full Ink Rule**): it is what the service said, not a guess.
- **Section**: one source inside a page did not answer, so only that section falls back, and its figures read `—`.
- **Stale**: the poll stopped returning. Amber, no dismiss, and rows trade time-left for the sample's age.
- **Offline push**: a pushed page whose service died keeps its last render; only live search says so.

**The fault sentence** is three things in this order: *what happened*, a title in the tone of the state (`18 finished downloads need a manual import`); *why*, one plain sentence a person can act on, with the service's raw message under *Why?*; and *the remedy*, a verb within thumb reach (`Review`). Equal faults are grouped: one line with the count and one way in, never eighteen rows.

**The remedy leads.** When the fix lives in the connection's form (`Paste the key again`, `Sign in again`, `Paste the token again`, `Check the address`, `Check the certificate`, `Change the address`, and for a gateway in front of the service `Add a service token`, `Check the token`, `Add access`, `Add the password`, `Check the password`), it is the first action and opens that connection's form, on its Access row for a gateway, with the choice the gateway wants (Cloudflare Access, or Password for a password prompt or a sign-in page). `Retry` follows as text in ink only where the same request can still succeed. With no fix in the form, `Retry` is the remedy.

**The Presence Rule.** A fault is a quiet line: glyph, sentence, remedy. The tone lives on the glyph and the title; no red fill, no red border. An amber fault's remedy is the one amber fill: the form's fix, or `Retry` when retrying is the fix, and on a line it is the compact control. `Retry` beside a red line is a ghost in ink, outlined in a centred state and text on a line, never filled and never red, because a red cure looks like the disease. A download is `Stuck` only after 30 minutes with nothing arriving, by the clock of the client that moves it where that client dates its last byte (qBittorrent, Transmission), over the arr's own `stalled`, which is the client's instant flag read a minute late; where nothing dates the bytes, the service's own word stands. A skeleton takes the shape of its content; there is never a full-page spinner.

**A failure toast** sits on the toast plate like every toast. The failure's glyph leads it in the failure's tone, walked against the plate: red only when nothing answered, amber for every fault and for a toast that carries no cause. The plate is never filled with a tone. A write that failed carries `Retry` where the same request can still go through (`failureRetryHelps`, and not a request the service turned down as made: a 4xx other than 408 or 429); `Retry` sends it again with the same follow-up, even once the page that asked has gone (`runServiceAction`).

**Dimming means a precondition is unmet** (the other service is not set up here, or the saved credential may not make this change), and never that a service did not answer. A dimmed control stays tappable, keeps its 44 pt target, names what it needs in its hint, and answers a tap with a toast whose one verb is the fix. It is dimmed to `opacity.dimmed` 0.5 (**today** `CrossServiceAction` still uses 0.38) and is never announced as disabled.

## Credential scope

A credential can work and still not be allowed to write: an Unraid or TrueNAS key without write scope, a view-only Nginx Proxy Manager account. The app asks once, on connect, what the key may do, and remembers the answer per connection; a refused write teaches it too. Nothing is broken, so nothing is amber:

- **The banner** is one quiet blue line at the top of the page: glyph, sentence, one verb (`Update the key`, `Change account`, or `Check again` when the app could not ask). It is a standing fact, not an event, so it is not announced on every visit.
- **Every write stays on the page**, dimmed but tappable, with the service's own reason (*This TrueNAS key can read. Changing anything here needs a key whose user holds a write role.*); its toast leads to that connection's settings. A write the service refused says `Nothing changed`.
- **Settings** names the scope beside the connection: `Answering · read-only key` (or `view-only account`, or `shared account` for Plex).
- A Plex token of an account the owner shared the server with reads the libraries and is refused who is watching. Now playing and Activity say so in blue, *Only the owner of this Plex server sees what's playing.*, never a refusal and never `Did not answer`; nothing is dimmed, because the sessions it cannot read are never drawn.
- A Jellyfin account that is not an administrator sees only its own playback and says so: *Showing only this account's playback* under Now playing, `yours only` under the Streams figure (the label stays `Streams`, so Home's stack card keeps its words), and `admin only` under a Libraries figure that reads `—`. The tabs it cannot read get a calm note naming what they need, never an error.

## Accessibility

Binding, not best effort. WCAG AA in both rooms, measured against the ground each colour actually lands on. Text grows and never clips. VoiceOver and TalkBack operate everything.

- **A row that is one link speaks one sentence** and silences its parts: *Sprite Fright, out on digital today, downloading, 62 percent.* The state comes before the time; units are words (*percent*, *hours*, *votes*), a percentage always *62 percent* in American spelling, never *62%* in a semantics label and never *per cent* (`spokenPercent` and `spokenPercents` in `lib/core/utils/percent_format.dart`, held by `test/core/utils/spoken_percent_guard_test.dart`); a dash is spoken as *no rating*, never *dash*.
- A remedy inside a row stays its own button. Silence the text, not the row: `Semantics(container: true, excludeSemantics: true)` on the whole row discards the button too.
- A `Semantics(hint:)` wrapped around a button is dropped: annotate the child.
- A dimmed control is never `Semantics(enabled: false)`: it is tappable, and its hint says what it needs.
- Status is spoken, not only coloured. The focus ring and a focused field are `line.focus`.
- A carousel that advances by itself shows its pause control and stops advancing under a screen reader and under Reduce Motion.

## Iconography

Two families, and they never swap roles. No icon is drawn by hand; no emoji, no custom illustration.

- **Interface symbols.** **Today** Flutter's Material Icons, rounded variant, for everything that is not a service, with the outlined variant as the unselected pose of a navigation destination; Activity's pulse line (`vital_signs`), which Material Icons does not have, comes from Material Symbols (outlined at rest, rounded when lit), and the desktop rail draws Material Symbols Rounded (at weight 300). **Direction:** Material Symbols Rounded everywhere (`material_symbols_icons`, already a dependency), setting all four axes: `wght` 400 (500 for back, the active tab, link chevrons and icons inside buttons); `FILL` 1 only for the active tab, a state glyph inside tone text, and play; `GRAD` −25 in the dark room, 0 on paper; and `opticalSize` equal to the size, since the font's default is the 48 px drawing and a 20 px icon without it is thin.
- An icon never replaces the verb of an action. It takes the colour of the text beside it; only a state glyph inside tone text is coloured. One icon per control, before the label; a trailing icon means "goes somewhere" (a chevron, open-in-new). Icons match the text: 16 with 13, 18 with 14, 20 with 15–16, 22 in bars.
- **Service marks** come from the `CupolaServices` font (U+E001–U+E011; SVG sources in `tool/service_glyphs/svg/`, usage in `assets/README.md`). A mark identifies a service and nothing else: monochrome, in ink on a neutral tile wherever a service is listed, one step brighter in the service's own room header. It never carries a status. TrueNAS, Unraid and Plex are deliberately not their logos (trademark policy): a drive rack, a hard disk, a film strip.
- **The brand mark** (the cupola seen from above, six lit panes around a round window) lives in `assets/brand/` and is drawn by `CupolaMark`. It is artwork, the one object that brings its own colour: drawn as it is on either ground, never redrawn or recoloured; the dark body belongs to the app icon, not to the mark. Where it stands and at what size: `assets/README.md`.

## Do and don't

- **Do** read every value from a token, never a widget-local literal for size, spacing, radius, duration, colour or weight.
- **Do** draw the failure state, and each of the six configuration cases, of anything you draw the healthy state of.
- **Do** give a screen one primary action and one authored moment, and give every animation its Reduce Motion answer.
- **Do** keep a widget's catalog card in step with it: re-render the card and update its `README.md` in the same change.
- **Don't** paint a service accent, a section accent or a brand hue anywhere in the interface.
- **Don't** paint the backlog amber, a destructive action red, or `Retry` red; don't use green for "on" or "selected".
- **Don't** set text in a bare `TextStyle(fontSize:)`, re-weight through `copyWith(fontWeight:)`, or go above 600.
- **Don't** show `0` for a source that did not answer, or count inside a capped page and call it a total.
- **Don't** hide a write the credential may not make, or blame a refusal on reachability.
- **Don't** blur behind scrolling content, or give a resting slab a shadow in the dark room.
- **Don't** add a per-OS skin: no Cupertino on iOS, Fluent on Windows or Adwaita on Linux. The OS owns safe areas, gestures, window buttons, window corners and the modifier key; nothing else.
