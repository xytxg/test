# Android HOME hero repair — 2026-11-17 PST

## Scope

Android HOME only, isolated `~/code/Iduanju-home-fix` / `codex/android-home-fix`, based on `eaf4a50`. No iOS, novel, version, workflow or release changes. Release remains held. The supplied box attachment path was unavailable to this executor; the reported defect was independently reproduced on the existing b13 APK with the real public home ranking.

## Actual root cause

`PosterHero` fixed the complete card to 177dp, leaving 149dp minus right-column padding. Compose Column measures non-weighted children in order: kicker, potentially two-line title, metadata, then CTA. The weighted Spacer cannot recover exhausted space. The last `PillButton.height(32.dp)` is a *preferred* height, clamped to the remaining parent constraints; it was compressed to about 20dp for the actual title “穿越八零，我把娘俩宠成宝”. Production MainActivity wraps HOME in Material3 Surface, whose body typography also contributed inherited line-height/font padding to otherwise small text. iOS's font metrics/layout are not interchangeable with these Compose constraints.

## Fix

- Keep the existing spec 10/11 poster/info layout, 112dp 3:4 poster, radius22, colors, font sizes and compact white CTA; no new design.
- Set explicit local hero text line heights and font-padding behavior, measure every real carousel title/metadata at the actual available width/font scale, and allocate one sufficient shared card height. Short/long slides no longer resize the pager or steal CTA space.
- Preserve a >=32dp visual white pill inside an explicit >=48dp clickable target. The full title/metadata precede it with an 8dp gap.
- Put pagination indicators into the same measured footer, not an independent bottom-right overlay. At narrow widths/large font, a second footer line prevents button/dot collision. Narrow windows reduce poster width only as needed to protect a readable info column.
- Audited the remaining HOME search/channels/shelves/continue row and SiteFeedPage sizing paths. No other variable-height hero text+CTA stack sharing the fixed vertical budget was found; no global button/category/novel styling changed.

## Verification and evidence

- `:core:test :app:assembleDebug :app:assembleDebugAndroidTest` succeeded. Core:89 tests,0 failures/errors,20 optional/live tests skipped (this HOME run does not repeat unrelated live rank probes).
- Native `HomeHeroLayoutTest`: 2 tests (light/dark) at 393dp/default font plus 2 at 320dp/font1.3, all pass. Real public Hongguo data, no fixture/network substitution; all five actual carousel pages checked in each configuration (20 page measurements/screenshots).
- Covers actual short and long titles including 持械入宋：第十一季 / 穿越八零，我把娘俩宠成宝 / 全球死考：刚下刑场你让我去考试一季 / 少夫人来自东北3 / 和离后我带女儿横扫魔域.
- Tests use the production Material3 Surface context; assert actual CTA >=48dp, pill >=32dp, CTA text no overflow and contained in the pill, metadata/title ordered without overlap, dots outside CTA and inside the card, and identical carousel height across titles. Logs contain actual native text/CTA/page Rects.
- At default density3, actual CTA is 300×144px (100×48dp), visual pill 300×96px (100×32dp); no clipped label. At 320dp/font1.3 the measured footer adapts without collision.
- Emulator size/font settings restored. Corrected debug APK is installed on emulator-5554. No other emulator was targeted.
- Box evidence: `/workspace/iduanju/compare/home-fix/`; stable original b13 screenshot `before-b13-stable.png`, corrected real-data captures `native/home-{light,dark}-{393dp-f1.0,320dp-f1.3}-page*.png`, current actual activity `after-installed-home.png`, and `bounds-*.log` / `native-*.log`.
- The initial launcher capture and transition-time b13 shot are diagnostic only, NOT before/after proof. Use only the explicitly stable baseline above.
- Spec 10/11 and existing correct iOS home screenshots were inspected side by side; source content and OS text rendering differ. This is not a pixel-perfect/1:1 claim. Existing continue-watching history contains labelled local player-test entries; hero and recommendation shelf data are real public content.
