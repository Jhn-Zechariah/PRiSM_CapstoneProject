import 'package:cloud_firestore/cloud_firestore.dart';

class AppPig {
  final String pigId;
  final String displayId;
  final String userId;
  final String breed;
  final DateTime birthDate;
  final String sex;
  final double birthWeightKg;
  final double currentWeightKg;
  final String notes;
  final String stage;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final DateTime? lastIntakeDate;
  final String? lastIntakeName;

  AppPig({
    required this.pigId,
    required this.displayId,
    required this.userId,
    required this.breed,
    required this.birthDate,
    required this.sex,
    required this.birthWeightKg,
    required this.currentWeightKg,
    required this.notes,
    required this.stage,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.lastIntakeDate,
    this.lastIntakeName,
  });

  Map<String, dynamic> toJson() {
    return {
      'pigId': pigId,
      'displayId': displayId,
      'userId': userId,
      'breed': breed,
      'birthDate': Timestamp.fromDate(birthDate),
      'sex': sex,
      'birthWeightKg': birthWeightKg,
      'currentWeightKg': currentWeightKg,
      'notes': notes,
      'stage': stage,
      'status': status,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(), // Always update this on save
      'lastIntakeDate': lastIntakeDate != null
          ? Timestamp.fromDate(lastIntakeDate!)
          : null, // 🔹 Save to Firestore
      'lastIntakeName': lastIntakeName, // 🔹 Save to Firestore
    };
  }

  factory AppPig.fromJson(Map<String, dynamic> json, String documentId) {
    return AppPig(
      pigId: documentId,
      userId: json['userId'] ?? '',
      displayId: json['displayId'] as String? ?? '',
      breed: json['breed'] as String? ?? 'Unknown',
      birthDate: (json['birthDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      sex: json['sex'] as String? ?? 'Unknown',
      birthWeightKg:
          (json['birthWeightKg'] as num?)?.toDouble() ??
          (json['currentWeightKg'] as num?)?.toDouble() ??
          1.4,
      currentWeightKg: (json['currentWeightKg'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String? ?? '',
      stage: json['stage'] as String? ?? 'Unknown',
      status: json['status'] as String? ?? 'Unknown',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
      lastIntakeDate: (json['lastIntakeDate'] as Timestamp?)?.toDate(),
      lastIntakeName: json['lastIntakeName'] as String?,
    );
  }
}
