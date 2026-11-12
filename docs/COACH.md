# Progressive-overload coach

The coach reads an exercise's logged history and does four things. It estimates the 1RM trend and suggests the next session's weight and reps. It also flags stalls and recommends a deload. All of it is pure maths on existing data: there is no schema change, and the coach stores no state.

Status: built on `feature/coach` (C0–C5), not merged. Free for now; see Free vs Pro for the gating follow-up.

## Progression rules (v1, tunable by the backtest)
All maths works on **completed** workouts only. A **working set** is non-warm-up, weight > 0, reps ≥ 1; partial reps are ignored. Sessions with an exercise = "exposures". Weights are computed in kg and rounded in the **display unit**.

### 1. Rep range (learned per exercise)
- **Top:** `hi` = the 75th percentile (nearest rank) of the top set's reps over the last 8 exposures.
- **Bottom:** `lo` = `hi − max(2, round(0.2·hi))`.
- Example: a lift whose top set usually lands at 7–8 reps gets **6–8**; one at 14–16 gets **13–16**.
- **Fallback:** 8–12 when there are fewer than 3 exposures.

### 2. Top set and fragments
- **Fragments** are sets with fewer than half the session's best reps (fatigued back-offs and failed tail sets). They are ignored everywhere.
- The **top set** is the first remaining set at the session's heaviest weight. The **2nd set** is the next remaining set at that weight.
- A session whose top weight is ≤ 92.5% of the median top weight of the previous 4 sessions is **light**. It is a deload if one was due. Otherwise a **one-off** light session is ignored and suggestions build on the session before it. Two light sessions in a row are the new normal and are not ignored. Because the median includes light sessions, a deliberate drop in weight stops counting as light after a couple of sessions.

### 3. 1RM and trend
- **Session e1RM** = max Epley over working sets. This is what the trend chart shows.
- **Session score** = the mean e1RM of the two best sets. Stall and regression use the score, so 2nd-set rep gains (how a double progression moves) count as progress. A one-set session of a lift usually done for 2+ sets has no score, because its single set would beat every normal session's average.
- **If `hi` ≤ 12:** show the e1RM in kg/lb, using the existing helper with its 12-rep cap.
- **If `hi` > 12:** the existing helper deliberately refuses estimates. So:
  - Track a relative **strength index** (Epley allowed up to 20 reps), used only for the trend and stall maths.
  - The card shows the **best set** and a **% trend**, not a fake 1RM.
- **Trend line:** session values plus a 3-exposure moving average. The headline shows the change vs about 4 weeks ago.

### 4. Next-session suggestion (double progression)
Take the last exposure's top weight W and top reps R, plus R2 = reps of the 2nd set at W (if any):

| Last exposure | Suggestion |
|---|---|
| R ≥ hi and (R2 ≥ hi−1 or no 2nd set) | **Add weight:** W + 1 step, target `lo`–`hi` (2 steps if R ≥ hi+3) |
| R ≥ hi, but R2 < hi−1 | **Hold W:** 2nd set target R2+1 |
| lo ≤ R < hi | **Hold W:** target R+1 |
| R < lo, once | **Hold W:** target `lo` |
| R < lo on 2 exposures in a row | **Step back** 1 step, target `hi`−1 |

- **Big relative jumps:** if one step is more than 12.5% of W (light dumbbells, small cables), extend `hi` by 4 ("add reps first").
- **Shown as:** top set plus the 2nd-set target, e.g. "92.5 kg × 6–8, then × 6+".

### 5. Increments and rounding
- **Plate-loaded** (`usesPlateCalculator`):
  - Step = 2 × the smallest plate (2.5 kg / 5 lb).
  - Round **down** to the nearest weight the bar (`barWeightKg ?? defaultBarWeightKg`) can load, using `PlateCalculator`.
- **Machine, cable or dumbbell:**
  - Step = the **learned** step: the most common gap between the adjacent distinct weights this exercise used in the last 12 weeks (ties go to the smaller gap). Converted to the display unit and snapped to {1, 1.25, 2, 2.5, 5} kg or {2.5, 5, 10} lb.
  - Default when there are fewer than 3 distinct weights: 2.5 kg / 5 lb.
  - The grid is **anchored on a weight actually used**, so 16/18/20 dumbbells and odd stacks stay reachable.
- **lb users:** history is converted to lb before learning the step, so suggestions land on lb-loadable weights.

### 6. Stall
- **Definition:** the best score of the **recent block** of sessions is no more than 0.5% above the best score of the **block before it**.
  - A block covers the last 21 days (so it holds more sessions for lifts trained more often) and never fewer than 5 sessions.
  - Both blocks must fall inside the current comparison window.
- **Window restarts** after a deload and after any break that earns a "welcome back" cut (rule 8). The first session of a window is its baseline.
- **No deload call within 14 days of a light session:** the lifter already backed off.
- **No deload call while the top of the range is being hit:** if the suggestion is "add weight", the lifter needs more load, not a deload.
- **UI:** the status chip shows "Stalled", and the session count shown is the number of sessions since the last new best.

