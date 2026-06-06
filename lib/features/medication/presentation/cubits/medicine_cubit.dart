import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 🔹 Added for real-time user detection
import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_stock.dart';
import '../../domain/repo/medicine_repo.dart';
import 'medicine_states.dart';

class MedicineCubit extends Cubit<MedicineState> {
  final MedicineRepository repository;
  StreamSubscription? _medicineSubscription;

  MedicineCubit({required this.repository}) : super(MedicineInitial());

  // 🔹 Automatically captures logged in user to start streaming their data
  void listenToMedicines() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      emit(MedicineError("No authenticated user found."));
      return;
    }

    emit(MedicineLoading());
    _medicineSubscription?.cancel();

    // Pass the active user ID into our repository stream filter
    _medicineSubscription = repository.streamMedicines(currentUser.uid).listen(
          (medicines) {
        emit(MedicineLoaded(medicines));
      },
      onError: (error) {
        emit(MedicineError(error.toString()));
      },
    );
  }

  Future<void> saveMedicineWithStock({
    required Medicine medicine,
    required MedicineStock initialBatch,
  }) async {
    try {
      await repository.addMedicineWithInitialStock(
        medicine: medicine,
        initialBatch: initialBatch,
      );
      emit(MedicineSaveSuccess());
    } catch (e) {
      emit(MedicineError(e.toString()));
    }
  }

// 🔹 Fetch the list of stocks for the dropdown
  Future<List<MedicineStock>> getStocksForMedicine(String medId) async {
    try {
      return await repository.getMedicineStocks(medId);
    } catch (e) {
      emit(MedicineError("Failed to load stock dates: $e"));
      return [];
    }
  }

  // 🔹 Send the update to Firestore
  Future<void> updateMedicineItem({
    required Medicine medicine,
    required MedicineStock updatedStock,
    required String stockDocId,
    required double oldStockAmount,
  }) async {
    try {
      emit(MedicineLoading());

      await repository.updateMedicineAndStock(
        medicine: medicine,
        updatedStock: updatedStock,
        stockDocId: stockDocId,
        oldStockAmount: oldStockAmount,
      );

      emit(MedicineSaveSuccess());

      listenToMedicines();
    } catch (e) {
      emit(MedicineError( e.toString()));
    }
  }

  Future<void> addNewStockBatch({
    required Medicine medicine,
    required MedicineStock newStock,
  }) async {
    try {
      emit(MedicineLoading());

      await repository.addNewStockBatch(
        medicine: medicine,
        newStock: newStock,
      );

      emit(MedicineSaveSuccess());

      // 🔹 Instantly refresh the UI stream just like we did for updates!
      listenToMedicines();
    } catch (e) {
      emit(MedicineError(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _medicineSubscription?.cancel();
    return super.close();
  }
}