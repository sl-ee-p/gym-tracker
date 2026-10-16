import 'package:flutter/material.dart';
import 'package:flutter_body_atlas/flutter_body_atlas.dart';

import '../models/exercise.dart';

/// Maps this app's free-text `muscleGroups` strings onto the muscles
/// flutter_body_atlas can actually draw.
///
/// [Exercise.muscleGroups] is unvalidated user text — a plain comma-separated
/// field, so a custom exercise can say "Wingspan Stabilizers". Everything here
/// therefore degrades to "highlight nothing" rather than throwing; an unknown
/// string is a diagram with no highlights, never a crash.
///
/// The table is hand-written rather than derived from [MuscleSearch] and the
/// catalog's `aliases`. Alias search is a substring match, so a query like
/// "abs" also hits unrelated tokens and "back" hits anything with "back" in a
/// display name — close enough for a search box, wrong for a diagram that is
/// asserting anatomy. An explicit table is also the only version that can be
/// unit-tested against a fixed expectation.
///
/// Both sides are always highlighted: the app records "Chest", not "left chest".

// ---------------------------------------------------------------------------
// Building blocks. One const set per anatomical group the app's vocabulary can
// name, composed into the lookup table below.
// ---------------------------------------------------------------------------

const _chest = <Muscle>{
  Muscle.pectoralisMajorLeft,
  Muscle.pectoralisMajorRight,
};

/// Anconeus sits with the triceps rather than the forearm: it is an elbow
/// extensor and a triceps synergist, and grouping it under "Forearms" would
/// light up the elbow for wrist work.
const _triceps = <Muscle>{
  Muscle.tricepsBrachiiCaputLateraleLeft,
  Muscle.tricepsBrachiiCaputLateraleRight,
  Muscle.tricepsBrachiiCaputLongumLeft,
  Muscle.tricepsBrachiiCaputLongumRight,
  Muscle.tricepsBrachiiCaputMedialeLeft,
  Muscle.tricepsBrachiiCaputMedialeRight,
  Muscle.anconeusLeft,
  Muscle.anconeusRight,
};

const _biceps = <Muscle>{
  Muscle.bicepsBrachiiCaputBreveLeft,
  Muscle.bicepsBrachiiCaputBreveRight,
  Muscle.bicepsBrachiiCaputLongumLeft,
  Muscle.bicepsBrachiiCaputLongumRight,
};

const _forearms = <Muscle>{
  Muscle.brachioradialisLeft,
  Muscle.brachioradialisRight,
  Muscle.extensorDigitorumLeft,
  Muscle.extensorDigitorumRight,
  Muscle.extensorCarpiUlnarisLeft,
  Muscle.extensorCarpiUlnarisRight,
  Muscle.extensorCarpiRadialisLongusLeft,
  Muscle.extensorCarpiRadialisLongusRight,
  Muscle.flexorCarpiUlnarisLeft,
  Muscle.flexorCarpiUlnarisRight,
  Muscle.flexorCarpiRadialisLeft,
  Muscle.flexorCarpiRadialisRight,
  Muscle.flexorDigitorumSuperficialisLeft,
  Muscle.flexorDigitorumSuperficialisRight,
  Muscle.palmarisLongusLeft,
  Muscle.palmarisLongusRight,
  Muscle.pronatorTeresLeft,
  Muscle.pronatorTeresRight,
  Muscle.pronatorQuadratusLeft,
  Muscle.pronatorQuadratusRight,
};

const _anteriorDeltoids = <Muscle>{
  Muscle.anteriorDeltoidLeft,
  Muscle.anteriorDeltoidRight,
};

const _lateralDeltoids = <Muscle>{
  Muscle.lateralDeltoidLeft,
  Muscle.lateralDeltoidRight,
};

const _posteriorDeltoids = <Muscle>{
  Muscle.posteriorDeltoidLeft,
  Muscle.posteriorDeltoidRight,
};

const _shoulders = <Muscle>{
  ..._anteriorDeltoids,
  ..._lateralDeltoids,
  ..._posteriorDeltoids,
};

