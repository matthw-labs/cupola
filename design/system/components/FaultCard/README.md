# FaultCard

One fault in Needs you, with its way out on the card: a headline that is a sentence by an amber warning glyph, what it means, which service raised it, the service's own words behind Why?, the proof a download carries, and the remedy. `StuckDownloadCard` builds one for each stuck download, with its four ways out; `StorageAlertCard` one for a TrueNAS alert about a disk, with its pool's evidence and Scrub; `DecisionFaultCard` one for every other kind of fault, with the control the Home's row has. A health check failing on several \*arrs is one card (`foldArrHealth`): the app's words for the check (`arr_health.dart`), the \*arrs named once on the source line, their own messages behind Why?, the first \*arr on the fill and each other one a quieter way out (`Open in Sonarr`).

Rendered from `lib/features/activity/presentation/widgets/fault_card.dart` (`FaultCard`, `FaultCard.whole`, `FaultCard.row`; and `RequestsWaitRow` from `needs_you_cards.dart`) by `test/design_catalog/fault_card_catalog_test.dart`. The words come from `lib/features/activity/domain/stuck_download_fault.dart` and `lib/features/activity/domain/fault_words.dart`, never from the widget.

## Where it is drawn

Needs you on Activity's All, one card per fault inside the section's slab, divided by hairlines; a stuck download that was folded with others on the Home's list is a card of its own here, since each has a way out of its own. The requests that wait sit under the faults on a slab of their own, as rows with Approve and Decline: a request is somebody waiting, not something broken. `FaultCard.whole` is the Needs you page's card. On a tablet (a window from 1024) and on the desktop, All draws `FaultCard.row` instead (`NeedsYouCard.row`): a line a fault, and the requests that wait one line of their own (`RequestsWaitRow`); the whole card is on the Needs you page, where the section's count leads. Above the cards, the import a Review of blocked imports sent reports itself first ([ImportReview](../ImportReview/README.md)); a failed one is a `FaultCard`.

## Anatomy

