# Wandr AI Technology Stack

## Decision Summary

Wandr v1 is a native iOS 27, local-first outing planner with Trips as a second planning surface. Siri can hand a **user-requested conversation summary** to Wandr; Wandr never queries WhatsApp, iMessage, or Messages itself.

Apple Foundation Models is the intelligence layer. Apple frameworks provide live evidence and user-owned handoffs. Deterministic Swift validates feasibility and controls all side effects. This replaces the previous Gemini/LangChain/backend-agent concept with a private, inspectable iOS architecture that needs no server model key.

## Stack at a Glance

| Area | Selected technology | Purpose | V1 constraint |
| --- | --- | --- | --- |
| Siri handoff | App Intents + App Shortcuts | Receives an explicit rich Siri summary into the foreground app | System/messaging app decides personal-context availability; no direct chat access |
| Intake/synthesis | Foundation Models | Typed brief extraction, grounded option synthesis, and streamed plans | Raw Siri summary is volatile; no action tools in model sessions |
| Default model | `SystemLanguageModel` | On-device, private model work for normal outing/trip plans | Runtime availability must be checked |
| Optional escalation | Private Cloud Compute | Complex synthesis only when device/service capability allows | Never the default and always falls back locally |
| Place and route evidence | MapKit | Venue/activity discovery, maps, route duration, and distance | Evidence, not a booking or opening-hours guarantee |
| Optional origin | Core Location | Host-selected current-location origin or search bias | When-In-Use only; manual area is equal fallback |
| Weather evidence | WeatherKit | Outdoor suitability and indoor fallback constraints | Optional entitlement/network path; explicit unavailable state |
| Calendar | EventKitUI | Editable, system-owned event draft after approval | No broad calendar read/write permission |
| Sharing | `ShareLink` + `Transferable` | Host-controlled export to Messages, WhatsApp, or another target | No automatic message or recipient selection |
| Local data | SwiftData | Structured brief, plans, revisions, evidence metadata, approvals, opt-in preferences | No cloud sync, accounts, raw chat summary, or transcript storage |
| Quality | Swift Testing + Evaluations | Deterministic and model-behavior regression coverage | Test-only infrastructure; no production data collection |

## Siri and Messaging Boundary

### Selected handoff

`PlanOutingFromSiriSummaryIntent` accepts one `AttributedString` parameter named `summary`. The intent runs in the foreground and requires authentication. An `AppShortcutsProvider` exposes natural phrases such as “Plan this group outing in Wandr.”

Rich text preserves a Siri/Shortcuts handoff more faithfully than a lossy plain string. On receipt, Wandr renders the summary solely on the Host Review screen. It extracts constrained fields after explicit confirmation, then deletes the raw `AttributedString` from in-memory state and never writes it to SwiftData.

### Availability and recovery

Apple Intelligence, Siri, Shortcuts, and the installed messaging app determine whether a personal-context summary can actually reach an App Intent. This capability must be tested on the exact judging device.

If the intent receives no content, only whitespace, unsupported content, or an unavailable handoff, Wandr shows **“Ask Siri to send the summary to Wandr again.”** It does not offer a mock group chat, local WhatsApp/iMessage scraping, a Messages extension, or an external messaging API as a fallback.

### Explicitly not used

- No Messages extension or WhatsApp integration.
- No contact access, chat transcript access, participant identity, polling, votes, or delivery tracking.
- No microphone or `SpeechAnalyzer`/`SpeechTranscriber` in this flow: Siri owns speech understanding before Wandr opens.
- No background App Intent behavior, purchases, booking submission, automatic calls, or automatic messages.

## Foundation Models Architecture

### Typed boundaries

All model input/output boundaries use `@Generable` domain types and focused `@Guide` constraints rather than manual JSON parsing. Guides constrain vocabulary, required fields, option counts, and safe response shape; deterministic services enforce feasibility and permissions.

