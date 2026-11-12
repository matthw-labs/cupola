# SettingsSignature

Cupola's signature at the foot of Settings on a phone: the mark, the claim, and which Cupola this is. The one place the
claim stands once the app is set up, and the phone's only readout of the version.

Rendered from `lib/features/settings/presentation/widgets/settings_signature.dart` by `test/design_catalog/settings_signature_catalog_test.dart`.

## Anatomy

- `AppSpacing.xxl` above it, after the last group (Danger zone for the operator, `Set up a service` for the
  requester), centred.
- `CupolaMark.sized(40)`, drawn as it is on either ground.
- `AppSpacing.md` below, the claim, `OnePunchline.claim` (*A Cupola over your server.*), in `textTheme.titleLarge` (the
  display face, at a section heading's size, as the Welcome sets it at a screen's) and `onSurface`, centred; it wraps
  rather than shrinks at a large reading size.
- `AppSpacing.xs` below, `kAppIdentityLine` (*Cupola 1.1.0-beta · Apache-2.0*: `kAppRelease`, the beta suffix included) in `textTheme.labelSmall` and `dimText`.
- `AppSpacing.md` under it, then the list's own clearance for the floating bar.

## The consumer provides

Nothing. Both phone indexes of `SettingsHomeScreen` end with it, the operator's and the requester's. The wide window
does not draw it: its rail ends with `kAppIdentityLine` alone, where a mark and a sentence would crowd the index.

## Semantics

One sentence, its parts silenced: *A Cupola over your server. Cupola 1.1.0-beta, Apache-2.0.* (`SettingsSignature.spoken`).
The mark is decorative.

## States in the catalog

- The operator's foot, after Danger zone.
- At 200%, the claim on two lines.
- The operator's About group it closes, in the plural voice of the people who make Cupola ("Email us", "Buy us a coffee").

## Don't

- Spell the claim or the version here: it quotes `OnePunchline.claim` and `kAppIdentityLine`, and
  `test/core/identity/signature_guard_test.dart` holds the claim to one place.
- Make it tappable, or add a third line: it signs, it does not offer.
