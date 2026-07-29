# Wandr — Handover

**Last updated:** 2026-07-26
**Build state:** clean · **Tests:** 369 passing, 0 failing · **Runs on:** iOS 27 simulator + device

---

## 1. What Wandr is

An iOS app for **spontaneously planning an outing in Delhi NCR** — a date, an after-work
thing, a whole day — inside a budget and a perimeter, using Apple's **on-device
Foundation Models**. Nothing leaves the phone. No server, no API keys, no token cost.

The product bet: planning an evening is a *group* problem that dies in a group chat.
Wandr reads the chat (or listens to the host), turns it into a plan, lets the host
shortlist by swiping, and lets the squad vote.

**Target:** iOS 27 (Apple Intelligence required for the model paths).
**Bundle id:** `aryaman.Wandr`
**Dataset:** 98 hand-curated venues across 8 Delhi NCR areas — a placeholder for a live
Places API.

---

## 2. Getting it running

Xcode 27 beta is required. **`xcode-select` on this machine points at CommandLineTools**,
so every command needs the `DEVELOPER_DIR` prefix — or fix it once with
`sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer` (needs your password).

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild build -scheme Wandr -destination 'id=82BD28EC-4A98-42BB-892D-2F0F5F58DAE8'
xcodebuild test  -scheme Wandr -destination 'id=82BD28EC-4A98-42BB-892D-2F0F5F58DAE8'
```

That UDID is *iPhone 17 Pro Max*. There is **no plain "iPhone 17 Pro"** on this machine —
naming it by string fails. List with `xcrun simctl list devices available`.

Install and launch:

```bash
xcrun simctl bootstatus <udid> -b
xcrun simctl install <udid> ~/Library/Developer/Xcode/DerivedData/Wandr-*/Build/Products/Debug-iphonesimulator/Wandr.app
xcrun simctl launch <udid> aryaman.Wandr
```

Test result details:

```bash
xcrun xcresulttool get test-results summary --path <path>.xcresult
```

### ⚠️ SourceKit lies in this project

The editor reports **hundreds of false errors** — "Cannot find type `SlotCategory` in
scope", "No such module `Testing`", "External macro implementation type
`FoundationModelsMacros.GenerableMacro` could not be found". Every one of these is
SourceKit indexing against CommandLineTools instead of Xcode 27 beta.

**`xcodebuild` is the only source of truth.** Do not act on editor diagnostics. If
`xcodebuild` succeeds, the code is fine.

### Xcode 27 project format

The project uses `PBXFileSystemSynchronizedRootGroup`. **New files are picked up
automatically** — never hand-edit the `.pbxproj` to add a file.

---

## 3. Application flow

### 3.1 The two ways in

```
┌─ SIRI PATH ────────────────────────────────────────────────────┐
│  WhatsApp/iMessage group chat                                  │
│    → user runs the Wandr Shortcut                              │
│    → Shortcut's own `Use Model` step extracts JSON             │
│      (prompt: Wandr/Resources/chat-extraction-prompt.txt)      │
│    → PlanOutingFromSiriSummaryIntent receives raw text         │
│    → ChatSummaryPayload.decode(from:)                          │
└────────────────────────────────────────────────────────────────┘

┌─ DIRECT PATH ──────────────────────────────────────────────────┐
│  Host types or dictates into PlanCaptureView                   │
│    → FreeTextSummaryExtractor (in-app Foundation Models call)  │
│    → ChatSummaryPayload                                        │
└────────────────────────────────────────────────────────────────┘
```

Both converge on `ChatSummaryPayload` — the single structured summary type.

### 3.2 Screen flow (`IntakeState` → `RootView`)

```
onboarding ──► awaitingSummary ──┐
                                 ├──► hostReview ──► confirmed ──► planning ──► decks
capturing ──► extracting ────────┘         │
                                            └──► recovery (emptySummary / handoffUnavailable)
