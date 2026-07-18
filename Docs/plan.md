# Wandr — Final Master Plan & App Structure

**Build for Eternal · District | iOS 27 | Local-first | Siri-mediated intake | iMessage squad poll**

> *"The group chat plans the night; nobody books it."* Siri summarizes the chat (Wandr never reads it), Wandr researches real Delhi venues on-device, the Host curates, the squad locks it with a poll inside the iMessage thread — ending in a scannable District Pass.

This document is the **single authoritative plan** for the entire app. The three documents in `Docs/` (AI-Orchestration-Flow, AI-Technology-Stack, AI-Integration-Blueprint) remain the architecture reference; where this plan diverges from them, the divergence is listed explicitly in §4 and this plan wins.

---

## 1. Positioning & pitch

**Problem (District by Eternal):** group outings die in the chat. 47 messages, zero bookings. Wandr collapses *discuss → decide → commit* into minutes.

**The two pitch lines:**

1. **Intelligence:** "Every model call runs on-device with Apple's Foundation Models — Dynamic Profiles, tool calling, and the AI is regression-tested with the new iOS 27 Evaluations framework. No server, no API key, nothing leaves the phone."
2. **Privacy:** "Count Wandr's permission prompts: **at most one, and it's optional** (When-In-Use location). No microphone, no contacts, no calendar permission, no chat access — Siri does the listening, EventKitUI does the saving."

---

## 2. Locked decisions (do not relitigate during the build)

| # | Decision | Consequence |
|---|---|---|
| D1 | **Intake is Docs-strict: Siri-mediated summary only.** `PlanOutingFromSiriSummaryIntent` is the single doorway; the host edits extracted constraints via chips. | **Cut:** SpeechAnalyzer/mic, share extension, Vision OCR, SnippetIntent. Recovery = "Ask Siri to send the summary to Wandr again." Stage insurance = invoking the *same intent* from the Shortcuts app with pasted text (same code path, no new surface). |
| D2 | **iMessage squad poll is core** — the one deliberate amendment to the Docs' non-goals. | New `WandrMessages` extension target; vote state rides in `MSMessage.url`; no server. |
| D3 | **Trips UI hidden.** `PlanKind.outing/.trip` stays in the domain; no Trips tab is built. | Outings-only UI; architecture claim survives for the pitch. |
| D4 | **Venue dataset = Delhi NCR**, ~40–60 curated venues, bundled JSON. | Hauz Khas / CP / Cyberhub demo geography lines up with MapKit. |
| D5 | Target app for the hackathon story = **District**; demo device = Apple-Intelligence iPhone on iOS 27 beta; second physical iPhone for the poll demo. | Preflight everything on those exact devices. |

---

## 3. Judging-criteria scorecard

| Feature in build | Framework / API | Cycle | Why it scores |
|---|---|---|---|
| Brief extraction, grounded research, streamed synthesis | **Foundation Models**: `@Generable` + `@Guide`, `LanguageModelSession.DynamicProfile` (OS27), `Tool` calling, 8K context (`SystemLanguageModel().contextSize`), streamed `PartiallyGenerated` | iOS 26 → 27 | Core iOS 27 AI story |
| Optional heavy synthesis | `PrivateCloudComputeLanguageModel`, capability-gated, always falls back locally | iOS 27 | iOS 27 bonus |
| Siri → app handoff | **App Intents** `@AppIntent` macro form + App Shortcuts phrases | WWDC 26 macros | WWDC 26 bonus |
| Venue/route/weather evidence | **MapKit** (`MKLocalSearch`, `MKDirections`), **WeatherKit** (with attribution) | current | Real data, zero hallucination |
| Squad poll in the thread | **Messages framework**: `MSMessage` + `MSSession` (+ `MSMessageLiveLayout` if time allows) | stable | UX wow; the demo climax |
| District Pass QR | **CoreImage** `CIQRCodeGenerator`; PassKit Wallet pass = stretch | current | Delight |
| Planning progress on lock screen | **Live Activity** (local-only, no push) | current | Polish |
| Design language | **SwiftUI + Liquid Glass** | WWDC 25/26 | WWDC 26 design |
| AI quality regression tests | **Evaluations framework** + Swift Testing | iOS 27 | Sleeper bonus — almost no team will have this; *say it out loud in the pitch* |
| Storage | **SwiftData**, local-only | current | Privacy story |

*Removed vs. the interim plan (deliberate, per D1): SpeechAnalyzer, Vision OCR, SnippetIntent. The trade buys the "at most one permission prompt" pitch line — state it honestly if a judge asks.*

