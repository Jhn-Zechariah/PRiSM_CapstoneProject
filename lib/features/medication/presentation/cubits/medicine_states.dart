import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_intake.dart';

abstract class MedicineState {}

class MedicineInitial extends MedicineState {}

class MedicineLoading extends MedicineState {}

// Emitted for the real-time main dashboard view
class MedicineLoaded extends MedicineState {
  final List<Medicine> medicines;
  MedicineLoaded(this.medicines);
}

// Emitted when a dialog operation finishes successfully
class MedicineSaveSuccess extends MedicineState {}

class MedicineError extends MedicineState {
  final String message;
  MedicineError(this.message);
}

// Add this below your existing MedicineLoaded state
class MedicineIntakesLoaded extends MedicineState {
  final List<MedicineIntake> intakes;

  MedicineIntakesLoaded(this.intakes);
}