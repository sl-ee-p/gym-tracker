import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../models/reminder_schedule.dart';
import '../models/user_profile.dart';
import '../models/weight_goal.dart';
import '../services/notification_service.dart';
import '../services/weight_repository.dart';
import '../utils/weight_format.dart';

class UserProvider extends ChangeNotifier {
  final WeightRepository _weightRepository = WeightRepository();
  
  UserProfile? _userProfile;
  bool _isLoading = false;
  
  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;

  /// Swaps in [profile] without touching the database, so widget tests can
  /// render against specific settings. Not for use by app code.
  @visibleForTesting
  void setProfileForTesting(UserProfile profile) {
    _userProfile = profile;
    notifyListeners();
  }
  
  String get weightUnit => _userProfile?.weightUnit ?? 'kg';
  double? get currentWeight => _userProfile?.currentWeight;
  String get userName => _userProfile?.name ?? 'User';

  /// Bar weight in kg for exercises that don't override it.
  double get defaultBarWeightKg => _userProfile?.defaultBarWeightKg ?? 20.0;

  /// Bar weight in kg to use for [exercise] — its own, or the global default.
  double barWeightFor(Exercise exercise) =>
      exercise.barWeightKg ?? defaultBarWeightKg;

  int get weeklyWorkoutGoal => _userProfile?.weeklyWorkoutGoal ?? 3;

  int? get accentColorLight => _userProfile?.accentColorLight;
  int? get accentColorDark => _userProfile?.accentColorDark;
  int? get highlightColorLight => _userProfile?.highlightColorLight;
  int? get highlightColorDark => _userProfile?.highlightColorDark;

  String? get homeLayout => _userProfile?.homeLayout;
  bool get autoBackupEnabled => _userProfile?.autoBackupEnabled ?? true;
  DateTime? get lastBackupAt => _userProfile?.lastBackupAt;
  String? get progressDateRange => _userProfile?.progressDateRange;
  int? get lastProgressExerciseId => _userProfile?.lastProgressExerciseId;

  /// The rest duration to open the timer picker on. 90 s until the user has
  /// started one, which is what the picker has always defaulted to.
  Duration get restTimerDuration =>
      Duration(seconds: _userProfile?.restTimerSeconds ?? 90);

  bool get partialRepsEnabled => _userProfile?.partialRepsEnabled ?? false;
  bool get rpeEnabled => _userProfile?.rpeEnabled ?? false;

  ReminderSchedule get workoutReminder => ReminderSchedule.parse(
        _userProfile?.workoutReminderDays,
        _userProfile?.workoutReminderMinutes ?? 18 * 60,
      );

  ReminderSchedule get weighInReminder => ReminderSchedule.parse(
        _userProfile?.weighInReminderDays,
        _userProfile?.weighInReminderMinutes ?? 7 * 60 + 30,
      );

  double? get targetWeight => _userProfile?.targetWeight;

  /// Progress towards [targetWeight], or null when no goal is set.
  WeightGoalProgress? get weightGoalProgress {
    final target = targetWeight;
    if (target == null) return null;
    return WeightGoalProgress.compute(
      targetKg: target,
      startKg: _userProfile?.targetWeightStart,
      currentKg: currentWeight,
    );
  }

