import 'package:cloud_firestore/cloud_firestore.dart';

class MedicineIntake {
  final String? id;
  final String pigId;
  final String userId;
  final String category;
  final String medName;
  final String dosage;
  final String unitOfMeasurement;
  final String status;
  final DateTime? nextSchedule; // 🔹 changed from String? to DateTime?
  final String? purpose;
  final DateTime dateTaken;

  MedicineIntake({
    this.id,
    required this.pigId,
    required this.category,
    required this.userId,
    required this.medName,
    required this.dosage,
    required this.unitOfMeasurement,
    required this.status,
    this.nextSchedule,
    this.purpose,
    required this.dateTaken,
  });

  MedicineIntake copyWith({
    String? id,
    String? pigId,
    String? userId,
    String? category,
    String? medName,
    String? dosage,
    String? unitOfMeasurement,
    String? status,
    DateTime? nextSchedule,
    String? purpose,
    DateTime? dateTaken,
  }) {
    return MedicineIntake(
      id: id ?? this.id,
      pigId: pigId ?? this.pigId,
      userId: userId ?? this.userId,
      category: category ?? this.category,
      medName: medName ?? this.medName,
      dosage: dosage ?? this.dosage,
      unitOfMeasurement: unitOfMeasurement ?? this.unitOfMeasurement,
      status: status ?? this.status,
      nextSchedule: nextSchedule ?? this.nextSchedule,
      purpose: purpose ?? this.purpose,
      dateTaken: dateTaken ?? this.dateTaken,
    );
  }

  factory MedicineIntake.fromMap(Map<String, dynamic> map, {String? documentId}) {
    return MedicineIntake(
      id: documentId ?? map['id'] as String?,
      pigId: map['pigId'] ?? '',
      category: map['category'] ?? '',
      userId: map['userId'] ?? '',
      medName: map['medName'] ?? '',
      dosage: map['dosage'] ?? '',
      unitOfMeasurement: map['unitOfMeasurement'] ?? '',
      status: map['status'] ?? 'Ongoing',
      // 🔹 Read as Timestamp now, not a String.
      nextSchedule: map['nextSchedule'] != null
          ? (map['nextSchedule'] as Timestamp).toDate()
          : null,
      purpose: map['purpose'] as String?,
      dateTaken: map['dateTaken'] != null
          ? DateTime.parse(map['dateTaken'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pigId': pigId,
      'userId': userId,
      'category': category,
      'medName': medName,
      'dosage': dosage,
      'unitOfMeasurement': unitOfMeasurement,
      'status': status,
      // 🔹 Write as Timestamp, not a String.
      'nextSchedule': nextSchedule != null ? Timestamp.fromDate(nextSchedule!) : null,
      'purpose': purpose,
      'dateTaken': dateTaken.toIso8601String(),
    };
  }
}