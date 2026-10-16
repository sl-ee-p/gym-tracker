import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// One entry in an [AppOverflowMenu].
class AppMenuItem {
  const AppMenuItem({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.isDestructive = false,
    this.enabled = true,
    this.isSelected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  /// Tints the row with the error color — for delete/cancel actions.
  final bool isDestructive;

  final bool enabled;

  /// Marks the row with a trailing check, for menus that pick one option out
  /// of a set (a date range, a sort order) rather than firing an action.
  final bool isSelected;
}

/// The app's three-dot overflow menu.
///
/// Built on [MenuAnchor] rather than [PopupMenuButton] on purpose.
/// `PopupMenuButton` pushes a full-screen modal route, and that route's
/// barrier swallows every pointer event until the menu is dismissed: with a
/// menu open you cannot scroll the list behind it or tap another nav tab, and
/// the first tap anywhere is spent just closing the menu.
///
/// [MenuAnchor] uses a `TapRegion` instead of a modal barrier, and with
/// `consumeOutsideTap: false` (the default, spelled out here because the whole
/// point of this widget depends on it) an outside tap both dismisses the menu
/// *and* reaches whatever was underneath. Scrolling while it is open works for
/// the same reason.
class AppOverflowMenu extends StatelessWidget {
  const AppOverflowMenu({
    super.key,
    required this.items,
    this.icon = Icons.more_vert,
    this.tooltip = 'More options',
    this.iconSize,
    this.child,
    this.enabled = true,
  });

  final List<AppMenuItem> items;
  final IconData icon;
  final String tooltip;
  final double? iconSize;

  /// Renders a text button with this label instead of the three-dot icon.
  final Widget? child;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      consumeOutsideTap: false,
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            onPressed: item.enabled ? item.onSelected : null,
            leadingIcon: Icon(
              item.icon,
              size: 20,
              color: item.isDestructive ? colorScheme.error : null,
            ),
            trailingIcon: item.isSelected
                ? Icon(Icons.check, size: 18, color: colorScheme.primary)
                : null,
            child: Text(
              item.label,
              style: item.isDestructive
                  ? TextStyle(color: colorScheme.error)
                  : null,
            ),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        if (child != null) {
          return TextButton(
            onPressed: enabled ? toggle : null,
            child: child!,
          );
        }
        return IconButton(
          icon: Icon(icon),
          iconSize: iconSize,
          tooltip: tooltip,
          onPressed: enabled ? toggle : null,
        );
      },
    );
  }
}
