import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../../domain/model/app_feeding_record.dart';
import '../cubits/feeding_record_cubit.dart';
import '../cubits/feeding_record_states.dart';

class FeedingRecordExpandedPreview extends StatefulWidget {
  final AppPig pig;
  final Color pigColor;

  const FeedingRecordExpandedPreview({
    super.key,
    required this.pig,
    required this.pigColor,
  });

  @override
  State<FeedingRecordExpandedPreview> createState() =>
      _FeedingRecordExpandedPreviewState();
}

class _FeedingRecordExpandedPreviewState
    extends State<FeedingRecordExpandedPreview> {

  // 🔹 Local state variable to securely hold onto the latest record once received
  AppFeedingRecord? _latestRecord;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<FeedingRecordCubit>().loadLatestRecord(widget.pig.pigId);
      }
    });
  }

  String _calculateAge(DateTime birthDate) {
    final days = DateTime.now().difference(birthDate).inDays;
    if (days < 30) return '$days days';
    final months = days ~/ 30;
    return '$months months';
  }

  Widget _buildInfoText(
      String label,
      String value,
      Color labelColor,
      Color textColor,
      ) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(fontSize: 12, color: labelColor),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white70 : Colors.black54;

    // 🔹 Swapped BlocBuilder for BlocConsumer to intercept and preserve state changes locally
    return BlocConsumer<FeedingRecordCubit, FeedingRecordState>(
      listenWhen: (previous, current) =>
      (current is LatestFeedingRecordLoaded && current.pigId == widget.pig.pigId) ||
          (current is LatestFeedingRecordsBulkUpdated && current.updates.containsKey(widget.pig.pigId)),
      listener: (context, state) {
        // Capture single or bulk updates immediately into local component state
        if (state is LatestFeedingRecordLoaded && state.pigId == widget.pig.pigId) {
          setState(() => _latestRecord = state.record);
        } else if (state is LatestFeedingRecordsBulkUpdated && state.updates.containsKey(widget.pig.pigId)) {
          setState(() => _latestRecord = state.updates[widget.pig.pigId]);
        }
      },
      buildWhen: (previous, current) =>
      (current is LatestFeedingRecordLoading && current.pigId == widget.pig.pigId) ||
          (current is LatestFeedingRecordLoaded && current.pigId == widget.pig.pigId) ||
          (current is LatestFeedingRecordError && current.pigId == widget.pig.pigId) ||
          (current is LatestFeedingRecordsBulkUpdated && current.updates.containsKey(widget.pig.pigId)),
      builder: (context, state) {
        // Prioritize our persistent local state record, fallback to cubit cache if empty
        AppFeedingRecord? activeRecord = _latestRecord ??
            context.read<FeedingRecordCubit>().getCachedLatestRecord(widget.pig.pigId);

        bool isLoading = false;

        if (state is LatestFeedingRecordLoading && state.pigId == widget.pig.pigId) {
          isLoading = true;
        }

        // Always display the absolute latest values resolved above safely
        final feedType = isLoading ? '...' : (activeRecord?.feedType ?? 'No data yet');
        final amount = isLoading ? '...' : (activeRecord?.amount.toString() ?? '0');

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoText(
                    'Age:',
                    _calculateAge(widget.pig.birthDate),
                    labelColor,
                    textColor,
                  ),
                  const SizedBox(height: 4),
                  _buildInfoText(
                    'Type of feed:',
                    feedType,
                    labelColor,
                    textColor,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoText(
                    'Stage:',
                    widget.pig.stage.isNotEmpty ? widget.pig.stage : 'N/A',
                    labelColor,
                    textColor,
                  ),
                  const SizedBox(height: 4),
                  _buildInfoText(
                    'Amount of feeds:',
                    amount,
                    labelColor,
                    textColor,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}