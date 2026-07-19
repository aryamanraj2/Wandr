# Wandr Planning Core — Step 3: The Real AI Pipeline

## 0. Implementation status — DONE so far

> **SUPERSEDED IN PART — read this box first.**
> This section was written when only commits 1–2 existed. **All eight §15 commits are
> now written and compiling**, and the deterministic test tier has been **executed**:
> `** TEST SUCCEEDED **`, **215 passed, 0 failed**. One real defect was found and fixed
> during that run (a bad assertion expression in `MapKitVenueEnricherTests` — the
> enricher itself was correct). The "⛔ NOT DONE — commits 3–8" table further down is
> **obsolete**; see `nonuistuff/step3-verification-status.md` for the current,
> authoritative per-commit ledger and for the device-gated tier's status.
> The commit-1 and commit-2 detail below remains accurate.

This section is the honest ledger: what actually landed, what did not, and where the
next session picks up. **§15's build sequence is the numbering used throughout.**

### ✅ DONE — commit 1: Gate + error mapping

| File | Status |
| --- | --- |
| `Wandr/Planning/AI/ModelAvailabilityGate.swift` | **new, landed** |
| `Wandr/Planning/AI/ModelErrorMapping.swift` | **new, landed** |
| `WandrTests/Planning/ModelErrorMappingTests.swift` | **new, landed** (2 suites) |

- `ModelAvailabilityGate` is the only reader of `SystemLanguageModel.default.availability`.
  Split into `check(_ model:)` (production) and `check(availability:)` +
  `failureCategory(for:)` (pure, so the deterministic tier covers every branch with
  no model on the host). All three §9.4 reason rows map as specified, `@unknown
  default` included.
- `ModelErrorMapping.category(for:)` is the single funnel. Covers `LanguageModelError`
  (all 9 cases), `SystemLanguageModel.Error.assetsUnavailable`,
  `LanguageModelSession.Error` (both cases — `.transcriptMutationWhileResponding` is
  new in 27 and is handled), `LanguageModelSession.ToolCallError` (unwraps to
  `underlyingError`), and `GeneratedContent.ParsingError` (a **struct** in 27, matched
  with `is`, not a pattern). Verified to compile against the real 27 SDK.
- **Two deviations from §9.4, both deliberate:**
  1. `PlanningFailure` **passes through untouched** as the first branch. §9.4 didn't
     name this row, but without it the gate's precise "turn on Apple Intelligence"
     would be re-mapped into a generic decoding failure. Asserted in tests.
  2. The `assertionFailure` for "anything else" fires **only** on `@unknown default`
     (a genuinely new framework case) and on schema/capability errors — *not* on every
     foreign `Error`. A blanket assertion would make the fallback row untestable and
     would trip on our own DTO-mapping errors, which are an expected runtime path.
- **Not asserted, and why:** the `LanguageModelError` rows. Those cases carry framework
  payload structs with no public initializer, so a test cannot construct one. The
  exhaustive `switch` is the available compile-time coverage; the device-gated tier
  (§13.2, not yet written) is what exercises them live.

### ✅ DONE — commit 2: The provenance edit (permitted edit 1)

| File | Status |
| --- | --- |
| `Wandr/Planning/Domain/OutingBrief.swift` | **edited** — additive only |
| `Wandr/Planning/Services/BriefNormalizer.swift` | **edited** — honors the marker |
| `Wandr/Planning/AI/FakeBriefExtractor.swift` | **data only** — two drafts annotated |
| `WandrTests/Planning/BriefNormalizerTests.swift` | **tightened to full equality** + 6 new tests |

- Shape chosen (§9.3 left the final call to the implementer): the enum is exactly as
  recommended — `DraftProvenance { stated, inferred }` — but the five per-field markers
  are grouped into a `DraftFieldProvenance` struct carried as one
  `provenance: DraftFieldProvenance = .allStated` field, rather than five separate
  init parameters. Keeps the initializer readable, stays `Equatable`, framework-free,
  and default-preserving.
- `BriefNormalizer` maps `stated → .host`, `inferred → .modelSuggestion`,
  absent → `.safeDefault`. **Ordering rule made explicit and tested:** a blank or
  absent value is `.safeDefault` *regardless* of its marker — a stray `.inferred`
  must never relabel Wandr's own fallback as a model suggestion. Clamping still
  applies to inferred values and does not change their marker.
- `FakeBriefExtractor.afterWorkDraft` and `.impossibleBudgetDraft` gained
  `provenance: DraftFieldProvenance(occasion: .inferred)` — the sanctioned test-double
  *data* change. **No Step 1 fixture was modified.**
- `BriefNormalizerTests.expectMatches` now asserts `actual.occasion == expected.occasion`
  (marker included), satisfying §3.9. Six new tests cover stated/inferred/absent,
  blank-with-marker, clamping-under-inferred, and an explicit
  "a draft built without provenance behaves exactly as before Step 3" additivity check.

### Verification at the point of hand-off

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project Wandr.xcodeproj -scheme Wandr \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WandrTests
```

`** TEST SUCCEEDED **` — **178 test cases, 0 failures.** All Step 1/2 suites green
unmodified apart from the declared `BriefNormalizerTests` tightening. (Step 2's doc
records 132; the delta is the new suites plus parameterized cases expanding
individually — the counting method differs, no Step 2 test was removed.)

One pre-existing warning survives, untouched and unrelated:
`fakeExtractorRecognizesFixtures` uses `try await` inside `#expect`, which warns under
the Swift 6 language mode.

### ⛔ ~~NOT DONE — commits 3–8~~ — OBSOLETE, all eight now landed

> **This table is out of date and kept only for history.** Commits 3–8 were
> subsequently written: `GenerableBriefDraft`, `FoundationModelsBriefExtractor`,
> `SearchDistrictVenuesTool`, `GenerableCuration`, `FoundationModelsItineraryCurator`,
> `MapKitVenueEnricher` (+ `VenueCoordinate` on `GroundedVenue`), `PlanningAssembly`,
> `LivePlanningHarness`, and the `LivePipelineTests` / `PlanningEvaluations` tiers.
> `LanguageModelSession` **is** now constructed (only under `Planning/AI/`), and the
> live pipeline is wired. Current status lives in
> `nonuistuff/step3-verification-status.md`.

