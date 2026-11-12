# Progressive-overload coach

The coach reads an exercise's logged history and does four things. It estimates the 1RM trend and suggests the next session's weight and reps. It also flags stalls and recommends a deload. All of it is pure maths on existing data: there is no schema change, and the coach stores no state.

Status: in progress on `feature/coach`. Milestones are listed at the end.

## Progression rules (v1, tunable by the backtest)
All maths works on **completed** workouts only. A **working set** is non-warm-up, weight > 0, reps ≥ 1; partial reps are ignored. Sessions with an exercise = "exposures". Weights are computed in kg and rounded in the **display unit**.

### 1. Rep range (learned per exercise)
- **Top:** `hi` = the 75th percentile of the top set's reps over the last 8 exposures.
- **Bottom:** `lo` = `hi − max(2, round(0.2·hi))`.
- Example: a lift whose top set usually lands at 7–8 reps gets **6–8**; one at 14–16 gets **13–16**.
- **Fallback:** 8–12 when there are fewer than 3 exposures.

### 2. Top set and fragments
- The **top set** is the first set at the heaviest weight whose reps are ≥ ⌈lo/2⌉.
- Sets below ⌈lo/2⌉ reps at a lower weight are **fragments**. They are ignored for decisions.

### 3. 1RM and trend
- **Session e1RM** = max Epley over working sets. Taking the max makes fatigued fragments harmless automatically.
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

- **Big relative jumps:** if one step is more than 10% of W (light dumbbells, small cables), extend `hi` by 4 ("add reps first").
- **Shown as:** top set plus the 2nd-set target, e.g. "92.5 kg × 6–8, then × 6+".

### 5. Increments and rounding
- **Plate-loaded** (`usesPlateCalculator`):
  - Step = 2 × the smallest plate (2.5 kg / 5 lb).
  - Round **down** to the nearest weight the bar (`barWeightKg ?? defaultBarWeightKg`) can load, using `PlateCalculator`.
- **Machine, cable or dumbbell:**
  - Step = the **learned** step: the most common gap between the adjacent distinct weights this exercise used. Converted to the display unit and snapped to {1, 1.25, 2, 2.5, 5} kg or {2.5, 5, 10} lb.
  - Default when there are fewer than 3 distinct weights: 2.5 kg / 5 lb.
  - The grid is **anchored on a weight actually used**, so 16/18/20 dumbbells and odd stacks stay reachable.
- **lb users:** history is converted to lb before learning the step, so suggestions land on lb-loadable weights.

### 6. Stall
- **Definition:** **4 consecutive exposures** where the best value (e1RM or index) gains ≤ 0.5% over the best of the 12 weeks before them.
- **Scope:** only exposures within the last 8 weeks count.
- **Grace:** the counter resets at a deload and at a long layoff (rule 8), with a 3-exposure grace period after either.
- **UI:** the status chip shows "Stalled".

### 7. Deload
- **Trigger** (either):
  - a stall, or
  - **regression:** 2 consecutive exposures ≥ 5% below the best of the last 6 weeks.
- **Size:** −10% of W, rounded **down** to loadable. Same sets, target `lo` reps, with the instruction "leave 2–3 reps in the tank".
- **Length:** 1 exposure if the exercise is trained ≤ 1×/week, 2 if more often (about a week either way).
- **Detection is stateless:** an exposure counts as a deload if its top weight is ≤ 92.5% of the median top weight of the previous 4 exposures, while a stall or regression was active. This survives backup and restore, and needs no schema change.
- **Resume:** the next suggestion is pre-deload W − 1 step, then normal double progression. The stall counter restarts with the 3-exposure grace.

### 8. Edge cases
| Case | Behaviour |
|---|---|
| 0 exposures | Empty state: "Log a session to get suggestions" |
| 1–2 exposures | "Building your baseline (n of 3)"; suggestion = repeat W, R+1; no trend or stall |
| New exercise | Same as 1–2 exposures |
| Gap > 14 days | Suggestion −5% (rounded); reason says "welcome back" |
| Gap > 28 days | Suggestion −10%; stall/regression window resets |
| Unit changed | Nothing stored per unit: history is kg, and the step and grid are re-derived in the new unit |
| Not weight × reps (time-based, unweighted, reps off) | Card says the coach covers weight × reps exercises only; no workout row |
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
- [ ] C1
- [ ] C2
- [ ] C3
- [ ] C4
- [ ] C5

Validation data stays outside the repo. The backtest reads a backup path given on the command line and writes its report to `~/scratch/coach-backtest/`, because the report contains personal training data.

## Extras (suggestions, not in scope)
- **RPE-aware tweak:** RPE ≤ 7 at `hi`−1 → allow adding weight.
- **Per-exercise rep-range override.**
- **Coach line on the Progress tab.**
- **Weekly "coach digest" on Home.**
