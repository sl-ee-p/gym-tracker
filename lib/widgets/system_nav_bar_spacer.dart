import 'package:flutter/material.dart';

/// Reserves the system navigation bar's height at the bottom of a pushed
/// screen.
///
/// Targeting Android 15+ forces edge-to-edge, so a screen's content would
/// otherwise scroll under the navigation bar and its last item could never
/// clear it. Pass this as a [Scaffold.bottomNavigationBar]: the Scaffold then
/// removes the bottom inset from its body and keeps FABs above it, without
/// touching the body's own layout. Tab screens don't need it; the shell's
/// [NavigationBar] already consumes the inset.
class SystemNavBarSpacer extends StatelessWidget {
  const SystemNavBarSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: MediaQuery.paddingOf(context).bottom);
  }
}
