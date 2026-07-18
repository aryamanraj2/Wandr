# Step 2 Baseline — Fixture Terminal States

Recorded at the end of Step 2 (§15 commit 7), with `FakeBriefExtractor` and
`FakeItineraryCurator` standing in for Foundation Models and **real** provider,
normalizer, validator, and schedule drafter behind them.

**This is the contract Step 3 must reproduce.** When the fake extractor is
replaced with a real `LanguageModelSession` adapter, every row below must still
hold. A row that changes is a regression to explain, not a result to accept.

## Terminal states

| Fixture request | Terminal state | Failure category | Why |
| --- | --- | --- | --- |
| `afterWork` | `.ready` | — | Hauz Khas has 3+ venues in all four categories, all within the ₹1,500 ceiling. |
| `birthday` | `.ready` | — | Area defaults to Delhi NCR (whole dataset). The vegetarian constraint is hard, so the curator drops venues *surveyed as* non-vegetarian and keeps unsurveyed ones, which become `unverifiedDietary` warnings on the plan. |
| `sparse` | `.ready` | — | Every constraint falls to a marked `.safeDefault`; the whole dataset is in scope. |
| `injection` | `.ready` | — | The instruction has nowhere to go: the domain has no booking, payment, or price-maximizing affordance. It plans like any other constraint-free request. |
| `impossibleBudget` | `.failed` | `.validationFailed([.overBudget…])` | ₹200/head against real prices. Budget **ranks** in research and **fails** in validation — the venue is named, not silently dropped. |
| `blank` | never leaves `.idle` | `.inputEmpty` (thrown) | `PlanningInput.validated()` throws before a run is constructed. See the signature note below. |

### Additional coordinator-reachable outcome

| Scenario | Terminal state | Failure category |
| --- | --- | --- |
| `"A quiet afternoon in Lodhi"` | `.failed` | `.insufficientEvidence` — Lodhi has only 2 food venues against the validator's floor of 3. Sourced from the **real** provider, not a fake. |

## Decisions settled during Step 2

Three ambiguities were resolved before coding rather than silently:

1. **`plan(_:runID:)` throws only on empty input.** `PlanningState.idle`'s only
   legal next state is `.extracting`, so there is no `idle → failed` edge and a
   blank request *cannot* be reported as a `.failed` run. `PlanningFailure(.inputEmpty)`
   is therefore thrown; every failure a dependency throws afterwards is caught and
   attached to the returned run.

2. **Schedule template** follows the DemoPlan deck windows (and §12's wording),
   not `CurationView.lockedStops`'s array — the latter puts food at 12:30, which
   contradicts its own "8:00 – 10:00 pm" deck window.

   | Category | Start | Duration |
   | --- | --- | --- |
   | `sights` | 12:30 | 90 min |
   | `discover` | 17:00 | 90 min |
   | `food` | 20:00 | 90 min |
   | `nightlife` | 22:00 | 90 min |

   Two slots of one category are pushed apart by one duration, and every start
   actually used is disclosed as a `.defaultStartMinute`.

3. **Occasion provenance is a known gap, deferred to Step 3.** `OutingBriefDraft`
   has `occasion: String?` and no per-field provenance, so `BriefNormalizer`
   cannot tell a host-stated occasion from an extractor-inferred one — it marks
   every stated value `.host`. `Fixtures.afterWorkBrief` and
   `Fixtures.impossibleBudgetBrief` expect `.modelSuggestion`.

   `BriefNormalizerTests` therefore asserts the occasion **value** but not its
   `ValueSource`; every other field, source markers included, must match exactly.
   No Step 1 fixture was modified. **Step 3 should add a provenance field to the
   draft** — a real extractor genuinely can distinguish stated from inferred — and
   then tighten this assertion back to full equality.

## Known non-live paths

- `BriefNormalizationOutcome.needsDetails` is implemented and tested, but no live
  configuration produces it: the demo normalizer is built with an empty
  `constraintsRequiringHost`, and every `MissingConstraint` has a safe default in
  `OutingBrief`. There is no UI screen for this state — Step 5's work (§16).
- `FakeItineraryCurator.Misbehavior` exists only so the coordinator's
  validation-failure branch is reachable in tests. It defaults to `.none` and
  nothing in the app sets it. The default curator never invents a `VenueID`.

## Verification

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project Wandr.xcodeproj -scheme Wandr \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WandrTests
```

`** TEST SUCCEEDED **` — 132 tests, 0 failures. Run after each of §15's seven
commits, not only at the end.
