import 'package:cloud_firestore/cloud_firestore.dart';

/// FarmDataService
/// Fetches and computes farm-level summaries from Firestore.
///
/// The former getFarmMLInputs() was removed: it substituted invented values
/// (28 degC / 75 % RH) when no readings existed and fed them to the ML
/// service. The thermal-status assessment now uses the live reading only
/// (see MlService.assess).
class FarmDataService {
  static final _db = FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // 1. TEMPERATURE — last 24 hrs average from temperature_readings
  //    Fields: tempAvg, tempMax, tempMin, timestamp (Timestamp)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<double> getLast24hrAvgTemperature() async {
    try {
      final since = DateTime.now().subtract(const Duration(hours: 24));

      final snapshot = await _db
          .collection('temperature_hourly')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(since))
          .orderBy('timestamp', descending: true)
          .get();

      if (snapshot.docs.isEmpty) return 0.0;

      // Use tempAvg field from each document
      final values = snapshot.docs
          .map((d) => (d.data()['tempAvg'] as num?)?.toDouble())
          .whereType<double>()
          .toList();

      if (values.isEmpty) return 0.0;
      return values.reduce((a, b) => a + b) / values.length;
    } catch (e) {
      print('>>> FarmDataService temp error: $e');
      return 0.0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. HUMIDITY — last 24 hrs average from humidity_readings
  //    Fields: humidityAvg, humidityMax, humidityMin, timestamp (Timestamp)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<double> getLast24hrAvgHumidity() async {
    try {
      final since = DateTime.now().subtract(const Duration(hours: 24));

      final snapshot = await _db
          .collection('humidity_hourly')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(since))
          .orderBy('timestamp', descending: true)
          .get();

      if (snapshot.docs.isEmpty) return 0.0;

      // Use humidityAvg field from each document
      final values = snapshot.docs
          .map((d) => (d.data()['humidityAvg'] as num?)?.toDouble())
          .whereType<double>()
          .toList();

      if (values.isEmpty) return 0.0;
      return values.reduce((a, b) => a + b) / values.length;
    } catch (e) {
      print('>>> FarmDataService humidity error: $e');
      return 0.0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. FEED INTAKE — total amount fed today across ALL pigs
  //    Path: pigs/{pigId}/feeding_records/{docId}
  //    Fields: amount (num), timestamp (String ISO format)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<double> getTodayTotalFeedIntake(String userId) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      // Get all active pigs for this user
      final pigsSnapshot = await _db
          .collection('pigs')
          .where('userId', isEqualTo: userId)
          .where('status', whereIn: ['Normal/Healthy', 'Abnormal/Sick'])
          .get();

      if (pigsSnapshot.docs.isEmpty) return 0.0;

      double totalFeed = 0.0;

      // For each pig, sum today's feeding records
      for (final pigDoc in pigsSnapshot.docs) {
        final feedSnapshot = await _db
            .collection('pigs')
            .doc(pigDoc.id)
            .collection('feeding_records')
            .get();

        for (final doc in feedSnapshot.docs) {
          final data = doc.data();

          // timestamp is stored as String: "2026-06-15T08:49:19.835932"
          final timestampStr = data['timestamp'] as String?;
          if (timestampStr == null) continue;

          final recordDate = DateTime.tryParse(timestampStr);
          if (recordDate == null) continue;

          // Only count today's records
          if (recordDate.isAfter(startOfDay)) {
            final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
            totalFeed += amount;
          }
        }
      }

      return totalFeed;
    } catch (e) {
      print('>>> FarmDataService feed error: $e');
      return 0.0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. WEIGHT CHANGE — average daily gain (ADG) across all active pigs
  //    Path: pigs/{pigId}/weight_history/{docId}
  //    Fields: weightKg (num), dateRecorded (Timestamp)
  //    Formula: ADG = (latest weight - earliest weight) / days between
  // ─────────────────────────────────────────────────────────────────────────
  static Future<double> getAvgWeightChange(String userId) async {
    try {
      // Get all active pigs for this user
      final pigsSnapshot = await _db
          .collection('pigs')
          .where('userId', isEqualTo: userId)
          .where('status', whereIn: ['Normal/Healthy', 'Abnormal/Sick'])
          .get();

      if (pigsSnapshot.docs.isEmpty) return 0.0;

      final List<double> adgList = [];

      for (final pigDoc in pigsSnapshot.docs) {
        final data = pigDoc.data();

        // Use birthWeightKg and currentWeightKg from the pig document itself
        final birthWeight = (data['birthWeightKg'] as num?)?.toDouble() ?? 0.0;
        final currentWeight =
            (data['currentWeightKg'] as num?)?.toDouble() ?? 0.0;
        final birthDate = (data['birthDate'] as Timestamp?)?.toDate();

        if (birthDate == null || birthWeight == 0.0) continue;

        final ageDays = DateTime.now().difference(birthDate).inDays;
        if (ageDays <= 0) continue;

        // ADG = (current - birth) / age in days
        final adg = (currentWeight - birthWeight) / ageDays;
        adgList.add(adg);
      }

      if (adgList.isEmpty) return 0.0;

      // Return average ADG across all pigs
      final avg = adgList.reduce((a, b) => a + b) / adgList.length;
      return double.parse(avg.toStringAsFixed(3));
    } catch (e) {
      print('>>> FarmDataService weight error: $e');
      return 0.0;
    }
  }
}
