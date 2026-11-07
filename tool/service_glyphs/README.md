# Service glyphs

The source of `assets/fonts/CupolaServices.otf` and `lib/core/service_glyphs.dart`,
the mark each service is drawn with (`ServiceKey.icon`).

Rebuild after changing any SVG here:

```sh
pip install fonttools skia-pathops
python3 tool/service_glyphs/build_font.py
```

Every source is one filled shape in a `0 0 24 24` viewBox. Paths may cut holes
with `fill-rule="evenodd"`; the build resolves it, since a font only has nonzero
winding.

## Where each mark comes from

| Source | Services |
|---|---|
| [Simple Icons](https://simpleicons.org) (CC0 1.0) | Radarr, Sonarr, qBittorrent, Transmission, Nginx Proxy Manager, Jellyfin, Emby |
| Drawn from the project's own logo | Seerr, Lidarr, Readarr, Prowlarr, Bazarr, SABnzbd, NZBGet, Dockge, Tracearr |
| Drawn for Cupola, deliberately not the logo | TrueNAS, Unraid, Plex |

The last three follow their owners' trademark policies. TrueNAS limits fair use
of its marks to text, and Unraid does not allow its logo in a third-party
interface without a licence, so both draw the kind of machine instead. Plex's
brand guide asks for written permission to use its logo in an app; until that
exists Plex is a film strip, and never a play symbol, which its guidelines also
rule out.

Tracearr's mark is the shield with a T of the project's logo, as one filled
shape with the T cut out (`evenodd`) and without the radar arcs. The project is
AGPL-3.0 and publishes no trademark guide.

`plex_official.svg` is the Plex chevron (Simple Icons), kept for when that
permission exists. It is not built into the font. If it ever is, it must stay
unaltered, which rules out tinting it: its colour is `#EBAF00`, Plex's Primary
Gold, reserved for the chevron.

Every mark belongs to its owner and is used only to identify the service Cupola
connects to; see the trademark notice in the README.
