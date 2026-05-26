import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Run `flutter pub add intl` if you don't have this yet

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

  // Clean mapping that matches your previous save logic fields exactly
  factory AppFeedingHistory.fromJson(Map<String, dynamic> json, String documentId) {
    // 👇 1. Safely parse the timestamp regardless of how it was saved
    DateTime parsedDate = DateTime.now(); // Default fallback

    final rawTimestamp = json['timestamp'];
    if (rawTimestamp is Timestamp) {
      parsedDate = rawTimestamp.toDate();
    } else if (rawTimestamp is String) {
      // If it was accidentally saved as a String, parse it cleanly
      parsedDate = DateTime.tryParse(rawTimestamp) ?? DateTime.now();
    }

    return AppFeedingHistory(
      id: documentId,
      pigId: json['pigId'] ?? '',
      feedType: json['feedType'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      timestamp: parsedDate, // 👈 2. Use the safely parsed date here
    );
  }

  // ── Convenience Getters for your UI ─────────────────────────────

  // 👇 Returns formatted date like: "May 26, 2026"
  String get formattedDate => DateFormat.yMMMMd().format(timestamp);

  // 👇 Returns formatted time like: "8:30 PM"
  String get formattedTime => DateFormat.jm().format(timestamp);
}