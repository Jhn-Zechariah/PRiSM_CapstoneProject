import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AppFeedingHistory {
  final String id;
  final String pigId;
  final String feedType;
  final double amount;
  final DateTime timestamp;

  AppFeedingHistory({
    required this.id,
    required this.pigId,
    required this.feedType,
    required this.amount,
    required this.timestamp,
  });

  factory AppFeedingHistory.fromJson(
      Map<String, dynamic> json,
      String documentId,
      ) {
    // Already safe — handles both Timestamp and String. No changes needed.
    DateTime parsedDate = DateTime.now();
    final rawTimestamp = json['timestamp'];
    if (rawTimestamp is Timestamp) {
      parsedDate = rawTimestamp.toDate();
    } else if (rawTimestamp is String) {
      parsedDate = DateTime.tryParse(rawTimestamp) ?? DateTime.now();
    }

    return AppFeedingHistory(
      id: documentId,
      pigId: json['pigId'] ?? '',
      feedType: json['feedType'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      timestamp: parsedDate,
    );
  }

  // ── Convenience Getters ────────────────────────────────────────────────────

  String get formattedDate => DateFormat.yMMMMd().format(timestamp);
  String get formattedTime => DateFormat.jm().format(timestamp);
}