---

## 4. Architecture — Docs spine + four amendments

Everything below is exactly per `Docs/` unless listed as an amendment.

### 4.1 The spine (unchanged from Docs)

- **State machine** (`PlanningRun`, single source of truth, only the coordinator transitions it):
  `awaitingSiriSummary → hostReview → extracting → needsDetails → researching → validating → curating → approving → executing → completed / failed / cancelled`
  Full transition table and host-visible behavior per `Docs/AI-Orchestration-Flow.md`.
- **One coordinator** — `TravelPlanningService` (actor) — owning short-lived `LanguageModelSession`s. Phase isolation via one `LanguageModelSession.DynamicProfile` that switches on run state:
  - **Intake:** sees the volatile Siri summary; constrained extraction; **no tools**.
  - **Research:** sees only the confirmed `OutingBrief` + opt-in preferences; **read-only tools**; evidence collection required before any venue-specific synthesis.
  - **Synthesis:** sees immutable evidence snapshots + validator output; **no live tools**; streams three candidates.
  - **Approval:** produces typed `ActionProposal`s; **no tools**.
- **Deterministic guards:** `FeasibilityValidator` (pure Swift, no model/network) decides feasibility; the model can never erase a warning or upgrade an unknown to a fact. `ActionExecutor` presents only host-tapped proposals in the foreground.
- **Privacy/retention:** raw Siri `AttributedString` is shown only on Host Review, discarded on confirm/cancel, never persisted. Audit record = metadata only (`source = siriMediatedSummary`, timestamp, outcome). SwiftData stores structured briefs, revisions, evidence metadata, approvals, opt-in preferences. No accounts, cloud, analytics, external LLMs.
- **Fallbacks:** every unavailability state (FM assets, guardrail refusal, PCC, location, weather, tool failure, empty summary) has a specified host-visible state per the Docs — none of them dead-end the UI.

### 4.2 The four amendments (this plan wins over Docs)

| # | Amendment | Detail |
|---|---|---|
| A1 | **Messages extension promoted from non-goal to core** | `WandrMessages` iMessage app extension carries the squad poll and District Pass. Privacy model: participants are pseudonymous `MSConversation.localParticipantIdentifier` UUIDs (per-device, conversation-local); all state lives in the `MSMessage.url` payload; no server, no contacts, no identity. The Host must tap send — Apple's rule, framed as "the Host stays in control," which matches the Docs' approval philosophy. |
| A2 | **Trips UI deferred** | `PlanKind` stays in the domain; no Trips tab in v1. |
| A3 | **District venue dataset + `SearchDistrictVenuesTool`** | Bundled `district-venues-delhi.json` joins the read-only tool catalog. MapKit stays the tool for real geography (coordinates, routes); the dataset supplies District-style commerce metadata (cover charge, offers, perks) MapKit can't. All evidence rules apply: timestamps, IDs, no model-invented venues. |
| A4 | **"Paisa Vasool" metrics** | Per-stop offer, effective per-head cost, and savings vs. list price — computed **deterministically** from dataset fields, never by the model. |

New `ActionProposal` kind: `sendSquadPoll` — it only **stages** the approved-plan snapshot into the App Group container; the actual `MSMessage` insertion happens inside the extension with an explicit user tap (the executor cannot and does not send anything).

---

## 5. Target & file structure

