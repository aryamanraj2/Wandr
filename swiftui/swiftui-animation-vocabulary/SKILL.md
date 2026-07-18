---
name: swiftui-animation-vocabulary
description: Name a vague animation or motion effect using precise SwiftUI and iOS terminology. Use when someone asks “what is this effect called?”, needs the right term to prompt an agent or designer, or must distinguish related motion patterns; use this for naming, not for designing or implementing animation.
---

# SwiftUI Animation Vocabulary

Turn a description of what someone sees or feels into the closest precise term. Lead with the term, define it in one sentence, then list up to two close alternatives only when they materially differ. Do not design, audit, or implement the effect unless asked separately.

## Response format

```markdown
**Matched geometry / shared-element transition** — The same visual element appears to travel and transform between two locations, preserving its identity.

Close alternate: **Zoom transition** — use this when the transition is specifically a presentation that expands from a source.
```

If no term matches exactly, say that it is an approximation and describe the effect using the closest vocabulary. Do not invent a proprietary-sounding term.

## Entrances, exits, and state changes

| Term | Meaning | Common SwiftUI mechanism |
| --- | --- | --- |
| Fade | Appearance or disappearance through opacity | `.transition(.opacity)` |
| Slide | Movement into or out of an edge | `.move(edge:)` transition |
| Scale-in | Modest growth to full size, often with opacity | `.scale.combined(with: .opacity)` |
| Pop-in | Scale-in with visible spring overshoot | Spring transition; use sparingly |
| Reveal | Content uncovered by a mask, clip, or progressive shape | `mask`, `clipShape`, custom `Animatable` |
| Crossfade | One state fades while another fades in at the same location | Opacity / content transition |
| Content transition | A rendered value changes with an animated bridge | `contentTransition` |
| Layout animation | A view moves or resizes smoothly after layout state changes | Value-driven animation on layout state |
| Accordion | A section expands or collapses while preserving reading context | Conditional content plus layout/opacity transition |
| Morph | One shape or representation becomes another | Shape animation, content transition, or matched geometry |

## Continuity and navigation

| Term | Meaning | Native mapping |
| --- | --- | --- |
| Spatial continuity | Before and after states remain visibly related | Symmetric transition and stable source context |
| Origin-aware transition | A presentation grows from the control or content that triggered it | System popover/menu behavior or zoom transition |
| Zoom transition | A source appears to expand into its destination | SwiftUI zoom presentation / navigation transition where available |
| Matched geometry / shared element | A visual item travels and transforms between two layouts | `matchedGeometryEffect` |
| Direction-aware transition | Forward and back motion use opposing, meaningful directions | Asymmetric transition or native navigation |
| Interactive dismissal | A presented view follows a gesture and can settle back or dismiss | System sheet or custom `DragGesture` |

## Interaction and feedback

| Term | Meaning | Native mapping |
| --- | --- | --- |
| Press feedback | Immediate response while a control is pressed | `ButtonStyle` and `configuration.isPressed` |
| Hold to confirm | A progress threshold confirms a deliberate sustained press | Long-press state plus visible progress and cancel path |
| Drag to reorder | A dragged item changes ordering while peers make room | `reorderable` / `reorderContainer` |
| Swipe action | Horizontal gesture reveals or performs a row action | `swipeActions` / `swipeActionsContainer` |
| Rubber-banding | Increasing resistance past a boundary, then spring-back | Custom drag resistance; system scroll behavior |
| Snap | A value settles to the nearest meaningful target | Predicted-end gesture plus spring |
| Haptic feedback | Tactile cue at a meaningful state change | `sensoryFeedback` or haptics API |
| Symbol effect | A system symbol animates to communicate state | `symbolEffect` |
| Shake | Brief lateral error or rejection signal | Short, accessible custom offset animation |

## Timing and physics

| Term | Meaning |
| --- | --- |
| Value-driven animation | Animation runs because a specific model value changed. |
| Explicit animation | A scoped animation applied with `withAnimation`. |
| Transition | Animation that describes a view entering or leaving the hierarchy. |
| Phase animation | A sequence of named visual phases. |
| Keyframe animation | Animation defined by multiple time/value points; use when the sequence must be prescribed, not directly manipulated. |
| Easing | The change in velocity during a fixed-duration animation. |
| Ease-out | Fast initial response that settles; useful for short response and entrance motion. |
| Ease-in-out | Acceleration and deceleration around an on-screen reposition. |
| Linear | Constant velocity; reserve for genuine continuous progress. |
| Spring | A velocity-aware animation that settles rather than ending at a fixed time. |
| Damping fraction | The amount of spring overshoot; `1` is a no-bounce baseline. |
| Response | How quickly a spring reacts; it is not a prescribed duration. |
| Momentum | Carrying motion forward after a drag or interruption. |
| Interruptible animation | Motion that can change target without visibly restarting. |

## Scrolling, ambient motion, and effects

| Term | Meaning | Caution |
| --- | --- | --- |
| Scroll transition | A visual effect driven by a view’s position within scrolling content | Do not pull otherwise offscreen lazy content into view. |
| Scroll-linked animation | Animation progress derives from scroll position | Keep content readable and reduce under accessibility settings. |
| Parallax | Foreground and background move at different rates | Avoid when it harms reading or motion comfort. |
| Stagger | Similar items animate with a small intentional offset | Reserve for rare, small groups; avoid in frequently changing lists. |
| Orchestration | Multiple motions are timed as one coherent event | State the causal order, not just delay values. |
| Timeline animation | Visual state is driven by display time | Use `TimelineView`; keep work light. |
| Shader effect | GPU pixel transformation for a visual effect | Use `colorEffect`, `distortionEffect`, or `layerEffect` according to the sampling need. |
| Blur transition | A temporary blur helps bridge visually dissimilar states | Avoid under Reduce Motion and do not sacrifice text readability. |
| Skeleton / shimmer | Placeholder indicating loading before content arrives | Do not imply activity if no progress is occurring. |

## Quality terms

| Term | Meaning |
| --- | --- |
| Jank | Visible stutter caused by missed display deadlines. |
| Dropped frame | A frame misses its presentation deadline, producing a hitch. |
| Layout thrash | Repeated layout changes in a hot animation or scroll path. |
| Perceived performance | How responsive an interface feels, which can differ from measured task time. |
| Reduced motion | An alternate behavior that avoids potentially uncomfortable automatic movement while retaining feedback. |
| Spatial consistency | Motion makes it clear where something came from, went, or changed. |
| Purposeful animation | Motion provides feedback, context, explanation, or meaningful status rather than decoration alone. |

## Sources

- Adaptation source: [emilkowalski/skills — Animation Vocabulary](https://github.com/emilkowalski/skills/tree/main/skills/animation-vocabulary)
- [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion/)
- [WWDC26: Compose advanced graphics effects with SwiftUI](https://developer.apple.com/videos/play/wwdc2026/322/)
