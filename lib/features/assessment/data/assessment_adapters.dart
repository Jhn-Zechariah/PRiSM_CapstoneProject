import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/ml_service.dart';
import '../domain/repo/assessment_ports.dart';

/// Production adapter over the existing MlService.
class MlAssessmentApi implements AssessmentApi {
  const MlAssessmentApi();

  @override
  Future<Map<String, dynamic>> environment(Map<String, dynamic> body) => MlService.assessEnvironment(body);

  @override
  Future<Map<String, dynamic>> pigGrowth(Map<String, dynamic> body) => MlService.assessPigGrowth(body);

  @override
  Future<Map<String, dynamic>> penThermal(Map<String, dynamic> body) => MlService.assessPenThermal(body);

  @override
  Future<Map<String, dynamic>> ruleConfig() => MlService.fetchRuleConfig();

  @override
  Future<Map<String, dynamic>> activeModel() => MlService.fetchActiveModel();
}

class PrefsRuleConfigCache implements RuleConfigCache {
  static const _key = 'assessment_rule_config_v1';

  @override
  Future<Map<String, dynamic>?> load() async {
    final s = (await SharedPreferences.getInstance()).getString(_key);
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  @override
  Future<void> save(Map<String, dynamic> rules) async {
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(rules));
  }
}

/// Reads the role from the Firebase ID token's custom claims (set server-side only).
class FirebaseRoleChecker implements RoleChecker {
  final String claim;
  final String value;
  FirebaseRoleChecker(this.claim, this.value);

  @override
  Future<bool> isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult();
    return token.claims?[claim] == value;
  }
}
