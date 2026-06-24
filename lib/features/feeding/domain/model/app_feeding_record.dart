import 'package:cloud_firestore/cloud_firestore.dart';

class AppFeedingRecord {
  final String id;
  final String pigId;
  final String userId;
  final String feedType;
  final double amount;
  final DateTime timestamp;

  AppFeedingRecord({
    required this.id,
    required this.pigId,
    required this.userId,
    required this.feedType,
    required this.amount,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pigId': pigId,
      'userId': userId,
      'feedType': feedType,
      'amount': amount,
      // FIX #2 (Critical): Save as native Firestore Timestamp, NOT toIso8601String().
      // Saving as a String breaks orderBy('timestamp') on collectionGroup queries
      // because Firestore string ordering is lexicographic, not chronological.
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory AppFeedingRecord.fromMap(Map<String, dynamic> map) {
    // FIX #1 (Critical): Safe timestamp parsing — mirrors AppFeedingHistory.
    // Previously used DateTime.parse(map['timestamp']) which throws a
    // FormatException when the field is a Firestore Timestamp object (not a
    // String), and crashes with a Null check error when the field is missing.
    DateTime parsedDate = DateTime.now();
    final raw = map['timestamp'];
    if (raw is Timestamp) {
      parsedDate = raw.toDate();
    } else if (raw is String) {
      // Legacy fallback: records saved before FIX #2 stored ISO strings.
      // Keep this branch so old data still loads correctly after migration.
      parsedDate = DateTime.tryParse(raw) ?? DateTime.now();
    }

    return AppFeedingRecord(
      id: map['id'] ?? '',
      pigId: map['pigId'] ?? '',
      userId: map['userId'] ?? '',
      feedType: map['feedType'] ?? '',
      // FIX #1 cont.: Guard against null before casting — avoids Null cast crash.
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      timestamp: parsedDate,
    );
  }
}