~~Nothing below was started. No `LanguageModelSession` is constructed anywhere in the
tree yet, and **`TravelPlanningService` is still wired to both fakes** — the app's
runtime behavior is exactly the Step 2 baseline.~~

| §15 commit | Status | Notes for the next session |
| --- | --- | --- |
| 3. Extraction | **not started** | `GenerableBriefDraft` must carry the same `DraftFieldProvenance` markers commit 2 added — that plumbing is now ready and waiting. |
| 4. Tool | **not started** | `Tool.call(arguments:)` returns `Output` directly in 27; there is no `ToolOutput` type. Return `String` for the compact records. |
| 5. Curation | **not started** | Blocking item: §15's rule that commit 5's live baseline is written down before any later step begins still stands. |
| 6. MapKit enrichment | **not started** | Still the declared cut line. |
| 7. Assembly + capture harness | **not started** | `PlanCaptureView.commit()` (line ~268) is the single call site to wire; `onCommit: (String) -> Void` already hands out the finished text. |
| 8. Evaluations starter | **not started** | — |

Consequently these §3 success criteria are **unmet**: 1, 2, 4 (partially — the mapping
exists and is tested, but no adapter funnels through it yet), 5, 6, 7, 8, 11, and 12.
Criteria **3 and 9 are met**; criterion 10 is met for the deterministic tier only.

### Not yet done from §17's checklist

- [ ] Token-count the two instruction constants (`tokenCount(for:)`) — no constants exist yet.
- [ ] Exercise the three Simulated Foundation Models Availability overrides against the
      gate and record outcomes. **The gate is ready for this now**; it is a scheme-editor
      task, not a code task, and is the cheapest next verification available.
- [ ] Verify one curation exchange in the Foundation Models Instrument.
- [ ] Confirm no file outside `Planning/AI/` imports FoundationModels. Currently true —
      only the two new files import it — but re-grep before the final commit.

---

## 1. Purpose

Step 2 finished the deterministic skeleton: `TravelPlanningService` drives a `PlanningRun` end to end with a real provider, normalizer, validator, and schedule drafter — and two deliberately fake stages, `FakeBriefExtractor` and `FakeItineraryCurator`, holding the seats reserved for Foundation Models. The terminal-state baseline for the six fixture requests is written down in `nonuistuff/step2-baseline.md`; 132 tests pass.

This document defines **Step 3**: replacing both fakes with real, on-device Foundation Models adapters, so the pipeline that runs when a planning payload reaches the app is actually AI — extraction by `LanguageModelSession`, curation by `LanguageModelSession` with tool calling against the bundled Delhi dataset, and MapKit supplying real coordinates for the vicinity story. This is "the whole AI pipeline" in one step — the original build order's Steps 3 and 4 merged, because nothing between them is independently demoable.

Step 3 delivers:

1. `ModelAvailabilityGate` — one place that reads `SystemLanguageModel.default.availability` and maps every `.unavailable` reason to an existing `PlanningFailure` category. No session is ever constructed past a failed gate.
2. `FoundationModelsBriefExtractor` — the real `BriefExtracting`: a short-lived, tool-free Intake session performing constrained `@Generable` extraction of the volatile request text into an `OutingBriefDraft`.
3. `SearchDistrictVenuesTool` — the bundled dataset exposed as a Foundation Models `Tool` (per `Docs/plan.md` §A3), returning bounded, compact, dataset-owned results. This is the *only* tool any model session receives in this step.
4. `FoundationModelsItineraryCurator` — the real `ItineraryCurating`: a research/curation session that must call the tool before ranking, and may only ever emit `VenueID`s drawn from the evidence snapshot. The validator still re-checks everything it says.
5. **MapKit vicinity enrichment** — real coordinates for dataset venues via `MKLocalSearch`, attached to `GroundedVenue` as optional evidence with its own source marker. Failure-tolerant, never blocking, never a model tool in this step.
6. The **draft provenance fix** the Step 2 baseline explicitly deferred to Step 3: `OutingBriefDraft` gains per-field stated-vs-inferred markers so `BriefNormalizer` can finally emit `.modelSuggestion`, and `BriefNormalizerTests` tightens back to full equality.
7. A **live capture harness** — until the Siri doorway exists, the first screen's existing text/voice input (`PlanCaptureView` + `PlanDictation`) is the end-to-end entry point: its submitted text becomes a `PlanningInput(.directCapture)` fed into the live pipeline, so the whole thing is testable on device by typing or dictating a request. Minimal wiring, not the UI bridge (§12.1).
8. Tests in three tiers — deterministic (no model), device-gated behavioral (real model, real device/AI-capable host), and an Evaluations-framework starter suite (`Docs/plan.md` §9's "sleeper bonus").

At the end of Step 3, a labeled-text planning payload — the exact shape the future Siri/Shortcut intent will deliver — runs through a fully real pipeline: model extraction → normalization → dataset research + MapKit coordinates → model curation → deterministic validation → schedule draft. The two fakes stop being the app's brain and become what they always claimed to be: test doubles.

This is still a hackathon-sized plan. The target is a demoable, honest AI pipeline, not a production inference service.

## 2. Authority and scope

Unchanged rule: **`Docs/plan.md` is the architecture authority whenever a document disagrees with this one.** Three conflicts are settled by it up front:

- **Intake payload format: labeled text, not JSON.** The working notes for this step said "the app will receive JSON." `Docs/plan.md` D1 and §6.1a are explicit and deliberate that the intake payload is a labeled-text `AttributedString` through `PlanOutingFromSiriSummaryIntent` — the Shortcut's `Use Model` step is pinned to **Text output specifically to avoid** a JSON/Dictionary contract, so that Wandr's own `@Generable` extraction remains the single authoritative typed parse. `Docs/plan.md` wins: Step 3's extractor consumes plain labeled text via the existing `PlanningInput.text`, and no JSON schema crosses the intake boundary, ever. (This is also why the extractor needs no new input type: a labeled block like `Area: Hauz Khas / Budget: ₹1500` is just easier text, and the model re-parses it exactly as it would free prose — `Docs/plan.md` §6.1a's "re-parses regardless of channel" rule.)
- **The Siri intent itself is not this step.** `PlanOutingFromSiriSummaryIntent`, `AppShortcutsProvider`, and the distributable Shortcut are `Docs/plan.md` Milestone B ("Siri/Shortcut handoff hardening"), and B's own preflight items require physical-device rehearsal that has nothing to do with the pipeline's correctness. Step 3 builds the pipeline that runs *once the payload has arrived*; the doorway arrives in a later step. Consequence: `PlanningInputSource`'s reserved `siriSummary`/`shortcutSummary` cases stay commented out, and Step 3's "Siri-shaped" fixture arrives through `.directCapture` like every other test input.
- **Two short-lived sessions, not one `DynamicProfile`.** `Docs/plan.md` §4.1/§6.2 describes one `WandrDynamicProfile` switching instructions/tools per phase. Step 3 makes a hackathon cut, called out here the way Step 2 called out its cuts: the Intake and Research/Curation phases are two separate, short-lived `LanguageModelSession`s, one per adapter, each dying with its call. The phase-isolation *guarantees* the Docs care about (intake sees volatile text and no tools; curation sees the brief and evidence but never the raw text; no phase gets an action tool) are enforced structurally by the Step 1 protocol seams — the curator's method signature literally cannot receive `PlanningInput.text`. A later step can consolidate onto `DynamicProfile` behind the same two protocols without touching the coordinator. What is *not* cut: everything each profile is forbidden from doing.

