import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_spacing.dart';

/// Parses `#RRGGBB`, `RRGGBB`, `#AARRGGBB` or a 3-digit `#RGB` shorthand into
/// an opaque [Color], or null if the text isn't a valid hex colour.
Color? parseHexColor(String input) {
  var hex = input.trim().replaceFirst('#', '').toUpperCase();
  if (hex.length == 3) {
    // #abc -> #aabbcc, the usual CSS shorthand.
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  if (!RegExp(r'^[0-9A-F]{8}$').hasMatch(hex)) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(value);
}

/// Formats a [Color] as `#RRGGBB`. Alpha is dropped — every colour this picker
/// produces is opaque, and a stray alpha channel in a theme seed produces
/// washed-out surfaces that are hard to trace back.
String formatHexColor(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
}

/// A short palette of starting points, so picking a colour doesn't require
/// knowing hex. Spread around the wheel and mid-saturation, since these are
/// used as Material 3 scheme seeds rather than painted directly — a
/// near-black or near-white seed produces a scheme with almost no colour in it.
const List<Color> _presetColors = [
  Color(0xFF0B6E77), // the app's own petrol default
  Color(0xFF8A5A22), // its copper highlight
  Color(0xFF2E6DB4),
  Color(0xFF4C6EF5),
  Color(0xFF7048E8),
  Color(0xFFB5179E),
  Color(0xFFC1121F),
  Color(0xFFE8590C),
  Color(0xFF2F9E44),
  Color(0xFF3C7A57),
  Color(0xFF495057),
  Color(0xFF1D3557),
];

/// Asks for a single colour as hex, with a live preview and a preset row.
///
/// Returns the chosen [Color], or null if dismissed. Built in-app rather than
/// pulling in a colour-picker package: the requirement is specifically a
/// hexadecimal picker, which is a text field, a swatch and a parser.
Future<Color?> showHexColorPicker(
  BuildContext context, {
  required String title,
  Color? initialColor,
  String? helperText,
}) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _HexColorPickerDialog(
      title: title,
      initialColor: initialColor,
      helperText: helperText,
    ),
  );
}

class _HexColorPickerDialog extends StatefulWidget {
  const _HexColorPickerDialog({
    required this.title,
    this.initialColor,
    this.helperText,
  });

  final String title;
  final Color? initialColor;
  final String? helperText;

  @override
  State<_HexColorPickerDialog> createState() => _HexColorPickerDialogState();
}

class _HexColorPickerDialogState extends State<_HexColorPickerDialog> {
  late final TextEditingController _controller;
  Color? _color;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor;
    _controller = TextEditingController(
      text: widget.initialColor != null
          ? formatHexColor(widget.initialColor!)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    setState(() => _color = parseHexColor(text));
  }

  void _selectPreset(Color color) {
    _controller.text = formatHexColor(color);
    setState(() => _color = color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isValid = _color != null;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.helperText != null) ...[
            Text(
              widget.helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Row(
            children: [
              // Live preview. An outline keeps a near-surface colour from
              // vanishing into the dialog background.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _color ?? theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: isValid
                    ? null
                    : Icon(
                        Icons.question_mark,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(9),
                    FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Hex colour',
                    hintText: '#0B6E77',
                    errorText: _controller.text.trim().isEmpty || isValid
                        ? null
                        : 'Not a hex colour',
                  ),
                  onChanged: _onTextChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final preset in _presetColors)
                InkWell(
                  onTap: () => _selectPreset(preset),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: preset,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: _color?.toARGB32() == preset.toARGB32()
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.outlineVariant,
                        width: _color?.toARGB32() == preset.toARGB32() ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: isValid ? () => Navigator.of(context).pop(_color) : null,
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}