```
Wandr.xcodeproj  (IPHONEOS_DEPLOYMENT_TARGET = 27.0)
├── Wandr (app target)
│   ├── App/            WandrApp.swift, RootView (Outings-only)
│   ├── Intake/         AwaitSiriSummaryView, HostReviewView, ConstraintChipsView
│   ├── Planning/       PlanningTimelineView, EvidenceCardView, CandidateGalleryView (3 plans)
│   ├── Approval/       ApprovalView, ProposalListView, SendToSquadView
│   └── Intents/        PlanOutingFromSiriSummaryIntent, WandrShortcuts (AppShortcutsProvider)
│
├── WandrKit (framework — shared by app + extension)
│   ├── Domain/         PlanKind, OutingBrief, TravelConstraints, GroundedOption, WandrPlan,
│   │                   PlanRevision, PlanningRun, ActionProposal, PlanningEvent,
│   │                   DistrictVenue, SquadPoll, DistrictPass
│   ├── Services/       TravelPlanningService (actor), TravelDataProvider, PreferenceStore,
│   │                   FeasibilityValidator, ActionExecutor, PlanningRunStore (SwiftData)
│   ├── FM/             WandrDynamicProfile, @Generable DTOs, availability gating, PCC escalation
│   ├── Tools/          ResolveOriginTool, SearchPlacesTool, SearchDistrictVenuesTool,
│   │                   EstimateRouteTool, GetForecastTool, LoadPreferencesTool, ValidateItineraryTool
│   ├── Poll/           SquadPollCodec (URL query-item payload), LockRule, PassRenderer (QR)
│   └── Resources/      district-venues-delhi.json (~40–60 venues)
│
├── WandrMessages (iMessage app extension)
│   └── MSMessagesAppViewController hosting SwiftUI:
│       DropPlanView (expanded: pending plan → insert MSMessage),
│       VoteView (compact: Approve / Veto), PassView (locked → QR pass),
│       template-layout fallback for non-app recipients
│
└── WandrTests          Swift Testing + Evaluations
                        (3 golden Siri-summary fixtures + 2 adversarial)

App Group: group.com.wandr.shared
  → carries the approved-plan JSON snapshot only. The live SwiftData store stays in the
    app container; the extension reads the snapshot — no cross-process store sharing.
```

Domain naming follows the Docs everywhere: `OutingBrief`, `TravelConstraints`, `GroundedOption`, `WandrPlan`, `PlanRevision`, `PlanningRun`, `ActionProposal`, `PlanningEvent`, plus the three new types `DistrictVenue`, `SquadPoll`, `DistrictPass`.

---

## 6. Feature specifications

### 6.1 Intake — `PlanOutingFromSiriSummaryIntent`

- `@AppIntent` macro form; foreground (`supportedModes`), authenticated; one `AttributedString` parameter named `summary`.
- `AppShortcutsProvider` phrases: "Plan this group outing in Wandr", "Use Wandr to plan this outing", "Wandr, plan our after-work plans."
- On receipt: render the summary **only** on Host Review; extract constrained fields only after explicit confirmation; then delete the raw `AttributedString` from memory. Never persisted.
- Empty / whitespace / unsupported / unavailable → recovery state: **"Ask Siri to send the summary to Wandr again."** No mock chat, no transcript import, no messaging-API fallback.
- **Rehearsal fallback (same code path):** a Shortcuts-app shortcut that runs this intent with pasted summary text. Build it during Milestone B and keep it on the demo device.

### 6.2 Foundation Models

- Gate every session on `SystemLanguageModel.default.availability` with a distinct UI state per `.unavailable` case.
- `@Generable` + `@Guide` for every model boundary (`OutingBrief` extraction, `WandrPlan` synthesis) — vocabulary, required fields, option counts constrained; no manual JSON.
- One `WandrDynamicProfile` (`LanguageModelSession.DynamicProfile`, OS27) switching instructions/tools per phase via `@SessionProperty`-driven state; transcript preserved across branch transitions where the Docs allow, redacted where they require (raw summary never enters research/synthesis context).
- Streaming: candidate plans stream as `PartiallyGenerated`, labeled *provisional* until the completed typed plan passes `FeasibilityValidator`.
- Budget: check `tokenCount(for:)` on instructions; keep tool descriptions concise (context is 8K on iOS 27).
- PCC (`PrivateCloudComputeLanguageModel`): only for host-approved, unusually complex synthesis, only after capability/quota/network checks; any failure returns to the system model. Never blocks editing; never a third-party LLM.

### 6.3 Tool catalog (all read-only)

Per Docs: `ResolveOriginTool`, `SearchPlacesTool`, `EstimateRouteTool`, `GetForecastTool`, `LoadPreferencesTool`, `ValidateItineraryTool` — plus:

- **`SearchDistrictVenuesTool`** — inputs: area, category, vibe tags, budget ceiling, party size; output: bounded `DistrictVenue` results (id, name, coordinates, cover charge, offer text + window, cuisine, music genre, timing, perks) with source = `bundledDataset(version:)` and retrieval timestamp. No availability/booking claims.

Tool errors become typed `PlanningEvent` limitations shown in the timeline and in the plan — the model may not paper over them with background knowledge.

### 6.4 Validator outing rules (deterministic, added to Docs rules)

- cover charge + food estimate ≤ budget/head (unknown prices stay **unknown**, never guessed);
- venue timing windows vs. the plan's stop sequence (e.g., "1+1 till 10 PM" flagged if arrival is 10:30);
- travel legs within mode/distance/buffer constraints; walkability between stops;
- dietary/accessibility flags honored; repeated stops and impossible ordering rejected;
- indoor fallback required when weather is unverified or bad.

