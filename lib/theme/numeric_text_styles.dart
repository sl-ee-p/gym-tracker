import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dedicated styles for weights/reps/timers/stat numbers, using tabular
/// (monospaced) figures so columns of numbers line up and stay glanceable
/// one-handed mid-rest.
class NumericTextStyles {
  const NumericTextStyles._();

  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle display({Color? color}) => GoogleFonts.inter(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        fontFeatures: _tabular,
        color: color,
      );

  static TextStyle title({Color? color}) => GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        fontFeatures: _tabular,
        color: color,
      );

  static TextStyle body({Color? color}) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontFeatures: _tabular,
        color: color,
      );
}
