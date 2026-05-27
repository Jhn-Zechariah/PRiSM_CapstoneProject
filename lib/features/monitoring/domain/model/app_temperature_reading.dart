import 'package:cloud_firestore/cloud_firestore.dart';

class AppTemperatureReading {
  final String id;
  final double tempMax;
  final double tempAvg;
  final double tempMin;
  final String tempStatus;
  final DateTime timestamp;

  AppTemperatureReading({
    required this.id,
    required this.tempMax,
    required this.tempAvg,
    required this.tempMin,
    required this.tempStatus,
    required this.timestamp,
  });

  factory AppTemperatureReading.fromJson(Map<String, dynamic> json, String docId) {
    DateTime parsedDate = DateTime.now();
    final rawTimestamp = json['timestamp'];

    if (rawTimestamp is Timestamp) {
      parsedDate = rawTimestamp.toDate();
    } else if (rawTimestamp is String) {
      parsedDate = DateTime.tryParse(rawTimestamp) ?? DateTime.now();
    }

    return AppTemperatureReading(
      id: docId,
      tempMax: (json['tempMax'] ?? 0.0).toDouble(),
      tempAvg: (json['tempAvg'] ?? 0.0).toDouble(),
      tempMin: (json['tempMin'] ?? 0.0).toDouble(),
      tempStatus: json['tempStatus'] ?? 'Unknown',
      timestamp: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tempMax': tempMax,
      'tempAvg': tempAvg,
      'tempMin': tempMin,
      'tempStatus': tempStatus,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}