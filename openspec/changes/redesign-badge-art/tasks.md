Every wave ends with CI green. All art is hand-written SVG in the subset of
design D3. No app drawing code changes before task 2.4 is ticked by the
owner. Relative size: S / M / L.

## 0. Owner decisions

Each has a default; unanswered ones are built as the default.

- [ ] 0.1 Style: sticker (outlined, cel-shaded; default) or the flatter modern variant (design D1).
- [ ] 0.2 A locked badge shows its family shape in grey (default) or stays a plain grey disc (D5).
- [ ] 0.3 Any badge with its own one-off picture in the first release (default: none).

## 1. Wave 1 - style sample (M)

- [x] 1.1 `ios/BadgeArt/` sources: the 13 frame shapes, the five rarity trims, and 10 motifs (flame, fork and knife, plate, scale, water drop, moon, star, crown, capsule, question mark). *Done 2026-10-01: shapes are hand-written path data in `tools/docs/write-badge-art.mjs`, which writes the committed SVG files (all 13 x 5 frames already, 92 KB). Epic's trim became ribbon tails: the wings read as noise at 44 pt.*
- [x] 1.2 `tools/docs/lint-badge-svg.mjs`: the allowed subset, a 24 x 24 motif view box and 64 x 64 frame view box, total size; wired into `.github/workflows/build.yml`'s localization job (no macOS needed).
- [x] 1.3 `tools/docs/build-badge-gallery.mjs` -> `docs/guide/badges.html`: the sample at 44, 60 and 120 pt, locked and unlocked, light and dark, both style variants side by side. *The modern variant is the same files with the outline removed.*
- [ ] 1.4 Owner looks at the gallery and answers 0.1 to 0.3; record the answers in design.md.

## 2. Wave 2 - the full set and the catalog (L)

- [ ] 2.1 `ios/Gamification/Sources/Gamification/BadgeArtCatalog.swift`: badge id -> (family, motif); family from each badge's existing category; header comment per house style.
- [ ] 2.2 Tests: every badge id from every badge source (core, secrets, bingo, boss, journeys, records, collections, seasonal, sport and body, supplements, training, level tiers) resolves; no unknown family or motif name.
- [ ] 2.3 The remaining frames (13 shapes x 5 rarities) and motifs (about 60); `tools/docs/check-badge-art.mjs` fails when the catalog and the files disagree, in CI.
- [ ] 2.4 The gallery shows all badges with a family filter; **owner approves it** (the gate for wave 3).

## 3. Wave 3 - the app (M)

- [ ] 3.1 Imagesets in `Assets.xcassets` generated from the sources by a script (vector preserved, original rendering); the script is re-runnable and its output is committed.
- [ ] 3.2 One family only (streak) in `BadgeMedallion`: frame + motif, the locked silhouette, the fallback to the disc; the other families still use the disc. Sideload and compare with the gallery at 40, 60 and 120 pt. Record what differed.
- [ ] 3.3 All families; the 11 call sites pass the badge (or its family and motif); the secret question-mark frame; the existing shine kept for epic and legendary.
- [ ] 3.4 Accessibility: labels name the rarity; Differentiate Without Colour and the largest Dynamic Type checked on the Achievements grid.
- [ ] 3.5 `BadgeMedallion.swift`'s header rewritten (the "no image assets" reasoning no longer holds); `docs/guide/` links the gallery.

## 4. Verification

- [ ] 4.1 CI green; `openspec validate redesign-badge-art --strict` passes.
- [ ] 4.2 On device: Achievements grid and detail, the unlock moment, level tiers, sport and body, seasonal, supplements; light and dark; every theme. No empty or misdrawn badge.
- [ ] 4.3 App size before and after noted here (budget: under 400 KB added).
