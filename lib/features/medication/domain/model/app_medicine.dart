class Medicine {
  final String? medId;
  final String userId;
  final String name;
  final String type;
  final String category;
  final String measurementUnit;
  final double reorderLevel;
  final double totalStock;

  Medicine({
    required this.medId,
    required this.userId,
    required this.name,
    required this.type,
    required this.category,
    required this.measurementUnit,
    required this.reorderLevel,
    required this.totalStock,
  });

  // Convert to Map for saving to Firestore
  Map<String, dynamic> toMap() {
    return {
      'medId' : medId,
      'userId': userId,
      'name': name,
      'type': type,
      'category': category,
      'measurement_unit': measurementUnit,
      'reorder_level': reorderLevel,
      'total_stock': totalStock,
    };
  }

  // Create a Medicine object from a Firestore Map
  factory Medicine.fromMap(Map<String, dynamic> map, String documentId) {
    return Medicine(
      medId: documentId,
      userId: map['userId'] ?? '',
      name: map['name'] ?? 'Unknown',
      type: map['type'] ?? 'Unknown',
      category: map['category'] ?? 'Medicine',
      measurementUnit: map['measurement_unit'] ?? '',
      reorderLevel: (map['reorder_level'] as num?)?.toDouble() ?? 0.0,
      totalStock: (map['total_stock'] as num?)?.toDouble() ?? 0.0,
    );
  }
  // 🔹 Creates a copy of the Medicine with updated fields
  Medicine copyWith({
    String? medId,
    String? userId,
    String? name,
    String? category,
    String? type,
    String? measurementUnit,
    double? reorderLevel,
    double? totalStock,
  }) {
    return Medicine(
      medId: medId ?? this.medId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      category: category ?? this.category,
      type: type ?? this.type,
      measurementUnit: measurementUnit ?? this.measurementUnit,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      totalStock: totalStock ?? this.totalStock,
    );
  }
}