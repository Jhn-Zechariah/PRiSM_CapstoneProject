import 'package:flutter/material.dart';

class NotificationControlsDialog extends StatefulWidget {
  const NotificationControlsDialog({Key? key}) : super(key: key);

  @override
  State<NotificationControlsDialog> createState() =>
      _NotificationControlsDialogState();
}

class _NotificationControlsDialogState
    extends State<NotificationControlsDialog> {
  bool isNotifEnabled = true;
  bool isHighTempAlert = true;
  bool isHighHumidityAlert = true;
  bool isLowStockAlert = true;
  bool isVaxSchedAlert = true;
  bool isMedExpAlert = true;
  bool isSoundOn = true;
  bool isVibrateOn = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.textTheme.bodyLarge?.color;

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
                'Notification Preferences',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.orange[800],
                ),
              ),
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('Notification', textColor),
            const SizedBox(height: 8),
            _buildSwitchRow(
              context: context,
              dotColor: Colors.blue[900]!,
              label: 'Enable Notifications',
              isEnabled: true,
              value: isNotifEnabled,
              onChanged: (val) {
                setState(() {
                  isNotifEnabled = val;
                  if (!val) {
                    isHighTempAlert = false;
                    isHighHumidityAlert = false;
                    isLowStockAlert = false;
                    isVaxSchedAlert = false;
                    isMedExpAlert = false;
                    isSoundOn = false;
                    isVibrateOn = false;
                  }
                });
              },
            ),
            _buildDivider(isDark),

            _buildSectionHeader('Alert types', textColor),
            const SizedBox(height: 8),

            _buildSwitchRow(
              context: context,
              dotColor: Colors.blue[900]!,
              label: 'High temperature alert',
              value: isHighTempAlert,
              onChanged: (val) => setState(() => isHighTempAlert = val),
              isEnabled: isNotifEnabled,
            ),
            const SizedBox(height: 12),
            _buildSwitchRow(
              context: context,
              dotColor: Colors.red[600]!,
              label: 'High humidity alert',
              value: isHighHumidityAlert,
              onChanged: (val) => setState(() => isHighHumidityAlert = val),
              isEnabled: isNotifEnabled,
            ),
            const SizedBox(height: 12),
            _buildSwitchRow(
              context: context,
              dotColor: Colors.orange[800]!,
              label: 'Low stock alert',
              value: isLowStockAlert,
              onChanged: (val) => setState(() => isLowStockAlert = val),
              isEnabled: isNotifEnabled,
            ),
            const SizedBox(height: 12),
            _buildSwitchRow(
              context: context,
              dotColor: Colors.blue[900]!,
              label: 'Vaccination Schedule',
              value: isVaxSchedAlert,
              onChanged: (val) => setState(() => isVaxSchedAlert = val),
              isEnabled: isNotifEnabled,
            ),
            const SizedBox(height: 12),
            _buildSwitchRow(
              context: context,
              dotColor: Colors.red[600]!,
              label: 'Medicine Expiration',
              value: isMedExpAlert,
              onChanged: (val) => setState(() => isMedExpAlert = val),
              isEnabled: isNotifEnabled,
            ),
            _buildDivider(isDark),

            _buildSectionHeader('Settings', textColor),
            const SizedBox(height: 8),

            _buildSwitchRowSettings(
              context: context,
              logoIcon: const Icon(Icons.volume_up, size: 20),
              label: 'Sound',
              value: isSoundOn,
              onChanged: (val) {
                setState(() {
                  isSoundOn = val;
                  if (!val) {
                    isVibrateOn = false;
                  }
                });
              },
              isEnabled: isNotifEnabled,
            ),
            const SizedBox(height: 8),

            _buildSwitchRowSettings(
              context: context,
              logoIcon: const Icon(Icons.vibration, size: 20),
              label: 'Vibration',
              value: isVibrateOn,
              onChanged: (val) {
                setState(() {
                  isVibrateOn = val;
                  if (val) {
                    isSoundOn = true;
                  }
                });
              },
              isEnabled: isNotifEnabled,
            ),
            const SizedBox(height: 24),

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
                  isNotifEnabled ? textColor : theme.disabledColor,
                  isNotifEnabled ? () => Navigator.pop(context) : () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  //helpers
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

  Widget _buildSwitchRowSettings({
    required BuildContext context,
    required Icon logoIcon,
    required String label,
    required bool value,
    required bool isEnabled,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        logoIcon,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
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
}
