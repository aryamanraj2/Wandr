<div align="center">

<img src="Wandr/Assets.xcassets/AppIcon.appiconset/wandrIcon.jpg" width="120" alt="Wandr App Icon">

# Wandr

**Turn a group chat into a plan, on-device.**

[![Platform](https://img.shields.io/badge/Platform-iOS%2027%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-6.0-0076FF?style=flat-square&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Tests](https://img.shields.io/badge/Tests-369%20passing-2F6A62?style=flat-square)](WandrTests)

</div>

---

## The Story Behind Wandr

Planning an outing is a group problem that dies in a group chat. Someone throws out a neighbourhood, someone else names a budget, a third person says "surprise me" — and twenty messages later nobody has actually decided anything.

Wandr starts from the chat instead of fighting it. Ask Siri to summarize the conversation and hand it to Wandr — or just speak or type the gist yourself — and Wandr turns it into a real, groundable plan: three or four stops, timed and sequenced, inside the group's budget and neighbourhood. The host reviews everything before it's used, the squad votes on the parts that are still open, and the result is a shareable schedule instead of a scroll of unread messages.

Everything runs on-device with Apple's Foundation Models. No server, no API keys, no chat ever leaves the phone.

---

## What Wandr Does

### Two ways in, one trust boundary

**Siri path** — the host runs a Wandr-authored Shortcut (or just asks Siri conversationally) to summarize an eligible WhatsApp/iMessage conversation. The summarization model call happens inside Shortcuts, on Apple's infrastructure — Wandr's own code never touches the chat. The resulting summary lands on `PlanOutingFromSiriSummaryIntent` as plain text.

**Direct path** — the host types or dictates the gist straight into the app. An on-device Foundation Models call (`FreeTextSummaryExtractor`) turns free text into the same structured summary the Shortcut would have produced.

Both converge on one type, `ChatSummaryPayload`, and both land on **Host Review** before anything else happens — every field the model claims the host said is shown back for confirmation before a single venue is fetched. Nothing is trusted implicitly, including the model's own extraction.

### A planning pipeline that never dead-ends

Once confirmed, `TravelPlanningService` runs a fixed seven-stage pipeline — extract, normalize, research, resolve, curate, validate, schedule — with a strict, no-self-transition state machine. The two ideas that hold it together:

- **Constraints have degrees, not a binary.** When a request can't be fully met, Wandr gives up the least important constraint first (setting → budget → time window → requested stops — dietary and accessibility are never touched) and *says so* on the plan, instead of just failing the run.
- **The model ranks; deterministic Swift owns every contract.** `FoundationModelsCurator` is the only file allowed to `import FoundationModels` in the planning core, and it never sees the host's raw words — only a numbered candidate list and a typed brief, framed as data. Every venue name, price, and availability claim is resolved and validated by plain Swift.

### Curate, poll, and schedule as a group

- **`CurationView`** — swipeable decks of grounded candidates per stop.
- **`SquadPollView`** — the group votes on whichever stops the host left open.
- **`ScheduleView`** — an editable, timed itinerary built from the winning picks, ready to share.

---

## Built Entirely with Apple Frameworks

Wandr has no third-party dependencies. Every feature is implemented using the iOS SDK directly.

| Framework | Used For |
|---|---|
| **SwiftUI** | All views, animations, and navigation |
| **FoundationModels** | On-device brief extraction and itinerary curation |
| **AppIntents** | The Siri handoff (`PlanOutingFromSiriSummaryIntent`, App Shortcuts) |
| **Speech / AVFoundation** | Dictation in the direct-capture path |
| **NaturalLanguage** | On-device text signal extraction (budget/area/time cues) |
| **Observation** | `@Observable` state across the intake and planning coordinators |
| **OSLog** | Structured, privacy-split diagnostics (`com.wandr.ai`) |

---

## Technical Highlights

**Swift 6 strict concurrency** — the app targets Swift 6 throughout; model sessions and the planning coordinator are actor-isolated so the UI thread stays free.

**Zero cloud dependency** — no backend, no accounts, no chat content ever persisted. Wandr discards the raw Siri summary on confirmation or cancellation and keeps only the structured, normalized result.

**The constraint ladder** — `ConstraintLadder` + `EvidenceResolver` turn a would-be dead end ("nothing fits ₹2000 for 2 people") into a disclosed compromise ("nothing here fits ₹2000 — these are the closest we found"), ranked by provenance and importance rather than a hardcoded order.

**Provenance on every value** — every inferable field carries a `ValueSource` (`.host` / `.modelSuggestion` / `.safeDefault`). Host Review shows exactly what was extracted versus assumed; relaxations are disclosed; warnings ride on the plan and the model cannot remove them.

**A slot identity bug class, closed for good** — stops are identified by `SlotBand` (lunch/afternoon/somethingNew/dinner/late), never by category, after two real incidents where two food stops collided under a shared `.food` key (poll ballots merging, decks colliding on the same venue). `SlotDeckBuilder` now reserves venues per later stop so this can't recur.

**Design system, not ad-hoc styling** — `WandrTheme.swift` centralizes the palette (charcoal / indigo / cyan / cream), type ramp, and a named motion vocabulary (`wandrLift`, `wandrSettle`, `wandrMorph`, …) so every screen moves with the same physical logic.

---

## Getting Started

Requires **Xcode 27 beta** and an iOS 27 simulator or device (Apple Intelligence is required for the model paths and is unavailable in the Simulator — see [`HANDOVER.md`](HANDOVER.md) §12 for what that does and doesn't let you verify).

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild build -scheme Wandr -destination 'id=<simulator-udid>'
xcodebuild test  -scheme Wandr -destination 'id=<simulator-udid>'
```

> `xcodebuild` is the only source of truth in this project — SourceKit indexes against CommandLineTools and reports hundreds of false errors against the Xcode 27 beta toolchain. Don't act on editor diagnostics; if `xcodebuild` succeeds, the code is fine.

---

## Testing

**369 tests, 0 failing.** Swift Testing throughout (`@Test`, `@Suite`, `#expect`, `#require`, parameterised `arguments:`).

The centerpiece is `PlanShapeEvaluationTests` — a golden set of 15 realistic host phrasings scored as a set rather than case by case, because every previous point fix had a habit of passing its own test while breaking something two files away. Every failure mode found along the way (a duration read as a clock time, an area silently widening to the whole city, a model echoing a sample value it was only ever shown as an example) is documented with its root cause in [`HANDOVER.md`](HANDOVER.md) §6.

---

## Project Structure

```
Wandr
├── App/            — Root shell, debug entry points
├── Capture/         — Speak-or-type intake (PlanOrb, dictation)
├── Intake/          — Siri handoff, host review, recovery, onboarding
├── Intents/         — PlanOutingFromSiriSummaryIntent, App Shortcuts
├── Domain/          — ChatSummaryPayload, intake state machine
├── Planning/
│   ├── AI/          — Extractors and curators (the only FoundationModels imports)
│   ├── Domain/       — OutingBrief, ConstraintLadder, SlotSchedule, WandrPlan
│   ├── Services/     — Normalizer, EvidenceResolver, FeasibilityValidator, ScheduleDrafter
│   └── Data/         — DistrictVenueProvider (the live-API seam)
├── Curation/         — Swipeable candidate decks
├── Poll/             — Squad voting
├── Schedule/         — Editable timeline
├── DesignSystem/     — WandrTheme — palette, type ramp, motion vocabulary
└── Docs/, HANDOVER.md — Architecture notes, bug history, pending work
```

---

<div align="center">

Designed and built by **Aryaman Jaiswal**

*Planning a night out shouldn't be a second job.*

</div>