### 7. Deload
- **Trigger** (either):
  - a stall, or
  - **regression:** 2 consecutive sessions whose scores are ≥ 5% below the best of the last 6 weeks, at the **same weight** as that best session. Lighter sessions score lower by design. A failed attempt at a heavier weight is handled by the rep rules (hold, then step back).
- **Size:** −10% of W, rounded **down** to loadable. Same sets, target `lo` reps, with the instruction "leave 2–3 reps in the tank".
- **Length:** 1 session if the exercise was trained ≤ 4 times in the previous 28 days, otherwise 2 (about a week either way).
- **Detection is stateless:** a light session (rule 2) that comes while a stall or regression is active is a deload. This survives backup and restore, and needs no schema change.
- **Resume:** the next suggestion is pre-deload W − 1 step, then normal double progression in a fresh window.

### 8. Edge cases
| Case | Behaviour |
|---|---|
| 0 exposures | Empty state: "Log a session to get suggestions" |
| 1–2 exposures | "Building your baseline (n of 3)"; suggestion = repeat W, R+1; no trend or stall |
| New exercise | Same as 1–2 exposures |
| Break > max(14 days, 2× the usual gap between sessions) | Suggestion −5% (rounded down); reason says "welcome back"; any deload call is dropped (the break was the deload) and the stall window restarts |
| Break > max(28 days, 4× the usual gap) | Suggestion −10% instead |
| Unit changed | Nothing stored per unit: history is kg, and the step and grid are re-derived in the new unit |
| Not weight × reps (time-based, unweighted, reps off) | Card says the coach covers weight × reps exercises only; no workout row |
| Working weights all below 1 kg (bodyweight logged as 0.1 kg) | Status `unsupported`, same as above |
| Sets of deleted exercises, in-progress workout | Ignored |
| RPE | Not used in v1 (only 200 sets). Listed as an extra |

### 9. "Why" explanations
The engine returns **reason codes + numbers** (e.g. `hitTopOfRange{w, r, hi, step}`), never text. The UI maps them to ARB strings, so the pure layer stays text-free and translatable later.

## UX
- **Exercise details → Coach card**, the first section above Instructions:
  - **Header:** "Coach", with a status chip: Progressing / Holding / Stalled / Deload.
  - **Headline number:** e1RM (or best set) with its 4-week delta.
  - **Sparkline:** `fl_chart` `LineChart`, minimal, last 12 exposures + moving average, theme colours in light and dark.
  - **"Next session" block:** weight × reps, a one-line reason, and "Rep range 6–8 · learned from your history".
  - **Empty state:** baseline progress dots (n of 3).
  - **Loading state:** a same-height placeholder, so the layout doesn't jump.
- **Workout screen → suggestion row**, above each exercise's `SetInputForm`:
  - It reads, e.g., "Coach · 92.5 kg × 6–8".
  - **Use** fills the weight and reps fields, which is the user's explicit accept. The row then shows the next-set target.
  - **Not now** hides the row for this workout (in memory).
  - **Why?** opens a bottom sheet with the reasons + sparkline.
