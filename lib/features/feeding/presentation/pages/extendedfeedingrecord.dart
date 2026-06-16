import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../../domain/model/app_feeding_record.dart';

class FeedingRecordExpandedPreview extends StatelessWidget {
  final AppPig pig;
  final Color pigColor;

  const FeedingRecordExpandedPreview({
    super.key,
    required this.pig,
    required this.pigColor,
  });

  //  Helper to calculate age from birthDate
  String _calculateAge(DateTime birthDate) {
    final days = DateTime.now().difference(birthDate).inDays;
    if (days < 30) return '$days days';
    final months = days ~/ 30;
    return '$months months';
  }

  //  Changed from Future to Stream, and .get() to .snapshots()
  Stream<AppFeedingRecord?> _streamLatestFeedingRecord() {
    return FirebaseFirestore.instance
        .collection('pigs')
        .doc(
          pig.pigId,
        ) // Make sure this is the exact string of the Firestore Document ID!
        .collection('feeding_records')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            try {
              return AppFeedingRecord.fromMap(snapshot.docs.first.data());
            } catch (e) {
              // If the data crashes while parsing, it will print here!
              debugPrint(" ERROR PARSING FEEDING RECORD: $e");
              return null;
            }
          }
          return null;
        });
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

    return StreamBuilder<AppFeedingRecord?>(
      stream: _streamLatestFeedingRecord(),
      builder: (context, snapshot) {
        String feedType = 'No data yet';
        String amount = '0';

        //  2. Add an explicit error check to show on the UI
        if (snapshot.hasError) {
          debugPrint(" STREAM ERROR: ${snapshot.error}");
          feedType = 'Stream Error!';
          amount = 'Error';
        } else if (snapshot.hasData && snapshot.data != null) {
          feedType = snapshot.data!.feedType;
          amount = snapshot.data!.amount.toString();
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          feedType = 'Loading...';
          amount = '...';
        }

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoText(
                    'Age:',
                    _calculateAge(pig.birthDate),
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
                    pig.stage.isNotEmpty ? pig.stage : 'N/A',
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
