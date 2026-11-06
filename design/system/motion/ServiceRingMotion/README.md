# ServiceRingMotion

The service dial in motion: each node interpolates between unlit, picked, connected and silent, spokes draw themselves in as services answer, and where the ring is the subject, the whole dial turns once every 96 seconds.

Hand-written from `lib/core/widgets/service_ring.dart`; static anatomy is on the **ServiceRing** card. 268pt diameter, circle radius 268 ÷ 2 − 14 (:496, :503), 18 slots in four domain arcs with 1.7 slots of gap (:448). *Replay* walks a setup (six picked, each configured in turn, one silent); clicking a node steps it through the four states.

- **Transition**: one `AnimationController` of `durationLg` 420ms (:126), `forward(from: 0)` on every change of states, active service or progress, read through `emphasizedCurve` = `Cubic(0.2, 0.8, 0.2, 1)` (:235). Every property of every node lerps from **the frame last painted** to the new target: radius (4 unlit, 5 picked/silent, 6 connected, :325–355), colour (`Color.lerp`, straight RGBA: a lit node is the primary ink, :314), halo alpha (0.34 dark / 0.42 light, radius 3.4 × node, the lamp, :307, :592), collar (1px at radius + 4, ink at 60% when active, :611), spoke (grows outward from 0.34 × radius to 9 short of the node, the lamp in a gradient 5% → 55% / 70%, :561–577), and the progress arc (1.5px, the primary ink at 50%, :551). A change mid-transition therefore bends from where it is instead of restarting.
- **Sweep**: `spin` repeats a second controller over `_spinPeriod` 96s (:122), linear; the angle is added to every node, tick and the arc start. *Sweep ×32* speeds it up so it can be seen; the readout keeps the real rate.
- **Colour**: monochrome: ink nodes, lamp halos and spokes (a service's accent is the lamp, `ServiceKey.accent`), the same for every service; the ring borrows no status tone. The centre is the Cupola brand mark (`assets/brand/cupola_mark.png`), drawn here as a labelled placeholder; the ring paints no service glyphs, so none appear.
- **Spoken**: one sentence, updated per change: *6 of 18 chosen, 4 answering, 1 not answering*.

**Reduce Motion**: the transition is removed, not shortened: `_from = null; _transition.value = 1` (:158–161) paints the new frame at once, and the sweep stops (`_syncSpinner`, :169). The card does both.

Web rendition limits: SVG with one linear and one radial gradient per node, repainted per frame from JS rather than a `CustomPainter`; the transition and sweep use `requestAnimationFrame`. `entrance` is fixed at 1 (the onboarding entrance is not shown).

Do turn `spin` on only where the ring is the whole subject. Don't recolour a silent node; it drains to `on-surface-variant` and keeps its collar.
