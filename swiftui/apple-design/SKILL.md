---
name: apple-design
description: Design, build, or review SwiftUI experiences for iOS 27 and the 2027 Apple-platform releases. Use when translating Apple design principles into native SwiftUI, adopting the refreshed Liquid Glass appearance, designing responsive and resizable iPhone layouts, refining navigation and toolbars, motion, interaction, typography, color, accessibility, scrolling performance, or WWDC26 SwiftUI APIs.
---

# Apple Design for SwiftUI — WWDC26 / iOS 27

Build apps that feel intentional, native, and responsive on iOS 27. Treat the linked `emilkowalski/skills` Apple Design skill as the conceptual foundation: direct manipulation, immediate response, interruptible motion, spatial continuity, material hierarchy, restraint, and accessibility. Apply those principles using Apple’s current native APIs and the WWDC26 guidance below.

This is a design-and-implementation skill, not a checklist to apply mechanically. Preserve the app’s purpose and content; use platform conventions for conventional jobs; spend bespoke design effort where it helps people understand the app’s unique value.

## Operating model

When implementing or reviewing a feature, work in this order:

1. State the user’s goal, the primary action, and the feedback needed after it.
2. Separate the **UI layer** (navigation and global controls) from the **content layer** (the app’s unique information and expression).
3. Start with standard SwiftUI components. Customize only where standard behavior cannot represent the product’s distinctive task or content.
4. Make the layout work at narrow, wide, tall, short, Dynamic Type, dark-mode, and resizable iPhone sizes before adding visual polish.
5. Add motion only when it explains causality, preserves spatial context, or confirms a meaningful action. Keep it interruptible and respect accessibility settings.
6. Check the performance path: state ownership, view identity, scrolling, image loading, and work performed during interaction.
7. Gate 2027-release APIs with availability when the deployment target needs it, and retain a usable fallback.
8. Prototype the interaction early, then inspect it in real context and, when needed, at slow speed or frame by frame. Refine the behavior and visual design together.

## Design reasoning: purpose before surface

Use Apple’s eight design principles to arbitrate tradeoffs. They are questions, not decoration:

| Principle | Ask | Implementing implication |
| --- | --- | --- |
| Purpose | Does this feature create clear value? | Cut features and ornament that consume attention without advancing the task. |
| Agency | Can people explore, cancel, and recover? | Keep navigation escapable; support undo for reversible mistakes; reserve confirmations for consequential, irreversible actions. |
| Responsibility | Is the app transparent and safe? | Request permission in context, disclose data use, and design AI suggestions so people retain review and control. |
| Familiarity | Does it behave as people expect on iPhone? | Keep system actions, gestures, labels, and icon metaphors recognizable. |
| Flexibility | Does it adapt to people and context? | Support Dynamic Type, accessibility, all supported orientations and sizes, input methods, and personalization where one layout cannot fit all. |
| Simplicity | Is the easiest path clear? | Use direct labels, hierarchy, and progressive disclosure; minimal appearance alone is not simplicity. |
| Craft | Are details coherent and reliable? | Align, animate, load, and write with care; test edge cases and iterate. |
| Delight | What should the person feel? | Let the first seven principles create the feeling; do not add arbitrary celebration effects. |

## iOS 27 layout and navigation

iPhone apps can be resizable in iOS 27. Do not assume a fixed phone width, a fixed orientation, or that `UIScreen.main.bounds` describes the view’s usable geometry.

- Prefer SwiftUI’s adaptive layout, safe-area behavior, size classes, `ViewThatFits`, `containerRelativeFrame`, and container-specific measurements.
- Keep the primary task and its core action visible at constrained sizes. Let secondary controls move into an overflow menu.
- Test live resizing in Xcode 27 previews, iPhone Mirroring, iPhone-on-iPad, Split View where applicable, rotation, and accessibility text sizes.
- Let system bars, tabs, and toolbars adapt. Never make custom chrome compete for the same edge space without a compelling product reason.

### Tabs and toolbars

Assign hierarchy deliberately rather than hoping the system guesses it correctly.

```swift
struct EditorView: View {
    var body: some View {
        ScrollView {
            EditorContent()
        }
        .toolbar {
            ToolbarItemGroup {
                UndoButton()
                RedoButton()
            }
            .visibilityPriority(.high)

            ToolbarOverflowMenu {
                ExportButton()
                DuplicateButton()
                DeleteButton()
            }

            ToolbarItem(placement: .topBarPinnedTrailing) {
                ShareButton()
            }
        }
        .toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar)
    }
}
```

