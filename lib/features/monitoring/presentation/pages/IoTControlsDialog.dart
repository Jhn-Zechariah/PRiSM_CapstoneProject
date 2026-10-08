import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../auth/presentation/cubits/profile_cubit.dart';

class IoTControlsDialog extends StatefulWidget {
  const IoTControlsDialog({super.key});

  @override
  State<IoTControlsDialog> createState() => _IoTControlsDialogState();
}

class _IoTControlsDialogState extends State<IoTControlsDialog> {
  bool isIotEnabled = true;
  bool isSprinklerAuto = true;

  final TextEditingController _tempController = TextEditingController();
  final TextEditingController _humidityController = TextEditingController();
  final TextEditingController _scheduleController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _durationController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadPreferences();
  }

  @override
  void dispose() {
    _tempController.dispose();
    _humidityController.dispose();
    _scheduleController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  // Load preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // Start with the local values
    bool iot = prefs.getBool('isIotEnabled') ?? true;
    bool auto = prefs.getBool('isSprinklerAuto') ?? true;
    String schedule = prefs.getString('iotSchedule') ?? '';
    String duration = prefs.getString('iotDuration') ?? '';

    // Firestore wins if it has saved settings
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sprinkler_settings')
          .doc('config')
          .get();
      final data = snap.data();
      if (data != null) {
        iot = data['isIotEnabled'] ?? iot;
        auto = data['isSprinklerAuto'] ?? auto;
        schedule = (data['schedule'] ?? schedule).toString();
        final d = data['durationMins'];
        if (d != null) duration = d.toString();
      }
    } catch (_) {
      // offline: keep the local values
    }

    if (!mounted) return;
    setState(() {
      isIotEnabled = iot;
      isSprinklerAuto = auto;
      _tempController.text = prefs.getString('iotMaxTemp') ?? '';
      _humidityController.text = prefs.getString('iotMaxHumidity') ?? '';
      _scheduleController.text = schedule;
      _durationController.text = duration;
      _isLoading = false;
    });
  }

    // Opens a clock picker and writes the time like "6:00 PM"
  Future<void> _pickScheduleTime() async {
    TimeOfDay initial = TimeOfDay.now();

    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$')
        .firstMatch(_scheduleController.text.trim().toUpperCase());
    if (m != null) {
      int h = int.parse(m.group(1)!);
      final min = int.parse(m.group(2)!);
      final pm = m.group(3) == 'PM';
      if (h == 12) {
        h = pm ? 12 : 0;
      } else if (pm) {
        h += 12;
      }
      initial = TimeOfDay(hour: h, minute: min);
    }

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final h12 = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final mm = picked.minute.toString().padLeft(2, '0');
      final ap = picked.period == DayPeriod.am ? 'AM' : 'PM';
      setState(() => _scheduleController.text = '$h12:$mm $ap');
    }
  }

    // Shows the current schedule at the top of the sprinkler section
  Widget _buildScheduleSummary(ThemeData theme) {
    final schedule = _scheduleController.text.trim();
    final duration = _durationController.text.trim();
    final active = isIotEnabled && isSprinklerAuto && schedule.isNotEmpty;

    final text = schedule.isEmpty
        ? 'No schedule set'
        : 'Daily at $schedule • ${duration.isEmpty ? '5' : duration} mins • '
            '${active ? 'Active' : 'Paused'}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (active ? Colors.green : Colors.grey).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 18,
            color: active ? Colors.green[600] : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Save preferences to SharedPreferences AND sync to Firestore
  Future<void> _savePreferences() async {
    // Validate schedule: format like 6:00 PM or 11:30 AM
    final scheduleRaw = _scheduleController.text.trim().toUpperCase();
    final match = RegExp(r'^(0?[1-9]|1[0-2]):([0-5]\d)\s*(AM|PM)$')
        .firstMatch(scheduleRaw);

    if (scheduleRaw.isNotEmpty && match == null) {
      if (mounted) {
        CustomSnackbar.show(
          context: context,
          message: "Schedule must look like 6:00 PM",
        );
      }
      return;
    }

    // Clean version, e.g. "06:00pm" becomes "6:00 PM"
    final scheduleText = match == null
        ? ''
        : '${int.parse(match.group(1)!)}:${match.group(2)} ${match.group(3)}';
    _scheduleController.text = scheduleText;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isIotEnabled', isIotEnabled);
    await prefs.setBool('isSprinklerAuto', isSprinklerAuto);
    await prefs.setString('iotMaxTemp', _tempController.text);
    await prefs.setString('iotMaxHumidity', _humidityController.text);
    await prefs.setString('iotSchedule', scheduleText);
    await prefs.setString('iotDuration', _durationController.text);

    final maxTemp = double.tryParse(_tempController.text);
    final maxHumidity = double.tryParse(_humidityController.text);

    // Settings document the ESP32 reads (fixed path, no user id needed)
    await FirebaseFirestore.instance
        .collection('sprinkler_settings')
        .doc('config')
        .set({
      'isIotEnabled': isIotEnabled,
      'isSprinklerAuto': isSprinklerAuto,
      'schedule': scheduleText,
      'durationMins': int.tryParse(_durationController.text.trim()) ?? 5,
    }, SetOptions(merge: true));

    // 🔹 Synchronize thresholds to Firestore so the backend (Cloud
    // Functions) can compare incoming live sensor readings against them.
    if (mounted) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final profileCubit = context.read<ProfileCubit>();
        await profileCubit.syncIotThresholds(user.uid, {
          'isIotEnabled': isIotEnabled,
          'isSprinklerAuto': isSprinklerAuto,
          'maxTemp': maxTemp,
          'maxHumidity': maxHumidity,
          'schedule': scheduleText,
          'durationMins': int.tryParse(_durationController.text),
        });
      }

      CustomSnackbar.show(
        context: context,
        message: "IoT settings saved and synced!",
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.textTheme.bodyLarge?.color;

    if (_isLoading) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                "IoT Controls",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.orange[800],
                ),
              ),
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('Overall control', textColor),
            const SizedBox(height: 8),
            _buildSwitchRow(
              context: context,
              dotColor: Colors.blue[900]!,
              label: 'Enable IoT System',
              value: isIotEnabled,
              isEnabled: true,
              onChanged: (val) {
                setState(() {
                  isIotEnabled = val;
                  isSprinklerAuto = val;
                });
              },
            ),
            _buildDivider(isDark),

            _buildSectionHeader('Sensor control', textColor),
            const SizedBox(height: 12),
            _buildInputRow(
              context: context,
              dotColor: Colors.blue[900]!,
              label: 'Max body temperature',
              controller: _tempController,
              hintText: '°C',
              enabled: isIotEnabled,
            ),
            const SizedBox(height: 12),
            _buildInputRow(
              context: context,
              dotColor: Colors.red[600]!,
              label: 'Max humidity',
              controller: _humidityController,
              hintText: '%',
              enabled: isIotEnabled,
            ),
            _buildDivider(isDark),

            _buildSectionHeader('Sprinkler control', textColor),
            const SizedBox(height: 8),
            _buildScheduleSummary(theme),
            const SizedBox(height: 12),
            _buildSwitchRow(
              context: context,
              dotColor: Colors.blue[900]!,
              label: 'Sprinkler automatic activation',
              value: isSprinklerAuto,
              onChanged: (val) => setState(() => isSprinklerAuto = val),
              isEnabled: isIotEnabled,
            ),
            const SizedBox(height: 12),
            _buildInputRow(
              context: context,
              dotColor: Colors.red[600]!,
              label: 'Activation schedule',
              controller: _scheduleController,
              hintText: 'Tap to set',
              enabled: isIotEnabled,
              readOnly: true,
              onTap: _pickScheduleTime,
            ),
            const SizedBox(height: 12),
            _buildInputRow(
              context: context,
              dotColor: Colors.orange[800]!,
              label: 'Activation duration',
              controller: _durationController,
              hintText: 'mins',
              enabled: isIotEnabled,
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildActionButton(
                  'Cancel',
                  textColor,
                      () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  'Save',
                  textColor,
                  _savePreferences,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Methods ---

  Widget _buildSectionHeader(String title, Color? color) {
    return Text(
      title,
      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Divider(
        color: isDark ? Colors.white24 : Colors.grey[400],
        thickness: 0.5,
      ),
    );
  }

  Widget _buildActionButton(
      String label,
      Color? color,
      VoidCallback onPressed,
      ) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSwitchRow({
    required BuildContext context,
    required Color dotColor,
    required String label,
    required bool value,
    required bool isEnabled,
    required ValueChanged<bool> onChanged,
  }) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isEnabled ? dotColor : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
        ),
        Switch(
          value: value,
          onChanged: isEnabled ? onChanged : null,
          activeThumbColor: Colors.white,
          activeTrackColor: Colors.green[600],
        ),
      ],
    );
  }

  Widget _buildInputRow({
    required BuildContext context,
    required Color dotColor,
    required String label,
    required TextEditingController controller,
    required bool enabled,
    String? hintText,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: enabled ? dotColor : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: enabled
                  ? theme.textTheme.bodyLarge?.color
                  : theme.disabledColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(6),
                boxShadow: isDark
                    ? []
                    : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: TextField(
                controller: controller,
                enabled: enabled,
                readOnly: readOnly,
                onTap: onTap,
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(color: theme.hintColor, fontSize: 11),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                ),
                keyboardType: label.contains("schedule")
                    ? TextInputType.text
                    : TextInputType.number,
              ),
            ),
          ),
        ),
      ],
    );
  }
}