```

| State | Screen | What happens |
|---|---|---|
| `onboarding` | `ShortcutSetupView` | Host installs the Shortcut, copies the prompt |
| `awaitingSummary` | `AwaitSiriSummaryView` | Waiting for the intent to fire |
| `capturing` | `PlanCaptureView` + `PlanDictation` | Host types or speaks |
| `extracting` | spinner | `FreeTextSummaryExtractor` runs |
| `hostReview` | `HostReviewView` | **Shows every extracted field back to the host before planning** |
| `recovery` | `RecoveryView` | Nothing usable; never a dead end |
| `confirmed` | → planning | Payload handed to `PlanningCoordinator` |

Then: `CurationView` (swipe decks) → `SquadPollView` (group vote) → `ScheduleView`
(editable timeline) → share.

**Host Review is the trust surface.** Everything the model claims the host said is
displayed for confirmation before a single venue is fetched. This is why invented
fields were treated as a serious bug rather than cosmetic (§6.4).

### 3.3 The planning pipeline

`TravelPlanningService` is the **only** owner of a run. Seven stages, fixed order:

```
PlanningInput (validated, volatile — never persisted)
   │
   ├─1─ EXTRACT      BriefExtracting          → OutingBriefDraft      [MODEL]
   │                 (everything optional, everything untrusted)
   │
   ├─2─ NORMALIZE    BriefNormalizer          → OutingBrief
   │                 (wraps every value in Sourced<T>: .host / .modelSuggestion / .safeDefault)
   │
   ├─3─ RESEARCH     VenueResearching         → [GroundedVenue]
   │                 (DistrictVenueProvider — the live-API seam)
   │
   ├─4─ RESOLVE      EvidenceResolver         → (eligible, relaxations)   ★ NEW
   │                 (pure Swift; gives up constraints rather than failing)
   │
   ├─5─ CURATE       ItineraryCurating        → [CurationSlot]        [MODEL]
   │                 (FoundationModelsCurator — the model ranks indices, nothing more)
   │
   ├─6─ VALIDATE     FeasibilityValidator     → WandrPlan
   │                 (deterministic; the only thing that can mint a WandrPlan)
   │
   └─7─ SCHEDULE     ScheduleDrafter          → ScheduleDraft
                     (timeline blocks, with every assumption disclosed)
