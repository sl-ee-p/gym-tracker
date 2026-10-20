# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

PlateLog (Dart package `gym_app`, Android application ID `com.slp.platelog`) is a Flutter workout-tracking app (SQLite-backed, offline-first, Android + iOS). It tracks exercises, workout sessions/sets, body weight, progress charts/analytics, and includes an Android home-screen heatmap widget and rest-timer notifications.

## Commands

- Install deps: `flutter pub get`
- Run app: `flutter run`
- Static analysis: `flutter analyze`
- Run full test suite: `flutter test`
- Run a single test file: `flutter test test/path/to/file_test.dart`
- Build Android release (Play upload): `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`
- Regenerate icons: edit and run `tool/make_icon.py` (needs Pillow + numpy), then `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`. `assets/icon/play_store_512.png` is the Play Store listing icon.

No CI is configured — run `flutter analyze` and `flutter test` locally before considering a change done. There is no mocking library in the project; data-layer tests use real SQLite via `sqflite_common_ffi` instead of mocking the database.

## Architecture

### Layering

UI (`screens/`, `widgets/`, `dialogs/`) → Provider (`ChangeNotifier` state) → Repository (`services/*_repository.dart`) → `DatabaseHelper` (`lib/services/database_helper.dart`, sqflite) → SQLite.

- `DatabaseHelper` is a singleton owning generic CRUD, schema creation/migration, and full-data export/clear. Table-specific repositories (`WorkoutRepository`, `ExerciseRepository`, `WeightRepository`, `WorkoutTemplateRepository`, `MeasurementRepository`) wrap it and encode domain rules that don't belong in the generic layer (e.g. refusing to delete a category still referenced by exercises, cascading set deletes on workout delete — since real FK enforcement is deliberately off).
- Four `ChangeNotifier` providers are registered in `main.dart`'s root `MultiProvider`: `UserProvider` (profile/settings/theme), `ExerciseProvider` (library + categories), `WorkoutProvider` (active workout + history + templates), `ProgressProvider` (charts/analytics/heatmap data). `RestTimerController` is also root-registered (not "Provider"-suffixed by convention, since it owns behavior/a ticker rather than loaded data) so the rest timer survives tab navigation.
- App startup (`lib/main.dart`): `AppInitializer` awaits `UserProvider.initialize()` first (the other providers need its persisted date range/settings), then loads `ExerciseProvider`/`WorkoutProvider`/`ProgressProvider` in parallel, fires notification init and the home-widget refresh unawaited, then removes the native splash screen.

### Database migrations (`lib/services/database_helper.dart`)

Schema is versioned (`_databaseVersion`); `_onUpgrade` uses a chain of non-exclusive `if (oldVersion < N)` blocks so a device several versions behind replays every intermediate `_upgradeToVN`. Each `_upgradeToVN` is append-only and must never be edited after shipping — `_createTables` always reflects the current fresh-install schema. Foreign keys are never enforced (`PRAGMA foreign_keys` stays off), so cascading deletes are handled explicitly in the repository layer. `test/database_migration_test.dart` freezes each prior schema version as literal SQL and must never be edited to match later schema changes — see the doc comment at the top of `database_helper.dart` for the exact checklist to follow when bumping the schema version.

### Native platform integration

- Android home-screen widget: `HomeWidgetService` (`lib/services/home_widget_service.dart`) renders the app's own heatmap painter off-tree to a PNG (`home_widget` package) and pushes it plus theme colors to `HeatmapWidgetProvider.kt` (`android/app/src/main/kotlin/com/slp/platelog/HeatmapWidgetProvider.kt`), which tints a native card around the bitmap. There is no iOS equivalent.
- Rest timer notifications: `NotificationService` (`lib/services/notification_service.dart`) schedules an OS alarm for when the app is backgrounded and shows an ongoing, controllable notification (Pause/Resume/±15s). Background button taps run on a separate isolate with no app memory access and forward the action id via `IsolateNameServer`/`SendPort` back to the live isolate, where `main.dart` maps it onto `RestTimerController` calls. The same service schedules the weekly workout/weigh-in reminders (`syncReminders`, driven by `UserProvider`) as repeating wall-clock notifications, which is why `flutter_timezone` sets `tz.local` at init.
- Personal records ("New best") use the rep rule in `lib/utils/personal_records.dart`: a set is a record if no earlier non-warm-up set had both ≥ weight and ≥ reps. The v8 migration has a frozen copy of that rule for its backfill; change the live rule there, never the migration.

### Constraints worth knowing before touching dependencies or Android build config

- `flutter_body_atlas` (muscle map) sets the Flutter/Dart SDK floor (`flutter: ">=3.38.0"`, `sdk: ^3.13.2` in `pubspec.yaml`) — this is what pulled the whole Android toolchain forward (AGP, compileSdk, Kotlin/Java 17). Don't lower it without checking that package's requirement.
- `android/build.gradle` forces every subproject's `compileSdk` up to a floor via an `afterEvaluate` hook, because `media_store_plus` hardcodes an old `compileSdkVersion`. `targetSdk` is 36 (Google Play's floor), which enforces edge-to-edge on Android 15+: pushed screens pass `SystemNavBarSpacer` as `bottomNavigationBar` so content clears the system nav bar, and bottom sheets must pad by `MediaQuery.paddingOf(context).bottom` (or use `SafeArea`). Tab screens are covered by the shell's `NavigationBar`.
- Release builds are signed with the upload key from `android/key.properties` + `android/app/upload-keystore.jks` (both gitignored; never commit them). Without those files the build silently falls back to debug signing, which Play rejects.

## Existing documentation

`docs/codebase/*.md` (`ARCHITECTURE`, `CONCERNS`, `CONVENTIONS`, `INTEGRATIONS`, `STACK`, `STRUCTURE`, `TESTING`) is a hand-maintained snapshot, mostly dated May 15 with `CONCERNS.md` updated Sept 4. Several claims are now stale versus the current `pubspec.yaml`/test suite (dependency versions, SDK floor, "no unit tests exist"). Treat it as directional history, not ground truth — prefer reading the current code. `docs/codebase/CONCERNS.md` still lists open product decisions worth checking with the user before assuming an answer: whether local data should be encrypted at rest, the required export format, whether "Clear All Data" should preserve profile/settings, and whether iOS branding/bundle ID (`com.example.gymApp`) should be unified with Android.

## Conventions

- snake_case file names, lowerCamelCase methods, PascalCase types; relative imports within `lib/`.
- Errors are surfaced via `debugPrint` + `SnackBar`, not exceptions bubbling to a global handler.