- Art: the poster at 44×66 (`HomeRowArt.large`), or the service's glyph on a plate, `AppSpacing.md` before the words.
- Headline: `AppType.row` in the ink (`AppType.section` on the page), after a 16px `warning_rounded` glyph in amber (20px on the page), `AppSpacing.xs` between. A sentence: `Big Buck Bunny is stuck at 47%`, `18 downloads need a manual import`.
- Explanation: `AppType.body` in `inkSecondary`, for a download how long nothing has arrived (`Nothing has arrived for 3 hours, and nobody sharing it has the whole file any more.`). Source: `AppType.meta` in `inkTertiary` (`Sonarr`, `TrueNAS · pool tank`); a stuck download has none, its proof already names its route.
- Why?: a 44pt text button in `inkSecondary` with a chevron; open, the service's words in `AppType.meta`.
- Proof, for a download: the release in `AppType.mono` on one line that fades, then the route alone, `Radarr → qBittorrent`, in `AppType.meta` (the explanation already says how long, and a failed download's headline already says it failed), then a 4pt bar in amber on `fillTrack` at how far it got. On the page, `evidence` adds a line per fact (`Pool tank · Healthy · 72%`).
- Remedy: the one amber fill, full width (`remedyFillStyle`), what it does under it in `AppType.meta` (`Radarr drops this one (1.1 GB so far), won't pick it again, and looks for another.`), then the quieter ways out as `OutlinedButton`s two a row, each taking half; a last one alone takes the row.
- Work the remedy started and that still runs (`running`) takes the fill's place, in blue since it is information and not a fault: `Scrubbing tank · 2% · about 9 h left` in `AppType.label`, a 4pt bar under it, the quieter ways out still beside it. The card reads it again every minute while it runs.
- Once a way out was taken, the controls give way to a note in `AppType.label` (`Dropped · Radarr is looking for another download`), with `Undo` where it can be taken back (Keep waiting). The note stays where the card was until Activity is read again.

## The row (`FaultCard.row`)

One line of a wide list: Needs you on a tablet and a desktop.

- The art at 36×54 (the card's art, scaled), `AppSpacing.md`, then the words: the headline in `AppType.row` (two lines at most) after the 16px amber glyph, and under it one line in `AppType.meta` `inkSecondary`, the proof when there is one (`Nothing for 3 h · Radarr → qBittorrent`), else the source (`Sonarr · Cosmos Laundromat`, `TrueNAS · pool tank`). No explanation, no Why?, no release, no bar: they are the card's.
- Beside the words, the remedy at the size of its words (`IntrinsicWidth` over the card's own fill), and the quieter ways out behind a 44pt outlined ⋯ (`Remove`, `Keep waiting`; `Open alert`), whose menu speaks *More ways out, Big Buck Bunny is stuck at 47%*. Narrower than 480, or at a large reading size, the remedy and the ⋯ go under the words, as on a tablet's list beside an open download.
- Work that runs and a way out taken say so under the words, in place of the controls, as on the card.
- **The requests** (`RequestsWaitRow`): the Seerr glyph's plate, `2 requests wait for your approval` in `AppType.row` the ink after a 7pt blue dot, under it what and who of the first two (`Charge · Anna · Metropolis · Luca`, then `· 3 more`), and `Review`, outlined, which opens the Requests view where each has its Approve and Decline.

## Tracearr's violations (`ViolationDecisionRow`)

Needs you also holds the unseen violations of severity high that Tracearr recorded (`lib/features/activity/presentation/widgets/violation_rows.dart`). They are not faults: a rule was broken by a person and nothing stopped working, so they are blue, are never counted among the faults (the Home's line, the badge and the stack's lights read faults only) and are never a notification of Needs you. They sit between the faults and the requests, in the same slab as the requests where there are both.

- A line over them in `AppType.label` in blue after a 7pt blue dot: `3 violations to review`; a floor when the list is longer than the page reads (the source reads one past `kNeedsYouViolationCap`, 5): `5+ violations to review`, spoken *at least 5 violations to review*. The section's count says it too (`3 faults · 2 violations · 3 requests`, a group of its own between the faults and the requests).
- A row each, newest first: Tracearr's glyph on a plate (`HomeRowArt`), the rule in `AppType.row` (600) in the ink, under it the person and when in `AppType.meta` in `inkSecondary` (`Anna · 2 h ago`), a chevron at the end. No remedy and no control: the whole row, at least 44 tall, opens the violation, where the owner acknowledges or dismisses it. No place and no address ever reaches it.
- One node: the rule as the label, the person and when as the value, hint *opens the violation*.

## The consumer provides

`headline`; optionally `explanation`, `source`, `why`, `art`, `release`, `proof`, `progress`, `evidence`, `primary` (the fill, built by the consumer so it can be gated or busy), `primarySubtitle`, `running` (text, progress), `secondary` (label, callback, spoken label), `note` (text, Undo callback) and, inside a slab, `divided`.

## Semantics

The words are one node: headline, explanation, source, release, proof and evidence, as one sentence. The buttons are their own: each names its title (`Try another download, Big Buck Bunny`). The note is a live region, so the outcome is said as it appears.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- A stuck download: proof, fill, what it does, Remove and Keep waiting.
- A group of blocked imports with its cause behind Why? and one way out.
- Two cards after a way out: a note alone, and one with Undo.
- A scrub that runs, in place of the fill, with Open alert beside it.
- A health check failing on four \*arrs: one card, the \*arrs on the source line, the other three two a row.
- `FaultCard.whole`: a storage alert with its evidence and Why? open.
- Tracearr's violations under the faults: three rows, and the floor (`5+`); at 200%.
- Text at 200%.
- The desktop: a stuck download in the page well.
- `FaultCard.row` on a desktop's All (784): three faults and the requests' line; beside an open download on a tablet (440), the remedy under the words; text at 200%.

## Do / don't

- Do lead with the remedy the cause points to: Look for peers again when somebody has the whole file, another download when nobody does.
- Do say what a way out will do before it is taken, and what it did after.
- Do confirm Remove, which deletes what arrived and looks for nothing else. The fill does not ask: what it will do is written under it.
- Don't paint anything but the glyph, the bar and the fill amber: the words are the ink's.
