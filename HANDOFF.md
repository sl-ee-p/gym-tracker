# Handoff: coach feedback (`feature/coach-feedback`, off `feature/coach`)

Plan: on/off switch, ratings that teach the coach, clearer explanations. Rules in `docs/COACH.md` § 8b.

## Done (1.2.0+17, pushed, not merged)
- **F1:** Settings → Workout → Coach switch (on by default). Schema v10: `user_profiles.coachEnabled` and `coach_feedback` (one rating per workout and exercise, in JSON backups, removed with its workout and by Clear All Data).
- **F2:** `ProgressionEngine.analyze(feedback:, prior:)`:
  - turns the ratings into a calibration from −2 to +2;
  - easing off and pushing change the add-weight and step-back thresholds;
  - the last session's rating acts directly.
  - With no feedback, the backtest reports for both windows are byte-identical to before.
- **F3:** "How did 92.5 kg × 6–8 feel?" with Too easy / About right / Too hard in the workout row after the first working set. The answer collapses to "Noted · Change". Deloads are not rated.
- **F4:** the Why sheet's "What the coach learned" section and the card's "Tuned to your ratings" line. A rating-driven one-miss step back says so (`missedEaseOff`), and the rating's reason replaces the reason of the rule it overrode.
- **F5:**
  - `flutter analyze`: only the 8 earlier infos remain, in untouched files.
  - Full suite: 470 tests pass.
  - Device check on a16 with a fresh x86_64 debug APK:
    - the owner's real v9 database upgraded to v10, with data intact;
    - rated Bayesian Curls "too hard", and the row was saved;
    - the rating survived reopening the workout;
    - Change reopened the chips in dark mode at 2× font, where they wrap;
    - after completing the workout, the card held at 17.5 kg × 13–16 with "Tuned to your ratings", and the Why sheet explained it;
    - Coach off hid the card and the row; turning it back on restored them.
  - Screenshots are in `build-logs/f5-*.png` (gitignored).

## Not verified
- Backup → restore of `coach_feedback` on a device. It is covered by unit tests only: `dataTables` export/import plus the migration test.
- Italian: English ARB only, by the owner's earlier decision.
- Release/AAB build: not built. The last AAB is 1.1.0+16.
- The "learns without a rating" idea was dropped. A rating is adjusted by what was logged, but sessions without a rating teach nothing.

## Emulator state
- a16 runs the **debug** 1.2.0+17 build with the owner's real data, plus the test workout 96, now completed (Bayesian Curls 17.5 kg × 16, rated too hard).
- The release install's data from before this session is in `~/scratch/coach-feedback/emu/release-1.1.0-data.tar` (v9 database).

## Seen, not changed
- The "Set added successfully!" snackbar, which has a Start Rest Timer action, stays on screen until it is swiped or acted on, even across screens. This predates this branch.

## Next
- The owner tries it on a device. Merge `feature/coach` + `feature/coach-feedback` only when asked.
- The Pro gating follow-up is unchanged (see `docs/COACH.md` § Free vs Pro).
- Possible extra: a per-exercise "Reset what the coach learned" action.
