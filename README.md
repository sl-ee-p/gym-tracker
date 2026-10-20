# PlateLog

An offline-first workout tracker built with Flutter. Log exercises, sets and body weight, follow your progress with charts and analytics, and keep everything on your own device in a local SQLite database. No account, no server.

Targets Android and iOS. The home-screen heatmap widget is Android only.

## Features

- **Workout logging**: start a session, add exercises, log sets (weight, reps, RPE), and pick up an in-progress workout where you left off.
- **Exercise library**: browse and search exercises, create your own, and organise them into categories.
- **Templates**: save a workout as a template and start future sessions from it.
- **Warm-up and plate helpers**: a warm-up set generator and a barbell plate calculator.
- **Rest timer**: keeps running as you move between tabs, and posts a controllable notification (pause, resume, ±15 s) with a sound when the app is in the background.
- **Personal records**: sets that beat every earlier non-warm-up set on both weight and reps are flagged as a new best.
- **Progress and analytics**: charts over a selectable date range, a workout heatmap, a muscle map, and achievements.
- **Body tracking**: body weight with an optional target, plus body measurements.
- **Reminders**: weekly workout and weigh-in reminders.
- **Export and backup**: export everything as JSON, or sets, workouts, weight and measurements as CSV, plus a printable PDF report. An automatic backup is written after each completed workout.
- **Customisation**: kg/lbs units, light/dark/system theme, custom accent and highlight colours, and a configurable home screen.
- **Android home-screen widget** showing your workout heatmap.

## Tech stack

| Area | Choice |
| --- | --- |
| Framework | Flutter (`>=3.38.0`), Dart `^3.13.2` |
| State management | `provider` (`ChangeNotifier`) |
| Storage | SQLite via `sqflite` |
| Charts | `fl_chart` |
| Notifications | `flutter_local_notifications`, `timezone`, `flutter_timezone` |
| Home widget | `home_widget` (Kotlin `HeatmapWidgetProvider`) |
| Muscle map | `flutter_body_atlas` |
| Export | `pdf`, `file_picker`, `media_store_plus` |

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.38 or newer (Dart 3.13.2 or newer). This floor is set by the `flutter_body_atlas` package, so don't use an older SDK.
- **Android**: Android SDK with platform 36 and a JDK 17. The Gradle wrapper (9.3.1) downloads Gradle itself.
- **iOS** (macOS only): Xcode and CocoaPods.

Run `flutter doctor` to check your setup.

### Run the app

```bash
git clone https://github.com/sl-ee-p/gym-tracker.git
cd gym-tracker
flutter pub get
flutter run
```

### Android SDK location

`android/local.properties` holds machine-specific paths (`sdk.dir`, `flutter.sdk`). Flutter rewrites it on `flutter pub get` and `flutter run`, so don't rely on the values committed in the repository.

## Development

```bash
flutter analyze                      # static analysis
flutter test                         # full test suite
flutter test test/path/to_test.dart  # a single test file
```

The data-layer tests use a real SQLite database through `sqflite_common_ffi` rather than mocks. On Linux this needs the native SQLite library installed. On Debian/Ubuntu, `sudo apt install libsqlite3-dev` provides the `libsqlite3.so` the tests look for. If you can't install it system-wide, point `LD_LIBRARY_PATH` at a directory containing a `libsqlite3.so` symlink to `libsqlite3.so.0`.

### Building

```bash
flutter build apk --release
```

Release builds fall back to debug signing unless you provide `android/key.properties`, so don't distribute them as-is.

### Regenerating assets

After changing `assets/icon/app_icon.png`:

```bash
flutter pub run flutter_launcher_icons
```

The native splash screen is configured under `flutter_native_splash` in `pubspec.yaml`.

## Project structure

```
lib/
  main.dart        App entry point, provider registration, startup
  models/          Plain data classes (workouts, sets, exercises, goals, ...)
  providers/       ChangeNotifier state (user, exercises, workouts, progress, rest timer)
  services/        Repositories, DatabaseHelper, export/backup, notifications, home widget, PDF
  screens/         Full-page UI
  widgets/         Reusable UI components
  dialogs/         Dialogs
  utils/           Pure helpers (personal records, plate calculator, formatting, ...)
  theme/           App theme
android/           Android host app, including the Kotlin home-screen widget
assets/            Icons, splash logo and the rest-timer sound
test/              Unit, provider, service and widget tests
```

### Architecture

The app is layered as UI, then providers, then repositories, then `DatabaseHelper`, then SQLite.

- `DatabaseHelper` is a singleton that owns schema creation, migrations, generic CRUD, and full-data export and clear.
- Table-specific repositories sit on top of it and hold the domain rules, such as cascading deletes. Foreign key enforcement is deliberately off.
- Providers are registered once at the root in `main.dart`. `RestTimerController` is registered there too so the timer survives tab changes.

### Database migrations

The schema is versioned. Each `_upgradeToVN` step is append-only and must never be edited once shipped. `_createTables` always reflects the current fresh-install schema. `test/database_migration_test.dart` freezes every prior schema as literal SQL. See the comment at the top of `lib/services/database_helper.dart` for the checklist to follow when bumping the version.

## Platform notes

- Android `compileSdk` is 36, `minSdk` is 24, and `targetSdk` is 36 (Google Play's current minimum), so the app is edge-to-edge on Android 15+.
- `android/build.gradle` raises every subproject's `compileSdk` to 36 because `media_store_plus` hardcodes an old value.
- The Android application ID is `com.slp.platelog` (permanent once published on Google Play). There is no `ios/` folder in this checkout yet; when one is added, give it a matching bundle ID.
- The home-screen widget has no iOS equivalent.
