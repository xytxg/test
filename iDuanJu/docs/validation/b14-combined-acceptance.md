# b14 combined acceptance — 2026-11-18 Asia/Shanghai

Integrated HOME3d0a6c4 + novel efa8498/f991dbd/d45d237/0f882b4 on eaf4a50, without editing production iOS reader visuals. The iOS reader diff is solely cancelPrefetch on disappear; typed exploration/filter state and loader changes are intentional functionality.

## Local compilation and bounded tests

- iOS full unsigned **device Release** build succeeded (1.5 build14), not only simulator/debug type checking.
- Android `:app:assembleRelease :app:assembleDebug :app:assembleDebugAndroidTest :core:test` succeeded (1.5.14/versionCode1514). Local Release uses local debug fallback signing for compilation only; distributable APK must use CI distribution signing verification.
- iOS combined:49 unit tests,0 failures,1 existing optional collection skip;3 native UI tests passed (real source ranking/detail/TOC/reader, sparse detail, portrait+landscape actual render layer).
- Android combined core:100 tests,0 failures/errors,21 optional/live skips. Five native tests passed:1 separate live unmodified source flow,1 actual-book offline reader/settings/TOC/gestures/resume,1 recorded-public-response source-filter UI,2 real HOME themes/all five slides.
- Real flow used the already-cached exact user collection SHA256 `874efe33cbe38b7dcf830704b5bd0614b9485fe1974a20d9c09030ebec07df30`; no re-download or fixture substitution for live flow. 七猫→爽文→无敌天命/青鸾峰上→1694章→fresh3815-character chapter→offline next/previous passed. Recorded filter fixtures keep provenance and are distinguished from live requests.
- HOME tested the actual long title 穿越八零，我把娘俩宠成宝 and other current titles in both themes. CTA48dp hit target /32dp visual pill, label inside pill, metadata/dots disjoint. Earlier standalone320dp/font1.3 proof also remains in HOME report; this combined run did not repeat the complete size matrix.
- Initial Android native run stopped because the primary emulator disappeared. Restored only iduanju_ui/5554, preserved app data, declined crash reporting through documented disabled mode and used software renderer/2GB. Worker emulator5556 untouched. A second real-flow wait exposed *test-state leakage*: previously persisted expanded source filters hid default 爽文 from the visible category composition. The test now uses isolated source storage and restores production storage afterwards; it does not clear or weaken production filter persistence. Final fresh live flow and separate filter state tests both passed.

## Actual rendering geometry

- iOS engine surface AND hosted render layer: portrait402×874, landscape874×402, exactly equal expanded/compact/expanded.
- Android actual Media3 SurfaceView: portraitRect(0,946–1180,1609),1180×663; landscapeRect(229,0–2326,1180),2097×1180. Compact→expanded→compact identical in each orientation. Outer window dimensions are not substituted for these measurements.
- Native simctl screenshots were captured during the single combined iOS test; misleading XCTest landscape capture is not used. Player color bars are explicitly labelled local viewport test media, not a real stream claim.

## Visual inspection and evidence

Reviewed real current Android detail/reader/menu/settings/TOC against worker’s actual current iOS references; HOME against known-good iOS/spec10/11. No new major core visual mismatch found. Native font glyphs, line wrapping/page numbers differ. Some combined reader shots preserve the prior actual reading offset near the chapter end (blank remainder is a last-page state), rather than pretending every screenshot is first-page content. Existing continue-watching history includes labelled local video test entries; HOME hero/shelves are real data.

Box `/workspace/iduanju/compare/b14/`: combined-native-core.jpg, combined-native-player.jpg, shots/, ios-release-build.log, android-build-test.log, ios-combined-acceptance.log, android-real-flow.log, android-core-native.log, android-home-bounds.log, android-render-check.log. Full archive `/workspace/iduanju/compare/b14-evidence.tgz`. Worker native proof remains `/workspace/iduanju/compare/parity/final-proof-20261118/` and HOME before/after `/workspace/iduanju/compare/home-fix/`.

## Explicit limits

Core acceptance is passed, NOT a claim of complete feature/pixel parity. Advanced Android TTS/background speech, all optional remote-font install/delete lifecycle, and full source-switch interaction through unavailable/challenged sources remain not fully verified. Legacy `readerParityComplete=false` is retained in the live probe, not replaced with a blanket true. Synchronous HTTP cannot be physically interrupted immediately; stale responses are discarded before cache. Earlier listing probes63/105 iOS,68/105 Android are not rerun/all-source success claims. Cloudflare hard-block passage is not guaranteed. See b14 release notes for the same limits.
