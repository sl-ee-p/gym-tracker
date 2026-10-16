import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../utils/weight_format.dart';

/// Sets, changes or removes the body-weight goal. Entered in the display
/// unit, stored as kg like every other weight. Shared by Settings, the Body
/// Weight tab and the Home block, so all three behave the same.
Future<void> showTargetWeightDialog(BuildContext context) async {
  final userProvider = context.read<UserProvider>();
  final unit = userProvider.weightUnit;
  final current = userProvider.targetWeight;
  final controller = TextEditingController(
    text: current == null ? '' : formatWeightValue(current, unit: unit),
  );

  // null: cancelled. A record so "remove" (kg: null) is distinguishable.
  final result = await showDialog<({double? kg})>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Target body weight'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [DecimalWeightInputFormatter()],
        decoration: InputDecoration(
          labelText: 'Target',
          suffixText: unit,
          helperText: 'Progress is measured from your current weight',
        ),
      ),
      actions: [
        if (current != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop((kg: null)),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final kg = parseWeightToKg(controller.text, unit: unit);
            if (kg == null || kg <= 0) return;
            Navigator.of(context).pop((kg: kg));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );

  controller.dispose();
  if (result == null) return;
  final kg = result.kg;
  if (kg == null) {
    await userProvider.clearTargetWeight();
  } else {
    await userProvider.updateTargetWeight(kg);
  }
}
