import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SprinklerLogsDialog extends StatefulWidget {
  const SprinklerLogsDialog({super.key});

  @override
  State<SprinklerLogsDialog> createState() => _SprinklerLogsDialogState();
}

class _SprinklerLogsDialogState extends State<SprinklerLogsDialog> {
  String _filter = 'Today';
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _showCustomPanel = false;
  bool _menuOpen = false;

  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = now;
    _startTime = const TimeOfDay(hour: 0, minute: 0);
    _endDate = now;
    _endTime = TimeOfDay.fromDateTime(now);
  }

  static const _filters = ['Today', 'This week', 'This month', 'Custom range'];

  static const _months = [
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

  String _fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  String _fmtTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  String _fmtDuration(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return m > 0 ? '${m}m ${r}s' : '${r}s';
  }

  DateTimeRange _currentRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    switch (_filter) {
      case 'This week':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day - (now.weekday - 1)),
          end: tomorrow,
        );
      case 'This month':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: tomorrow,
        );
      case 'Custom range':
        return DateTimeRange(
          start: _customStart ?? today,
          end: _customEnd ?? tomorrow,
        );
      default:
        return DateTimeRange(start: today, end: tomorrow);
    }
  }

  void _onFilterChanged(String? v) {
    if (v == null) return;
    setState(() {
      _filter = v;
      _showCustomPanel = v == 'Custom range';
      _menuOpen = false;
    });
  }

  DateTime get _fullStart => DateTime(
    _startDate.year,
    _startDate.month,
    _startDate.day,
    _startTime.hour,
    _startTime.minute,
  );
  DateTime get _fullEnd => DateTime(
    _endDate.year,
    _endDate.month,
    _endDate.day,
    _endTime.hour,
    _endTime.minute,
  );
  bool get _isValid => _fullStart.isBefore(_fullEnd);

  String _tod(TimeOfDay t) => _fmtTime(DateTime(2000, 1, 1, t.hour, t.minute));

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: const Color(0xFFE8622A)),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => isStart ? _startDate = picked : _endDate = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: const Color(0xFFE8622A)),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  void _applyRange() {
    setState(() {
      _customStart = _fullStart;
      _customEnd = _fullEnd;
      _showCustomPanel = false;
    });
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE8622A).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFE8622A).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 13, color: const Color(0xFFE8622A)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomPanel(bool isDark) {
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade500,
      letterSpacing: 0.5,
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8622A).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE8622A).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From', style: labelStyle),
          const SizedBox(height: 4),
          Row(
            children: [
              _chip(
                Icons.calendar_today_outlined,
                _fmtDate(_startDate),
                () => _pickDate(true),
              ),
              const SizedBox(width: 6),
              _chip(Icons.access_time, _tod(_startTime), () => _pickTime(true)),
            ],
          ),
          const SizedBox(height: 8),
          Text('To', style: labelStyle),
          const SizedBox(height: 4),
          Row(
            children: [
              _chip(
                Icons.calendar_today_outlined,
                _fmtDate(_endDate),
                () => _pickDate(false),
              ),
              const SizedBox(width: 6),
              _chip(Icons.access_time, _tod(_endTime), () => _pickTime(false)),
            ],
          ),
          if (!_isValid)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 13, color: Colors.red),
                  SizedBox(width: 4),
                  Text(
                    'Start must be before end.',
                    style: TextStyle(color: Colors.red, fontSize: 11),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton(
              onPressed: _isValid ? _applyRange : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8622A),
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Apply Range',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.textTheme.bodyLarge?.color;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sprinkler Logs',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.orange[800],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _menuOpen = !_menuOpen),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade400,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _filter,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Icon(
                                _menuOpen
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: textColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_menuOpen)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.white,
                            border: Border.all(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade400,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: _filters
                                .map(
                                  (f) => InkWell(
                                    onTap: () => _onFilterChanged(f),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 11,
                                      ),
                                      color: f == _filter
                                          ? const Color(
                                              0xFFE8622A,
                                            ).withValues(alpha: 0.10)
                                          : Colors.transparent,
                                      child: Text(
                                        f,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: textColor,
                                          fontWeight: f == _filter
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      if (_filter == 'Custom range' && _showCustomPanel)
                        _buildCustomPanel(isDark),
                      if (_filter == 'Custom range' &&
                          !_showCustomPanel &&
                          _customStart != null &&
                          _customEnd != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFE8622A,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(
                                0xFFE8622A,
                              ).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.schedule,
                                size: 14,
                                color: Color(0xFFE8622A),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${_fmtDate(_customStart!)} ${_fmtTime(_customStart!)}  →  '
                                  '${_fmtDate(_customEnd!)} ${_fmtTime(_customEnd!)}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFFE8622A),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _showCustomPanel = true),
                                child: const Icon(
                                  Icons.edit_outlined,
                                  size: 14,
                                  color: Color(0xFFE8622A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() {
                                  _filter = 'Today';
                                  _customStart = null;
                                  _customEnd = null;
                                  _showCustomPanel = false;
                                }),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Color(0xFFE8622A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('sprinkler_logs')
                            .where(
                              'timestamp',
                              isGreaterThanOrEqualTo: Timestamp.fromDate(
                                _currentRange().start,
                              ),
                            )
                            .where(
                              'timestamp',
                              isLessThan: Timestamp.fromDate(
                                _currentRange().end,
                              ),
                            )
                            .orderBy('timestamp', descending: true)
                            .limit(200)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Center(
                              child: Text(
                                'Failed to load logs',
                                style: TextStyle(color: textColor),
                              ),
                            );
                          }
                          if (!snap.hasData) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final docs = snap.data!.docs;
                          if (docs.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No logs for this period',
                                  style: TextStyle(color: textColor),
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              thickness: 0.5,
                              color: isDark ? Colors.white24 : Colors.grey[400],
                            ),
                            itemBuilder: (context, i) {
                              final d = docs[i].data();
                              final isSchedule = d['type'] == 'schedule';
                              final ts = (d['timestamp'] as Timestamp?)
                                  ?.toDate()
                                  .toLocal();
                              final durSec =
                                  (d['durationSec'] as num?)?.toInt() ?? 0;

                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  isSchedule ? Icons.schedule : Icons.touch_app,
                                  color: isSchedule
                                      ? Colors.blue[700]
                                      : Colors.orange[800],
                                ),
                                title: Text(
                                  isSchedule
                                      ? 'Schedule activation'
                                      : 'Manual activation',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: textColor,
                                  ),
                                ),
                                subtitle: Text(
                                  '${ts == null ? '--' : '${_fmtDate(ts)} • ${_fmtTime(ts)}'}'
                                  '\nDuration: ${_fmtDuration(durSec)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textColor,
                                  ),
                                ),
                                isThreeLine: true,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
