import 'package:flutter/material.dart';

class IoTControlsDialog extends StatefulWidget {
  const IoTControlsDialog({Key? key}) : super(key: key);

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

  @override
  void dispose() {
    _tempController.dispose();
    _humidityController.dispose();
    _scheduleController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Define theme variables
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.textTheme.bodyLarge?.color;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // 2. Adapt background color
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
                  // Keep branding color consistent
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
                  // If the master switch is turned OFF,
                  // we force the sprinkler auto activation to OFF as well.
                  if (!val) {
                    isSprinklerAuto = false;
                  }
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
              hintText: '00:00',
              enabled: isIotEnabled,
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
                  isIotEnabled ? textColor : theme.disabledColor,
                  isIotEnabled ? () => Navigator.pop(context) : () {},
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
                // Input background adapts
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
                // Text and Hint color adapt
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
                    ? TextInputType.datetime
                    : TextInputType.number,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