const _traps = <Muscle>{
  Muscle.trapeziusUpperLeft,
  Muscle.trapeziusUpperRight,
  Muscle.trapeziusMiddleLeft,
  Muscle.trapeziusMiddleRight,
  Muscle.trapeziusLowerLeft,
  Muscle.trapeziusLowerRight,
};

const _lats = <Muscle>{
  Muscle.latissimusDorsiLeft,
  Muscle.latissimusDorsiRight,
};

/// "Back" as this app's seeded exercises mean it — the pulling musculature.
///
/// Note what is *not* here: the artwork has no erector spinae, thoracolumbar
/// fascia or quadratus lumborum, so the lower back is genuinely undrawable.
/// See the `lower back` entry in the lookup table.
const _back = <Muscle>{
  ..._lats,
  ..._traps,
  Muscle.infraspinatusLeft,
  Muscle.infraspinatusRight,
};

const _abs = <Muscle>{
  Muscle.rectusAbdominis1,
  Muscle.rectusAbdominis2Left,
  Muscle.rectusAbdominis2Right,
  Muscle.rectusAbdominis3Left,
  Muscle.rectusAbdominis3Right,
  Muscle.rectusAbdominis4Left,
  Muscle.rectusAbdominis4Right,
};

/// The two aggregate ids, not the sixteen individual digitations. An aggregate
/// fans out to every path it covers via [Muscle.parts], so this paints the
/// whole oblique sheet with two entries instead of sixteen.
const _obliques = <Muscle>{
  Muscle.externalObliqueLeft,
  Muscle.externalObliqueRight,
};

const _quadriceps = <Muscle>{
  Muscle.rectusFemorisLeft,
  Muscle.rectusFemorisRight,
  Muscle.vastusLateralisLeft,
  Muscle.vastusLateralisRight,
  Muscle.vastusMedialisLeft,
  Muscle.vastusMedialisRight,
};

const _hamstrings = <Muscle>{
  Muscle.bicepsFemorisLeft,
  Muscle.bicepsFemorisRight,
  Muscle.semitendinosusLeft,
  Muscle.semitendinosusRight,
  Muscle.semimembranosus1Left,
  Muscle.semimembranosus1Right,
  Muscle.semimembranosus2Left,
  Muscle.semimembranosus2Right,
};

const _glutes = <Muscle>{
  Muscle.gluteusMaximusLeft,
  Muscle.gluteusMaximusRight,
  Muscle.gluteusMedius1Left,
  Muscle.gluteusMedius1Right,
  Muscle.gluteusMedius2Left,
  Muscle.gluteusMedius2Right,
};

/// Gastrocnemius only. The soleus is not in the artwork, and the tibialis
/// anterior / fibularis group is the shin — the antagonist, not the calf.
const _calves = <Muscle>{
  Muscle.gastrocnemiusLeft,
  Muscle.gastrocnemiusRight,
};

const _shins = <Muscle>{
  Muscle.tibialisAnteriorLeft,
  Muscle.tibialisAnteriorRight,
  Muscle.fibularisLongusLeft,
  Muscle.fibularisLongusRight,
  Muscle.extensorDigitorumLongusLeft,
  Muscle.extensorDigitorumLongusRight,
  Muscle.extensorHallucisLongusLeft,
  Muscle.extensorHallucisLongusRight,
};

const _adductors = <Muscle>{
  Muscle.adductorMagnusLeft,
  Muscle.adductorMagnusRight,
  Muscle.adductorLongusLeft,
  Muscle.adductorLongusRight,
  Muscle.pectineusLeft,
  Muscle.pectineusRight,
  Muscle.gracilisLeft,
  Muscle.gracilisRight,
};

const _neck = <Muscle>{
  Muscle.sternocleidomastoidLeft,
  Muscle.sternocleidomastoidRight,
  Muscle.platysma,
  Muscle.sternohyoid,
};

const _core = <Muscle>{..._abs, ..._obliques};

const _legs = <Muscle>{
  ..._quadriceps,
  ..._hamstrings,
  ..._glutes,
  ..._calves,
  ..._adductors,
};

