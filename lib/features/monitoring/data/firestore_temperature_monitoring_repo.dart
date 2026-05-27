import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../domain/model/app_temperature_reading.dart';
import '../domain/repo/temperature_monitoring_repo.dart';

class FirestoreTemperatureMonitoringRepo implements TemperatureMonitoringRepo {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String esp32Ip = "192.168.1.100";

  @override
  Future<AppTemperatureReading> fetchLiveHardwareTelemetry() async {
    final response = await http
        .get(Uri.parse("http://$esp32Ip/data"))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final Map<String, dynamic> rawJson = jsonDecode(response.body);

      // 👇 Maps data directly into your clean model object right at the infrastructure border
      return AppTemperatureReading.fromJson(rawJson, 'live_stream_entry');
    }
    throw Exception('Failed to connect to local hardware endpoint');
  }

  @override
  Future<bool> setSprinklerState(bool turnOn) async {
    final state = turnOn ? "on" : "off";
    final response = await http
        .get(Uri.parse("http://$esp32Ip/sprinkler?state=$state"))
        .timeout(const Duration(seconds: 5));
    return response.statusCode == 200;
  }

  @override
  Future<void> saveTemperatureReading(AppTemperatureReading reading) async {
    await _firestore.collection('temperature_readings').add(reading.toJson());
  }

  @override
  Stream<List<AppTemperatureReading>> streamFilteredReadings(int timeRangeIndex) {
    final now = DateTime.now();
    DateTime? startDate;

    switch (timeRangeIndex) {
      case 1: // This Month
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 2: // This Week
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        break;
      case 3: // Today
        startDate = DateTime(now.year, now.month, now.day);
        break;
      default: // All Time
        startDate = null;
    }

    Query query = _firestore
        .collection('temperature_readings')
        .orderBy('timestamp', descending: false);

    if (startDate != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return AppTemperatureReading.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }
}