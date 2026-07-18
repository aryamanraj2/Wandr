---
name: swiftui-design-engineering
description: Design, build, or review polished native SwiftUI interfaces for iOS 27 and current Apple-platform releases. Use for component craft, interaction feedback, motion decisions, gesture behavior, presentation origins, performance, accessibility, and code review that must preserve Apple conventions while giving an app a distinct identity.
---

# SwiftUI Design Engineering

Build interfaces whose quality comes from many small, coherent decisions: an action responds immediately, a transition explains its cause, content remains legible, and the feature behaves correctly in every supported context. Treat beauty as product leverage, but never as a reason to defeat function, performance, or accessibility.

## Design decision sequence

Before adding a custom visual or animation, answer in this order:

1. **Purpose:** What user task, state, or relationship does it clarify?
2. **Frequency:** How often will a person encounter it? The more frequent it is, the less visual latency it can carry.
3. **Native baseline:** Can `Button`, `Menu`, `ContextMenu`, `Sheet`, `NavigationStack`, `TabView`, `List`, drag-and-drop, or a system transition already solve it?
4. **Feedback:** What immediate visual, haptic, textual, or audible confirmation is useful?
5. **Adaptation:** Does it work with Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, contrast changes, alternate input, resize, and dark mode?
6. **Cost:** Can it stay smooth on representative hardware without doing work in `body`, a gesture callback, or an animation tick?

Do not animate keyboard-first actions, repeated navigation, focus changes, or high-frequency controls merely to add personality. Motion can be near-instant and restrained for frequent direct feedback; reserve more expressive motion for occasional transitions and rare moments of success or orientation.

## Native component craft

- Prefer system components for standard jobs. Customization should make the app’s content or specialized task clearer, not reimplement a familiar interaction.
- Make every pressable control react at touch-down. Use a `ButtonStyle` with a subtle `configuration.isPressed` effect when the system control does not already convey enough feedback.
- Never make a control’s only feedback depend on color, sound, motion, or a gesture. Pair signals and retain an accessible name and value.
- Let popovers, context menus, and zoom transitions retain their relationship to the triggering item. Keep a modal centered when it is not conceptually attached to a source.
- Avoid entrances from zero scale. If a custom entrance needs scale, pair modest scale (roughly 0.95–0.98) with opacity; retain a perceptible physical form.
- Use custom components only when their task or data deserves dedicated interaction. Audit ordinary functionality for an existing system control before drawing a bespoke replacement.

```swift
struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
```

Use this sparingly. A semantic `Button` retains keyboard, VoiceOver, Switch Control, and system interaction behavior that a gesture-only view does not.

## Motion selection

| Situation | Prefer | Avoid |
| --- | --- | --- |
| A state appears, disappears, or changes hierarchy | A short transition that preserves context | Decorative motion that delays access |
| A person drags, swipes, resizes, or interrupts | An interactive spring with continuous gesture feedback | Fixed keyframe-style sequences that must finish first |
| A screen, menu, or popover has a source | Source-aware / zoom / directionally symmetric transition | Entering from one edge and dismissing to an unrelated edge |
| A value changes in place | Content transition or a modest opacity/scale bridge | A jump that makes the new value look unrelated |
| Continuous progress | Linear motion tied to real progress | Looping decorative motion that suggests false progress |
| Information-dense or repeated UI | No motion, or minimal instant feedback | Stagger, parallax, or bounce for style |

Use springs for user-driven, retargetable movement. SwiftUI springs preserve velocity when one spring supersedes another on the same property, which makes them appropriate for interruption. Default to no visible overshoot; introduce small bounce only where a real gesture supplies momentum.

Use `.easeOut` for a short entrance or response, `.easeInOut` for a noninteractive on-screen reposition, and `.linear` only when the represented phenomenon is actually constant (for example, a determinate progress indicator). Do not choose an animation because its name sounds exciting; choose it because its velocity curve communicates the event.

## Gestures, feedback, and physicality

- Prefer standard gestures. Add a custom gesture only for a specialized, frequent task that standard controls cannot express; always provide an alternate control path.
- During direct manipulation, track the person’s movement continuously and make the intended destination evident before release.
- Use velocity and predicted ending location to settle a custom drag. Resist gradually beyond a boundary and spring back; do not freeze abruptly.
- Start a reversed transition from the visible, current value. Do not block input while the first transition completes.
- Trigger haptics on a meaningful causal event — a snap, commit, error, or threshold — and align them with the corresponding visual state. System controls already provide appropriate feedback; do not duplicate it.

## Accessibility and performance are craft

- Use `accessibilityReduceMotion` to substitute fades or immediate state changes for large, automatic, repetitive, or depth-changing movement. Tighten springs and avoid blur transitions under reduced motion.
- Use `accessibilityReduceTransparency` and `colorSchemeContrast` to strengthen custom material contrast. Keep text and controls readable above variable content.
- Support touch, keyboard, VoiceOver, Voice Control, Switch Control, and onscreen alternatives for essential gesture actions.
- Keep animatable state localized. Give lists stable IDs, avoid `AnyView` in hot rows, and move durable row state to a model or parent binding.
- Test on device and at 1× or slow-motion playback when reviewing a complex interaction. A correct-looking still image cannot prove a transition feels coherent.

## Required review format

For a code or design review, report concrete fixes as a table before any narrative:

| Before | After | Why |
| --- | --- | --- |
| A gesture-only tappable view | A semantic `Button` plus `ButtonStyle` | Preserves alternate input and supplies immediate feedback. |
| A fixed-duration drag settling animation | An interactive spring that receives the current gesture state | Lets the motion reverse or retarget without a jump. |

Use file and line references when reviewing a repository. State uncertainty where feel cannot be inferred from source and identify the device or slow-motion check required.

## Sources

- Adaptation source: [emilkowalski/skills — Emil Design Engineering](https://github.com/emilkowalski/skills/tree/main/skills/emil-design-eng)
- [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion/)
- [Apple HIG: Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures/)
- [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)
- [SwiftUI spring](https://developer.apple.com/documentation/swiftui/animation/spring)
