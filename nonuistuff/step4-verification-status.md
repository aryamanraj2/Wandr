# Step 4 (UI Bridge) — Verification Status

Date: 2026-07-19. Machine: `aryamanjaiswal` (see step3-verification-status.md for
the `DEVELOPER_DIR` requirement and simulator details — unchanged).

## What landed (six commits, per `nonuistuff/bridge.md` §7)

1. **Evidence retention** — `WandrPlan.evidence: [GroundedVenue]` (additive,
   defaulted) + `venue(_:)`; `FeasibilityValidator` populates it. All prior suites
   passed **unmodified** (223 passed, 0 failed).
2. **Candidate honesty** — `perHead`/`openWindow`/`travelNote` optional, `venueID`
   + `warnings` added, `priceLabel` keeps Free ≠ unknown, `costRange` discloses
   unpriced picks. `DemoPlan` unchanged via defaulted parameters.
3. **`PlanPresentation`** — pure `WandrPlan → [Deck]` mapper + 21 deterministic
   tests, including a compile-time-exhaustive `PlanWarning.Kind` survival check.
   Warning placement rule: card for a rendered venue, deck header otherwise —
   every warning reaches exactly one rendered surface.
4. **`CurationView` injection** — `init(decks:)`, `RootView` maps
   `harness.readyPlan`, re-keyed on plan ID. Empty (never `DemoPlan`) before ready.
5. **Schedule bridge** — `SchedulePresentation` (minutes verbatim, single day
   dated from `plan.generatedAt`), harness fetches the draft before `.ready`
   flips, `ScheduleView` gains `init(days:blocks:)`.
6. **Warning surface** — `Wandr.caution` token; card + deck-header rendering,
   VoiceOver included. §8.2 assertions added to the Hauz Khas live test.

## Verification

- Deterministic tier ran after **every** commit: `** TEST SUCCEEDED **` each time.
- Device-gated end-to-end: `hauzKhasResolvesAndValidates()` ran real inference and
  passed with the new bridge assertions (xcresult confirmed **1 executed**, not a
  vacuous filter pass): mapped decks non-empty, every rendered `venueID` ∈
  `plan.evidenceIDs`, and **no rendered area outside the brief's** — the automatic
  form of the "Gurgaon in a Hauz Khas plan" check.

## Still manual (§8.3)

Typing the six fixture requests on device and eyeballing the decks. The §11
dataset-vs-`MapKitVenueProvider` decision is now answerable by doing exactly that.

## Carry-forward lesson (adds to the `#expect` negation gotcha)

`#expect(collection.allSatisfy { … })` (and key-path forms) can fail to compile
inside the macro expansion ("call can throw, but it is not marked with 'try'").
Bind the result to a local `let` and assert the local.
