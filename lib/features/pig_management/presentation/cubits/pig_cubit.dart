import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/pig_management/presentation/cubits/pig_states.dart';
import '../../data/firestore_pig_repo.dart';
import '../../domain/model/app_pig.dart';
import '../../domain/repo/pig_repo.dart';

class PigCubit extends Cubit<PigState> {
  final PigRepo _pigRepo;
  StreamSubscription? _pigSubscription;
  StreamSubscription? _authSubscription;

  final Set<String> _migrationCheckedUids = {};

  PigCubit({required PigRepo pigRepo})
      : _pigRepo = pigRepo,
        super(PigInitial()) {
    _listenToAuthChanges();
  }

  void changeFilter(String newFilter) {
    if (state is PigLoaded) {
      final currentState = state as PigLoaded;
      final newFilteredPigs = _applyFilter(currentState.allPigs, newFilter);

      emit(PigLoaded(
        allPigs: currentState.allPigs,
        filteredPigs: newFilteredPigs,
        currentFilter: newFilter,
      ));
    }
  }

  void _onPigsUpdated(List<AppPig> newPigs) {
    final currentFilter = state is PigLoaded ? (state as PigLoaded).currentFilter : 'Active';
    final filtered = _applyFilter(newPigs, currentFilter);

    emit(PigLoaded(
      allPigs: newPigs,
      filteredPigs: filtered,
      currentFilter: currentFilter,
    ));
  }

  void _listenToAuthChanges() {
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      if (user != null) {
        _loadPigs(user.uid);

        if (_pigRepo is FirebasePigRepo &&
            !_migrationCheckedUids.contains(user.uid)) {
          _migrationCheckedUids.add(user.uid);

          (_pigRepo).migrateCounterForUser(user.uid).catchError((_) {
            _migrationCheckedUids.remove(user.uid);
          });
        }
      } else {
        // 🔹 FIX: reset the uid guard too, not just the subscription —
        // otherwise re-login (same account) can be skipped by _loadPigs's
        // dedupe check.
        _pigSubscription?.cancel();
        _pigSubscription = null;
        _lastLoadedUid = null;
        emit(PigInitial());
      }
    });
  }

  List<AppPig> _applyFilter(List<AppPig> pigs, String filter) {
    return pigs.where((pig) {
      final statusLower = pig.status.toLowerCase();
      final isInactive = statusLower == 'sold' || statusLower == 'deceased';
      return filter == 'Inactive' ? isInactive : !isInactive;
    }).toList();
  }

  String? _lastLoadedUid;

  void _loadPigs(String uid) {
    if (_lastLoadedUid == uid && _pigSubscription != null) return;

    _pigSubscription?.cancel();
    _lastLoadedUid = uid;

    emit(PigLoading());

    _pigSubscription = _pigRepo.streamPigs(uid).listen(
          (pigs) => _onPigsUpdated(pigs),
      onError: (error) => emit(PigError("Failed to load pigs: $error")),
    );
  }

  /// 🔹 NEW: Called explicitly by AppNav when AuthCubit confirms a login.
  /// Bypasses the uid-equality dedupe guard since this is a trusted,
  /// explicit signal — unlike userChanges(), which can miss emissions
  /// during rapid logout→login cycles without a full app restart.
  void forceReload(String uid) {
    _pigSubscription?.cancel();
    _pigSubscription = null;
    _lastLoadedUid = uid;

    emit(PigLoading());

    _pigSubscription = _pigRepo.streamPigs(uid).listen(
          (pigs) => _onPigsUpdated(pigs),
      onError: (error) => emit(PigError("Failed to load pigs: $error")),
    );
  }

  Future<void> addPig(AppPig pig) => _pigRepo.addPig(pig);

  Future<void> updatePigDetails(AppPig updatedPig, {required double oldWeightKg}) async {
    try {
      await _pigRepo.updatePigProfile(updatedPig, oldWeightKg: oldWeightKg);
    } catch (e) {
      emit(PigError("Failed to update pig profile: $e"));
    }
  }

  Future<void> updateWeight(String pigId, double oldWeight, double newWeight) async {
    try {
      if (oldWeight == newWeight) return;
      await _pigRepo.updatePigWeight(pigId, newWeight);
    } catch (e) {
      emit(PigError("Failed to update weight: $e"));
    }
  }

  @override
  Future<void> close() {
    _pigSubscription?.cancel();
    _authSubscription?.cancel();
    return super.close();
  }
}