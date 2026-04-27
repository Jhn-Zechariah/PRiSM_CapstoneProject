import '../../domain/models/app_pig.dart';


// --- STATES ---
abstract class PigState {}

class PigInitial extends PigState {}

class PigLoading extends PigState {}

class PigLoaded extends PigState {
  final List<AppPig> pigs;
  PigLoaded(this.pigs);
}

class PigError extends PigState {
  final String message;
  PigError(this.message);
}