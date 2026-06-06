import 'package:flutter/material.dart';

class ThemeSettingsDialog extends StatefulWidget {
  final ThemeMode currentTheme;
  final Function(ThemeMode) onThemeSelected;

  const ThemeSettingsDialog({
    super.key,
    required this.currentTheme,
    required this.onThemeSelected,
  });

  @override
  State<ThemeSettingsDialog> createState() => _ThemeSettingsDialogState();
}

class _ThemeSettingsDialogState extends State<ThemeSettingsDialog> {
  late ThemeMode _selectedTheme;

  @override
  void initState() {
    super.initState();
    // Pre-select the radio button based on the currently active theme
    _selectedTheme = widget.currentTheme;
  }

  void _handleThemeChange(ThemeMode newMode) {
    setState(() {
      _selectedTheme = newMode;
    });
    widget.onThemeSelected(newMode);
    Navigator.pop(context); // Auto-close dialog on selection
  }

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
                "Theme Settings",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.orange[800], // Kept your branding color
                ),
              ),
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('Appearance', textColor),
            _buildDivider(isDark),
            const SizedBox(height: 2),

            _buildRadioRow(
              context: context,
              icon: Icons.brightness_auto, // 🔹 Changed to Icon
              iconColor: Colors.blue,
              label: 'System Default',
              value: ThemeMode.system,
            ),

            _buildRadioRow(
              context: context,
              icon: Icons.wb_sunny, // 🔹 Changed to Icon
              iconColor: Colors.amber,
              label: 'Light Mode',
              value: ThemeMode.light,
            ),

            _buildRadioRow(
              context: context,
              icon: Icons.nightlight_round, // 🔹 Changed to Icon
              iconColor: Colors.deepPurple[400]!,
              label: 'Dark Mode',
              value: ThemeMode.dark,
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
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Divider(
        color: isDark ? Colors.white24 : Colors.grey[400],
        thickness: 0.5,
      ),
    );
  }

  Widget _buildRadioRow({
    required BuildContext context,
    required IconData icon, // 🔹 Accept an IconData
    required Color iconColor, // 🔹 Accept an icon color
    required String label,
    required ThemeMode value,
  }) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;

    return InkWell(
      // Makes the entire row tap-able, not just the tiny radio circle!
      onTap: () => _handleThemeChange(value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor,
              size: 22, // 🔹 Nice readable size for the icon
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
            ),
            Radio<ThemeMode>(
              value: value,
              groupValue: _selectedTheme,
              activeColor: Colors.orange[800], // Matches the title color
              onChanged: (ThemeMode? newValue) {
                if (newValue != null) {
                  _handleThemeChange(newValue);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}