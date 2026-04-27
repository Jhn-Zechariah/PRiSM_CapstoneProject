import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/auth/presentation/cubits/pig_states.dart';
import '../../domain/models/app_pig.dart';
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

  void _loadPigs(String uid) {
    // CRITICAL: Cancel the old stream if someone else was logged in previously!
    _pigSubscription?.cancel();

    emit(PigLoading());

    // Listen to the stream from your repo
    _pigSubscription = _pigRepo.streamPigs(uid).listen(
          (pigs) {
        emit(PigLoaded(pigs));
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