- Use `visibilityPriority(.high)` for editing controls that must remain discoverable when space contracts.
- Put uncommon or destructive actions in `ToolbarOverflowMenu`; do not hide the only route to the primary action.
- Use `.topBarPinnedTrailing` only for an action that must stay continuously available.
- Use `toolbarMinimizeBehavior` to reveal more content while scrolling; preserve a clear route back to actions.
- Use `Tab(role: .prominent)` only for a genuinely distinct destination or task. Do not use it as a branding accent.

## Liquid Glass, brand, color, and materials

Treat the interface as two layers:

- **UI layer:** system navigation and actions — tabs, toolbars, menus, sheets, and controls. Keep this familiar, light, and legible.
- **Content layer:** the app’s imagery, information, writing, data visualization, and distinctive interactions. Put most brand expression here.

The 2027 releases refine the Liquid Glass appearance automatically. First run the app and inspect the system result; do not restyle system components merely to force an old visual language.

- Move solid brand-color bands out of top bars and into scrollable or full-bleed content where appropriate. Glass controls can then float above content and respond to its color.
- Use color to communicate hierarchy, status, feedback, selection, or a meaningful action. A saturated color without semantic purpose adds noise.
- Support dark mode and increased contrast; validate text and icon legibility over every material and content background.
- Read `accessibilityReduceMotion`, `accessibilityReduceTransparency`, and `colorSchemeContrast` when a custom visual needs a gentler motion, a more opaque surface, or stronger separation. Do not remove feedback; substitute a non-vestibular, legible equivalent.
- Build custom glass only when it conveys app-specific structure. Keep related custom glass elements visually consistent; use native glass APIs and availability checks.
- On iPad and macOS, use `appearsActive` when a custom element needs to reflect inactive-window state. Do not duplicate system inactive styling without a reason.
- Let material weight communicate hierarchy: use a stronger separation for a large structural surface and a lighter treatment for small, direct controls. Do not stack multiple light translucent layers; legibility collapses quickly.
- For a modal task, dim and visually recede the background. For a parallel, non-blocking panel, preserve the underlying flow with separation and offset rather than a heavy scrim.
- Prefer a scroll-edge material or gradient treatment only where floating chrome overlaps content. Do not add permanent hairline separators merely because a toolbar exists.
- When custom material enters or exits, animate its scale and material appearance with its opacity so it reads as a surface arriving or leaving, not a flat layer fading.

```swift
struct SidebarFooter: View {
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        AccountButton()
            .opacity(appearsActive ? 1 : 0.5)
    }
}
```

## Typography, iconography, and writing

- Prefer San Francisco and SwiftUI text styles. They supply established legibility, Dynamic Type behavior, localization support, and a native voice.
- When using a custom font, scale it with `Font.custom(_:size:relativeTo:)`, test every accessibility category, allow wrapping, and avoid relying on truncation for essential information.
- Establish hierarchy through the combined effect of text style, weight, width, spacing, and placement — not size alone. Use tighter leading and slightly tighter tracking for large display text; use more generous leading and neutral tracking for small body text.
- Treat `tracking(_:)` as style-specific. Do not apply one letter-spacing value to every text size or language; it will be too loose at display sizes or too tight at small sizes.
- Use custom icons when they are recognizable at small sizes, internally consistent, and faithful to iOS conventions for common actions. Otherwise use SF Symbols.
- Use direct, specific labels (for example, “Saved articles” rather than “Library” when that is the actual destination). Do not rely on a logo to orient people within the app.
- Write controls as actions or clear destinations; communicate status, completion, warning, and error near the event that caused them.

## Motion and interaction

Use motion to show that an input had an effect, connect a source to its result, or preserve context during navigation. The original Apple Design source remains especially useful here: interfaces should feel like direct manipulation rather than a sequence of disconnected scenes.

- Respond immediately on touch-down or gesture start. Show continuous feedback during a drag rather than only after it ends.
- Keep a gesture-driven element attached to the user’s input; respect the initial grab offset.
- Start an interrupted animation from its current presentation, not its original target. Let a user reverse a transition without waiting for it to finish.
- Preserve spatial logic: dismiss toward the origin direction; make expanded content appear to originate from the triggering item; use native zoom transitions when the relationship benefits from being explicit.
- Make intermediate movement point toward the expected result. A control expanding, snapping, or following a drag should reveal its destination through its trajectory rather than merely interpolating between two unrelated states.
- Use spring motion for user-driven, retargetable interactions. Prefer a restrained, critically damped feel by default; reserve visible bounce for motion that carries real momentum.
- Use haptics or sound only at meaningful causal moments (commit, snap, success, error). Align them with the visual transition and do not add them as ambient decoration.
- Reduce or replace large movement, parallax, and repeated oscillation when `accessibilityReduceMotion` is enabled. Preserve useful state feedback with opacity, color, or immediate changes.

