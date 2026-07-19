# Wandr Planning Core — Step 4: The UI Bridge

## 1. Purpose

Step 3 finished the real AI pipeline: a live `TravelPlanningService` extracts a brief
with `LanguageModelSession`, researches the bundled dataset with MapKit coordinate
enrichment, curates with a tool-calling session, validates deterministically, and drafts
a schedule. `LivePlanningHarness` runs it from the capture screen and holds the result.

**And then the UI throws it away.**

`CurationView.swift:13` reads `@State private var decks: [Deck] = DemoPlan.decks`. There
is no injection point. `RootView.swift:71-73` says so outright:

```swift
// A ready run is the "plan ready" acknowledgment: the curation screen appears,
// still showing DemoPlan (the live plan is held by the harness, not rendered,
// until the bridge step).
```

This was a declared deferral, not a defect. But it has a cost that only became visible
when a real request was run by hand: **a host typing "Six of us want dinner and music in
Hauz Khas Friday, ₹1,500 each" sees Diggin in Anand Lok, Sunder Nursery in Nizamuddin,
and Ghost Street in Cyber Hub** — the hardcoded `DemoPlan` fixtures, unrelated to the
request, spanning areas the brief never named. The pipeline very likely worked correctly.
Nobody can tell.

Step 4 makes the validated plan the thing the screen draws.

It is also a **prerequisite for judging any research-layer change.** Whether the 33-venue
/ 4-area dataset needs a live `MapKitVenueProvider` (see §11) is currently unanswerable,
because there is no way to look at what the pipeline picked. Building a new provider
before the bridge means building it blind — and would repeat exactly the debugging round
that produced this document.

## 2. Authority and scope

`Docs/plan.md` remains the architecture authority. `nonuistuff/plan.md` §16 already names
this work: *"The UI bridge: rendering live runs in `CurationView`/`ScheduleView`,
replacing `DemoPlan`."* Step 3 §3.12's "`CurationView`, `ScheduleView`, `DemoPlan` are
untouched" was scoped to Step 3 and is now lifted **for these files only**.

What stays closed: no Siri/App Intents (Milestone B), no `.needsDetails` screen, no
streaming partials, no replan loop, no new provider, no visual redesign. Step 4 changes
**what the existing screens are fed**, not how they look.

Three edits are declared up front, in the same style Step 3 declared its two:

1. **`WandrPlan` gains `evidence: [GroundedVenue]`** (§4.1) — additive, defaulted.
2. **`Candidate` becomes honest about unknowns** (§4.2) — `perHead`/`openWindow`/
   `travelNote` optional, plus a `venueID` and a warnings surface.
3. **`CurationView`/`ScheduleView` gain injection points** (§4.3) — `DemoPlan` survives
   as the preview default and nothing else.

## 3. The central finding: the evidence is discarded

This is the structural problem, and it is bigger than "map slots to decks."

`CuratedCandidate` (`WandrPlan.swift:43-45`) is documented as carrying nothing
displayable:

> *"It carries an ID and nothing displayable. Name, area, price, offer, and hours are
> resolved from the matching `GroundedVenue` at presentation time."*

That contract is correct and worth keeping — it is what stops the model contributing a
display fact. But **presentation time has no `GroundedVenue` to resolve against:**

| Holder | Carries | Evidence? |
| --- | --- | --- |
| `CuratedCandidate` | `venueID`, `rank`, `rationale` | ❌ |
| `WandrPlan` | `evidenceIDs: [VenueID]`, `evidenceSources` | ❌ IDs only |
| `PlanningRun` | `state`, `brief`, `events`, `failure`, `plan`, `missingConstraints` | ❌ |
| `LivePlanningHarness` | `readyPlan: WandrPlan?` | ❌ |
| `TravelPlanningService` | `schedules: [PlanningRunID: ScheduleDraft]` | ❌ (schedule only) |

The `[GroundedVenue]` array lives transiently inside `TravelPlanningService.plan()`,
passes to the curator, validator, and drafter, and is released when the run ends.

**Good news:** the schedule half is already solved. `TravelPlanningService:133` exposes
`func scheduleDraft(for runID: PlanningRunID) -> ScheduleDraft?`. No edit needed there.

### 3.1 Resolution: put the evidence on the plan

`WandrPlan` gains `evidence: [GroundedVenue]`. `FeasibilityValidator` already holds the
evidence at the moment it constructs the plan, so populating it is free — no new seam, no
protocol change, no `TravelPlanningService` edit.

