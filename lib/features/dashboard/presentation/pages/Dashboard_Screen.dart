import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
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
// Hour-boundary helper — used by Dashboard, Temperature, and Humidity to
// decide when their hourly-aggregate chart caches need to be refreshed.
// The ESP32 only writes one new document to temperature_hourly /
// humidity_hourly per hour, so there is no value in re-querying more
// often than that. Each screen stores the "hour key" it last loaded data
// for, and only re-queries Firestore once the current hour key has moved
// past that — whether because the screen reopened later, or because a
// Timer.periodic(1 hour) tick fired while it stayed open.
// ─────────────────────────────────────────────
String currentHourKey() {
  final n = DateTime.now();
  return "${n.year}-${n.month.toString().padLeft(2, '0')}-"
      "${n.day.toString().padLeft(2, '0')}-${n.hour.toString().padLeft(2, '0')}";
}

// ─────────────────────────────────────────────
// LiveSensorService — SINGLE shared poller for live sensor data.
//
// Replaces the old pattern where Dashboard, Temperature, and Humidity each
// ran their own Timer.periodic + http.get() against the ESP32. Now there's
// exactly ONE polling loop system-wide:
//
//   1. Try the ESP32's local HTTP endpoint first (fast, ~50-200ms, zero
//      Firestore cost). Works whenever the phone is on the same LAN as
//      the ESP32.
//   2. If that fails (phone is on mobile data / different WiFi / ESP32
//      unreachable), fall back to a Firestore snapshot listener on
//      live_sensor/latest — which the ESP32 pushes to every ~7s. This
//      works from anywhere with internet.
//
// All three screens read from this service's ValueNotifiers instead of
// fetching themselves. This cuts redundant LAN calls 3x -> 1x and ensures
// Firestore reads (when away from home) only happen once system-wide
// instead of once per open screen.
// ─────────────────────────────────────────────
class LiveSensorService {
  static Timer? _timer;
  static StreamSubscription<DocumentSnapshot>? _firestoreSub;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static int _consecutiveFailures = 0;
  static bool _started = false;

  // Unified staleness rule used everywhere (was 20s/4-fail on Dashboard,
  // 15s/2-fail on Temperature & Humidity — now consistent across all three,
  // using the more lenient values since those already correctly absorb
  // the ESP32's blocking Firestore/sprinkler-poll calls without flicker).
  static const int _stalenessLimitSeconds = 20;
  static const int _failuresBeforeOffline = 4;

  /// Latest raw sensor JSON, however it was sourced (LAN or Firestore).
  /// Screens listen to this directly via ValueListenableBuilder.
  static final ValueNotifier<Map<String, dynamic>?> latestData = ValueNotifier(
    null,
  );
  static final ValueNotifier<String> connectionStatus = ValueNotifier<String>(
    "Connecting...",
  );
  static final ValueNotifier<String> sensorStatus = ValueNotifier<String>(
    "Sensor Offline",
  );

