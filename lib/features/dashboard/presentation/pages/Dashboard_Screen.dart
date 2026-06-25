import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/widgets/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/widgets/text.dart';
import '../../../auth/presentation/cubits/profile_cubit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/ml_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

const String esp32Ip = "192.168.1.249";

// Global notifiers — shared across Dashboard, Temperature, and Humidity screens.
// Writing to these triggers listeners in every screen without any setState on AppNav.
final sprinklerNotifier = ValueNotifier<bool>(false);
final tempMaxTodayNotifier = ValueNotifier<double>(0);
final humidityMaxTodayNotifier = ValueNotifier<double>(0);

// ─────────────────────────────────────────────
// SprinklerMemory — persists across navigation and app restarts via Firestore
// ─────────────────────────────────────────────
class SprinklerMemory {
  static String lastActivated = "--";
  static String date = "--";
  static String duration = "--";
  static String status = "OFF";
  static DateTime? activatedAt;

  static Future<void> save() async {
    try {
      await FirebaseFirestore.instance
          .collection('sprinkler_state')
          .doc('latest')
          .set({
        'lastActivated': lastActivated,
        'date': date,
        'duration': duration,
        'status': status,
        'activatedAt':
        activatedAt != null ? Timestamp.fromDate(activatedAt!) : null,
      });
    } catch (e) {
      debugPrint('Error saving sprinkler state: $e');
    }
  }

  static Future<void> load() async {
    try {
      DocumentSnapshot? doc;
      // Try cache first — instant, works offline
      try {
        doc = await FirebaseFirestore.instance
            .collection('sprinkler_state')
            .doc('latest')
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        doc = null;
      }
      // Fallback to server if cache empty
      if (doc == null || !doc.exists) {
        try {
          doc = await FirebaseFirestore.instance
              .collection('sprinkler_state')
              .doc('latest')
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          doc = null;
        }
      }
      if (doc != null && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        lastActivated = data['lastActivated'] as String? ?? '--';
        date = data['date'] as String? ?? '--';
        duration = data['duration'] as String? ?? '--';
        status = data['status'] as String? ?? 'OFF';
        final at = data['activatedAt'];
        activatedAt = at != null ? (at as Timestamp).toDate() : null;
      }
    } catch (e) {
      debugPrint('Error loading sprinkler state: $e');
    }
  }
}

// ─────────────────────────────────────────────
// SensorMemory — in-memory cache shared across screens
// ─────────────────────────────────────────────
class SensorMemory {
  static double lastTemp = 0;
  static double lastHumidity = 0;
  static double lastTempMaxToday = 0;
  static String lastTempMaxDate = "--";
  static double lastHumidityMaxToday = 0;
  static String lastHumidityMaxDate = "--";
  static String lastPigStatus = "--";
  static String lastConnectionStatus = "Connecting...";
  static String lastSensorStatus = "Sensor Offline";
  static List<FlSpot> lastGraphSpots = [];
  static bool graphLoaded = false;

  // Temperature monitoring screen cache
  static List<Map<String, double>> lastTempChartData = [];
  static bool tempChartLoaded = false;
  static String lastTempChartDate = "";
  static double? lastTempDisplayMax;
  static double? lastTempDisplayMin;
  static double? lastTempDisplayAvg;
  static double? lastTempSessionMax;
  static double? lastTempSessionMin;

  // Humidity monitoring screen cache
  static List<Map<String, double>> lastHumidityChartData = [];
  static bool humidityChartLoaded = false;
  static String lastHumidityChartDate = "";
  static double? lastHumidityDisplayMax;
  static double? lastHumidityDisplayMin;
  static double? lastHumidityDisplayAvg;
  static double? lastHumiditySessionMax;
  static double? lastHumiditySessionMin;

  // Centralized setters so notifiers always stay in sync
  static void setTempMaxToday(double v) {
    lastTempMaxToday = v;
    tempMaxTodayNotifier.value = v;
  }

  static void setHumidityMaxToday(double v) {
    lastHumidityMaxToday = v;
    humidityMaxTodayNotifier.value = v;
  }

  static String todayKey() {
    final n = DateTime.now();
    return "${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}";
  }

  static void resetIfNewDay() {
    final today = todayKey();
    if (lastTempMaxDate != today) {
      setTempMaxToday(0);
      lastTempMaxDate = today;
    }
    if (lastHumidityMaxDate != today) {
      setHumidityMaxToday(0);
      lastHumidityMaxDate = today;
    }
    if (lastTempChartDate != today && lastTempChartDate.isNotEmpty) {
      lastTempChartData = [];
      tempChartLoaded = false;
      lastTempChartDate = today;
      lastTempDisplayMax = null;
      lastTempDisplayMin = null;
      lastTempDisplayAvg = null;
      lastTempSessionMax = null;
      lastTempSessionMin = null;
    }
    if (lastHumidityChartDate != today && lastHumidityChartDate.isNotEmpty) {
      lastHumidityChartData = [];
      humidityChartLoaded = false;
      lastHumidityChartDate = today;
      lastHumidityDisplayMax = null;
      lastHumidityDisplayMin = null;
      lastHumidityDisplayAvg = null;
      lastHumiditySessionMax = null;
      lastHumiditySessionMin = null;
    }
  }