```

`PlanningState` transitions are a strict table with **no self-transitions** — re-entering
a phase throws `IllegalPlanningTransition`, treated as a wiring bug, not a runtime
condition:

```
idle → extracting → {needsDetails, researching, failed, cancelled}
researching → {validating, failed, cancelled}
validating  → {curating, needsDetails, failed, cancelled}
curating    → {ready, failed, cancelled}
ready → {idle, researching}     failed → {idle, extracting, researching}
```

---

## 4. The three rules the architecture rests on

### Rule 1 — The model ranks; deterministic Swift owns every contract

`FoundationModelsCurator` is the **only** file in the planning core allowed to
`import FoundationModels`. Its output is a *preference ordering* over a list the app
already holds — indices into a numbered list, plus one sentence of prose each.

It never emits a name, a price, an availability claim, or a venue ID. Indices are
resolved back to dataset `VenueID`s by the app. Whatever the model fails to supply is
backfilled from the provider's own deterministic rank.

**Two safety properties hold by construction:**
1. The curator sees only the typed brief and the dataset — never the host's raw words.
   There is no free-text channel for prompt injection to arrive on.
2. The candidate list and brief are framed as **DATA** in the instructions. Text inside
   a venue name or tag is never treated as a command.

The one genuine injection surface is `FreeTextSummaryExtractor`, which *does* see host
text. It's contained by: instructions that frame input as content; a fixed `@Generable`
schema of scalar fields with no tool and no free-text output; and re-validation of every
returned value.

### Rule 2 — Nothing dead-ends

Constraints have **degrees of satisfaction**, not a binary satisfy/violate. When the
request can't be met exactly, Wandr gives up the least important constraint — and
**says so**. See §5.

### Rule 3 — Guessing is allowed; hiding the guess is not

Every inferable brief value carries a `ValueSource` (`.host` / `.modelSuggestion` /
`.safeDefault`). Host Review shows what was extracted. Relaxations are disclosed.
Warnings ride on the plan and the model cannot remove them.

This marker was written for the review screen and turned out to be exactly the
importance weight the constraint ladder needed (§5.2).

---

## 5. The constraint ladder (the core of the current design)

### 5.1 Why it exists

Before it, every constraint was binary and the run either satisfied all of them or
**died**. A group of two with ₹2000 between them asking for lunch got:

> One pick works out to ₹2400 a head, over your ₹2000 limit.

…and a *Try again* button that could only ever produce the same dead end. The users
least able to act on that message — tight budget, small neighbourhood — were exactly
the ones who got it.

### 5.2 How it works

**`ConstraintLadder.rungs(for:)`** returns the constraints that actually bind this brief,
ordered `(provenance, productRank)` ascending:

| rank | constraint | why it goes first |
|---|---|---|
| 1 | `setting` | indoor/outdoor is a preference, not a need |
| 2 | `budget` | costs money, not the outing |
| 3 | `timeWindow` | bends the schedule |
| 4 | `requestedStops` | last — they *asked* for lunch |

Provenance outranks product order: a **Wandr-defaulted** budget is dropped before a
**host-stated** time window. `vibe` is deliberately absent — it has never filtered a
venue, only ranked one, so a rung for it would claim a compromise nobody made.

**`EvidenceResolver.resolve(brief:evidence:)`** — pure Swift, no model call, cannot fail:

1. Compute what the plan will need (from `SlotSchedule`, not just `requestedStops`).
2. Filter evidence under all constraints.
3. If any needed category is empty → relax the next rung → re-filter.
4. Repeat until satisfied or the ladder is exhausted.
5. **Only record a relaxation that actually put something back** — a rung that changed
   nothing was not a compromise worth claiming.

Returns `(eligible: [GroundedVenue], relaxations: [PlanRelaxation])`, each relaxation
carrying a host-readable disclosure like *"Nothing here fits ₹2000 for the group — these
are the closest we found."*

### 5.3 What is never relaxed

**`dietary` and `accessibility`.** Relaxing those means proposing food someone cannot eat
or a door someone cannot get through — that is not a degraded plan, it is a harmful one.
They stay hard filters in `ConstraintEligibility`, which has an `ignoringSetting`
parameter and deliberately **no equivalent for those two**.

An area with no coverage stays `areaNotCovered` — that's a fact about the dataset, not a
preference.

### 5.4 What can still fail the run

Only three things now:

1. **Model unavailability** — device ineligible / Apple Intelligence off / assets not
   ready. Each has its own host action.
2. **`insufficientEvidence`** — the ladder is exhausted and there is *nothing at all* to
   show. This is the first time "try widening the area" has been true advice.
3. **`validationFailed`** — genuine model misbehaviour: an invented venue, a duplicate
   within a deck, the same venue in two stops, or a contradicted hard constraint.

Everything else degrades: over-budget → a warning on the card; thin deck → a thin deck
with a note.

---

## 6. Every bug found and fixed

Chronological. Each entry: symptom → root cause → fix. **Note how few were the model.**

### 6.1 "3 hours" planned a whole day
- **Symptom:** host said they had 3 hours; got a full-day itinerary.
- **Cause:** `OutingTimeWindow` had no duration axis. "3 hours" fell through to the clock
  parser, which read the bare `3` as an evening hour and produced *"starts at 3 pm with
  no end"* — a window strictly worse than saying nothing.
- **Fix:** third axis `maximumDurationMinutes`; duration text is excised *before* clock
  scanning (they share digits); `SlotSchedule` closes the window from the right.

### 6.2 Searching "Khan Market" returned everywhere but Khan Market
- **Cause:** `matches.isEmpty ? allVenues : matches` — an area the dataset didn't cover
  silently widened to the entire city.
- **Fix:** Khan Market added (12 venues); an uncovered named area is now an honest
  `areaNotCovered` failure listing only dataset-owned coverage.

### 6.3 "CP" returned Nizamuddin
- **Cause:** whole-string `canonicalArea` matching. Verbose extractor output ("the CP
  area") missed every alias, dumped all 85 venues ranked cheapest-first — and Nizamuddin
  is the cheapest area.
- **Fix:** token-run alias matching. Short aliases are rejected only when preceded by a
  number, so `km` = Khan Market but "5 km from CP" is kilometres.

### 6.4 Host Review showed constraints the host never said
- **Symptom:** host said "outing at 12:30, lunch"; got back OUTING = *After-office*,
  ACCESSIBILITY = *step-free entry*, VIBE = *quiet*.
- **Cause:** **all three were verbatim copies of Wandr's own `@Guide` sample values.**
  A small on-device model reads an example sitting next to an empty optional field as a
  default to emit. Not hallucination — the prompt implied it.
- **Fix:** every quoted sample *value* removed from all `@Guide` descriptions **and** from
  `chat-extraction-prompt.txt`. Plus a deterministic backstop: `unechoed()` drops a
  constraint whose content words appear nowhere in the host's text; `outingType()`
  requires keyword support.
- **Rule for the future:** *describe the field; never show a value that would be valid to
  return.*

### 6.5 "Lunch" was structurally impossible
- **Symptom:** "we want lunch" returned Agrasen ki Baoli, a stepwell.
- **Cause:** the `food` category existed **only 20:00–22:00**. A 12:30–2pm window
  intersected exactly one band — `sights`. The model was never shown a restaurant.
- **Fix:** categories own multiple bands (`food` = Lunch 12:00–15:30 *and* Dinner
  20:00–22:00). Latest-qualifying-band selection keeps dinner the default when the evening
  is open.
- **Also found:** bands were intersected with the window **independently**, so a 90-minute
  window could promise three separate hour-long stops. Layout is now sequential with
  minimums reserved for later stops.

### 6.6 "I just said lunch" still produced a 10pm bar
- **Cause A:** the request only **re-ranked** bands, and only inside a capacity budget
  that ran for windows bounded at *both* ends. The host named no time → open window →
  that branch never executed → the whole band table survived.
- **Cause B:** `Set<SlotCategory>` cannot tell lunch from dinner. Even once food won, the
  latest qualifying band is Dinner.
- **Fix:** `SlotBand` (`lunch`/`afternoon`/`somethingNew`/`dinner`/`late`) replaces
  category as the unit of request. A named request **filters**, it does not rank.

### 6.7 The budget screenshot — two bugs in one sentence
- **Symptom:** *"One pick works out to ₹2400 a head, over your ₹2000 limit"* → dead end.
- **Cause A:** the field was `budgetPerHead: Int`. Nothing established whether the host's
  number was per head or for the group; Wandr assumed per head, then compared it against
  a per-head venue price. It even told the model *"budget around ₹3000 per head"* when the
  host never said "per head" — the same invention class as 6.4.
- **Cause B:** over-budget was a `FeasibilityViolation`, and violations fail the **whole
  run**. Fix 6.6 made this far more likely: a "lunch" request produces exactly one deck,
  so a single expensive candidate had nothing to hide behind.
- **Fix A:** `Budget` is `.unspecified` / `.perHead` / `.total`. **An unqualified number
  is the group's total** — only `each`, `per head`, `a head`, `pp`, `per person`, `/head`
  make it per-head. `ceilingPerHead(for: GroupSize)` is the one place a total is divided.
- **Fix B:** the constraint ladder (§5). Over-budget is now `PlanWarning.overBudget`,
  rendered on the card.

### 6.8 Thin decks killed the run
- **Cause:** fewer than 3 candidates threw `insufficientCandidates` or
  `insufficientEvidence`.
- **Fix:** both deleted. A shortfall is `PlanWarning.thinDeck`. Two real restaurants beat
  no plan. `minimumCandidatesPerSlot` is now what `SlotDeckBuilder` fills *towards*, not a
  contract anyone dies over.

### 6.9 The squad poll merged two food stops *(latent — never reported)*
- **Cause:** `PollSession` keyed ballots by `deck.category.rawValue`. Two `.food` decks
  would have shared one ballot — voting on lunch would also have voted on dinner.
- **Fix:** slot identity is the band, threaded through `CurationSlot` → `Deck.slotID` →
  poll → `ScheduleDrafter` → `CurationView.slotWindows`.

### 6.10 The curator would have silently undone every relaxation *(latent — caught pre-ship)*
- **Cause:** `FoundationModelsCurator` called `ConstraintEligibility.isEligible` again
  *after* `EvidenceResolver` had already filtered and relaxed. It would have dropped the
  exact venue kept because the alternative was an empty deck — while the host still saw
  the disclosure saying it had been kept.
- **Fix:** the curator no longer filters. Comment in place explaining why.
- **General rule:** **anything that re-filters after `EvidenceResolver` silently undoes a
  relaxation.**

### 6.11 "Lunch and snacks" → "The same place was picked for two different stops"
- **Symptom:** Saket, 12–5pm, 5 people, ₹1500/head, "lunch and snacks" → dead end.
- **Cause:** *self-inflicted by 6.6/6.9.* Both words map to food, so the plan had two food
  stops. Each deck was rebuilt from the **full category pool** with no memory of what
  earlier stops took, so the same restaurant landed in both — and `FeasibilityValidator`
  Rule 3 (no venue reuse) killed the run.
  The plan had asserted *"Rule 3 already guarantees lunch and dinner get different
  restaurants."* **That was wrong — Rule 3 detects the collision, it doesn't prevent it.**
- **Fix A:** `SlotDeckBuilder.build(excluding:)` — a venue an earlier stop took is off the
  table.
- **Fix B:** `limit:` — Fix A alone made the lunch deck eat all 4 venues, so dinner was
  dropped for having nothing. Each deck now reserves at least one venue per later stop
  sharing its category. Same reservation principle `layOut` uses for time.

---

## 7. Research grounding

The relaxation design is not invented. It follows how production systems solve this.

**[Google's trip planner](https://research.google/blog/optimizing-llm-based-trip-planning/)**
splits the work: the LLM interprets *qualitative* preferences using world knowledge; a
deterministic optimizer owns *quantitative* constraints (hours, travel time, budget). When
the LLM proposes something infeasible the optimizer **substitutes** rather than rejects —
it *"avoids binary failure … rather than rejecting infeasible requests outright."*
Wandr already had the split; the enforcement half **threw** where Google's substitutes.

**[AWARE-US](https://arxiv.org/html/2601.02643)** (Jan 2026) formalises the missing half as
*preference-aware query repair*: rank constraints by importance, relax the lowest first,
iterate until feasible. It names Wandr's exact failure — *"prior systems often respond with
'no results' or apply ad hoc relaxations, which can violate user intent."*

**[Soft constraints](https://link.springer.com/article/10.1007/s10601-010-9098-8)** —
constraints have degrees of satisfaction, not a binary. Wandr modelled every constraint as
binary.

**Where Wandr improves on the paper:** AWARE-US does *not* tell the user what it relaxed.
Wandr's premise is the opposite (Rule 3). We relax **and** disclose.

**The cheap part:** AWARE-US uses an LLM to infer importance weights from dialogue. Wandr
doesn't need to — `Sourced<Value>.source` was already an importance weight on every field.

Also relevant: **LLM+P** (natural language → formal spec → classical solver) is the pattern
behind §8.2.

---

## 8. Technology decisions

### 8.1 Core AI (WWDC26) — evaluated, not adopted

Core AI is real: `.aimodel` assets, a memory-safe Swift runtime (`AIModel`,
`InferenceFunction`, `NDArray`), KV-cache states, ahead-of-time compilation via
`coreai-build`, specialization + `AIModelCache`.

**It is not Wandr's problem.** Core AI solves *"I need a custom LLM-scale model on
device."* Every defect in §6 is deterministic Swift *around* the model — a budget basis
never established, a violation that throws instead of relaxing, a slot identity that
collides. Shipping a custom model would add a ~1 GB Background Assets download, first-run
specialization stalls, and per-OS asset management, and would fix **none** of them.

**But keep the seam in view.** The open-source `coreai-models` package exposes
`CoreAILanguageModel`, which conforms to Foundation Models' `LanguageModel` protocol — a
`LanguageModelSession` can be backed by a custom model **without changing any `@Generable`
code**. Everything in the pipeline is engine-agnostic by construction. If the 3B on-device
model turns out to be the ceiling, the model swaps and the pipeline doesn't move.

### 8.2 The model proposes the plan shape; Swift validates it

`ExtractedSummary.stops: [String]?` — a closed vocabulary (`lunch`, `afternoon`,
`somethingNew`, `dinner`, `late`), validated in `ChatSummaryBriefMapper.band(named:)`
against `SlotBand`, unknowns dropped.

`[String]`, **not** a `@Generable` enum — a non-frozen enum traps on a case the model
invents. Same treatment as `outingType`.

This is the one job a small model does genuinely better than a keyword table: *"something
to eat before the movie"* is a lunch, and no list of nouns will ever say so. The keyword
scan (`keywordStops`) is the **fallback**, which also keeps the path testable with no
model and no device.

### 8.3 Sampling is left at the framework default

Deliberate. Reliability comes from the schema, the validator, and the backfill — not from
pinning to greedy decoding, which would make every run of the same brief return an
identical slate and read as hardcoded. `maximumResponseTokens: 400` is a runaway guard,
not a quality knob.

---

## 9. Domain model reference

| Type | File | Notes |
|---|---|---|
| `Sourced<Value>` | `OutingBrief.swift` | value + `ValueSource`. **Doubles as the ladder's importance weight** |
| `OutingBriefDraft` | `OutingBrief.swift` | model output; every field optional and untrusted |
| `OutingBrief` | `OutingBrief.swift` | normalized, canonical; the only thing research/curation consume |
| `Budget` | `OutingBrief.swift` | `.unspecified` / `.perHead` / `.total`; `ceilingPerHead(for:)` |
| `OutingTimeWindow` | `OutingBrief.swift` | 3 axes: earliest start, latest end, **max duration** |
| `SlotBand` | `SlotSchedule.swift` | **the unit of a stop.** lunch / afternoon / somethingNew / dinner / late |
| `SlotSchedule` | `SlotSchedule.swift` | which stops fit the window; `requestHonoured` flags a dropped request |
| `RelaxableConstraint` | `ConstraintLadder.swift` | setting / budget / timeWindow / requestedStops |
| `PlanRelaxation` | `ConstraintLadder.swift` | constraint + mandatory host-readable disclosure |
| `GroundedVenue` | `GroundedVenue.swift` | immutable evidence snapshot; `VenueCost` is **always per head** |
| `CurationSlot` | `WandrPlan.swift` | `slotID` derived from `band` — never from category |
| `WandrPlan` | `WandrPlan.swift` | immutable; only `FeasibilityValidator` can mint one |
| `PlanWarning` | `WandrPlan.swift` | incl. `.overBudget`, `.thinDeck`; model cannot remove |
| `PlanningFailure` | `PlanningFailure.swift` | every case has a message **and** a `retryAction` — no dead ends |

### The band table

```
Lunch          12:00 – 15:30   (.food)
Afternoon      12:30 – 17:00   (.sights)
Something new  17:00 – 20:00   (.discover)
Dinner         20:00 – 22:00   (.food)
Late           22:00 – 25:00   (.nightlife)   ← 25:00 = 1am, renders correctly
```

Selection rules: a **non-empty request is the stop list** (all of it, including two of one
category). An **empty request** collapses to one stop per category, taking the *latest*
band that fits — which is why an open evening means dinner, not lunch.

---

## 10. Testing

**369 tests, 0 failing.** Swift Testing throughout (`@Test`, `@Suite`, `#expect`,
`#require`, parameterised `arguments:`).

