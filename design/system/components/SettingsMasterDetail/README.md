# SettingsMasterDetail

Settings side by side where there is room: the sections in a list that stays put, the one picked beside it.

Rendered from `lib/features/settings/presentation/widgets/settings_master_detail.dart` (`SettingsMasterDetail`, `SettingsSectionPage`) by `test/design_catalog/settings_master_detail_catalog_test.dart`.

- **When** (`SettingsMasterDetail.showsRail`): a desktop window from `AppBreakpoints.desktopCompact` (1100); a touch build from `AppBreakpoints.touchSplit` (1024: a tablet on its side, where the shell's rail leaves the page about 1080 wide). Below, Settings is the phone's drill-down, a tablet upright included.
- **The list**: 300 wide, a hairline (`outline-variant` at 55%) on its right; the rows of `SettingsMasterDetail.sections` (the requester's own: Overview, Account, Appearance, Home, Region), the one you stand on lit, the longest matching location winning so a page under a section keeps it lit; the app's identity line at its foot (`label-small`, `dim-text`).
- **A section beside the list** (`SettingsSectionPage`, the eight rows of the list in `router.dart`): it takes the place of the section before it where it stands, with no slide (which carried the list away with the page) and no back button (its route implies none): the list is the way between sections, and Overview is its first row. Without the list the same page is the platform's slide with its back button. A page under a section (a connection's form) is a drill-down either way.
- Navigation is `go`, never `push`: the URL is the phone's, every page its own route, a deep link resolves from its path alone.

## States in the catalog

Drawn on the touch build (`phone` sheets), dark and light.

- A tablet on its side, 1180 × 820: the list beside Appearance, no back button.
- A tablet upright, 820 × 1180: the drill-down, Appearance alone with its back button.
- `ServiceSettingsScreen`, the form a section opens: Jellyfin's, tested at an Emby's address (drawn with `act`): `This is Emby`, the cause line and the amber `Set up Emby`. The closest card for the connection form, which has none of its own.
- Text at 200%: on its side.

## Do / don't

- Do add a section to `SettingsMasterDetail.sections` and give its route `_section` in `router.dart`, so it is lit in the list and takes its place without a slide.
- Don't give a section beside the list a back button of its own.
