# Brand assets

The brand mark and the service marks are not copied into the design system: they live where the app
builds them from. What follows is how to use them, and the sample artwork the catalog draws with,
which does live here (`Imagery/`).

## The Cupola mark

The Cupola mark: the cupola seen from above, six lit window panes on a hexagon's edge midpoints around a central round window, with the Earth's limb glowing through them. Full-colour vector art with its own gradients; it does not take a single ink and never inherits colour.

- `cupola_mark.svg`: the mark of record (transparent ground). Use it for splash, About and onboarding, on `surface` or any dark ground. Never recolour, outline, flatten or redraw it.
- `cupola_icon.svg` (the app icon, dark appearance): the mark on its own dark rounded body with a vignette. Store listings, docs, anywhere the mark must sit on a light ground.
- `cupola_launcher.svg`: the icon simplified for small sizes (launcher, favicon, ≤48px). Below 48px use this, never the full mark.

The name is set in the display face (Bricolage Grotesque, a display role at 600) beside the mark, in `on-surface`. There is no separate wordmark file.

The files are `assets/brand/cupola_mark.svg`, `cupola_icon.svg` and `cupola_launcher.svg` in the repository root; they are not duplicated here.

## Service marks

The eighteen service marks (one per service, the glyph `ServiceKey.icon` draws). The same outlines ship as the `CupolaServices` font (`assets/fonts/CupolaServices.otf`, codepoints U+E001–U+E012, `ServiceGlyphs.<name>` in Dart); these SVGs are the sources the font is built from (`tool/service_glyphs/build_font.py`).

- Single ink, one filled shape on a `0 0 24 24` box, drawn in **black** here. In the app a mark is **monochrome**, never the service's colour: in a list or a row it is the secondary ink (`on-surface-variant`); on a tile it is the primary ink on a neutral well (the room's strong fill with an edge in the service's own header, the lamp at 14% on the settings header) and a label asked of a service's accent resolves to the room's ink, because that accent is the lamp (`ServiceKey.accent`). A service is told apart by the mark's shape and its name. Render the font glyph when the mark must take the room's ink; an `<img>` cannot.
- Sources: Simple Icons (CC0 1.0) for Radarr, Sonarr, qBittorrent, Transmission, Nginx Proxy Manager, Jellyfin, Emby; drawn from each project's own logo for Seerr, Lidarr, Readarr, Prowlarr, Bazarr, SABnzbd, NZBGet, Dockge; drawn for Cupola and deliberately **not** the logo for TrueNAS (a drive rack), Unraid (a hard disk) and Plex (a film strip), because their trademark policies rule the logo out.
- Every mark belongs to its owner and only identifies the service Cupola connects to. Never colour a mark with a brand hue, never use one decoratively, never redraw a logo from memory.

The SVG sources live in `tool/service_glyphs/svg/` and the built font in `assets/fonts/CupolaServices.otf`; they are not duplicated here. Rebuild the font with `python3 tool/service_glyphs/build_font.py` after changing a source.

## Sample artwork

Sample artwork for pictures of media surfaces: one poster (`poster.jpg`, 300×450, from TMDB's `w500`) and one backdrop (`backdrop.jpg`, 800×450, from TMDB's `w1280`), taken from Cupola's own image cache and reduced, so the catalog shows artwork the way the app receives it. The title is *Nosferatu* (1922).

- Artwork is content, not a palette to pick from: it sits in `plate-*` wells, under `AppGradients.heroScrim` on a backdrop, cropped with cover fit. The one colour the interface takes from it is the title light, derived by the rules in the brand book (*The title light*), never a hue picked by hand. **Today** nothing is derived and the lamp lights every room.
- A missing image is a real state and stays a plate; these files do not replace the no-artwork renditions.

The design catalog serves them to the real widgets as `CatalogArt.poster` and `CatalogArt.backdrop` (`test/design_catalog/catalog.dart`); the motion cards reference them as `__POSTER__` and `__BACKDROP__`, which the gallery substitutes.

