import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/pig_management/presentation/cubits/pig_states.dart';
import '../../domain/model/app_pig.dart';
import '../../domain/repo/pig_repo.dart';

class PigCubit extends Cubit<PigState> {
  final PigRepo _pigRepo;
  StreamSubscription? _pigSubscription;
  StreamSubscription? _authSubscription;
  String? _lastLoadedUid;

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

        if (!_migrationCheckedUids.contains(user.uid)) {
          _migrationCheckedUids.add(user.uid);

          _pigRepo.migrateCounterForUser(user.uid).catchError((_) {
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
    return pigs
        .where((pig) => filter == 'Inactive' ? pig.isInactive : !pig.isInactive)
        .toList();
  }

  /// Subscribes to the user's pigs. Skips the work when a healthy stream for
  /// the same uid is already live, so userChanges() and forceReload() firing
  /// together on login don't query Firestore twice.
  void _loadPigs(String uid) {
    if (_lastLoadedUid == uid &&
        _pigSubscription != null &&
        state is! PigError &&
        state is! PigInitial) {
      return;
    }

    _pigSubscription?.cancel();
    _lastLoadedUid = uid;

    emit(PigLoading());

    _pigSubscription = _pigRepo.streamPigs(uid).listen(
          (pigs) => _onPigsUpdated(pigs),
      onError: (error) => emit(PigError("Failed to load pigs: $error")),
    );
  }

  /// Called explicitly by AppNav when AuthCubit confirms a login, in case
  /// userChanges() misses an emission during rapid logout→login cycles.
  void forceReload(String uid) => _loadPigs(uid);

  Future<void> addPig(AppPig pig) => _pigRepo.addPig(pig);

  // Errors are rethrown to the caller instead of emitted, so a failed write
  // doesn't replace the loaded pig list with an error screen.
  Future<void> updatePigDetails(AppPig updatedPig, {required double oldWeightKg}) =>
      _pigRepo.updatePigProfile(updatedPig, oldWeightKg: oldWeightKg);

  Future<void> updateWeight(String pigId, double newWeight) =>
      _pigRepo.updatePigWeight(pigId, newWeight);

  @override
  Future<void> close() {
    _pigSubscription?.cancel();
    _authSubscription?.cancel();
    return super.close();
  }
}
