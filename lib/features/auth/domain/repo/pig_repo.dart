import '../models/app_pig.dart';
import '../models/app_weight_history.dart';

abstract class PigRepo {
  // Adds a new pig profile and initializes weight history
  Future<void> addPig(AppPig pig);

  //update pig
  Future<void> updatePigProfile(AppPig updatedPig);

  // Gets a real-time stream of all pigs
  Stream<List<AppPig>> streamPigs(String userId);

  // Updates the pig's current weight and adds a history record
  Future<void> updatePigWeight(String pigId, double newWeight);

  // Add this inside abstract class PigRepo
  Stream<List<AppWeightRecord>> streamWeightHistory(String pigId);

  // Deletes a pig profile
  Future<void> deletePig(String pigId);
}