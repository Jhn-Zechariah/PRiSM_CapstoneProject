import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repo/temperature_monitoring_repo.dart';
import 'temperature_monitoring_states.dart';

class TemperatureMonitoringCubit extends Cubit<TemperatureMonitoringState> {
  final TemperatureMonitoringRepo _repo;
  Timer? _pollingTimer;
  StreamSubscription? _historySubscription;

  // Internal memory caches
  final List<Map<String, double>> _liveChartPoints = [];
  bool _isSprinklerOn = false;
  int _currentTimeRange = 3; // Defaults to Today

  TemperatureMonitoringCubit({required TemperatureMonitoringRepo repo})
      : _repo = repo,
        super(TemperatureInitial());

  /// Starts global operations and background streaming loops
  void startMonitoring() {
    _emitActiveState(
      tempMax: 0, tempAvg: 0, tempMin: 0,
      status: "Normal", connection: "Connecting...",
    );

    _executePoll();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _executePoll());
  }

  Future<void> _executePoll() async {
    // If exploring historical bounds, skip making local device updates
    if (_currentTimeRange != 3) return;

    try {
      // 🔹 Replaced map extraction with type-safe model extraction
      final reading = await _repo.fetchLiveHardwareTelemetry();

      final max = reading.tempMax;
      final avg = reading.tempAvg;
      final min = reading.tempMin;
      final status = reading.tempStatus;

      _liveChartPoints.add({
        'index': _liveChartPoints.length.toDouble(),
        'temp': max,
      });

      // Shift dynamic chart buffer max items
      if (_liveChartPoints.length > 20) {
        _liveChartPoints.removeAt(0);
        for (int i = 0; i < _liveChartPoints.length; i++) {
          _liveChartPoints[i] = {'index': i.toDouble(), 'temp': _liveChartPoints[i]['temp']!};
        }
      }

      _emitActiveState(
        tempMax: max, tempAvg: avg, tempMin: min,
        status: status, connection: "Live",
        points: List.from(_liveChartPoints),
      );

      // 🔹 Persist the clean model instance directly to Firestore
      await _repo.saveTemperatureReading(reading);
    } catch (_) {
      _emitActiveState(
        tempMax: 0, tempAvg: 0, tempMin: 0,
        status: "N/A", connection: "No connection",
      );
    }
  }

  /// Switches filters and maps data layers smoothly
  void changeTimeRange(int rangeIndex) {
    _currentTimeRange = rangeIndex;
    _historySubscription?.cancel();

    if (rangeIndex == 3) {
      // Revert instantly to live loop configuration channels
      _emitActiveState(connection: "Live", points: List.from(_liveChartPoints));
      return;
    }

    _emitActiveState(connection: "Loading Archive...");

    _historySubscription = _repo.streamFilteredReadings(rangeIndex).listen((readings) {
      if (readings.isEmpty) {
        _emitActiveState(tempMax: 0, tempAvg: 0, tempMin: 0, points: []);
        return;
      }

      List<Map<String, double>> archivedPoints = [];
      for (int i = 0; i < readings.length; i++) {
        archivedPoints.add({'index': i.toDouble(), 'temp': readings[i].tempMax});
      }

      final temps = readings.map((e) => e.tempMax).toList();
      final highest = temps.reduce((a, b) => a > b ? a : b);
      final lowest = temps.reduce((a, b) => a < b ? a : b);
      final average = temps.reduce((a, b) => a + b) / temps.length;

      _emitActiveState(
        tempMax: highest, tempAvg: average, tempMin: lowest,
        connection: "Archived Data", points: archivedPoints,
      );
    });
  }

  /// Sends state updates to the hardware and handles failures gracefully
  Future<void> toggleSprinkler() async {
    final targetState = !_isSprinklerOn;
    final success = await _repo.setSprinklerState(targetState);
    if (success) {
      _isSprinklerOn = targetState;
      _emitActiveState();
    }
  }

  void _emitActiveState({
    double? tempMax, double? tempAvg, double? tempMin,
    String? status, String? connection, List<Map<String, double>>? points,
  }) {
    if (state is TemperatureMonitorActive) {
      final current = state as TemperatureMonitorActive;
      emit(current.copyWith(
        tempMax: tempMax, tempAvg: tempAvg, tempMin: tempMin,
        tempStatus: status, connectionStatus: connection,
        isSprinklerActivated: _isSprinklerOn,
        selectedTimeRangeIndex: _currentTimeRange,
        chartPoints: points,
      ));
    } else {
      emit(TemperatureMonitorActive(
        tempMax: tempMax ?? 0.0, tempAvg: tempAvg ?? 0.0, tempMin: tempMin ?? 0.0,
        tempStatus: status ?? "Normal", connectionStatus: connection ?? "Live",
        isSprinklerActivated: _isSprinklerOn, selectedTimeRangeIndex: _currentTimeRange,
        chartPoints: points ?? [],
      ));
    }
  }

  @override
  Future<void> close() {
    _pollingTimer?.cancel();
    _historySubscription?.cancel();
    return super.close();
  }
}