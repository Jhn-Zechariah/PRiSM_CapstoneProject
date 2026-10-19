import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/core/constants/thermal_thresholds.dart';

/// Bands from docs/SENSOR_THRESHOLDS.md: skin 32-35 degC, humidity 50-70 %.
void main() {
  test('AMG8833 skin-surface temperature bands', () {
    expect(ThermalThresholds.skinTempStatus(31.9), 'Low');
    expect(ThermalThresholds.skinTempStatus(32.0), 'Normal');
    expect(ThermalThresholds.skinTempStatus(35.0), 'Normal');
    expect(ThermalThresholds.skinTempStatus(35.1), 'High');
    expect(ThermalThresholds.skinTempColor(30), Colors.blue);
    expect(ThermalThresholds.skinTempColor(34), Colors.green);
    expect(ThermalThresholds.skinTempColor(37), Colors.red);
  });

  test('relative humidity bands', () {
    expect(ThermalThresholds.humidityStatus(49.9), 'Low');
    expect(ThermalThresholds.humidityStatus(50), 'Normal');
    expect(ThermalThresholds.humidityStatus(70), 'Normal');
    expect(ThermalThresholds.humidityStatus(70.1), 'High');
    expect(ThermalThresholds.humidityColor(85), Colors.red);
  });

  test('air temperature: grower comfort zone 15.6-23.9 degC', () {
    expect(ThermalThresholds.airTempStatus(15.5), 'Low');
    expect(ThermalThresholds.airTempStatus(15.6), 'Normal');
    expect(ThermalThresholds.airTempStatus(23.9), 'Normal');
    expect(ThermalThresholds.airTempStatus(24.0), 'High');
    expect(ThermalThresholds.airTempColor(31), Colors.red);
  });
}
