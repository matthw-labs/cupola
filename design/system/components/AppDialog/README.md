# AppDialog

The one confirmation dialog in the app, in one style: title, a sentence, optional checkboxes, and a Cancel / confirm pair whose confirm names what will happen. A delete looks like every other confirmation. A typed variant gates the few actions that reach past the device.

Rendered from `lib/core/widgets/app_dialog.dart` (`showAppConfirmDialog`, `showAppTypedConfirmDialog`, `AppConfirmOption`, `AppConfirmResult`) by `test/design_catalog/app_dialog_catalog_test.dart`, on Material 3 `AlertDialog`. The catalog opens the real dialog in each scene, barrier included.

## Anatomy

- **Surface**: `dialogTheme` (`surfaceContainerHigh` in dark, `surfaceContainer` (white) in light), with a continuous `AppRadius.slab` (26) corner, a 1px `room.edge` line and no shadow. Material 3 metrics: 24 padding, 16 between title and content, 24 above the actions, actions right-aligned 8 apart. Barrier the room's scrim (`#0A0A0D` at 70% dark, `#16151A` at 40% light); shown on the root navigator unless `useRootNavigator: false`.
- **Title row**: an optional 24pt icon in `onSurface`, then `AppSpacing.md`, then the title in `titleLarge` at 600, whole: it names what the action touches, and a cap at two lines hid that name. The dialog is `scrollable`, so the title scrolls with the content and the buttons stay in view at any length; the title is also the dialog's `semanticLabel`.
- **Message**: `bodyMedium`.
- **Note** (`note`): `AppSpacing.sm` under the message, one line of what another service knows about the thing the action touches, `bodySmall` in `on-surface-variant`: the removal of a movie or a series says `Watched by 3 · last 12 days ago` or `Nobody has watched it` from Tracearr, and nothing when Tracearr did not answer for the title. It informs the choice and is no part of it: no checkbox, no effect on the confirm.
- **Options**: `AppSpacing.md` above, one `CheckboxListTile` each: leading checkbox, zero content padding, the tile's own `bodyLarge` title and a `bodySmall` subtitle in `on-surface-variant`, the secondary ink.
- **Field** (`field: AppConfirmField`): `AppSpacing.md` under the message, one text field with a floating label and no counter, limit held at `maxLength` (200). For a word to whoever the action lands on, optional by nature: the dialog confirms with it empty, and the label says so (`Message for Anna · optional`, Tracearr's Stop). The result carries it trimmed in `text`.
- **Actions**: a `TextButton` Cancel (`cancelLabel`, the theme's `primary` and `labelLarge` 600) and the theme's own `FilledButton` confirm (`confirmLabel`; the ink fill, `primary`, padding 16 × 12, `AppRadius.control` (14)). No style of its own. A label too long to sit beside Cancel makes the pair stack rather than truncate, with the confirm on top and Cancel beneath it, 8 apart (`actionsOverflowDirection: VerticalDirection.up`, Material's stacked order).
- **Typed variant** (`showAppTypedConfirmDialog`): the same title row and message, then `AppSpacing.md`, the phrase on a `surfaceContainerHighest` plate (`AppRadius.borderRadiusSm`, padding 12 × 8, `bodyMedium` 600, selectable), `AppSpacing.md`, a text field labelled *Type it to confirm*, autofocused. The confirm stays disabled until the field matches the phrase, trimmed and case-insensitive.

## Colour

None of its own. **A destructive confirmation is not red**: red in the tone rule means unreachable and nothing else, and a delete, a stop or a reset is an action, not a status. The icon is `onSurface`, every line of text is the dialog's own ink, the confirm is the theme's `primary`. `test/core/widgets/app_dialog_test.dart` walks every text, glyph and fill in the dialog on both themes and fails on any red; `test/core/theme/neutral_destructive_test.dart` fails on any button style or dialog in `lib/` built with the error colour.

It used to have a `destructive` variant (red fill, red title and glyph, a red *This cannot be undone.* banner), on the theory that red on an action meant irreversible. That exception is gone, and so are `destructive`, `dangerNote` and `AppConfirmOption.danger`.

## The weight is carried by words

- **The confirm label is a verb and its object**: *Delete job*, *Take down*, *Remove from Radarr*, *Stop playback*, never *Confirm*, *OK*, *Yes*, or a bare *Delete*. `confirmLabel` is required; the scan above rejects a single word.
- **When an option changes what the action does, the label says so** (`confirmLabelFor`): *Remove from queue* becomes *Remove and delete files* when *Delete from download client* is ticked. `confirmLabel` must be the label for the options' initial values; the helper asserts it.
- **If it cannot be undone, one neutral sentence says so**, in the message (*This cannot be undone.*), or in the subtitle of the option that makes it so. An action that can be undone says nothing of the sort: *Forget certificate*, *Stop playback*.

## Variants

- **Standard** (the grab confirmation from the Interactive search sheet): *Grab release* (or *Grab rejected release*, with the rejections listed) / *Download "…"?* / Cancel, *Download release*. An icon is optional (*Approve this request?* → *Approve request*).
- **A delete with options**: *Remove from queue?* with *Delete from download client* (ticked by default, its subtitle ending *This cannot be undone.*) and *Blocklist this release*; the confirm reads *Remove and delete files*, and *Remove from queue* once the first is unticked.
- **A delete with a note**: *Remove Big Buck Bunny from Radarr?* / *Radarr stops looking for it.* / *Watched by 3 · last 12 days ago* / the two options.
- **A delete with no options**: *Delete snapshot?* / *tank/media@… is destroyed. This cannot be undone.* / *Delete snapshot* (TrueNAS).
- **Typed**: *Shut down nas?*, the hostname to type, *Shut down server* inert until it matches (TrueNAS power; NPM's *Take offline* and *Save and reload* go through the same helper).

## The consumer provides

Title, message, icon, `confirmLabel`, optionally `confirmLabelFor`, `cancelLabel` and the options (`key`, `label`, `subtitle`, `initialValue`). The result is `AppConfirmResult(confirmed, options, text)`, read with `option(key)`; dismissing returns `AppConfirmResult.cancelled`. The typed variant takes `phrase` and returns whether it was confirmed. A haptic, where a flow wants one, is the caller's, fired before the dialog opens.

## Semantics

Material's: a dialog route, checkbox tiles that announce their state, two buttons. The typed variant's disabled confirm carries the hint *Type <phrase> above to enable*, on the button's label. A `Semantics(hint:)` wrapped around a button is dropped.

## States in the catalog

Each sheet is drawn in the dark and the light room; the delete dialog also on the desktop.

- Standard, with an icon, with a field for a word to the viewer (Stop this stream?), Enter confirms with the confirm focused, a delete with its options ticked and unticked, a delete with no options, a delete with a note (Watched by 3, and Nobody has watched it), a long title, the typed confirmation.
- Text at 200%: the grab confirmation, the delete with two options, the typed confirmation.

## Keyboard

Enter runs the confirm, the primary action, only where the call site passes `enterConfirms: true`: an action it can reverse (*Download release*, *Approve request*, *Save changes*, *Import 3 files*). A delete, a stop, a discard, a decline or a sign-out stays off, so a key pressed by habit never removes anything; the typed variant has no Enter at all. The key is taken only while the dialog's own focus holds it, which the dialog takes on open and no ring marks. With a button focused, Enter presses that button (Cancel cancels); on a checkbox it toggles it; in a text field it stays a newline, multiline or not. The keypad's Enter does the same as Enter.

The catalog's *Enter confirms* scene tabs to the confirm, so the ring sits on the primary action.

## Do / don't

- Do phrase the title as the question and put the object in the message.
- Do make the confirm label say the whole of what happens, options included.
- Don't paint any part of a confirmation red, amber or with any other tone. The words carry it.
- Don't write *This cannot be undone.* for something that can be.
- Don't add a third button.
