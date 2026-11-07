# AppBottomSheet

The one sheet chrome in the app: drag handle, optional header with a lit tile, a body that scrolls, on a lifted panel that rises from the bottom edge. Where there is room it is a dialog instead (see *Where there is room*).

Rendered from `lib/core/widgets/app_bottom_sheet.dart` (`AppSheetHandle`, `AppSheetHeader`, `AppBottomSheet`) by `test/design_catalog/app_bottom_sheet_catalog_test.dart`; shown through `lib/core/utils/sheet_utils.dart`. The catalog draws each panel as it stands open, over the modal barrier.

## Anatomy

- **Panel**: the room's raised step, `room.raised` (`#17171D` dark, white light; the widget paints it itself), top corners `radius.sheet` (30), continuous (a rounded superellipse, the theme's sheet shape), `shadow.sheet` cast upwards (`AppElevation.sheet`), clipped: the brand book's sheet. `SheetUtils.showCupolaModalSheet` shows it on the root navigator (above the floating nav bar), scroll-controlled and safe-area aware; the panel pads itself by the keyboard inset and keeps its content inside the bottom safe area. The barrier is the room's scrim, through the theme's `modalBarrierColor` (`#0A0A0D` at 70% dark, `#16151A` at 40% light). A min-content sheet caps at 92% of the screen height. A desktop window under 720 wide or 500 tall still gets the sheet, which Material centres and caps at 640pt.
- **Ink**: the panel paints its own fill above the route's Material, so it carries a transparent `Material` of its own inside the clip. A Material row in a sheet (a `ListTile`, an `InkWell`) draws its tap and its selected tint on that, above the fill; without it they were hidden under the panel, and Flutter 3.47 asserts on it.
- **Handle** (`AppSheetHandle`, `showHandle`, on by default): 36 × 4, `AppRadius.borderRadiusFull`, `onSurfaceVariant` at 35%, `AppSpacing.sm` above and below.
- **Header** (`AppSheetHeader`, only when `title` is non-empty): padding `AppSpacing.lg` at the sides, `AppSpacing.md` below, 0 above, `AppSpacing.md` when the handle is hidden. Optional 40 × 40 tile, `AppRadius.borderRadiusMd`, the accent at 14% (a service's accent is the lamp), a 20pt glyph through `ServiceTheme.onTint` against its tile over `room.raised` (`tintAlpha: 0.14`; the lamp resolves to the primary ink), `AppSpacing.md` to the text. Title `titleLarge` at 600, two lines at most; subtitle `bodySmall` in `onSurfaceVariant`, `AppSpacing.xs` below, two lines at most: it is where a service-supplied media title lands. Then an optional `headerTrailing`, then an optional close `IconButton` (`close_rounded`, the platform close tooltip, `maybePop`). Without an accent the tile takes `primary`.
- **Accent glow** (only with `accent` set): a radial wash behind the top 140pt (the accent, the lamp) at 22% (`opacityServiceGlow`) fading to 0, centred at the top, radius 1.1 (`AppGradients.serviceGlow`).
- **Body**: `bodyPadding`, by default `AppSpacing.lg` / 0 / `AppSpacing.lg` / `AppSpacing.lg`; `.showScrollable` passes zero.

## Where there is room

From 720 wide with a short side of 500 (`AppBreakpoints.sheetsAreDialogs`: a tablet either way up, a folded-out phone, a desktop window; never a phone on its side, which is 430 tall) `SheetUtils.showCupolaModalSheet` opens no sheet: it opens the theme's dialog (the slab's corners `radius.slab`, its `line.edge`, `room.scrim` behind; `insetPadding` `space.xl`), centred, closed by Esc or a click outside (unless `isDismissible` is false). The sheet inside it knows (`SheetInDialog`) and draws no panel, no handle and no drag: the same header, always with its close button since a pointer has no edge to swipe from, the same glow and the same body.

- `AppBottomSheet.show`, a form or a picker: `SheetUtils.formWidth` (520) wide, as tall as the body up to `SheetUtils.heightShare` (85%) of the window, scrolled inside past it.
- `AppBottomSheet.showScrollable`, a long list: `SheetUtils.listWidth` (680) wide and 85% of the window tall, the list on a scroll of its own in place of the drag.
- A caller that builds its own `AppBottomSheet` and shows it through `SheetUtils.showCupolaModalSheet` gets the same; it passes `dialogWidth` and `tall` for a list (Manual import's match sheet does).
- A list of actions is not a dialog: it is a menu under the button that asked (see MediaDetailActions).

## Variants

- `AppBottomSheet.show`: min-content forms and pickers. The body sits in a `SingleChildScrollView`, so the keyboard can never overflow it. Callers: the one-field value pickers (`showMediaValueSheet`, e.g. *Quality profile*, subtitle *Currently HD-1080p*), Sonarr's *Series type*, qBittorrent's *Add torrent* form.
- `AppBottomSheet.showScrollable`: a drag-to-resize list in a `DraggableScrollableSheet` (0.6 initial / 0.4 min / 0.95 max). The builder receives the sheet's `ScrollController`, and every branch of its body must attach it or drag-to-close stops working. See ReleaseRow for the Interactive search sheet.
- Both take `isDismissible` and `enableDrag`.

## The consumer provides

Title, subtitle, icon, accent, trailing, close, and the body. Option rows and form content are the caller's: `MediaValueOptionRow` draws a picker option with an 18pt `check_circle_rounded` / `circle_outlined` and a `bodyLarge` label, 600 and in the primary ink when selected (the accent walked against the surface resolves to ink), 500 otherwise; the Add torrent submit is the caller's `FilledButton` (the theme's ink button, never the client's colour), minimum height 46, its glyph and label in one ink, the on-ink, with the label's `label-large` 600 set as the button's `textStyle`, never on the `Text`, where the theme's text colour overrides the foreground.

## Semantics

The sheet adds no node of its own; the header reads as its text, and the close button carries the platform close tooltip.

## States in the catalog

Each sheet is drawn in the dark and the light room; the picker also on the desktop.

- A picker with icon, accent and subtitle; qBittorrent's Add torrent form; `showScrollable` with its close button; no title and no accent; `showHandle: false`; a long title and subtitle; Play with (`PlayWithSheet`, the body of the sheet `playWith` opens) for an Emby title (Emby, Emby in the browser) and, for contrast, a Jellyfin one (its apps and Jellyfin in the browser).
- Text at 200%: the picker, and the long title and subtitle with the close button.
- Desktop: the sheet in a window under 720; where there is room, the picker, the Add torrent form and the long list as dialogs, and the picker as a dialog at 200%.

## Do / don't

- Do pass a service's sheet its accent: the lamp, which lights the header and the tile without a hue; the title and subtitle say whose sheet it is.
- Do resolve any ink against the sheet's own ground.
- Don't build a second sheet chrome.
- Don't leave a `.showScrollable` branch unattached to its controller.
