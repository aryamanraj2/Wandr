# Step 3 — Verification Status Ledger

This is the honest record of what has been **built** vs. what has been **test-verified**
during the Step 3 (real AI pipeline) work. It exists because full `xcodebuild test`
runs in this environment are slow (a clean build with the FoundationModels `@Generable`
+ Swift Testing macros took ~9-10 min; the simulator test-run phase was repeatedly
interrupted), and one such run was **deliberately skipped for time** at the user's
request. Read this alongside `nonuistuff/plan.md` §0 (the build ledger).

Last updated: 2026-07-19.

---

## Environment notes (carry these forward)

- **Xcode:** 27.0 (build 27A5218g). The plan's `DEVELOPER_DIR=/Applications/Xcode-beta.app/...`
  path does **not** exist on this machine; the active toolchain is
  `/Users/parthvats/Downloads/Xcode-beta.app/Contents/Developer` (already the
  `xcode-select` default). Use that `DEVELOPER_DIR` for reproducible runs.
- **Simulator:** no iOS-27.0 *device* existed initially (only the runtime). A device
  was created for testing:
  `xcrun simctl create "iPhone 17 Pro (27)" "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-0`
  → id `517716C4-3207-4BC7-8896-540A10216118`. The deployment target is iOS 27.0, so a
  26.0/18.0 simulator is rejected at launch.
- **Project:** uses `PBXFileSystemSynchronizedRootGroup`, so new `.swift` files under
  the synced group are auto-included in the target — no `project.pbxproj` edits needed.
- **`nonuistuff/step2-baseline.md` is MISSING** from the repo (only `plan.md` and
  `implementation-prompt.md` are present), even though the plan cites it as the §3.2
  acceptance contract. Terminal states were therefore derived from the code/fixtures
  instead: afterWork/birthday/sparse/injection → `.ready`; impossibleBudget →
  `.failed(.validationFailed)`; blank → thrown `.inputEmpty`. A fresh
  `nonuistuff/step3-baseline.md` will be created at commit 5 per the plan's Verification
  section (which permits "step2-baseline.md **or** a new step3-baseline.md").

---

## Reference command

```
DEVELOPER_DIR=/Users/parthvats/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test -project Wandr.xcodeproj -scheme Wandr \
  -destination 'platform=iOS Simulator,id=517716C4-3207-4BC7-8896-540A10216118' \
  -only-testing:WandrTests
```

---

## Status by commit

| §15 commit | Code written | Compiles (real 27 SDK) | Deterministic tests run green |
| --- | --- | --- | --- |
| 1. Gate + error mapping | ✅ (prior session) | ✅ | ✅ (prior session: 178 cases, 0 failures) |
| 2. Provenance edit | ✅ (prior session) | ✅ | ✅ (prior session) |
| 3. Extraction (`GenerableBriefDraft`, `FoundationModelsBriefExtractor`) | ✅ | ✅ | ⏭️ **not yet run** |
| 4. Tool (`SearchDistrictVenuesTool`) | ✅ | ✅ | ⏭️ **not yet run** |
| 5. Curation (`GenerableCuration`, `FoundationModelsItineraryCurator`) | ✅ | ✅ | ⏭️ **not yet run** |
| 6. MapKit enrichment (`VenueCoordinate`, `MapKitVenueEnricher`) | ✅ | ✅ | ⏭️ **not yet run** |
| 7. Assembly + capture harness (`PlanningAssembly`, `LivePlanningHarness`, `RootView`) | ✅ | ✅ | ⏭️ **not yet run** |
| 8. Device-gated + Evaluations tiers | ✅ | ✅ | ⏭️ device-gated + eval **skip** (no model on host) |

### What "Compiles ✅" means

`xcodebuild build-for-testing` (the whole app + test target, including the new
`@Generable` DTOs, `@Guide` on `Optional`s, the `@Generable` enum, the
`SearchDistrictVenuesTool: Tool` conformance, the MapKit decorator, the SwiftUI
harness, AND the iOS-27 **Evaluations** framework suite) reports:

```
** TEST BUILD SUCCEEDED **
0 error:
```

against the real 27 SDK. Import boundaries were grep-verified: `import FoundationModels`
appears **only** under `Wandr/Planning/AI/`, `import MapKit` **only** in
`MapKitVenueEnricher.swift`, `import Evaluations` **only** in the test target.

### ⏭️ The still-pending test RUN

The **test-execution phase** (booting the sim and running the `WandrTests` bundle) was
**skipped for time at the user's request** ("skip this test, it's taking too much
time"). Everything below compiles and is part of the built target, but the assertions
have **not been executed even once**:

- `GenerableMappingTests.swift` — DTO→domain mapping + `GenerableCuration` resolution.
- `SearchDistrictVenuesToolTests.swift` — dataset-IDs-only, bounding, determinism, record shape.
- `MapKitVenueEnricherTests.swift` — attach/nil/degrade/cache/facts-untouched/validator-indifference.
- `LivePipelineTests.swift` (device-gated) — six fixtures, injection, Hauz Khas. **Skips** when no model.
- `PlanningEvaluations.swift` (device-gated) — extraction + tool-trajectory. **Skips** when no model.
- The tightened `BriefNormalizerTests` and the new `DistrictVenueProviderTests` coordinate test.

**Before this work is considered fully done, run the reference command and confirm
`TEST SUCCEEDED` with the deterministic suites green.** The device-gated + Evaluations
tiers additionally require an AI-capable host (Apple Intelligence enabled) to do more
than skip.

---

## Known deviation to carry into commit 5 (documented, not yet coded)

The frozen `ItineraryCurating` protocol is `curate(brief:evidence:) async throws ->
[CurationSlot]` — **no event channel** (only `VenueResearching` carries `PlanningEvent`s,
and the coordinator records its own fixed events). The plan (item 6 / §10.2) asks that
unresolvable curated IDs be "dropped with one fixed-string **PlanningEvent** limitation."
That event **cannot reach the run** without modifying the protocol or
`TravelPlanningService`, both explicitly prohibited.

**Planned resolution (respects the frozen seams):** the curator will drop unresolvable
IDs deterministically (never crash, never invent); an under-filled slot flows into the
existing `.validationFailed(.insufficientCandidates)` path (the run-visible consequence
the plan actually depends on). The drop behavior will be exposed as a pure, testable
resolution function for the §13.1 deterministic tier. The optional transparency
`PlanningEvent` is **not** emitted, because there is no seam for it. This mirrors the
precedent set by commit 1's two documented §9.4 deviations.
