# TrueNasStorage

The Storage section of the TrueNAS console: one row per pool, its state and how full it is, each leading to the pool's own page.

Rendered from `lib/features/truenas/presentation/storage/truenas_storage_screen.dart`, over the shell's `lib/core/widgets/floating_bottom_nav_bar.dart`, by `test/design_catalog/true_nas_storage_catalog_test.dart`. The state word comes from `TrueNasPool.stateWord` (`lib/features/truenas/domain/models/pool.dart`), the same word Home's Storage says.

## Values

- Each pool is an `AppCard.surfaceOutlined` row: the status glyph (16pt), the pool name in `titleSmall` at 600, the state word in `labelSmall` in the secondary ink, and a chevron.
- The state word is the lexicon's (`words.md`): `Healthy` for ZFS's `ONLINE` with nothing counted, `Has errors`, `Degraded`, `Faulted`, `Not in service`, `State unknown`. Never the server's uppercase word, never `Online`.
- Tone: a sound pool's glyph is the green check, quiet, its word in secondary ink; any other state is the amber fault, glyph and usage bar alike. Red never appears: the NAS answered.
- Usage: a 6pt bar in the secondary ink, amber from 90% or on a pool that is not sound, then `72% used · 31.2 TB / 43.6 TB` in the data role.

## Semantics

Each row is one tappable card that opens the pool's page; the name and the state word are read in order.

## States in the catalog

Drawn in the dark and the light room, on a phone.

- Storage: `tank` sound (`Healthy`) and `backup` degraded (`Degraded`), over the shell's floating bar.
