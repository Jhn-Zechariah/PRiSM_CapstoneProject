class MedicineIntake {
  final String? id;
  final String pigId;
  final String type;
  final String category;
  final String medName;
  final String dosage;
  final String unitOfMeasurement;
  final String status;
  final String? nextSchedule;
  final String? purpose;
  final DateTime dateTaken; // 🔹 Renamed from createdAt

  MedicineIntake({
    this.id,
    required this.pigId,
    required this.type,
    required this.category,
    required this.medName,
    required this.dosage,
    required this.unitOfMeasurement,
    required this.status,
    this.nextSchedule,
    this.purpose,
    required this.dateTaken, // 🔹 Updated parameter
  });

  MedicineIntake copyWith({
    String? id,
    String? pigId,
    String? type,
    String? category,
    String? medName,
    String? dosage,
    String? unitOfMeasurement,
    String? status,
    String? nextSchedule,
    String? purpose,
    DateTime? dateTaken,
  }) {
    return MedicineIntake(
      id: id ?? this.id,
      pigId: pigId ?? this.pigId,
      type: type ?? this.type,
      category: category ?? this.category,
      medName: medName ?? this.medName,
      dosage: dosage ?? this.dosage,
      unitOfMeasurement: unitOfMeasurement ?? this.unitOfMeasurement,
      status: status ?? this.status,
      nextSchedule: nextSchedule ?? this.nextSchedule,
      purpose: purpose ?? this.purpose,
      dateTaken: dateTaken ?? this.dateTaken, // 🔹 Updated here
    );
  }

  factory MedicineIntake.fromMap(Map<String, dynamic> map, {String? documentId}) {
    return MedicineIntake(
      id: documentId ?? map['id'] as String?,
      pigId: map['pigId'] ?? '',
      type: map['type'] ?? '',
      category: map['category'] ?? '',
      medName: map['medName'] ?? '',
      dosage: map['dosage'] ?? '',
      unitOfMeasurement: map['unitOfMeasurement'] ?? '',
      status: map['status'] ?? 'Ongoing',
      nextSchedule: map['nextSchedule'] as String?,
      purpose: map['purpose'] as String?,
      dateTaken: map['dateTaken'] != null
          ? DateTime.parse(map['dateTaken'].toString())
          : DateTime.now(), // 🔹 Updated here
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pigId': pigId,
      'type': type,
      'category': category,
      'medName': medName,
      'dosage': dosage,
      'unitOfMeasurement': unitOfMeasurement,
      'status': status,
      'nextSchedule': nextSchedule,
      'purpose': purpose,
      'dateTaken': dateTaken.toIso8601String(), // 🔹 Updated here
    };
  }
}