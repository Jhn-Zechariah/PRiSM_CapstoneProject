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
  final Map<String, List<MedicineStock>> _stockCache = {};

  StreamSubscription? _medicineSubscription;
  StreamSubscription? _intakeSubscription;
  StreamSubscription? _authSubscription;

  String? _uid;
  String? _intakeUid;

  // Expiry lookups only run once the stock page has asked for them, and
  // each medicine is fetched at most once at a time.
  bool _expiriesWanted = false;
  final Set<String> _expiriesInFlight = {};
  // Medicines written to while their expiry lookup was in flight; that
  // result may predate the write, so it is discarded and fetched again.
  final Set<String> _staleExpiries = {};

  MedicineCubit({required this.repository}) : super(const MedicineState()) {
    _listenToAuthChanges();
  }

  /// Strips the "Exception: " prefix so messages read cleanly in the UI.
  static String errorMessage(Object e) =>
      e.toString().replaceFirst('Exception: ', '');

  void _listenToAuthChanges() {
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      if (user != null) {
        _start(user.uid);
      } else {
        _medicineSubscription?.cancel();
        _medicineSubscription = null;
        _intakeSubscription?.cancel();
        _intakeSubscription = null;
        _uid = null;
        _intakeUid = null;
        _expiriesWanted = false;
        _expiriesInFlight.clear();
        _staleExpiries.clear();
        _stockCache.clear();
        emit(const MedicineState());
      }
    });
  }

  /// Subscribes to the user's medicines. Skips the work when a healthy
  /// stream for the same uid is already live, so userChanges() and
  /// forceReload() firing together on login don't query Firestore twice.
  void _start(String uid) {
    if (_uid == uid &&
        _medicineSubscription != null &&
        state.medicinesError == null) {
      return;
    }

    if (_uid != uid) {
      // Different account: drop everything from the previous one
      _intakeSubscription?.cancel();
      _intakeSubscription = null;
      _intakeUid = null;
      _stockCache.clear();
      _expiriesInFlight.clear();
      emit(const MedicineState());
    }

    _medicineSubscription?.cancel();
    _uid = uid;

    emit(state.copyWith(medicinesLoading: true, clearMedicinesError: true));

    _medicineSubscription = repository.streamMedicines(uid).listen(
      (medicines) {
        emit(state.copyWith(
          medicines: medicines,
          medicinesLoading: false,
          clearMedicinesError: true,
        ));
        if (_expiriesWanted) _loadMissingExpiries();
      },
      onError: (e) => emit(state.copyWith(
        medicinesLoading: false,
        medicinesError: e.toString(),
      )),
    );
  }

  /// Called explicitly by AppNav when AuthCubit confirms a login, in case
  /// userChanges() misses an emission during rapid logout→login cycles.
  void forceReload(String uid) => _start(uid);

  /// Starts the intake history stream. Called by the history page rather
  /// than on login, so sessions that never open history don't download
  /// every intake record.
  void listenToIntakes() {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_intakeUid == uid &&
        _intakeSubscription != null &&
        state.intakesError == null) {
      return;
    }

    _intakeSubscription?.cancel();
    _intakeUid = uid;

    emit(state.copyWith(intakesLoading: true, clearIntakesError: true));

    _intakeSubscription = repository.streamIntakes(uid).listen(
      (intakes) => emit(state.copyWith(
        intakes: intakes,
        intakesLoading: false,
        clearIntakesError: true,
      )),
      onError: (e) => emit(state.copyWith(
        intakesLoading: false,
        intakesError: e.toString(),
      )),
    );
  }

  // ── Expiry dates for the stock list ───────────────────────────────────────

  /// Called by the stock page; also keeps expiries current as medicines
  /// change from then on.
  void ensureExpiries() {
    _expiriesWanted = true;
    _loadMissingExpiries();
  }

  Future<void> _loadMissingExpiries() async {
    final ids = state.medicines
        .map((m) => m.medId ?? '')
        .where((id) =>
            id.isNotEmpty &&
            !state.nextExpiries.containsKey(id) &&
            !_expiriesInFlight.contains(id))
        .toList();
    if (ids.isEmpty) return;

    _expiriesInFlight.addAll(ids);
    // Fetched in parallel instead of one medicine after another
    final results = await Future.wait(ids.map((id) async {
      try {
        return MapEntry(id, await repository.getNearestExpiry(id));
      } catch (_) {
        return MapEntry(id, 'Error');
      }
    }));
    _expiriesInFlight.removeAll(ids);

    if (isClosed) return;
    final fresh =
        results.where((r) => !_staleExpiries.remove(r.key)).toList();
    emit(state.copyWith(
      nextExpiries: {...state.nextExpiries, ...Map.fromEntries(fresh)},
    ));
    if (fresh.length != results.length) _loadMissingExpiries();
  }

  void _invalidateStock(String? medId) {
    if (medId == null) return;
    _stockCache.remove(medId);
    if (_expiriesInFlight.contains(medId)) _staleExpiries.add(medId);
    if (state.nextExpiries.containsKey(medId)) {
      emit(state.copyWith(
        nextExpiries: Map.of(state.nextExpiries)..remove(medId),
      ));
    }
  }

  /// Clears cached stock data for [medId] after a write and re-fetches its
  /// expiry if the stock page is showing it.
  void _afterStockWrite(String? medId) {
    _invalidateStock(medId);
    if (_expiriesWanted) _loadMissingExpiries();
  }

  // ── Stocks ────────────────────────────────────────────────────────────────

  /// Throws on failure so the calling dialog can show the error.
  Future<List<MedicineStock>> getStocksForMedicine(
      String medId, {
        bool forceRefresh = false,
      }) async {
    if (!forceRefresh && _stockCache.containsKey(medId)) {
      return _stockCache[medId]!;
    }
    final stocks = await repository.getMedicineStocks(medId);
    _stockCache[medId] = stocks;
    return stocks;
  }

  Future<MedicineIntake?> getLastIntake(String pigId, String medName) =>
      repository.getLastIntake(pigId: pigId, medName: medName);

  // ── Writes ────────────────────────────────────────────────────────────────
  //
  // Each write throws on failure and is awaited by the dialog that started
  // it, so errors can't be lost when no screen is listening.

  Future<void> saveMedicineWithStock({
    required Medicine medicine,
    required MedicineStock initialBatch,
  }) async {
    await repository.addMedicineWithInitialStock(
      medicine: medicine,
      initialBatch: initialBatch,
    );
  }

  Future<void> updateMedicineItem({
    required Medicine medicine,
    required MedicineStock updatedStock,
    required String stockDocId,
    required double oldStockAmount,
  }) async {
    try {
      await repository.updateMedicineAndStock(
        medicine: medicine,
        updatedStock: updatedStock,
        stockDocId: stockDocId,
        oldStockAmount: oldStockAmount,
      );
    } finally {
      _afterStockWrite(medicine.medId);
    }
  }

  Future<void> addNewStockBatch({
    required Medicine medicine,
    required MedicineStock newStock,
  }) async {
    try {
      await repository.addNewStockBatch(
        medicine: medicine,
        newStock: newStock,
      );
    } finally {
      _afterStockWrite(medicine.medId);
    }
  }

  Future<void> addIntakeAndReduceStock({
    required MedicineIntake intake,
    required MedicineStock selectedStock,
    required String medicineId,
  }) async {
    try {
      await repository.addIntakeAndReduceStock(
        intake: intake,
        selectedStock: selectedStock,
        medicineId: medicineId,
      );
    } catch (e, stackTrace) {
      dev.log('Firestore save error: $e',
          name: 'MedicineCubit', error: e, stackTrace: stackTrace);
      rethrow;
    } finally {
      _afterStockWrite(medicineId);
    }
  }

  @override
  Future<void> close() {
    _medicineSubscription?.cancel();
    _intakeSubscription?.cancel();
    _authSubscription?.cancel();
    return super.close();
  }
}