| Typed value | Model responsibility | Deterministic guard |
| --- | --- | --- |
| `OutingBrief` | Extract only confirmed/suggested constraints from volatile summary | Host confirms constraints; raw summary is discarded |
| `TravelConstraints` | Represent date, time, budget, group, access, and preference rules | Validator treats unknowns and conflicts explicitly |
| `GroundedOption` | Reference venue/route/forecast evidence by ID | Evidence source and retrieval time required |
| `WandrPlan` | Present an editable candidate with rationale and alternatives | Warnings/evidence cannot be removed by synthesis |
| `ActionProposal` | Describe a possible native handoff | Executor accepts only host-approved, immutable proposals |
| `PlanningEvent` | Explain an orchestration step or limitation | Never stores private model reasoning or raw chat content |

### `LanguageModelSession` and Dynamic Profiles

One coordinator owns short-lived `LanguageModelSession`s for a `PlanningRun`. Dynamic Profiles isolate phases through different instructions, context, tool sets, and transcript-retention rules:

1. **Intake:** receives the volatile Siri summary, performs constrained extraction, and has no tools.
2. **Research:** sees only the confirmed structured brief and opt-in preferences; exposes read-only tools and requires evidence collection before venue-specific synthesis.
3. **Synthesis:** sees immutable evidence snapshots and validator output; has no live tools by default.
4. **Approval:** creates typed proposals from a selected plan; has no tools.

No profile receives an irreversible action tool. The raw Siri summary is redacted before research/synthesis contexts and is not retained in long-lived session history.

### Tools, streaming, and errors

`Tool` implementations are deliberately narrow, with concise descriptions and compact typed results:

- `ResolveOriginTool`, `SearchPlacesTool`, `EstimateRouteTool`, `GetForecastTool`, `LoadPreferencesTool`, and `ValidateItineraryTool` are read-only.
- Research tool use is required before factual venue recommendations may be synthesized.
- Tool errors become typed limitations that appear in the host’s timeline and plan; the model must not replace them with background knowledge.
- Long candidate-plan generation uses streamed output. Partial output is labeled provisional until the completed typed plan passes deterministic validation.
- Structured handling covers unavailable model assets, unsupported locale, guardrail refusal, context exhaustion, concurrent requests, malformed generated content, and tool failures.

### Model selection

1. `SystemLanguageModel.default` is the default for all extraction and normal outing/trip synthesis.
2. Private Cloud Compute may be considered only for a host-approved, unusually complex synthesis and only after its current iOS 27 capability, quota, and network requirements are satisfied.
3. PCC unavailability, quota, network failure, or service failure returns to the system model with a reduced scope if necessary. It never blocks host editing or invokes a third-party LLM.

### Foundation Models exclusions

- No custom Foundation Models adapters.
- No Gemini, LangChain, hosted orchestration backend, server LLM, API key, model proxy, or prompt log.
- No model-generated side effects, booking decisions, payment decisions, or messaging decisions.

## Live Evidence and Native Handoffs

### MapKit and Core Location

MapKit is the factual place/route layer. `MKLocalSearch` (or a focused equivalent) returns candidate venues and activities; directions returns distance and duration evidence used by validation. SwiftUI `Map` presents the selected route and venues.

Core Location is optional. Ask for When-In-Use authorization only after the host taps **Use my location**. Stop after resolving a usable origin, use the lowest practical accuracy, and provide manual city/neighborhood entry whenever permission is denied, approximate, or unnecessary. No background location, route history, geofencing, or Always authorization is in v1.

### WeatherKit

WeatherKit supplies the minimum forecast fields needed to validate outdoor plans. Any WeatherKit UI must include required attribution. Missing entitlement, network, or forecast data yields a visible weather-unverified warning and an indoor option—not invented weather data or a blocked plan.

### EventKitUI, URLs, and sharing

