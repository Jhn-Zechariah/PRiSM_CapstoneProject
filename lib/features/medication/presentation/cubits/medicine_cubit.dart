import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_intake.dart';
import '../../domain/model/app_medicine_stock.dart';
import '../../domain/repo/medicine_repo.dart';
import 'medicine_states.dart';

class MedicineCubit extends Cubit<MedicineState> {
  final MedicineRepository repository;

  StreamSubscription? _medicineSubscription;
  StreamSubscription? _intakeSubscription;

  String? _lastLoadedUid;

  MedicineCubit({required this.repository}) : super(MedicineInitial());

  // ----------------------------------------------------------------------
  // MEDICINE STREAM LOGIC
  // ----------------------------------------------------------------------
  void listenToMedicines() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Prevent restarting same stream
    if (_lastLoadedUid == currentUser.uid &&
        _medicineSubscription != null) {
      return;
    }

    _lastLoadedUid = currentUser.uid;
    _medicineSubscription?.cancel();

    emit(MedicineLoading());

    _medicineSubscription =
        repository.streamMedicines(currentUser.uid).listen(
              (medicines) => emit(MedicineLoaded(medicines)),
          onError: (e) => emit(MedicineError(e.toString())),
        );
  }

  // ----------------------------------------------------------------------
  // MEDICINE INTAKE STREAM LOGIC
  // ----------------------------------------------------------------------
  void listenToIntakes() {
    if (_intakeSubscription != null) return;

    _intakeSubscription = repository.streamIntakes().listen(
          (intakes) => emit(MedicineIntakesLoaded(intakes)),
      onError: (e) => emit(MedicineError(e.toString())),
    );
  }

  // ----------------------------------------------------------------------
  // CRUD LOGIC
  // ----------------------------------------------------------------------
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

  Future<List<MedicineStock>> getStocksForMedicine(String medId) async {
    try {
      return await repository.getMedicineStocks(medId);
    } catch (e) {
      emit(MedicineError("Failed to load stock dates: $e"));
      return [];
    }
  }

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

      // Not needed if stream already active
      // listenToMedicines();
    } catch (e) {
      emit(MedicineError(e.toString()));
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

      // Not needed if stream already active
      // listenToMedicines();
    } catch (e) {
      emit(MedicineError(e.toString()));
    }
  }

  Future<void> addIntakeAndReduceStock({
    required MedicineIntake intake,
    required MedicineStock selectedStock,
    required String medicineId,
  }) async {
    try {
      emit(MedicineLoading());

      await repository.addIntakeAndReduceStock(
        intake: intake,
        selectedStock: selectedStock,
        medicineId: medicineId,
      );

      emit(MedicineSaveSuccess());

      // Not needed if stream already active
      // listenToMedicines();
    } catch (e, stackTrace) {
      print("🔥 FIRESTORE SAVE ERROR: $e");
      print("🔥 STACKTRACE: $stackTrace");

      final errorMessage =
      e.toString().replaceAll('Exception: ', '');

      emit(MedicineError(errorMessage));
    }
  }

  @override
  Future<void> close() {
    _medicineSubscription?.cancel();
    _intakeSubscription?.cancel();
    return super.close();
  }
}