# ActivitySection

One section of Activity: its name on the page over a slab of rows, what it counts at the end of the name's line, and, when the count leads somewhere, a chevron. `ActivitySlab` is the slab on its own and `ActivitySlabLink` is the line of a slab that leads on (`All 8 requests`).

Rendered from `lib/features/activity/presentation/widgets/activity_section.dart` (`ActivitySection`, `ActivitySlab`, `ActivitySlabLink`) by `test/design_catalog/activity_section_catalog_test.dart`. The rows that sit on the slab are the [`ActivityRows`](../ActivityRows/README.md) card.

## Where it is drawn

Every section of the Activity page: Needs you, Everyone's requests, Watching now, Downloads, Up next and Finished today on All; Downloads and Up next on Downloads; Everyone's requests, whole, on Requests and on Seerr's Requests tab (`RequestsBoard`), under the slab of the requests that wait for you. History draws its days the same way, one section a day. The page decides whether a section is drawn: **a section with nothing to say is not drawn, never an empty slab.**

## Anatomy

- Heading, on the page: `AppSpacing.gutter` on each side, `AppSpacing.section` above, `AppSpacing.md` below. The name in `AppType.section` in the ink; the count after it in `AppType.meta` in `inkSecondary`.
- Count, led somewhere (`onOpen`): the same words in weight 600 and tabular figures, then a 16px chevron, in a target at least 44 tall. Not led: plain `meta`, no target.
- Slab (`ActivitySlab`): the room's slab fill (`slab`), a 1px hairline (`hair`), `AppRadius.borderRadiusSlab`, its rows clipped to the corners, `AppSpacing.lg` inside on each side by default (`slabPadding` for rows that run edge to edge). The slab sits `AppSpacing.gutter` in from the page.
- Lit slab (`ActivitySection(light:)`, `ActivitySlab(light:)`): a section about titles may carry its first title's light inside its slab (`SlabLight`, the picture at 0.5 clipped to the corners, in the dark room only: by day the slab stays white). Downloads does, from the first download with a poster.
- Slab link (`ActivitySlabLink`): a line of at least 44, the label in `AppType.label` in `inkSecondary`, the count after it in `AppType.meta` in `inkTertiary` (one line beside the label, ellipsised before the label is; under it at a large reading size), a 18px chevron at the end, over a hairline when it follows rows (`divided: false` when it is the slab's only line).

At a large reading size (a text scale of 1.3 and over) the count goes under the name instead of beside it, left-aligned: beside it, the name broke inside its words. The same happens at any size when the count, measured as it is set, does not fit beside the name with its gap and chevron (Needs you's `3 faults · 2 violations · 3 requests` on a phone): it goes under the name rather than run past the page. A slab link at that size puts its count under its label, whole and free to wrap, rather than ellipsising it in what the label leaves of the line.

## The consumer provides

`title` and `children` (the rows, already divided: the first is not, the rest are); optionally `meta`, `onOpen` with the `openHint` that says where it leads (`Opens Downloads`), a `semanticLabel` when the name and the count are not the whole sentence, and a `slabPadding`. A slab link takes `label`, `onTap`, optionally `meta` and `divided`.

## Semantics

The heading is one node: a header whose label is the name and the count (`Downloads, 4 moving, 1 stuck`), or the `semanticLabel`; a button with the hint when it leads somewhere. The parts inside are silenced. A slab link is one button labelled `label, meta`, the dots between its counts said as pauses (`All 120 requests, 2 processing, 1 declined`).

The section draws no tone: the rows do, through `statusToneColor`.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- A section with a count and three rows, a section with no count, and one whose count leads on (`onOpen`, with its chevron).
- `ActivitySlabLink` as the last line of a slab, and as the slab's only line with a long count at 320pt.
- A count too long for the name's line (`3 faults · 2 violations · 3 requests`), under the name at the default size.
- Text at 200%: the count under the name, on a section that leads on and on one that does not, with a link line.
- The desktop: a section in the page well.

## Do / don't

- Do let the page drop a section with nothing to say. An empty slab reads as a promise.
- Do put what the section counts in `meta` as one phrase (`4 moving · 1 stuck`), not as a badge.
- Do give `onOpen` an `openHint`: a chevron alone says nothing to a screen reader.
- Don't tone the heading or the slab. Colour is the rows' and comes from `statusToneColor`.
- Don't nest a slab in a slab: a group inside a section is a second section.
