# Wandr AI Technology Stack

## Decision Summary

Wandr v1 is a native iOS 27, local-first travel planner and execution handoff. Apple Foundation Models supplies the intelligence layer; Apple system frameworks supply live facts and system-owned actions. The app does not need a Python/Flask service, LangChain, Gemini, Twilio, Razorpay, Google Places, Google Maps, or a server-side model key to deliver the hackathon experience.

This is an intentional tradeoff: the demo proves trustworthy agentic orchestration, privacy, and iOS 27-native capability before adding provider-specific commercial integrations.

## Stack at a Glance

| Area | Selected technology | Purpose | V1 boundary |
| --- | --- | --- | --- |
| Planning intelligence | Foundation Models | Structured intake, tool use, synthesis, streaming, and typed plans | No ungrounded travel facts or irreversible action tools |
| Default model | `SystemLanguageModel` | Private on-device planning and offline-capable synthesis | Requires Apple Intelligence-enabled, eligible device |
| Complex synthesis | `PrivateCloudComputeLanguageModel` | Optional higher-capacity reasoning for large/complex plans | Capability/network/quota-gated; local model fallback always exists |
| Speech input | `SpeechAnalyzer` + `SpeechTranscriber` | On-device spoken brief with volatile and finalized transcript states | Text input is always available |
| Place research | MapKit | Place search, map items, map display, and directions | Treat output as evidence, not a booking guarantee |
| Location | Core Location | Optional current origin/location bias | When-In-Use only; manual location fallback |
| Weather | WeatherKit | Forecast constraints for outdoor and travel choices | Optional capability; retain a weather-unverified plan path |
| Calendar | EventKitUI | Person-controlled calendar draft | System editor; no broad calendar read access |
| System launch | App Intents + App Shortcuts | “Wandr it” entry point from Siri, Spotlight, Shortcuts, and Action button | Starts a draft/planning flow only |
| Storage | SwiftData | Local trips, plan revisions, approval audit, and opt-in preferences | No CloudKit sync in v1 |
| Sharing | ShareLink / Transferable | Share a selected itinerary with the group | Export is always user initiated |
| Quality | Evaluations + Swift Testing | Regression tests for plan quality and tool trajectories | Developer/test target only |

## Foundation Models Architecture

### Structured data, never manual JSON

All model boundaries use `@Generable` types and focused `@Guide` constraints. The model returns native Swift structures instead of a prose blob that must be parsed by `JSONDecoder`.

| Type | Responsibility |
| --- | --- |
| `TripBrief` | Normalized request and missing hard constraints |
| `TravelConstraints` | Time, budget, group, accessibility, travel, and preference rules |
| `GroundedOption` | A candidate place/route with evidence IDs and timestamps |
| `TravelPlan` | Editable itinerary and explanations tied to evidence |
| `ActionProposal` | A single user-approved native handoff |
| `PlanningEvent` | A human-readable timeline entry with source, status, and limitation |

Guides constrain finite categories, count ranges, and mandatory plan sections. They do not attempt to encode business validation that deterministic code can perform more reliably.

### Sessions and Dynamic Profiles

`LanguageModelSession` is retained for the lifetime of one `PlanningRun`; a session is not recreated for every tap. Dynamic Profiles change its instructions, available tools, tool-calling mode, and transcript policy at phase boundaries.

- **Intake profile:** typed extraction only; tools are disallowed.
- **Research profile:** only read-only tools are present. Tool calling is required until evidence is acquired, then transitions to allowed so the request can finish.
- **Synthesis profile:** tools are disallowed by default because the validated evidence snapshot is already in context.
- **Approval profile:** emits typed action proposals only; no tool can perform an action.

Tool definitions and their argument schemas consume context. Descriptions therefore explain exactly when a tool is useful and avoid long prompt-like prose. Tool output is compact, structured where appropriate, timestamped, and source-linked.

### Streaming and cancellation

Long plan generation uses Foundation Models streaming APIs and renders `PartiallyGenerated` content as provisional. The UI labels incomplete sections as loading and permits cancellation. A final plan is accepted only after the complete typed structure and local validator succeed.