const _arms = <Muscle>{..._biceps, ..._triceps, ..._forearms};

/// Everything the artwork draws. Deliberately the whole enum rather than a
/// union of the sets above: "Full Body" should not quietly omit the sartorius
/// or the iliotibial tract just because no app string names them.
final Set<Muscle> _fullBody = Muscle.values.toSet();

// ---------------------------------------------------------------------------
// The lookup table
// ---------------------------------------------------------------------------

/// Normalized muscle-group string -> muscles to highlight.
///
/// Keys must already be normalized by [normalizeMuscleGroup]. The first block
/// is the vocabulary `Exercise.getDefaultExercises()` actually seeds; the rest
/// are near-misses a user is likely to type by hand.
final Map<String, Set<Muscle>> _byGroupKey = <String, Set<Muscle>>{
  // The 15 strings the seeded catalog uses.
  'chest': _chest,
  'triceps': _triceps,
  'shoulders': _shoulders,
  'back': _back,
  'hamstrings': _hamstrings,
  'glutes': _glutes,
  'biceps': _biceps,
  'rear delts': _posteriorDeltoids,
  'quadriceps': _quadriceps,
  'calves': _calves,
  'forearms': _forearms,
  'core': _core,
  'abs': _abs,
  'obliques': _obliques,
  'full body': _fullBody,

  // Singulars and common shorthand.
  'pecs': _chest,
  'pec': _chest,
  'pectorals': _chest,
  'tricep': _triceps,
  'tris': _triceps,
  'bicep': _biceps,
  'bis': _biceps,
  'shoulder': _shoulders,
  'delts': _shoulders,
  'deltoids': _shoulders,
  'front delts': _anteriorDeltoids,
  'anterior delts': _anteriorDeltoids,
  'side delts': _lateralDeltoids,
  'lateral delts': _lateralDeltoids,
  'medial delts': _lateralDeltoids,
  'rear delt': _posteriorDeltoids,
  'rear deltoids': _posteriorDeltoids,
  'posterior delts': _posteriorDeltoids,
  'lats': _lats,
  'latissimus dorsi': _lats,
  'traps': _traps,
  'trapezius': _traps,
  'upper back': _traps,
  'hamstring': _hamstrings,
  'hams': _hamstrings,
  'glute': _glutes,
  'gluteus': _glutes,
  'quads': _quadriceps,
  'quad': _quadriceps,
  'calf': _calves,
  'forearm': _forearms,
  'abdominals': _abs,
  'abdominal': _abs,
  'rectus abdominis': _abs,
  'oblique': _obliques,
  'adductors': _adductors,
  'inner thigh': _adductors,
  'inner thighs': _adductors,
  'neck': _neck,
  'legs': _legs,
  'leg': _legs,
  'arms': _arms,
  'arm': _arms,
  'shins': _shins,
  'tibialis anterior': _shins,
  'fullbody': _fullBody,
  'full-body': _fullBody,
  'total body': _fullBody,

  // Deliberately empty: real muscle names this artwork does not contain.
  // Mapped explicitly so they read as "known but undrawable" to
  // [isKnownMuscleGroup] instead of looking like typos — and so nobody
  // "helpfully" points them at the lats, which is not where they are.
  'lower back': <Muscle>{},
  'erector spinae': <Muscle>{},
  'spinal erectors': <Muscle>{},
  'lumbar': <Muscle>{},
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// The comparison key for a muscle-group string.
///
/// Mirrors [Exercise.normalizeName] (trim + lower-case) and additionally
/// collapses runs of internal whitespace, so `'Rear   Delts'` and
/// `'rear delts'` are the same key.
///
/// The trim is load-bearing rather than defensive: [Exercise.fromMap] splits
/// the stored column on `,` without trimming, so a row written by an older
/// build — or any import that used `', '` as its separator — yields values
/// with a leading space.
String normalizeMuscleGroup(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The muscles to highlight for one muscle-group string.
///
/// Empty when the string isn't recognized, and also empty for the handful of
/// recognized-but-undrawable entries (see `lower back`). Callers that need to
/// tell those apart should use [isKnownMuscleGroup].
Set<Muscle> musclesForMuscleGroup(String raw) =>
    _byGroupKey[normalizeMuscleGroup(raw)] ?? const <Muscle>{};

/// Whether [raw] is a string this mapping recognizes at all — including the
/// entries that are known but have no artwork to highlight.
bool isKnownMuscleGroup(String raw) =>
    _byGroupKey.containsKey(normalizeMuscleGroup(raw));

/// Every muscle worked by [exercise], unioned over its muscle groups.
///
/// This is the single normalization point both the standalone Muscle Map
/// screen and the exercise details screen go through, so the two can't drift.
Set<Muscle> musclesForExercise(Exercise exercise) {
  final result = <Muscle>{};
  for (final group in exercise.muscleGroups) {
    result.addAll(musclesForMuscleGroup(group));
  }
  return result;
}

/// The muscle-group strings on [exercise] that this mapping can't draw, in the
/// order they were entered, de-duplicated by normalized key.
///
/// Lets a screen say "Not shown: Wingspan Stabilizers" instead of leaving the
/// user to wonder why a group they typed isn't lit up.
List<String> undrawableMuscleGroups(Exercise exercise) {
  final seen = <String>{};
  final result = <String>[];
  for (final group in exercise.muscleGroups) {
    final key = normalizeMuscleGroup(group);
    if (key.isEmpty || !seen.add(key)) continue;
    if (musclesForMuscleGroup(group).isEmpty) result.add(group.trim());
  }
  return result;
}

/// Normalized group keys whose muscles are best seen from behind.
///
/// Not simply "has no path in the front layer" — that test gives the wrong
/// answer for several groups. The artwork draws `gluteus_medius_2` on the front
/// (the muscle really does wrap onto the hip), and the lats, upper traps,
/// gastrocnemius and semitendinosus all appear in both layers, so a
/// presence-based rule would open Squats and Calf Raises on a view that shows a
/// sliver of the muscle in question. This is the editorial answer instead:
/// which side a lifter would actually look at.
const Set<String> _posteriorGroupKeys = <String>{
  'back',
  'rear delts',
  'rear delt',
  'rear deltoids',
  'posterior delts',
  'glutes',
  'glute',
  'gluteus',
  'hamstrings',
  'hamstring',
  'hams',
  'lats',
  'latissimus dorsi',
  'traps',
  'trapezius',
  'upper back',
  'calves',
  'calf',
};

/// Which view to open [exercise] on.
///
/// The back, when every muscle group the exercise names is one you'd look at
/// from behind; the front otherwise. Without this, a posterior-only movement
/// like Face Pulls or Leg Curl opens on an all-neutral front view, which reads
/// as a broken diagram rather than as "look at the other side".
///
/// Undrawable groups are ignored rather than counted as anterior, so
/// `['Hamstrings', 'Lower Back']` still opens on the back.
AtlasAsset preferredViewForExercise(Exercise exercise) {
  var sawDrawableGroup = false;
  for (final group in exercise.muscleGroups) {
    if (musclesForMuscleGroup(group).isEmpty) continue;
    sawDrawableGroup = true;
    if (!_posteriorGroupKeys.contains(normalizeMuscleGroup(group))) {
      return AtlasAsset.musclesFront;
    }
  }
  return sawDrawableGroup ? AtlasAsset.musclesBack : AtlasAsset.musclesFront;
}

/// Turns a muscle set into the `colorMapping` [BodyAtlasView] expects.
///
/// Goes through [MuscleCatalog.byMuscle] rather than constructing [MuscleInfo]
/// values: the widget keys its map by identity, so it has to be handed the
/// catalog's own const instances.
Map<MuscleInfo, Color?> atlasColorMapping(Set<Muscle> muscles, Color color) {
  return <MuscleInfo, Color?>{
    for (final muscle in muscles) ?MuscleCatalog.byMuscle[muscle]: color,
  };
}