### 6.5 Squad poll (WandrMessages)

**Flow:** Host approves → taps **Send to Squad** (`sendSquadPoll` proposal stages the App Group snapshot) → opens the Wandr iMessage app in Messages → DropPlanView shows the pending plan → Host taps to insert the `MSMessage` (template layout + payload) and **taps send** → participants tap the bubble → compact VoteView → Approve/Veto → extension composes the `MSSession`-updated message (old bubble collapses, tally advances) → at threshold, next render is the locked state.

**Payload — versioned URL query items (the entire poll state, no backend):**

```
v=1&plan=<uuid>&venue=<datasetID>&t=<epochStart>&size=6&cost=1200
&votes=<pid1>:y,<pid2>:y,<pid3>:v&state=open|locked
```

- `SquadPollCodec` in WandrKit encodes/decodes and is the single schema owner (unit-tested both directions).
- Participant identity = `MSConversation.localParticipantIdentifier` (per-device UUID) → honest vote dedupe, zero accounts.
- `LockRule` (pure function): `approvals == size` (N-of-N default; threshold constant in one place). Evaluated at render time in the extension; votes arriving after lock are ignored and the UI says so.
- Payload stays small: venue detail resolves from the bundled dataset by ID.
- Non-app recipients see the `MSMessageTemplateLayout` fallback (image + text summary).
- Known limits, stated honestly if asked: payload is client-trusted; tally advances when a vote is *sent*, not push-live.

### 6.6 District Pass

- On `state=locked`, the bubble renders the **District Pass**: QR (CoreImage `CIQRCodeGenerator` encoding plan+venue IDs), venue, time, party size; animated morph — this is the applause moment. Tap → full-screen pass in the extension.
- Stretch: PassKit Wallet pass generated from the same `DistrictPass` model.

### 6.7 Native handoffs (ActionExecutor)

`calendarDraft` (EventKitUI `EKEventEditViewController` — zero calendar permission), `openRoute` (Maps), `openBookingURL` / `openPhoneLink` (visible, host-tapped, never auto-completed), `sharePlan` (`ShareLink`/`Transferable`), `sendSquadPoll` (stage snapshot only). Executor verifies proposal ∈ approved revision + explicit tap + URL/phone policy, and records presented/cancelled/failed — never "booked."

### 6.8 Ancillary

- **WeatherKit:** minimum forecast fields; required attribution UI; missing entitlement/network → visible "weather unverified" + indoor option.
- **Core Location:** optional; request When-In-Use only after the host taps "Use my location"; manual area entry always equal.
- **Live Activity:** local-only planning progress (researching → validating → curating); no push.
- **Liquid Glass:** design pass across brief chips, timeline, candidate gallery, pass.

---

## 7. Build order — milestones with hard cut lines

Ordered so the demo is never broken: each milestone ends demoable. If behind, cut from the bottom of the current milestone, never the top of the next.

### Milestone A — Planning core (the biggest)
1. WandrKit + domain models + SwiftData persistence; App Group container wired.
2. `PlanOutingFromSiriSummaryIntent` + AwaitSiriSummary/HostReview/chips screens; raw-summary volatility enforced.
3. `PlanningRun` state machine in `TravelPlanningService` + visible `PlanningEvent` timeline.
4. Tools: `SearchDistrictVenuesTool` (bundled JSON) + MapKit search/routes; `FeasibilityValidator` with outing rules.
5. FM: `WandrDynamicProfile` intake + synthesis; all availability states; streamed candidates.
6. Curation gallery (3 candidates, evidence cards, Paisa Vasool badges) + approval + handoffs (EventKitUI, Maps, ShareLink).
   - **Cut line A:** WeatherKit and the edit→replan loop go first; extraction → research → validate → curate → approve → handoff is untouchable.

### Milestone B — Siri handoff hardening (small but critical)
1. `AppShortcutsProvider` phrases; recovery states polished.
2. **Preflight the real Siri→intent summary handoff on the exact demo device + messaging app.** This is the doorway and the #1 risk — do it the first day of B, not the last.
3. Build + rehearse the Shortcuts-app fallback shortcut (same intent, pasted text).
   - **Cut line B:** nothing. All three items are mandatory.