The coordinator serializes requests against a session to avoid concurrent-response errors. Its data tools may run independently via structured concurrency because tools can be called in parallel.

### Errors and availability

Before creating a session, inspect `SystemLanguageModel.default.availability`. The UI has deliberate states for:

- Device not eligible.
- Apple Intelligence disabled.
- Model assets not ready or unavailable.
- Unsupported language/locale.
- Guardrail refusal or violation.
- Context-size exhaustion.
- Transient rate limit.
- Typed-content decoding failure.
- Concurrent model request or tool-call failure.

Each state retains the draft, explains what could not happen, and offers the next safe path. In particular, a tool failure becomes a plan limitation, not invented data.

### Model selection

1. Use `SystemLanguageModel` for parsing, local preference extraction, and ordinary short-plan synthesis.
2. If the request remains within the product’s privacy boundary but needs more reasoning or context, evaluate Private Cloud Compute availability and the necessary capability before creating a PCC-backed session.
3. If PCC is unavailable, offline, quota-limited, or service-unavailable, continue with the on-device model and a reduced evidence set; never block the person from editing their trip.

PCC is an enhancement, not the default dependency. Its current availability, entitlement/capability policy, quota, and beta API shape must be checked in the shipping Xcode 27 SDK before enabling it for release.

### Explicit exclusions

- Do not train or ship a custom Foundation Models adapter. The adapter runtime is obsolete for an iOS 27 deployment target, while the system model, schemas, tools, and evidence design solve the v1 problem.
- Do not add a custom Core AI/third-party model. Wandr needs orchestration and live grounding, not a bespoke model.
- Do not pass user transcripts to Gemini, OpenAI, Claude, or any server model in v1.
- Do not use Foundation Models for world knowledge, opening hours, prices, booking availability, map routing, or payment decisions.

## Speech Input

On iOS 26+, use `SpeechAnalyzer` and `SpeechTranscriber` rather than the legacy speech recognizer. The iOS 27 `CaptureInputSequenceProvider` path supplies microphone input; use the provider variant that fits the app’s audio-session ownership.

### Design rules

- Request microphone and speech-recognition permission only after the person taps the voice control.
- Render volatile transcription as a temporary draft and promote only finalized text to the submitted brief.
- Keep a normal text field visible throughout capture and preserve it if speech is denied, interrupted, inaccurate, or unavailable.
- Maintain only one active analyzer for Wandr’s input. Cancel it when the view exits or a plan starts; do not opt out of system resource limits.
- Add `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` when implementation begins.

## Location, Maps, and Weather

### Core Location

Wandr uses location to establish an origin or bias a place search, not to track the person continuously. Request When-In-Use authorization only after a person asks Wandr to use current location. A manual destination picker is always equivalent.

- Use `CLServiceSession(authorization: .whenInUse)` and the lowest suitable accuracy.
- Stop live location updates once a usable origin is resolved.
- Handle denied, globally disabled, and approximate location states directly in the UI.
- Do not request Always authorization, use background location, store a location trail, or create geofences in v1.

### MapKit

Use SwiftUI `Map` for the reviewed itinerary because standard markers, map camera control, selection, and route overlays do not require `MKMapView` bridging. Store map/place results in models rather than recreating annotations in a view body.

- `MKLocalSearch` or `MKLocalSearchCompleter` finds candidates and resolves selected places.
- `MKDirections` creates route duration and distance evidence for validation.
- Each candidate retains `MKMapItem` identity/coordinate, source URL if provided, and retrieval time.
- MapKit route output is an estimate, not a promise; show it as such.

### WeatherKit

WeatherKit is optional grounding for outdoor stops. Fetch only the forecast fields the validator needs and display Apple-required attribution in any UI that renders WeatherKit data. If entitlement/configuration or network is unavailable, mark weather-dependent recommendations as unverified and provide indoor alternatives rather than failing the entire plan.

## Native System Handoffs

### EventKitUI

