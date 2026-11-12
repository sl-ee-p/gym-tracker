# Handoff: progressive-overload coach (`feature/coach`)

Spec: `docs/COACH.md`.

## Done
- **C0:** gen-l10n scaffold (English ARB only, `supportedLocales` [en]), `docs/COACH.md`, `CLAUDE.md` note, version 1.1.0+12.
  - Checked on the a16 emulator: debug build launches, Home and Exercises render, no Flutter errors.

- **C1:** pure engine `lib/coach/` (`coach_models.dart`, `load_grid.dart`, `progression_engine.dart`) + 47 table-driven tests in `test/coach/`. Version 1.1.0+13.
  - Rules refined while testing, now reflected in `docs/COACH.md`: the first session of a window is a baseline; regression only counts at the same or a lighter weight.
  - No UI yet, so there was nothing to check on the emulator.

## Not verified
- Italian layout: no IT ARB, by the owner's decision.
- Pro gating: deferred until `feature/pro-unlock` merges.

## Next
- **C2:** `tool/coach_backtest.dart` on the Oct 20 backup, tune `CoachConfig`, report to the owner and pause. Recommended effort: high.

## Emulator notes
- a16 now runs the **debug** build (version 1.1.0).
- The earlier release-signed install was uninstalled, because the signatures differ. Its data was saved first to `~/scratch/platelog-coach/emu-data-before-coach.tar`, and its `gym_tracker.db` (the owner's history) was pushed back as root.
