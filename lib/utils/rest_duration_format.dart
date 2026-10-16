/// One place for the rest timer's `mm:ss`.
///
/// It lived as a top-level function in `rest_timer_widget.dart`, which was fine
/// while only widgets needed it. The ongoing notification needs the same string
/// for its paused body, and a service reaching into `lib/widgets/` to get it
/// would invert the layering — so it moved here, next to the other formatter in
/// `weight_format.dart`.
library;

/// `mm:ss`, the rest timer's format everywhere it appears — the modal's
/// countdown, the workout header's pill and the notification's paused text.
///
/// [roundUp] is for a live countdown: a timer with 89.6 s left should read
/// 01:30, not 01:29, so it starts at the duration the user picked and reaches
/// 00:00 exactly when it fires.
String formatRestDuration(Duration duration, {bool roundUp = false}) {
  final rawSeconds = duration.inMilliseconds / 1000;
  final seconds =
      (roundUp ? rawSeconds.ceil() : rawSeconds.floor()).clamp(0, 1 << 30);
  final minutes = seconds ~/ 60;
  final remSeconds = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remSeconds.toString().padLeft(2, '0')}';
}
