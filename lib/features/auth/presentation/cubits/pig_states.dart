import '../../domain/models/app_pig.dart';


// --- STATES ---
abstract class PigState {}

class PigInitial extends PigState {}

class PigLoading extends PigState {}

class PigLoaded extends PigState {
  final List<AppPig> allPigs;
  final List<AppPig> filteredPigs;
  final String currentFilter;
  PigLoaded({
    required this.allPigs,
    required this.filteredPigs,
    this.currentFilter = 'Active',
  });
}

class PigError extends PigState {
  final String message;
  PigError(this.message);
}