# ServiceOfflineState

The leaf for a configured service that has never answered in this session: a glyph, a fact, an age, and the recovery.

Rendered from `lib/core/widgets/service_offline_state.dart` by `test/design_catalog/service_offline_state_catalog_test.dart`. The plain leaf is used by TrueNAS, Unraid, SABnzbd, Transmission, NZBGet and Nginx Proxy Manager; `.failure` (below) by the surfaces that hold the error that failed.

## Values

- Centred column, padding `space-xl`. No fill behind the glyph.
- `cloud_off` (`failureIcon` for a host that did not answer) at 32px in that state's tone: red, `statusToneColor` walked against `surface`. The title names the state and the glyph carries its tone; the service's accent is registry data and is not painted.
- `space-lg`, then the title *&lt;Service&gt; did not answer* in `title-medium` at 600.
- `space-sm`, then the body in `body-small`, `on-surface-variant`: *It has not answered for 40 minutes. Anything it holds is missing from this page.* When no silence is recorded the span is dropped, not invented: *Anything it holds is missing from this page.*
- `space-xl`, then the actions: *Retry* with an 18px `refresh` glyph as the ghost button in ink (`OutlinedButton.icon`: `fill-control` with a `line-edge` side, never filled, never red, because it sits beside silence), and optionally, `space-sm` after it, a text button *Settings* in `primary` with a 56 × 44 minimum target.

## `.failure`, the same leaf, told why

`ServiceOfflineState.failure(service:, error:, onRetry:, instanceId:)` classifies the error (`classifyConnectionFailure`) and says what the connection form would say, instead of assuming silence:

- **Glyph** from `describeFailure` (`cloud_off`, `key_off`, `timer_off`, `gpp_bad`, `wrong_location`, `alt_route`, `lock_person`, `report`, `code_off`, `no_encryption`, `wifi_lock`) at 32px, in the tone walked against `surface`: **red only when nothing answered**, **amber for a fault**: the server answered (or the device would not dial), so there is one thing to fix.
- **Title**: `describeFailure`'s headline, which names who: *Radarr did not answer* for silence; *Radarr answered but refused the key*, *Radarr answered with an error*, *Radarr was reached but did not reply in time* for a fault; *Cloudflare Access answered instead of Radarr* when a gateway answered in the service's place (`accessGatewayOf(error)`, passed to `describeFailure`).
- **Address**: the host (`ServiceKey.extractHost`) of the connection that failed: the lens's, or `instanceId`'s when the page reads another (a media server opened on one of its connections), `space-xs` under the title in `AppTheme.chrome` 12 `on-surface-variant`; dropped when the connection names none, and when neither of its addresses answered: the body names both then (*At home · nas.home.arpa:7878*, *Away · radarr.example.net*, one a line).
- **Body**: `failureMessageOf(service, error)`, the sentence the failure itself carries: a web page in the service's place (*A web page answered at radarr.example.com instead of Radarr.*, with the path hint under it when the address has none), a gateway (*Radarr is behind Cloudflare Access. Cupola needs a service token to reach it.*), the failure's own sentence, or the reason's (`connectionFailureMessage`); the same sentence Home's summary and the connection test say; with a recorded silence, *It has not answered for 40 minutes.* leads it. Never the exception.
- **Actions**: the way into the connection form is always there, and defaults to the form of the connection that failed (`ServiceRoutes.settingsForConnection`): the lens's, or `instanceId`'s, because after a failed read the address or the key is the likeliest fix. The silence it reports, and the remedy's form, are that connection's too. When the form holds the fault's remedy (`FailureRemedy`: *Paste the key again*, *Sign in again*, *Check the address*, *Check the certificate*, *Change the address*, and for a gateway *Add a service token*, *Check the token*, *Add access*, *Add the password*, *Check the password*) the remedy is the button in the fault's one amber fill (`remedyFillStyle`), and opens the form through `FailureRemedy.open`, on its Access row for a gateway with the choice it wants (`FailureRemedy.access`: Cloudflare Access, or Password) and *Retry* follows as the text action in ink only where retrying can still help (`failureRetryHelps`); a refused key, an `http://` address or a gateway in front of the service has no Retry. Otherwise *Retry* leads and the text action is *Settings*: Retry in the amber fill for a fault (it is the remedy there), the ghost in ink for silence. A Seerr session that ended (blue) is not a fault: *Sign in again* takes the ink fill instead of the amber one (`remedyFillStyle(fault: false)`), with no Retry. The actions wrap and stay centred on a narrow pane.
- Semantics speak *title. address. body* as one sentence.

Used by the library walls (`MediaBrowseScaffold(service:)`, Readarr's authors among them), the Jellyfin, Plex and Emby Overview when the server is dark (one state for the page, not one per region), the Stream tabs that are one read each, and Activity's streaming feed when its only media server is dark.

## Consumer provides

`serviceName` and `onRetry`; optionally `since` (how long it has not answered, formatted as minutes or hours) and `onOpenSettings`.

`since` is how long the connection has not answered, from the silence the probe recorded (`SilenceClock`: the first probe that did not answer, ended by any answer, in memory only). The client pages hand it to `fromSummary` from `ref.watchSilence`; `.failure` reads it itself, for the lens connection whose host it prints, when none is given. Where no silence was recorded (a cold start has none until a minute of its own has passed) the span is dropped, not invented.

## Semantics

The column speaks one sentence (*SABnzbd did not answer. It has not answered for 40 minutes. …*); glyph, title and body are excluded under it, and the buttons remain separate controls.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- `ServiceOfflineState`: did not answer with and without a known age.
- `.failure`: connection refused (red), neither address answered (red, both addresses in the body), 401, a certificate, a web page in the service's place, Cloudflare Access, a 500 (amber).
- Text at 200%: did not answer, a 401, Cloudflare Access.

## Do / don't

- Do prefer `FaultBand.unreachable` wherever any retained readout exists: last-known data at full ink beats an emptied page. This leaf is for the cold open only.
- Don't dim for this state; dimming means not configured.
- Don't paint the recovery in the error tone.
