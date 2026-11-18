# Detail/player correction verification — 2026-11-17

No release or tag created by this correction batch. Work is based on main after PR13 (2acfe21).

## Player

- Removed the old portrait landscape-video `H - 156` render area. The engine surface now occupies the full viewport regardless of controls/panels.
- A native `PlayerRenderHost` pins the actual engine UIView to its bounds on native layout/rotation. Debug accessibility measures that surface **and its hosted AVPlayer/sample-buffer layer**, not a SwiftUI wrapper.
- Full controls remain overlays. Compact state has only a 12pt single-line title and a 2pt edge progress line. It has no broad scrim and no scrubber/time/knob. Expanded scrims are shorter/less opaque so the image remains visible underneath.
- Centre transport suppression during episode switches remains unchanged.

Native iOS simulator: `CompactChromeUITests` passes expanded → compact → expanded in portrait and landscape. Actual surface AND hosted layer window rects are equal in each state:

| Orientation | Actual engine surface / render layer rect (pt) |
|---|---|
| Portrait | `{{0,0},{402,874}}` |
| Landscape | `{{0,0},{874,402}}` |

Native Android emulator: Debug reads Media3's **videoSurfaceView**, not its Compose wrapper. After playback is ready, compact → expanded → compact has identical global rect, bounds and viewport:

| Orientation | Actual surface (px) | Surface bounds | Viewport |
|---|---|---|---|
| Portrait | `Rect(0,946 - 1180,1609)` | 1180×663 | 1180×2556 |
| Landscape | `Rect(229,0 - 2326,1180)` | 2097×1180 | 2556×1180 |

Colour-bar video is a clearly labelled local fixture, not a real source. This verifies renderer geometry, not source-network reliability. Raw simulator screenshots were inspected side-by-side. The current runtime's landscape `app.screenshot()` produces a rotated/cropped snapshot even though the actual simulator display is correct; final landscape evidence uses **simctl's raw display screenshot**, without rotating or re-compositing video.

## Detail (spec 12 / 13)

- Metric card fixed at 63pt. Real one/two-metric responses occupy one/two columns at the spec's three-column density. Missing metrics are omitted; no fake zero/rating/heat values.
- Light-mode play buttons now use the CSS `.btn.white` meaning (`--text` ground / `--bg` text), not literal white.
- Android grouping corrected from ≤60 ungrouped to ≤30, matching iOS and the spec's 48-episode 1–30 / 31–48 groups.
- Actor without avatar uses the known name initial rather than a movie-placeholder icon.
- Native sparse/full/scrolled screenshots inspected in light/dark on both platforms. Scrolled states use real taps/swipes, including 31–48 group, pinned nav and floating play bar. Fixtures are explicitly labelled; covers are placeholders and data differ from the design, so these are structural comparisons, **not a claim of pixel-identical real-data content**.

## Checks

- iOS relevant unit suites: 27 tests, 0 failures, 1 pre-existing skip.
- iOS native CompactChrome UI test: passed; native sparse/scrolled DetailLayout UI test: passed in both themes.
- Android `:core:test`: 87 tests, 0 failures/errors, 19 skipped (live/conditional). `:app:assembleDebug`: passed.
- CF cookie test now isolates/restores existing huangguo cookies so prior real simulator verification does not contaminate assertions.

Evidence on the box: `/workspace/iduanju/compare/corrections/`.
Key files: `raw-PORTRAIT_{EXPANDED,COMPACT}.png`, `raw-LANDSCAPE_{EXPANDED,COMPACT}.png`, `and-verified-{false,true}-{compact,expanded,compact-again}.png`, `*-player-*-comparison.png`, `detail-compare-{sparse,full,scrolled}-{light,dark}.png`, and native render-bounds logs.