### Milestone C — Squad poll (the climax)
1. WandrMessages target; DropPlanView reads the App Group snapshot; insert `MSMessage` (template layout + payload).
2. Vote flow: compact VoteView → `MSSession` update; tally + dedupe via participant ID; `SquadPollCodec` round-trip tests.
3. Threshold lock + **District Pass morph** (QR) — **not cuttable**; it's the applause moment.
4. `MSMessageLiveLayout` in-transcript tally.
   - **Cut line C:** live layout first (template re-sends still demo perfectly).

### Milestone D — Judge polish
1. Liquid Glass pass; app icon; empty/error states.
2. Local-only Live Activity.
3. Evaluations suite (see §9) — then *mention it in the pitch*.
4. Demo rehearsal: two physical devices, second Apple ID in the thread, venues preflighted, timings drilled.
   - **Cut line D:** everything except rehearsal.

### Stretch (only if all above is green)
PassKit Wallet pass · PCC synthesis for complex briefs · Visual Intelligence `IntentValueQuery`.

---

## 8. Demo script (5 minutes)

1. **Hook (30s):** a real chaotic group chat on screen. "This is how nights out die. Watch."
2. **The Siri boundary (60s):** ask Siri to summarize the chat, then "plan this outing in Wandr." Wandr opens on Host Review. Point at it: **"Only the summary crossed. Wandr has no chat access, no mic, no contacts — this screen is the entire boundary."** Confirm; edit one chip.
3. **Watch it think (45s):** event timeline — District venues searched, routes estimated, budget validated. "No hallucinated venues. A deterministic validator, not the model, decides feasibility."
4. **Curate (30s):** three candidates; pick one; show the 1+1 offer and per-head Paisa Vasool math.
5. **Send to Squad (60s):** approve → Messages → drop the poll bubble → send. Second device votes Approve. Tally advances.
6. **The lock (30s):** final vote lands → bubble morphs into the District Pass with QR. "The plan the group chat could never finish — locked, ticketed, in the thread."
7. **Criteria close (30s):** "On-device Foundation Models with iOS 27 Dynamic Profiles and tool calling, App Intents, and the AI is regression-tested with Apple's new Evaluations framework. One optional permission prompt. Nothing leaves the phone."

---

## 9. Test & Evaluations strategy

- **Deterministic (Swift Testing):** intent `AttributedString` input; empty/whitespace recovery; host-confirmation gating; raw-summary non-persistence; extraction → constraints; validator rules (budget, timing windows, ordering); `SquadPollCodec` round-trip + `LockRule` (open→locked, post-lock vote ignored, dedupe); pass payload; share output.
- **Evaluations framework (iOS 27):** three golden Siri-summary fixtures (after-office party, birthday outing, full-day outing — per Docs) + two adversarial (summary containing injected instructions → must be treated as content; request to invent availability → must surface unknown). Assert expected research-tool trajectories, required evidence IDs, feasibility warnings preserved, unavailable-model paths, PCC failure fallback, approval gating. Evaluation subjects call the shipped coordinator through deterministic providers — no duplicated prompts in tests.

---

## 10. Risk register

| Risk | Mitigation |
|---|---|
| **Siri→intent summary handoff unavailable/unreliable on stage — #1 risk now that it's the sole intake** | Preflight on the exact device + messaging app on day one of Milestone B; Shortcuts-app fallback invoking the same intent with pasted text; keep one recorded run as insurance |
| FM asset unavailability / guardrail refusal mid-demo | Docs' fallback states keep the UI alive; preflight the morning of; scripted briefs tested in advance |
| iMessage extension debugging is famously fiddly | Start C early; two physical devices (not simulator); template layout works even if live layout misbehaves |
| Payload exceeds practical URL limits | Payload carries IDs + votes only; venue detail lives in the bundled dataset |
| Hinglish summaries confuse the on-device model | Test fixtures early in A; if weak, script demo chats in English and note locale support honestly |
| Two-device logistics | Second iPhone, second Apple ID in the group thread; rehearse the vote sequence twice |

---

## 11. Non-goals

Unchanged from the Docs, except amendment A1 (the poll):

- No payments, UPI, or bill splitting; no autonomous bookings or claimed reservations; no automatic calls or messages.
- No server, accounts, CloudKit, analytics, embeddings, external LLMs, or custom FM adapters.
- No chat reading (iMessage, WhatsApp, or otherwise), no contacts, no participant identity beyond pseudonymous conversation-local UUIDs, no microphone.
- No push-updating bubbles; no background execution.
- Every commitment is a user tap: **the AI proposes, the Host curates, the squad disposes.**
