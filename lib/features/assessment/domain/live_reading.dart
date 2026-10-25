/// The live sensor payload (LiveSensorService.latestData: ESP32 /sensor or
/// live_sensor/latest) mapped to API request bodies. Read-only: nothing here writes.
class LiveReading {
  final DateTime time;
  final bool phoneTime; // true when the device clock was not usable
  final double? airTempC;
  final bool? airTempValid;
  final double? humidityPct;
  final bool? humidityValid;
  final double? penSurfaceC; // AMG8833 pen-level summary (legacy field name pigBodyTemp)
  final bool? penSurfaceValid;
  final bool? sprinklerOn;

  LiveReading({
    required this.time,
    required this.phoneTime,
    this.airTempC,
    this.airTempValid,
    this.humidityPct,
    this.humidityValid,
    this.penSurfaceC,
    this.penSurfaceValid,
    this.sprinklerOn,
  });

  static double? _num(dynamic v) => v is num ? v.toDouble() : null;

  static DateTime? _time(dynamic ts) {
    if (ts is String) return DateTime.tryParse(ts);
    if (ts is DateTime) return ts;
    try {
      return (ts as dynamic).toDate() as DateTime; // Firestore Timestamp
    } catch (_) {
      return null;
    }
  }

  static LiveReading? fromLive(Map<String, dynamic>? data, DateTime receivedAt) {
    if (data == null) return null;
    final t = _time(data['timestamp']);
    final usable = t != null && t.year >= 2020; // same NTP-failure rule as LiveSensorService
    return LiveReading(
      time: usable ? t : receivedAt,
      phoneTime: !usable,
      airTempC: _num(data['ambientTemp']),
      airTempValid: data['ambientTempValid'] as bool?,
      humidityPct: _num(data['ambientHumidity']),
      humidityValid: data['ambientHumidityValid'] as bool?,
      penSurfaceC: _num(data['pigBodyTemp']),
      penSurfaceValid: data['pigBodyTempValid'] as bool?,
      sprinklerOn: data['sprinkler'] as bool?,
    );
  }

  double? get usableAirTemp => airTempValid == false ? null : airTempC;
  double? get usableHumidity => humidityValid == false ? null : humidityPct;

  Map<String, dynamic> environmentBody() => {
        'readings': [
          {
            'timestamp': time.toUtc().toIso8601String(),
            'dht_temp_c': usableAirTemp,
            'dht_humidity_pct': usableHumidity,
            'dht_temp_valid': airTempValid,
            'dht_humidity_valid': humidityValid,
            'sprinkler_on': sprinklerOn,
          }
        ],
      };

  Map<String, dynamic> penThermalBody() => {
        'current': {
          'timestamp': time.toUtc().toIso8601String(),
          'amg_summary_c': penSurfaceValid == false ? null : penSurfaceC,
          'dht_temp_c': usableAirTemp,
          if (penSurfaceValid == false) 'amg_summary_c__state': 'sensor_offline',
          if (airTempValid == false) 'dht_temp_c__state': 'sensor_offline',
        },
        'history': const [],
      };

  Map<String, dynamic> rawRef() => {
        'path': 'live_sensor/latest',
        'docId': null,
        'observedAt': time.toUtc().toIso8601String(),
        'note': 'live document is overwritten; values are copied in inputSummary',
      };
}
