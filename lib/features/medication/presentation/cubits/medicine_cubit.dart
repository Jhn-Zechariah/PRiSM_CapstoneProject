import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_intake.dart';
import '../../domain/model/app_medicine_stock.dart';
import '../../domain/repo/medicine_repo.dart';
import 'medicine_states.dart';

class MedicineCubit extends Cubit<MedicineState> {
  final MedicineRepository repository;
  final Map<String, String> expiryCache = {};

  // 🔹 New: cache of fetched stock batches, keyed by medicine id.
  final Map<String, List<MedicineStock>> _stockCache = {};

  List<Medicine> currentMedicines = [];

  StreamSubscription? _medicineSubscription;
  StreamSubscription? _intakeSubscription;

  String? _lastLoadedUid;
  String? _lastIntakeUid; // also fixes the earlier multi-user intake bug

  MedicineCubit({required this.repository}) : super(MedicineInitial());

  void listenToMedicines() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    if (_lastLoadedUid == currentUser.uid && _medicineSubscription != null) return;

    _lastLoadedUid = currentUser.uid;
    _medicineSubscription?.cancel();

    emit(MedicineLoading());

    _medicineSubscription = repository.streamMedicines(currentUser.uid).listen(
          (medicines) {
        currentMedicines = medicines;
        emit(MedicineLoaded(medicines));
      },
      onError: (e) => emit(MedicineError(e.toString())),
    );
  }

  void listenToIntakes() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    if (_lastIntakeUid == currentUser.uid && _intakeSubscription != null) return;

    _lastIntakeUid = currentUser.uid;
    _intakeSubscription?.cancel();

    _intakeSubscription = repository.streamIntakes(currentUser.uid).listen(
          (intakes) => emit(MedicineIntakesLoaded(intakes)),
      onError: (e) => emit(MedicineError(e.toString())),
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

  // 🔹 Now serves from cache when available — avoids a Firestore read
  // every time the same medicine is selected again in the dialog.
  Future<List<MedicineStock>> getStocksForMedicine(
      String medId, {
        bool forceRefresh = false,
      }) async {
    if (!forceRefresh && _stockCache.containsKey(medId)) {
      return _stockCache[medId]!;
    }
    try {
      final stocks = await repository.getMedicineStocks(medId);
      _stockCache[medId] = stocks;
      return stocks;
    } catch (e) {
      emit(MedicineError('Failed to load stock dates: $e'));
      return [];
    }
  }

  // 🔹 Single place to invalidate both caches whenever stock changes.
  void _invalidateStockCache(String? medId) {
    if (medId == null) return;
    expiryCache.remove(medId);
    _stockCache.remove(medId);
  }

  Future<void> updateMedicineItem({
    required Medicine medicine,
    required MedicineStock updatedStock,
    required String stockDocId,
    required double oldStockAmount,
  }) async {
    try {
      emit(MedicineLoading());
      _invalidateStockCache(medicine.medId);

      await repository.updateMedicineAndStock(
        medicine: medicine,
        updatedStock: updatedStock,
        stockDocId: stockDocId,
        oldStockAmount: oldStockAmount,
      );

      emit(MedicineSaveSuccess());
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
      _invalidateStockCache(medicine.medId);

      await repository.addNewStockBatch(
        medicine: medicine,
        newStock: newStock,
      );

      emit(MedicineSaveSuccess());
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
      _invalidateStockCache(medicineId); // 🔹 stock amount just changed too

      await repository.addIntakeAndReduceStock(
        intake: intake,
        selectedStock: selectedStock,
        medicineId: medicineId,
      );

      emit(MedicineSaveSuccess());
    } catch (e, stackTrace) {
      dev.log('Firestore save error: $e', name: 'MedicineCubit', error: e, stackTrace: stackTrace);
      final errorMessage = e.toString().replaceAll('Exception: ', '');
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