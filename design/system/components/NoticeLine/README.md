# NoticeLine

The notice a flow ends a step with: a tone, a headline, a sentence and the verbs that remedy it. What signing in to Seerr says when a step stops, and what copying from another device says when nothing arrived.

Rendered from `lib/core/widgets/notice_line.dart` (`NoticeLine`, `noticeAction`) by `test/design_catalog/notice_line_catalog_test.dart`; the sign-in's own words are `lib/features/discover/presentation/seerr_sign_in_notice.dart`, copying's are `lib/features/pairing/presentation/pair_words.dart`, and the Tracearr owner's are `lib/features/tracearr/presentation/tracearr_owner_notice.dart` (`TracearrOwnerFields`).

## Anatomy

- A column, stretched to the width it is given: the notice, then `AppSpacing.xs` below it its verbs in a `Wrap` (`AppSpacing.sm` apart across, `AppSpacing.xs` between lines).
- **The notice** is a row, top-aligned: a 16px glyph, `AppSpacing.sm` gap, then the words.
- **The glyph** follows the tone, so a notice read without colour still says which kind it is: `cloud_off_rounded` for red, `info_outline_rounded` for blue, `error_outline_rounded` for amber (and any other).
- **The headline**: `titleSmall` at 600, in the tone's ink. **The sentence**, when there is one, under it in `bodySmall`, `onSurfaceVariant`. The tone is spent on the glyph and the headline; the sentence stays quiet.
- The ink is `statusToneColor(colorScheme, tone, surface: colorScheme.surface)`: walked against the ground the notice sits on.
- No fill, no border, no padding of its own: the host places it.

## The verbs

`noticeAction(context, label, onPressed, {fill})`, each aligned to the start:

- **Without `fill`**: a `TextButton` in ink (`retryInkStyle`), 44pt, the ghost beside a line that is red or blue. `Retry` beside a red line is this.
- **With `fill`**: the notice's one fill. A fault's (`StatusTone.warning`) is the amber fill under its amber ink (`remedyFillStyle`); any other tone's is the ordinary ink fill, since an amber button beside a blue glyph says something is broken.
- Every verb keeps its 44pt floor at standard density, which the desktop's compact density would otherwise take 8pt off.

## The consumer provides

`tone`, `title`, `sentence` (or none), and `actions`. The words are the caller's, each flow keeps its own in one place; the tone follows the five-arm rule: red is a device or server that did not answer and nothing else, amber is a fault, blue is a step that is the person's own, never a fault. `Retry` is offered only where the same request can still succeed.

## Semantics

The notice is one node, a live region, speaking `Title. Sentence.`; the glyph and the two lines are silenced under it. The verbs are buttons beside it, each with a focus stop of its own.

## States in the catalog

Each sheet is drawn in the dark and the light room: the phone at 390pt, and one scene on a desktop window.

- Red with `Retry` and `Start again`, both in ink; blue with `Start again` in ink; amber with its one fill; a notice with no sentence and no verb.
- On a desktop window: the same notice, its verbs at their 44pt floor under compact density.
- Text at 200%: the longest headline and sentence, wrapped, with both verbs.

## Do / don't

- Do say the cause once, in the headline, and the remedy in the verb.
- Do give an amber fault the one fill, and a red or blue notice ghosts.
- Don't tone the sentence.
- Don't offer `Retry` for a cause the same request cannot get past.