This also makes the `CuratedCandidate` doc comment *true* for the first time: resolution
at presentation time becomes possible because the plan is finally self-contained.

**Alternative considered and rejected:** resolve IDs at presentation time by re-reading
`DistrictVenueProvider`. It avoids touching `Domain/`, but it loses MapKit-enriched
coordinates, re-does work, and **breaks entirely the moment a live `MapKitVenueProvider`
exists** — a live POI result is not re-findable by ID from a bundled file. It is the
wrong foundation for the step that follows this one.

## 4. Declared edits

### 4.1 `WandrPlan.evidence` (edit 1)

```swift
/// The evidence snapshot this plan was validated against.
///
/// Carried on the plan so presentation can resolve `CuratedCandidate.venueID` into
/// display facts without re-querying a provider — which would lose MapKit enrichment
/// and would not work at all for a live (non-bundled) provider.
let evidence: [GroundedVenue]
```

Additive, defaulted to `[]` so every existing construction site and test compiles
unchanged. `GroundedVenue` is `Equatable`, so `WandrPlan: Equatable` survives.

Add one convenience, since every consumer needs it:

```swift
func venue(_ id: VenueID) -> GroundedVenue? { evidence.first { $0.venueID == id } }
```

**Acceptance:** `FeasibilityValidatorTests` and every Step 1/2/3 suite pass **unmodified**
after this edit. If any test breaks, the edit was not additive and must be reworked.

### 4.2 `Candidate` becomes honest (edit 2)

This is where the bridge earns its keep. Five impedance mismatches between the UI model
and the domain, each of which is currently resolved by the UI simply *asserting* a fact:

| `Candidate` (UI) | Domain source | Problem |
| --- | --- | --- |
| `perHead: Int` | `VenueCost.unknown` | **cannot represent unknown** |
| `openWindow: String` | `OpeningHours.unknown` | cannot represent unknown |
| `travelNote: String` | **nothing** | no source exists at all |
| `id: UUID` (fresh) | `VenueID` | warnings are keyed by `VenueID` and cannot attach |
| — | `PlanWarning` | **no warning surface exists** |

Plus `StopCategory` (UI) and `SlotCategory` (domain) are parallel enums with identical
cases and need an explicit mapping.

**`travelNote` is the sharpest one.** `DemoPlan` says "14 min by cab from Hauz Khas" and
"41 min by cab — flagged". There is no travel-time source in the system: `MKDirections` is
deferred (`plan.md` §16), and `ScheduleAssumption.travelTimeNotVerified` exists precisely
to state that out loud. Rendering a computed-looking travel time for a live plan would
be **fabricating a display fact** — the exact failure the whole grounding architecture
exists to prevent. It becomes `travelNote: String?` and is `nil` for every live candidate
until `MKDirections` lands.

**`perHead` is the MapKit blocker** flagged during the provider discussion. Every future
`MapKitVenueProvider` venue has `VenueCost.unknown`. If `perHead` stays non-optional, the
next step has a deck of unrenderable venues and an incentive to invent a cost band. Fix
it here, once, before that pressure exists.

Resulting shape:

```swift
struct Candidate: Identifiable, Hashable {
    let id: UUID = UUID()
    /// The evidence this card is grounded in. Warnings attach through this.
    let venueID: VenueID?          // nil only for DemoPlan preview fixtures
    let name: String
    let area: String
    let tagline: String
    let category: StopCategory

    let perHead: Int?              // was Int      — nil = VenueCost.unknown
    let listPrice: Int?
    let offer: String?
    let offerWindow: String?

    let openWindow: String?        // was String   — nil = OpeningHours.unknown
    let travelNote: String?        // was String   — nil until MKDirections exists

    let imageSeed: Int

    /// Validator warnings about this venue. Never editable by the UI, never
    /// suppressible, never model-authored.
    let warnings: [String]
}
```

`savings` already guards on `listPrice`; it gains a `perHead` guard.

**Ripple:** `CurationView.costRange` (≈line 36) does
`deck.shortlisted.map(\.perHead)` then `.min()`/`.max()`. It becomes a `compactMap`, and
the header must distinguish "₹1,100–1,600" from "₹1,100–1,600 + 2 unpriced". A live plan
with unknown costs must not silently render a *narrower* range than the truth.

### 4.3 Injection points (edit 3)

