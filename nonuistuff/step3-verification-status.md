# Step 3 — Verification Status Ledger

> **UPDATE 2026-07-19 (later session): the pending test RUN was executed.**
> Deterministic tier: **215 passed, 0 failed, `** TEST SUCCEEDED **`.** One real
> defect was found and fixed in the process (a test-expression bug in
> `MapKitVenueEnricherTests`, see "Executed run" below). The device-gated tier was
> also found to be **genuinely runnable on this host** — Apple Intelligence is
> available, so `LivePipelineTests` does real inference rather than skipping.
> Environment section below is corrected for this machine.



This is the honest record of what has been **built** vs. what has been **test-verified**
during the Step 3 (real AI pipeline) work. It exists because full `xcodebuild test`
runs in this environment are slow (a clean build with the FoundationModels `@Generable`
+ Swift Testing macros took ~9-10 min; the simulator test-run phase was repeatedly
interrupted), and one such run was **deliberately skipped for time** at the user's
request. Read this alongside `nonuistuff/plan.md` §0 (the build ledger).

Last updated: 2026-07-19.

---

## Environment notes (carry these forward)

- **Xcode:** 27.0 (build 27A5218g).
  ⚠️ **The toolchain path is machine-specific — the two dev machines differ.**
  - On the machine where this ledger was first written: `/Users/parthvats/Downloads/Xcode-beta.app/Contents/Developer`.
  - On **this** machine (`aryamanjaiswal`): `/Applications/Xcode-beta.app/Contents/Developer`.
    `xcode-select -p` here points at `/Library/Developer/CommandLineTools`, so bare
    `xcodebuild` fails with "requires Xcode" — `DEVELOPER_DIR` **must** be set
    explicitly on every invocation, including `xcrun` calls in the same shell.
- **Simulator:** on this machine an `iPhone 17` device on the iOS 27.0 runtime already
  exists and is what the runs below used — no `simctl create` needed. Available iOS 27
  runtimes here: `27.0 (24A5370g)` and `27.0 (24A5380i)`. The deployment target is
  iOS 27.0, so a 26.x simulator is rejected at launch.
- **Apple Intelligence IS available on this host**, which the original ledger assumed
  it would not be. Consequence: `LivePipelineTests` and `PlanningEvaluations` do **not**
  silently skip here — they run real on-device inference in the simulator, which is
  slow (see "Runtime cost" below).
- **Project:** uses `PBXFileSystemSynchronizedRootGroup`, so new `.swift` files under
  the synced group are auto-included in the target — no `project.pbxproj` edits needed.
- **`nonuistuff/step2-baseline.md` is present** (uploaded mid-session). The terminal
  states were independently derived from the code first and then **confirmed to match
  step2-baseline.md exactly**, including the `impossibleBudget → .validationFailed([.overBudget…])`
  category and the additional `"A quiet afternoon in Lodhi" → .insufficientEvidence`
  outcome (both now asserted in `LivePipelineTests`). A companion
  `nonuistuff/step3-baseline.md` records the Step 3 live contract per the plan's
  Verification section.

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
| 1. Gate + error mapping | ✅ (prior session) | ✅ | ✅ **executed** |
| 2. Provenance edit | ✅ (prior session) | ✅ | ✅ **executed** |
| 3. Extraction (`GenerableBriefDraft`, `FoundationModelsBriefExtractor`) | ✅ | ✅ | ✅ **executed** |
| 4. Tool (`SearchDistrictVenuesTool`) | ✅ | ✅ | ✅ **executed** |
| 5. Curation (`GenerableCuration`, `FoundationModelsItineraryCurator`) | ✅ | ✅ | ✅ **executed** |
| 6. MapKit enrichment (`VenueCoordinate`, `MapKitVenueEnricher`) | ✅ | ✅ | ✅ **executed** (1 defect found + fixed) |
| 7. Assembly + capture harness (`PlanningAssembly`, `LivePlanningHarness`, `RootView`) | ✅ | ✅ | ✅ **executed** |
| 8. Device-gated + Evaluations tiers | ✅ | ✅ | see "Device-gated tier" below — **runs for real here** |

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