  /// Call once, guarded, from DashboardScreen.initState().
  static void start() {
    if (_started) return;
    _started = true;

    Connectivity().checkConnectivity().then((results) {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      connectionStatus.value = hasNet ? "Live" : "Connecting...";
    });

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (!hasNet) {
        connectionStatus.value = "Connecting...";
        sensorStatus.value = "Sensor Offline";
      } else {
        // Net just came back — try a poll immediately instead of waiting
        // for the next tick, so the UI recovers fast.
        _poll();
      }
    });

    _poll();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  static Future<void> _poll() async {
    Map<String, dynamic>? data;

    // 1. LAN first — fastest path, zero Firestore read cost.
    try {
      final response = await http
          .get(Uri.parse('http://$esp32Ip/sensor'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      // not on home network, or ESP32 unreachable — fall through
    }

    if (data != null) {
      _attachFirestoreFallbackIfNeeded(); // keep it warm for when LAN drops
      _applyData(data);
      return;
    }

    // 2. LAN failed — ensure the Firestore fallback listener is attached.
    // Its snapshots feed _applyData() asynchronously as they arrive; here
    // we just track the failure streak for the LAN path itself.
    _attachFirestoreFallbackIfNeeded();
    _consecutiveFailures++;
    if (_consecutiveFailures >= _failuresBeforeOffline &&
        latestData.value == null) {
      final results = await Connectivity().checkConnectivity();
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      connectionStatus.value = hasNet ? "Sensor Offline" : "No connection";
      sensorStatus.value = "Sensor Offline";
    }
  }

  static void _attachFirestoreFallbackIfNeeded() {
    if (_firestoreSub != null) return;
    _firestoreSub = FirebaseFirestore.instance
        .collection('live_sensor')
        .doc('latest')
        .snapshots()
        .listen((snap) {
          if (!snap.exists) return;
          final data = snap.data();
          if (data == null) return;
          _applyData(data);
        }, onError: (_) {});
  }

  static void _applyData(Map<String, dynamic> data) {
    DateTime? ts;
    final tsField = data['timestamp'];
    if (tsField is String) {
      ts = DateTime.tryParse(tsField);
    } else if (tsField is Timestamp) {
      ts = tsField.toDate();
    }

    final nowUtc = DateTime.now().toUtc();
    final tsUtc = ts?.toUtc();
    final diffSeconds = tsUtc != null ? nowUtc.difference(tsUtc).inSeconds : -1;
    final isStale = ts == null || diffSeconds.abs() > _stalenessLimitSeconds;

    if (isStale) {
      _consecutiveFailures++;
    } else {
      _consecutiveFailures = 0;
    }
    final shouldShowOffline = _consecutiveFailures >= _failuresBeforeOffline;

    if (!isStale) {
      connectionStatus.value = "Live";
      sensorStatus.value = "Sensor Online";
      latestData.value = data;
      SensorMemory.lastConnectionStatus = "Live";
      SensorMemory.lastSensorStatus = "Sensor Online";
    } else if (shouldShowOffline) {
      connectionStatus.value = "Sensor Offline";
      sensorStatus.value = "Sensor Offline";
      SensorMemory.lastConnectionStatus = "Sensor Offline";
      SensorMemory.lastSensorStatus = "Sensor Offline";
    }
    // Between 1 and (failuresBeforeOffline-1) failures: keep previous
    // label — avoids flicker from a single transient miss.
  }

  /// Only call this if the whole app is tearing down — screens should NOT
  /// call this in their own dispose(), since other screens may still need
  /// the service running.
  static void stop() {
    _timer?.cancel();
    _timer = null;
    _firestoreSub?.cancel();
    _firestoreSub = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _started = false;
  }
}

class VaxScheduleMemory {
  static String medName = "--";
  static String dateLabel = "--";
  static bool loaded = false;
}

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
            'activatedAt': activatedAt != null
                ? Timestamp.fromDate(activatedAt!)
                : null,
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
  static String lastGraphHourKey = "";

  // Temperature monitoring screen cache
  static List<Map<String, double>> lastTempChartData = [];
  static bool tempChartLoaded = false;
  static String lastTempChartDate = "";
  static String lastTempChartHourKey = "";
  static double? lastTempDisplayMax;
  static double? lastTempDisplayMin;
  static double? lastTempDisplayAvg;
  static double? lastTempSessionMax;
  static double? lastTempSessionMin;

  // Humidity monitoring screen cache
  static List<Map<String, double>> lastHumidityChartData = [];
  static bool humidityChartLoaded = false;
  static String lastHumidityChartDate = "";
  static String lastHumidityChartHourKey = "";
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
          (data['humidityMaxToday'] as num?)?.toDouble() ?? 0,
        );
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
  bool _isLoading = true;

  String _vaxMedName = VaxScheduleMemory.medName;
  String _vaxDateLabel = VaxScheduleMemory.dateLabel;


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

  // ML
  String _mlCondition = "Analyzing...";
  List<String> _mlRecommendations = [];
  bool _mlLoading = true;
  List<FlSpot> _graphSpots = List.of(SensorMemory.lastGraphSpots);
  bool _graphLoading = !SensorMemory.graphLoaded;
  Timer? _hourlyRefreshTimer;

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

    // Starts the single shared LAN-first/Firestore-fallback poller.
    // Guarded internally — safe to call even if Dashboard remounts.
    LiveSensorService.start();

    // Read initial values from global notifiers — no props needed
    _localIsActivated = sprinklerNotifier.value;
    _tempMaxToday = tempMaxTodayNotifier.value;
    _humidityMaxToday = humidityMaxTodayNotifier.value;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    context.read<ProfileCubit>().loadUserData();

    sprinklerNotifier.addListener(_onSprinklerNotifierChanged);
    tempMaxTodayNotifier.addListener(_onTempMaxNotifierChanged);
    humidityMaxTodayNotifier.addListener(_onHumidityMaxNotifierChanged);

    // Listen to the shared service instead of polling ourselves.
    LiveSensorService.latestData.addListener(_onLiveDataChanged);
    LiveSensorService.connectionStatus.addListener(_onConnectionStatusChanged);
    LiveSensorService.sensorStatus.addListener(_onSensorStatusChanged);

    _initializeData();
  }

  // didUpdateWidget intentionally removed — DashboardScreen has no props
  // to sync, so any call to didUpdateWidget was a sign of a parent setState
  // leaking into this widget's lifecycle.

  @override
  void dispose() {
    _durationTimer?.cancel();
    _toggleTimer?.cancel();
    _hourlyRefreshTimer?.cancel();
    _fadeController.dispose();
    sprinklerNotifier.removeListener(_onSprinklerNotifierChanged);
    tempMaxTodayNotifier.removeListener(_onTempMaxNotifierChanged);
    humidityMaxTodayNotifier.removeListener(_onHumidityMaxNotifierChanged);
    LiveSensorService.latestData.removeListener(_onLiveDataChanged);
    LiveSensorService.connectionStatus.removeListener(
      _onConnectionStatusChanged,
    );
    LiveSensorService.sensorStatus.removeListener(_onSensorStatusChanged);
    // NOTE: we do NOT call LiveSensorService.stop() here — Temperature and
    // Humidity screens may still be alive and depend on it continuing to run.
    super.dispose();
  }

  // ── Shared service listeners ─────────────────

  void _onConnectionStatusChanged() {
    if (!mounted) return;
    setState(
      () {},
    ); // _buildHeader reads LiveSensorService.connectionStatus.value directly
  }

  void _onSensorStatusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onLiveDataChanged() {
    if (!mounted) return;
    final data = LiveSensorService.latestData.value;
    if (data == null) return;

    setState(() {
      final newTempLive =
          (data['tempMax'] as num?)?.toDouble() ??
          (data['tempAvg'] as num?)?.toDouble();
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

      if (!_sprinklerMemoryLoaded && _lastActivated == "--") {
        _lastActivated = data['lastActivated'] as String? ?? _lastActivated;
      }
      if (!_sprinklerMemoryLoaded && _date == "--") {
        _date = data['date'] as String? ?? _date;
      }
      if (_duration == "--" && _lastActivated == "--") {
        _duration = data['duration'] as String? ?? _duration;
      }

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

      final newWaterPct = (data['waterPct'] as num?)?.toDouble();
      if (newWaterPct != null) _waterPct = newWaterPct;
      _waterStatus = data['waterStatus'] as String? ?? _waterStatus;
      _isLoading = false;
    });

    if (!_sprinklerJustToggled &&
        !sprinklerNotifier.value &&
        _sprinklerActivatedAt != null) {
      final elapsed = DateTime.now().difference(_sprinklerActivatedAt!);
      if (elapsed.inSeconds > 3) _stopDurationTimer(keepDuration: true);
    }
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
      if (SensorMemory.lastTempMaxToday > 0) {
        _tempMaxToday = SensorMemory.lastTempMaxToday;
      }
      if (SensorMemory.lastHumidityMaxToday > 0) {
        _humidityMaxToday = SensorMemory.lastHumidityMaxToday;
      }
      if (SensorMemory.lastPigStatus != "--") {
        _pigStatus = SensorMemory.lastPigStatus;
      }

      if (SprinklerMemory.lastActivated != "--") {
        _lastActivated = SprinklerMemory.lastActivated;
      }
      if (SprinklerMemory.date != "--") _date = SprinklerMemory.date;
      if (SprinklerMemory.duration != "--") {
        _duration = SprinklerMemory.duration;
      }
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

    // Apply whatever the shared service already has, in case it fetched
    // before this screen's listeners were attached.
    if (LiveSensorService.latestData.value != null) {
      _onLiveDataChanged();
    }

    _fetchMLInsights();
    _loadGraphData();
    _syncTodayMaxFromFirestore();
    _loadNextVaccineSchedule();

    _toggleTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _crossfadeToggle(),
    );

    // Re-check the rolling 24h graph once per hour. _loadGraphData() itself
    // is a no-op (zero Firestore reads) if the hour key hasn't advanced
    // since the last load, so this is safe to fire on a simple timer.
    _hourlyRefreshTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _loadGraphData(),
    );
  }

  // ── Crossfade temp/humidity display ─────────

  Future<void> _crossfadeToggle() async {
    if (!mounted) return;
    await _fadeController.reverse();
    if (!mounted) return;
    setState(() => _showingTemperature = !_showingTemperature);
    await _fadeController.forward();
  }

  // ── Firestore: sync today's historical max on startup ───────────────

  Future<void> _syncTodayMaxFromFirestore() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      QuerySnapshot? tempSnapshot;
      try {
        tempSnapshot = await FirebaseFirestore.instance
            .collection('temperature_hourly')
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
            )
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
            .orderBy('timestamp')
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        tempSnapshot = null;
      }
      if (tempSnapshot == null || tempSnapshot.docs.isEmpty) {
        try {
          tempSnapshot = await FirebaseFirestore.instance
              .collection('temperature_hourly')
              .where(
                'timestamp',
                isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
              )
              .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
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
            .collection('humidity_hourly')
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
            )
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
            .orderBy('timestamp')
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        humiditySnapshot = null;
      }
      if (humiditySnapshot == null || humiditySnapshot.docs.isEmpty) {
        try {
          humiditySnapshot = await FirebaseFirestore.instance
              .collection('humidity_hourly')
              .where(
                'timestamp',
                isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
              )
              .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
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
        SensorMemory.setTempMaxToday(firestoreTempMax);
        SensorMemory.save();
        if (mounted) setState(() => _tempMaxToday = firestoreTempMax);
      }

      if (firestoreHumidityMax > 0) {
        SensorMemory.setHumidityMaxToday(firestoreHumidityMax);
        SensorMemory.save();
        if (mounted) setState(() => _humidityMaxToday = firestoreHumidityMax);
      }

    } catch (e) {
      debugPrint('Error syncing today max from Firestore: $e');
    }
  }

  Future<void> _loadNextVaccineSchedule() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('medicine_intakes')
          .where('category', isEqualTo: 'Vaccine')
          .get();

      DateTime? bestDate;
      String? bestName;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ts = data['nextSchedule'];
        DateTime? scheduleDate;
        if (ts is Timestamp) {
          scheduleDate = ts.toDate();
        } else if (ts is String) {
          scheduleDate = DateTime.tryParse(ts);
        }
        if (scheduleDate == null) continue;

        if (bestDate == null || scheduleDate.isBefore(bestDate)) {
          bestDate = scheduleDate;
          bestName = data['medName'] as String? ?? 'Unknown';
        }
      }

      if (!mounted) return;
      if (bestDate != null && bestName != null) {
        final label = DateFormat('MMM dd').format(bestDate);
        VaxScheduleMemory.medName = bestName;
        VaxScheduleMemory.dateLabel = label;
        VaxScheduleMemory.loaded = true;
        setState(() {
          _vaxMedName = bestName!;
          _vaxDateLabel = label;
        });
      }
    } catch (e) {
      debugPrint('Error loading vax schedule: $e');
    }
  }

  // ── Graph ────────────────────────────────────


  Future<void> _loadGraphData() async {
    final hourKey = currentHourKey();
    if (SensorMemory.graphLoaded && SensorMemory.lastGraphHourKey == hourKey) {
      // Already have data for this hour — just make sure it's reflected
      // in this screen's state (e.g. on a fresh mount) without re-reading.
      if (mounted && _graphSpots != SensorMemory.lastGraphSpots) {
        setState(() {
          _graphSpots = List.of(SensorMemory.lastGraphSpots);
          _graphLoading = false;
        });
      }
      return;
    }

    if (!SensorMemory.graphLoaded) setState(() => _graphLoading = true);
    try {
      final now = DateTime.now();
      final DateTime rangeStart = now.subtract(const Duration(hours: 24));

      final snapshot = await FirebaseFirestore.instance
          .collection('temperature_hourly')
          .orderBy('timestamp', descending: false)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
          )
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .limit(30) // at most ~24-25 docs expected in a rolling 24h window
          .get();

      final List<FlSpot> spots = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        final temp =
            (data['tempAvg'] as num?)?.toDouble() ??
            (data['temperature'] as num?)?.toDouble() ??
            (data['tempMax'] as num?)?.toDouble();
        if (ts == null || temp == null) continue;
        // x = hours-ago, so the window always reads left (24h ago) to
        // right (now), sliding forward by one tick each time a new
        // hourly doc lands — never re-bucketed by wall-clock hour-of-day.
        final hoursAgo = now.difference(ts).inMinutes / 60.0;
        spots.add(FlSpot((24 - hoursAgo).clamp(0, 24), temp));
      }
      spots.sort((a, b) => a.x.compareTo(b.x));

      if (!mounted) return;
      SensorMemory.lastGraphSpots = spots;
      SensorMemory.graphLoaded = true;
      SensorMemory.lastGraphHourKey = hourKey;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$action Sprinkler?'),
        content: Text(
          _localIsActivated
              ? 'Are you sure you want to turn the sprinkler off?'
              : 'Are you sure you want to turn the sprinkler on?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _localIsActivated
                  ? const Color(0xFFD32F2F)
                  : Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(action, style: const TextStyle(color: Colors.white)),
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
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
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

      // Wait longer than ESP32 poll interval (5s) before confirming.
      // Live data will arrive via LiveSensorService's normal cadence —
      // no manual re-fetch needed here anymore.
      await Future.delayed(const Duration(milliseconds: 6000));
      if (mounted) {
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
        color:
            accentColor?.withValues(alpha: 0.25) ??
            (isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06)),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color:
              accentColor?.withValues(alpha: 0.10) ??
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
    final connStatus = LiveSensorService.connectionStatus.value;
    final sensStatus = LiveSensorService.sensorStatus.value;
    final isLive = connStatus == "Live";
    final sensorOnline = sensStatus == "Sensor Online";
    final sensorColor = sensorOnline ? Colors.green : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.transparent,
              child: Icon(
                Symbols.account_circle,
                size: 50,
                color: isDark ? Colors.white : Colors.black,
              ),
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
                    fontSize: 20,
                  ),
                  Text(
                    "Here's what's happening in your farm.",
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
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
              connStatus,
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
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherCard(bool isDark) {
    final showTemp = _showingTemperature;
    final displayTemp = _tempMax > 0 ? _tempMax : _lastKnownTemp;
    final displayHumidity = _humidityLive > 0
        ? _humidityLive
        : _lastKnownHumidity;
    final sensStatus = LiveSensorService.sensorStatus.value;
    final connStatus = LiveSensorService.connectionStatus.value;
    final isOffline =
        sensStatus == "Sensor Offline" || connStatus == "No connection";

    final value = _isLoading
        ? "--"
        : isOffline
        ? "--"
        : showTemp
        ? (displayTemp > 0 ? "${displayTemp.toStringAsFixed(1)}°" : "--")
        : (displayHumidity > 0
              ? "${displayHumidity.toStringAsFixed(1)}%"
              : "--");

    final icon = showTemp
        ? Icons.thermostat_outlined
        : Icons.water_drop_outlined;
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
                  child: Row(
                    children: [
                      Icon(icon, size: 14, color: iconColor),
                      const SizedBox(width: 4),
                      Text(
                        showTemp ? "Temperature" : "Humidity",
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                _isLoading
                    ? const SizedBox(
                        height: 40,
                        width: 40,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FadeTransition(
                        opacity: _fadeAnimation,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) =>
                              SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.2),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              ),
                          child: Text(
                            value,
                            key: ValueKey(value),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildDot(isActive: showTemp, color: Colors.orange),
                    const SizedBox(width: 4),
                    _buildDot(isActive: !showTemp, color: Colors.blue),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _isSprinklerLoading ? null : _confirmSprinkler,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _localIsActivated ? Icons.check_circle : Icons.shower,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _localIsActivated ? 'Active' : 'Activate',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
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
                  final v = SensorMemory.lastTempMaxToday > 0 ? SensorMemory.lastTempMaxToday : _tempMaxToday;
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
            child: _buildInfoCard(isDark, Symbols.shower, "Sprinkler Info", [
              "Status: $_sprinklerStatus",
              "Time: $_lastActivated",
              "Date: $_date",
              "Duration: $_duration",
            ], const Color(0xFF1E88E5)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    bool isDark,
    IconData icon,
    String title,
    List<String> items,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _bentoDecoration(isDark, accentColor: iconColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                e,
                style: TextStyle(
                  color: isDark ? Colors.white60 : const Color(0xFF707070),
                  fontSize: 12,
                ),
              ),
            ),
          ),
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
    const xMax = 24.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _bentoDecoration(isDark, accentColor: Colors.green),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Symbols.monitoring,
                  color: Colors.green,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Temperature (Last 24 hrs)",
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("°C", style: TextStyle(fontSize: 10, color: labelColor)),
              Text(
                "Hourly Graph",
                style: TextStyle(fontSize: 10, color: labelColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: _graphLoading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.green,
                    ),
                  )
                : !hasData
                ? Center(
                    child: Text(
                      "No temperature data available",
                      style: TextStyle(color: labelColor, fontSize: 12),
                    ),
                  )
                : LineChart(
                    LineChartData(
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
                            getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                              radius: 2,
                              color: Colors.green,
                              strokeWidth: 0,
                              strokeColor: Colors.transparent,
                            ),
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
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          bottom: BorderSide(color: axisColor, width: 1.5),
                          left: BorderSide(color: axisColor, width: 1.5),
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              // x is "hours-ago", 0 = 24h ago, 24 = now.
                              const labels = {
                                0: '24h ago',
                                6: '18h ago',
                                12: '12h ago',
                                18: '6h ago',
                                24: 'Now',
                              };
                              final h = value.toInt();
                              if (!labels.containsKey(h))
                                return const SizedBox.shrink();
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  labels[h]!,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: labelColor,
                                  ),
                                ),
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
                              const allowed = [20, 25, 30, 35, 40, 45];
                              if (!allowed.contains(value.toInt()) ||
                                  value != value.roundToDouble())
                                return const SizedBox.shrink();
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  '${value.toInt()}°',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: labelColor,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) =>
                              isDark ? const Color(0xFF2A2A2A) : Colors.white,
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              final hoursAgo = (24 - spot.x).round();
                              final label = hoursAgo <= 0
                                  ? 'Now'
                                  : '${hoursAgo}h ago';
                              return LineTooltipItem(
                                '$label\n${spot.y.toStringAsFixed(1)}°C',
                                TextStyle(
                                  color: lineColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                    ),
                  ),
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
            [
              "Vax name: $_vaxMedName",
              "Date: $_vaxDateLabel",
            ],
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
      decoration: _bentoDecoration(
        isDark,
        accentColor: const Color(0xFF1E88E5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Symbols.water_medium,
                  size: 15,
                  color: Color(0xFF1E88E5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Water Level",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Level: ${_waterPct.toStringAsFixed(0)}%",
            style: TextStyle(
              color: isDark ? Colors.white60 : const Color(0xFF707070),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                "Status: ",
                style: TextStyle(
                  color: isDark ? Colors.white60 : const Color(0xFF707070),
                  fontSize: 12,
                ),
              ),
              Text(
                _waterStatus,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_waterPct / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: conditionColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.lightbulb_outline,
                  size: 15,
                  color: conditionColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Smart Recommendation",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const Spacer(),
              if (!_mlLoading)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: conditionColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: conditionColor, width: 1),
                  ),
                  child: Text(
                    _mlCondition,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: conditionColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_mlLoading)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  "Analyzing farm conditions...",
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : const Color(0xFF707070),
                  ),
                ),
              ],
            )
          else if (_mlRecommendations.isEmpty)
            Text(
              "No recommendations at this time.",
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : const Color(0xFF707070),
              ),
            )
          else
            ..._mlRecommendations.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_right, size: 16, color: conditionColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        r,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white60
                              : const Color(0xFF707070),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!_mlLoading && _mlCondition != "Unavailable")
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.memory,
                    size: 11,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Powered by PRISM trained ML · live sensor data",
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white30 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
