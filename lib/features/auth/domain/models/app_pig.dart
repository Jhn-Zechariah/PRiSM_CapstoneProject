import 'package:cloud_firestore/cloud_firestore.dart';

class AppPig {
  final String pigId;
  final String userId;
  final String breed;
  final DateTime birthDate;
  final String sex;
  final double currentWeightKg;
  final String notes;
  final String stage;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AppPig({
    required this.pigId,
    required this.userId,
    required this.breed,
    required this.birthDate,
    required this.sex,
    required this.currentWeightKg,
    required this.notes,
    required this.stage,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  // Convert AppPig --> Firestore JSON
  Map<String, dynamic> toJson() {
    return {
      'pigId': pigId,
      'userId': userId,
      'breed': breed,
      'birthDate': Timestamp.fromDate(birthDate),
      'sex': sex,
      'currentWeightKg': currentWeightKg,
      'notes': notes,
      'stage': stage,
      'status': status,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(), // Always update this on save
    };
  }

  // Convert Firestore JSON --> AppPig
  factory AppPig.fromJson(Map<String, dynamic> json, String documentId) {
    return AppPig(
      pigId: documentId, // Use the actual document ID
      userId: json['userId'] ?? '',
      breed: json['breed'] as String? ?? 'Unknown',
      birthDate: (json['birthDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      sex: json['sex'] as String? ?? 'Unknown',
      currentWeightKg: (json['currentWeightKg'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String? ?? '',
      stage: json['stage'] as String? ?? 'Unknown',
      status: json['status'] as String? ?? 'Unknown',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}