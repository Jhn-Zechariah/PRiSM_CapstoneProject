class AppFeedingRecord {
  final String id;
  final String pigId;
  final String feedType;
  final double amount;
  final DateTime timestamp;

  AppFeedingRecord({
    required this.id,
    required this.pigId,
    required this.feedType,
    required this.amount,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pigId': pigId,
      'feedType': feedType,
      'amount': amount,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory AppFeedingRecord.fromMap(Map<String, dynamic> map) {
    return AppFeedingRecord(
      id: map['id'] ?? '',
      pigId: map['pigId'] ?? '',
      feedType: map['feedType'] ?? '',
      amount: (map['amount'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}