- **Stall/deload banner:** shown in that row, tinted (`tertiaryContainer`):
  - Wording: "Stalled 4 sessions · Deload suggested: 80 kg × 6, easy".
  - Buttons: **Start deload** (switches the row's targets to the deload values) and **Not now**.
  - The same state shows as the chip and a line on the coach card.
- **Visuals:** existing tokens only (`AppSpacing`, `AppRadius`, `NumericTextStyles`, colour scheme roles), no new colours. Bottom sheets pad by `MediaQuery.paddingOf(context).bottom`.

## Free vs Pro
- Free for now, on `main`, as decided.
- **Follow-up when Pro merges** (recorded in docs, not built now):
  - add `ProFeature.coach` and wrap the details card in `ProGate`
  - free users simply don't see the workout row, which honours MONETIZATION.md's "no paywall on the active workout screen"

## Architecture and files
- **`lib/coach/`** (pure Dart, no Flutter imports):
  - `coach_models.dart`: `CoachSet`, `CoachExposure`, `CoachSuggestion`, `CoachStatus`, `CoachReason`.
  - `load_grid.dart`: learned step, snapping, plate rounding via `PlateCalculator`.
  - `progression_engine.dart`: `CoachReport analyze(exposures, CoachConfig, {required DateTime now, required String unit})`.
  - All thresholds go in `CoachConfig`, so the backtest can tune them.
- **`lib/services/coach_service.dart`:** maps `getExerciseProgressData` rows → exposures and returns a `CoachReport` per exercise.
- **`lib/providers/coach_provider.dart`:**
  - A per-exercise cache, invalidated when a workout completes or sets change.
  - Registered in `main.dart`.
  - Holds the in-memory "Not now" / "Start deload" state.
- **UI:**
  - `lib/widgets/coach/coach_card.dart`, `coach_sparkline.dart`, `coach_suggestion_row.dart`, `coach_why_sheet.dart`.
  - Hooks in `exercise_details_screen.dart` and `workout_screen.dart`, with `SetInputForm` gaining a small "apply values" entry point (key/controller), the only change to it.
- **l10n:**
  - `l10n.yaml` (arb-dir `lib/l10n`, template `app_en.arb`).
  - `flutter_localizations` + `generate: true` in pubspec.
  - `localizationsDelegates`/`supportedLocales: [en]` in `MaterialApp`.
  - Only the coach's strings, with `@key` placeholder metadata. No `app_it.arb`.
- **Backtest:**
  - `tool/coach_backtest.dart`, a pure Dart CLI that takes a backup path as an argument.
  - It replays each scored exposure from only the prior history.
  - Its report is written **outside the repo** (`~/scratch/coach-backtest/report.md`), so personal training data is never committed.
- **Tests:** `test/coach/*_test.dart`, table-driven (`for (final c in cases) test(c.name, …)`) covering:
  - normal progression
  - hold
  - step back
  - stall
  - deload trigger, length and resume
  - sparse data (0/1/2 exposures)
  - layoffs of 15 and 30 days
  - lb rounding
  - plate vs stack vs dumbbell grids
  - fragments ignored
  - high-rep index mode

  Plus widget tests for the card states and the Use/Not now row, and a service test on real SQLite (ffi).
- **Docs:** `docs/COACH.md` (these rules, kept current, plus the Pro follow-up), a short `CLAUDE.md` note (coach module + l10n), and `HANDOFF.md` if the session runs short.

## Milestones (branch `feature/coach` off `main`, commit and push after each)
| # | Content | Effort |
|---|---|---|
| C0 | Branch, `docs/COACH.md` rules, l10n scaffold (EN ARB, delegates), app still runs | low |
| C1 | Pure engine + table-driven tests | **high** |
| C2 | Backtest on the Oct 20 backup, tune `CoachConfig`, report the agreement + wrong-looking cases, **pause for review** | **high** |
| C3 | Service + provider + Coach card (sparkline, empty/loading, light/dark) + why sheet | medium |
| C4 | Workout suggestion row, Use / Not now, deload banner | medium |
| C5 | DoD wrap-up: full suite, fresh debug APK, screenshots, version **1.1.0+12**, docs, push | low |

The backtest's metrics, per exposure in 20 Jul–20 Oct:
- **decision agreement:** add / hold / back off vs what was actually lifted
- **weight:** exact, and within 1 step
- **reps:** top-set reps within ±1
- **calls:** every stall/deload call next to what was done over the following 2 exposures

Progress:
- [x] C0: l10n scaffold + this document
- [x] C1: pure engine (`lib/coach/`) + table-driven tests (`test/coach/`)
- [x] C2: backtest (`tool/coach_backtest.dart`) + tuning (see Validation)
- [x] C3: CoachService, CoachProvider, Coach card on Exercise details, "Why?" sheet
- [x] C4: workout-screen row (Use / Not now / Why?), set-2 target, deload offer (Start deload / Not now)
- [x] C5: wrap-up: analyze, full suite, emulator screenshots (light, dark, 2× font), 1.1.0+16

## Validation (C2)

Run: `dart run tool/coach_backtest.dart <backup.json> <report.md> [from] [to]`. Each scored session is predicted from earlier history only. Aggregate results on the owner's own logs:

| Window | Scored sessions | Decision agrees | Weight exact | Weight within 1 step | Deload episodes |
|---|---|---|---|---|---|
| Tuning: 20 Jul–20 Oct (backup of 20 Oct) | 235 | 58% | 51% | 88% | 1 (the one clear plateau) |
| Unseen: 21 Oct–11 Nov (backup of 11 Nov) | 71 | 49% | 48% | 93% | 0 |

- **Low exact agreement is mostly the lifter's own inconsistency.** The same situation gets "add" one week and "hold" the next.
- **When the lifter did go up, it worked.** Where the coach said "add weight" and the lifter went up, they still hit the bottom of the rep range 96% (tuning) and 100% (unseen) of the time. They also hit it 95–100% of the time when they went up after "climbing reps".
- **Rule changes from the backtest:**
  - stall = block versus block, not session versus a 12-week peak
  - the stall score counts the 2nd set
  - breaks scale with training frequency, and a break cancels any deload call and restarts the stall window
  - only one-off light sessions are ignored
  - regression requires the same weight
  - no deload while "add weight" applies
  - placeholder weights are unsupported
  - after review: the minimum stall block is 5 sessions, and no deload is called within 14 days of a light session. On the unseen window, 4 calls (1 false alarm, 3 early) became 0, while the real plateau in the tuning window was kept.

Validation data stays outside the repo. The backtest reads a backup path given on the command line and writes its report to `~/scratch/coach-backtest/`, because the report contains personal training data.

## Extras (suggestions, not in scope)
- **RPE-aware tweak:** RPE ≤ 7 at `hi`−1 → allow adding weight.
- **Per-exercise rep-range override.**
- **Coach line on the Progress tab.**
- **Weekly "coach digest" on Home.**
