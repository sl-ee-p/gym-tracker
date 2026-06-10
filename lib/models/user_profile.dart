class UserProfile {
  int? id;
  String name;
  DateTime createdDate;
  double? currentWeight;
  String weightUnit; // 'kg' or 'lbs'
  
  UserProfile({
    this.id,
    required this.name,
    required this.createdDate,
    this.currentWeight,
    this.weightUnit = 'kg',
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdDate': createdDate.toIso8601String(),
      'currentWeight': currentWeight,
      'weightUnit': weightUnit,
    };
  }
  
  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      createdDate: DateTime.parse(map['createdDate']),
      currentWeight: map['currentWeight']?.toDouble(),
      weightUnit: map['weightUnit'] ?? 'kg',
    );
  }
  
  UserProfile copyWith({
    int? id,
    String? name,
    DateTime? createdDate,
    double? currentWeight,
    String? weightUnit,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      createdDate: createdDate ?? this.createdDate,
      currentWeight: currentWeight ?? this.currentWeight,
      weightUnit: weightUnit ?? this.weightUnit,
    );
  }
}