  static Future<void> save() async {
    try {
      await FirebaseFirestore.instance
          .collection('sensor_memory')
          .doc('latest')
          .set({
        'lastTemp': lastTemp,
        'lastHumidity': lastHumidity,
        'tempMaxToday': lastTempMaxToday,
        'tempMaxDate': lastTempMaxDate,
        'humidityMaxToday': lastHumidityMaxToday,
        'humidityMaxDate': lastHumidityMaxDate,
        'lastPigStatus': lastPigStatus,
      });
    } catch (e) {
      debugPrint('Error saving sensor memory: $e');
    }
  }

  static Future<void> load() async {
    try {
      DocumentSnapshot? doc;
      try {
        doc = await FirebaseFirestore.instance
            .collection('sensor_memory')
            .doc('latest')
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        doc = null;
      }
      if (doc == null || !doc.exists) {
        try {
          doc = await FirebaseFirestore.instance
              .collection('sensor_memory')
              .doc('latest')
              .get(const GetOptions(source: Source.server));
        } catch (_) {
          doc = null;
        }
      }
      if (doc != null && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        lastTemp = (data['lastTemp'] as num?)?.toDouble() ?? 0;
        lastHumidity = (data['lastHumidity'] as num?)?.toDouble() ?? 0;
        setTempMaxToday((data['tempMaxToday'] as num?)?.toDouble() ?? 0);
        lastTempMaxDate = data['tempMaxDate'] as String? ?? '--';
        setHumidityMaxToday(
            (data['humidityMaxToday'] as num?)?.toDouble() ?? 0);
        lastHumidityMaxDate = data['humidityMaxDate'] as String? ?? '--';
        lastPigStatus = data['lastPigStatus'] as String? ?? '--';
        resetIfNewDay();
      }
    } catch (e) {
      debugPrint('Error loading sensor memory: $e');
    }
  }
}