Two Step-1/2 file edits are permitted in this step, both additive, declared here exactly as Step 2 declared its `offer`/`offerWindow` edit:

1. **`OutingBriefDraft` gains per-field provenance** (`Domain/OutingBrief.swift`). The Step 2 baseline (decision 3) explicitly deferred this: the draft cannot distinguish a host-stated occasion from a model-inferred one, so `BriefNormalizer` marks everything `.host` and two fixtures' `.modelSuggestion` expectations are asserted loosely. Step 3 adds the minimal marker (see §9.3), updates `BriefNormalizer` to honor it, and tightens `BriefNormalizerTests` back to full equality. This is a *mandated* fix, not an opportunistic one.
2. **`GroundedVenue` gains an optional coordinate** (`Domain/GroundedVenue.swift`): `coordinate: VenueCoordinate?`, defaulting to `nil`, where `VenueCoordinate` is a tiny framework-free lat/long pair in `Domain/`. `Domain/` stays Foundation-only — `CLLocationCoordinate2D` does not appear there; the MapKit enricher converts at its own boundary. Existing call sites don't break; `FeasibilityValidatorTests` must pass unmodified after the edit.

Everything else stays closed: no Siri/Shortcuts/App Intents, no Messages extension or poll, no WeatherKit, no SwiftData, no PCC (`PrivateCloudComputeLanguageModel` is a stretch goal in `Docs/plan.md`, not Milestone A), no Live Activity, no server, no external LLM, no booking/payment/calendar action, no UI redesign, and no replacement of `DemoPlan` — the UI *bridge* (rendering live results in the curation and schedule screens) is still a later step, which also covers the "show it in the current UI, schedule it later" half of the ask. One carve-out against Step 2's "UI untouched" rule, made deliberately: because the Siri doorway is deferred, **the capture screen's submit path is Step 3's live entry point** (§12.1) — `PlanCaptureView`'s existing text/voice output is allowed to *start* a live run, with the smallest diff that achieves it. Its visual design, `CurationView`, `ScheduleView`, and `DemoPlan` remain untouched. The bright line that separated Step 2 from Step 3 — `LanguageModelSession` — is now crossed, but only inside `Wandr/Planning/AI/`. **`import FoundationModels` is legal in `Planning/AI/` and nowhere else**; `import MapKit` is legal in `Planning/Data/` (the enricher) and nowhere else. `Domain/`, `Services/`, and the coordinator remain framework-free, which is the whole reason the fakes were built behind protocols in the first place.

## 3. Definition of success for step 3

Step 3 is complete when all of the following are true:

