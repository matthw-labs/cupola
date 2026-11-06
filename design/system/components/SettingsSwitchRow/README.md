# SettingsSwitchRow

A setting that is on or off, inside a settings group: its glyph in a well, what it is, what it does, and the switch.
The rows of Hints, Background search (the master switch and *Tell me when one finishes*) and Notifications.

Rendered from `lib/core/widgets/settings_switch_row.dart` by `test/design_catalog/settings_switch_row_catalog_test.dart`.

## Anatomy

- A row inside a `SettingsGroupCard`, `AppSpacing.lg` across and `AppSpacing.sm` down.
- **The well**: 36×36, the primary at 14%, radius 8, its glyph at 18 in the primary. Then `AppSpacing.lg`.
- **The words**, taking what is left: the title in `textTheme.titleSmall`, the description under it in
  `textTheme.bodySmall` and `onSurfaceVariant`. A **note** may follow, 2 above, in the same face: quiet in
  `onSurfaceVariant`, or in its tone, walked against `surfaceContainer` (`statusToneColor`): a permission blocked is
  amber, something to switch back on and not something that failed.
- **The switch**, the theme's own. While something outside the app answers for it (the OS asking for a permission), a
  20pt spinner, stroke 2, stands in its place.

## The consumer provides

`icon`, `title`, `description`, `value`, `onChanged`, and optionally `note` (`text`, `tone`) and `busy`. The words are
the screen's own; the row says nothing of its own.

`onChanged` null draws the switch where it stands and lets it not move: the setting depends on another one, and the
description says which (*Needs Background search, a search that ends with the app has nothing to announce*).

## Semantics

One node: the title, the description, the note and the switch's state, said as one sentence, and a double tap flips
it. The glyph is silenced. A row is one stop for a screen reader, not three.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- On and off, in a group: Notifications' three rows (*Needs you*, *Ready to watch*, *Flagged by Tracearr*, the last only
  for an owner with a Tracearr set up).
- With a note: a permission blocked, in amber, and granted, quiet.
- Held by another setting, and busy while the OS asks.
- At 200%.

## Do / don't

- Do put it in a `SettingsGroupCard`, whose hairline starts past the well.
- Do ask the OS before the value changes when the setting needs a permission, and keep `busy` while it asks: a switch
  that turns on and back off reads as broken.
- Don't use it for a choice of more than two (`SettingsChoiceRow`), or for a figure (the steppers of Background search).
- Don't colour the title or the switch: the tone is the note's alone.
