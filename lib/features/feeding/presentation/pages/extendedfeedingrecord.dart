import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../../domain/model/app_feeding_record.dart';

class FeedingRecordExpandedPreview extends StatefulWidget {
  final AppPig pig;
  final Color pigColor;

  const FeedingRecordExpandedPreview({
    super.key,
    required this.pig,
    required this.pigColor,
  });

  @override
  State<FeedingRecordExpandedPreview> createState() => _FeedingRecordExpandedPreviewState();
}

class _FeedingRecordExpandedPreviewState extends State<FeedingRecordExpandedPreview> {
  late Stream<AppFeedingRecord?> _feedingStream;

  @override
  void initState() {
    super.initState();
    // 🔹 Initialize stream ONCE here to prevent infinite read loops
    _feedingStream = FirebaseFirestore.instance
        .collection('pigs')
        .doc(widget.pig.pigId)
        .collection('feeding_records')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        try {
          return AppFeedingRecord.fromMap(snapshot.docs.first.data());
        } catch (e) {
          debugPrint(" ERROR PARSING FEEDING RECORD: $e");
          return null;
        }
      }
      return null;
    });
  }

  String _calculateAge(DateTime birthDate) {
    final days = DateTime.now().difference(birthDate).inDays;
    if (days < 30) return '$days days';
    final months = days ~/ 30;
    return '$months months';
  }

  Widget _buildInfoText(String label, String value, Color labelColor, Color textColor) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: '$label ', style: TextStyle(fontSize: 12, color: labelColor)),
          TextSpan(
            text: value,
            style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500),
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

    return StreamBuilder<AppFeedingRecord?>(
      stream: _feedingStream, // 🔹 Uses the cached stream
      builder: (context, snapshot) {
        String feedType = 'No data yet';
        String amount = '0';

        if (snapshot.hasData && snapshot.data != null) {
          feedType = snapshot.data!.feedType;
          amount = snapshot.data!.amount.toString();
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          feedType = '...';
          amount = '...';
        }

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoText('Age:', _calculateAge(widget.pig.birthDate), labelColor, textColor),
                  const SizedBox(height: 4),
                  _buildInfoText('Type of feed:', feedType, labelColor, textColor),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoText('Stage:', widget.pig.stage.isNotEmpty ? widget.pig.stage : 'N/A', labelColor, textColor),
                  const SizedBox(height: 4),
                  _buildInfoText('Amount of feeds:', amount, labelColor, textColor),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
