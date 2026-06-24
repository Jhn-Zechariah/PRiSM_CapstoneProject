import '../model/app_medicine.dart';
import '../model/app_medicine_intake.dart';
import '../model/app_medicine_stock.dart';

abstract class MedicineRepository {
  /// Streams real-time updates for medicines belonging strictly to the specified user.
  Stream<List<Medicine>> streamMedicines(String userId);

  /// Atomically saves a new medicine profile and its accompanying initial stock batch.
  Future<void> addMedicineWithInitialStock({
    required Medicine medicine,
    required MedicineStock initialBatch,
  });

  Future<List<MedicineStock>> getMedicineStocks(String medicineId);

  Future<void> updateMedicineAndStock({
    required Medicine medicine,
    required MedicineStock updatedStock,
    required String stockDocId,
    required double oldStockAmount,
  });

  Future<void> addNewStockBatch({
    required Medicine medicine,
    required MedicineStock newStock,
  });

  Future<void> addIntakeAndReduceStock({
    required MedicineIntake intake,
    required MedicineStock selectedStock,
    required String medicineId,
  });

  // FIX #3: userId is now required to prevent cross-user data leaks.
  Stream<List<MedicineIntake>> streamIntakes(String userId);

  /// Streams upcoming intakes for the specific user.
  Stream<List<MedicineIntake>> streamUpcomingIntakes(String userId);
}