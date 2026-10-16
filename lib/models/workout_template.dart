class WorkoutTemplate {
  int? id;
  String name;
  int? categoryId;
  String? notes;
  List<int> exerciseIds;

  /// Parallel array to [exerciseIds]. A `null` entry means that exercise is
  /// standalone; a non-null entry equal to another member's entry means
  /// those exercises are grouped together (a superset/circuit) — the shared
  /// value is the group's anchor exerciseId, i.e. one of the ids already in
  /// [exerciseIds]. Defaults to an all-null list the same length as
  /// [exerciseIds] when not supplied, so a template with no groups behaves
  /// exactly as it did before grouping existed.
  List<int?> exerciseGroupIds;
  DateTime createdDate;

  WorkoutTemplate({
    this.id,
    required this.name,
    this.categoryId,
    this.notes,
    this.exerciseIds = const [],
    List<int?>? exerciseGroupIds,
    required this.createdDate,
  }) : exerciseGroupIds =
            exerciseGroupIds ?? List<int?>.filled(exerciseIds.length, null);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'categoryId': categoryId,
        'notes': notes,
        'exerciseIds': exerciseIds.join(','),
        // Same comma-joined-text convention as exerciseIds, except a null
        // entry is encoded as an empty segment (e.g. ",5,5" for
        // [null, 5, 5]) rather than omitted, so position is preserved.
        'exerciseGroupIds':
            exerciseGroupIds.map((groupId) => groupId?.toString() ?? '').join(','),
        'createdDate': createdDate.toIso8601String(),
      };

  factory WorkoutTemplate.fromMap(Map<String, dynamic> map) {
    final exerciseIds = map['exerciseIds'] != null && (map['exerciseIds'] as String).isNotEmpty
        ? (map['exerciseIds'] as String).split(',').where((s) => s.isNotEmpty).map(int.parse).toList()
        : <int>[];

    // Absent (pre-v7 row) or empty both mean "no groups" — default to an
    // all-null list rather than an empty one so every exercise still gets a
    // (null) entry to look up by index.
    final rawGroupIds = map['exerciseGroupIds'] as String?;
    final exerciseGroupIds = rawGroupIds != null && rawGroupIds.isNotEmpty
        ? rawGroupIds.split(',').map((s) => s.isEmpty ? null : int.parse(s)).toList()
        : List<int?>.filled(exerciseIds.length, null);

    return WorkoutTemplate(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      categoryId: map['categoryId']?.toInt(),
      notes: map['notes'],
      exerciseIds: exerciseIds,
      exerciseGroupIds: exerciseGroupIds,
      createdDate: DateTime.parse(map['createdDate']),
    );
  }

  WorkoutTemplate copyWith({
    int? id, String? name, int? categoryId, String? notes,
    List<int>? exerciseIds, List<int?>? exerciseGroupIds, DateTime? createdDate,
  }) => WorkoutTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        categoryId: categoryId ?? this.categoryId,
        notes: notes ?? this.notes,
        exerciseIds: exerciseIds ?? this.exerciseIds,
        exerciseGroupIds: exerciseGroupIds ?? this.exerciseGroupIds,
        createdDate: createdDate ?? this.createdDate,
      );

  /// Groups of 2+ exerciseIds that should become a superset/circuit, in
  /// template order. A would-be group left with fewer than 2 valid members
  /// is omitted.
  List<List<int>> get exerciseGroups {
    final membersByAnchor = <int, List<int>>{};
    final anchorOrder = <int>[];

    for (var i = 0; i < exerciseIds.length; i++) {
      final anchor = i < exerciseGroupIds.length ? exerciseGroupIds[i] : null;
      if (anchor == null) continue;
      if (!membersByAnchor.containsKey(anchor)) anchorOrder.add(anchor);
      membersByAnchor.putIfAbsent(anchor, () => []).add(exerciseIds[i]);
    }

    return [
      for (final anchor in anchorOrder)
        if (membersByAnchor[anchor]!.length >= 2) membersByAnchor[anchor]!,
    ];
  }
}