### Fluid-motion rules for custom interactions

Apply these rules only when building a custom, directly manipulated control. Prefer the system’s `ScrollView`, sheet, menu, navigation, and drag-and-drop behaviors when they already provide the interaction.

| Situation | Native SwiftUI decision |
| --- | --- |
| Press or drag begins | Give immediate visual feedback and track the gesture continuously; do not wait for `onEnded`. |
| A drag can become horizontal or vertical | Watch candidate directions in parallel, then commit after a small movement threshold (about 10 pt is a useful starting point). |
| A control reaches a boundary | Apply progressive resistance rather than a hard stop; settle back with a spring after release. |
| A drag ends | Use velocity and `predictedEndTranslation` to choose a snap target. Do not choose solely from the finger’s final position. |
| Motion is retargeted or reversed | Use an interactive spring and retain the current position and velocity; never snap back to a stale model target. |
| Two-axis movement | Model horizontal and vertical motion separately when their velocity or constraints differ. |

For a custom spring, reason in terms of **response** and **damping fraction**, not a fixed duration. A useful baseline is `.spring(response: 0.35, dampingFraction: 1)`: it settles without an artificial overshoot. Use a damping fraction near `0.8` only after a flick, throw, rotation, or sheet drag that visibly carries momentum. A preset animation that cannot be redirected is unsuitable for an object a person is actively manipulating.

When building a custom snap target, project the release forward before finding the nearest valid target. The source model’s normal scroll projection uses a deceleration rate around `0.998`; in SwiftUI, prefer `predictedEndTranslation` rather than recreating that physics unless you are implementing a bespoke interaction engine. Hand the release velocity into the settling behavior so drag and animation meet without a perceptible seam.

For taps, allow a person to begin a press, drag away to cancel, and drag back to re-enter when appropriate. Avoid adding double-tap or long-press recognition if it delays a more common action without clear value.

### Frame and feedback discipline

- Keep work out of the gesture and display-update path. Do not decode images, perform I/O, rebuild large data sets, or repeatedly allocate models during a drag, scroll, or `TimelineView` tick.
- Use a display-synchronized tool such as `TimelineView` only for visible time-based visuals. Animate lightweight properties and stop or reduce the effect when it is obscured or no longer meaningful.
- Consider a restrained stretch or blur only for very fast content where it communicates speed. Never use it to conceal dropped frames or unclear behavior.
- Pair visual, haptic, and sound feedback on the causal event itself. Use one decisive cue for a snap or commit rather than multiple redundant cues.

## Native interaction APIs from WWDC26

Prefer the APIs that make richer interactions work consistently across standard and custom containers.

### Reorder and swipe actions

Use `reorderable()` with `reorderContainer(for:isEnabled:move:)` to support drag reordering in lists, stacks, grids, and custom layouts. Keep the ordering source of truth in the model and apply the returned difference atomically.

Use `swipeActions(edge:allowsFullSwipe:content:onPresentationChanged:)` together with `swipeActionsContainer()` for custom row layouts in `ScrollView`, `LazyVStack`, grids, or custom layouts. Use full swipe only when it commits a safe, unsurprising action; avoid it for irreversible deletion unless the action is recoverable.

Use `confirmationDialog(item:)` or `alert(item:)` for model-based presentations so the data that caused the presentation is explicit. Let a sheet own its dismissal and action handling where possible.

## SwiftUI data flow and build performance

Use the current Observation model and preserve a simple, visible data-flow path.

- Use `@Observable` for new shared mutable models; use `@State private` for view-owned state and view-owned observable reference models.
- Pass immutable values with `let`; use `@Binding` only when the child must mutate parent-owned state; use `@Bindable` for bindings to an injected observable model.
- In projects built with Xcode 27, `@State` is implemented by the `State()` macro. Class instances stored in `@State` initialize lazily once rather than being recreated during every view initialization.
- Remove an unnecessary default `@State` value if `init` assigns that same property; the macro’s initialization rules can make the previous pattern source-incompatible.
- Keep `body` pure and cheap. Move I/O, expensive transforms, and side effects to models, tasks, or explicit actions.
- Let `ContentBuilder` reduce overload ambiguity in deeply nested view code. Xcode 27 unifies common type-specific builders behind it, improving type-check performance even when targeting earlier releases.
- `AsyncImage` uses standard HTTP caching by default in the 2027 releases. Supply a `URLRequest` for request-level policy, or configure a `URLSession` and `URLCache` through `asyncImageURLSession` for a sustained custom policy.