1. `TravelPlanningService` is constructed with `FoundationModelsBriefExtractor` and `FoundationModelsItineraryCurator` and **zero coordinator changes** — the swap is a different argument at the construction site, exactly as Step 2 §8 promised. Any change to `TravelPlanningService.swift` in this step is a defect in Step 2's seams and must be justified in writing before it lands.
2. On an AI-capable device with Apple Intelligence enabled, the six sanitized fixture requests reproduce the **Step 2 baseline terminal states** (`step2-baseline.md`): afterWork/birthday/sparse/injection → `.ready`, impossibleBudget → `.failed(.validationFailed)`, blank → thrown `.inputEmpty`. A changed row is a regression to explain, not a result to accept. (The *contents* of `.ready` plans may legitimately differ from the fakes' output — the baseline pins terminal states and failure categories, not venue picks.)
3. Every `SystemLanguageModel.Availability.UnavailableReason` maps to the `PlanningFailure` category that was reserved for it in Step 1 — `.deviceNotEligible → .deviceIneligible`, `.appleIntelligenceNotEnabled → .intelligenceDisabled`, `.modelNotReady → .modelAssetsNotReady` — and each lands the run in `.failed` with the correct `PlanningRetryAction`, verified with the Xcode scheme's Simulated Foundation Models Availability override.
4. Every model error the pipeline can hit maps through one function to an existing `PlanningFailure` category (§9.4's table) — no new generic error path, no raw `error.localizedDescription` shown to a host, and no model error escaping the adapters as anything but `PlanningFailure`.
5. The injection fixture, run through the **real** extractor, still produces a draft with no executable content — the instruction has no field to occupy — and no `PlanningEvent`, failure payload, or log line contains `PlanningInput.text`. Step 1's volatility rule survives contact with a real model.
6. `FoundationModelsItineraryCurator` can only propose venues the evidence snapshot contains. Structurally this is guaranteed twice: the `@Generable` curation schema emits venue IDs as strings that are resolved against the snapshot (unresolvable IDs are dropped before slots are built, recorded as a limitation event), and `FeasibilityValidator` Rule 1 still rejects any invented ID that slips through. A model that under-fills a slot produces the same `.validationFailed(.insufficientCandidates…)` path Step 2 already proved reachable.
7. The curator's session receives the brief and the tool — **not** an inline dump of the evidence array. Venue facts enter the transcript only as bounded tool results (§10.3), keeping the whole exchange comfortably inside the on-device context window (read `SystemLanguageModel().contextSize`; 8K on this OS — never hard-code it).
8. MapKit enrichment attaches real coordinates to at least the demo-critical venues (Hauz Khas set) when the network and geocoding cooperate, and degrades to `coordinate == nil` plus a single recorded limitation event when they don't. No MapKit failure may change a run's terminal state. MapKit makes **no** claim the dataset didn't make — no hours, no availability, no ratings; coordinates and displayable map presence only.
9. The draft-provenance gap is closed: a real extraction marks stated fields as stated and inferred fields as inferred, `BriefNormalizer` maps those to `.host`/`.modelSuggestion` respectively, and `BriefNormalizerTests`' loosened occasion assertion is restored to full equality against the Step 1 fixtures.
10. All Step 1/2 tests still pass unmodified (except the two declared edits' direct test updates), the deterministic tier runs green on any Mac, and the device-gated tier runs green on the demo device. An Evaluations-framework starter suite exists with the three golden + two adversarial fixtures `Docs/plan.md` §9 names — it may be thin, but it must run and assert something real.
11. **End-to-end from the first screen:** typing or dictating a request in `PlanCaptureView` on the demo device starts a real run through `PlanningAssembly`'s live pipeline, and the run's terminal state (and failure message, when it fails) is observable — at minimum through the capture screen's existing status affordances or a debug surface. `CurationView`/`ScheduleView` still render `DemoPlan`; rendering the *live plan* is the bridge step's job.
12. `CurationView`, `ScheduleView`, `DemoPlan`, and the fakes' files are untouched; `PlanCaptureView` is touched only on its submit path (§12.1), not its design. The fakes stay in the tree — they are now what `TravelPlanningServiceTests` runs on CI-without-a-model, which is exactly the role Step 2 built them for.

## 4. Architecture in one sentence

Two short-lived `LanguageModelSession`s — a tool-free Intake session that turns volatile labeled text into a typed `OutingBriefDraft`, and a single-tool curation session that ranks dataset venue IDs it looked up through `SearchDistrictVenuesTool` — slot in behind the existing `BriefExtracting`/`ItineraryCurating` protocols, while the deterministic validator, normalizer, provider (now MapKit-enriched), drafter, and coordinator continue not to know or care that the model is real.

## 5. Non-negotiable boundaries

Step 1/2 boundaries all still stand. The new ones:

### 5.1 Availability boundary

No `LanguageModelSession` is constructed anywhere without passing `ModelAvailabilityGate` first, **at call time** — availability changes when the user toggles Settings mid-session, so a cached check from app launch is a stale check. The gate is checked inside each adapter's entry method, throwing the mapped `PlanningFailure` before any session exists. The coordinator neither knows nor checks — unavailability is just another `PlanningFailure` landing a run in `.failed` with `.openSettings`/`.waitAndRetry`/`.none` retry actions the UI already understands.

### 5.2 Intake session boundary

The Intake session: sees `PlanningInput.text` (the one legitimate reader, same as the fake); has **no tools**; has instructions that are fixed, versioned string constants — **never** interpolating the request text into instructions (the text goes in the prompt position only, which is the injection-resistance posture the framework is trained for); produces only the `@Generable` draft DTO; and dies when the call returns. Nothing from the session — transcript, partial output, error payload — outlives the call or reaches a `PlanningEvent`.

### 5.3 Curation session boundary

The curation session: sees the normalized `OutingBrief` (never `PlanningInput.text` — the protocol signature already makes this impossible); has exactly one tool, `SearchDistrictVenuesTool`; is instructed that venue facts come only from tool results and that its output is rank order and short rationale, never a price, hour, availability claim, or venue it didn't retrieve. Its output is IDs + ranks + rationale strings; every display fact in the UI still comes from `GroundedVenue`. Rationale strings are model prose and are treated accordingly: they may be shown as "why we picked this" copy, but they are never parsed, never trusted as fact, and never allowed to contradict a warning (the validator's warnings are appended after curation and cannot be erased — Step 1's rule, unchanged).

### 5.4 Tool boundary

`SearchDistrictVenuesTool` wraps `DistrictVenueProvider` and is read-only, deterministic, and bounded: at most a fixed number of results per call (§10.3), compact fields only, every result carrying its dataset-owned `VenueID`. It never fabricates, never reorders nondeterministically, and never returns a venue the provider didn't. Tool call failures (there should be none — the dataset is bundled — but decode regressions exist) surface as thrown errors that the adapter maps to `PlanningFailure`, not as empty-but-successful results.

### 5.5 Evidence boundary (extended to MapKit)

MapKit is a second evidence *enricher*, not a second evidence *source of truth*. The dataset still decides which venues exist; MapKit may only attach coordinates to them. An enriched venue carries its coordinate provenance implicitly (coordinate present = geocoded; absent = not); the `EvidenceSource` of the venue remains `bundledDataset` because the venue's *facts* are still the dataset's. `MKLocalSearch` results are matched conservatively (name + area proximity); an ambiguous or failed match leaves `coordinate` nil rather than guessing. Nothing MapKit returns — POI category, hours, phone, URL — is copied onto the venue in this step.

### 5.6 Validator boundary (unchanged, now load-bearing)

`FeasibilityValidator` is untouched and is now the thing standing between a live generative model and the UI. Every property Step 2 proved — invented IDs rejected, duplicates rejected, budget enforced, thin decks failed with the correct category split — is now the safety case for shipping model curation at all. If any Step 3 work is tempted to relax a validator rule to make the model's output pass, that temptation is the bug.

## 6. Core state machine

Unchanged from Steps 1–2. What changes is only the **driver** column:

| State | Step 2 driver | Step 3 driver |
| --- | --- | --- |
| `extracting` | `FakeBriefExtractor` | **`FoundationModelsBriefExtractor`** (gate → session → draft) |
| `researching` | `DistrictVenueProvider` | `DistrictVenueProvider` **+ MapKit coordinate enrichment** |
| `validating` | `FeasibilityValidator` | unchanged |
| `curating` | `FakeItineraryCurator` | **`FoundationModelsItineraryCurator`** (gate → session + tool → slots) |
| everything else | unchanged | unchanged |

The Step 2 discovery about phase order stands verbatim: the coordinator curates *then* validates, and the state names don't change. No transition-table edit is needed or permitted.

## 7. What does *not* change

- **All six service protocols.** If a protocol needs to change to accommodate the model, stop — that is a design smell to resolve by adapting on the adapter's side of the seam.
- **`TravelPlanningService`.** Zero edits (§3.1).
- **The fakes.** They stay, unmodified, as the no-model test doubles. `TravelPlanningServiceTests` keeps running on them so the coordinator's behavior contract remains testable on any Mac.
- **`BriefNormalizer`'s contract.** It gains the ability to read the draft's new provenance markers, but its outcome shape, defaults, clamping, and `.needsDetails` semantics are untouched.
- **The dataset.** `district-venues-delhi.json` may grow toward the 40–60 target any time (pre-demo polish, per Step 2 §16), but Step 3 has no dependency on it growing.

## 8. New components

| Component | File | Job | Frameworks |
| --- | --- | --- | --- |
| `ModelAvailabilityGate` | `Planning/AI/ModelAvailabilityGate.swift` | availability → `PlanningFailure` mapping; the only reader of `SystemLanguageModel.default.availability` | FoundationModels |
| `PlanningFailure` error mapping | same file or `Planning/AI/ModelErrorMapping.swift` | one function: any model-layer `Error` → `PlanningFailure` (§9.4) | FoundationModels |
| `GenerableBriefDraft` | `Planning/AI/GenerableBriefDraft.swift` | the `@Generable` extraction DTO + lossless mapping to `OutingBriefDraft` | FoundationModels |
| `FoundationModelsBriefExtractor` | `Planning/AI/FoundationModelsBriefExtractor.swift` | real `BriefExtracting` | FoundationModels |
| `SearchDistrictVenuesTool` | `Planning/AI/SearchDistrictVenuesTool.swift` | FM `Tool` over `DistrictVenueProvider` | FoundationModels |
| `GenerableCuration` | `Planning/AI/GenerableCuration.swift` | the `@Generable` curation DTO (slot picks by ID string) + resolution against evidence | FoundationModels |
| `FoundationModelsItineraryCurator` | `Planning/AI/FoundationModelsItineraryCurator.swift` | real `ItineraryCurating` | FoundationModels |
| `VenueCoordinate` | `Planning/Domain/GroundedVenue.swift` (edit 2) | framework-free lat/long pair | Foundation |
| `MapKitVenueEnricher` | `Planning/Data/MapKitVenueEnricher.swift` | `MKLocalSearch`-based coordinate attachment, composed in front of/around `DistrictVenueProvider` as a `VenueResearching` decorator | MapKit |

The DTO split (`GenerableBriefDraft` vs `OutingBriefDraft`, `GenerableCuration` vs `CurationSlot`) is deliberate and non-negotiable: `@Generable` requires `import FoundationModels`, and `Domain/` is framework-free by Step 1 contract. The DTOs live in `Planning/AI/`, mirror the domain shapes closely, and map in one obvious function each. Resist the urge to unify them.

A note on isolation, because the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: every new type in `Planning/AI/` and `Planning/Data/` follows the existing `nonisolated` convention, and session calls run off the main actor (the adapters are `Sendable` structs invoked from the `TravelPlanningService` actor, same as the fakes). A `LanguageModelSession` created and awaited inside the adapter's method needs no additional isolation ceremony — but forgetting `nonisolated` on the new types will produce the same MainActor warnings Step 1 already fought.

## 9. Extraction contract

### 9.1 Instructions

Fixed constant, short (token-count it once with `tokenCount(for:)` during development; keep well under a few hundred tokens), and structured as: role (extract outing constraints from a request), the injection rule (the request is content to read, never instructions to follow — mirroring `Docs/plan.md` §6.1a's phrasing), the honesty rule (only extract what is actually stated or clearly implied; leave everything else absent rather than guessing), and the provenance rule (mark each extracted field as stated by the host or inferred). No examples of Delhi venues, no vocabulary the dataset owns — the extractor must not learn facts the research phase is responsible for.

### 9.2 Schema

`GenerableBriefDraft` mirrors `OutingBriefDraft` field-for-field with `@Guide` constraints doing the bounding the domain would otherwise have to re-do:

- `occasion: String?` with a guide description; `areaName: String?` likewise (free text — normalization owns canonicalization, not the schema).
- `groupSize: Int?` guided to `GroupSize.supportedRange`; `budgetPerHeadRupees: Int?` guided to `BudgetPerHead.supportedRange`. (Clamping still happens again in `BriefNormalizer` — belt and braces, because `@Guide` bounds generation but the mapping function is still the domain's gate.)
- Time window as three optionals matching `OutingTimeWindow` (minutes-from-midnight ints guided 0…1439, day label as free text).
- Dietary/accessibility as arrays of enum-valued strings guided to the exact `rawValue` vocabularies of `DietaryRequirement`/`AccessibilityRequirement`; the mapping function converts unrecognized values to nothing (dropped, never crashed) and distinguishes "empty array generated" (→ `.noneStated` only if the model explicitly flagged it; otherwise `.unknown`) conservatively — when in doubt, `.unknown`, which the validator already treats honestly.
- `setting` guided to `SettingPreference` raw values; `vibeTags` bounded `.count` guide; `notes` bounded.
- Per-field provenance (§9.3).

Property order matters for nothing here (no streaming in this step — extraction output is small), so order fields for readability.

### 9.3 The provenance edit (permitted edit 1)

`OutingBriefDraft` gains the minimal marker that closes the baseline's known gap. The recommended shape — final call is the implementer's, with the constraint that it must stay `Equatable`, framework-free, and default-preserving so no Step 2 call site breaks:

```swift
/// How the extractor came to know a draft value.
nonisolated enum DraftProvenance: String, Sendable, Equatable { case stated, inferred }
```

with per-field optional markers only for the fields whose `Sourced` marker the normalizer must decide (`occasion`, `area`, `groupSize`, `budgetPerHead`, `timeWindow`), defaulting to `stated` so every existing initializer call in fixtures and fakes keeps its current meaning. `GenerableBriefDraft` carries the same per-field marker generated by the model; `BriefNormalizer` maps `stated → .host`, `inferred → .modelSuggestion`, absent → `.safeDefault` (existing behavior). Then restore `BriefNormalizerTests`' occasion assertion to full equality and update the two fixtures' expectations to whatever the fakes now declare (the fakes may need their canned drafts annotated — that is a test-double data change, not a behavior change, and is the one sanctioned touch to `FakeBriefExtractor`'s *data*, in the same commit as the tightened test).

### 9.4 Error mapping (one table, one function)

The deployment floor is 27, so the deprecated `GenerationError` is not used; the surface spans three types and every branch maps to a category Step 1 already reserved:

| Model-layer error | `PlanningFailure` category |
| --- | --- |
| gate: `.deviceNotEligible` | `.deviceIneligible` |
| gate: `.appleIntelligenceNotEnabled` | `.intelligenceDisabled` |
| gate: `.modelNotReady` | `.modelAssetsNotReady` |
| `LanguageModelError.guardrailViolation`, `.refusal` | `.guardrailRefusal` |
| `LanguageModelError.contextSizeExceeded` | `.contextTooLarge` |
| `LanguageModelError.unsupportedLanguageOrLocale` | `.guardrailRefusal` (message already says "try describing it differently"; a dedicated category is not worth a Step 1 edit) |
| `LanguageModelError.rateLimited`, `.timeout` | `.modelAssetsNotReady` (retry action `.waitAndRetry` is the honest UX for both) |
| `SystemLanguageModel.Error.assetsUnavailable` | `.modelAssetsNotReady` |
| `LanguageModelSession.Error.concurrentRequests` | `.modelAssetsNotReady` (should be unreachable — sessions are per-call — but mapped, not crashed) |
| `GeneratedContent.ParsingError`, any DTO-mapping failure | `.structuredOutputDecodingFailed` |
| anything else | `.structuredOutputDecodingFailed`, plus an `assertionFailure` in debug so an unknown case is noticed during development |

The mapping function is the **only** place these error types are caught; both adapters funnel through it. No failure message ever interpolates the underlying error's description.

### 9.5 Generation options

Greedy sampling (`GenerationOptions(samplingMode: .greedy)`) for extraction. Extraction is a classification/extraction task where creativity is a liability, and greedy output is reproducible enough to make the device-gated fixture tests meaningfully re-runnable. (Reproducibility still isn't guaranteed across OS model updates — the baseline table, not exact drafts, is the regression contract.)

## 10. Curation contract

### 10.1 Instructions

Fixed constant: role (assemble an outing from real venues for this brief), the grounding rule (venues come only from the search tool; call it before proposing anything; never name a venue you did not retrieve), the output rule (ranked venue IDs per category with a one-line rationale each; no prices, no hours, no availability claims — those belong to the evidence), and the constraint rule (respect the brief's dietary/accessibility/setting constraints when choosing among retrieved venues; when a venue's compliance is unknown, prefer known-compliant ones but do not claim the unknown is safe).

### 10.2 Schema

`GenerableCuration`: for each of up to four slots, a category (guided to `SlotCategory` raw values), and 3–5 candidate venue IDs (guided `.count`, as ID strings) with a short rationale each. The adapter resolves ID strings against the evidence snapshot: resolvable → `CuratedCandidate` with rank = position; unresolvable → dropped with one `PlanningEvent` limitation ("a suggestion couldn't be verified against real venues" — fixed string, no model text). Slot titles reuse the fake's category-title mapping so the downstream UI expectation is unchanged. If dropping unresolvable IDs leaves a slot under the validator's floor, that is exactly the `.insufficientCandidates` validation failure Step 2 made reachable — the pipeline's honesty path, not a crash.

### 10.3 Context discipline

The brief compacts to a few hundred tokens; the danger is evidence. Rules:

- The prompt contains the brief's constraint summary only — never a serialized venue list.
- `SearchDistrictVenuesTool.Arguments`: area (optional), category, and a bounded maximum; the tool returns at most **8 venues per call**, each as a compact single-line record (id, name, category, area, per-head cost band or "unknown", 2–3 vibe tags, offer text if any). No taglines, no limitations arrays, no timestamps — the model needs enough to *choose*, and the UI never renders tool output.
- Worst case (4 categories × 8 venues × ~25 tokens + instructions + brief + output) sits comfortably inside the 8K window with room to spare. Verify once with the Foundation Models Instrument during development rather than trusting this arithmetic.

### 10.4 Tool determinism

The tool delegates to `DistrictVenueProvider`'s existing deterministic search/order. Same arguments → same results, always — which makes tool-trajectory assertions in the Evaluations suite actually assertable.

## 11. MapKit vicinity contract

`MapKitVenueEnricher` is a `VenueResearching` **decorator**: it wraps `DistrictVenueProvider`, calls it, then best-effort attaches coordinates.

- Resolution: `MKLocalSearch` with `naturalLanguageQuery = "\(venue.name), \(venue.area), Delhi"`, region-biased to Delhi NCR. Accept a match only when it is unambiguous (top result whose name plausibly matches — conservative contains/fuzzy check); otherwise leave `coordinate` nil.
- Concurrency: enrich with bounded parallelism and an overall time budget (a few seconds); on timeout, return what's resolved so far. The pipeline must feel the same speed with MapKit misbehaving as without it.
- Failure: any error, no-network, or rate limiting → venues pass through unenriched, plus exactly one recorded `PlanningEvent` limitation ("map locations couldn't be verified" — fixed string). Never a `PlanningFailure`.
- Caching: resolved coordinates are cached in-memory per app session keyed by `VenueID`, so replans don't re-geocode. (Persisting them into the JSON later is a fine pre-demo polish task; not this step.)
- Scope: coordinates only (§5.5). `MKDirections`/travel time stays deferred; `ScheduleDrafter`'s `.travelTimeNotVerified` assumption remains true and stated.

This is the cuttable commit (§15). If the demo timeline compresses, the pipeline ships without coordinates and loses nothing but the map flourish — which is exactly why the enricher is a decorator and not a provider rewrite.

## 12. Composition

Who constructs what, in this step:

- **Tests** construct all combinations (fake/real per seam) — that's most of §13.
- **The app** gains one composition helper (e.g. `PlanningAssembly` in `Planning/`, Foundation-only signature, FM import allowed via its `AI/` dependencies) that answers "give me the live pipeline": real extractor, normalizer, MapKit-decorated provider, real curator, validator, drafter, no-op store. It has exactly one UI caller in this step — the capture harness below — which prevents the eventual bridge step from reaching into `AI/` internals.
- The fakes are **not** wired as an automatic runtime fallback. Unavailability is a visible `.failed` state with an honest retry action, per `Docs/plan.md`'s fallback philosophy — silently swapping to canned extraction would fabricate a working AI demo on a device that doesn't have one.

### 12.1 Live capture harness (the interim doorway)

Until the Siri intent exists, `PlanCaptureView` is the doorway, and Step 3 wires it — minimally:

- On submit (typed text or `PlanDictation`'s final transcript — both already end as a `String`), construct `PlanningInput(text:source:.directCapture)` and hand it to a `TravelPlanningService` built by `PlanningAssembly`, off the main actor, holding the `PlanningRunID` so the existing cancel affordance can call `requestCancellation(of:)`.
- Surface the outcome honestly with what the screen already has: its progress/status states while the run is in flight, and on completion either "plan ready" (`.ready` — the plan object is held, not yet rendered; the curation screen still shows `DemoPlan` until the bridge step) or the `PlanningFailure.userMessage` + retry action on `.failed`. If the capture screen has no natural place for the failure sentence, a minimal alert/inline text is acceptable; a redesign is not.
- The harness obeys the same privacy rule as everything else: the submitted text goes into `PlanningInput` and nowhere else — not into a log, not into any state that outlives the run.
- This is deliberately *observation-poor*: no live event timeline, no streaming, no `.needsDetails` screen. Its one job is proving, on device, that voice/text → extraction → research → curation → validation → schedule runs end to end. Everything richer is the bridge step.

## 13. Test plan

### 13.1 Deterministic tier (no model, any Mac — the default `WandrTests` run)

- **Error mapping:** every row of §9.4's table, as a pure function test.
- **DTO mapping:** `GenerableBriefDraft → OutingBriefDraft` across representative values — vocabulary hits, unrecognized enum strings dropped, bounds clamped, provenance carried; `GenerableCuration` resolution — resolvable IDs become ranked candidates, unresolvable IDs dropped with the limitation event, empty curation yields empty slots.
- **Tool:** `SearchDistrictVenuesTool` returns only dataset IDs, honors its result bound, is deterministic across repeated calls, and its compact record contains no field the spec excludes.
- **Provenance edit:** normalizer maps stated/inferred/absent to `.host`/`.modelSuggestion`/`.safeDefault`; `BriefNormalizerTests` restored to full equality; all Step 1/2 suites still green.
- **Coordinate edit:** `GroundedVenue` with and without a coordinate round-trips through provider decoding (JSON has no coordinate field — decodes nil), validator indifferent to its presence.
- **Enricher (with a stubbed geocoding seam):** attaches on unambiguous match, leaves nil on ambiguity/failure/timeout, emits exactly one limitation event per failed run, never alters venue facts, never changes terminal state. (Give the enricher an injectable geocoding function precisely so this tier never touches live MapKit.)
- **Coordinator:** unchanged tests keep running on the fakes.

### 13.2 Device-gated tier (real model; AI-capable host or physical device)

Guard with a runtime availability check that skips (not fails) when the model is unavailable, so the suite stays green on CI Macs while running for real on the demo device.

- The six fixture requests through the **full live pipeline** reproduce the Step 2 baseline terminal states (§3.2).
- The injection fixture: draft contains no instruction-shaped content; run reaches `.ready`; no event/failure carries the input text (re-run of Step 2's coordinator-level volatility test, now against the real extractor).
- The Hauz Khas request: curator's slots all resolve, plan validates, every candidate ID exists in evidence.
- Availability override runs (manual, scheme editor): each `.unavailable` reason produces the mapped `.failed` category — recorded as a checklist item in the PR description rather than automated, since the override is a scheme setting.

### 13.3 Evaluations tier (starter suite — `Docs/plan.md` §9)

Three golden fixtures (after-office, birthday, full-day — one of them in the Shortcut's labeled-block format, per §9's "both intake channels" requirement) + two adversarial (in-summary injected instruction → treated as content; request to invent availability → surfaces unknown). Assert: extraction field expectations, curator tool-call trajectory (the tool is called before any proposal; only dataset IDs appear), and warnings preserved into the plan. Keep it a starter: the point in `Docs/plan.md` is *having* the suite to say out loud in the pitch; depth is Milestone D polish.

### 13.4 What Step 3 does not test

WeatherKit, routes, PCC, Siri intent delivery, UI rendering, and live-MapKit assertions in CI (the enricher's live behavior is verified manually on the demo device; its logic is verified through the stub seam).

## 14. File layout for this step

```text
Wandr/
├── Planning/
│   ├── Domain/                       (two declared edits: OutingBriefDraft provenance, GroundedVenue coordinate)
│   ├── Services/                     (unchanged — zero edits)
│   ├── Data/
│   │   ├── DistrictVenueProvider.swift        (unchanged)
│   │   └── MapKitVenueEnricher.swift          (new — VenueResearching decorator, imports MapKit)
│   ├── AI/
│   │   ├── FakeBriefExtractor.swift           (unchanged code; canned-draft data may gain provenance markers)
│   │   ├── FakeItineraryCurator.swift         (unchanged)
│   │   ├── ModelAvailabilityGate.swift        (new)
│   │   ├── ModelErrorMapping.swift            (new — or folded into the gate file)
│   │   ├── GenerableBriefDraft.swift          (new)
│   │   ├── FoundationModelsBriefExtractor.swift (new)
│   │   ├── SearchDistrictVenuesTool.swift     (new)
│   │   ├── GenerableCuration.swift            (new)
│   │   └── FoundationModelsItineraryCurator.swift (new)
│   └── PlanningAssembly.swift        (new — the live-pipeline front door)
├── Capture/
│   └── PlanCaptureView.swift         (submit-path wiring only, §12.1 — design untouched)
└── WandrTests/
    └── Planning/
        ├── (all Step 1/2 suites — green, at most the two declared-edit test updates)
        ├── ModelErrorMappingTests.swift        (new)
        ├── GenerableMappingTests.swift         (new)
        ├── SearchDistrictVenuesToolTests.swift (new)
        ├── MapKitVenueEnricherTests.swift      (new — stubbed seam)
        ├── LivePipelineTests.swift             (new — device-gated, availability-skipping)
        └── Evaluations/
            └── PlanningEvaluations.swift       (new — starter suite)
```

## 15. Build sequence for this step

Small, testable commits; run the full `WandrTests` target after each (see `step2-baseline.md` §Verification for the exact `DEVELOPER_DIR=` invocation).

1. **Gate + error mapping.** `ModelAvailabilityGate`, the mapping function, and their deterministic tests. No session yet.
2. **Provenance edit.** `OutingBriefDraft` markers, `BriefNormalizer` mapping, fake-draft data annotations, `BriefNormalizerTests` tightened. All Step 1/2 suites green before continuing — this is the commit most likely to ripple, so it lands before any model code depends on it.
3. **Extraction.** `GenerableBriefDraft` + mapping + tests; `FoundationModelsBriefExtractor`; device-gated extraction tests; first live run of the six fixtures through extractor-real/curator-fake, checked against the baseline.
4. **Tool.** `SearchDistrictVenuesTool` + deterministic tests.
5. **Curation.** `GenerableCuration` + resolution tests; `FoundationModelsItineraryCurator`; device-gated full-live-pipeline run; baseline table reproduced and recorded (this step's equivalent of Step 2's commit 7 — append the live results to `step2-baseline.md` or a `step3-baseline.md`).
6. **MapKit enrichment.** Coordinate edit, `MapKitVenueEnricher` + stub-seam tests, manual demo-device verification. **Cut line: this commit and everything after it are droppable without breaking the step.**
7. **Assembly + capture harness.** `PlanningAssembly`, then the §12.1 wiring of `PlanCaptureView`'s submit path — the commit after which typing or dictating on the first screen runs the real pipeline on device. Verify manually with the six fixture requests spoken/typed.
8. **Evaluations starter.** The five-fixture Evaluations suite.

Do not begin the next step (UI bridge / Siri intent) until commit 5's live baseline is written down — it is the regression contract every later step inherits.

## 16. Explicitly deferred work

- `PlanOutingFromSiriSummaryIntent`, `AppShortcutsProvider`, the distributable Shortcut, and activating `PlanningInputSource.siriSummary/.shortcutSummary` — Milestone B, next step's doorway work.
- The UI bridge: rendering live runs in `CurationView`/`ScheduleView`, replacing `DemoPlan`, the `.needsDetails` screen, streaming partial candidates into the UI. (Streaming was deliberately left out of this step's adapters — outputs are small and the UI can't render partials yet; adopt `streamResponse` when the bridge exists to show it.)
- `DynamicProfile` consolidation of the two sessions (§2's declared cut).
- MapKit routes/travel time (`EstimateRouteTool`), WeatherKit (`GetForecastTool`), `ResolveOriginTool`, `LoadPreferencesTool`, PCC escalation, `ValidateItineraryTool` as a model-callable wrapper.
- SwiftData persistence (`PlanningRunStoring` stays no-op), Live Activity, Messages extension, District Pass.
- Deepening the Evaluations suite past the starter five — Milestone D polish, per `Docs/plan.md` §7.

## 17. Final checklist for starting implementation

- [ ] Read `nonuistuff/step2-baseline.md` end to end — it is the acceptance contract for §3.2.
- [ ] Confirm the demo device (or dev Mac host for the simulator) has Apple Intelligence enabled and `SystemLanguageModel.default.availability == .available` before writing any device-gated test.
- [ ] Confirm the two declared Domain edits are additive-only by running the untouched Step 1/2 suites immediately after each edit.
- [ ] Token-count the two instruction constants once (`tokenCount(for:)`) and record the numbers in code comments.
- [ ] Verify one full curation exchange in the Foundation Models Instrument to confirm §10.3's context arithmetic.
- [ ] Confirm no file outside `Planning/AI/` imports FoundationModels, and none outside `Planning/Data/MapKitVenueEnricher.swift` imports MapKit, before the final commit (a simple grep is fine; make it a habit, not a hope).
- [ ] Exercise all three Simulated Foundation Models Availability overrides against the gate and record the outcomes in the PR description.
- [ ] After commit 7, run the six fixture requests through the capture screen by hand (typed and at least one dictated) on the demo device and confirm each reaches its baseline terminal state.
- [ ] Re-run the full `WandrTests` target after each commit in §15 — not just once at the end.

When these are complete, the next task is the **doorway and the bridge**: `PlanOutingFromSiriSummaryIntent` + Host Review intake (Milestone B) and wiring live runs into the existing UI — not more model work, and not the poll.