### ✅ The executed run (2026-07-19, later session)

The test-execution phase that had been skipped was run. **Deterministic tier result:
`** TEST SUCCEEDED **` — 215 passed, 0 failed.**

Command used (device-gated + Evaluations suites excluded so the deterministic tier
returns in minutes rather than hours — see "Runtime cost"):

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test -project Wandr.xcodeproj -scheme Wandr \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WandrTests \
  -skip-testing:WandrTests/PlanningEvaluationTests \
  -skip-testing:WandrTests/LivePipelineTests
```

#### Defect found and fixed: `MapKitVenueEnricherTests/oneLimitationOnFailure()`

The first execution failed exactly one test. It reproduced deterministically, including
with `-parallel-testing-enabled NO`, so it was not flakiness.

The failing assertion was written inline as:

```swift
#expect(!(limitations.first?.detail ?? "").contains("food-1"))
```

Swift Testing reported `Expectation failed: … → <not evaluated>`. Instrumenting the
test proved **the enricher was behaving correctly**: exactly one limitation event, the
fixed title, and detail `"Some places on this plan don't have a confirmed map
location."` — which plainly contains no `"food-1"`. The expectation should have passed.
The prefix `!` applied across the parenthesized `??` expression is not evaluated as
intended inside the macro expansion, so the assertion failed on a true condition.

**This was a bug in the test, not in `MapKitVenueEnricher`.** The implementation
already satisfied §11's contract. Fix: bind the subject to a local first, and assert
the stronger property directly.

```swift
let detail = limitations.first?.detail ?? ""
#expect(detail == MapKitVenueEnricher.limitationDetail)
#expect(detail.contains("food-1") == false)
```

**Carry-forward lesson:** avoid `#expect(!(expr).method(…))`. Bind to a local, or write
`#expect(x.method(…) == false)`. The macro's expression-capture makes the inline prefix-
`!`-over-parenthesized-expression form unreliable, and it fails *silently in the wrong
direction* — it reports a passing condition as a failure, which costs real debugging time.

### ✅ Import boundaries re-verified (§17 checklist item)

Re-grepped on 2026-07-19 after all eight commits landed:

- `import FoundationModels` — app target: **only** `Planning/AI/` (`ModelAvailabilityGate`,
  `ModelErrorMapping`, `GenerableBriefDraft`, `GenerableCuration`,
  `FoundationModelsBriefExtractor`, `FoundationModelsItineraryCurator`,
  `SearchDistrictVenuesTool`). Test target: `ModelErrorMappingTests`, `LivePipelineTests`,
  `PlanningEvaluations` — expected, they assert against the framework's own types.
- `import MapKit` — **only** `Planning/Data/MapKitVenueEnricher.swift`.
- `import Evaluations` — **only** `WandrTests/Planning/Evaluations/PlanningEvaluations.swift`.
- `PlanningAssembly.swift` imports **neither** FoundationModels nor MapKit, so §12's
  "Foundation-only signature, FM reachable via its `AI/` dependencies" holds.

### 🔴 Baseline regression found by the live tier — birthday fixture — and fixed

Running `LivePipelineTests` for real caught a genuine defect that **no deterministic
test could have caught**, because it only appears when a real model makes a real choice.

**Symptom.** `readyFixturesReachReady()` failed. With the assertion made diagnosable
(see below), the culprit was named:

```
birthday expected .ready (step2-baseline) but got failed, category:
  .validationFailed([.unmetDietaryRequirement(slotID: discover,
                     venueID: hk-disc-1, missing: [vegetarian])])
```

**Root cause.** `FakeItineraryCurator` has an `isEligible` filter that drops venues the
dataset *surveyed* as non-compliant with a hard constraint, while keeping unsurveyed
ones (which become validator warnings). `FoundationModelsItineraryCurator` had **no
such filter** — it only *instructed* the model to "respect the brief's dietary…
constraints". The model picked `hk-disc-1`, surveyed as non-vegetarian, and
`FeasibilityValidator` correctly rejected the whole plan. A `.ready` baseline row
became `.failed`.