| Suite | Covers |
|---|---|
| `PlanShapeEvaluationTests` | **The golden set** — see below |
| `ConstraintLadderTests` / `EvidenceResolverTests` | Ladder order, relaxation minimality, hard-constraint floor |
| `SlotScheduleTests` | Bands, durations, multi-stop, overlap |
| `ChatSummaryBriefMapperTests` | Budget basis, time parsing, stop classification, end-to-end regressions |
| `FeasibilityValidatorTests` | Every violation + the warnings that replaced two of them |
| `TravelPlanningServiceTests` | Full pipeline, state machine, cancellation |
| `SlotDeckBuilderTests` | Deck contract, budget ordering, dedup |
| `FreeTextSummaryExtractorTests` | Anti-echo backstop, value validation |
| `DistrictVenueProviderTests` | Area aliasing, coverage, ranking |
| `PollTallyTests`, `PlanningRunStateTests`, `ScheduleDrafterTests` | … |

### The golden set (`PlanShapeEvaluationTests`)

15 realistic phrasings scored **as a set**, not case by case. This exists because every
previous fix passed its own test while breaking something two files away.

It earned itself on first run: **13/15**, and both failures were wrong assumptions in the
dataset, not the code (an open window resolves food to dinner, not lunch; an 8-hour day
fits three stops, not two). Neither would have surfaced in a per-rule test.

