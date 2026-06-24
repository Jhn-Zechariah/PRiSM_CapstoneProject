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


  // Swapped FirebasePigRepo to PigRepo here for clean architecture
  PigCubit({required PigRepo pigRepo})
      : _pigRepo = pigRepo,
        super(PigInitial()) {
    _listenToAuthChanges();
  }


  // 👇 Method for the UI to call when the dropdown changes
  void changeFilter(String newFilter) {
    if (state is PigLoaded) {
      final currentState = state as PigLoaded;


      // Calculate the new filtered list
      final newFilteredPigs = _applyFilter(currentState.allPigs, newFilter);


      // Emit the updated state
      emit(PigLoaded(
        allPigs: currentState.allPigs,
        filteredPigs: newFilteredPigs,
        currentFilter: newFilter,
      ));
    }
  }


  // 👇 Apply the filter when new data arrives from Firebase
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
        // User logged in (or switched accounts), load THEIR pigs
        _loadPigs(user.uid);

        if (_pigRepo is FirebasePigRepo &&
            !_migrationCheckedUids.contains(user.uid)) {
          _migrationCheckedUids.add(user.uid);

          (_pigRepo).migrateCounterForUser(user.uid).catchError((_) {
            _migrationCheckedUids.remove(user.uid);
          });
        }
      } else {
        // User logged out, cancel the stream and reset the UI
        _pigSubscription?.cancel();
        emit(PigInitial());
      }
    });
  }


  // 👇 Helper logic to filter the list
  List<AppPig> _applyFilter(List<AppPig> pigs, String filter) {
    return pigs.where((pig) {
      final statusLower = pig.status.toLowerCase();
      final isInactive = statusLower == 'sold' || statusLower == 'deceased';
      return filter == 'Inactive' ? isInactive : !isInactive;
    }).toList();
  }


  String? _lastLoadedUid;


  void _loadPigs(String uid) {
    // 🔹 Optimization: Only start a new stream if the user has actually changed
    if (_lastLoadedUid == uid && _pigSubscription != null) return;


    _lastLoadedUid = uid;
    _pigSubscription?.cancel();


    emit(PigLoading());


    _pigSubscription = _pigRepo.streamPigs(uid).listen(
          (pigs) {
        _onPigsUpdated(pigs);
      },
      onError: (error) {
        emit(PigError("Failed to load pigs: $error"));
      },
    );
  }


  // add pig
  Future<void> addPig(AppPig pig) => _pigRepo.addPig(pig);


  // update pig info
  Future<void> updatePigDetails(AppPig updatedPig, {required double oldWeightKg}) async {
    try {
      await _pigRepo.updatePigProfile(updatedPig, oldWeightKg: oldWeightKg);
    } catch (e) {
      emit(PigError("Failed to update pig profile: $e"));
    }
  }


  // update weight
  Future<void> updateWeight(
      String pigId,
      double oldWeight,
      double newWeight,
      ) async {
    try {

      if (oldWeight == newWeight) {
        return;
      }

      await _pigRepo.updatePigWeight(
        pigId,
        newWeight,
      );

    } catch (e) {
      emit(PigError(
        "Failed to update weight: $e",
      ));
    }
  }


  @override
  Future<void> close() {
    // Always cancel subscriptions to prevent memory leaks!
    _pigSubscription?.cancel();
    _authSubscription?.cancel();
    return super.close();
  }
}