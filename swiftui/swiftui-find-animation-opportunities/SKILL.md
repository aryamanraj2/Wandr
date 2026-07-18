---
name: swiftui-find-animation-opportunities
description: Read-only analysis that finds only high-value SwiftUI motion opportunities and explicitly rejects needless motion. Use when someone asks what should animate, wants an iOS screen to feel more responsive, or needs precise motion recommendations without code changes.
---

# Find SwiftUI Motion Opportunities

Inspect an interface as a strict filter, not a motion generator. Do not edit source code. A short, high-confidence set of recommendations is better than an animated version of every state change.

## Gate every candidate

Record the decision for each candidate in this order.

| Gate | Eligible when | Reject when |
| --- | --- | --- |
| Frequency | The event is occasional or rare | It is repeated navigation, a keyboard action, a focus change, or a high-frequency control |
| Purpose | Motion gives feedback, maintains spatial context, makes a state legible, bridges a jarring change, explains onboarding, or marks a rare success | The only rationale is “more alive” or “looks cool” |
| Function | Motion helps people understand or control the UI | It moves data people need to read, delays an action, or competes with content |
| Accessibility | A reduced-motion and alternate-input behavior is clear | Motion is the only explanation or gesture is the only route |
| Performance | The update is local and cheap | It needs continuous heavy work, unstable identity, or layout churn in a scroll path |

## Hunt in SwiftUI code and UI

Look for these seams, then apply the gate:

- A meaningful `Button` has no immediate pressed feedback.
- A low-frequency view appears, disappears, expands, or changes identity with a visible jump.
- A sheet, popover, or detail presentation loses its visual relationship to the triggering item.
- A custom drag reaches a snap point or a boundary without continuous feedback, resistance, or a clear settling state.
- A destructive action would benefit from a reversible step, confirmation, or hold-to-confirm interaction.
- An occasional status change, success state, or onboarding feature needs a concise explanation.
- A value change would be more legible through a content transition, while remaining readable and non-distracting.

Explicitly reject motion on tab switching, list-row browsing, search keystrokes, command and keyboard invocation, frequent toggles, dense data, and content that already receives appropriate system motion.

## Native recommendation recipes

Use a system component first. When a recommendation survives the gate, recommend a native mechanism and an availability-safe fallback.

| Opportunity | SwiftUI recipe | Check |
| --- | --- | --- |
| Press feedback | Semantic `Button` with a subtle pressed style (about 0.97 scale, ~140 ms ease-out) | Do not duplicate feedback a standard control already supplies. |
| Context-preserving detail | Zoom or source-aware transition; symmetric dismissal path | Verify the source remains recognizable. |
| Expand/collapse | Opacity plus layout transition; preserve reading position | Avoid on high-frequency rows. |
| Custom drag settle | `DragGesture` plus predicted end and an interactive spring | Verify reversal, boundary resistance, and an alternate action. |
| Added/removed occasional item | Identity-aware transition from modest scale and opacity | Keep the list stable and avoid a large stagger. |
| Status or success | `contentTransition`, `symbolEffect`, or `sensoryFeedback` where the state is meaningful | Pair nonvisual feedback and honor Reduce Motion. |

## Required report

Return no more than seven recommendations for a whole app, and fewer for a view. Use this exact structure:

### Opportunities

| Priority | Location | User event | Gate evidence | Recommendation | Native mechanism | Accessibility / performance check |
| --- | --- | --- | --- | --- | --- | --- |

### Rejected candidates

List at least two considered candidates when the UI has enough surface area. State the reason, such as high frequency, no purpose, system behavior already sufficient, information density, or accessibility risk.

### Verdict

State whether the screen needs motion at all. “No additions recommended” is a valid and often strong result.

## Sources

- Adaptation source: [emilkowalski/skills — Find Animation Opportunities](https://github.com/emilkowalski/skills/tree/main/skills/find-animation-opportunities)
- [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion/)
- [Apple HIG: Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback/)
- [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)
