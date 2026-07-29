# Handover — plan shape, extraction boundary, retrieval

Session of 2026-07-27/28. Read `CLAUDE.md` first; it governs *how* to work here and
this file records *what happened*. `HANDOVER.md` remains the architecture reference.

---

## 1. State

- **301 tests pass, 1 skipped, 0 failing.** The skip is the semantic-ranking quality
  test, correctly disabled in the Simulator (see §5).
- **Everything below is uncommitted** except phases 1–4, which were committed mid-session
  (`b52c2a4`, `aaecfa6`, `3b5438a`, `4271640`, `2b362d7`, `1049686`). The Phase 5
  evaluation suite, the dataset expansion, and the fixture repairs are still in the
  working tree.
- Verify with:
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # no sudo needed
  xcodebuild test -scheme Wandr -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
  ```

---

## 2. THE OPEN BUG — start here

`areaNotCovered` fires for an area the app **does** cover.

**Repro:** `Dinner in hauz khas for my sister birthday budget around 2000`
→ error screen: *"Wandr doesn't cover that area yet. Right now it knows … **Hauz Khas** …"*
The failure message lists the very area that was asked for.

**Not the cause** (both checked and ruled out this session):
- Extraction did **not** drop the field. `DONE fields=4 settled=[outingType,area,budget,stops]`.
- The dataset is fine — the message enumerates all 16 covered areas.
- Not the fake extractor. Production wires `ChatSummaryBriefExtractor`
  (`PlanningCoordinator.swift:47`), so `FakeBriefExtractor.birthdayDraft` never runs.

**Leading hypothesis — the model over-captured the area string.** Compare the two runs:

| prompt | after the area name | outcome |
|---|---|---|
| `Dinner in khan market**,** its a first date with budget around 2000` | comma | worked, plan built |
| `Dinner in khan market` (no budget) | end of string | worked |
| `Dinner in hauz khas **for my sister birthday** budget around 2000` | no delimiter | **failed** |

With nothing marking where the neighbourhood ends, `ExtractedSummary.area` most likely
came back as something like `"hauz khas for my sister birthday"`, which normalizes to
nothing `DistrictVenueProvider` recognises. Existing alias tests cover
`"Connaught Place, New Delhi"` and `"the CP area"` but not a trailing clause the model
swallowed.

**This is unconfirmed.** The area value is host text and is deliberately never logged, so
it took a screenshot to get this far. Confirm by breakpointing or temporarily printing
`payload.area` — do not commit that print.

**Proposed fix — the same one applied three times already this session.** "Hauz khas" is
in the host's own words, and the only thing that can currently see it is a free-text
field from an 11-field generation. Identical failure mode to `dinner` (lost stop) and
`for 2` (wrong group size); both were fixed by unioning the model's answer with a
deterministic read of the raw text.

- In `FreeTextSummaryExtractor.payload(from:shape:occasion:source:)`, scan `source`
  against the covered-area vocabulary and prefer an exact hit over `extracted.area`.
- The vocabulary is **not** a hand-written list — `DistrictVenueProvider` already derives
  covered areas from the JSON and owns the aliases (`CP`, `Gurgaon`, …). That keeps this
  consistent with the no-hardcoding rule.
- Over-capture then becomes harmless: the scan finds `hauz khas` *inside* whatever the
  model returned.

**Invariant to add** (CLAUDE.md requires one per fix): *for every covered area name, a
sentence containing that name resolves to that area regardless of the words around it.*
Quantify over `DistrictVenueProvider`'s covered set — not one test per neighbourhood.

---

## 3. What changed, and why

The through-line: **the boundary was in the wrong place.** The model was doing
*structure* badly (13 fields in one call) while Swift did *semantics* badly (a 63-word
keyword table). The axis is structure vs semantics, not AI vs Swift. They were swapped.

### Phase 1 — the growth path is gone
The reported bug (`12.00 to 5:00 pm … lunch and snacks` planning through to an 8 pm
dinner) was **not** the "snacks" keyword mapping. Root cause: a request collapsing to one
recognised stop reached a *seeded-growth* branch that inflated it to four — inference
performed on top of an explicit request.

- Deleted from `SlotSchedule`: the `.seeded` branch, `grown(from:within:)`,
  `targetStopCount`, `maximumEarlierStops`, `SlotBand.seedsAnOuting`.
- Rule is now two-valued: **named nothing** → default arc; **named anything** → exactly
  that, plus interludes between them.
- `FeasibilityValidator` gained two invariants quantified over all plans:
  `grewBeyondRequest`, `ranPastStatedEnd`.
- Two parser fixes: a `.` between digits is a minute separator (`"12.00"` was parsing as
  *two* clock tokens, the second inheriting the trailing `pm` — producing a 12:00→12:00
  window and an **empty plan**); and `OutingTimeWindow`'s initializer now makes a window
  ending at-or-before its start **unrepresentable**.

### Phase 2 — the spine
`SlotBand` is now anchors (meals) + interludes, with `role` and `isOptIn`. Added
`earlyStart` (06:00–08:00) and `midMorning` (10:30–12:00); breakfast moved to 08:00–10:30.

Interlude count is **computed, never written**:
```swift
interludes = clamp(round(gapMinutes / pace.intervalMinutes), 1, 3)
// unhurried 150 · steady 125 · packed 100
```
gap 270 (lunch→dinner) ⇒ 2 unhurried/steady, **3 packed**. The literal `2` appears
nowhere. `exclusive` ("nothing else") turns the fill off.

### Phase 3 — what the model emits
`OccasionShape { pace, activityBias, groupSeating, arc }` — a third `@Generable` call.
It emits **no time, no count, no stop name**; `pace` feeds the Phase 2 formula, so the
model's read of the mood changes stop count without the model counting anything.
`OccasionProfile` on the brief carries it. Strings not `@Generable` enums (a non-frozen
enum traps on an invented case); `.anyOf` constrains the decoder and `parsedOccasion`
still validates.

### Phase 4 — retrieval replaces the keyword table
- `SemanticVenueRanker` (actor): `NLContextualEmbedding` cosine over each venue's
  `name + tagline + vibeTags`, cached, returns `nil` rather than a wrong opinion when it
  can't load. **Measured 4/5 top-1** over the real dataset on the host.
- `SlotBrief { query, mustSeat, avoid }` generated per slot in `FoundationModelsCurator`;
  ranking feeds `SlotDeckBuilder.build(preferredIndices:)`. Wired into the *deterministic*
  branch too — that's the branch most slots take.
- **Deleted** `categoryKeywords` (63 words), `categoriesNamed`, and the
  `SlotBand.all(in:)` category expansion. `bandKeywords` stays: three meals is a closed
  set, and there will not be a fourth.
- ⚠️ **The Shortcut must be re-imported.** `chat-extraction-prompt.txt` gained `stops` and
  `onlyTheseStops`; until re-imported, a Siri-path request naming an activity rather than
  a meal produces no stop.

### Phase 5 — the golden set is no longer an oracle
`WandrTests/Planning/PlanShapeEvaluation.swift` — Apple's `Evaluations` framework. 26
phrasings as **JSON**, `expected` is `nil` on every sample, scored by five invariants
(`Produced` guardrail, within-stated-end, within-request-span, no-overlap,
named-stops-present) plus a `StopCount` distribution. Adding a phrasing is adding a JSON
object; it cannot bring an expectation with it.

**It found a real bug on its first run.** `withinRequestSpan` came back 0.952:
`"lunch, but we're only free 8 to 9"` is unsatisfiable, so the schedule correctly falls
back to dinner — but my own Phase 1 `grewBeyondRequest` saw a plan outside the lunch span
and **would have failed the whole run**. The one case designed never to dead-end was the
one that always would. Fixed in both places; `anUnsatisfiableRequestIsNotGrowth` pins it.

### Dataset
194 → **320 venues, 5 per (area, category), 16 areas.** Every slot now clears the
curator's `venues.count > minimumCandidatesPerSlot` guard, so the model is reachable
everywhere. Nizamuddin had **0** nightlife and **0** discover before this. All 320 names
and taglines are distinct — templated text would defeat the ranker.

Mock data, authored in the existing style. Real landmarks (Jama Masjid, Chausath Khamba,
Sunder Nursery) are factual; cafés and bars are invented, as the originals were. **Not
real pricing or hours.**

---

## 4. Tests that changed, and why (none were "just stale")

Each of these was passing for a reason that had stopped being true. Worth reading before
touching them.

- **8 golden cases** encoded seeded growth. The *rule* was deleted on instruction; these
  described it. `[.dinner]` for "dinner at saket" is also the final answer under
  anchors+interludes (one anchor ⇒ no gap), so it is not a placeholder.
- **`"lunch and then dinner, nothing else"`** carried `plannedStops: "lunch and dinner"` —
  the words "nothing else" never reached the payload. It asserted Wandr could read a word
  it was never given, and passed only while nothing was ever placed between two stops.
- **`impossibleBudget`** said ₹200, and new street-food entries at ₹100 made it
  *achievable* — a fixture named "impossible" was testing that a plan can be built.
  Lowering it doesn't help either: a **free** qawwali evening (correct data) means no
  budget can leave nightlife empty. It now names Khan Market, where nightlife starts at
  ₹1200. **Keep the area, not just the number.**
- **`uncoveredAreaFailsHonestly`** asserted the message omits "Noida" — true only while
  Noida was uncovered. Now asserts it omits the host's *own* word (`Faridabad`), which is
  what the comment always claimed.
- **Mapper tests** now assert both halves — with the model's classification and without —
  so the degradation is pinned rather than hidden.

---

## 5. Environment landmines (all verified by probe this session)

- **`Evaluations` exists.** A plain `-sdk` probe reports `no such module` because it is a
  *Developer* framework under `Platforms/*/Developer/Library/Frameworks`, beside XCTest.
  It links into a test target with **no build-setting changes**. `HANDOVER.md` §10 and the
  old test header both recorded the false conclusion from the bad probe.
- **`containsColumn` needs `import TabularData`** explicitly (`MemberImportVisibility`).
- **`SystemLanguageModel` is available in the Simulator** — it runs live inference against
  the host Mac's model. The claim that it can't is wrong on Xcode 27.
- **`NLContextualEmbedding` fails in the Simulator**, and deceptively:
  `hasAvailableAssets` returns **`true`** while `load()` throws. The real error is a
  sandbox permission, not a missing asset:
  ```
  Failed to load embedding from MIL representation: filesystem error:
    in create_directories: Permission denied ["/var/db/com.apple.naturallanguaged/com.apple.e5rt.e5bundlecache"]
  ```
  A skip-gate built on the flag alone does not skip — it runs the test and fails it. Gate
  on an actual `load()` attempt.
- **Mean-centering embeddings made ranking worse**: spread ×6, ordering inverted (raw 4/5,
  centred 1/5). With a small corpus the centroid measures distance-from-typical. Don't
  re-try it; the note is in `SemanticVenueRanker.vector(for:using:)`.
- **SourceKit noise**: single-file diagnostics constantly report "Cannot find type
  'SlotCategory'" etc. Ignore them; verify with a real compile.

---

## 6. Known limitations — stated, not hidden

- **Interlude *supply* is still fixed.** The count is derived, but the band table defines
  only two interlude rows between lunch and dinner, so `packed` cannot produce its third
  stop there. Finishing this means interlude identity becoming `(gap, ordinal)` with
  windows split from the gap, instead of enum cases — a type change across `SlotBand`,
  `CurationSlot`, `SlotID` and the poll.
- **`OccasionShape.arc` and `activityBias` are not wired into ranking.** So "first date,
  ₹2000" surfacing a ₹450 counter is not currently a bug — budget is a ceiling and nothing
  says a celebration should spend nearer it. Making it so is a product change.
- **The old `PlanShapeEvaluationTests` still exists** alongside the new evaluation.
  Deleting it is the actual "retire" step, deliberately not done in the same change that
  added its replacement.
- **`PlanShapeEvaluation.subject(from:)` runs the deterministic half only.** Pointing it at
  the live extractor is now possible and is the obvious next step.
- **Semantic ranking is device-only** (§5), and reorders 5 candidates into a deck wanting
  3–5, so differences between similar prompts will be subtle.
- No meal-time tagging in the dataset — a breakfast slot draws the same `.food` pool as
  dinner. `openWindow` is a label and is not matched.

---

## 7. Method notes

`CLAUDE.md` §1 exists because of a real pathology here, and it bit twice this session:

- **Verify before asserting absence.** Two "this isn't available" claims in the repo were
  both wrong, and both had cost real design decisions. The compile probe outranks recall
  *and* outranks the previous session's notes.
- **Reach for the log earlier.** Three hypotheses about the area bug were wrong
  (extraction dropping it, the fake extractor, a stale build). One `settled=[…]` line and
  one screenshot settled it. Symptom-based theorising was slower than looking.
- **A changed oracle needs a written reason.** Where expectations moved, the file says why
  it was a deleted *rule* rather than a moved goalpost. Keep doing that.
