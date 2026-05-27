
abstract class TemperatureMonitoringState {}

class TemperatureInitial extends TemperatureMonitoringState {}

class TemperatureMonitorActive extends TemperatureMonitoringState {
  final double tempMax;
  final double tempAvg;
  final double tempMin;
  final String tempStatus;
  final String connectionStatus;
  final bool isSprinklerActivated;
  final int selectedTimeRangeIndex;
  final List<Map<String, double>> chartPoints;

  TemperatureMonitorActive({
    required this.tempMax,
    required this.tempAvg,
    required this.tempMin,
    required this.tempStatus,
    required this.connectionStatus,
    required this.isSprinklerActivated,
    required this.selectedTimeRangeIndex,
    required this.chartPoints,
  });

  TemperatureMonitorActive copyWith({
    double? tempMax,
    double? tempAvg,
    double? tempMin,
    String? tempStatus,
    String? connectionStatus,
    bool? isSprinklerActivated,
    int? selectedTimeRangeIndex,
    List<Map<String, double>>? chartPoints,
  }) {
    return TemperatureMonitorActive(
      tempMax: tempMax ?? this.tempMax,
      tempAvg: tempAvg ?? this.tempAvg,
      tempMin: tempMin ?? this.tempMin,
      tempStatus: tempStatus ?? this.tempStatus,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      isSprinklerActivated: isSprinklerActivated ?? this.isSprinklerActivated,
      selectedTimeRangeIndex: selectedTimeRangeIndex ?? this.selectedTimeRangeIndex,
      chartPoints: chartPoints ?? this.chartPoints,
    );
  }
}