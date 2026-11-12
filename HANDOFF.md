# Handoff: progressive-overload coach (`feature/coach`)

Spec: `docs/COACH.md`.

## Done
- **C0:** gen-l10n scaffold (English ARB only, `supportedLocales` [en]), `docs/COACH.md`, `CLAUDE.md` note, version 1.1.0+12.
  - Checked on the a16 emulator: debug build launches, Home and Exercises render, no Flutter errors.

## Not verified
- Italian layout: no IT ARB, by the owner's decision.
- Pro gating: deferred until `feature/pro-unlock` merges.

## Next
- **C1:** pure engine in `lib/coach/` + table-driven tests. Recommended effort: high.

## Emulator notes
- a16 now runs the **debug** build (version 1.1.0).
- The earlier release-signed install was uninstalled, because the signatures differ. Its data was saved first to `~/scratch/platelog-coach/emu-data-before-coach.tar`, and its `gym_tracker.db` (the owner's history) was pushed back as root.