```swift
struct CurationView: View {
    @State private var decks: [Deck]
    init(decks: [Deck] = DemoPlan.decks) { _decks = State(initialValue: decks) }
```

Same for `ScheduleView`'s `blocks`/`days`. `DemoPlan` is **not deleted** — it stays as the
default argument so all seventeen `#Preview` blocks keep working. It just stops being what
a live run displays.

## 5. Non-negotiable boundaries

### 5.1 Warnings must arrive

`PlanWarning`'s doc says *"Warnings are attached to the plan and survive every UI
mapping. The model cannot add, edit, or remove one."* Today they survive into a struct
nothing renders. The bridge is the first mapping that can actually violate this rule, so
it is asserted (§8): **for every warning on the plan, its text reaches a rendered
surface.** A plan with `unverifiedDietary` on a candidate must not draw a clean card.

### 5.2 No fabricated display facts

The mapper may only read `GroundedVenue` fields. It may not infer a cost band from a
category, synthesize a travel note, invent hours, or promote `rationale` into a factual
claim. Unknown renders as absent, never as a plausible number. This rule is what the
`Optional`s in §4.2 exist to make *representable* — without them the type system forces a
lie.

### 5.3 `rationale` is prose, not fact

`CuratedCandidate.rationale` is model text. It may be shown as "why we picked this," and
it must never be parsed, never override a warning, and never sit where a host reads it as
a venue fact. If it is rendered, it is visually subordinate to the warnings.

### 5.4 Direction of dependency

`Planning/` must not import SwiftUI or know `Deck`/`Candidate` exist. The mapper lives in
the **UI side** of the boundary and depends inward on `Domain/`. Same reasoning as Step
3 §8's DTO split — and the same instruction applies: `StopCategory` and `SlotCategory`
stay separate types with an explicit mapping. Resist the urge to unify them.

### 5.5 Validator untouched

`FeasibilityValidator` gains one line populating `evidence` on the plan it already
builds. No rule changes. If a rendering problem tempts a validator edit, that is the bug.

## 6. New components

| Component | File | Job |
| --- | --- | --- |
| `PlanPresentation` | `Wandr/Curation/PlanPresentation.swift` | pure `(WandrPlan) -> [Deck]`; resolves IDs against `plan.evidence`, attaches warnings |
| `SchedulePresentation` | `Wandr/Schedule/SchedulePresentation.swift` | pure `(ScheduleDraft, WandrPlan) -> ([PlanDay], [ScheduleBlock])` |
| category mapping | in `PlanPresentation` | `SlotCategory <-> StopCategory` |

Both are pure, `Foundation`-only, and take no SwiftUI dependency — so both are fully
testable in the deterministic tier with no model, no network, and no view.

### 6.1 Mapping rules

- Slot order: `plan.slots` order is authoritative; do not re-sort.
- Candidate order: `CuratedCandidate.rank` ascending (1-based).
- A `venueID` with no match in `plan.evidence` is **dropped**, not rendered as a
  placeholder. (It should be unreachable — the curator already resolves against the
  snapshot and `FeasibilityValidator` Rule 1 rejects invented IDs — but the mapper is not
  the place to discover that, and a half-drawn card is worse than an absent one.)
- `Deck.slotName` ← `CurationSlot.title`. `Deck.window` ← the schedule draft's block for
  that slot when one exists, else `""`. **Not** a hardcoded string.
- `warnings` ← `plan.warnings(about: venueID).map(\.message)`, plus
  `plan.warnings(for: slotID)` surfaced at deck level.

## 7. Build sequence

Small commits; run the deterministic tier after each (see `step3-verification-status.md`
for the `DEVELOPER_DIR=` invocation and the `-skip-testing:` flags that keep it to
minutes).

1. **Evidence retention.** `WandrPlan.evidence` + `venue(_:)`; `FeasibilityValidator`
   populates it. All Step 1/2/3 suites green **unmodified** — this is the commit most
   likely to ripple, so it lands alone and first.
2. **Candidate honesty.** The §4.2 shape, `DemoPlan` updated to the new initializer,
   `costRange` ripple fixed. UI still renders `DemoPlan`; nothing live yet. Previews green.
3. **`PlanPresentation` + tests.** Pure mapper, deterministic tier only. No view changes.
4. **`CurationView` injection.** Init parameter, `RootView` passes `harness.readyPlan`.
   **This is the commit after which a live run is visible.** Run the Hauz Khas request by
   hand immediately.
