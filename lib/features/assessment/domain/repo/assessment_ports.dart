import '../model/assessment.dart';

/// Calls to the assessment API. Implemented by data/ml_assessment_api.dart; tests use fakes.
abstract class AssessmentApi {
  Future<Map<String, dynamic>> environment(Map<String, dynamic> body);
  Future<Map<String, dynamic>> pigGrowth(Map<String, dynamic> body);
  Future<Map<String, dynamic>> penThermal(Map<String, dynamic> body);
  Future<Map<String, dynamic>> ruleConfig();
  Future<Map<String, dynamic>> activeModel();
}

/// Where assessment results are kept (separate from raw observations).
abstract class AssessmentStore {
  Future<void> save(Assessment a,
      {required String userId, required String subjectId, required Map<String, dynamic> rawRef});
}

/// Local copy of the rule config, used when the API is unreachable.
abstract class RuleConfigCache {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> rules);
}

/// UI-only role check. The API enforces the role server-side on every admin request.
abstract class RoleChecker {
  Future<bool> isAdmin();
}
