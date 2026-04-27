import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/auth/presentation/cubits/pig_states.dart';
import '../../domain/repo/pig_repo.dart';

class PigCubit extends Cubit<PigState> {
  final PigRepo _pigRepo;
  StreamSubscription? _pigSubscription;

  // Swapped FirebasePigRepo to PigRepo here for clean architecture
  PigCubit({required PigRepo pigRepo})
      : _pigRepo = pigRepo,
        super(PigInitial()) {
    // Start listening to the database as soon as the cubit is created
    _loadPigs();
  }

  void _loadPigs() {
    emit(PigLoading());

    // Listen to the stream from your repo
    _pigSubscription = _pigRepo.streamPigs().listen(
          (pigs) {
        emit(PigLoaded(pigs));
      },
      onError: (error) {
        emit(PigError("Failed to load pigs: $error"));
      },
    );
  }

  // 👇 ADDED THIS METHOD
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
    return super.close();
  }
}