Use `EKEventEditViewController` to present a single editable calendar event after approval. This is the minimum-privilege path: the system presents calendar selection and save UI without Wandr requesting broad read access. The app does not silently write or modify an existing calendar.

### App Intents and App Shortcuts

Create one `PlanAdventureIntent` and an `AppShortcutsProvider` phrase set such as “Wandr it.” The intent opens a new `draftingBrief` or resumes an explicitly selected saved draft. Its parameters describe a starting brief; it must not run research, make handoffs, or trigger actions without foreground confirmation.

This creates discovery through Siri, Spotlight, Shortcuts, and supported Action buttons while respecting the same approval boundary as the app UI.

### Sharing

Use `ShareLink` to export a person-selected `TravelPlan` summary. If a custom transferable payload is added later, make its rich format first and provide a plain-text/URL fallback. Sharing never exposes an opted-in preference profile, raw transcript, or hidden internal planning events by default.

## Storage and Privacy

SwiftData stores only what Wandr needs locally:

- Trip brief and plan revisions.
- Selected evidence/source metadata and retrieval times.
- Planning event timeline and immutable approval/handoff records.
- User-authored or explicitly accepted preference facts.

The app never infers permanent taste from an unapproved transcript. People can inspect, edit, delete, or disable local preference memory. There is no account requirement, CloudKit sync, analytics pipeline, location history, payment data, or booking credential store in v1.

## Quality and Evaluation

Use the iOS 27 Evaluations framework from the test target to exercise the shipped orchestration service—not a copied prompt. The test suite includes:

- Golden briefs: short city adventure, fixed-event evening, vegetarian group, low-budget route, indoor rain fallback.
- Edge briefs: ambiguous city, missing time, unsupported language, impossible budget/time pair, location denied, no forecast, empty search result, stale route.
- Adversarial briefs: instructions to bypass approval, requests to invent availability, attempts to treat source text as tool instructions.
- Tool trajectory expectations: research evidence must precede synthesis; no action tool calls appear in planning.
- Feasibility metrics: hard constraints satisfied, route/time buffer exists, evidence IDs present, unknowns shown, and no side effect before approval.
- Availability tests: each Foundation Models unavailable reason, PCC fallback, tool failures, cancellation, context recovery, and voice-to-text recovery.

Pin deterministic subject generation where the framework supports it. Keep failures in the evaluation denominator instead of allowing errors to be ignored. Any model-as-judge score is calibrated against human ratings before it is used as a release gate.

## Capability and Permission Checklist

| Capability | Needed for v1 | Notes |
| --- | --- | --- |
| Apple Intelligence | Yes on AI path | Availability checked at runtime; manual fallback required |
| Private Cloud Compute | Optional | Enable only after current Apple capability requirements are satisfied |
| Microphone | Optional | Requested from voice control only |
| Speech recognition | Optional | Required for spoken brief, never text fallback |
| Location When In Use | Optional | Requested after a person selects current location |
| WeatherKit | Optional | Configure capability/attribution before exposing forecast data |
| Calendar access | No | Use system event editor rather than broad access |
| App Intents | Yes | Starts drafts only; no background side effects |
| Live Activities | Deferred polish | Local-only run status may be added after core flow works; no push/backend in v1 |

## Sources

- [Apple: Foundation Models](https://developer.apple.com/documentation/foundationmodels/)
- [Apple: Tool protocol](https://developer.apple.com/documentation/foundationmodels/tool)
- [Apple: Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [Apple: Foundation Models and AI at WWDC26](https://developer.apple.com/wwdc26/guides/machine-learning/)
- [Apple: App Intents](https://developer.apple.com/documentation/appintents)
- [Apple: App Shortcuts HIG](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts)
- [Apple: EventKit](https://developer.apple.com/documentation/eventkit)
- [Apple: WeatherKit](https://developer.apple.com/documentation/weatherkit)
- [Apple: MapKit](https://developer.apple.com/documentation/mapkit)
- [Apple: Core Location](https://developer.apple.com/documentation/corelocation)
- [Apple: Evaluating tool-calling behavior](https://developer.apple.com/documentation/Evaluations/evaluating-tool-calling-behavior)
