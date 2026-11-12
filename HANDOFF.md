# Handoff: progressive-overload coach (`feature/coach`)

Spec: `docs/COACH.md`.

## Done
- **C0:** gen-l10n scaffold (English ARB only, `supportedLocales` [en]), `docs/COACH.md`, `CLAUDE.md` note, version 1.1.0+12.
  - Checked on the a16 emulator: debug build launches, Home and Exercises render, no Flutter errors.

- **C1:** pure engine `lib/coach/` (`coach_models.dart`, `load_grid.dart`, `progression_engine.dart`) + 47 table-driven tests in `test/coach/`. Version 1.1.0+13.
  - Rules refined while testing, now reflected in `docs/COACH.md`: the first session of a window is a baseline; regression only counts at the same or a lighter weight.
  - No UI yet, so there was nothing to check on the emulator.

- **C2:** `tool/coach_backtest.dart` + tuning. Reports are in `~/scratch/coach-backtest/` (personal data, not in the repo). Backups used: the 20 Oct one and the owner's 11 Nov upload (`data/`). Aggregate results in `docs/COACH.md` § Validation. Version 1.1.0+14.
  - **Paused for the owner's review** of the agreement + wrong-looking cases before the UI.

- **C3:** `CoachService` + `CoachProvider` (refreshed by a proxy provider on workout/unit changes) + Coach card on Exercise details + "Why?" sheet. Version 1.1.0+15.
  - Checked on a16 with the owner's 11 Nov backup and a demo copy that adds a stalled exercise (`~/scratch/coach-backtest/demo/`): progressing, stalled + deload, baseline, empty, Why sheet; light, dark, 2× font. Screenshots in `build-logs/c3-*.png` (gitignored).
  - The emulator currently holds the **demo** data. The owner's real data is in the app's pre-restore copy under Downloads/PlateLog and in `~/scratch/coach-backtest/data/`.

- **C4:** `CoachSuggestionRow` inside `SetInputForm` through a new optional `suggestionBuilder` (the form still never fills itself; only "Use" fills it). Top-set target, then set 2. "Not now" hides it per workout; a stall offers a deload; "Start deload" switches the targets.
  - On a16: Use fills 92.5 kg × 8, the set-2 target follows, the deload offer and started deload work (light, dark, 2× font).
  - TalkBack label: "Fill in 92.5 kg for 8 reps".
- **C5:** version 1.1.0+16, docs updated.

- **Release (2026-11-12):** AAB 1.1.0+16 built from `feature/coach` and copied to `~/platelog-1.1.0-16.aab`.
  - Signed with the upload key (SHA-256 80:E6:92:…:FE:52); the R8 mapping is bundled.
  - Permissions are identical to +11, with no INTERNET.
  - x86_64 release smoke test on a16 with the owner's restored backup: Coach card, workout row and Use all work, with no errors.

## Not verified
- Italian layout: no IT ARB, by the owner's decision.
- Pro gating: deferred until `feature/pro-unlock` merges.

## Next
- The owner reviews the feature on a device. Merge `feature/coach` only when asked.
- When `feature/pro-unlock` merges: add `ProFeature.coach`, wrap `CoachCard` in `ProGate`, and hide `CoachSuggestionRow` for free users (no paywall on the workout screen).
- Extras proposed in `docs/COACH.md`: RPE tweak, per-exercise rep-range override, Progress-tab line, weekly digest.
- Emulator state: a16 runs the x86_64 **release** build with the owner's real 11 Nov backup and an in-progress test workout (Chest Press, no sets). Discard it before reusing the emulator.

## Emulator notes
- a16 now runs the **debug** build (version 1.1.0).
- The earlier release-signed install was uninstalled, because the signatures differ. Its data was saved first to `~/scratch/platelog-coach/emu-data-before-coach.tar`, and its `gym_tracker.db` (the owner's history) was pushed back as root.
