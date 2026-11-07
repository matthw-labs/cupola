# ServiceRecordRow

One record in a service tab's list (a scheduled task, a user, a device, a playlist) that speaks as a single sentence.

Rendered from `lib/core/widgets/service_record_row.dart` by `test/design_catalog/service_record_row_catalog_test.dart`. Used by the Plex, Jellyfin and Emby tab screens and by the Live, History, Users and Violations tabs of Tracearr. A Violations row leads somewhere: so does a Jellyfin or Emby Users row whose person Tracearr knows (see *A door to Tracearr* below). A Violations row it is wrapped in `PressableScale` (hint *opens the violation*) and opens the violation's page. Built on `AppCard.outlined` (transparent fill, 1px `outline`, `AppRadius.md`) with padding `AppSpacing.md` (12).

## Values

- A `Row` centred on the cross axis.
- Leading icon at the theme's default 24pt, in the tone colour (`statusToneColor` against `surface`), then `AppSpacing.md` (12). `ServiceRecordRow.poster` puts a picture there instead (`ServiceOverviewArt`, 36 by 54: the poster with its light, or the initials plate when there is none); the tone still colours the trailing figure.
- Body (`Expanded`): the title in `AppTheme.rowTitle` (15, w600, 20 leading), up to two lines; `AppSpacing.xs` (4); the detail in `bodySmall` in `CupolaThemeColors.dimText`, up to three lines. Both ellipsise. An empty detail leaves its line out, gap included. An optional `footer` (a `Wrap` of `GenreChip`s, the kinds of server a person has an account on) sits under the detail after `AppSpacing.sm` (8).
- `AppSpacing.sm` (8), then the trailing figure in `AppTheme.data` (13, w500, 18 leading) in the tone colour, `TextAlign.end`, up to two lines, ellipsised. It takes its natural width on the trailing edge, capped at `ServiceRecordRow.trailingMaxFraction` (40%) of the row's content width; the `Expanded` body gets everything else. A long figure wraps and then ellipsises within its cap rather than pushing the title out. (It was once `Flexible` beside the body, which handed a short figure half the row and floated it mid-card.)

## Consumer provides

`icon` (or `art`, through `.poster`), `tone`, `title`, `detail`, `trailing`, an optional `footer` and one composed `semanticLabel` that carries the footer's words. All six are required; a figure the source did not report is passed as `—`.

## A door to Tracearr

A Users row of Jellyfin or Emby leads to the person's page in Tracearr when Tracearr is set up and holds an account of that person on this kind of server (`accounts.external_user_id` equal to the user's id on the server; two servers of one kind are told apart by the server's name when both are known; an id that more than one person holds is no door). The row is wrapped in `PressableScale` (hint *opens the person in Tracearr*) and carries a `GenreChip` *In Tracearr* in its footer, which its `semanticLabel` also says. A person Tracearr does not know, and a household without Tracearr, get the plain row.

## Semantics

The row is one container node speaking `semanticLabel`; icon, title, detail and trailing are excluded beneath it. Compose the sentence so it carries what the colour carries ("Extract chapter images, Failed, Started 3 h ago, 4 min, The file could not be read"), and spell out dotted detail lines as a spoken list.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Tasks in each tone: running (blue), failed (amber), completed (green), idle (neutral).
- Users and playlists: administrator (primary), disabled (neutral), smart playlist (blue).
- Poster rows (Tracearr Live and History) and footer rows (Tracearr Users), also at 200%.
- Users with a door to Tracearr: the chip under a person Tracearr holds an account of, the plain row for one it does not.
- Tracearr violations: unseen blue whatever the severity, an acknowledged one neutral, the severity in words at the end (`High`, `Warning`, `Low`).
- Long text: a title on two lines, a detail on three, a trailing figure that yields.
- Text at 200%: the four task rows.
- The desktop: the same row across a wider list.

## Do / don't

- Do follow the five-arm tone rule: a running task is blue (`info`), a failed one amber (`warning`), a completed one green (`success`), an idle one neutral. `primary` marks a role (an administrator), not a state.
- Don't use `error` for anything but an unreachable source.
- Don't put a control inside the row; it is a readout. Content in the catalog is illustrative.