`EKEventEditViewController` presents an editable calendar draft after the host approves a proposal. This avoids broad calendar access and keeps the save decision in system UI.

The deterministic executor may open a visible Maps route, booking page, or `tel:` handoff only after explicit host selection. It cannot infer completion of a reservation or call.

`ShareLink` and `Transferable` export a host-selected final plan. The system share sheet may include iMessage or WhatsApp according to installed apps, but Wandr never chooses recipients or sends in the background.

## Storage, Retention, and Privacy

SwiftData stores locally:

- confirmed `OutingBrief`/trip fields, without raw Siri summary text;
- plan revisions, structured evidence IDs, retrieval timestamps, source names, and validation warnings;
- immutable approval records and native-handoff status;
- optional, user-accepted preference facts.

The summary-source audit record contains only metadata such as `source = siriMediatedSummary`, handoff time, confirmation/cancellation outcome, and a retention flag. It contains neither the summary text nor a transcript-derived identifier.

Preference memory is opt-in, editable, and removable. Wandr has no account requirement, CloudKit sync, analytics pipeline, embeddings store, contact data, location trail, payments data, or booking credentials in v1.

## Evaluation and Test Strategy

The first test target uses three sanitized Siri-summary fixtures:

1. **After-office party:** time-limited, mixed dietary preferences, neighborhood constraint.
2. **Birthday outing:** group size, budget, surprise/activity preference, accessibility caveat.
3. **Full-day outing:** multiple activities, weather sensitivity, fixed finishing time.

Deterministic tests cover `AttributedString` input, missing/empty summary recovery, host-confirmation gating, raw-summary non-persistence, extraction into constraints, grounded alternatives, re-planning, and final share payload creation.

Foundation Models Evaluations cover structured extraction, expected research-tool trajectories, required evidence IDs, feasibility warnings, source freshness, unavailable model paths, PCC failure, tool failure, injection resistance, and approval gating. Evaluation subjects call the shipped coordinator through deterministic providers rather than duplicating prompts in a test.

## Capability and Permission Checklist

| Capability or permission | Needed in v1 | Decision |
| --- | --- | --- |
| App Intents / App Shortcuts | Yes | Foreground Siri handoff only |
| Apple Intelligence | Yes for model path | Check runtime availability and show recovery state |
| Private Cloud Compute | Optional | Complex synthesis escalation only |
| Location When In Use | Optional | Request only after host action; manual fallback exists |
| WeatherKit entitlement | Optional | Use only if configured; show limitation otherwise |
| Calendar permission | No | System event editor instead of broad calendar access |
| Microphone / Speech Recognition | No | Siri owns the spoken-context path |
| Messages / Contacts / WhatsApp permissions | No | Explicit privacy boundary |
| Background execution | No | All planning and actions remain foreground, host-controlled |

## Sources

- [Apple: Foundation Models](https://developer.apple.com/documentation/foundationmodels/)
- [Apple: Tool protocol](https://developer.apple.com/documentation/foundationmodels/tool)
- [Apple: Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [Apple: App Intents](https://developer.apple.com/documentation/appintents)
- [Apple: Integrating your messaging app with Apple Intelligence](https://developer.apple.com/documentation/appintents/integrating-your-messaging-app-with-apple-intelligence)
- [Apple: Use model actions in Shortcuts (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/260/)
- [Apple: MapKit](https://developer.apple.com/documentation/mapkit)
- [Apple: Core Location](https://developer.apple.com/documentation/corelocation)
- [Apple: WeatherKit](https://developer.apple.com/documentation/weatherkit)
- [Apple: Evaluating tool-calling behavior](https://developer.apple.com/documentation/Evaluations/evaluating-tool-calling-behavior)
- [Google Cloud: grounded agentic travel architecture](https://docs.cloud.google.com/architecture/agentic-ai-system-with-grounding-using-maps)
- [TravelAgent research paper](https://arxiv.org/abs/2409.08069)