5. **Schedule bridge.** `SchedulePresentation` + `ScheduleView` injection, fed by
   `TravelPlanningService.scheduleDraft(for:)` (already exists — surface it through the
   harness).
6. **Warning surface.** Render `Candidate.warnings` on the card and deck-level warnings on
   the deck header. §5.1's assertion goes green here.

Commits 1–4 are the spine. 5–6 complete it. Nothing here is cuttable the way Step 3's
MapKit commit was — a bridge that renders venues but hides warnings is worse than no
bridge, because it looks finished.

## 8. Test plan

### 8.1 Deterministic tier (no model, any Mac)

- **`PlanPresentation`:** slot/candidate ordering preserved; `VenueCost.unknown` →
  `perHead == nil` (**never** `0` — the `Hauz Khas Fort` fixture legitimately costs ₹0,
  so zero and unknown must not collapse); `OpeningHours.unknown` → `openWindow == nil`;
  `travelNote == nil` always; unresolvable `venueID` dropped; category mapping total
  across all four cases.
- **Warning survival (§5.1):** for a plan carrying every `PlanWarning.Kind`, assert every
  warning's `message` appears in the mapped output. Parameterize over the `Kind` cases so
  a newly added kind fails until it is surfaced.
- **`SchedulePresentation`:** `ScheduleDraftBlock` minutes → `ScheduleBlock` verbatim; day
  bar spans only days the draft covers.
- **Evidence edit:** `WandrPlan` round-trips with and without evidence; a plan built
  without it behaves exactly as before (additivity check, mirroring the one Step 3's
  provenance edit used).
- **All Step 1/2/3 suites unmodified.** Especially `FeasibilityValidatorTests`.

### 8.2 Device-gated tier

Extend `LivePipelineTests`: for the Hauz Khas fixture, assert the mapped `[Deck]` is
non-empty, every rendered candidate's `venueID` is in `plan.evidenceIDs`, and no rendered
`area` falls outside the brief's area — the assertion that would have caught the
"Gurgaon in a Hauz Khas plan" symptom automatically instead of by eye.

### 8.3 Manual

Type the six fixture requests on device. For each, the curation screen must show venues
consistent with the request — the check that was impossible before this step.

## 9. Definition of success

1. Typing "Six of us want dinner and music in Hauz Khas Friday, ₹1,500 each" renders
   **dataset venues from the live run**, not `DemoPlan`.
2. `DemoPlan` appears in `#Preview` blocks and nowhere else in a live code path.
3. Every `PlanWarning` on the plan is visible to the host.
4. No display fact appears that no `GroundedVenue` field supports. `travelNote` is absent,
   not invented.
5. A venue with `VenueCost.unknown` renders honestly and is distinguishable from ₹0.
6. `TravelPlanningService`, `FeasibilityValidator`'s rules, all six service protocols, and
   the two model adapters are unchanged.
7. Deterministic tier green; Step 1/2/3 suites unmodified.
8. `Planning/` imports no SwiftUI.

## 10. Explicitly deferred

`.needsDetails` screen, streaming partials, replan loop, host edits writing back to the
plan, `MKDirections` travel times (which is what unblocks `travelNote`), Siri intent
(Milestone B), squad voting, Live Activity.

## 11. What this unblocks

Once the bridge lands, the dataset question becomes answerable with evidence instead of
argument. Run the six fixtures, look at the decks, and decide:

- If Hauz Khas and Connaught Place produce good decks and only Lodhi nightlife (0 venues)
  and Cyberhub sights (0 venues) come up thin — **grow the dataset**, which `plan.md` §7
  already sanctions as pre-demo polish and which costs no new architecture.
- If coverage is the real ceiling — build `MapKitVenueProvider` + `LayeredVenueProvider`,
  with two constraints now known from the MapKit reference:
  - `MKLocalSearch.Request.region` is a **bias, not a filter**. A radius limit must be
    applied by the provider after results return, or Gurgaon POIs will appear in a Hauz
    Khas search legitimately.
  - `MKLocalSearch` is rate-limited to roughly **1 request/second**, and
    `MapKitVenueEnricher` already spends against that budget geocoding per venue. A POI
    search layered on top compounds it.

  `Candidate.perHead: Int?` (§4.2) is the edit that makes that provider representable, so
  it is worth landing here regardless of which way the decision goes.

Either way, the decision gets made by looking at real output — which is the entire point
of this step.