Guardrails that must hold for *every* case: no plan is ever empty; no constraint is ever
invented; stops never overlap.

**`Evaluations` (Apple's iOS 27 framework) is NOT available in this Xcode beta** —
verified by compile probe, not inference:

```
$ echo 'import Evaluations' | swiftc -typecheck -
error: no such module 'Evaluations'
```

So the suite is plain Swift Testing with the same discipline. Each case carries the host's
literal sentence so the dataset replays against a real extractor when the framework lands.

---

## 11. Diagnostics

```bash
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.wandr.ai"' --level debug
```

**Privacy split in `AILog`** — counts, categories, durations, token totals, error
classifications and indices are `.public`; prompt text, host words and extracted field
values are `.private`. Never widen this.

Key lines:

| Line | Read it for |
|---|---|
| `PLAN slots=… requested=… relaxed=… windowStart/End=… durationCap=… areas=… eligible=…` | The single most useful line. `requested=-` means the stop word never survived extraction (a *different* bug from one the schedule got wrong). `areas=7` for a host who named one neighbourhood means a mis-resolved area. |
| `SLOT-DONE source=backfilled` | The model failed and deterministic ranking covered it — invisible in the UI |
| `rejectedOutOfRange` rising | The model has stopped understanding the numbered list |
| `SLOT-SKIP reason=…` | A deck silently vanished — first thing to check on a short plan |
| `settled=[…]` | Exactly which fields extraction returned |

**Because failures now degrade instead of stopping, regressions go silent.** That is why
these counters exist. **Read the log before blaming the model** — of the eleven bugs in
§6, exactly zero were the model reasoning badly.

---

## 12. Known gaps and unverified claims

Be honest about these; they are the difference between "tested" and "works".

### Cannot be verified on this machine
- **No model call has ever been executed in the simulator.** Apple Intelligence is
  unavailable there. Both extraction and curation are verified by compile + unit tests on
  pure logic only. **The anti-echo behaviour and the model's stop classification are
  unproven against a real model.**
- **No UI tap-through.** AXe/xcui cannot drive the app — it can't load
  `SimulatorKit.framework`, relocated to `Contents/SharedFrameworks` in Xcode 27 beta.
- **Apple's `Evaluations` framework is unavailable** (§10).

### Design limitations
- **"Snacks" expands to lunch-or-dinner.** The keyword table can't tell a snack from a
  meal, and there is no `.snack` band for it to land on. Harmless in a midday window;
  coarse in general.
- **Travel time between stops is not modelled.** No MapKit. `travelNote` is empty rather
  than faked.
- **Venue opening hours are not matched against the window.** `SlotSchedule` gates *slots*,
  not venue hours; the validator's `unknownHours` warning rides along instead.
- **The dataset is 98 venues across 8 areas.** Nizamuddin has only 6. A tight budget in a
  thin area will produce thin decks — correct behaviour now, but it looks sparse.
- **Host Review fields are not editable.** The host can confirm or start over, not correct.

---

## 13. Pending work

Roughly in priority order.

1. **Live Places API.** `VenueResearching` is the retriever seam — swapping it should not
   touch the curator, validator, or scheduler. The ladder in §5 is where API results get
   relaxed against. This is the user's stated direction: fire a live API on JSON receipt
   and curate from live ratings.
2. **Verify the model paths on a real device.** 10/10 runs reaching `.ready`; the full
   manual path (mic → extraction → Host Review → confirm → decks → schedule → share);
   confirm the anti-echo guard against a real model.
3. **`session.prewarm()`** on `HostReviewView` appearance, so model load is off the
   critical path.
4. **Two-phase generation for latency.** Pass 1 = indices only (~30 tokens/slot); pass 2 =
   rationales streamed after decks render. Needs `RationaleWriter`, a
   populatable-after-construction `CuratedCandidate.rationale`, and a UI ripple. Note the
   `.count(3...5)` floor *raises* rationale token count, so this matters more, not less.
5. **Adopt `Evaluations`** when it appears in the SDK — the golden set is already shaped
   for it. Model-as-judge needs Cohen's kappa > 0.6 calibration before its scores mean
   anything.
6. **Editable Host Review fields.**
7. **A `.snack` band**, or a finer stop vocabulary.

---

## 14. Landmines — read before you change anything

1. **Never re-filter evidence after `EvidenceResolver`.** It silently undoes a relaxation
   the host was already told about. (§6.10)
2. **Slot identity is `SlotBand`, never `SlotCategory`.** Lunch and dinner are both
   `.food`. Keying anything by category collapses them — it has already broken the curator,
   the poll, and the schedule once each. (§6.9, §6.11)
3. **Never put a sample *value* in a `@Guide` description or the Shortcut prompt.** The
   model emits it verbatim as a default. Describe the field instead. (§6.4)
4. **Venue costs are always per head; budgets may not be.** Only `ceilingPerHead(for:)`
   may bridge them. Never compare `statedRupees` to a price. (§6.7)
5. **`dietary` and `accessibility` are never relaxed.** No parameter, no flag, no
   exception. (§5.3)
6. **A rule implemented in only one curator is a rule the other silently breaks.**
   `SlotDeckBuilder` and `ConstraintEligibility` are shared by `FoundationModelsCurator`
   and `FakeItineraryCurator` precisely so a green test can't prove nothing.
7. **Ignore SourceKit.** `xcodebuild` is the only truth. (§2)
8. **`ls -td`, not `ls -t`,** when listing `.xcresult` bundles — they're directories.
9. **Two stops of one category must not share a venue, and the first must not eat the
   pool.** `excluding:` and `limit:` on `SlotDeckBuilder`. (§6.11)
10. **Duration text must be excised before clock scanning.** "3 hours" and "3 o'clock"
    share their digits. (§6.1)

---

## 15. Reference

- **Repo:** `/Users/aryamanjaiswal/Downloads/Github_pulls/Wandr`
- **Simulator UDID:** `82BD28EC-4A98-42BB-892D-2F0F5F58DAE8` (iPhone 17 Pro Max, iOS 27.0)
- **Dataset version:** `delhi-ncr-2026-07c` — 98 venues; food 28, sights 24, nightlife 23,
  discover 23
- **Areas covered:** Hauz Khas (15), Connaught Place (14), Lodhi (13), Cyberhub (13), Khan
  Market (13), Saket (12), Aerocity (12), Nizamuddin (6)
- **Older design docs:** `Docs/` — `plan.md`, `AI-Orchestration-Flow.md`,
  `AI-Integration-Blueprint.md`, `AI-Technology-Stack.md`. **Treat these as historical
  intent, not current truth** — the constraint ladder, the budget basis, and multi-stop
  plans all postdate them.
