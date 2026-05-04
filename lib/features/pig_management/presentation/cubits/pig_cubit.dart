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

  // Swapped FirebasePigRepo to PigRepo here for clean architecture
  PigCubit({required PigRepo pigRepo})
      : _pigRepo = pigRepo,
        super(PigInitial()) {
    _listenToAuthChanges();
  }

  // 👇 2. Method for the UI to call when the dropdown changes
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

  // 👇 3. Make sure to apply the filter when new data arrives from Firebase!
  // (Wherever you listen to your stream in the Cubit, update it like this)
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
      } else {
        // User logged out, cancel the stream and reset the UI
        _pigSubscription?.cancel();
        emit(PigInitial());
      }
    });
  }

  // 👇 1. Helper logic to filter the list
  List<AppPig> _applyFilter(List<AppPig> pigs, String filter) {
    return pigs.where((pig) {
      final statusLower = pig.status.toLowerCase();
      final isInactive = statusLower == 'sold' || statusLower == 'deceased';
      return filter == 'Inactive' ? isInactive : !isInactive;
    }).toList();
  }

  void _loadPigs(String uid) {
    // CRITICAL: Cancel the old stream if someone else was logged in previously!
    _pigSubscription?.cancel();

    emit(PigLoading());

    // Listen to the stream from your repo
    _pigSubscription = _pigRepo.streamPigs(uid).listen(
          (pigs) {
        // 👇 INSTANT FIX: Pass the new pigs to our helper method!
        _onPigsUpdated(pigs);
      },
      onError: (error) {
        emit(PigError("Failed to load pigs: $error"));
      },
    );
  }

  //update pig info
  Future<void> updatePigDetails(AppPig updatedPig) async {
    try {
      await _pigRepo.updatePigProfile(updatedPig);
    } catch (e) {
      emit(PigError("Failed to update pig profile: $e"));
    }
  }

  // update weight
  Future<void> updateWeight(String pigId, double newWeight) async {
    try {
      await _pigRepo.updatePigWeight(pigId, newWeight);
      // We don't need to emit a state here!
      // The streamPigs() listener above will automatically see the
      // database change and emit a fresh PigLoaded state for you.
    } catch (e) {
      emit(PigError("Failed to update weight: $e"));
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