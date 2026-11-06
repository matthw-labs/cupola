# ServiceGlyphs

One mark per service, from the `CupolaServices` font: the glyph that says *which* service a surface belongs to, never what it does.

Rendered from `lib/core/service_glyphs.dart` (generated), `ServiceKey.icon` in `lib/features/settings/domain/service_key.dart` and `tool/service_glyphs/README.md` by `test/design_catalog/service_glyphs_catalog_test.dart`; the well shown is the service settings header's (`service_settings_screen.dart`).

## Values

- **Font**: family `CupolaServices` (`assets/fonts/CupolaServices.otf`, 18 glyphs, 4.9 KB), built by `tool/service_glyphs/build_font.py` from one filled shape per service in a `0 0 24 24` viewBox (`evenodd` holes resolved at build, since a font winds nonzero). The same script writes `service_glyphs.dart`; neither is edited by hand.
- **Codepoints** (registry order, `ServiceKey.values`): Seerr E001 · Radarr E002 · Sonarr E003 · Lidarr E004 · qBittorrent E005 · Transmission E006 · Bazarr E007 · TrueNAS E008 · Dockge E009 · Prowlarr E00A · Readarr E00B · SABnzbd E00C · NZBGet E00D · Unraid E00E · Nginx Proxy Manager E00F · Jellyfin E010 · Plex E011.
- **Consume**: `Icon(service.icon)`, `ServiceKey.icon` returns `ServiceGlyphs.<name>` (`ServiceGlyphs.radarr`, `ServiceGlyphs.nginxProxyManager` …). The constants are reached through `ServiceKey.icon`, never directly.
- **Well** (shown): 48 × 48, `ServiceTheme.fromAccent(service.accent).softContainer` (the service's accent (the lamp) at `DesignTokens.opacityServiceSoftContainer`, 14%), `AppRadius.borderRadiusMd`, mark at 24, name under it in `textTheme.labelSmall`, `onSurfaceVariant`. The well sits on a `surfaceContainer` card, and the mark is the primary ink (`ServiceTheme.onTint` resolves the lamp to ink): monochrome, the eighteen told apart by shape.
- **Sizes in use**: 12.9 (onboarding small tile) · 14 (`ServiceTabBar.header` well, search results) · 15 (⌘K connection row) · 16 (deck active chip, inspector queue row, manual-import rows) · 18 (service matrix cell, onboarding walk, release-search job) · 20 (manual-import fix sheet, where-to-watch slot) · 24 (settings header, `ListTile` leading default).

## Provenance

Six marks are [Simple Icons](https://simpleicons.org) (CC0 1.0), for Radarr, Sonarr, qBittorrent, Transmission, Nginx Proxy Manager, Jellyfin. Eight are drawn from each project's own logo: Seerr, Lidarr, Readarr, Prowlarr, Bazarr, SABnzbd, NZBGet, Dockge. Three are deliberately **not** logos, because their owners' trademark policies rule it out: TrueNAS (fair use limited to text) is a drive rack, Unraid (no logo in a third-party interface without a licence) is a hard disk, and Plex (written permission needed for its logo in an app; no play symbol either) is a film strip. `plex_official.svg`, the Plex chevron, sits in the source folder for when that permission exists; it is **not** built into the font, and if it ever is it must stay unaltered, never tinted, its `#EBAF00` is reserved for the chevron.

## Semantics

A mark is decoration beside the service's name and is always excluded (`ExcludeSemantics`); the name carries the meaning.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The eighteen marks on the settings header's well, and Radarr's mark at every size in use.
- Text at 200%: the eighteen wells; the marks are icons and keep their size.

## Do / don't

- Do use a mark only to identify the service Cupola connects to; every mark belongs to its owner.
- Don't use one as a category glyph (a download arrow, a play button, that was the old `ServiceKey.icon`, and three download clients read as one picture), as a status, as a button's verb, or in any colour but the room's ink, never its brand colour.
