import 'package:intl/intl.dart';

import '../../pig_management/domain/model/app_pig.dart';
import '../../pig_management/domain/model/app_weight_history.dart';

final _day = DateFormat('yyyy-MM-dd');

/// Request body for POST /assess/pig-growth from MANUAL pig data only (no temperature).
/// Shared by the pig profile card and the Weight History growth panel.
Map<String, dynamic> growthRequestBody(AppPig pig, List<AppWeightRecord> records) => {
      'pig': {
        'pig_id': pig.pigId,
        'birth_date': _day.format(pig.birthDate),
        'sex': pig.sex,
        'breed': pig.breed,
      },
      'weights': [
        for (final r in records.where((r) => r.weightKg > 0))
          {
            'id': r.id,
            'date': _day.format(r.dateRecorded),
            'weight_kg': r.weightKg,
            'source': r.source,
            'notes': r.notes.length > 120 ? r.notes.substring(0, 120) : r.notes,
          }
      ],
    };
