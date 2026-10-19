import 'package:flutter/material.dart';

/// Low / Normal / High bands for live sensor readings, taken from published
/// sources (full citations in docs/SENSOR_THRESHOLDS.md).
///
/// These are display bands for the farmer. They are NOT the ML thermal-status
/// classifier, which is shown only on the Dashboard recommendation card.
class ThermalThresholds {
  ThermalThresholds._();

  /// AMG8833 = apparent SKIN SURFACE temperature, not rectal/core temperature
  /// (rectal norm for pigs is 38.7-39.8 degC, MSD Veterinary Manual).
  /// Comfort skin temperature of pigs: 32-35 degC (Huynh, 2005, Wageningen
  /// University thesis, citing Geers et al., 1987; Huynh et al., 2005,
  /// J. Anim. Sci. 83:1385). 36 degC is reported as a heat-stress threshold
  /// for 60 kg pigs (Vermeer & Aarnink, 2023), so readings above 35 degC
  /// are shown as High.
  static const double skinTempLowBelowC = 32.0;
  static const double skinTempHighAboveC = 35.0;

  /// Relative humidity: 50-70 % is desirable in swine buildings
  /// (Fehr & Huhnke, 1984, MSU Extension Bulletin E-1760); 80 % RH worsened
  /// heat-stress responses (Huynh et al., 2005, J. Anim. Sci. 83:1385).
  static const double humidityLowBelowPct = 50.0;
  static const double humidityHighAbovePct = 70.0;

  /// Air (room) temperature, DHT22: comfort zone of grower pigs (50-130 lb)
  /// 60-75 degF = 15.6-23.9 degC (Liu, 2025, University of Guam Extension
  /// Fact Sheet EXT-02-2025, "Pig comfort zones"); consistent with the
  /// upper thermoneutral limits of Vermeer & Aarnink (2023, Table 3.3.1:
  /// grower 30 kg 28 degC, finisher >60 kg 25 degC). PAES 401:2001 sets
  /// 30 degC as the absolute maximum for housed growers/finishers.
  static const double airTempLowBelowC = 15.6;
  static const double airTempHighAboveC = 23.9;

  static String airTempStatus(double t) => _status(t, airTempLowBelowC, airTempHighAboveC);
  static Color airTempColor(double t) => _color(t, airTempLowBelowC, airTempHighAboveC);

  static String skinTempStatus(double t) => _status(t, skinTempLowBelowC, skinTempHighAboveC);
  static Color skinTempColor(double t) => _color(t, skinTempLowBelowC, skinTempHighAboveC);

  static String humidityStatus(double h) => _status(h, humidityLowBelowPct, humidityHighAbovePct);
  static Color humidityColor(double h) => _color(h, humidityLowBelowPct, humidityHighAbovePct);

  static String _status(double v, double low, double high) {
    if (v < low) return "Low";
    if (v <= high) return "Normal";
    return "High";
  }

  static Color _color(double v, double low, double high) {
    if (v < low) return Colors.blue;
    if (v <= high) return Colors.green;
    return Colors.red;
  }
}
