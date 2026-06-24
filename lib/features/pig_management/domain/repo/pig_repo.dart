import '../model/app_pig.dart';
import '../model/app_weight_history.dart';

abstract class PigRepo {
  Stream<List<AppPig>> streamPigs(String userId);

  Future<void> addPig(AppPig pig);

  // 🔹 CHANGED: now requires oldWeightKg so we don't need an extra read
  // to detect whether the weight changed.
  Future<void> updatePigProfile(AppPig updatedPig, {required double oldWeightKg});

  Future<void> updatePigWeight(String pigId, double newWeight);

  Stream<List<AppWeightRecord>> streamWeightHistory(String pigId);

}