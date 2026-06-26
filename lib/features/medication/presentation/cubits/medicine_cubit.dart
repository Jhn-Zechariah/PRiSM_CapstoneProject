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
  final Map<String, List<MedicineStock>> _stockCache = {};

  List<Medicine> currentMedicines = [];

  StreamSubscription? _medicineSubscription;
  StreamSubscription? _intakeSubscription;
  StreamSubscription? _authSubscription; // 🔹 NEW

  String? _lastLoadedUid;
  String? _lastIntakeUid;

  MedicineCubit({required this.repository}) : super(MedicineInitial()) {
    _listenToAuthChanges(); // 🔹 NEW
  }

  // 🔹 NEW
  void _listenToAuthChanges() {
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      if (user != null) {
        listenToMedicines();
        listenToIntakes();
      } else {
        _medicineSubscription?.cancel();
        _medicineSubscription = null;
        _intakeSubscription?.cancel();
        _intakeSubscription = null;
        _lastLoadedUid = null;
        _lastIntakeUid = null;
        currentMedicines = [];
        _stockCache.clear();
        expiryCache.clear();
        emit(MedicineInitial());
      }
    });
  }

  void listenToMedicines() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    if (_lastLoadedUid == currentUser.uid && _medicineSubscription != null) return;

    _medicineSubscription?.cancel();
    _lastLoadedUid = currentUser.uid;

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

    _intakeSubscription?.cancel();
    _lastIntakeUid = currentUser.uid;

    _intakeSubscription = repository.streamIntakes(currentUser.uid).listen(
          (intakes) => emit(MedicineIntakesLoaded(intakes)),
      onError: (e) => emit(MedicineError(e.toString())),
    );
  }

  /// 🔹 NEW: Explicit trusted reload, called from AppNav on Authenticated.
  void forceReload(String uid) {
    _medicineSubscription?.cancel();
    _medicineSubscription = null;
    _lastLoadedUid = uid;

    _intakeSubscription?.cancel();
    _intakeSubscription = null;
    _lastIntakeUid = uid;

    emit(MedicineLoading());

    _medicineSubscription = repository.streamMedicines(uid).listen(
          (medicines) {
        currentMedicines = medicines;
        emit(MedicineLoaded(medicines));
      },
      onError: (e) => emit(MedicineError(e.toString())),
    );

    _intakeSubscription = repository.streamIntakes(uid).listen(
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
      _invalidateStockCache(medicineId);

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
    _authSubscription?.cancel(); // 🔹 NEW
    return super.close();
  }
}