// ─────────────────────────────────────────────
// DashboardScreen
// No constructor params — reads from global notifiers directly so
// AppNav never needs to call setState when sprinkler/sensor values change.
// ─────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  int _consecutiveFailures = 0;
  StreamSubscription? _connectivitySub;
  bool _isLoading = true;
  String _connectionStatus = "Connecting...";
  String _sensorStatus = "Connecting...";

  double _tempMax = 0;
  String _tempStatus = "Normal";
  double _waterPct = 0;
  String _waterStatus = "Unknown";
  double _lastKnownTemp = SensorMemory.lastTemp;
  double _lastKnownHumidity = SensorMemory.lastHumidity;
  bool _isSprinklerLoading = false;
  double _tempMaxToday = 0;
  double _humidityMaxToday = 0;
  double _humidityLive = SensorMemory.lastHumidity;

  String _sprinklerStatus = "OFF";
  String _lastActivated = "--";
  String _date = "--";
  String _duration = "--";
  String _pigStatus = "--";

  bool _graphShowLast24hrs = false;

  // ML
  String _mlCondition = "Analyzing...";
  List<String> _mlRecommendations = [];
  bool _mlLoading = true;
  List<FlSpot> _graphSpots = List.of(SensorMemory.lastGraphSpots);
  bool _graphLoading = !SensorMemory.graphLoaded;

  DateTime? _sprinklerActivatedAt;
  Timer? _durationTimer;
  bool _sprinklerMemoryLoaded = false;
  bool _sprinklerJustToggled = false;
  late bool _localIsActivated;

  // Crossfade animation
  bool _showingTemperature = true;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  Timer? _toggleTimer;

  @override
  void initState() {
    super.initState();
    // Read initial values from global notifiers — no props needed
    _localIsActivated = sprinklerNotifier.value;
    _tempMaxToday = tempMaxTodayNotifier.value;
    _humidityMaxToday = humidityMaxTodayNotifier.value;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);

    context.read<ProfileCubit>().loadUserData();

    sprinklerNotifier.addListener(_onSprinklerNotifierChanged);
    tempMaxTodayNotifier.addListener(_onTempMaxNotifierChanged);
    humidityMaxTodayNotifier.addListener(_onHumidityMaxNotifierChanged);

    Connectivity().checkConnectivity().then((results) {
      if (!mounted) return;
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      setState(() {
        _connectionStatus = hasNet ? "Live" : "Connecting...";
        SensorMemory.lastConnectionStatus = _connectionStatus;
      });
    });

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      setState(() {
        _connectionStatus = hasNet ? "Live" : "Connecting...";
        SensorMemory.lastConnectionStatus = _connectionStatus;
        if (!hasNet) {
          _sensorStatus = "Sensor Offline";
          SensorMemory.lastSensorStatus = "Sensor Offline";
        }
      });
    });

    _initializeData();
  }

  // didUpdateWidget intentionally removed — DashboardScreen has no props
  // to sync, so any call to didUpdateWidget was a sign of a parent setState
  // leaking into this widget's lifecycle.

  @override
  void dispose() {
    _timer?.cancel();
    _durationTimer?.cancel();
    _toggleTimer?.cancel();
    _connectivitySub?.cancel();
    _fadeController.dispose();
    sprinklerNotifier.removeListener(_onSprinklerNotifierChanged);
    tempMaxTodayNotifier.removeListener(_onTempMaxNotifierChanged);
    humidityMaxTodayNotifier.removeListener(_onHumidityMaxNotifierChanged);
    super.dispose();
  }

  // ── Notifier listeners ──────────────────────

  void _onSprinklerNotifierChanged() {
    if (!mounted) return;
    _sprinklerJustToggled = false;
    final newVal = sprinklerNotifier.value;
    if (_localIsActivated != newVal) {
      setState(() {
        _localIsActivated = newVal;
        _sprinklerStatus = newVal ? "ON" : "OFF";
        if (!newVal && _sprinklerActivatedAt != null) {
          _stopDurationTimer(keepDuration: true);
          SprinklerMemory.status = "OFF";
          SprinklerMemory.activatedAt = null;
        }
      });
    }
  }

  void _onTempMaxNotifierChanged() {
    if (!mounted) return;
    final v = tempMaxTodayNotifier.value;
    if (v != _tempMaxToday) setState(() => _tempMaxToday = v);
  }

  void _onHumidityMaxNotifierChanged() {
    if (!mounted) return;
    final v = humidityMaxTodayNotifier.value;
    if (v != _humidityMaxToday) setState(() => _humidityMaxToday = v);
  }

  // ── Sprinkler duration timer ─────────────────

  void _startDurationTimer(DateTime activatedAt) {
    _durationTimer?.cancel();
    _sprinklerActivatedAt = activatedAt;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_sprinklerActivatedAt!);
      final mins = elapsed.inMinutes;
      final secs = elapsed.inSeconds % 60;
      final d = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
      SprinklerMemory.duration = d;
      setState(() => _duration = d);
    });
  }

  void _stopDurationTimer({bool keepDuration = false}) {
    _durationTimer?.cancel();
    _durationTimer = null;
    if (keepDuration && _sprinklerActivatedAt != null) {
      final elapsed = DateTime.now().difference(_sprinklerActivatedAt!);
      final mins = elapsed.inMinutes;
      final secs = elapsed.inSeconds % 60;
      _duration = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    }
    _sprinklerActivatedAt = null;
  }

  // ── Initialisation ───────────────────────────

  Future<void> _initializeData() async {
    await Future.wait([SensorMemory.load(), SprinklerMemory.load()]);
    SensorMemory.resetIfNewDay();

    if (!mounted) return;

    setState(() {
      if (SensorMemory.lastTemp > 0) {
        _lastKnownTemp = SensorMemory.lastTemp;
        _tempMax = SensorMemory.lastTemp;
      }
      if (SensorMemory.lastHumidity > 0) {
        _lastKnownHumidity = SensorMemory.lastHumidity;
        _humidityLive = SensorMemory.lastHumidity;
      }
      _isLoading = false;
      if (SensorMemory.lastTempMaxToday > 0)
        _tempMaxToday = SensorMemory.lastTempMaxToday;
      if (SensorMemory.lastHumidityMaxToday > 0)
        _humidityMaxToday = SensorMemory.lastHumidityMaxToday;
      if (SensorMemory.lastPigStatus != "--")
        _pigStatus = SensorMemory.lastPigStatus;

      if (SprinklerMemory.lastActivated != "--")
        _lastActivated = SprinklerMemory.lastActivated;
      if (SprinklerMemory.date != "--") _date = SprinklerMemory.date;
      if (SprinklerMemory.duration != "--")
        _duration = SprinklerMemory.duration;
      _sprinklerStatus = SprinklerMemory.status;
      _sprinklerMemoryLoaded = true;

      if (SprinklerMemory.activatedAt != null && !_sprinklerJustToggled) {
        _localIsActivated = SprinklerMemory.status == "ON";
      }
    });

    // Resume duration timer if sprinkler was ON when app closed
    if (SprinklerMemory.activatedAt != null && _durationTimer == null) {
      _sprinklerActivatedAt = SprinklerMemory.activatedAt;
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final e = DateTime.now().difference(SprinklerMemory.activatedAt!);
        final m = e.inMinutes;
        final s = e.inSeconds % 60;
        final d = m > 0 ? '${m}m ${s}s' : '${s}s';
        SprinklerMemory.duration = d;
        setState(() => _duration = d);
      });
    }

    _fetchData();
    _fetchMLInsights();
    _loadGraphData();
    _syncTodayMaxFromFirestore();

    _timer =
        Timer.periodic(const Duration(seconds: 3), (_) => _fetchData());
    _toggleTimer = Timer.periodic(
        const Duration(seconds: 3), (_) => _crossfadeToggle());
  }

  // ── Crossfade temp/humidity display ─────────

  Future<void> _crossfadeToggle() async {
    if (!mounted) return;
    await _fadeController.reverse();
    if (!mounted) return;
    setState(() => _showingTemperature = !_showingTemperature);
    await _fadeController.forward();
  }

  // ── Sensor fetch (direct ESP32 only, no Firestore fallback) ─────────

  Future<void> _fetchData() async {
    Map<String, dynamic>? data;

    try {
      final response = await http
          .get(Uri.parse('http://$esp32Ip/sensor'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        data = jsonDecode(response.body) as Map<String, dynamic>;
        _consecutiveFailures = 0;
      }
    } catch (_) {
      _consecutiveFailures++;
    }

    if (data == null) {
      // Require 4 consecutive failures (~20s) before marking offline.
      // This absorbs the 1-3s blocking from ESP32's Firestore HTTPS poll.
      if (_consecutiveFailures < 4) return;
      if (!mounted) return;
      final results = await Connectivity().checkConnectivity();
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      setState(() {
        _connectionStatus = hasNet ? "Sensor Offline" : "No connection";
        _sensorStatus = "Sensor Offline";
        SensorMemory.lastConnectionStatus = _connectionStatus;
        SensorMemory.lastSensorStatus = "Sensor Offline";
        _isLoading = false;
      });
      return;
    }

    _consecutiveFailures = 0;
    if (!mounted) return;

    try {
      final tsField = data['timestamp'];
      DateTime? ts;
      if (tsField is String) ts = DateTime.tryParse(tsField);

      final nowUtc = DateTime.now().toUtc();
      final tsUtc = ts?.toUtc();
      final diffSeconds =
      tsUtc != null ? nowUtc.difference(tsUtc).inSeconds : -1;
      // abs() handles any remaining timezone offset edge cases
      final isStale = ts == null || diffSeconds.abs() > 20;

      if (isStale) {
        _consecutiveFailures++;
      } else {
        _consecutiveFailures = 0;
      }
      final shouldShowOffline = _consecutiveFailures >= 4;

      setState(() {
        final newTempLive = (data!['tempAvg'] as num?)?.toDouble();
        if (newTempLive != null && newTempLive > 0) {
          _tempMax = newTempLive;
          _lastKnownTemp = _tempMax;
          SensorMemory.lastTemp = _tempMax;
          SensorMemory.resetIfNewDay();
          if (newTempLive > SensorMemory.lastTempMaxToday) {
            SensorMemory.setTempMaxToday(newTempLive);
            SensorMemory.save();
          }
          _tempMaxToday = SensorMemory.lastTempMaxToday;
        }

        final newHumidity = (data['humidity'] as num?)?.toDouble();
        if (newHumidity != null && newHumidity > 0) {
          _humidityLive = newHumidity;
          _lastKnownHumidity = newHumidity;
          SensorMemory.lastHumidity = newHumidity;
          SensorMemory.resetIfNewDay();
          if (newHumidity > SensorMemory.lastHumidityMaxToday) {
            SensorMemory.setHumidityMaxToday(newHumidity);
            SensorMemory.save();
          }
          _humidityMaxToday = SensorMemory.lastHumidityMaxToday;
        }

        _tempStatus = data['tempStatus'] as String? ?? _tempStatus;

        if (!_sprinklerJustToggled) {
          _localIsActivated = sprinklerNotifier.value;
          _sprinklerStatus = _localIsActivated ? "ON" : "OFF";
        }

        if (!_sprinklerMemoryLoaded && _lastActivated == "--")
          _lastActivated =
              data['lastActivated'] as String? ?? _lastActivated;
        if (!_sprinklerMemoryLoaded && _date == "--")
          _date = data['date'] as String? ?? _date;
        if (_duration == "--" && _lastActivated == "--")
          _duration = data['duration'] as String? ?? _duration;

        final newPigStatus = data['pigStatus'] as String?;
        if (newPigStatus != null && newPigStatus != "--") {
          _pigStatus = newPigStatus;
          SensorMemory.lastPigStatus = newPigStatus;
        }

        if ((newTempLive != null && newTempLive > 0) ||
            (newHumidity != null && newHumidity > 0) ||
            (newPigStatus != null && newPigStatus != "--")) {
          SensorMemory.save();
        }

        _waterPct = (data['waterPct'] as num?)?.toDouble() ?? _waterPct;
        _waterStatus = data['waterStatus'] as String? ?? _waterStatus;
        _isLoading = false;

        // Only flip status label when truly settled — avoids flicker
        if (!isStale && _consecutiveFailures == 0) {
          _connectionStatus = "Live";
          SensorMemory.lastConnectionStatus = "Live";
          _sensorStatus = "Sensor Online";
          SensorMemory.lastSensorStatus = "Sensor Online";
        } else if (shouldShowOffline) {
          _connectionStatus = "Sensor Offline";
          SensorMemory.lastConnectionStatus = "Sensor Offline";
          _sensorStatus = "Sensor Offline";
          SensorMemory.lastSensorStatus = "Sensor Offline";
        }
        // Between 1-3 failures: keep previous label — no flicker
      });

      if (!_sprinklerJustToggled && !sprinklerNotifier.value &&
          _sprinklerActivatedAt != null) {
        final elapsed = DateTime.now().difference(_sprinklerActivatedAt!);
        if (elapsed.inSeconds > 3) _stopDurationTimer(keepDuration: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sensorStatus = "Sensor Offline";
        SensorMemory.lastSensorStatus = "Sensor Offline";
        _isLoading = false;
      });
    }
  }

  // ── Firestore: sync today's historical max on startup ───────────────

  Future<void> _syncTodayMaxFromFirestore() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      QuerySnapshot? tempSnapshot;
      try {
        tempSnapshot = await FirebaseFirestore.instance
            .collection('temperature_readings')
            .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
            .orderBy('timestamp')
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        tempSnapshot = null;
      }
      if (tempSnapshot == null || tempSnapshot.docs.isEmpty) {
        try {
          tempSnapshot = await FirebaseFirestore.instance
              .collection('temperature_readings')
              .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
              .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(now))
              .orderBy('timestamp')
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          tempSnapshot = null;
        }
      }

      double firestoreTempMax = 0;
      if (tempSnapshot != null) {
        for (final doc in tempSnapshot.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final t = (d['tempMax'] as num?)?.toDouble() ?? 0;
          if (t > firestoreTempMax) firestoreTempMax = t;
        }
      }

      QuerySnapshot? humiditySnapshot;
      try {
        humiditySnapshot = await FirebaseFirestore.instance
            .collection('humidity_readings')
            .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
            .orderBy('timestamp')
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        humiditySnapshot = null;
      }
      if (humiditySnapshot == null || humiditySnapshot.docs.isEmpty) {
        try {
          humiditySnapshot = await FirebaseFirestore.instance
              .collection('humidity_readings')
              .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
              .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(now))
              .orderBy('timestamp')
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          humiditySnapshot = null;
        }
      }

      double firestoreHumidityMax = 0;
      if (humiditySnapshot != null) {
        for (final doc in humiditySnapshot.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final h = (d['humidityMax'] as num?)?.toDouble() ?? 0;
          if (h > firestoreHumidityMax) firestoreHumidityMax = h;
        }
      }

      if (!mounted) return;

      if (firestoreTempMax > 0) {
        SensorMemory.resetIfNewDay();
        if (firestoreTempMax > SensorMemory.lastTempMaxToday) {
          SensorMemory.setTempMaxToday(firestoreTempMax);
          SensorMemory.save();
        }
        setState(() => _tempMaxToday = SensorMemory.lastTempMaxToday);
      }

      if (firestoreHumidityMax > 0) {
        SensorMemory.resetIfNewDay();
        if (firestoreHumidityMax > SensorMemory.lastHumidityMaxToday) {
          SensorMemory.setHumidityMaxToday(firestoreHumidityMax);
          SensorMemory.save();
        }
        setState(() => _humidityMaxToday = SensorMemory.lastHumidityMaxToday);
      }
    } catch (e) {
      debugPrint('Error syncing today max from Firestore: $e');
    }
  }

  // ── Graph ────────────────────────────────────

  Future<void> _loadGraphData() async {
    if (!SensorMemory.graphLoaded) setState(() => _graphLoading = true);
    try {
      final now = DateTime.now();
      final DateTime rangeStart = _graphShowLast24hrs
          ? now.subtract(const Duration(hours: 24))
          : DateTime(now.year, now.month, now.day);

      final snapshot = await FirebaseFirestore.instance
          .collection('temperature_hourly')
          .orderBy('timestamp', descending: false)
          .where('timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .limit(500)
          .get();

      final Map<int, List<double>> hourlyTemps = {};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        final temp = (data['tempAvg'] as num?)?.toDouble() ??
            (data['temperature'] as num?)?.toDouble() ??
            (data['tempMax'] as num?)?.toDouble();
        if (ts == null || temp == null) continue;
        final hourKey = _graphShowLast24hrs
            ? now.difference(ts).inHours
            : ts.hour;
        hourlyTemps.putIfAbsent(hourKey, () => []).add(temp);
      }

      final List<FlSpot> spots = [];
      hourlyTemps.forEach((hourKey, temps) {
        final avgTemp = temps.reduce((a, b) => a + b) / temps.length;
        final double x = _graphShowLast24hrs
            ? (24 - hourKey).toDouble()
            : hourKey.toDouble();
        spots.add(FlSpot(x.clamp(0, _graphShowLast24hrs ? 24 : 23), avgTemp));
      });
      spots.sort((a, b) => a.x.compareTo(b.x));

      if (!mounted) return;
      SensorMemory.lastGraphSpots = spots;
      SensorMemory.graphLoaded = true;
      setState(() {
        _graphSpots = spots;
        _graphLoading = false;
      });
    } catch (e) {
      debugPrint('Dashboard graph error: $e');
      if (!mounted) return;
      setState(() => _graphLoading = false);
    }
  }

  // ── ML insights ──────────────────────────────

  Future<void> _fetchMLInsights() async {
    try {
      final result = await MlService.analyzeFarm(
        temperatureC: _tempMax > 0 ? _tempMax : 28.0,
        humidityPct: _humidityMaxToday > 0 ? _humidityMaxToday : 75.0,
        weightChangeKg: 0.0,
        feedIntakeKg: 0.0,
      ).timeout(const Duration(seconds: 6));

      if (!mounted) return;
      final condition = result['condition'] ?? '';
      final recs = List<String>.from(result['recommendations'] ?? []);
      if (condition.isNotEmpty && recs.isNotEmpty) {
        setState(() {
          _mlCondition = condition;
          _mlRecommendations = recs;
          _mlLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mlCondition = "Unavailable";
        _mlRecommendations = [e.toString()];
        _mlLoading = false;
      });
    }
  }

  // ── Sprinkler toggle ─────────────────────────
  bool _isSprinklerDialogOpen = false;

  Future<void> _confirmSprinkler() async {
    if (_isSprinklerLoading || _isSprinklerDialogOpen) return;
    _isSprinklerDialogOpen = true;
    // Sensor offline does NOT block the button — command goes via Firestore

    final action = _localIsActivated ? 'Deactivate' : 'Activate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$action Sprinkler?'),
        content: Text(_localIsActivated
            ? 'Are you sure you want to turn the sprinkler off?'
            : 'Are you sure you want to turn the sprinkler on?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
              _localIsActivated ? const Color(0xFFD32F2F) : Colors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child:
            Text(action, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    _isSprinklerDialogOpen = false;
    if (!mounted) return;
    if (confirmed == true) await _toggleSprinkler(!_localIsActivated);
  }

  Future<void> _toggleSprinkler(bool turnOn) async {
    setState(() => _isSprinklerLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('sprinkler_command')
          .doc('pending')
          .set({'state': turnOn ? 'on' : 'off'});

      if (!mounted) return;

      final now = DateTime.now();
      setState(() => _localIsActivated = turnOn);
      sprinklerNotifier.value = turnOn; // broadcast to all screens

      if (turnOn) {
        final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
        final minute = now.minute.toString().padLeft(2, '0');
        final period = now.hour < 12 ? 'AM' : 'PM';
        final timeStr = '$hour:$minute $period';
        const months = [
          'Jan','Feb','Mar','Apr','May','Jun',
          'Jul','Aug','Sep','Oct','Nov','Dec'
        ];
        final dateStr =
            '${months[now.month - 1]} ${now.day.toString().padLeft(2, '0')}';

        SprinklerMemory.lastActivated = timeStr;
        SprinklerMemory.date = dateStr;
        SprinklerMemory.duration = '0s';
        SprinklerMemory.status = "ON";
        SprinklerMemory.activatedAt = now;
        SprinklerMemory.save();
        _sprinklerJustToggled = true;

        setState(() {
          _sprinklerStatus = "ON";
          _lastActivated = timeStr;
          _date = dateStr;
          _duration = '0s';
          _isSprinklerLoading = false;
        });
        _startDurationTimer(now);
      } else {
        String finalDuration = '--';
        if (_sprinklerActivatedAt != null) {
          final elapsed = DateTime.now().difference(_sprinklerActivatedAt!);
          final mins = elapsed.inMinutes;
          final secs = elapsed.inSeconds % 60;
          finalDuration = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
        }
        SprinklerMemory.duration = finalDuration;
        SprinklerMemory.status = "OFF";
        SprinklerMemory.activatedAt = null;
        SprinklerMemory.save();
        _stopDurationTimer();
        _sprinklerJustToggled = true;

        setState(() {
          _sprinklerStatus = "OFF";
          _isSprinklerLoading = false;
          _duration = finalDuration;
        });
      }

      // Wait longer than ESP32 poll interval (5s) before confirming
      await Future.delayed(const Duration(milliseconds: 6000));
      if (mounted) {
        await _fetchData();
        setState(() => _sprinklerJustToggled = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSprinklerLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send sprinkler command: $e")),
        );
      }
    }
  }

  // ── Decoration helper ────────────────────────

  BoxDecoration _bentoDecoration(bool isDark, {Color? accentColor}) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: accentColor?.withValues(alpha: 0.25) ??
            (isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06)),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: accentColor?.withValues(alpha: 0.10) ??
              (isDark
                  ? Colors.black.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.08)),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white.withValues(alpha: 0.9),
          blurRadius: 1,
          offset: const Offset(0, -1),
        ),
      ],
    );
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppTopBar(),
            const SizedBox(height: 16),
            _buildHeader(isDarkMode),
            const SizedBox(height: 16),
            _buildWeatherCard(isDarkMode),
            const SizedBox(height: 16),
            _buildQuickStatsRow(isDarkMode),
            const SizedBox(height: 16),
            _buildTemperatureGraph(isDarkMode),
            const SizedBox(height: 16),
            _buildBottomStatsRow(isDarkMode),
            const SizedBox(height: 16),
            _buildRecommendationCard(isDarkMode),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final isLive = _connectionStatus == "Live";
    final sensorOnline = _sensorStatus == "Sensor Online";
    final sensorColor = sensorOnline ? Colors.green : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.transparent,
              child: Icon(Symbols.account_circle,
                  size: 50, color: isDark ? Colors.white : Colors.black),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CustomText(
                      type: TextType.username,
                      prefix: 'Hello, ',
                      suffix: '👋',
                      fontSize: 20),
                  Text("Here's what's happening in your farm.",
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statusPill(
              isLive ? Icons.wifi : Icons.wifi_off,
              _connectionStatus,
              isLive ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            _statusPill(
              sensorOnline ? Icons.sensors : Icons.sensors_off,
              sensorOnline ? "Sensor Online" : "Sensor Offline",
              sensorColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildWeatherCard(bool isDark) {
    final showTemp = _showingTemperature;
    final displayTemp = _tempMax > 0 ? _tempMax : _lastKnownTemp;
    final displayHumidity =
    _humidityLive > 0 ? _humidityLive : _lastKnownHumidity;
    final isOffline = _sensorStatus == "Sensor Offline" ||
        _connectionStatus == "No connection";

    final value = _isLoading
        ? "--"
        : isOffline
        ? "--"
        : showTemp
        ? (displayTemp > 0
        ? "${displayTemp.toStringAsFixed(1)}°"
        : "--")
        : (displayHumidity > 0
        ? "${displayHumidity.toStringAsFixed(1)}%"
        : "--");

    final icon =
    showTemp ? Icons.thermostat_outlined : Icons.water_drop_outlined;
    final iconColor = showTemp ? Colors.orange : Colors.blue;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _bentoDecoration(isDark),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Row(children: [
                    Icon(icon, size: 14, color: iconColor),
                    const SizedBox(width: 4),
                    Text(showTemp ? "Temperature" : "Humidity",
                        style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.grey,
                            fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 4),
                _isLoading
                    ? const SizedBox(
                    height: 40,
                    width: 40,
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : FadeTransition(
                  opacity: _fadeAnimation,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) =>
                        SlideTransition(
                          position: Tween<Offset>(
                              begin: const Offset(0, 0.2),
                              end: Offset.zero)
                              .animate(animation),
                          child: FadeTransition(
                              opacity: animation, child: child),
                        ),
                    child: Text(value,
                        key: ValueKey(value),
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color:
                            isDark ? Colors.white : Colors.black)),
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  _buildDot(isActive: showTemp, color: Colors.orange),
                  const SizedBox(width: 4),
                  _buildDot(isActive: !showTemp, color: Colors.blue),
                ]),
              ],
            ),
          ),
          GestureDetector(
            onTap: _isSprinklerLoading ? null : _confirmSprinkler,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: _isSprinklerLoading
                    ? Colors.grey.shade400
                    : _localIsActivated
                    ? Colors.green
                    : const Color(0xFFD32F2F),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _isSprinklerLoading
                  ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      _localIsActivated
                          ? Icons.check_circle
                          : Icons.shower,
                      color: Colors.white,
                      size: 18),
                  const SizedBox(width: 6),
                  Text(
                      _localIsActivated ? 'Active' : 'Activate',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot({required bool isActive, required Color color}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isActive ? 16 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: isActive ? color : color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildQuickStatsRow(bool isDark) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildInfoCard(
              isDark,
              Symbols.bar_chart_4_bars,
              "Quick Stats",
              [
                "Max Temp Today: ${() {
                  SensorMemory.resetIfNewDay();
                  final v = SensorMemory.lastTempMaxToday > 0
                      ? SensorMemory.lastTempMaxToday
                      : _tempMaxToday;
                  return v == 0 ? '…' : '${v.toStringAsFixed(1)}°C';
                }()}",
                "Max Humidity Today: ${_humidityMaxToday == 0 ? '…' : '${_humidityMaxToday.toStringAsFixed(1)}%'}",
                "Pig Status: $_pigStatus",
              ],
              const Color(0xFFE53935),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _buildInfoCard(
              isDark,
              Symbols.shower,
              "Sprinkler Info",
              [
                "Status: $_sprinklerStatus",
                "Time: $_lastActivated",
                "Date: $_date",
                "Duration: $_duration",
              ],
              const Color(0xFF1E88E5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isDark, IconData icon, String title,
      List<String> items, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _bentoDecoration(isDark, accentColor: iconColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? Colors.white : Colors.black)),
            ),
          ]),
          const SizedBox(height: 10),
          ...items.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(e,
                style: TextStyle(
                    color: isDark
                        ? Colors.white60
                        : const Color(0xFF707070),
                    fontSize: 12)),
          )),
        ],
      ),
    );
  }

  Widget _buildTemperatureGraph(bool isDark) {
    final lineColor = Colors.green;
    final axisColor = isDark ? Colors.white38 : Colors.black26;
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    final spots = _graphSpots;
    final hasData = spots.isNotEmpty;
    final xMax = _graphShowLast24hrs ? 24.0 : 23.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _bentoDecoration(isDark, accentColor: Colors.green),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Symbols.monitoring,
                  color: Colors.green, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  _graphShowLast24hrs
                      ? "Temperature (Last 24 hrs)"
                      : "Temperature (Today)",
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            GestureDetector(
              onTap: () {
                setState(
                        () => _graphShowLast24hrs = !_graphShowLast24hrs);
                _loadGraphData();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green, width: 1),
                ),
                child: Text(
                    _graphShowLast24hrs ? "24 hrs" : "Today",
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.green)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("°C",
                  style: TextStyle(fontSize: 10, color: labelColor)),
              Text(
                  _graphShowLast24hrs ? "Hour (0 = 24hrs ago)" : "Hour",
                  style: TextStyle(fontSize: 10, color: labelColor)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: _graphLoading
                ? Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.green))
                : !hasData
                ? Center(
                child: Text("No temperature data available",
                    style: TextStyle(
                        color: labelColor, fontSize: 12)))
                : LineChart(LineChartData(
              minX: 0,
              maxX: xMax,
              minY: 18,
              maxY: 47,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.6,
                  color: lineColor,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (s, p, b, i) =>
                        FlDotCirclePainter(
                            radius: 2,
                            color: Colors.green,
                            strokeWidth: 0,
                            strokeColor: Colors.transparent),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        Colors.green.withValues(alpha: 0.35),
                        Colors.green.withValues(alpha: 0.10),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 5,
                getDrawingHorizontalLine: (_) => FlLine(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  bottom: BorderSide(
                      color: axisColor, width: 1.5),
                  left: BorderSide(
                      color: axisColor, width: 1.5),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles:
                    SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles:
                    SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      const labels = {
                        0: '12AM',
                        4: '4AM',
                        8: '8AM',
                        12: '12PM',
                        16: '4PM',
                        20: '8PM',
                        23: '11PM',
                      };
                      final h = value.toInt();
                      if (!labels.containsKey(h))
                        return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(labels[h]!,
                            style: TextStyle(
                                fontSize: 9,
                                color: labelColor)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: 5,
                    getTitlesWidget: (value, meta) {
                      const allowed = [
                        20, 25, 30, 35, 40, 45
                      ];
                      if (!allowed
                          .contains(value.toInt()) ||
                          value != value.roundToDouble())
                        return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text('${value.toInt()}°',
                            style: TextStyle(
                                fontSize: 10,
                                color: labelColor)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => isDark
                      ? const Color(0xFF2A2A2A)
                      : Colors.white,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      String label;
                      if (_graphShowLast24hrs) {
                        final hoursAgo =
                        (24 - spot.x).toInt();
                        label = hoursAgo == 0
                            ? 'Now'
                            : '${hoursAgo}h ago';
                      } else {
                        final h = spot.x.toInt();
                        final hour12 =
                        h % 12 == 0 ? 12 : h % 12;
                        label =
                        '$hour12:00 ${h >= 12 ? 'PM' : 'AM'}';
                      }
                      return LineTooltipItem(
                        '$label\n${spot.y.toStringAsFixed(1)}°C',
                        TextStyle(
                            color: lineColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      );
                    }).toList();
                  },
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatsRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(
            isDark,
            Symbols.calendar_month,
            "Vax Schedule",
            ["Vax name: ", "Date: "],
            const Color(0xFFFB8C00),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(child: _buildWaterLevelCard(isDark)),
      ],
    );
  }

  Widget _buildWaterLevelCard(bool isDark) {
    final statusColor = switch (_waterStatus) {
      "Full" => Colors.green,
      "Normal" => Colors.blue,
      "Low" => Colors.orange,
      "Critical" => Colors.red.shade900,
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
      _bentoDecoration(isDark, accentColor: const Color(0xFF1E88E5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color:
                  const Color(0xFF1E88E5).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Symbols.water_medium,
                  size: 15, color: Color(0xFF1E88E5)),
            ),
            const SizedBox(width: 8),
            Text("Water Level",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black)),
          ]),
          const SizedBox(height: 10),
          Text("Level: ${_waterPct.toStringAsFixed(0)}%",
              style: TextStyle(
                  color: isDark
                      ? Colors.white60
                      : const Color(0xFF707070),
                  fontSize: 12)),
          const SizedBox(height: 4),
          Row(children: [
            Text("Status: ",
                style: TextStyle(
                    color: isDark
                        ? Colors.white60
                        : const Color(0xFF707070),
                    fontSize: 12)),
            Text(_waterStatus,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_waterPct / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor:
              isDark ? Colors.white12 : Colors.grey.shade200,
              valueColor:
              AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(bool isDark) {
    Color conditionColor = Colors.amber;
    if (_mlCondition == "Good") conditionColor = Colors.green;
    if (_mlCondition == "High Risk") conditionColor = Colors.red;
    if (_mlCondition == "Unavailable") conditionColor = Colors.grey;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _bentoDecoration(isDark, accentColor: conditionColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: conditionColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.lightbulb_outline,
                  size: 15, color: conditionColor),
            ),
            const SizedBox(width: 8),
            Text("Smart Recommendation",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black)),
            const Spacer(),
            if (!_mlLoading)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: conditionColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: conditionColor, width: 1),
                ),
                child: Text(_mlCondition,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: conditionColor)),
              ),
          ]),
          const SizedBox(height: 10),
          if (_mlLoading)
            Row(children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text("Analyzing farm conditions...",
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white60
                          : const Color(0xFF707070))),
            ])
          else if (_mlRecommendations.isEmpty)
            Text("No recommendations at this time.",
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? Colors.white60
                        : const Color(0xFF707070)))
          else
            ..._mlRecommendations.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_right,
                      size: 16, color: conditionColor),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(r,
                          style: TextStyle(
                              color: isDark
                                  ? Colors.white60
                                  : const Color(0xFF707070),
                              fontSize: 12))),
                ],
              ),
            )),
          if (!_mlLoading && _mlCondition != "Unavailable")
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(Icons.memory,
                    size: 11,
                    color: isDark ? Colors.white30 : Colors.black26),
                const SizedBox(width: 4),
                Text("Powered by PRISM trained ML · live sensor data",
                    style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? Colors.white30
                            : Colors.black38)),
              ]),
            ),
        ],
      ),
    );
  }
}