  ThemeMode get themeMode {
    switch (_userProfile?.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> loadUserProfile() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _userProfile = await _weightRepository.getUserProfile();
      
      // If no user profile exists, create a default one
      if (_userProfile == null) {
        _userProfile = UserProfile(
          name: 'User',
          createdDate: DateTime.now(),
          weightUnit: 'kg',
        );
        
        final id = await _weightRepository.insertUserProfile(_userProfile!);
        _userProfile = _userProfile!.copyWith(id: id);
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateUserName(String name) async {
    if (_userProfile == null) return;
    
    try {
      final updatedProfile = _userProfile!.copyWith(name: name);
      await _weightRepository.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating user name: $e');
    }
  }

  Future<void> updateWeightUnit(String unit) async {
    if (_userProfile == null) return;
    
    try {
      // Update user profile
      final updatedProfile = _userProfile!.copyWith(weightUnit: unit);
      await _weightRepository.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating weight unit: $e');
    }
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    if (_userProfile == null) return;

    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    try {
      final updatedProfile = _userProfile!.copyWith(themeMode: value);
      await _weightRepository.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating theme mode: $e');
    }
  }

  Future<void> updateCurrentWeight(double weight) async {
    if (_userProfile == null) return;
    
    try {
      // A goal set before any weight was logged has no starting point; the
      // first weigh-in after it becomes one, so the progress bar can appear.
      final needsGoalStart = _userProfile!.targetWeight != null &&
          _userProfile!.targetWeightStart == null;
      final updatedProfile = _userProfile!.copyWith(
        currentWeight: weight,
        targetWeightStart: needsGoalStart ? weight : null,
      );
      await _weightRepository.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating current weight: $e');
    }
  }

  Future<void> clearCurrentWeight() async {
    if (_userProfile == null) return;

    try {
      final updatedProfile = _userProfile!.copyWith(clearCurrentWeight: true);
      await _weightRepository.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing current weight: $e');
    }
  }

  /// Writes [updated] through to the database and swaps it in on success.
  /// Every setter below funnels through here so persistence and the
  /// in-memory copy can't disagree.
  Future<void> _persist(UserProfile updated, String what) async {
    try {
      await _weightRepository.updateUserProfile(updated);
      _userProfile = updated;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating $what: $e');
    }
  }

  Future<void> updateDefaultBarWeight(double kg) async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(defaultBarWeightKg: kg),
      'default bar weight',
    );
  }

  Future<void> updateWeeklyWorkoutGoal(int goal) async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(weeklyWorkoutGoal: goal),
      'weekly workout goal',
    );
  }

  Future<void> updateThemeColors({
    int? accentLight,
    int? accentDark,
    int? highlightLight,
    int? highlightDark,
  }) async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(
        accentColorLight: accentLight,
        accentColorDark: accentDark,
        highlightColorLight: highlightLight,
        highlightColorDark: highlightDark,
      ),
      'theme colors',
    );
  }

  /// Drops every custom color so the app falls back to AppTheme's palette.
  Future<void> resetThemeColors() async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(clearThemeColors: true),
      'theme colors',
    );
  }

  Future<void> updateHomeLayout(String? layout) async {
    if (_userProfile == null) return;
    await _persist(
      layout == null
          ? _userProfile!.copyWith(clearHomeLayout: true)
          : _userProfile!.copyWith(homeLayout: layout),
      'home layout',
    );
  }

  Future<void> updateAutoBackupEnabled(bool enabled) async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(autoBackupEnabled: enabled),
      'auto backup setting',
    );
  }

  Future<void> updatePartialRepsEnabled(bool enabled) async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(partialRepsEnabled: enabled),
      'partial reps setting',
    );
  }

  Future<void> updateRpeEnabled(bool enabled) async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(rpeEnabled: enabled),
      'RPE setting',
    );
  }

  /// Sets the goal and restarts its progress from today's weight: a new goal
  /// is measured from where you are now, not from where an old one began.
  Future<void> updateTargetWeight(double kg) async {
    if (_userProfile == null) return;
    final start = currentWeight;
    await _persist(
      start == null
          ? _userProfile!
              .copyWith(targetWeight: kg, clearTargetWeightStart: true)
          : _userProfile!.copyWith(targetWeight: kg, targetWeightStart: start),
      'target weight',
    );
  }

  Future<void> clearTargetWeight() async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(clearTargetWeight: true),
      'target weight',
    );
  }

  Future<void> updateWorkoutReminder(ReminderSchedule schedule) async {
    if (_userProfile == null) return;
    final days = schedule.encodeDays();
    await _persist(
      days == null
          ? _userProfile!.copyWith(
              clearWorkoutReminder: true,
              workoutReminderMinutes: schedule.minutesOfDay)
          : _userProfile!.copyWith(
              workoutReminderDays: days,
              workoutReminderMinutes: schedule.minutesOfDay),
      'workout reminder',
    );
    await _afterReminderChange(schedule);
  }

  Future<void> updateWeighInReminder(ReminderSchedule schedule) async {
    if (_userProfile == null) return;
    final days = schedule.encodeDays();
    await _persist(
      days == null
          ? _userProfile!.copyWith(
              clearWeighInReminder: true,
              weighInReminderMinutes: schedule.minutesOfDay)
          : _userProfile!.copyWith(
              weighInReminderDays: days,
              weighInReminderMinutes: schedule.minutesOfDay),
      'weigh-in reminder',
    );
    await _afterReminderChange(schedule);
  }

  Future<void> _afterReminderChange(ReminderSchedule schedule) async {
    // Asked at the moment it's obviously needed — the user just switched a
    // reminder on — not at launch.
    if (schedule.isEnabled) {
      await NotificationService.instance.requestNotificationPermission();
    }
    await syncReminders();
  }

  /// Schedules the OS reminders to match the saved settings. Called at
  /// startup and after anything that replaces the profile (Clear, Restore).
  Future<void> syncReminders() => NotificationService.instance.syncReminders(
        workout: workoutReminder,
        weighIn: weighInReminder,
      );

  Future<void> updateProgressDateRange(String rangeName) async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(progressDateRange: rangeName),
      'progress date range',
    );
  }

  /// Remembers the Progress screen's selected exercise. Pass null to forget
  /// it — needed when the saved exercise has since been deleted, and the
  /// reason [UserProfile.copyWith] grew a `clear` flag for this field.
  Future<void> updateLastProgressExercise(int? exerciseId) async {
    if (_userProfile == null) return;
    await _persist(
      exerciseId == null
          ? _userProfile!.copyWith(clearLastProgressExercise: true)
          : _userProfile!.copyWith(lastProgressExerciseId: exerciseId),
      'last progress exercise',
    );
  }

  Future<void> updateRestTimerDuration(Duration duration) async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(restTimerSeconds: duration.inSeconds),
      'rest timer duration',
    );
  }

  Future<void> recordBackupAt(DateTime timestamp) async {
    if (_userProfile == null) return;
    await _persist(
      _userProfile!.copyWith(lastBackupAt: timestamp),
      'last backup time',
    );
  }

  // Helper method to convert weight between units. Delegates to
  // utils/weight_format.dart so there is exactly one conversion factor in the
  // app — a second copy here would let display and storage drift apart.
  double convertWeight(double weight, String fromUnit, String toUnit) {
    if (fromUnit == toUnit) return weight;
    if (fromUnit == 'kg') return kgToUnit(weight, toUnit);
    if (toUnit == 'kg') return unitToKg(weight, fromUnit);
    return weight;
  }

  // Format weight with appropriate unit. [weight] is assumed to be stored in
  // [fromUnit] (all persisted weights in this app are kg) and is converted
  // to the display unit before formatting — it must not just be relabeled.
  String formatWeight(double weight, {String? unit, String fromUnit = 'kg'}) {
    final displayUnit = unit ?? weightUnit;
    final displayWeight = convertWeight(weight, fromUnit, displayUnit);
    return '${formatDecimal(displayWeight)} $displayUnit';
  }

  // Get weight in user's preferred unit
  double getWeightInPreferredUnit(double weight, String currentUnit) {
    return convertWeight(weight, currentUnit, weightUnit);
  }

  Future<void> initialize() async {
    await loadUserProfile();
  }
}