## Long lists, lazy stacks, and scrolling

Choose `LazyVStack` or `LazyHStack` for large, custom scrollable content, then design to their actual lifecycle.

- Treat offscreen sizes as estimates. Avoid absolute content size and offset assumptions.
- Give every `ForEach` stable identity. Make each item resolve to one predictable subview when programmatic scrolling matters; do not create a variable number of leaf views per element.
- Pre-filter data outside the view builder (or use a SwiftData `Predicate`), rather than using conditionals inside each row.
- Initialize setup needed for prefetching in `init` or model work, not `onAppear`. Lazy stacks prefetch before a row becomes visible, while `onAppear` can delay essential setup into the scrolling path.
- Move state that must survive an offscreen row into an observable model or an outer binding. A lazy stack can eventually discard offscreen row state.
- Use `ScrollPosition` with stable IDs for programmatic scrolling. Avoid layout changes from `onAppear` or frequent geometry callbacks during an animated scroll.
- Do not apply scroll transitions that move normally invisible lazy-stack children into the visible rectangle; it defeats the expected loading behavior.

## Graphics effects

For a distinctive visual, build a pipeline from small, testable transformations instead of a monolithic custom view.

1. Identify the existing data and visual layers.
2. Apply ordinary layout and visual modifiers first (composition, blur, clip, overlay, alignment).
3. Add one shader effect only when an effect needs per-pixel work.
4. Drive only the needed parameter with `TimelineView` or state; stop or simplify expensive animation when it is not meaningful.
5. Keep foreground content legible and validate GPU work on representative devices.

Select the shader based on the transformation:

| Need | SwiftUI shader effect |
| --- | --- |
| Transform each pixel’s color independently | `colorEffect` |
| Sample source pixels from a transformed coordinate | `distortionEffect` |
| Sample neighboring pixels or the whole source layer | `layerEffect` |

Do not use shaders to manufacture a brand look at the cost of text readability, battery, or motion comfort. If the effect does not reinforce content or feedback, remove it.

## iOS 27 readiness review

Before handing off a feature, verify:

- [ ] The primary task, its result, and recovery path are obvious.
- [ ] Native tabs, navigation, toolbars, menus, sheets, and context menus are used for conventional interaction.
- [ ] Brand expression lives mainly in content, not in a replacement navigation system.
- [ ] The view remains usable when resized, rotated, using large Dynamic Type, in dark mode, and with increased contrast or reduced motion.
- [ ] Controls have textual accessibility labels where symbols alone are ambiguous; actions have appropriate traits and hit targets.
- [ ] Motion is immediate, causal, spatially coherent, interruptible where directly manipulated, and optional for motion-sensitive people.
- [ ] Custom drag interactions have a directional threshold, continuous tracking, a velocity-aware snap decision, and progressive boundary resistance where applicable.
- [ ] Translucent surfaces remain readable with Reduce Transparency and Increased Contrast; custom materials do not stack without a hierarchy reason.
- [ ] Toolbar priority and overflow behavior have been tested at narrow widths.
- [ ] Collections use stable identity, externalized durable state, and no important `onAppear` initialization.
- [ ] No new 2027 API is called unguarded when the project supports earlier OS versions.
- [ ] The feature is tested on device or representative preview configurations, not only a single simulator size.

## Primary sources

- Foundation source: [emilkowalski/skills — Apple Design](https://github.com/emilkowalski/skills/tree/main/skills/apple-design)
- [WWDC26: What’s new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/)
- [WWDC26: Dive into lazy stacks and scrolling with SwiftUI](https://developer.apple.com/videos/play/wwdc2026/321/)
- [WWDC26: Compose advanced graphics effects with SwiftUI](https://developer.apple.com/videos/play/wwdc2026/322/)
- [WWDC26: Communicate your brand identity on iOS](https://developer.apple.com/videos/play/wwdc2026/251/)
- [WWDC26: Principles of great design](https://developer.apple.com/videos/play/wwdc2026/250/)
- [Apple’s iOS 27 guide](https://developer.apple.com/wwdc26/guides/ios/)