So the two curators silently disagreed about what a hard constraint excludes. That
means `TravelPlanningServiceTests` (which runs on the fake) had stopped predicting
live behaviour — the drift that let this through.

**Fix — enforcement by construction, not by instruction.** The curator now filters the
evidence with the same asymmetric rule the fake uses and hands only that filtered set
to `SearchDistrictVenuesTool`, so a contradicted venue is **unreachable** by the model
rather than merely discouraged. Model output is also resolved against the *filtered*
set, so a hallucinated ID naming a contradicted venue can't sneak back in.

**What this is NOT.** It does not touch `FeasibilityValidator` or relax a single rule —
§5.6 stands. It is the §5.4 tool boundary doing its job. The validator still re-checks
everything and remains the safety case.

**The asymmetry is load-bearing and must not be "tightened":** surveyed-and-contradicted
is excluded; **never-surveyed is kept**, because those are what become
`unverifiedDietary` warnings — which is exactly what `step2-baseline.md`'s birthday row
describes ("the curator drops venues *surveyed as* non-vegetarian and keeps unsurveyed
ones"). Dropping unknowns too would hide the gap and thin the deck.

**Regression pinned in the fast tier.** `WandrTests/Planning/CuratorEligibilityTests.swift`
(8 tests) now covers the rule deterministically — dietary/accessibility/setting
asymmetry, soft preferences excluding nothing, unconstrained briefs keeping everything,
and a parity check that everything `FakeItineraryCurator.curate` emits is eligible under
the real curator's filter. A future divergence now fails in **seconds**, not only under
a slow live run.

**Test diagnosability improvement.** `readyFixturesReachReady()` looped four fixtures
through a bare `#expect(run.state == .ready)`, so a failure said only "one of four
broke". It now labels each fixture and reports the failure category. This stays inside
Step 1's volatility rule: the label is a fixed test-authored string and
`PlanningFailure.Category` is a domain enum — neither can carry `PlanningInput.text`.

### Device-gated tier — it does NOT skip on this host

The original ledger assumed the device-gated tier would skip for lack of a model. On
this machine it does not: **Apple Intelligence is available**, confirmed by sampling the
hung test process and finding live `FoundationModels` stack frames. `LivePipelineTests`
and `PlanningEvaluations` therefore execute real on-device inference.

#### ✅ First real end-to-end proof: `hauzKhasResolvesAndValidates()` — **PASSED in 34s**

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test-without-building -project Wandr.xcodeproj -scheme Wandr \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'WandrTests/LivePipelineTests/hauzKhasResolvesAndValidates()' \
  -parallel-testing-enabled NO
```

Verified via `xcresulttool` that **1 test case actually executed** (not a vacuous pass).
This is the §13.2 demo-critical assertion: the Hauz Khas request's curated slots all
resolve against evidence and the plan validates — meaning real `LanguageModelSession`
extraction, real tool-calling curation, real ID resolution, and deterministic validation
all work together against the bundled dataset.

⚠️ **`-only-testing` filter syntax gotcha:** a Swift Testing function needs the
**parentheses** — `-only-testing:'WandrTests/Suite/testName()'`. Without them the filter
matches nothing, **zero tests run, and xcodebuild still reports `TEST EXECUTE SUCCEEDED`**.
That is a silently-green false pass. Always confirm the executed-case count in the
`.xcresult` before trusting a narrow run.

**A single full pipeline run costs ~34s here**, which means the whole `LivePipelineTests`
suite (~9 fixture runs) is minutes, not hours. The hours-long component is the
**Evaluations** suite specifically.

**Runtime cost — the reason the first full run looked "stuck":** a full
`-only-testing:WandrTests` run appears to hang after ~116 tests. It is not hung. Every
deterministic suite completes, then `PlanningEvaluationTests` starts and runs many full
inferences in the simulator, each far slower than on real hardware. Budget accordingly,
or split the tiers as above. `LivePipelineTests/blankThrows()` is the one live test that
passes instantly — it throws `.inputEmpty` before extraction, so it never touches a model.

### ⏭️ Superseded: the previously-pending test RUN

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
