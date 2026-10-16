import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/home_block.dart';
import '../providers/user_provider.dart';
import '../utils/app_spacing.dart';

/// Choose which dashboard sections appear, and in what order.
///
/// One list holding every section, rather than separate "shown" and "hidden"
/// lists. Two lists meant a toggle teleported the row from one to the other,
/// and re-deriving the shown list from the default order reset everything
/// else. Here a row never moves when you toggle it — it dims in place and
/// keeps its position, so switching it back on restores exactly what you had.
///
/// Edits apply immediately rather than behind a Save button: the dashboard is
/// one back-press away, so the feedback loop is short and there is nothing to
/// lose by leaving.
class CustomizeHomeScreen extends StatefulWidget {
  const CustomizeHomeScreen({super.key});

  @override
  State<CustomizeHomeScreen> createState() => _CustomizeHomeScreenState();
}

class _CustomizeHomeScreenState extends State<CustomizeHomeScreen> {
  late HomeLayout _layout;

  @override
  void initState() {
    super.initState();
    _layout = HomeLayoutCodec.parse(context.read<UserProvider>().homeLayout);
  }

  Future<void> _apply(HomeLayout next) async {
    setState(() => _layout = next);
    await context.read<UserProvider>().updateHomeLayout(next.encode());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCount = _layout.visible.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customise Home'),
        actions: [
          if (!_layout.isDefault)
            TextButton(
              onPressed: () => _apply(HomeLayout.defaultLayout),
              child: const Text('Reset'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Drag to reorder. Anything switched off is hidden from the home '
            'screen but keeps its place here, so you can switch it back on '
            'without losing your order.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // AnimatedSize so the warning appearing and disappearing pushes the
          // list down smoothly rather than jumping it.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: visibleCount > 0
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber,
                                color: theme.colorScheme.onErrorContainer),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                'Every section is switched off, so the home '
                                'screen is empty.',
                                style: TextStyle(
                                    color: theme.colorScheme.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) =>
                _apply(_layout.reordered(oldIndex, newIndex)),
            children: [
              for (var i = 0; i < _layout.order.length; i++)
                _BlockTile(
                  key: ValueKey(_layout.order[i].key),
                  index: i,
                  block: _layout.order[i],
                  isVisible: _layout.isVisible(_layout.order[i]),
                  onChanged: (visible) => _apply(
                    _layout.withVisibility(_layout.order[i], visible),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One draggable row. Hidden and shown differ only in appearance, and the
/// transition between them is animated — the row itself never moves.
class _BlockTile extends StatelessWidget {
  const _BlockTile({
    super.key,
    required this.index,
    required this.block,
    required this.isVisible,
    required this.onChanged,
  });

  final int index;
  final HomeBlock block;
  final bool isVisible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const duration = Duration(milliseconds: 220);
    const curve = Curves.easeOut;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        decoration: BoxDecoration(
          color: isVisible
              ? theme.colorScheme.surfaceContainerLow
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isVisible
                ? theme.colorScheme.outlineVariant
                : Colors.transparent,
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          leading: ReorderableDragStartListener(
            index: index,
            child: AnimatedOpacity(
              duration: duration,
              curve: curve,
              opacity: isVisible ? 1 : 0.45,
              child: const Icon(Icons.drag_handle),
            ),
          ),
          title: AnimatedDefaultTextStyle(
            duration: duration,
            curve: curve,
            style: theme.textTheme.bodyLarge!.copyWith(
              color: isVisible
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
            child: Text(block.label),
          ),
          // AnimatedSize collapses the subtitle away rather than snapping the
          // row's height when the "Hidden" label appears.
          subtitle: AnimatedSize(
            duration: duration,
            curve: curve,
            alignment: Alignment.topLeft,
            child: isVisible
                ? const SizedBox(height: 0, width: double.infinity)
                : Text(
                    'Hidden',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          trailing: Switch(value: isVisible, onChanged: onChanged),
          onTap: () => onChanged(!isVisible),
        ),
      ),
    );
  }
}
