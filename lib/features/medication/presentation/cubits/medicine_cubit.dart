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
  StreamSubscription? _intakeSubscription; // 🔹 Added subscription for intakes

  MedicineCubit({required this.repository}) : super(MedicineInitial());

  // ----------------------------------------------------------------------
  // 🔹 MEDICINE STREAM LOGIC
  // ----------------------------------------------------------------------
  void listenToMedicines() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      emit(MedicineError("No authenticated user found."));
      return;
    }

    emit(MedicineLoading());
    _medicineSubscription?.cancel();

    _medicineSubscription = repository.streamMedicines(currentUser.uid).listen(
          (medicines) {
        emit(MedicineLoaded(medicines));
      },
      onError: (error) {
        emit(MedicineError(error.toString()));
      },
    );
  }

  // ----------------------------------------------------------------------
  // 🔹 MEDICINE INTAKE STREAM LOGIC (MERGED HERE)
  // ----------------------------------------------------------------------
  void listenToIntakes() {
    emit(MedicineLoading());

    _intakeSubscription?.cancel();

    // 🔹 Now perfectly abstracting the stream from the repository layer
    _intakeSubscription = repository.streamIntakes().listen(
          (intakes) {
        emit(MedicineIntakesLoaded(intakes));
      },
      onError: (error) {
        emit(MedicineError(error.toString()));
      },
    );
  }

  // ----------------------------------------------------------------------
  // 🔹 CRUD LOGIC
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
      listenToMedicines();
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
      listenToMedicines();
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
      listenToMedicines();
    } catch (e, stackTrace) {
      print("🔥 FIRESTORE SAVE ERROR: $e");
      print("🔥 STACKTRACE: $stackTrace");
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      emit(MedicineError(errorMessage));
    }
  }

  @override
  Future<void> close() {
    _medicineSubscription?.cancel();
    _intakeSubscription?.cancel(); // 🔹 Ensure the intake stream is closed too
    return super.close();
  }
}