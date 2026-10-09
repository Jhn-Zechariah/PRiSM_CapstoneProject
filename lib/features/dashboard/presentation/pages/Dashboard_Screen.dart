import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

const String esp32Ip = "192.168.1.8";

final sprinklerNotifier = ValueNotifier<bool>(false);
final tempMaxTodayNotifier = ValueNotifier<double>(0);
final humidityMaxTodayNotifier = ValueNotifier<double>(0);

// Stores the time when the sprinkler was last toggled.
// Shared with Temperature and Humidity monitoring screens.
DateTime? sprinklerToggledAt;

// True only while the ESP32 (schedule start/end, auto-off) is changing the
// sprinkler state, as opposed to the user tapping the button.
bool sprinklerChangeIsRemote = false;

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
  static bool _started = false;

  // Staleness is judged against the PHONE's own clock at the moment a
  // reading is received (LAN response or Firestore snapshot) — never
  // against the ESP32's embedded 'timestamp' field. That field comes from
  // the ESP32's NTP sync; if NTP fails at boot the firmware falls back to
  // sending "1970-01-01T00:00:00Z" forever, which used to make every
  // reading look decades old and the sensor permanently "offline" even
  // though it kept pushing fresh data every few seconds.
  //
  // Kept at 15s (above the 10s ESP32 update and poll interval) so a
  // missed/offline reading is reflected within about one cycle. NOTE: this only controls
  // how fast the badge flips to "Sensor Offline" — flipping back to
  // "Sensor Online" already happens the instant any reading arrives, with
  // no waiting period. If plugging the sensor back in doesn't bring the
  // badge back online, no reading is arriving at all (check the
  // [LiveSensorService] debugPrint logs to see whether the LAN poll or the
  // Firestore fallback is the one failing).
  // Require 2 consecutive failed checks before showing Sensor Offline.
  static const int _maxConsecutiveFailures = 2;
  static int _consecutiveFailures = 0;

  /// How old the 'timestamp' field on a one-shot Firestore GET is allowed
  /// to be before it's trusted as proof the sensor is currently live. A
  /// plain .get() (unlike a LAN response or a listener's change event)
  /// just returns whatever is currently stored, so this is what actually
  /// catches the "ESP32 unplugged, doc frozen" case for that path.
  static const int _oneShotGetFreshnessLimitSeconds = 30;

  /// Wall-clock time this phone last actually received a reading.
  static DateTime? _lastUpdateReceivedAt;

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

    sensorStatus.addListener(() => debugPrint(
        '[LiveSensorService] >>> BADGE sensor = ${sensorStatus.value}'));
    connectionStatus.addListener(() => debugPrint(
        '[LiveSensorService] >>> BADGE connection = ${connectionStatus.value}'));

    Connectivity().checkConnectivity().then((results) {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      connectionStatus.value = hasNet ? "Live" : "Connecting...";
    });

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (!hasNet) {
        // Don't flip to offline here directly — connectivity_plus can
        // report a transient "no network" blip for a second or two during
        // normal WiFi roaming/DHCP renewal even though the connection is
        // actually fine, and that used to instantly flash the status red
        // with zero grace period, bypassing the staleness window
        // everything else respects. Let _checkStaleness() (driven by the
        // 5s poll timer) be the single source of truth for the offline
        // label — it already accounts for genuinely lost connectivity.
      } else {
        // Net just came back — try a poll immediately instead of waiting
        // for the next tick, so the UI recovers fast.
        _poll();
      }
    });

    _poll();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  /// Guards against overlapping polls — the LAN request (2s timeout) plus a
  /// possible reachability check (DNS lookup, up to a few seconds) can take
  /// longer than the 5s timer interval, so without this a second _poll()
  /// could start while the first is still resolving and race it.
  static bool _polling = false;

  /// Age (in seconds) of a Firestore-sourced reading's own 'timestamp'
  /// field, vs. the phone's wall clock. Null if there's no usable
  /// timestamp. Used to tell a genuinely fresh reading apart from "this is
  /// just whatever was last stored," which a plain .get() or the first
  /// event after a listener (re)subscribe can both hand back even when the
  /// ESP32 has been unplugged for hours.
  static int? _dataAgeSeconds(Map<String, dynamic>? data) {
    final ts = data?['timestamp'];
    DateTime? t;
    if (ts is Timestamp) {
      t = ts.toDate();
    } else if (ts is String) {
      t = DateTime.tryParse(ts);
    }
    // Missing, unparseable, or NTP-failed (1970) timestamp = unknown age.
    if (t == null || t.year < 2020) {
      debugPrint('[LiveSensorService] timestamp unusable: raw=$ts parsed=$t '
          '(null = missing/unparseable, year<2020 = ESP32 NTP failed)');
      return null;
    }
    return DateTime.now().toUtc().difference(t.toUtc()).inSeconds;
  }

  static Future<void> _poll() async {
    _attachSprinklerCommandListener();
    if (_polling) return;
    _polling = true;
    try {
      await _pollOnce();
    } finally {
      _polling = false;
    }
  }

  static Future<void> _pollOnce() async {
    // Check real internet reachability IN PARALLEL with the LAN attempt,
    // instead of only after LAN + Firestore both fail. Updates the badge
    // almost immediately instead of waiting behind ~8s of other timeouts.
    final internetCheckFuture = _hasRealInternet();
    final sw = Stopwatch()..start();
    debugPrint('[LiveSensorService] ── poll start ── '
        '${DateTime.now().toIso8601String()} | '
        'fails=$_consecutiveFailures/$_maxConsecutiveFailures | '
        'lastReading=${_lastUpdateReceivedAt == null ? "never" : "${DateTime.now().difference(_lastUpdateReceivedAt!).inSeconds}s ago"}');

    Map<String, dynamic>? data;

    // 1. LAN first — fastest path, zero Firestore read cost.
    try {
      final response = await http
          .get(Uri.parse('http://$esp32Ip/sensor'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint(
          '[LiveSensorService] LAN poll got HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      // not on home network, or ESP32 unreachable — fall through
      debugPrint('[LiveSensorService] LAN poll failed: $e');
    }

    unawaited(internetCheckFuture.then((hasNet) {
      if (connectionStatus.value != "Live") {
        connectionStatus.value = hasNet ? "Live" : "No Connection";
        SensorMemory.lastConnectionStatus = connectionStatus.value;
      }
    }));

    if (data != null) {
      debugPrint('[LiveSensorService] LAN poll OK (${sw.elapsedMilliseconds} ms)');
      connectionStatus.value = "Live";
      _markOnline(data);
      return;
    }

    // 2. LAN failed — try a direct one-shot Firestore read first. Some
    // networks silently throttle or kill long-lived streaming connections
    // (which the snapshot listener below depends on) while still letting
    // discrete short HTTPS request/response calls through fine — exactly
    // like the ESP32's own pushes, which always succeed on the same kind
    // of network. A plain .get() is a single request/response, so it isn't
    // affected by that.
    //
    // Unlike a LAN response or a listener's change event, a one-shot .get()
    // is NOT proof the sensor is live right now — it just returns whatever
    // document is currently stored, even if it's hours old (e.g. the ESP32
    // got unplugged). So this path — and only this path — has to check the
    // document's own 'timestamp' field for actual recency before trusting
    // it. Threshold is generous (well above the ~3-7s push interval) to
    // tolerate normal network/round-trip delay without false negatives.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('live_sensor')
          .doc('latest')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
      final d = doc.data();
      final ageSeconds = _dataAgeSeconds(d);
      debugPrint('[LiveSensorService] Firestore GET returned after ${sw.elapsedMilliseconds} ms | '
          'fromCache=${doc.metadata.isFromCache} | '
          'raw timestamp=${d?['timestamp']} (${d?['timestamp'].runtimeType}) | '
          'age=${ageSeconds}s | limit=${_oneShotGetFreshnessLimitSeconds}s');
      if (d != null && ageSeconds != null && ageSeconds <= _oneShotGetFreshnessLimitSeconds) {
        debugPrint('[LiveSensorService] Firestore one-shot GET OK (age ${ageSeconds}s)');
        _attachFirestoreFallbackIfNeeded(); // keep it warm in case it does work
        _markOnline(d);
        return;
      } else if (d != null && ageSeconds != null) {
        // Doc has a valid timestamp but is older than the limit, so the
        // ESP32 has stopped pushing. Mark offline immediately instead of
        // waiting for the failure counter.
        debugPrint(
          '[LiveSensorService] stale doc (age ${ageSeconds}s) — '
              'ESP32 not pushing, marking Offline',
        );
        _attachFirestoreFallbackIfNeeded();
        final hasNet = await _hasRealInternet();
        connectionStatus.value = hasNet ? "Live" : "No Connection";
        sensorStatus.value = "Sensor Offline";
        SensorMemory.lastConnectionStatus = connectionStatus.value;
        SensorMemory.lastSensorStatus = "Sensor Offline";
        return;
      } else if (d != null) {
        // ageSeconds == null (missing/1970 timestamp): age unknown, so
        // fall through to the failure counter below.
        debugPrint(
          '[LiveSensorService] doc has unusable timestamp — treating as no data',
        );
      }
    } catch (e) {
      debugPrint('[LiveSensorService] Firestore one-shot GET failed: $e');
    }

    // 3. One-shot GET also failed/returned nothing — ensure the Firestore
    // listener is attached anyway (free extra coverage if the network
    // allows it after all), then fall back to the staleness check.
    _attachFirestoreFallbackIfNeeded();
    await _checkStaleness();
  }

  static void _attachFirestoreFallbackIfNeeded() {
    if (_firestoreSub != null) return;
    debugPrint('[LiveSensorService] attaching Firestore fallback listener');
    _firestoreSub = FirebaseFirestore.instance
        .collection('live_sensor')
        .doc('latest')
        .snapshots()
        .listen(
          (snap) {
        if (!snap.exists) {
          debugPrint('[LiveSensorService] Firestore snapshot: doc missing');
          return;
        }
        final data = snap.data();
        if (data == null) return;
        // The FIRST snapshot delivered right after (re)subscribing is
        // just "whatever is currently stored," not proof of a fresh
        // write — same trap as the one-shot GET above. Only trust it
        // if the doc's own timestamp is actually recent, otherwise a
        // reattach right after the ESP32 gets unplugged would still
        // flash "Online" once using the stale last-known reading.
        final ageSeconds = _dataAgeSeconds(data);
        if (ageSeconds == null ||
            ageSeconds > _oneShotGetFreshnessLimitSeconds) {
          debugPrint(
            '[LiveSensorService] Firestore snapshot stale (age ${ageSeconds}s) — ignoring',
          );
          return;
        }
        debugPrint(
          '[LiveSensorService] Firestore snapshot received (age ${ageSeconds}s)',
        );
        _markOnline(data);
      },
      onError: (e) {
        // A Firestore stream that hits an error (auth token refresh,
        // transient network blip, etc.) terminates for good — it will
        // never deliver another snapshot. Previously this left
        // _firestoreSub pointing at that dead subscription forever,
        // so the fallback was never re-attached. If LAN also wasn't
        // reachable at that moment, no data source was left at all
        // and the app got stuck "offline" permanently after the
        // first hiccup. Clearing it here lets the next _poll() tick
        // (every 5s) resubscribe automatically.
        debugPrint('[LiveSensorService] Firestore listener error: $e');
        _firestoreSub = null;
      },
      onDone: () {
        debugPrint('[LiveSensorService] Firestore listener closed');
        _firestoreSub = null;
      },
    );
  }

  /// Only call this once a reading is already known to be live: a LAN
  /// response is live by construction (a dead ESP32 wouldn't answer at
  /// all), while Firestore-sourced data must first pass the
  /// [_dataAgeSeconds] freshness check at the call site.
  static void _markOnline(Map<String, dynamic> data) {
    debugPrint('[LiveSensorService] _markOnline data=$data');

    // Any successful reading immediately resets failed attempts.
    _consecutiveFailures = 0;

    _lastUpdateReceivedAt = DateTime.now();
    connectionStatus.value = "Live";
    sensorStatus.value = "Sensor Online";
    latestData.value = data; // must be LAST so listeners see "Online"

    SensorMemory.lastConnectionStatus = "Live";
    SensorMemory.lastSensorStatus = "Sensor Online";

    debugPrint(
      '[LiveSensorService] Sensor Online — failure counter reset',
    );
  }

  /// Handles a failed sensor check.
  /// The sensor is marked Offline only after 3 consecutive failed checks.
  static Future<void> _checkStaleness() async {
    final hasNet = await _hasRealInternet();

    connectionStatus.value = hasNet ? "Live" : "No Connection";
    SensorMemory.lastConnectionStatus = connectionStatus.value;

    _consecutiveFailures++;

    debugPrint(
      '[LiveSensorService] Failed sensor check: '
          '$_consecutiveFailures/$_maxConsecutiveFailures',
    );

    // Do not immediately mark the sensor offline.
    if (_consecutiveFailures < _maxConsecutiveFailures) {
      return;
    }

    sensorStatus.value = "Sensor Offline";
    SensorMemory.lastSensorStatus = "Sensor Offline";

    debugPrint(
      '[LiveSensorService] Sensor Offline after '
          '$_consecutiveFailures consecutive failed checks',
    );

    // Allow Firestore listener to reconnect on the next poll.
    if (hasNet) {
      await _firestoreSub?.cancel();
      _firestoreSub = null;
    }
  }

  // ── Real-time sprinkler ON/OFF from the ESP32 ──
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _sprinklerCmdSub;
  static bool _sprinklerCmdFirstEvent = true;

  static void _attachSprinklerCommandListener() {
    if (_sprinklerCmdSub != null) return;
    _sprinklerCmdFirstEvent = true;
    _sprinklerCmdSub = FirebaseFirestore.instance
        .collection('sprinkler_command')
        .doc('pending')
        .snapshots()
        .listen(
          (snap) {
        // First event is only the stored value, not a new change.
        if (_sprinklerCmdFirstEvent) {
          _sprinklerCmdFirstEvent = false;
          return;
        }
        // Our own button tap: the screens already update themselves.
        if (snap.metadata.hasPendingWrites) return;

        final state = snap.data()?['state'] as String?;
        if (state == null) return;
        final isOn = state == 'on';
        if (isOn == sprinklerNotifier.value) return;

        debugPrint('[LiveSensorService] sprinkler changed by ESP32 -> $state');
        // Stops stale sensor readings from flipping the button back.
        sprinklerToggledAt = DateTime.now();
        sprinklerChangeIsRemote = true;
        sprinklerNotifier.value = isOn; // listeners run right here
        sprinklerChangeIsRemote = false;
      },
      onError: (e) {
        debugPrint('[LiveSensorService] sprinkler listener error: $e');
        _sprinklerCmdSub = null; // re-attached on the next poll
      },
      onDone: () => _sprinklerCmdSub = null,
    );
  }

  static Future<bool> _hasRealInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.every((r) => r == ConnectivityResult.none)) return false;
      final lookup = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
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
    _sprinklerCmdSub?.cancel();
    _sprinklerCmdSub = null;
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
      try {
        doc = await FirebaseFirestore.instance
            .collection('sprinkler_state')
            .doc('latest')
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        doc = null;
      }
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

  static List<Map<String, double>> lastTempChartData = [];
  static bool tempChartLoaded = false;
  static String lastTempChartDate = "";
  static String lastTempChartHourKey = "";
  static double? lastTempDisplayMax;
  static double? lastTempDisplayMin;
  static double? lastTempDisplayAvg;
  static double? lastTempSessionMax;
  static double? lastTempSessionMin;

  static List<Map<String, double>> lastHumidityChartData = [];
  static bool humidityChartLoaded = false;
  static String lastHumidityChartDate = "";
  static String lastHumidityChartHourKey = "";
  static double? lastHumidityDisplayMax;
  static double? lastHumidityDisplayMin;
  static double? lastHumidityDisplayAvg;
  static double? lastHumiditySessionMax;
  static double? lastHumiditySessionMin;

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

  static DateTime _lastSaveAt = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> save() async {
    final nowT = DateTime.now();
    if (nowT.difference(_lastSaveAt) < const Duration(seconds: 60)) return;
    _lastSaveAt = nowT;
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

  // _tempMax and _humidityLive intentionally start at 0 and are NEVER
  // restored from cache — they must come from a live ESP32 response.
  double _tempMax = 0;
  String _tempStatus = "Normal";
  double _waterPct = 0;
  String _waterStatus = "Unknown";
  double _lastKnownTemp = 0;
  double _lastKnownHumidity = 0;
  bool _isSprinklerLoading = false;
  double _tempMaxToday = 0;
  double _humidityMaxToday = 0;
  double _humidityLive = 0;

  // AMG8833 thermal heatmap — 64 pixels (8x8)
  List<double> _thermalPixels = List.filled(64, 0.0);

  String _sprinklerStatus = "OFF";
  String _lastActivated = "--";
  String _date = "--";
  String _duration = "--";
  String _pigStatus = "--";

  // ML — start with empty state; card is hidden until sensor is live
  String _mlCondition = "";
  List<String> _mlRecommendations = [];
  bool _mlLoading = false;

  List<FlSpot> _graphSpots = List.of(SensorMemory.lastGraphSpots);
  bool _graphLoading = !SensorMemory.graphLoaded;
  Timer? _hourlyRefreshTimer;

  DateTime? _sprinklerActivatedAt;
  Timer? _durationTimer;
  bool _sprinklerMemoryLoaded = false;
  bool _sprinklerJustToggled = false;
  // ignore: unused_field, prefer_final_fields
  double _lastMlTemp = 0;
  // ignore: unused_field, prefer_final_fields
  double _lastMlHumidity = 0;
  // ignore: unused_field
  DateTime? _lastMlRun;
  late bool _localIsActivated;

  bool _showingTemperature = false;
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

    debugPrint('[Dashboard] new reading -> hum=${data['humidity']} | '
        'temp=${data['ambientTemp']} | water=${data['waterPct']}% '
        '(${data['waterStatus']}) | sprinkler=${data['sprinkler']}');

    final espSprinkler = data['sprinkler'] as bool?;
    final recentlyToggled = sprinklerToggledAt != null &&
        DateTime.now().difference(sprinklerToggledAt!) <
            const Duration(seconds: 25);
    if (espSprinkler != null &&
        !recentlyToggled &&
        !_sprinklerJustToggled &&
        espSprinkler != sprinklerNotifier.value) {
      sprinklerNotifier.value = espSprinkler;
    }

    setState(() {
      final tempValid = data['ambientTempValid'] as bool? ?? true;
      final newTempLive = tempValid
          ? (data['ambientTemp'] as num?)?.toDouble()
          : null;
      if (newTempLive != null && newTempLive > 0 && newTempLive <= 80) {
        _tempMax = newTempLive;
        _lastKnownTemp = _tempMax;
        SensorMemory.lastTemp = _tempMax;
        _pigStatus = newTempLive < 38.7
            ? "Low"
            : (newTempLive <= 39.8 ? "Normal" : "High");
        SensorMemory.lastPigStatus = _pigStatus;
        SensorMemory.resetIfNewDay();
        if (newTempLive > SensorMemory.lastTempMaxToday) {
          SensorMemory.setTempMaxToday(newTempLive);
          SensorMemory.save();
        }
        _tempMaxToday = SensorMemory.lastTempMaxToday;
      }

      final humValid = data['humidityValid'] as bool? ?? true;
      final newHumidity = humValid ? (data['humidity'] as num?)?.toDouble() : null;
      if (newHumidity != null && newHumidity > 0 && newHumidity <= 100) {
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

      // AMG8833 thermal pixels are supplied by the ESP32 /sensor endpoint.
      // They are displayed locally and are NOT stored in Firestore.
      final rawThermalPixels = data['thermalPixels'];
      if (rawThermalPixels is List && rawThermalPixels.length == 64) {
        _thermalPixels = rawThermalPixels
            .map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList();
      }

      _isLoading = false;
    });

    if (!_sprinklerJustToggled &&
        !sprinklerNotifier.value &&
        _sprinklerActivatedAt != null) {
      final elapsed = DateTime.now().difference(_sprinklerActivatedAt!);
      if (elapsed.inSeconds > 3) _stopDurationTimer(keepDuration: true);
    }

    if (!_mlLoading &&
        (_lastMlRun == null ||
            DateTime.now().difference(_lastMlRun!) >
                const Duration(minutes: 1))) {
      _lastMlRun = DateTime.now();
      _fetchMLInsights();
    }
  }

  // ── Notifier listeners ──────────────────────

  void _onSprinklerNotifierChanged() {
    if (!mounted) return;
    _sprinklerJustToggled = false;
    final newVal = sprinklerNotifier.value;
    final remote = sprinklerChangeIsRemote; // ESP32 changed it (schedule)

    if (_localIsActivated != newVal) {
      setState(() {
        _localIsActivated = newVal;
        _sprinklerStatus = newVal ? "ON" : "OFF";
        if (!newVal && _sprinklerActivatedAt != null) {
          _stopDurationTimer(keepDuration: true);
          SprinklerMemory.duration = _duration;
          SprinklerMemory.status = "OFF";
          SprinklerMemory.activatedAt = null;
          SprinklerMemory.save();
        }
      });
    }

    // Schedule just started: fill in the Sprinkler Info card + timer.
    if (remote && newVal && _sprinklerActivatedAt == null) {
      final now = DateTime.now();
      final timeStr = DateFormat('h:mm a').format(now); // e.g. 6:00 PM
      final dateStr = DateFormat('MMM dd').format(now);

      SprinklerMemory.lastActivated = timeStr;
      SprinklerMemory.date = dateStr;
      SprinklerMemory.duration = '0s';
      SprinklerMemory.status = "ON";
      SprinklerMemory.activatedAt = now;
      SprinklerMemory.save();

      setState(() {
        _lastActivated = timeStr;
        _date = dateStr;
        _duration = '0s';
      });
      _startDurationTimer(now);
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
    // _loadGraphData(); // Temperature sensor disabled — nothing to graph.
    _loadNextVaccineSchedule();

    // Recompute today's max from the same data the Temperature/Humidity
    // screens use, so a stale or spiky stored value gets corrected.
    unawaited(_scanTodayTempMax());
    unawaited(_scanTodayHumidityMax());

    _toggleTimer?.cancel();
    _toggleTimer = Timer.periodic(
      const Duration(seconds: 4),
          (_) => _crossfadeToggle(),
    );

    // Temperature sensor disabled — no graph to refresh hourly.
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

  Future<void> _scanTodayHumidityMax() async {
    try {
      final now = DateTime.now();
      var cursor = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(milliseconds: 1));
      double maxH = 0;
      while (true) {
        final snap = await FirebaseFirestore.instance
            .collection('humidity_second')
            .orderBy('timestamp')
            .where('timestamp', isGreaterThan: Timestamp.fromDate(cursor))
            .limit(1000)
            .get();
        for (final doc in snap.docs) {
          final d = doc.data();
          final ts = (d['timestamp'] as Timestamp?)?.toDate();
          if (ts == null) continue;
          cursor = ts;
          final h = (d['humidity'] as num?)?.toDouble();
          if (h == null ||
              d['humidityValid'] == false ||
              h <= 0 ||
              h > 100) {
            continue;
          }
          if (h > maxH) maxH = h;
        }
        if (snap.docs.length < 1000) break;
      }
      if (!mounted || maxH <= 0) return;
      SensorMemory.lastHumidityMaxDate = SensorMemory.todayKey();
      SensorMemory.setHumidityMaxToday(maxH);
      SensorMemory.save();
      setState(() => _humidityMaxToday = maxH);
    } catch (e) {
      debugPrint('Error scanning today humidity max: $e');
    }
  }

  // Scans every temperature_second reading since midnight and sets the
  // exact highest valid value, same rule as the Temperature screen.
  Future<void> _scanTodayTempMax() async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      var cursor = midnight.subtract(const Duration(milliseconds: 1));
      double maxT = 0;

      while (true) {
        final snap = await FirebaseFirestore.instance
            .collection('temperature_second')
            .orderBy('timestamp')
            .where('timestamp', isGreaterThan: Timestamp.fromDate(cursor))
            .limit(1000)
            .get();

        for (final doc in snap.docs) {
          final d = doc.data();
          final ts = (d['timestamp'] as Timestamp?)?.toDate();
          if (ts == null) continue;
          cursor = ts;
          final raw = d['ambientTemp'];
          if (raw == null) continue;
          final t = (raw as num).toDouble();
          if (d['ambientTempValid'] == false || t < 0 || t > 80) continue;
          if (t > maxT) maxT = t;
        }

        if (snap.docs.length < 1000) break;
      }

      if (!mounted || maxT <= 0) return;
      SensorMemory.lastTempMaxDate = SensorMemory.todayKey();
      SensorMemory.setTempMaxToday(maxT);
      SensorMemory.save();
      setState(() => _tempMaxToday = maxT);
    } catch (e) {
      debugPrint('Error scanning today temp max: $e');
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
        if (scheduleDate.isBefore(
          DateTime.now().subtract(const Duration(days: 1)),
        )) continue;

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
    // Guard: only run when we have a real live humidity value. Temperature
    // sensor (AMG8833) is disabled, so it's no longer part of this check —
    // a neutral placeholder temperature is passed to the ML service instead.
    if (_humidityLive <= 0) {
      if (_mlCondition.isEmpty || _mlCondition == "Unavailable") {
        setState(() {
          _mlCondition = "Unavailable";
          _mlRecommendations = [
            "Sensor is offline. Connect to receive smart recommendations.",
          ];
          _mlLoading = false;
        });
      }
      return;
    }

    setState(() => _mlLoading = true);

    try {
      final result = await MlService.analyzeFarm(
        temperatureC: _lastKnownTemp > 0 ? _lastKnownTemp : 25.0,
        humidityPct: _humidityLive,
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
      } else {
        setState(() => _mlLoading = false);
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

    if (LiveSensorService.sensorStatus.value != "Sensor Online" &&
        !_localIsActivated) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.sensors_off, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Sensor Offline'),
            ],
          ),
          content: const Text(
            'Cannot activate the sprinkler while the sensor is offline. Please ensure the sensor is online and try again.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      _isSprinklerDialogOpen = false;
      return;
    }

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
      // Fire the LAN command first — this is what makes the relay flip
      // instantly instead of waiting for the ESP32's 2s Firestore poll.
      unawaited(
        http
            .post(
          Uri.parse('http://$esp32Ip/sprinkler'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'state': turnOn ? 'on' : 'off'}),
        )
            .timeout(const Duration(seconds: 2))
            .then<void>((_) {})
            .catchError((e) {
          debugPrint('[Sprinkler] LAN command failed: $e');
        }),
      );

      await FirebaseFirestore.instance
          .collection('sprinkler_command')
          .doc('pending')
          .set({'state': turnOn ? 'on' : 'off'});

      if (!mounted) return;

      final now = DateTime.now();
      setState(() => _localIsActivated = turnOn);
      sprinklerToggledAt = DateTime.now();
      sprinklerNotifier.value = turnOn;

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
    // Show ML card only when we have a result (loading or done with real data)
    // ignore: unused_local_variable
    final showMlCard = _mlLoading || _mlCondition.isNotEmpty;

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
            _buildThermalHeatmap(isDarkMode),
            const SizedBox(height: 16),
            _buildQuickStatsRow(isDarkMode),
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
    final isNoInternet = connStatus == "No Connection";
    final sensorOnline = sensStatus == "Sensor Online";
    final sensorColor = sensorOnline ? Colors.green : Colors.red;
    // When there's no internet at all, the ESP32 might be perfectly fine —
    // we simply have no way to check it. Saying "Sensor Offline" in that
    // case wrongly implies the device itself is broken. Show the same
    // "No Internet" reason on both pills instead of two conflicting
    // messages.
    final sensorLabel = isNoInternet
        ? "No Internet"
        : (sensorOnline ? "Sensor Online" : "Sensor Offline");

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
              sensorLabel,
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
        sensStatus == "Sensor Offline" || connStatus == "No Connection";

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

  //THERMAL HEATMAP LOCATION

  Widget _buildThermalHeatmap(bool isDark) {
    final sensorOffline =
        LiveSensorService.sensorStatus.value == "Sensor Offline" ||
            LiveSensorService.connectionStatus.value == "No Connection";

    final validPixels = _thermalPixels
        .where((t) => t.isFinite && t > 0 && t < 80)
        .toList();

    final hasThermalData = validPixels.length == 64;
    final minTemp = hasThermalData
        ? validPixels.reduce((a, b) => a < b ? a : b)
        : 0.0;
    final maxTemp = hasThermalData
        ? validPixels.reduce((a, b) => a > b ? a : b)
        : 0.0;

    Color thermalColor(double temp) {
      if (!temp.isFinite || temp <= 0) {
        return isDark ? Colors.grey.shade800 : Colors.grey.shade300;
      }

      final range = maxTemp - minTemp;
      final normalized = range <= 0
          ? 0.5
          : ((temp - minTemp) / range).clamp(0.0, 1.0);

      // Blue -> cyan -> green -> yellow -> red.
      final stops = <Color>[
        Colors.blue,
        Colors.cyan,
        Colors.green,
        Colors.yellow,
        Colors.red,
      ];
      final scaled = normalized * (stops.length - 1);
      final index = scaled.floor().clamp(0, stops.length - 2);
      final localT = scaled - index;
      return Color.lerp(stops[index], stops[index + 1], localT) ?? stops[index];
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _bentoDecoration(isDark, accentColor: Colors.red),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.thermostat,
                  size: 20,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Thermal Heatmap",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "AMG8833 • 8 × 8 thermal sensor",
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasThermalData && !sensorOffline)
                Text(
                  "MAX ${maxTemp.toStringAsFixed(1)}°C",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (sensorOffline || !hasThermalData)
            Container(
              height: 260,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    sensorOffline ? Icons.cloud_off : Icons.thermostat_outlined,
                    size: 34,
                    color: isDark ? Colors.white38 : Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sensorOffline ? "Sensor Offline" : "Waiting for thermal data…",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "64 AMG8833 pixels",
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          else
            AspectRatio(
              aspectRatio: 1,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 64,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemBuilder: (context, index) {
                  final temp = _thermalPixels[index];
                  final cellColor = thermalColor(temp);

                  return Container(
                    decoration: BoxDecoration(
                      color: cellColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        "${temp.toStringAsFixed(1)}°",
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: temp >= (minTemp + maxTemp) / 2
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                hasThermalData ? "${minTemp.toStringAsFixed(1)}°C" : "--",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      colors: [
                        Colors.blue,
                        Colors.cyan,
                        Colors.green,
                        Colors.yellow,
                        Colors.red,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hasThermalData ? "${maxTemp.toStringAsFixed(1)}°C" : "--",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.grey,
                ),
              ),
            ],
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
                "Max Temperature Today: ${_tempMaxToday == 0 ? '…' : '${_tempMaxToday.toStringAsFixed(1)}°C'}",
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
            ["Vax name: $_vaxMedName", "Date: $_vaxDateLabel"],
            const Color(0xFFFB8C00),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(child: _buildWaterLevelCard(isDark)),
      ],
    );
  }

  Widget _buildWaterLevelCard(bool isDark) {
    // Same offline rule used by the weather card: sensor offline OR no internet
    final sensStatus = LiveSensorService.sensorStatus.value;
    final connStatus = LiveSensorService.connectionStatus.value;
    final isOffline =
        sensStatus == "Sensor Offline" || connStatus == "No Connection";

    // When offline, force Unknown regardless of the last stored value
    final displayStatus = isOffline ? "Unknown" : _waterStatus;
    final displayPct = isOffline ? 0.0 : _waterPct;

    final statusColor = switch (displayStatus) {
      "Full" => Colors.green,
      "Normal" => Colors.blue,
      "Low" => Colors.orange,
      "Empty" || "Critical" => Colors.red.shade900,
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
            isOffline ? "Level: --" : "Level: ${displayPct.toStringAsFixed(0)}%",
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
                displayStatus,
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
              value: (displayPct / 100).clamp(0.0, 1.0),
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
              if (!_mlLoading && _mlCondition.isNotEmpty)
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
              "No recommendations at this time. Check your sensor connection.",
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
          if (!_mlLoading &&
              _mlCondition.isNotEmpty &&
              _mlCondition != "Unavailable")
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
