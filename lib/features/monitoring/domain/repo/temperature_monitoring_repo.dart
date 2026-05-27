import '../model/app_temperature_reading.dart';

abstract class TemperatureMonitoringRepo {
  /// Fetches live hardware telemetry and parses it directly into a domain reading model
  Future<AppTemperatureReading> fetchLiveHardwareTelemetry();

  /// Sends a trigger payload to toggle state changes on physical sprinklers
  Future<bool> setSprinklerState(bool turnOn);

  /// Saves a structured summary record back to the database
  Future<void> saveTemperatureReading(AppTemperatureReading reading);

  /// Streams time-filtered reading summaries for graph plotting
  Stream<List<AppTemperatureReading>> streamFilteredReadings(int timeRangeIndex);
}