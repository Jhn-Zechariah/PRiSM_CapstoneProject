import '../models/app_pig.dart';

abstract class PigRepo {
  // Adds a new pig profile and initializes weight history
  Future<void> addPig(AppPig pig);

  // Gets a real-time stream of all pigs
  Stream<List<AppPig>> streamPigs();

  // Updates the pig's current weight and adds a history record
  Future<void> updatePigWeight(String pigId, double newWeight);

  // Deletes a pig profile
  Future<void> deletePig(String pigId);
}