// The "New best" line once rendered "100 × 8 kg" — unit tacked on after the
// reps, so it read as 8 kg lifted 100 times — and never converted kg for lbs
// users. These pin the fixed format: weight with its unit first, reps last.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/achievement.dart';
import 'package:gym_app/theme/app_theme.dart';
import 'package:gym_app/widgets/workout_heatmap_card.dart';

void main() {
  Future<String> renderedText(
    WidgetTester tester,
    Achievement achievement, {
    String weightUnit = 'kg',
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: AchievementRow(achievement: achievement, weightUnit: weightUnit),
      ),
    ));
    // Every RichText joined: the leading Icon renders one too, so .first
    // alone would pick up the glyph instead of the line of text.
    return tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join(' ');
  }

  Achievement record({double? weightKg = 100, int? reps = 8}) => Achievement(
        kind: AchievementKind.personalRecord,
        title: 'Bench Press',
        date: DateTime.now(),
        weightKg: weightKg,
        reps: reps,
      );

  testWidgets('puts the unit with the weight and the reps last',
      (tester) async {
    final text = await renderedText(tester, record());
    expect(text, contains('100 kg × 8'));
    expect(text, isNot(contains('8 kg')));
  });

  testWidgets('converts the stored kg for lbs users', (tester) async {
    final text = await renderedText(tester, record(), weightUnit: 'lbs');
    expect(text, contains('220.46 lbs × 8'));
  });

  testWidgets('shows just the weight when the record has no reps',
      (tester) async {
    final text = await renderedText(tester, record(reps: null));
    expect(text, contains('100 kg'));
    expect(text, isNot(contains('×')));
  });

  testWidgets('milestones still show their detail text', (tester) async {
    final text = await renderedText(
      tester,
      Achievement(
        kind: AchievementKind.milestone,
        title: '100 workouts',
        detail: 'logged since you started',
        date: DateTime.now(),
      ),
    );
    expect(text, contains('100 workouts'));
    expect(text, contains('logged since you started'));
  });
}
